#Requires -Version 7.0
<#
.SYNOPSIS
    PowerShell Security Framework - Root Module
.DESCRIPTION
    Main module file that initializes the security framework.
#>

$ModulePath = $PSScriptRoot

# Import all submodules
$subModules = @(
    'modules\EventLogs.psm1',
    'modules\Hardening.psm1',
    'modules\Reconnaissance.psm1',
    'modules\PatchManagement.psm1',
    'modules\JEAManagement.psm1',
    'modules\ThreatDetection.psm1'
)

foreach ($module in $subModules) {
    $fullPath = Join-Path -Path $ModulePath -ChildPath $module
    if (Test-Path -Path $fullPath) {
        Import-Module -Name $fullPath -Force -Global
    }
    else {
        Write-Warning "Module not found: $fullPath"
    }
}

Write-Verbose "PowerShell Security Framework loaded successfully."
