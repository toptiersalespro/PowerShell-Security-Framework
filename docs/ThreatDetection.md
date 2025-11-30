# Threat Detection Module Documentation

## Overview

The ThreatDetection module provides functions for identifying malicious PowerShell activity, AMSI bypass attempts, and suspicious code patterns.

## Functions

### Find-SuspiciousScriptPatterns

Scans script block logs for patterns commonly associated with malicious activity.

**Detection Patterns:**

| Pattern Name        | Risk Level | Description                  |
| ------------------- | ---------- | ---------------------------- |
| Base64 Decode       | Medium     | `FromBase64String` usage     |
| Download Cradle     | High       | Web requests/downloads       |
| Invoke-Expression   | High       | Dynamic code execution       |
| AMSI Reference      | Critical   | AMSI DLL/function references |
| Reflection          | High       | .NET reflection usage        |
| Credential Access   | Medium     | Credential harvesting        |
| Memory Manipulation | Critical   | VirtualProtect, VirtualAlloc |
| Mimikatz Indicators | Critical   | Known mimikatz strings       |
| Encoded Command     | High       | -enc/-EncodedCommand usage   |
| Hidden Window       | Medium     | Hidden window execution      |

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| MaxEvents | int | 500 | Maximum events to analyze |

**Output Properties:**

- `TimeCreated` - When detected
- `PatternName` - Name of matched pattern
- `RiskLevel` - Critical/High/Medium/Low
- `MatchedPattern` - Regex that matched
- `UserId` - Executing user
- `CodeSnippet` - First 200 chars of code

**Examples:**

```powershell
# Basic scan
Find-SuspiciousScriptPatterns

# Deep scan
Find-SuspiciousScriptPatterns -MaxEvents 5000

# Filter critical only
Find-SuspiciousScriptPatterns | Where-Object { $_.RiskLevel -eq 'Critical' }

# Export findings
Find-SuspiciousScriptPatterns | Export-Csv -Path "ThreatFindings.csv"
```

---

### Get-AMSIDetectionEvents

Retrieves AMSI (Antimalware Scan Interface) detection events from Windows Defender.

**Event Source:** Microsoft-Windows-Windows Defender/Operational (Event ID 1116)

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| MaxEvents | int | 100 | Maximum events to return |

**Examples:**

```powershell
# Get recent AMSI detections
Get-AMSIDetectionEvents

# Get last 500 detections
Get-AMSIDetectionEvents -MaxEvents 500 | Format-List
```

---

### Test-AMSIStatus

Verifies that AMSI is functioning correctly by checking provider registration.

**Output Properties:**

- `AMSIEnabled` - Boolean status
- `TestResult` - Status message
- `Details` - Additional information
- `Timestamp` - When checked

**Examples:**

```powershell
# Check AMSI status
Test-AMSIStatus

# Alert if AMSI disabled
$status = Test-AMSIStatus
if (-not $status.AMSIEnabled) {
    Write-Warning "AMSI may be compromised!"
}
```

## Threat Hunting Workflows

### Daily Threat Scan

```powershell
# Morning threat check
$threats = Find-SuspiciousScriptPatterns -MaxEvents 2000
$critical = $threats | Where-Object { $_.RiskLevel -eq 'Critical' }

if ($critical) {
    Write-Host "ALERT: $($critical.Count) critical findings!" -ForegroundColor Red
    $critical | Format-Table TimeCreated, PatternName, CodeSnippet
}
```

### AMSI Monitoring

```powershell
# Check for AMSI bypass attempts
$amsiPatterns = Find-SuspiciousScriptPatterns |
    Where-Object { $_.PatternName -eq 'AMSI Reference' }

if ($amsiPatterns) {
    Write-Host "Potential AMSI bypass attempts detected!" -ForegroundColor Red
    $amsiPatterns | Select-Object TimeCreated, UserId, CodeSnippet
}
```

### Incident Investigation

```powershell
# Deep dive on suspicious activity
$allFindings = Find-SuspiciousScriptPatterns -MaxEvents 10000

# Group by risk
$allFindings | Group-Object RiskLevel |
    Select-Object Name, Count |
    Sort-Object @{E={switch($_.Name){'Critical'{1}'High'{2}'Medium'{3}default{4}}}}

# Timeline view
$allFindings |
    Sort-Object TimeCreated |
    Select-Object TimeCreated, RiskLevel, PatternName |
    Format-Table
```
