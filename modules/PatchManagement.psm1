#Requires -Version 7.0
<#
.SYNOPSIS
    Patch Management module for update scanning and inventory.
.DESCRIPTION
    Provides functions for scanning installed updates, checking for missing
    patches across local and remote systems.
.NOTES
    Module: PatchManagement
    Author: PowerShell Security Framework
    Based on: PowerShell-Automation-and-Scripting-for-Cybersecurity (Packt)
#>

function Get-InstalledUpdates {
    <#
    .SYNOPSIS
        Retrieves installed updates across a range of IP addresses.
    .DESCRIPTION
        Uses background jobs to query Get-HotFix across multiple systems
        in parallel with configurable concurrency.
    .PARAMETER BaseIP
        Base IP address (e.g., "192.168.1").
    .PARAMETER MinIP
        Starting IP octet.
    .PARAMETER MaxIP
        Ending IP octet.
    .PARAMETER MaxJobs
        Maximum concurrent jobs. Default is 5.
    .EXAMPLE
        Get-InstalledUpdates -BaseIP "192.168.1" -MinIP 1 -MaxIP 10
    .EXAMPLE
        Get-InstalledUpdates -BaseIP "10.0.0" -MinIP 100 -MaxIP 110 -MaxJobs 10
    .OUTPUTS
        HotFix objects from queried systems
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}$')]
        [string]$BaseIP,

        [Parameter(Mandatory)]
        [ValidateRange(1, 254)]
        [int]$MinIP,

        [Parameter(Mandatory)]
        [ValidateRange(1, 254)]
        [int]$MaxIP,

        [Parameter()]
        [ValidateRange(1, 50)]
        [int]$MaxJobs = 5
    )

    # Build IP list
    $ipAddresses = $MinIP..$MaxIP | ForEach-Object { "$BaseIP.$_" }

    # Clean old jobs
    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue

    $scriptBlock = {
        param([string]$IpAddress)
        Get-HotFix -ComputerName $IpAddress -ErrorAction SilentlyContinue
    }

    foreach ($ip in $ipAddresses) {
        while ((Get-Job -State Running).Count -ge $MaxJobs) {
            Start-Sleep -Seconds 2
        }
        Write-Verbose "Starting job for $ip"
        Start-Job -ScriptBlock $scriptBlock -ArgumentList $ip | Out-Null
    }

    # Wait for completion
    while ((Get-Job -State Running).Count -gt 0) {
        Write-Verbose "Waiting for jobs to complete..."
        Start-Sleep -Seconds 3
    }

    # Collect results
    $results = Get-Job | ForEach-Object {
        Receive-Job -Job $_ -ErrorAction SilentlyContinue
        Remove-Job -Job $_
    }

    return $results
}

function Test-MissingUpdates {
    <#
    .SYNOPSIS
        Scans remote hosts for missing Windows updates.
    .DESCRIPTION
        Uses wsusscn2.cab offline scan to identify missing updates
        on local or remote systems.
    .PARAMETER ComputerName
        Target computer(s). Default is localhost.
    .PARAMETER CabPath
        Path to wsusscn2.cab file. Downloads if not present.
    .PARAMETER Force
        Force re-download of cab file.
    .EXAMPLE
        Test-MissingUpdates -ComputerName "Server01", "Server02"
    .EXAMPLE
        Test-MissingUpdates -Force
    .OUTPUTS
        PSCustomObject with ComputerName, MissingUpdates, UpdateTitles
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$ComputerName = @("localhost"),

        [Parameter()]
        [string]$CabPath = "$env:TEMP\wsusscn2.cab",

        [Parameter()]
        [switch]$Force
    )

    foreach ($computer in $ComputerName) {
        Write-Verbose "Scanning $computer for missing updates..."

        $scriptBlock = {
            param($CabPath, $Force)

            if ($Force -and (Test-Path -Path $CabPath)) {
                Remove-Item -Path $CabPath -Force
            }

            if (-not (Test-Path -Path $CabPath)) {
                $cabUrl = "http://go.microsoft.com/fwlink/?linkid=74689"
                Write-Verbose "Downloading wsusscn2.cab..."
                Invoke-WebRequest -Uri $cabUrl -OutFile $CabPath -UseBasicParsing
            }

            $UpdateSession = New-Object -ComObject Microsoft.Update.Session
            $UpdateServiceManager = New-Object -ComObject Microsoft.Update.ServiceManager
            $UpdateService = $UpdateServiceManager.AddScanPackageService("Offline Sync Service", $CabPath)
            $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
            $UpdateSearcher.ServerSelection = 3
            $UpdateSearcher.ServiceID = $UpdateService.ServiceID.ToString()

            $SearchResult = $UpdateSearcher.Search("IsInstalled=0")

            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                MissingCount = $SearchResult.Updates.Count
                Updates = $SearchResult.Updates | ForEach-Object { $_.Title }
            }
        }

        if ($computer -eq "localhost" -or $computer -eq $env:COMPUTERNAME) {
            & $scriptBlock -CabPath $CabPath -Force:$Force
        }
        else {
            $session = New-PSSession -ComputerName $computer -ErrorAction Stop
            try {
                Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $CabPath, $Force
            }
            finally {
                Remove-PSSession -Session $session
            }
        }
    }
}

Export-ModuleMember -Function Get-InstalledUpdates, Test-MissingUpdates
