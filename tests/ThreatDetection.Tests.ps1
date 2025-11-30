#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for ThreatDetection module.
.DESCRIPTION
    Unit tests for threat detection functions.
#>

BeforeAll {
    $modulePath = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path -Path $modulePath -ChildPath 'modules\ThreatDetection.psm1') -Force
}

Describe 'Test-AMSIStatus' {
    It 'Should return AMSI status object' {
        $result = Test-AMSIStatus
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'AMSIEnabled'
        $result.PSObject.Properties.Name | Should -Contain 'TestResult'
    }

    It 'Should include timestamp' {
        $result = Test-AMSIStatus
        $result.Timestamp | Should -BeOfType [DateTime]
    }
}

Describe 'Find-SuspiciousScriptPatterns' {
    Context 'Pattern detection' {
        It 'Should not throw with default parameters' {
            { Find-SuspiciousScriptPatterns -MaxEvents 10 } | Should -Not -Throw
        }

        It 'Should return objects with severity levels' {
            $result = Find-SuspiciousScriptPatterns -MaxEvents 100 | Select-Object -First 1
            if ($result) {
                $result.RiskLevel | Should -BeIn @('Critical', 'High', 'Medium', 'Low')
            }
        }
    }
}

Describe 'Get-AMSIDetectionEvents' {
    It 'Should not throw when querying AMSI events' {
        { Get-AMSIDetectionEvents -MaxEvents 10 -ErrorAction SilentlyContinue } | Should -Not -Throw
    }
}
