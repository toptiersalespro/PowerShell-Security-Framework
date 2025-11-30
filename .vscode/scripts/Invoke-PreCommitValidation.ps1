#Requires -Version 7.0
<#
.SYNOPSIS
    Pre-commit validation hook for PowerShell Security Framework.

.DESCRIPTION
    Runs comprehensive validation on changed .ps1/.psm1 files before commit.
    Blocks commits if critical issues found.

.EXAMPLE
    .\Invoke-PreCommitValidation.ps1

.NOTES
    Add to .git/hooks/pre-commit:
    #!/bin/sh
    pwsh -NoProfile -ExecutionPolicy Bypass -File .vscode/scripts/Invoke-PreCommitValidation.ps1
    exit $?
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

Write-Host "`n🚀 Pre-Commit Validation" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════`n" -ForegroundColor Cyan

# Get staged PowerShell files
$stagedFiles = git diff --cached --name-only --diff-filter=ACM | Where-Object { $_ -match '\.(ps1|psm1)$' }

if (-not $stagedFiles) {
    Write-Host "ℹ️  No PowerShell files staged for commit" -ForegroundColor Cyan
    exit 0
}

Write-Host "📁 Found $($stagedFiles.Count) PowerShell file(s) to validate:`n" -ForegroundColor White
$stagedFiles | ForEach-Object { Write-Host "   • $_" -ForegroundColor Gray }
Write-Host ""

$totalIssues = 0
$criticalIssues = 0

foreach ($file in $stagedFiles) {
    $fullPath = Join-Path -Path (git rev-parse --show-toplevel) -ChildPath $file

    if (-not (Test-Path -Path $fullPath)) {
        Write-Host "⚠️  Skipping deleted file: $file" -ForegroundColor Yellow
        continue
    }

    Write-Host "🔍 Validating: $file" -ForegroundColor Cyan

    # Test 1: Syntax
    Write-Host "   [1/4] Syntax check..." -NoNewline
    try {
        $content = Get-Content -Path $fullPath -Raw
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$null, [ref]$errors)

        if ($errors) {
            Write-Host " ❌" -ForegroundColor Red
            $errors | ForEach-Object {
                Write-Host "      Line $($_.Extent.StartLineNumber): $_" -ForegroundColor Red
            }
            $criticalIssues += $errors.Count
            continue
        } else {
            Write-Host " ✅" -ForegroundColor Green
        }
    } catch {
        Write-Host " ❌" -ForegroundColor Red
        Write-Host "      $_" -ForegroundColor Red
        $criticalIssues++
        continue
    }

    # Test 2: Module initialization (for .psm1 files)
    if ($file -match '\.psm1$') {
        Write-Host "   [2/4] Initialization order..." -NoNewline

        $scriptRoot = Split-Path -Path $PSScriptRoot -Parent
        $initTestScript = Join-Path -Path $scriptRoot -ChildPath '.vscode\scripts\Test-ModuleInitialization.ps1'

        if (Test-Path -Path $initTestScript) {
            try {
                $null = & $initTestScript -Path $fullPath 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host " ✅" -ForegroundColor Green
                } else {
                    Write-Host " ❌" -ForegroundColor Red
                    $criticalIssues++
                }
            } catch {
                Write-Host " ⚠️" -ForegroundColor Yellow
                Write-Host "      Could not run initialization test" -ForegroundColor Yellow
            }
        } else {
            Write-Host " ⏭️  (test script not found)" -ForegroundColor Gray
        }
    } else {
        Write-Host "   [2/4] Initialization order... ⏭️  (not a module)" -ForegroundColor Gray
    }

    # Test 3: PSScriptAnalyzer
    Write-Host "   [3/4] PSScriptAnalyzer..." -NoNewline

    if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
        Import-Module PSScriptAnalyzer -ErrorAction SilentlyContinue

        $scriptRoot = Split-Path -Path $PSScriptRoot -Parent
        $customRulesPath = Join-Path -Path $scriptRoot -ChildPath '.vscode\scripts\PSScriptAnalyzerCustomRules.psm1'

        $analyzerParams = @{
            Path     = $fullPath
            Severity = @('Error', 'Warning')
        }

        if (Test-Path -Path $customRulesPath) {
            $analyzerParams['CustomRulePath'] = $customRulesPath
        }

        $results = Invoke-ScriptAnalyzer @analyzerParams

        $errors = $results | Where-Object { $_.Severity -eq 'Error' }
        $warnings = $results | Where-Object { $_.Severity -eq 'Warning' }

        if ($errors) {
            Write-Host " ❌ ($($errors.Count) errors)" -ForegroundColor Red
            $errors | Select-Object -First 3 | ForEach-Object {
                Write-Host "      Line $($_.Line): $($_.RuleName) - $($_.Message)" -ForegroundColor Red
            }
            if ($errors.Count -gt 3) {
                Write-Host "      ... and $($errors.Count - 3) more" -ForegroundColor Red
            }
            $criticalIssues += $errors.Count
        } elseif ($warnings) {
            Write-Host " ⚠️  ($($warnings.Count) warnings)" -ForegroundColor Yellow
            $totalIssues += $warnings.Count
        } else {
            Write-Host " ✅" -ForegroundColor Green
        }
    } else {
        Write-Host " ⏭️  (PSScriptAnalyzer not installed)" -ForegroundColor Gray
        Write-Host "      Run: Install-Module PSScriptAnalyzer -Scope CurrentUser" -ForegroundColor Gray
    }

    # Test 4: Contains sensitive data
    Write-Host "   [4/4] Sensitive data scan..." -NoNewline

    $sensitivePatterns = @(
        'password\s*=\s*[''"](?!(\$|{))',  # Hardcoded passwords
        'api[_-]?key\s*=\s*[''"](?!(\$|{))',  # Hardcoded API keys
        'secret\s*=\s*[''"](?!(\$|{))',  # Hardcoded secrets
        'credential\s*=\s*[''"][^$]'  # Hardcoded credentials
    )

    $sensitiveMatches = @()
    foreach ($pattern in $sensitivePatterns) {
        $matches = Select-String -Path $fullPath -Pattern $pattern -CaseSensitive:$false
        if ($matches) {
            $sensitiveMatches += $matches
        }
    }

    if ($sensitiveMatches) {
        Write-Host " ⚠️  (potential secrets found)" -ForegroundColor Yellow
        $sensitiveMatches | Select-Object -First 2 | ForEach-Object {
            Write-Host "      Line $($_.LineNumber): $($_.Line.Trim())" -ForegroundColor Yellow
        }
        $totalIssues += $sensitiveMatches.Count
    } else {
        Write-Host " ✅" -ForegroundColor Green
    }

    Write-Host ""
}

# Summary
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════`n" -ForegroundColor Cyan

Write-Host "Files validated: $($stagedFiles.Count)" -ForegroundColor White
Write-Host "Critical issues: $criticalIssues" -ForegroundColor $(if ($criticalIssues -gt 0) { 'Red' } else { 'Green' })
Write-Host "Warnings: $totalIssues" -ForegroundColor $(if ($totalIssues -gt 0) { 'Yellow' } else { 'Green' })

Write-Host ""

if ($criticalIssues -gt 0) {
    Write-Host "❌ COMMIT BLOCKED: Fix critical issues before committing" -ForegroundColor Red
    Write-Host ""
    Write-Host "To bypass (NOT RECOMMENDED): git commit --no-verify" -ForegroundColor Gray
    exit 1
} elseif ($totalIssues -gt 0) {
    Write-Host "⚠️  COMMIT ALLOWED: Review warnings before pushing" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "✅ All validations passed - commit approved!" -ForegroundColor Green
    exit 0
}
