#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Parallel worker template for bulk processing.

.DESCRIPTION
    Reads a list of items and processes them concurrently with robust logging and result aggregation.
    Uses PowerShell 7+ ForEach-Object -Parallel for optimal performance.
    Follows TPRS v1.1 and 40 Laws compliance.

.PARAMETER InputFile
    File with one work item per line (e.g. computer names).

.PARAMETER ThrottleLimit
    Max degree of parallelism. Default: 10.

.PARAMETER ConfigFile
    Optional JSON config.

.OUTPUTS
    [PSCustomObject[]] - Array of processing results

.EXAMPLE
    .\Invoke-ParallelProcess.ps1 -InputFile .\hosts.txt -ThrottleLimit 20
    Processes all hosts in parallel with 20 concurrent threads.

.NOTES
    Author: Kyle Thompson
    Version: 1.0.0
    Compliance: TPRS v1.1 | 40 Laws | Zero-Defect
#>

#region Module Constants

$script:LogPath = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
$script:LogFile = Join-Path -Path $script:LogPath -ChildPath 'parallel.log'

#endregion

#region Parameters

[CmdletBinding()]
[OutputType([PSCustomObject[]])]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$InputFile,

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$ThrottleLimit = 10,

    [Parameter()]
    [string]$ConfigFile = '.\parallel-config.json'
)

#endregion

#region Private Functions

function Write-ParallelLog {
    <#
    .SYNOPSIS
        Writes structured log entries.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "$timestamp [$Level] $Message"

    if (-not (Test-Path $script:LogPath)) {
        New-Item -ItemType Directory -Path $script:LogPath -Force | Out-Null
    }

    $entry | Out-File -FilePath $script:LogFile -Append -Encoding UTF8

    switch ($Level) {
        'INFO'  { Write-Verbose $entry }
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Error $Message }
    }
}

function Import-ParallelConfig {
    <#
    .SYNOPSIS
        Imports and validates configuration.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    try {
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) {
            return $null
        }
        return $content | ConvertFrom-Json
    }
    catch {
        Write-ParallelLog -Message "Failed to parse config: $($_.Exception.Message)" -Level 'ERROR'
        return $null
    }
}

#endregion

#region Main Execution

# Load config (optional)
$config = Import-ParallelConfig -Path $ConfigFile

# Read input items with null-safe filtering
$rawItems = Get-Content -Path $InputFile -ErrorAction Stop

# SIN #2 FIX: Safe null check before Trim
$items = $rawItems | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_)
} | ForEach-Object {
    $_.Trim()
}

if ($items.Count -eq 0) {
    Write-ParallelLog -Message 'No valid items found in input file.' -Level 'WARN'
    exit 0
}

Write-ParallelLog -Message "Loaded $($items.Count) items. Starting parallel processing with throttle $ThrottleLimit..."

# Parallel processing block
$results = $items | ForEach-Object -Parallel {
    $item = $_
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # Example work: ping test (customize as needed)
    $reachable = $false
    $errorMsg = $null

    try {
        $ping = Test-Connection -ComputerName $item -Count 1 -Quiet -ErrorAction Stop
        $reachable = [bool]$ping
    }
    catch {
        $reachable = $false
        $errorMsg = $_.Exception.Message
    }

    # Return typed result object
    [PSCustomObject]@{
        Timestamp = $timestamp
        Target    = $item
        Reachable = $reachable
        Error     = $errorMsg
    }
} -ThrottleLimit $ThrottleLimit

Write-ParallelLog -Message 'Parallel work complete. Writing results...'

# SIN #3 FIX: Consistent return handling
if ($null -eq $results -or $results.Count -eq 0) {
    Write-ParallelLog -Message 'No results produced.' -Level 'WARN'
    # Return empty typed array, not @()
    return [PSCustomObject[]]@()
}

$outFile = Join-Path -Path $PSScriptRoot -ChildPath 'parallel-results.csv'
$results | Sort-Object Target | Export-Csv -Path $outFile -NoTypeInformation
Write-ParallelLog -Message "Results written to $outFile"

# Output for pipeline
$results

#endregion
