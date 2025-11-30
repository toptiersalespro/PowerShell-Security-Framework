#Requires -Version 7.0
<#
.SYNOPSIS
    Incident response playbook for rapid triage.
.DESCRIPTION
    Automated incident response workflow that collects forensic data,
    identifies threats, and generates an incident report.
.PARAMETER IncidentId
    Unique identifier for the incident.
.PARAMETER OutputPath
    Directory for incident artifacts.
.PARAMETER CollectMemory
    Collect memory-related artifacts (requires admin).
.EXAMPLE
    .\Invoke-IncidentResponse.ps1 -IncidentId "INC-2024-001"
.EXAMPLE
    .\Invoke-IncidentResponse.ps1 -CollectMemory
.NOTES
    Category: incident-response
    Requires: Administrative privileges
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$IncidentId = "IR-$(Get-Date -Format 'yyyyMMdd-HHmmss')",

    [Parameter()]
    [string]$OutputPath = "$env:USERPROFILE\IncidentResponse\$IncidentId",

    [Parameter()]
    [switch]$CollectMemory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Import framework
$frameworkPath = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
Import-Module (Join-Path -Path $frameworkPath -ChildPath 'SecurityFramework.psd1') -Force

Write-Host @"
╔═══════════════════════════════════════════════╗
║       INCIDENT RESPONSE PLAYBOOK              ║
║       Incident ID: $($IncidentId.PadRight(24))║
╚═══════════════════════════════════════════════╝
"@ -ForegroundColor Red

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$irReport = @{
    IncidentId = $IncidentId
    StartTime = Get-Date
    ComputerName = $env:COMPUTERNAME
    Username = $env:USERNAME
    Domain = $env:USERDOMAIN
    Sections = [ordered]@{}
}

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Phase 1: System State Snapshot
Write-Host "`n[PHASE 1] Capturing System State..." -ForegroundColor Cyan
$irReport.Sections['SystemState'] = @{
    Hostname = $env:COMPUTERNAME
    OSVersion = [System.Environment]::OSVersion.VersionString
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    Uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    CurrentProcesses = (Get-Process).Count
    NetworkConnections = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue).Count
}
Write-Host "  System: $($irReport.Sections.SystemState.Hostname)" -ForegroundColor Gray
Write-Host "  Processes: $($irReport.Sections.SystemState.CurrentProcesses)" -ForegroundColor Gray
Write-Host "  Active Connections: $($irReport.Sections.SystemState.NetworkConnections)" -ForegroundColor Gray

# Phase 2: PowerShell Activity
Write-Host "`n[PHASE 2] Analyzing PowerShell Activity..." -ForegroundColor Cyan
try {
    $events = Get-AllPowerShellEvents -MaxEvents 1000
    $codeBlocks = Get-ExecutedCode

    $irReport.Sections['PowerShellActivity'] = @{
        TotalEvents = $events.Count
        ScriptBlocks = $codeBlocks.Count
        UniqueUsers = @($events | Select-Object -ExpandProperty UserId -Unique).Count
    }

    $events | Export-Csv -Path "$OutputPath\PowerShellEvents.csv" -NoTypeInformation
    $codeBlocks | Export-Csv -Path "$OutputPath\ExecutedCode.csv" -NoTypeInformation

    Write-Host "  Events: $($events.Count)" -ForegroundColor Gray
    Write-Host "  Script blocks: $($codeBlocks.Count)" -ForegroundColor Gray
}
catch {
    Write-Warning "  PowerShell analysis failed: $_"
    $irReport.Sections['PowerShellActivity'] = @{ Error = $_.Exception.Message }
}

# Phase 3: Threat Detection
Write-Host "`n[PHASE 3] Running Threat Detection..." -ForegroundColor Cyan
try {
    $threats = Find-SuspiciousScriptPatterns -MaxEvents 2000
    $critical = @($threats | Where-Object { $_.RiskLevel -eq 'Critical' })
    $high = @($threats | Where-Object { $_.RiskLevel -eq 'High' })

    $irReport.Sections['ThreatDetection'] = @{
        TotalFindings = $threats.Count
        Critical = $critical.Count
        High = $high.Count
    }

    if ($threats.Count -gt 0) {
        $threats | Export-Csv -Path "$OutputPath\ThreatFindings.csv" -NoTypeInformation
    }

    if ($critical.Count -gt 0) {
        Write-Host "  [CRITICAL] $($critical.Count) critical threats detected!" -ForegroundColor Red
        foreach ($c in $critical | Select-Object -First 3) {
            Write-Host "    - $($c.PatternName)" -ForegroundColor Red
        }
    }
    elseif ($high.Count -gt 0) {
        Write-Host "  [HIGH] $($high.Count) high-risk patterns found" -ForegroundColor Yellow
    }
    else {
        Write-Host "  No critical threats detected" -ForegroundColor Green
    }
}
catch {
    Write-Warning "  Threat detection failed: $_"
    $irReport.Sections['ThreatDetection'] = @{ Error = $_.Exception.Message }
}

# Phase 4: User/Privilege Analysis
Write-Host "`n[PHASE 4] Analyzing Users and Privileges..." -ForegroundColor Cyan
try {
    $localUsers = Get-LocalUsersAndGroups
    $admins = @($localUsers | Where-Object { $_.GroupName -eq 'Administrators' })

    $irReport.Sections['UserAnalysis'] = @{
        LocalGroupMemberships = $localUsers.Count
        AdministratorCount = $admins.Count
        Administrators = $admins | Select-Object -ExpandProperty Name
    }

    $localUsers | Export-Csv -Path "$OutputPath\LocalUsers.csv" -NoTypeInformation

    Write-Host "  Admin accounts: $($admins.Count)" -ForegroundColor Gray
}
catch {
    Write-Warning "  User analysis failed: $_"
}

# Phase 5: Network Connections
Write-Host "`n[PHASE 5] Capturing Network State..." -ForegroundColor Cyan
try {
    $connections = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, OwningProcess,
            @{N='ProcessName';E={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}}

    $irReport.Sections['NetworkState'] = @{
        EstablishedConnections = $connections.Count
        UniqueRemoteAddresses = @($connections | Select-Object -ExpandProperty RemoteAddress -Unique).Count
    }

    $connections | Export-Csv -Path "$OutputPath\NetworkConnections.csv" -NoTypeInformation
    Write-Host "  Active connections: $($connections.Count)" -ForegroundColor Gray
}
catch {
    Write-Warning "  Network capture failed: $_"
}

# Phase 6: Running Processes
Write-Host "`n[PHASE 6] Capturing Process List..." -ForegroundColor Cyan
try {
    $processes = Get-Process | Select-Object Id, ProcessName, Path, StartTime, CPU,
        @{N='CommandLine';E={(Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine}}

    $processes | Export-Csv -Path "$OutputPath\ProcessList.csv" -NoTypeInformation
    $irReport.Sections['Processes'] = @{ Count = $processes.Count }
    Write-Host "  Processes captured: $($processes.Count)" -ForegroundColor Gray
}
catch {
    Write-Warning "  Process capture failed: $_"
}

# Finalize Report
$stopwatch.Stop()
$irReport.EndTime = Get-Date
$irReport.Duration = $stopwatch.Elapsed.ToString()

# Generate HTML Report
$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Incident Response Report - $IncidentId</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; margin: 40px; background: #1a1a2e; color: #eee; }
        h1 { color: #ff6b6b; border-bottom: 2px solid #ff6b6b; padding-bottom: 10px; }
        h2 { color: #4ecdc4; margin-top: 30px; }
        .section { background: #16213e; padding: 20px; margin: 20px 0; border-radius: 8px; }
        .critical { color: #ff6b6b; font-weight: bold; }
        .high { color: #feca57; }
        .info { color: #54a0ff; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #0f3460; }
        th { background: #0f3460; }
        .timestamp { color: #888; font-size: 0.9em; }
    </style>
</head>
<body>
    <h1>🔴 INCIDENT RESPONSE REPORT</h1>
    <p class="timestamp">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>

    <div class="section">
        <h2>📋 Incident Summary</h2>
        <table>
            <tr><th>Incident ID</th><td>$IncidentId</td></tr>
            <tr><th>Computer</th><td>$($irReport.ComputerName)</td></tr>
            <tr><th>User</th><td>$($irReport.Domain)\$($irReport.Username)</td></tr>
            <tr><th>Duration</th><td>$($irReport.Duration)</td></tr>
        </table>
    </div>

    <div class="section">
        <h2>⚠️ Threat Summary</h2>
        <p class="critical">Critical Findings: $($irReport.Sections.ThreatDetection.Critical)</p>
        <p class="high">High Risk Findings: $($irReport.Sections.ThreatDetection.High)</p>
    </div>

    <div class="section">
        <h2>📁 Artifacts Collected</h2>
        <ul>
            <li>PowerShell Events: $($irReport.Sections.PowerShellActivity.TotalEvents)</li>
            <li>Script Blocks: $($irReport.Sections.PowerShellActivity.ScriptBlocks)</li>
            <li>Network Connections: $($irReport.Sections.NetworkState.EstablishedConnections)</li>
            <li>Processes: $($irReport.Sections.Processes.Count)</li>
        </ul>
    </div>

    <div class="section">
        <h2>📂 Output Location</h2>
        <p><code>$OutputPath</code></p>
    </div>
</body>
</html>
"@

$htmlReport | Set-Content -Path "$OutputPath\IncidentReport.html"
$irReport | ConvertTo-Json -Depth 5 | Set-Content -Path "$OutputPath\IncidentReport.json"

Write-Host @"

╔═══════════════════════════════════════════════╗
║       INCIDENT RESPONSE COMPLETE              ║
╚═══════════════════════════════════════════════╝
"@ -ForegroundColor Green

Write-Host "Duration: $($irReport.Duration)" -ForegroundColor Gray
Write-Host "Artifacts: $OutputPath" -ForegroundColor Cyan
Write-Host "Report: $OutputPath\IncidentReport.html" -ForegroundColor Cyan

# Return summary
[PSCustomObject]@{
    IncidentId = $IncidentId
    CriticalFindings = $irReport.Sections.ThreatDetection.Critical
    HighFindings = $irReport.Sections.ThreatDetection.High
    OutputPath = $OutputPath
}
