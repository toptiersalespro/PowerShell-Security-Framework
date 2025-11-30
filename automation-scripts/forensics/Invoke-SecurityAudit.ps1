#Requires -Version 7.0
<#
.SYNOPSIS
    Security audit playbook for collecting forensic data.
.DESCRIPTION
    Comprehensive security audit that collects event logs, user information,
    privilege assignments, and suspicious activity indicators.
.PARAMETER OutputPath
    Directory for audit output files.
.PARAMETER IncludeThreatScan
    Include threat detection scan.
.EXAMPLE
    .\Invoke-SecurityAudit.ps1 -OutputPath "C:\Audits"
.EXAMPLE
    .\Invoke-SecurityAudit.ps1 -IncludeThreatScan
.NOTES
    Category: forensics
    Requires: Administrative privileges
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath = "$env:USERPROFILE\SecurityAudits\$(Get-Date -Format 'yyyyMMdd_HHmmss')",

    [Parameter()]
    [switch]$IncludeThreatScan
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import framework
$frameworkPath = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
Import-Module (Join-Path -Path $frameworkPath -ChildPath 'SecurityFramework.psd1') -Force

# Initialize
Write-Host "=== PowerShell Security Audit ===" -ForegroundColor Cyan
Write-Host "Output: $OutputPath" -ForegroundColor Gray

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$auditResults = @{
    AuditTime = Get-Date
    ComputerName = $env:COMPUTERNAME
    Sections = @{}
}

# Section 1: PowerShell Events
Write-Host "`n[1/5] Collecting PowerShell Events..." -ForegroundColor Yellow
try {
    $events = Get-AllPowerShellEvents -MaxEvents 500
    $auditResults.Sections['PowerShellEvents'] = @{
        Count = $events.Count
        EventTypes = $events | Group-Object -Property Id | ForEach-Object { @{ Id = $_.Name; Count = $_.Count } }
    }
    $events | Export-Csv -Path "$OutputPath\PowerShellEvents.csv" -NoTypeInformation
    Write-Host "  Collected $($events.Count) events" -ForegroundColor Green
}
catch {
    Write-Warning "  Failed to collect events: $_"
    $auditResults.Sections['PowerShellEvents'] = @{ Error = $_.Exception.Message }
}

# Section 2: Executed Code
Write-Host "`n[2/5] Extracting Executed Code..." -ForegroundColor Yellow
try {
    $code = Get-ExecutedCode
    $auditResults.Sections['ExecutedCode'] = @{ Count = $code.Count }
    $code | Export-Csv -Path "$OutputPath\ExecutedCode.csv" -NoTypeInformation
    Write-Host "  Extracted $($code.Count) script blocks" -ForegroundColor Green
}
catch {
    Write-Warning "  Failed to extract code: $_"
    $auditResults.Sections['ExecutedCode'] = @{ Error = $_.Exception.Message }
}

# Section 3: Local Users and Groups
Write-Host "`n[3/5] Enumerating Local Users/Groups..." -ForegroundColor Yellow
try {
    $localUsers = Get-LocalUsersAndGroups
    $auditResults.Sections['LocalUsers'] = @{ Count = $localUsers.Count }
    $localUsers | Export-Csv -Path "$OutputPath\LocalUsersAndGroups.csv" -NoTypeInformation
    Write-Host "  Found $($localUsers.Count) membership entries" -ForegroundColor Green
}
catch {
    Write-Warning "  Failed to enumerate users: $_"
    $auditResults.Sections['LocalUsers'] = @{ Error = $_.Exception.Message }
}

# Section 4: User Rights Assignment
Write-Host "`n[4/5] Checking User Rights..." -ForegroundColor Yellow
try {
    $rights = Get-UserRightsAssignment
    $auditResults.Sections['UserRights'] = @{ Count = $rights.Count }
    $rights | Export-Csv -Path "$OutputPath\UserRightsAssignment.csv" -NoTypeInformation
    Write-Host "  Found $($rights.Count) privilege assignments" -ForegroundColor Green
}
catch {
    Write-Warning "  Failed to check rights: $_"
    $auditResults.Sections['UserRights'] = @{ Error = $_.Exception.Message }
}

# Section 5: Threat Scan (optional)
if ($IncludeThreatScan) {
    Write-Host "`n[5/5] Running Threat Detection Scan..." -ForegroundColor Yellow
    try {
        $threats = Find-SuspiciousScriptPatterns -MaxEvents 1000
        $auditResults.Sections['ThreatScan'] = @{
            Count = $threats.Count
            Critical = @($threats | Where-Object { $_.RiskLevel -eq 'Critical' }).Count
            High = @($threats | Where-Object { $_.RiskLevel -eq 'High' }).Count
        }
        $threats | Export-Csv -Path "$OutputPath\SuspiciousPatterns.csv" -NoTypeInformation
        Write-Host "  Found $($threats.Count) suspicious patterns" -ForegroundColor $(if ($threats.Count -gt 0) { 'Red' } else { 'Green' })
    }
    catch {
        Write-Warning "  Threat scan failed: $_"
        $auditResults.Sections['ThreatScan'] = @{ Error = $_.Exception.Message }
    }
}
else {
    Write-Host "`n[5/5] Threat Scan skipped (use -IncludeThreatScan to enable)" -ForegroundColor Gray
}

# Generate summary
$auditResults | ConvertTo-Json -Depth 5 | Set-Content -Path "$OutputPath\AuditSummary.json"

Write-Host "`n=== Audit Complete ===" -ForegroundColor Cyan
Write-Host "Results saved to: $OutputPath" -ForegroundColor Green
