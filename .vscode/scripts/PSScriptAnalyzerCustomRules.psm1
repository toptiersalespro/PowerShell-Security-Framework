#Requires -Version 7.0
<#
.SYNOPSIS
    Custom PSScriptAnalyzer rules for PowerShell Security Framework.

.DESCRIPTION
    Detects the 3 root causes identified in AI-TRAINING-ROOT-CAUSE-ANALYSIS.md:
    1. Uninitialized script-scoped variables in parameter defaults
    2. Null-dereference patterns (method calls without null checks)
    3. Inconsistent return types across code paths

.NOTES
    Install PSScriptAnalyzer: Install-Module PSScriptAnalyzer -Scope CurrentUser
    Use rules: Invoke-ScriptAnalyzer -Path script.ps1 -CustomRulePath .\PSScriptAnalyzerCustomRules.psm1
#>

using namespace System.Management.Automation.Language

#region Rule 1: Uninitialized Script Variables in Defaults

function Measure-UninitializedScriptVariable {
    <#
    .SYNOPSIS
        Detects script-scoped variables used in parameter defaults before initialization.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ScriptBlockAst]$ScriptBlockAst
    )

    $results = @()

    # Step 1: Find all script-scoped variable initializations
    $initializedVars = @{}
    $scriptBlockAst.FindAll({
        param($node)
        $node -is [AssignmentStatementAst] -and
        $node.Left -is [VariableExpressionAst] -and
        $node.Left.VariablePath.UserPath -match '^\$?script:'
    }, $true) | ForEach-Object {
        $varName = $_.Left.VariablePath.UserPath -replace '^\$?script:', ''
        $initializedVars[$varName] = $_.Extent.StartLineNumber
    }

    # Step 2: Find all functions with parameters that use script-scoped defaults
    $functions = $scriptBlockAst.FindAll({ $args[0] -is [FunctionDefinitionAst] }, $false)

    foreach ($function in $functions) {
        if (-not $function.Body.ParamBlock) { continue }

        foreach ($param in $function.Body.ParamBlock.Parameters) {
            if (-not $param.DefaultValue) { continue }

            # Check if default value references script-scoped variable
            $param.DefaultValue.FindAll({
                param($node)
                $node -is [VariableExpressionAst] -and
                $node.VariablePath.UserPath -match '^\$?script:'
            }, $true) | ForEach-Object {
                $varName = $_.VariablePath.UserPath -replace '^\$?script:', ''

                # Check if variable was initialized BEFORE function declaration
                if (-not $initializedVars.ContainsKey($varName) -or
                    $initializedVars[$varName] -gt $function.Extent.StartLineNumber) {

                    $results += [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                        Message  = "Script-scoped variable '\$script:$varName' used in parameter default before initialization. Initialize at module level before function declarations."
                        Extent   = $param.Extent
                        RuleName = 'PSAvoidUninitializedScriptVariable'
                        Severity = 'Error'
                    }
                }
            }
        }
    }

    return $results
}

#endregion

#region Rule 2: Null-Dereference Patterns

function Measure-UnsafeMethodCall {
    <#
    .SYNOPSIS
        Detects method calls on variables without null checks.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ScriptBlockAst]$ScriptBlockAst
    )

    $results = @()

    # High-risk method calls that fail on null
    $dangerousMethods = @(
        'Trim', 'TrimStart', 'TrimEnd', 'ToUpper', 'ToLower',
        'Replace', 'Split', 'Substring', 'IndexOf', 'Contains'
    )

    # Find all member invocations (method calls)
    $scriptBlockAst.FindAll({
        param($node)
        $node -is [InvokeMemberExpressionAst] -and
        $dangerousMethods -contains $node.Member.Value
    }, $true) | ForEach-Object {
        $invocation = $_
        $targetExpr = $invocation.Expression

        # Check if target is a variable
        if ($targetExpr -is [VariableExpressionAst]) {
            $varName = $targetExpr.VariablePath.UserPath

            # Check if there's a null check in the surrounding context
            $hasNullCheck = $false
            $parent = $invocation.Parent

            while ($parent -and -not $hasNullCheck) {
                # Look for if statements checking null/empty
                if ($parent -is [IfStatementAst]) {
                    $condition = $parent.Clauses[0].Item1.ToString()
                    if ($condition -match "\[string\]::IsNullOrWhiteSpace\(\s*\`$$varName\s*\)" -or
                        $condition -match "\-not\s+\`$$varName" -or
                        $condition -match "\`$$varName\s+-ne\s+\`$null") {
                        $hasNullCheck = $true
                    }
                }
                $parent = $parent.Parent
            }

            if (-not $hasNullCheck) {
                $results += [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                    Message  = "Method '$($invocation.Member.Value)' called on variable '\$$varName' without null/empty check. Use [string]::IsNullOrWhiteSpace() before calling."
                    Extent   = $invocation.Extent
                    RuleName = 'PSAvoidUnsafeMethodCall'
                    Severity = 'Warning'
                }
            }
        }
    }

    return $results
}

#endregion

#region Rule 3: Inconsistent Return Types

function Measure-InconsistentReturnType {
    <#
    .SYNOPSIS
        Detects functions with inconsistent return types across code paths.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ScriptBlockAst]$ScriptBlockAst
    )

    $results = @()

    $functions = $scriptBlockAst.FindAll({ $args[0] -is [FunctionDefinitionAst] }, $false)

    foreach ($function in $functions) {
        # Get declared OutputType if exists
        $outputType = $function.Body.ParamBlock.Attributes |
            Where-Object { $_.TypeName.Name -eq 'OutputType' } |
            Select-Object -First 1

        if (-not $outputType) { continue }

        # Find all return statements
        $returnStatements = $function.Body.FindAll({
            $args[0] -is [ReturnStatementAst]
        }, $true)

        $returnTypes = @()

        foreach ($returnStmt in $returnStatements) {
            if (-not $returnStmt.Pipeline) { continue }

            $expr = $returnStmt.Pipeline.PipelineElements[0].Expression

            # Detect type of return value
            $detectedType = if ($expr -is [ArrayLiteralAst]) {
                if ($expr.Elements.Count -eq 0) {
                    'EmptyArray'  # @()
                } else {
                    'Array'
                }
            } elseif ($expr -is [MemberExpressionAst] -and $expr.Member.Value -eq 'ToArray') {
                'TypedArray'  # $list.ToArray()
            } elseif ($expr -is [VariableExpressionAst]) {
                'Variable'
            } else {
                'Unknown'
            }

            $returnTypes += [PSCustomObject]@{
                Type   = $detectedType
                Line   = $returnStmt.Extent.StartLineNumber
                Extent = $returnStmt.Extent
            }
        }

        # Check for problematic patterns
        $hasEmptyArray = $returnTypes | Where-Object { $_.Type -eq 'EmptyArray' }
        $hasTypedArray = $returnTypes | Where-Object { $_.Type -eq 'TypedArray' }

        if ($hasEmptyArray -and $hasTypedArray) {
            foreach ($emptyReturn in $hasEmptyArray) {
                $results += [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                    Message  = "Function '$($function.Name)' returns @() here but typed array elsewhere. Use `$results.ToArray() or empty typed collection for consistency."
                    Extent   = $emptyReturn.Extent
                    RuleName = 'PSAvoidInconsistentReturnType'
                    Severity = 'Warning'
                }
            }
        }
    }

    return $results
}

#endregion

#region Rule 4: StrictMode Enforcement

function Measure-MissingStrictMode {
    <#
    .SYNOPSIS
        Ensures Set-StrictMode -Version Latest is present.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ScriptBlockAst]$ScriptBlockAst
    )

    $results = @()

    # Check if Set-StrictMode is called at script level
    $hasStrictMode = $scriptBlockAst.FindAll({
        param($node)
        $node -is [CommandAst] -and
        $node.CommandElements[0].Value -eq 'Set-StrictMode'
    }, $false) | Where-Object {
        $versionParam = $_.CommandElements | Where-Object { $_ -is [CommandParameterAst] -and $_.ParameterName -eq 'Version' }
        $versionValue = $_.CommandElements | Where-Object { $_ -is [StringConstantExpressionAst] -and $_.Value -eq 'Latest' }

        $versionParam -and $versionValue
    }

    if (-not $hasStrictMode) {
        $results += [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
            Message  = "Set-StrictMode -Version Latest not found at module/script level. This prevents detection of uninitialized variables."
            Extent   = $scriptBlockAst.Extent
            RuleName = 'PSUseMandatoryStrictMode'
            Severity = 'Error'
        }
    }

    return $results
}

#endregion

#region Rule 5: Generic List Usage

function Measure-ArrayAddUsage {
    <#
    .SYNOPSIS
        Detects += operations on arrays and suggests Generic.List.
    #>
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param(
        [Parameter(Mandatory)]
        [ScriptBlockAst]$ScriptBlockAst
    )

    $results = @()

    # Find all += assignments to array variables
    $scriptBlockAst.FindAll({
        param($node)
        $node -is [AssignmentStatementAst] -and
        $node.Operator -eq 'PlusEquals'
    }, $true) | ForEach-Object {
        $assignment = $_

        # Check if this is in a loop (performance issue)
        $inLoop = $false
        $parent = $assignment.Parent
        while ($parent) {
            if ($parent -is [LoopStatementAst] -or $parent -is [ForEachStatementAst]) {
                $inLoop = $true
                break
            }
            $parent = $parent.Parent
        }

        if ($inLoop) {
            $varName = $assignment.Left.VariablePath.UserPath

            $results += [Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord]@{
                Message  = "Array '+=' operation on '\$$varName' inside loop causes O(n²) performance. Use [System.Collections.Generic.List[T]]::new() with .Add() method."
                Extent   = $assignment.Extent
                RuleName = 'PSAvoidArrayPlusEquals'
                Severity = 'Information'
            }
        }
    }

    return $results
}

#endregion

Export-ModuleMember -Function @(
    'Measure-UninitializedScriptVariable'
    'Measure-UnsafeMethodCall'
    'Measure-InconsistentReturnType'
    'Measure-MissingStrictMode'
    'Measure-ArrayAddUsage'
)
