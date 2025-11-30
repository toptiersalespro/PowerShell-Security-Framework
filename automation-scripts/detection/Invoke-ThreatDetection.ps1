#Requires -Version 7.0
# cspell:ignore AMSI amsi Mimikatz sekurlsa
<#
.SYNOPSIS
    Detection playbook for identifying malicious PowerShell activity.
.DESCRIPTION
    Analyzes PowerShell event logs for suspicious patterns, AMSI bypass
    attempts, and known malicious indicators.
.PARAMETER OutputPath
    Directory for detection results.
.PARAMETER MaxEvents
    Maximum events to analyze.
.PARAMETER AlertOnly
    Only output alerts, suppress informational messages.
.EXAMPLE
    .\Invoke-ThreatDetection.ps1
.EXAMPLE
    .\Invoke-ThreatDetection.ps1 -MaxEvents 5000 -OutputPath "C:\Alerts"
.NOTES
    Category: detection
    Requires: Administrative privileges
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath = "$env:TEMP\ThreatDetection_$(Get-Date -Format 'yyyyMMddHHmmss')",

    [Parameter()]
    [int]$MaxEvents = 2000,

    [Parameter()]
    [switch]$AlertOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import framework
$frameworkPath = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
Import-Module (Join-Path -Path $frameworkPath -ChildPath 'SecurityFramework.psd1') -Force

# Helper function for styled console output (PSScriptAnalyzer compliant)
function Write-ThreatLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Header', 'DarkWarning')]
        [string]$Level = 'Info'
    )

    $styledMsg = switch ($Level) {
        'Info'        { "$($PSStyle.Foreground.BrightBlack)$Message$($PSStyle.Reset)" }
        'Warning'     { "$($PSStyle.Foreground.Yellow)$Message$($PSStyle.Reset)" }
        'Error'       { "$($PSStyle.Foreground.Red)$Message$($PSStyle.Reset)" }
        'Success'     { "$($PSStyle.Foreground.Green)$Message$($PSStyle.Reset)" }
        'Header'      { "$($PSStyle.Foreground.Cyan)$Message$($PSStyle.Reset)" }
        'DarkWarning' { "$($PSStyle.Foreground.FromRgb(255,140,0))$Message$($PSStyle.Reset)" }
    }

    Write-Information -MessageData $styledMsg -InformationAction Continue
}

if (-not $AlertOnly) {
    Write-ThreatLog -Message "=== Threat Detection Playbook ===" -Level Header
    Write-ThreatLog -Message "Analyzing up to $MaxEvents events..." -Level Info
}

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$detectionResults = @{
    ScanTime     = Get-Date
    ComputerName = $env:COMPUTERNAME
    Findings     = [System.Collections.Generic.List[object]]::new()
}

# Check AMSI Status
if (-not $AlertOnly) { Write-ThreatLog -Message "`n[1/3] Checking AMSI Status..." -Level Warning }
$amsiStatus = Test-AMSIStatus
$detectionResults.AMSIStatus = $amsiStatus

if (-not $amsiStatus.AMSIEnabled) {
    $finding = [PSCustomObject]@{
        Category  = "AMSI"
        Severity  = "Critical"
        Finding   = "AMSI appears to be disabled or bypassed"
        Details   = $amsiStatus.Details
        Timestamp = Get-Date
    }
    $detectionResults.Findings.Add($finding)
    Write-ThreatLog -Message "  [CRITICAL] AMSI may be compromised!" -Level Error
}
else {
    if (-not $AlertOnly) { Write-ThreatLog -Message "  AMSI is active" -Level Success }
}

# Check AMSI Detection Events
if (-not $AlertOnly) { Write-ThreatLog -Message "`n[2/3] Checking AMSI Detection History..." -Level Warning }
try {
    $amsiDetections = Get-AMSIDetectionEvents -MaxEvents 100
    if ($amsiDetections.Count -gt 0) {
        foreach ($detection in $amsiDetections) {
            $finding = [PSCustomObject]@{
                Category  = "AMSI Detection"
                Severity  = "High"
                Finding   = "Malware detected by AMSI"
                Details   = $detection.ThreatName
                Timestamp = $detection.TimeCreated
            }
            $detectionResults.Findings.Add($finding)
        }
        Write-ThreatLog -Message "  [ALERT] $($amsiDetections.Count) AMSI detections found!" -Level Error
        $amsiDetections | Export-Csv -Path "$OutputPath\AMSIDetections.csv" -NoTypeInformation
    }
    else {
        if (-not $AlertOnly) { Write-ThreatLog -Message "  No AMSI detections" -Level Success }
    }
}
catch {
    if (-not $AlertOnly) { Write-Warning "  Could not query AMSI events: $_" }
}

# Scan for Suspicious Patterns
if (-not $AlertOnly) { Write-ThreatLog -Message "`n[3/3] Scanning Script Block Logs..." -Level Warning }
try {
    $suspiciousPatterns = Find-SuspiciousScriptPatterns -MaxEvents $MaxEvents

    $critical = @($suspiciousPatterns | Where-Object { $_.RiskLevel -eq 'Critical' })
    $high     = @($suspiciousPatterns | Where-Object { $_.RiskLevel -eq 'High' })
    $medium   = @($suspiciousPatterns | Where-Object { $_.RiskLevel -eq 'Medium' })

    foreach ($pattern in $suspiciousPatterns) {
        $finding = [PSCustomObject]@{
            Category  = "Suspicious Pattern"
            Severity  = $pattern.RiskLevel
            Finding   = $pattern.PatternName
            Details   = $pattern.CodeSnippet
            Timestamp = $pattern.TimeCreated
        }
        $detectionResults.Findings.Add($finding)
    }

    if ($critical.Count -gt 0) {
        Write-ThreatLog -Message "  [CRITICAL] $($critical.Count) critical patterns found!" -Level Error
        foreach ($c in $critical | Select-Object -First 5) {
            Write-ThreatLog -Message "    - $($c.PatternName) at $($c.TimeCreated)" -Level Error
        }
    }
    if ($high.Count -gt 0) {
        Write-ThreatLog -Message "  [HIGH] $($high.Count) high-risk patterns found" -Level Warning
    }
    if ($medium.Count -gt 0) {
        Write-ThreatLog -Message "  [MEDIUM] $($medium.Count) medium-risk patterns found" -Level DarkWarning
    }
    if ($suspiciousPatterns.Count -eq 0) {
        if (-not $AlertOnly) { Write-ThreatLog -Message "  No suspicious patterns detected" -Level Success }
    }

    if ($suspiciousPatterns.Count -gt 0) {
        $suspiciousPatterns | Export-Csv -Path "$OutputPath\SuspiciousPatterns.csv" -NoTypeInformation
    }
}
catch {
    if (-not $AlertOnly) { Write-Warning "  Pattern scan failed: $_" }
}

# Save results
$detectionResults | ConvertTo-Json -Depth 5 | Set-Content -Path "$OutputPath\DetectionResults.json"

# Summary
if (-not $AlertOnly) {
    Write-ThreatLog -Message "`n=== Detection Summary ===" -Level Header
    $summaryLevel = if ($detectionResults.Findings.Count -gt 0) { 'Warning' } else { 'Success' }
    Write-ThreatLog -Message "Total Findings: $($detectionResults.Findings.Count)" -Level $summaryLevel
    Write-ThreatLog -Message "Results: $OutputPath" -Level Info
}

# Return findings for pipeline
$detectionResults.Findings
