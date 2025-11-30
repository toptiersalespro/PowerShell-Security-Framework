#Requires -Version 7.0
<#
.SYNOPSIS
    Patch management playbook for update inventory and compliance.
.DESCRIPTION
    Scans local and remote systems for installed patches and identifies
    potentially missing updates.
.PARAMETER ComputerName
    Target computer(s) to scan.
.PARAMETER IPRange
    IP range parameters for bulk scanning (BaseIP, MinIP, MaxIP).
.PARAMETER OutputPath
    Directory for scan results.
.EXAMPLE
    .\Invoke-PatchAudit.ps1
.EXAMPLE
    .\Invoke-PatchAudit.ps1 -ComputerName "Server01","Server02"
.NOTES
    Category: monitoring
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$ComputerName = @("localhost"),

    [Parameter()]
    [string]$OutputPath = "$env:TEMP\PatchAudit_$(Get-Date -Format 'yyyyMMddHHmmss')"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import framework
$frameworkPath = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
Import-Module (Join-Path -Path $frameworkPath -ChildPath 'SecurityFramework.psd1') -Force

Write-Host "=== Patch Audit Playbook ===" -ForegroundColor Cyan

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$auditResults = @{
    ScanTime = Get-Date
    Systems = [System.Collections.Generic.List[object]]::new()
}

foreach ($computer in $ComputerName) {
    Write-Host "`nScanning: $computer" -ForegroundColor Yellow

    $systemResult = @{
        ComputerName = $computer
        Hotfixes = @()
        Error = $null
    }

    try {
        $hotfixes = Get-HotFix -ComputerName $computer -ErrorAction Stop |
            Sort-Object -Property InstalledOn -Descending

        $systemResult.Hotfixes = $hotfixes
        $systemResult.HotfixCount = $hotfixes.Count
        $systemResult.LatestHotfix = $hotfixes | Select-Object -First 1

        Write-Host "  Found $($hotfixes.Count) installed updates" -ForegroundColor Green
        Write-Host "  Latest: $($systemResult.LatestHotfix.HotFixID) ($($systemResult.LatestHotfix.InstalledOn))" -ForegroundColor Gray

        # Export individual system report
        $hotfixes | Export-Csv -Path "$OutputPath\Hotfixes_$computer.csv" -NoTypeInformation
    }
    catch {
        Write-Warning "  Failed to scan: $_"
        $systemResult.Error = $_.Exception.Message
    }

    $auditResults.Systems.Add($systemResult)
}

# Summary report
$summary = $auditResults.Systems | ForEach-Object {
    [PSCustomObject]@{
        ComputerName = $_.ComputerName
        HotfixCount = $_.HotfixCount
        LatestHotfix = $_.LatestHotfix.HotFixID
        LatestDate = $_.LatestHotfix.InstalledOn
        Status = if ($_.Error) { "Error" } else { "OK" }
    }
}

$summary | Export-Csv -Path "$OutputPath\PatchAuditSummary.csv" -NoTypeInformation
$auditResults | ConvertTo-Json -Depth 5 | Set-Content -Path "$OutputPath\PatchAuditFull.json"

Write-Host "`n=== Patch Audit Summary ===" -ForegroundColor Cyan
$summary | Format-Table -AutoSize
Write-Host "Results: $OutputPath" -ForegroundColor Gray
