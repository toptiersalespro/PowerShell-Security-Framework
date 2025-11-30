#Requires -Version 7.0
<#
.SYNOPSIS
    Hardening playbook for securing Windows systems.
.DESCRIPTION
    Applies security hardening configurations including PowerShell logging,
    script block logging, and other defensive measures.
.PARAMETER EnableTranscription
    Enable PowerShell transcription logging.
.PARAMETER EnableScriptBlockLogging
    Enable script block logging (Event ID 4104).
.PARAMETER TranscriptPath
    Path for transcript files.
.PARAMETER Execute
    Apply changes. Without this flag, runs in dry-run mode.
.EXAMPLE
    .\Invoke-SystemHardening.ps1 -WhatIf
.EXAMPLE
    .\Invoke-SystemHardening.ps1 -Execute
.NOTES
    Category: hardening
    Requires: Administrative privileges
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [switch]$EnableTranscription = $true,

    [Parameter()]
    [switch]$EnableScriptBlockLogging = $true,

    [Parameter()]
    [string]$TranscriptPath = "C:\ProgramData\WindowsPowerShell\Transcripts",

    [Parameter()]
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import framework
$frameworkPath = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
Import-Module (Join-Path -Path $frameworkPath -ChildPath 'SecurityFramework.psd1') -Force

Write-Host "=== System Hardening Playbook ===" -ForegroundColor Cyan

if (-not $Execute) {
    Write-Warning "DRY RUN MODE: Use -Execute to apply changes"
}

$results = [System.Collections.Generic.List[PSCustomObject]]::new()

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script requires administrative privileges."
    return
}

# Hardening 1: PowerShell Transcription
if ($EnableTranscription) {
    Write-Host "`n[1/2] Configuring PowerShell Transcription..." -ForegroundColor Yellow

    if ($Execute) {
        try {
            $result = Enable-PSTranscription -OutputDirectory $TranscriptPath
            $results.Add([PSCustomObject]@{
                Setting = "PowerShell Transcription"
                Status = "Enabled"
                Details = "Output: $TranscriptPath"
            })
            Write-Host "  Transcription enabled: $TranscriptPath" -ForegroundColor Green
        }
        catch {
            Write-Error "  Failed to enable transcription: $_"
            $results.Add([PSCustomObject]@{ Setting = "PowerShell Transcription"; Status = "Failed"; Details = $_.Exception.Message })
        }
    }
    else {
        Write-Host "  Would enable transcription to: $TranscriptPath" -ForegroundColor Gray
        $results.Add([PSCustomObject]@{ Setting = "PowerShell Transcription"; Status = "Planned"; Details = "Dry run" })
    }
}

# Hardening 2: Script Block Logging
if ($EnableScriptBlockLogging) {
    Write-Host "`n[2/2] Configuring Script Block Logging..." -ForegroundColor Yellow

    if ($Execute) {
        try {
            $result = Enable-ScriptBlockLogging
            $results.Add([PSCustomObject]@{
                Setting = "Script Block Logging"
                Status = "Enabled"
                Details = "Event ID 4104"
            })
            Write-Host "  Script block logging enabled" -ForegroundColor Green
        }
        catch {
            Write-Error "  Failed to enable script block logging: $_"
            $results.Add([PSCustomObject]@{ Setting = "Script Block Logging"; Status = "Failed"; Details = $_.Exception.Message })
        }
    }
    else {
        Write-Host "  Would enable script block logging (Event ID 4104)" -ForegroundColor Gray
        $results.Add([PSCustomObject]@{ Setting = "Script Block Logging"; Status = "Planned"; Details = "Dry run" })
    }
}

# Summary
Write-Host "`n=== Hardening Summary ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

if (-not $Execute) {
    Write-Host "`nRun with -Execute to apply these changes." -ForegroundColor Yellow
}

return $results
