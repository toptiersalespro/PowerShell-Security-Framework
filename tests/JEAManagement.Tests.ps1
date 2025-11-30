#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for JEAManagement module.
.DESCRIPTION
    Unit tests for JEA management functions.
#>

BeforeAll {
    $modulePath = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path -Path $modulePath -ChildPath 'modules\JEAManagement.psm1') -Force
}

Describe 'Get-VirtualAccountLogons' {
    It 'Should not throw' {
        { Get-VirtualAccountLogons -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Should return empty if no JEA sessions' {
        $result = Get-VirtualAccountLogons
        # May be empty on systems without JEA
        $result | Should -BeOfType [PSCustomObject] -Or $result | Should -BeNullOrEmpty
    }
}

Describe 'Get-JEAEndpoints' {
    Context 'When querying JEA endpoints' {
        It 'Should not throw' {
            { Get-JEAEndpoints -ErrorAction Stop } | Should -Not -Throw
        }
    }
}

Describe 'New-JEAConfiguration' {
    Context 'Parameter validation' {
        It 'Should require Name parameter' {
            { New-JEAConfiguration -AllowedCmdlets 'Get-Process' -AllowedUsers 'TEST\User' -WhatIf } | Should -Throw
        }

        It 'Should require AllowedCmdlets parameter' {
            { New-JEAConfiguration -Name 'Test' -AllowedUsers 'TEST\User' -WhatIf } | Should -Throw
        }

        It 'Should support WhatIf' {
            { New-JEAConfiguration -Name 'TestJEA' -AllowedCmdlets 'Get-Process' -AllowedUsers 'TEST\User' -WhatIf } | Should -Not -Throw
        }
    }
}
