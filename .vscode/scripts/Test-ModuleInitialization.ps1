#Requires -Version 7.0
<#
.SYNOPSIS
    Validates PowerShell module initialization order.

.DESCRIPTION
    Checks for the 3 root causes identified in the framework:
    1. Script-scoped variables used in defaults before initialization
    2. Null-dereference patterns
    3. Inconsistent return types

.PARAMETER Path
    Path to the PowerShell module file (.psm1).

.EXAMPLE
    .\Test-ModuleInitialization.ps1 -Path ..\modules\ThreatDetection.psm1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

Write-Host "`n🔬 Module Initialization Order Validator" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════`n" -ForegroundColor Cyan

$issues = @()
$warnings = @()
$info = @()

# Parse the module
$content = Get-Content -Path $Path -Raw
$parseErrors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors)

if ($parseErrors) {
    Write-Host "❌ PARSE ERRORS:" -ForegroundColor Red
    $parseErrors | ForEach-Object {
        Write-Host "   Line $($_.Extent.StartLineNumber): $_" -ForegroundColor Red
    }
    exit 1
}

Write-Host "✅ Syntax valid" -ForegroundColor Green

# Check 1: StrictMode
Write-Host "`n[1/6] Checking Set-StrictMode..." -NoNewline
$strictModeCmd = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst] -and
    $node.CommandElements[0].Value -eq 'Set-StrictMode'
}, $false) | Where-Object {
    $_.CommandElements | Where-Object {
        $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $_.Value -eq 'Latest'
    }
}

if ($strictModeCmd) {
    Write-Host " ✅" -ForegroundColor Green
} else {
    Write-Host " ❌" -ForegroundColor Red
    $issues += "Missing 'Set-StrictMode -Version Latest' at module level"
}

# Check 2: Script-scoped variable initialization
Write-Host "[2/6] Checking script variable initialization..." -NoNewline

$scriptVarInits = @{}
$ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
    $node.Left.VariablePath.UserPath -match '^\$?script:'
}, $true) | ForEach-Object {
    $varName = $_.Left.VariablePath.UserPath -replace '^\$?script:', '' -replace '^\$', ''
    $scriptVarInits[$varName] = $_.Extent.StartLineNumber
}

$functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
$uninitializedVars = @()

foreach ($function in $functions) {
    if (-not $function.Body.ParamBlock) { continue }

    foreach ($param in $function.Body.ParamBlock.Parameters) {
        if (-not $param.DefaultValue) { continue }

        $param.DefaultValue.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.VariablePath.UserPath -match '^\$?script:'
        }, $true) | ForEach-Object {
            $varName = $_.VariablePath.UserPath -replace '^\$?script:', '' -replace '^\$', ''

            if (-not $scriptVarInits.ContainsKey($varName) -or
                $scriptVarInits[$varName] -gt $function.Extent.StartLineNumber) {
                $uninitializedVars += [PSCustomObject]@{
                    Function = $function.Name
                    Variable = $varName
                    Line     = $param.Extent.StartLineNumber
                }
            }
        }
    }
}

if ($uninitializedVars) {
    Write-Host " ❌" -ForegroundColor Red
    foreach ($var in $uninitializedVars) {
        $issues += "Line $($var.Line): Function '$($var.Function)' uses `$script:$($var.Variable) in parameter default before initialization"
    }
} else {
    Write-Host " ✅" -ForegroundColor Green
}

# Check 3: Null-dereference patterns
Write-Host "[3/6] Checking null-dereference patterns..." -NoNewline

$dangerousMethods = @('Trim', 'TrimStart', 'TrimEnd', 'ToUpper', 'ToLower', 'Replace', 'Split', 'Substring')
$unsafeCalls = @()

$ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
    $dangerousMethods -contains $node.Member.Value
}, $true) | ForEach-Object {
    $invocation = $_
    $targetExpr = $invocation.Expression

    if ($targetExpr -is [System.Management.Automation.Language.VariableExpressionAst]) {
        # Very basic check - just flag all for manual review
        $unsafeCalls += [PSCustomObject]@{
            Method = $invocation.Member.Value
            Line   = $invocation.Extent.StartLineNumber
            Code   = $invocation.Extent.Text
        }
    }
}

if ($unsafeCalls.Count -gt 5) {
    Write-Host " ⚠️" -ForegroundColor Yellow
    $warnings += "$($unsafeCalls.Count) method calls found that may need null checks. Review manually."
} else {
    Write-Host " ✅" -ForegroundColor Green
}

# Check 4: Return type consistency
Write-Host "[4/6] Checking return type consistency..." -NoNewline

$inconsistentReturns = @()

foreach ($function in $functions) {
    $returnStatements = $function.Body.FindAll({
        $args[0] -is [System.Management.Automation.Language.ReturnStatementAst]
    }, $true)

    $hasEmptyArray = $false
    $hasTypedCollection = $false

    foreach ($returnStmt in $returnStatements) {
        if (-not $returnStmt.Pipeline) { continue }

        $expr = $returnStmt.Pipeline.PipelineElements[0].Expression
        $exprText = $expr.Extent.Text

        if ($exprText -match '^@\(\s*\)$') {
            $hasEmptyArray = $true
        } elseif ($exprText -match '\.ToArray\(\)') {
            $hasTypedCollection = $true
        }
    }

    if ($hasEmptyArray -and $hasTypedCollection) {
        $inconsistentReturns += $function.Name
    }
}

if ($inconsistentReturns) {
    Write-Host " ❌" -ForegroundColor Red
    foreach ($funcName in $inconsistentReturns) {
        $issues += "Function '$funcName' returns @() in some paths but typed collection in others"
    }
} else {
    Write-Host " ✅" -ForegroundColor Green
}

# Check 5: ErrorActionPreference
Write-Host "[5/6] Checking ErrorActionPreference..." -NoNewline

if ($content -match '\$ErrorActionPreference\s*=\s*[''"]Stop[''"]') {
    Write-Host " ✅" -ForegroundColor Green
} else {
    Write-Host " ⚠️" -ForegroundColor Yellow
    $warnings += "Consider setting \$ErrorActionPreference = 'Stop' at module level"
}

# Check 6: Generic.List usage
Write-Host "[6/6] Checking collection performance..." -NoNewline

$arrayPlusEquals = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $node.Operator -eq 'PlusEquals'
}, $true) | Where-Object {
    # Check if in loop
    $inLoop = $false
    $parent = $_.Parent
    while ($parent) {
        if ($parent -is [System.Management.Automation.Language.LoopStatementAst] -or
            $parent -is [System.Management.Automation.Language.ForEachStatementAst]) {
            $inLoop = $true
            break
        }
        $parent = $parent.Parent
    }
    $inLoop
}

if ($arrayPlusEquals) {
    Write-Host " ℹ️" -ForegroundColor Cyan
    $info += "$($arrayPlusEquals.Count) array += operations in loops detected. Consider using [System.Collections.Generic.List[T]] for better performance."
} else {
    Write-Host " ✅" -ForegroundColor Green
}

# Summary
Write-Host "`n" -NoNewline
Write-Host "═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════`n" -ForegroundColor Cyan

if ($issues) {
    Write-Host "❌ ERRORS ($($issues.Count)):" -ForegroundColor Red
    $issues | ForEach-Object { Write-Host "   • $_" -ForegroundColor Red }
    Write-Host ""
}

if ($warnings) {
    Write-Host "⚠️  WARNINGS ($($warnings.Count)):" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "   • $_" -ForegroundColor Yellow }
    Write-Host ""
}

if ($info) {
    Write-Host "ℹ️  INFORMATION ($($info.Count)):" -ForegroundColor Cyan
    $info | ForEach-Object { Write-Host "   • $_" -ForegroundColor Cyan }
    Write-Host ""
}

if (-not $issues -and -not $warnings) {
    Write-Host "✅ All checks passed! Module initialization is correct." -ForegroundColor Green
    exit 0
} elseif (-not $issues) {
    Write-Host "✅ No errors found. Review warnings if applicable." -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ Module has initialization issues that must be fixed." -ForegroundColor Red
    exit 1
}
