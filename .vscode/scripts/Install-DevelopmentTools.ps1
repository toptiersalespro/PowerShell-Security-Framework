#Requires -Version 7.0
<#
.SYNOPSIS
    Installs and configures development tools for PowerShell Security Framework.

.DESCRIPTION
    One-command setup for:
    - PSScriptAnalyzer
    - Pester testing framework
    - Git hooks configuration
    - VSCode task validation

.EXAMPLE
    .\Install-DevelopmentTools.ps1

.EXAMPLE
    .\Install-DevelopmentTools.ps1 -SkipGitHooks
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$SkipGitHooks
)

$ErrorActionPreference = 'Stop'

Write-Host "`n🚀 PowerShell Security Framework - Development Tools Setup" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

$success = 0
$warnings = 0
$errors = 0

# Step 1: Check PowerShell version
Write-Host "[1/6] Checking PowerShell version..." -NoNewline

if ($PSVersionTable.PSVersion.Major -ge 7) {
    Write-Host " ✅ v$($PSVersionTable.PSVersion)" -ForegroundColor Green
    $success++
} else {
    Write-Host " ❌ v$($PSVersionTable.PSVersion) - Requires PowerShell 7+" -ForegroundColor Red
    Write-Host "      Download from: https://github.com/PowerShell/PowerShell/releases" -ForegroundColor Yellow
    $errors++
}

# Step 2: Install PSScriptAnalyzer
Write-Host "[2/6] Installing PSScriptAnalyzer..." -NoNewline

try {
    $existingModule = Get-Module -ListAvailable -Name PSScriptAnalyzer | Sort-Object Version -Descending | Select-Object -First 1

    if ($existingModule) {
        Write-Host " ✅ v$($existingModule.Version) (already installed)" -ForegroundColor Green
        $success++
    } else {
        Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        $installedModule = Get-Module -ListAvailable -Name PSScriptAnalyzer | Select-Object -First 1
        Write-Host " ✅ v$($installedModule.Version) (newly installed)" -ForegroundColor Green
        $success++
    }
} catch {
    Write-Host " ❌" -ForegroundColor Red
    Write-Host "      Error: $($_.Exception.Message)" -ForegroundColor Red
    $errors++
}

# Step 3: Install Pester
Write-Host "[3/6] Installing Pester..." -NoNewline

try {
    $existingPester = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1

    if ($existingPester -and $existingPester.Version -ge [version]'5.0.0') {
        Write-Host " ✅ v$($existingPester.Version) (already installed)" -ForegroundColor Green
        $success++
    } else {
        # Uninstall old Pester versions first (common issue)
        if ($existingPester -and $existingPester.Version -lt [version]'5.0.0') {
            Write-Host " ⚠️  Removing old version..." -ForegroundColor Yellow -NoNewline
            Uninstall-Module -Name Pester -AllVersions -Force -ErrorAction SilentlyContinue
        }

        Install-Module -Name Pester -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
        $installedPester = Get-Module -ListAvailable -Name Pester | Select-Object -First 1
        Write-Host " ✅ v$($installedPester.Version) (newly installed)" -ForegroundColor Green
        $success++
    }
} catch {
    Write-Host " ❌" -ForegroundColor Red
    Write-Host "      Error: $($_.Exception.Message)" -ForegroundColor Red
    $errors++
}

# Step 4: Configure Git hooks
if (-not $SkipGitHooks) {
    Write-Host "[4/6] Configuring Git hooks..." -NoNewline

    $gitRoot = git rev-parse --show-toplevel 2>$null

    if ($LASTEXITCODE -eq 0 -and $gitRoot) {
        try {
            # Set hooks path to custom directory
            git config core.hooksPath .githooks

            # Make pre-commit hook executable (Windows doesn't need this, but doesn't hurt)
            $preCommitHook = Join-Path -Path $gitRoot -ChildPath '.githooks\pre-commit'

            if (Test-Path -Path $preCommitHook) {
                # On Unix-like systems, ensure executable
                if ($IsLinux -or $IsMacOS) {
                    chmod +x $preCommitHook
                }
                Write-Host " ✅" -ForegroundColor Green
                $success++
            } else {
                Write-Host " ⚠️  Hook file not found" -ForegroundColor Yellow
                $warnings++
            }
        } catch {
            Write-Host " ❌" -ForegroundColor Red
            Write-Host "      Error: $($_.Exception.Message)" -ForegroundColor Red
            $errors++
        }
    } else {
        Write-Host " ⏭️  Not a Git repository" -ForegroundColor Gray
    }
} else {
    Write-Host "[4/6] Configuring Git hooks... ⏭️  Skipped" -ForegroundColor Gray
}

# Step 5: Validate custom rules
Write-Host "[5/6] Validating custom PSScriptAnalyzer rules..." -NoNewline

$customRulesPath = Join-Path -Path $PSScriptRoot -ChildPath 'PSScriptAnalyzerCustomRules.psm1'

if (Test-Path -Path $customRulesPath) {
    try {
        Import-Module $customRulesPath -Force -ErrorAction Stop
        $exportedFunctions = Get-Command -Module PSScriptAnalyzerCustomRules

        if ($exportedFunctions.Count -ge 5) {
            Write-Host " ✅ ($($exportedFunctions.Count) rules loaded)" -ForegroundColor Green
            $success++
        } else {
            Write-Host " ⚠️  Only $($exportedFunctions.Count) rules found" -ForegroundColor Yellow
            $warnings++
        }

        Remove-Module PSScriptAnalyzerCustomRules -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host " ❌" -ForegroundColor Red
        Write-Host "      Error: $($_.Exception.Message)" -ForegroundColor Red
        $errors++
    }
} else {
    Write-Host " ❌ File not found" -ForegroundColor Red
    $errors++
}

# Step 6: Test validation script
Write-Host "[6/6] Testing module validation script..." -NoNewline

$validationScript = Join-Path -Path $PSScriptRoot -ChildPath 'Test-ModuleInitialization.ps1'

if (Test-Path -Path $validationScript) {
    try {
        # Test on ThreatDetection module
        $testModule = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent) -ChildPath 'modules\ThreatDetection.psm1'

        if (Test-Path -Path $testModule) {
            $null = & $validationScript -Path $testModule -ErrorAction Stop 2>&1
            Write-Host " ✅" -ForegroundColor Green
            $success++
        } else {
            Write-Host " ⚠️  Test module not found" -ForegroundColor Yellow
            $warnings++
        }
    } catch {
        Write-Host " ⚠️  Test failed (non-critical)" -ForegroundColor Yellow
        $warnings++
    }
} else {
    Write-Host " ❌ Script not found" -ForegroundColor Red
    $errors++
}

# Summary
Write-Host "`n═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "SETUP SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Write-Host "✅ Success: $success" -ForegroundColor Green
Write-Host "⚠️  Warnings: $warnings" -ForegroundColor Yellow
Write-Host "❌ Errors: $errors" -ForegroundColor Red

Write-Host ""

if ($errors -eq 0) {
    Write-Host "🎉 Setup complete! Development tools are ready." -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Cyan
    Write-Host "  1. Open any .psm1 file in VSCode" -ForegroundColor White
    Write-Host "  2. Press Ctrl+Shift+B to see available validation tasks" -ForegroundColor White
    Write-Host "  3. Run 'Invoke-Pester' to execute tests" -ForegroundColor White
    Write-Host "  4. Git commits will now auto-validate PowerShell files" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "⚠️  Setup completed with errors. Review messages above." -ForegroundColor Yellow
    Write-Host ""
}

# Show useful commands
Write-Host "USEFUL COMMANDS:" -ForegroundColor Cyan
Write-Host "  • Test module: .vscode\scripts\Test-ModuleInitialization.ps1 -Path <file>" -ForegroundColor Gray
Write-Host "  • Run analyzer: Invoke-ScriptAnalyzer -Path <file> -CustomRulePath .vscode\scripts\PSScriptAnalyzerCustomRules.psm1" -ForegroundColor Gray
Write-Host "  • Pre-commit check: .vscode\scripts\Invoke-PreCommitValidation.ps1" -ForegroundColor Gray
Write-Host ""
