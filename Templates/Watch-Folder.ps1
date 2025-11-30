#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    File system watcher template.

.DESCRIPTION
    Monitors a folder for changes (create, change, delete, rename).
    Logs events and optionally runs a handler script.
    Follows TPRS v1.1 and 40 Laws compliance.

.PARAMETER Path
    Folder path to watch.

.PARAMETER Filter
    File filter (e.g. *.txt). Default: *.*

.PARAMETER HandlerScript
    Optional .ps1 script to run when an event occurs.

.PARAMETER TimeoutSeconds
    How long to run before exiting. 0 = run until Ctrl+C.

.PARAMETER IncludeSubdirectories
    Whether to watch subdirectories. Default: $true

.OUTPUTS
    [void] - Runs until timeout or manual stop

.EXAMPLE
    .\Watch-Folder.ps1 -Path C:\Inbox -Filter "*.pdf"
    Watches for PDF files in the Inbox folder.

.EXAMPLE
    .\Watch-Folder.ps1 -Path C:\Inbox -HandlerScript .\Process-File.ps1 -TimeoutSeconds 3600
    Watches for 1 hour and runs handler on each event.

.NOTES
    Author: Kyle Thompson
    Version: 1.0.0
    Compliance: TPRS v1.1 | 40 Laws | Zero-Defect
#>

#region Module Constants

$script:LogPath = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
$script:LogFile = Join-Path -Path $script:LogPath -ChildPath 'watcher.log'

#endregion

#region Parameters

[CmdletBinding()]
[OutputType([void])]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$Path,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Filter = '*.*',

    [Parameter()]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) { return $true }
        Test-Path $_ -PathType Leaf
    })]
    [string]$HandlerScript,

    [Parameter()]
    [ValidateRange(0, 86400)]
    [int]$TimeoutSeconds = 0,

    [Parameter()]
    [bool]$IncludeSubdirectories = $true
)

#endregion

#region Private Functions

function Write-WatcherLog {
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

#endregion

#region Main Execution

# Create FileSystemWatcher
$fsw = [System.IO.FileSystemWatcher]::new()
$fsw.Path = (Resolve-Path $Path).Path
$fsw.Filter = $Filter
$fsw.IncludeSubdirectories = $IncludeSubdirectories
$fsw.EnableRaisingEvents = $true

Write-WatcherLog -Message "Watching '$($fsw.Path)' for '$Filter' changes..."

# Capture handler script path for use in action block
$handlerPath = $HandlerScript

# Event action script block
$eventAction = {
    param($sender, $eventArgs)

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # Safe property access with null checks
    $changeType = if ($null -ne $eventArgs.ChangeType) { $eventArgs.ChangeType.ToString() } else { 'Unknown' }
    $fileName = if (-not [string]::IsNullOrWhiteSpace($eventArgs.Name)) { $eventArgs.Name } else { 'Unknown' }
    $fullPath = if (-not [string]::IsNullOrWhiteSpace($eventArgs.FullPath)) { $eventArgs.FullPath } else { 'Unknown' }

    $msg = "[$timestamp] File event: ChangeType=$changeType; Name=$fileName; FullPath=$fullPath"

    # Write to console and log
    Write-Host $msg -ForegroundColor Cyan

    $logFile = Join-Path -Path $using:script:LogPath -ChildPath 'watcher.log'
    if (Test-Path (Split-Path $logFile)) {
        $msg | Out-File -FilePath $logFile -Append -Encoding UTF8
    }

    # Execute handler if specified (with null check - SIN #2 FIX)
    $handler = $using:handlerPath
    if (-not [string]::IsNullOrWhiteSpace($handler) -and (Test-Path $handler)) {
        try {
            & $handler -FullPath $fullPath -ChangeType $changeType
        }
        catch {
            $errMsg = "[$timestamp] [ERROR] HandlerScript error: $($_.Exception.Message)"
            Write-Host $errMsg -ForegroundColor Red
            if (Test-Path (Split-Path $logFile)) {
                $errMsg | Out-File -FilePath $logFile -Append -Encoding UTF8
            }
        }
    }
}

# Register events
$registrations = [System.Collections.Generic.List[System.Management.Automation.PSEventJob]]::new()

$registrations.Add((Register-ObjectEvent -InputObject $fsw -EventName Created -Action $eventAction))
$registrations.Add((Register-ObjectEvent -InputObject $fsw -EventName Changed -Action $eventAction))
$registrations.Add((Register-ObjectEvent -InputObject $fsw -EventName Deleted -Action $eventAction))
$registrations.Add((Register-ObjectEvent -InputObject $fsw -EventName Renamed -Action $eventAction))

Write-WatcherLog -Message "Registered 4 event handlers (Created, Changed, Deleted, Renamed)."

try {
    if ($TimeoutSeconds -gt 0) {
        Write-WatcherLog -Message "Watcher will run for $TimeoutSeconds second(s)..."
        Start-Sleep -Seconds $TimeoutSeconds
    }
    else {
        Write-WatcherLog -Message 'Press Ctrl+C to stop watching.'
        while ($true) {
            Start-Sleep -Seconds 5
        }
    }
}
finally {
    Write-WatcherLog -Message 'Stopping watcher and unregistering events.'

    foreach ($reg in $registrations) {
        if ($null -ne $reg) {
            Unregister-Event -SubscriptionId $reg.Id -ErrorAction SilentlyContinue
            Remove-Job -Job $reg -Force -ErrorAction SilentlyContinue
        }
    }

    $fsw.EnableRaisingEvents = $false
    $fsw.Dispose()

    Write-WatcherLog -Message 'Watcher stopped.'
}

#endregion
