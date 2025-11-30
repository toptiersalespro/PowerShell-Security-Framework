#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Backup a folder and rotate old backups.

.DESCRIPTION
    Creates timestamped backups of a source directory under a backup root.
    Keeps only the latest N backups and deletes older ones.
    Supports -WhatIf and -Confirm for safe operation.
    Follows TPRS v1.1 and 40 Laws compliance.

.PARAMETER SourcePath
    Directory to back up.

.PARAMETER BackupRoot
    Root backup directory.

.PARAMETER RetentionCount
    Number of backups to retain. Default: 7.

.PARAMETER ConfigFile
    Optional JSON config.

.OUTPUTS
    [PSCustomObject] - Backup operation result

.EXAMPLE
    .\Backup-Rotate.ps1 -SourcePath C:\Data -BackupRoot D:\Backups -WhatIf
    Shows what backup would be created without making changes.

.EXAMPLE
    .\Backup-Rotate.ps1 -SourcePath C:\Data -BackupRoot D:\Backups -RetentionCount 14
    Creates backup and keeps last 14 copies.

.NOTES
    Author: Kyle Thompson
    Version: 1.0.0
    Compliance: TPRS v1.1 | 40 Laws | Zero-Defect
#>

#region Module Constants

$script:LogPath = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
$script:LogFile = Join-Path -Path $script:LogPath -ChildPath 'backup.log'

#endregion

#region Parameters

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
[OutputType([PSCustomObject])]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$SourcePath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$BackupRoot,

    [Parameter()]
    [ValidateRange(1, 365)]
    [int]$RetentionCount = 7,

    [Parameter()]
    [string]$ConfigFile = '.\backup-config.json'
)

#endregion

#region Private Functions

function Write-BackupLog {
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

function Import-BackupConfig {
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
        Write-BackupLog -Message "Failed to parse config: $($_.Exception.Message)" -Level 'ERROR'
        return $null
    }
}

#endregion

#region Main Execution

# Merge config if present
$config = Import-BackupConfig -Path $ConfigFile
if ($config) {
    if (-not [string]::IsNullOrWhiteSpace($config.SourcePath)) { $SourcePath = $config.SourcePath }
    if (-not [string]::IsNullOrWhiteSpace($config.BackupRoot)) { $BackupRoot = $config.BackupRoot }
    if ($config.RetentionCount) { $RetentionCount = [int]$config.RetentionCount }
}

# Ensure backup root exists
if (-not (Test-Path $BackupRoot)) {
    Write-BackupLog -Message "BackupRoot does not exist. Creating: $BackupRoot"
    if ($PSCmdlet.ShouldProcess($BackupRoot, 'Create backup directory')) {
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupName = "Backup_$timestamp"
$backupPath = Join-Path -Path $BackupRoot -ChildPath $backupName

Write-BackupLog -Message "Creating backup: $backupPath"

# Create backup with ShouldProcess
$backupSuccess = $false
try {
    if ($PSCmdlet.ShouldProcess($SourcePath, "Backup to $backupPath")) {
        Copy-Item -Path $SourcePath -Destination $backupPath -Recurse -Force -ErrorAction Stop
        $backupSuccess = $true
        Write-BackupLog -Message 'Backup completed.'
    }
}
catch {
    Write-BackupLog -Message "Backup failed: $($_.Exception.Message)" -Level 'ERROR'
    exit 1
}

# Rotation with ShouldProcess
Write-BackupLog -Message "Applying retention: keep last $RetentionCount backups."

$backups = Get-ChildItem -Path $BackupRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'Backup_*' } |
    Sort-Object CreationTime -Descending

$removedCount = 0
if ($backups.Count -gt $RetentionCount) {
    $toRemove = $backups | Select-Object -Skip $RetentionCount

    foreach ($old in $toRemove) {
        if ($PSCmdlet.ShouldProcess($old.FullName, 'Remove old backup')) {
            Write-BackupLog -Message "Removing old backup: $($old.FullName)" -Level 'WARN'
            Remove-Item -Path $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
            $removedCount++
        }
    }
}
else {
    Write-BackupLog -Message 'No old backups to remove.'
}

# Return result object
[PSCustomObject]@{
    Timestamp      = Get-Date
    SourcePath     = $SourcePath
    BackupPath     = $backupPath
    Success        = $backupSuccess
    BackupsRemoved = $removedCount
    BackupsKept    = [Math]::Min($backups.Count, $RetentionCount)
}

#endregion
