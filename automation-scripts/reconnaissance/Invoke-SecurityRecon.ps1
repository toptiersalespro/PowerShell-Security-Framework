#Requires -Version 7.0
<#
.SYNOPSIS
    Reconnaissance playbook for security enumeration.
.DESCRIPTION
    Comprehensive enumeration of users, groups, privileges, and security
    settings for security assessment purposes.
.PARAMETER OutputPath
    Directory for enumeration results.
.PARAMETER IncludeAD
    Include Active Directory enumeration if available.
.EXAMPLE
    .\Invoke-SecurityRecon.ps1
.EXAMPLE
    .\Invoke-SecurityRecon.ps1 -IncludeAD -OutputPath "C:\Recon"
.NOTES
    Category: reconnaissance
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath = "$env:TEMP\SecurityRecon_$(Get-Date -Format 'yyyyMMddHHmmss')",

    [Parameter()]
    [switch]$IncludeAD
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import framework
$frameworkPath = Split-Path -Parent $PSScriptRoot | Split-Path -Parent
Import-Module (Join-Path -Path $frameworkPath -ChildPath 'SecurityFramework.psd1') -Force

Write-Host "=== Security Reconnaissance Playbook ===" -ForegroundColor Cyan

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$reconResults = @{
    ScanTime = Get-Date
    ComputerName = $env:COMPUTERNAME
    Domain = $env:USERDOMAIN
    Sections = @{}
}

# Section 1: Local Users and Groups
Write-Host "`n[1/4] Enumerating Local Users and Groups..." -ForegroundColor Yellow
try {
    $localUsers = Get-LocalUsersAndGroups
    $reconResults.Sections['LocalUsers'] = @{
        Count = $localUsers.Count
        AdminMembers = @($localUsers | Where-Object { $_.GroupName -eq 'Administrators' }).Count
    }
    $localUsers | Export-Csv -Path "$OutputPath\LocalUsersAndGroups.csv" -NoTypeInformation
    Write-Host "  Found $($localUsers.Count) group memberships" -ForegroundColor Green
    Write-Host "  Administrators: $($reconResults.Sections['LocalUsers'].AdminMembers)" -ForegroundColor Gray
}
catch {
    Write-Warning "  Failed: $_"
    $reconResults.Sections['LocalUsers'] = @{ Error = $_.Exception.Message }
}

# Section 2: User Rights Assignment
Write-Host "`n[2/4] Enumerating User Rights..." -ForegroundColor Yellow
try {
    $rights = Get-UserRightsAssignment
    $reconResults.Sections['UserRights'] = @{
        Count = $rights.Count
        UniqueRights = @($rights | Select-Object -ExpandProperty RightName -Unique).Count
    }
    $rights | Export-Csv -Path "$OutputPath\UserRightsAssignment.csv" -NoTypeInformation
    Write-Host "  Found $($rights.Count) privilege assignments" -ForegroundColor Green

    # Highlight dangerous privileges
    $dangerousRights = @('SeDebugPrivilege', 'SeTcbPrivilege', 'SeLoadDriverPrivilege', 'SeBackupPrivilege')
    $dangerous = $rights | Where-Object { $dangerousRights -contains $_.RightName }
    if ($dangerous) {
        Write-Host "  [WARNING] Found $($dangerous.Count) assignments of sensitive privileges" -ForegroundColor Yellow
    }
}
catch {
    Write-Warning "  Failed: $_"
    $reconResults.Sections['UserRights'] = @{ Error = $_.Exception.Message }
}

# Section 3: CIM Namespaces
Write-Host "`n[3/4] Enumerating CIM Namespaces..." -ForegroundColor Yellow
try {
    $namespaces = Get-CimNamespace -Namespace 'root' -Recurse
    $reconResults.Sections['CIMNamespaces'] = @{ Count = @($namespaces).Count }
    $namespaces | ForEach-Object { [PSCustomObject]@{ Namespace = $_ } } |
        Export-Csv -Path "$OutputPath\CIMNamespaces.csv" -NoTypeInformation
    Write-Host "  Found $(@($namespaces).Count) namespaces" -ForegroundColor Green
}
catch {
    Write-Warning "  Failed: $_"
    $reconResults.Sections['CIMNamespaces'] = @{ Error = $_.Exception.Message }
}

# Section 4: Active Directory (if requested and available)
if ($IncludeAD) {
    Write-Host "`n[4/4] Enumerating Active Directory..." -ForegroundColor Yellow

    # Try ADSI method (no module required)
    try {
        $adUsers = Get-ADUsersAndGroupsWithAdsi
        $reconResults.Sections['ADGroups'] = @{ Count = $adUsers.Count }
        $adUsers | Export-Csv -Path "$OutputPath\ADGroupMembership.csv" -NoTypeInformation
        Write-Host "  Found $($adUsers.Count) AD group memberships (ADSI)" -ForegroundColor Green
    }
    catch {
        Write-Warning "  AD enumeration failed: $_"
        $reconResults.Sections['ADGroups'] = @{ Error = $_.Exception.Message }
    }

    # Try GPO permissions if GroupPolicy module available
    try {
        if (Get-Module -ListAvailable -Name GroupPolicy) {
            $gpoPerms = Get-GpoPermissions
            $reconResults.Sections['GPOPermissions'] = @{ Count = $gpoPerms.Count }
            $gpoPerms | Export-Csv -Path "$OutputPath\GPOPermissions.csv" -NoTypeInformation
            Write-Host "  Found $($gpoPerms.Count) GPO permissions" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "  GPO enumeration failed: $_"
    }
}
else {
    Write-Host "`n[4/4] Skipping AD enumeration (use -IncludeAD)" -ForegroundColor Gray
}

# Save summary
$reconResults | ConvertTo-Json -Depth 5 | Set-Content -Path "$OutputPath\ReconSummary.json"

Write-Host "`n=== Reconnaissance Complete ===" -ForegroundColor Cyan
Write-Host "Results saved to: $OutputPath" -ForegroundColor Green

return $reconResults
