#Requires -Version 7.0
<#
.SYNOPSIS
    PowerShell Security Framework CLI Runner.
.DESCRIPTION
    Command-line interface for running framework operations.
.PARAMETER Action
    The action to perform.
.PARAMETER OutputPath
    Output directory for results.
.EXAMPLE
    .\framework.ps1 -Action Audit
.EXAMPLE
    .\framework.ps1 -Action Detect -OutputPath "C:\Results"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Audit', 'Detect', 'Harden', 'Recon', 'Patch', 'IR', 'Test', 'Help')]
    [string]$Action,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$Execute,

    [Parameter()]
    [string]$IncidentId
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot

# Import framework
Import-Module (Join-Path -Path $scriptRoot -ChildPath 'SecurityFramework.psd1') -Force

function Show-Help {
    Write-Host @"

╔═══════════════════════════════════════════════════════════════╗
║         POWERSHELL SECURITY FRAMEWORK v1.0.0                  ║
╚═══════════════════════════════════════════════════════════════╝

USAGE:
    .\framework.ps1 -Action <Action> [Options]

ACTIONS:
    Audit    - Run comprehensive security audit (forensics)
    Detect   - Run threat detection scan
    Harden   - Apply system hardening (-Execute to apply)
    Recon    - Security reconnaissance and enumeration
    Patch    - Patch compliance audit
    IR       - Incident response playbook
    Test     - Run Pester tests
    Help     - Show this help message

OPTIONS:
    -OutputPath <path>   - Custom output directory
    -Execute             - Apply changes (for Harden action)
    -IncidentId <id>     - Custom incident ID (for IR action)

EXAMPLES:
    .\framework.ps1 -Action Audit
    .\framework.ps1 -Action Detect -OutputPath "C:\Scans"
    .\framework.ps1 -Action Harden -Execute
    .\framework.ps1 -Action IR -IncidentId "INC-001"
    .\framework.ps1 -Action Test

MODULES:
    EventLogs        - PowerShell event analysis
    Hardening        - System hardening
    Reconnaissance   - Security enumeration
    PatchManagement  - Update scanning
    JEAManagement    - Just Enough Administration
    ThreatDetection  - Threat detection & AMSI

"@ -ForegroundColor Cyan
}

switch ($Action) {
    'Audit' {
        $script = Join-Path -Path $scriptRoot -ChildPath 'automation-scripts\forensics\Invoke-SecurityAudit.ps1'
        $params = @{ IncludeThreatScan = $true }
        if ($OutputPath) { $params['OutputPath'] = $OutputPath }
        & $script @params
    }
    'Detect' {
        $script = Join-Path -Path $scriptRoot -ChildPath 'automation-scripts\detection\Invoke-ThreatDetection.ps1'
        $params = @{}
        if ($OutputPath) { $params['OutputPath'] = $OutputPath }
        & $script @params
    }
    'Harden' {
        $script = Join-Path -Path $scriptRoot -ChildPath 'automation-scripts\hardening\Invoke-SystemHardening.ps1'
        $params = @{ Execute = $Execute }
        & $script @params
    }
    'Recon' {
        $script = Join-Path -Path $scriptRoot -ChildPath 'automation-scripts\reconnaissance\Invoke-SecurityRecon.ps1'
        $params = @{ IncludeAD = $true }
        if ($OutputPath) { $params['OutputPath'] = $OutputPath }
        & $script @params
    }
    'Patch' {
        $script = Join-Path -Path $scriptRoot -ChildPath 'automation-scripts\monitoring\Invoke-PatchAudit.ps1'
        $params = @{}
        if ($OutputPath) { $params['OutputPath'] = $OutputPath }
        & $script @params
    }
    'IR' {
        $script = Join-Path -Path $scriptRoot -ChildPath 'automation-scripts\incident-response\Invoke-IncidentResponse.ps1'
        $params = @{}
        if ($OutputPath) { $params['OutputPath'] = $OutputPath }
        if ($IncidentId) { $params['IncidentId'] = $IncidentId }
        & $script @params
    }
    'Test' {
        $testsPath = Join-Path -Path $scriptRoot -ChildPath 'tests'
        if (Get-Module -ListAvailable -Name Pester) {
            Invoke-Pester -Path $testsPath -Output Detailed
        } else {
            Write-Warning "Pester module not installed. Run: Install-Module Pester -Force"
        }
    }
    'Help' {
        Show-Help
    }
}
