# EventLogs Module Documentation

## Overview

The EventLogs module provides functions for querying and analyzing PowerShell event logs for security monitoring and forensic analysis.

## Functions

### Get-AllPowerShellEvents

Queries relevant event IDs from all PowerShell-related event logs.

**Event IDs Covered:**

- **200, 400, 500, 501, 600, 800** - Windows PowerShell log
- **4103** - Module logging
- **4104** - Script block logging
- **4105, 4106** - Script block logging (start/stop)

**Parameters:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| MaxEvents | int | No | 1000 | Maximum events to return |

**Examples:**

```powershell
# Get last 100 PowerShell events
Get-AllPowerShellEvents -MaxEvents 100

# Get events and filter by ID
Get-AllPowerShellEvents | Where-Object { $_.Id -eq 4104 }

# Export to CSV
Get-AllPowerShellEvents -MaxEvents 5000 | Export-Csv -Path "PSEvents.csv"
```

---

### Get-ExecutedCode

Extracts executed PowerShell code from script block logging events (Event ID 4104).

**Key Features:**

- Handles multi-part script blocks (reconstructs large scripts)
- Filters by search word, user, level, or path
- Sorts by time for timeline analysis

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| SearchWord | string | No | Filter by keyword in code |
| UserId | string | No | Filter by executing user SID |
| Level | string | No | Filter by log level |
| Path | string | No | Filter by script path |

**Output Properties:**

- `TimeCreated` - When the code was executed
- `ExecutedCode` - The actual PowerShell code
- `UserId` - SID of the executing user
- `Level` - Log level (Information, Warning, etc.)
- `Path` - Path to the script file (if applicable)
- `ProviderName` - Event log provider
- `ScriptblockId` - Unique ID for the script block

**Examples:**

```powershell
# Find all code using Invoke-Expression
Get-ExecutedCode -SearchWord "Invoke-Expression"

# Find code executed by SYSTEM
Get-ExecutedCode -UserId "S-1-5-18"

# Find warning-level executions
Get-ExecutedCode -Level "Warning"

# Full forensic export
Get-ExecutedCode | Export-Csv -Path "ExecutedCode.csv" -NoTypeInformation
```

## Use Cases

### Threat Hunting

```powershell
# Look for download cradles
Get-ExecutedCode -SearchWord "DownloadString|Invoke-WebRequest|Net.WebClient"

# Look for encoded commands
Get-ExecutedCode -SearchWord "FromBase64String|-enc"

# Look for credential access
Get-ExecutedCode -SearchWord "Get-Credential|SecureString"
```

### Incident Timeline

```powershell
# Get all code execution in time order
Get-ExecutedCode |
    Sort-Object TimeCreated |
    Select-Object TimeCreated, UserId, @{N='CodePreview';E={$_.ExecutedCode.Substring(0,100)}}
```

### Compliance Auditing

```powershell
# Export all script executions for review
$code = Get-ExecutedCode
$code | Export-Csv -Path "ScriptAudit_$(Get-Date -Format 'yyyyMMdd').csv"
Write-Host "Exported $($code.Count) script blocks"
```
