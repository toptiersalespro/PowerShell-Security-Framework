#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for EventLogs module.
.DESCRIPTION
    Unit tests for Get-AllPowerShellEvents and Get-ExecutedCode functions.
#>

BeforeAll {
    $modulePath = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path -Path $modulePath -ChildPath 'modules\EventLogs.psm1') -Force
}

Describe 'Get-AllPowerShellEvents' {
    Context 'When querying events' {
        It 'Should not throw with default parameters' {
            { Get-AllPowerShellEvents -MaxEvents 10 -ErrorAction Stop } | Should -Not -Throw
        }

        It 'Should accept MaxEvents parameter' {
            { Get-AllPowerShellEvents -MaxEvents 5 } | Should -Not -Throw
        }

        It 'Should validate MaxEvents range' {
            { Get-AllPowerShellEvents -MaxEvents 0 } | Should -Throw
            { Get-AllPowerShellEvents -MaxEvents -1 } | Should -Throw
        }
    }
}

Describe 'Get-ExecutedCode' {
    Context 'When extracting script blocks' {
        It 'Should not throw with no parameters' {
            { Get-ExecutedCode -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should accept SearchWord parameter' {
            { Get-ExecutedCode -SearchWord "test" -ErrorAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Should return objects with expected properties' {
            $result = Get-ExecutedCode -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($result) {
                $result.PSObject.Properties.Name | Should -Contain 'TimeCreated'
                $result.PSObject.Properties.Name | Should -Contain 'ExecutedCode'
                $result.PSObject.Properties.Name | Should -Contain 'UserId'
            }
        }
    }
}
