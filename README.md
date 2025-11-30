# PowerShell Security Automation Framework

A comprehensive, production-ready security automation framework for Windows systems built with PowerShell 7.0+.

Based on techniques from **PowerShell Automation and Scripting for Cybersecurity** (Packt Publishing).

## 📁 Framework Structure

```
PowerShell-Security-Framework/
├── SecurityFramework.psd1          # Module manifest
├── SecurityFramework.psm1          # Root module
├── modules/
│   ├── EventLogs.psm1              # PowerShell event log analysis
│   ├── Hardening.psm1              # System hardening functions
│   ├── Reconnaissance.psm1         # Security enumeration
│   ├── PatchManagement.psm1        # Update scanning
│   ├── JEAManagement.psm1          # Just Enough Administration
│   └── ThreatDetection.psm1        # Threat detection & AMSI
├── automation-scripts/
│   ├── forensics/                  # Forensic collection playbooks
│   ├── detection/                  # Threat detection playbooks
│   ├── hardening/                  # System hardening playbooks
│   ├── reconnaissance/             # Security enumeration playbooks
│   ├── monitoring/                 # Continuous monitoring playbooks
│   └── incident-response/          # IR automation playbooks
├── config/                         # Configuration files
├── tests/                          # Pester unit tests
└── docs/                           # Documentation
```

## 🚀 Quick Start

### Installation

```powershell
# Clone or download to a location
$frameworkPath = "C:\Path\To\PowerShell-Security-Framework"

# Import the module
Import-Module "$frameworkPath\SecurityFramework.psd1" -Force

# Verify loaded functions
Get-Command -Module SecurityFramework
```

### Basic Usage

```powershell
# Query PowerShell events
Get-AllPowerShellEvents -MaxEvents 100

# Extract executed script blocks
Get-ExecutedCode -SearchWord "Invoke-Expression"

# Enumerate local users and groups
Get-LocalUsersAndGroups | Where-Object { $_.GroupName -eq 'Administrators' }

# Check user rights assignments
Get-UserRightsAssignment | Where-Object { $_.RightName -like '*Debug*' }

# Scan for suspicious patterns
Find-SuspiciousScriptPatterns -MaxEvents 1000

# Test AMSI status
Test-AMSIStatus
```

## 📚 Modules

### EventLogs

- `Get-AllPowerShellEvents` - Query PowerShell events (IDs 200, 400, 500, 501, 600, 800, 4103-4106)
- `Get-ExecutedCode` - Extract and reconstruct executed script blocks with multi-part support

### Hardening

- `Enable-PSTranscription` - Enable PowerShell transcription logging
- `Enable-ScriptBlockLogging` - Enable script block logging (Event ID 4104)

### Reconnaissance

- `Get-LocalUsersAndGroups` - Enumerate local group memberships
- `Get-ADUsersAndGroups` - Enumerate AD groups (requires ActiveDirectory module)
- `Get-ADUsersAndGroupsWithAdsi` - Enumerate AD groups via ADSI (no module required)
- `Get-UserRightsAssignment` - Export and parse secedit privileges
- `Get-OuACLSecurity` - Enumerate OU ACLs
- `Get-GpoPermissions` - Enumerate GPO permissions
- `Get-CimNamespace` - Recursively enumerate WMI namespaces

### PatchManagement

- `Get-InstalledUpdates` - Parallel hotfix scanning across IP ranges
- `Test-MissingUpdates` - Offline WSUS scan for missing updates

### JEAManagement

- `Get-VirtualAccountLogons` - Monitor JEA virtual account sessions
- `New-JEAConfiguration` - Create JEA endpoint configurations
- `Get-JEAEndpoints` - List registered JEA endpoints

### ThreatDetection

- `Get-AMSIDetectionEvents` - Query AMSI detection events from Defender
- `Find-SuspiciousScriptPatterns` - Detect suspicious code patterns
- `Test-AMSIStatus` - Verify AMSI is functioning

## 🎯 Automation Playbooks

### Forensics

```powershell
# Run comprehensive security audit
.\automation-scripts\forensics\Invoke-SecurityAudit.ps1 -OutputPath "C:\Audits" -IncludeThreatScan
```

### Detection

```powershell
# Run threat detection scan
.\automation-scripts\detection\Invoke-ThreatDetection.ps1 -MaxEvents 5000
```

### Hardening

```powershell
# Preview hardening changes
.\automation-scripts\hardening\Invoke-SystemHardening.ps1 -WhatIf

# Apply hardening
.\automation-scripts\hardening\Invoke-SystemHardening.ps1 -Execute
```

### Reconnaissance

```powershell
# Security enumeration with AD
.\automation-scripts\reconnaissance\Invoke-SecurityRecon.ps1 -IncludeAD
```

### Monitoring

```powershell
# Patch audit across systems
.\automation-scripts\monitoring\Invoke-PatchAudit.ps1 -ComputerName "Server01","Server02"
```

### Incident Response

```powershell
# Automated incident triage
.\automation-scripts\incident-response\Invoke-IncidentResponse.ps1 -IncidentId "INC-2024-001"
```

## 🧪 Testing

```powershell
# Run all Pester tests
Invoke-Pester -Path ".\tests" -Output Detailed

# Run specific test file
Invoke-Pester -Path ".\tests\ThreatDetection.Tests.ps1"
```

## ⚠️ Requirements

- **PowerShell 7.0+** (recommended: 7.4+)
- **Windows 10/11 or Windows Server 2016+**
- **Administrative privileges** for most functions
- **Optional**: ActiveDirectory module for AD enumeration
- **Optional**: GroupPolicy module for GPO analysis

## 🔒 Security Considerations

- This framework contains detection patterns for educational purposes
- Some patterns (AMSI bypass, memory manipulation) are included for **detection reference only**
- Run in isolated/authorized environments only
- Follow your organization's security policies

## 📜 License

Based on techniques from **PowerShell Automation and Scripting for Cybersecurity** (Packt Publishing).

For educational and authorized security testing purposes only.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functions
4. Submit a pull request

---

**Built for Blue Teams** 🛡️
