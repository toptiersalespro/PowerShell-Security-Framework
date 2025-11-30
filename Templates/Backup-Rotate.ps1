#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-TemplateLog {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO',

        [Parameter()]
        [string]$LogFile = '.\logs\backup.log'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "$timestamp [$Level] $Message"

    switch ($Level) {
        'INFO'  { Write-Information -MessageData $entry -InformationAction Continue }
        'WARN'  { Write-Warning -Message $entry }
        'ERROR' { Write-Warning -Message "[ERROR] $entry" }
    }

    $logDir = Split-Path -Path $LogFile -Parent
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        $null = New-Item -ItemType Directory -Path $logDir -Force
    }

    $entry | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Import-Config {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$LogFile = '.\logs\backup.log'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-TemplateLog -Message "Config file not found at path: $Path" -Level 'WARN' -LogFile $LogFile
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-TemplateLog -Message "Config file at $Path is empty." -Level 'WARN' -LogFile $LogFile
            return $null
        }
        return $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-TemplateLog -Message "Failed to parse config at $Path. $_" -Level 'ERROR' -LogFile $LogFile
        return $null
    }
}

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true)]
    [string]$BackupRoot,

    [Parameter()]
    [int]$RetentionCount = 7,

    [Parameter()]
    [string]$ConfigFile = '.\backup-config.json'
)

$logFile = '.\logs\backup.log'

$config = Import-Config -Path $ConfigFile -LogFile $logFile
if ($config) {
    if ($config.SourcePath)     { $SourcePath     = $config.SourcePath }
    if ($config.BackupRoot)     { $BackupRoot     = $config.BackupRoot }
    if ($config.RetentionCount) { $RetentionCount = [int]$config.RetentionCount }
}

if (-not (Test-Path -LiteralPath $SourcePath)) {
    Write-TemplateLog -Message "SourcePath does not exist: $SourcePath" -Level 'ERROR' -LogFile $logFile
    exit 1
}

if (-not (Test-Path -LiteralPath $BackupRoot)) {
    Write-TemplateLog -Message "BackupRoot does not exist. Creating: $BackupRoot" -LogFile $logFile
    $null = New-Item -ItemType Directory -Path $BackupRoot -Force
}

$timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupName = "Backup_$timestamp"
$backupPath = Join-Path -Path $BackupRoot -ChildPath $backupName

Write-TemplateLog -Message "Creating backup at: $backupPath" -LogFile $logFile

try {
    if ($PSCmdlet.ShouldProcess($backupPath, "Copy from source '$SourcePath'")) {
        Copy-Item -Path $SourcePath -Destination $backupPath -Recurse -Force -ErrorAction Stop
        Write-TemplateLog -Message 'Backup completed.' -LogFile $logFile
    } else {
        Write-TemplateLog -Message 'Backup skipped by ShouldProcess/WhatIf.' -Level 'WARN' -LogFile $logFile
    }
}
catch {
    Write-TemplateLog -Message "Backup failed: $_" -Level 'ERROR' -LogFile $logFile
    exit 1
}

Write-TemplateLog -Message "Applying retention policy: keep last $RetentionCount backups." -LogFile $logFile

$backups = Get-ChildItem -Path $BackupRoot -Directory |
           Where-Object { $_.Name -like 'Backup_*' } |
           Sort-Object CreationTime -Descending

if ($backups.Count -gt $RetentionCount) {
    $toRemove = $backups | Select-Object -Skip $RetentionCount
    foreach ($old in $toRemove) {
        if ($PSCmdlet.ShouldProcess($old.FullName, 'Remove old backup')) {
            Write-TemplateLog -Message "Removing old backup: $($old.FullName)" -Level 'WARN' -LogFile $logFile
            Remove-Item -Path $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-TemplateLog -Message 'No old backups to remove.' -LogFile $logFile
}
