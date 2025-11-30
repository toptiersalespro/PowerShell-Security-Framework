#Requires -Version 7.0
<#
.SYNOPSIS
    EventLogs module for querying PowerShell security events.
.DESCRIPTION
    Provides functions for querying PowerShell event logs, extracting executed
    script blocks, and supporting forensic analysis of PowerShell activity.
.NOTES
    Module: EventLogs
    Author: PowerShell Security Framework
    Based on: PowerShell-Automation-and-Scripting-for-Cybersecurity (Packt)
#>

function Get-AllPowerShellEvents {
    <#
    .SYNOPSIS
        Queries relevant event IDs from all PowerShell-related event logs.
    .DESCRIPTION
        Queries event IDs 200, 400, 500, 501, 600, 800, 4103, 4104, 4105, and 4106
        from Microsoft-Windows-PowerShell/Operational, PowerShellCore/Operational,
        and Windows PowerShell event logs.
    .PARAMETER MaxEvents
        Maximum number of events to return. Default is 1000.
    .EXAMPLE
        Get-AllPowerShellEvents | Select-Object -First 10
    .EXAMPLE
        Get-AllPowerShellEvents -MaxEvents 500 | Where-Object { $_.Id -eq 4104 }
    .OUTPUTS
        System.Diagnostics.Eventing.Reader.EventLogRecord
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(1, 100000)]
        [int]$MaxEvents = 1000
    )

    $xml = @'
<QueryList>
    <Query Id="0" Path="Microsoft-Windows-PowerShell/Operational">
        <Select Path="Microsoft-Windows-PowerShell/Operational">*[System[(EventID=4103 or EventID=4104 or EventID=4105 or EventID=4106)]]</Select>
        <Select Path="PowerShellCore/Operational">*[System[(EventID=4103 or EventID=4104 or EventID=4105 or EventID=4106)]]</Select>
        <Select Path="Windows PowerShell">*[System[(EventID=200 or EventID=400 or EventID=500 or EventID=501 or EventID=600 or EventID=800)]]</Select>
    </Query>
</QueryList>
'@

    try {
        Get-WinEvent -FilterXml $xml -MaxEvents $MaxEvents -ErrorAction Stop
    } catch {
        if ($_.Exception.Message -match 'No events were found') {
            Write-Warning "No PowerShell events found matching the criteria."
            return @()
        }
        Write-Error "Failed to query events: $($_.Exception.Message)"
        throw
    }
}

function Get-ExecutedCode {
    <#
    .SYNOPSIS
        Extracts executed PowerShell code from script block logging events.
    .DESCRIPTION
        Queries EventLog for script block logging events (ID 4104) and reconstructs
        executed code, including multi-part script blocks.
    .PARAMETER SearchWord
        Filter events containing this keyword in the executed code.
    .PARAMETER UserId
        Filter events by the executing user's SID.
    .PARAMETER Level
        Filter events by log level.
    .PARAMETER Path
        Filter events where code was executed from this path.
    .EXAMPLE
        Get-ExecutedCode -SearchWord "Invoke-Expression"
    .EXAMPLE
        Get-ExecutedCode -UserId "S-1-5-18"
    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$SearchWord,
        [Parameter()][string]$UserId,
        [Parameter()][string]$Level,
        [Parameter()][string]$Path
    )

    $PSWinEventLog = @{ ProviderName = "Microsoft-Windows-PowerShell"; Id = 4104 }
    $PSCoreEventLog = @{ ProviderName = "PowerShellCore"; Id = 4104 }

    try {
        $AllEvents = Get-WinEvent -FilterHashtable $PSWinEventLog, $PSCoreEventLog -ErrorAction Stop |
            Sort-Object @{Expression = { $_.Properties[3].Value } }, @{Expression = { $_.Properties[0].Value } } |
            ForEach-Object {
                [PSCustomObject]@{
                    TimeCreated   = $_.TimeCreated
                    ExecutedCode  = $_.Properties[2].Value
                    UserId        = $_.UserId
                    Level         = $_.LevelDisplayName
                    Path          = $_.Properties[4].Value
                    ProviderName  = $_.ProviderName
                    ScriptblockId = $_.Properties[3].Value
                    IsMultiPart   = $_.Properties[1].Value -ne 1
                    CurrentPart   = $_.Properties[0].Value
                    TotalParts    = $_.Properties[1].Value
                }
            }
    } catch {
        if ($_.Exception.Message -match 'No events were found') {
            Write-Warning "No script block logging events found."
            return @()
        }
        throw
    }

    $oldScriptBlockId = ""
    $CodeEvents = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Process multi-part events
    $AllEvents | Where-Object { $_.IsMultiPart } | ForEach-Object {
        if ($oldScriptBlockId -ne $_.ScriptblockId) {
            $ScriptBlockCode = $_.ExecutedCode
            $oldScriptBlockId = $_.ScriptblockId
        } else { $ScriptBlockCode += $_.ExecutedCode }
        if ($_.CurrentPart -eq $_.TotalParts) {
            $CodeEvents.Add([PSCustomObject]@{
                    TimeCreated = $_.TimeCreated; ExecutedCode = $ScriptBlockCode
                    UserId = $_.UserId; Level = $_.Level; Path = $_.Path
                    ProviderName = $_.ProviderName; ScriptblockId = $_.ScriptblockId
                })
        }
    }

    # Process single-part events
    $AllEvents | Where-Object { -not $_.IsMultiPart } | ForEach-Object {
        $CodeEvents.Add([PSCustomObject]@{
                TimeCreated = $_.TimeCreated; ExecutedCode = $_.ExecutedCode
                UserId = $_.UserId; Level = $_.Level; Path = $_.Path
                ProviderName = $_.ProviderName; ScriptblockId = $_.ScriptblockId
            })
    }

    $CodeEvents = $CodeEvents | Sort-Object TimeCreated

    if ($SearchWord) { $CodeEvents = $CodeEvents | Where-Object { $_.ExecutedCode -match $SearchWord } }
    if ($UserId) { $CodeEvents = $CodeEvents | Where-Object { $_.UserId -eq $UserId } }
    if ($Level) { $CodeEvents = $CodeEvents | Where-Object { $_.Level -eq $Level } }
    if ($Path) { $CodeEvents = $CodeEvents | Where-Object { $_.Path -like "$Path*" } }

    return $CodeEvents
}

Export-ModuleMember -Function Get-AllPowerShellEvents, Get-ExecutedCode
