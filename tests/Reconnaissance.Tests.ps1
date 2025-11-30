#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for Reconnaissance module.
.DESCRIPTION
    Unit tests for reconnaissance and enumeration functions.
#>

BeforeAll {
    $modulePath = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path -Path $modulePath -ChildPath 'modules\Reconnaissance.psm1') -Force
}

Describe 'Get-LocalUsersAndGroups' {
    Context 'When enumerating local groups' {
        It 'Should not throw' {
            { Get-LocalUsersAndGroups -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Should return objects with GroupName property' {
            $result = Get-LocalUsersAndGroups | Select-Object -First 1
            if ($result) {
                $result.PSObject.Properties.Name | Should -Contain 'GroupName'
            }
        }

        It 'Should include Administrators group' {
            $result = Get-LocalUsersAndGroups
            $adminGroup = $result | Where-Object { $_.GroupName -eq 'Administrators' }
            $adminGroup | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-CimNamespace' {
    Context 'When enumerating namespaces' {
        It 'Should return namespaces under root' {
            $result = Get-CimNamespace -Namespace 'root'
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should support Recurse parameter' {
            { Get-CimNamespace -Namespace 'root' -Recurse | Select-Object -First 10 } | Should -Not -Throw
        }
    }
}

Describe 'Get-UserRightsAssignment' {
    Context 'When running as admin' {
        BeforeAll {
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }

        It 'Should return privilege assignments when admin' -Skip:(-not $isAdmin) {
            $result = Get-UserRightsAssignment
            $result | Should -Not -BeNullOrEmpty
        }

        It 'Should return objects with RightName and Account properties' -Skip:(-not $isAdmin) {
            $result = Get-UserRightsAssignment | Select-Object -First 1
            $result.PSObject.Properties.Name | Should -Contain 'RightName'
            $result.PSObject.Properties.Name | Should -Contain 'Account'
        }
    }
}
