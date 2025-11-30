#Requires -Version 7.0
<#
.SYNOPSIS
    PowerShell Security Framework - Module Manifest
.DESCRIPTION
    Main module manifest that loads all security framework modules.
.NOTES
    Framework: PowerShell Security Automation Framework
    Based on: PowerShell-Automation-and-Scripting-for-Cybersecurity (Packt)
#>

@{
    RootModule = 'SecurityFramework.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'PowerShell Security Framework'
    Description = 'Comprehensive PowerShell Security Automation Framework for detection, hardening, and incident response.'

    PowerShellVersion = '7.0'

    NestedModules = @(
        'modules\EventLogs.psm1',
        'modules\Hardening.psm1',
        'modules\Reconnaissance.psm1',
        'modules\PatchManagement.psm1',
        'modules\JEAManagement.psm1',
        'modules\ThreatDetection.psm1'
    )

    FunctionsToExport = @(
        # EventLogs
        'Get-AllPowerShellEvents',
        'Get-ExecutedCode',
        # Hardening
        'Enable-PSTranscription',
        'Enable-ScriptBlockLogging',
        # Reconnaissance
        'Get-LocalUsersAndGroups',
        'Get-ADUsersAndGroups',
        'Get-ADUsersAndGroupsWithAdsi',
        'Get-UserRightsAssignment',
        'Get-OuACLSecurity',
        'Get-GpoPermissions',
        'Get-CimNamespace',
        # PatchManagement
        'Get-InstalledUpdates',
        'Test-MissingUpdates',
        # JEAManagement
        'Get-VirtualAccountLogons',
        'New-JEAConfiguration',
        'Get-JEAEndpoints',
        # ThreatDetection
        'Get-AMSIDetectionEvents',
        'Find-SuspiciousScriptPatterns',
        'Test-AMSIStatus'
    )

    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @('Security', 'Forensics', 'Hardening', 'Detection', 'DFIR', 'BlueTeam')
            ProjectUri = ''
            ReleaseNotes = 'Initial release - comprehensive security automation framework'
        }
    }
}
