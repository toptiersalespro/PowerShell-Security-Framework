@{
    # PSScriptAnalyzer Settings for PowerShell Security Framework
    # Reference: https://github.com/PowerShell/PSScriptAnalyzer

    # Severity levels: Error, Warning, Information
    Severity = @('Error', 'Warning', 'Information')

    # Include default rules
    IncludeDefaultRules = $true

    # Exclude specific rules (if needed)
    ExcludeRules = @(
        # Uncomment to disable specific rules
        # 'PSUseSingularNouns'  # If you have valid plural function names
    )

    # Rule-specific settings
    Rules = @{
        # Enforce cmdlet naming conventions
        PSUseApprovedVerbs = @{
            Enable = $true
        }

        # Avoid using aliases
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }

        # Use consistent indentation
        PSUseConsistentIndentation = @{
            Enable          = $true
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind            = 'space'
        }

        # Use consistent whitespace
        PSUseConsistentWhitespace = @{
            Enable                          = $true
            CheckInnerBrace                 = $true
            CheckOpenBrace                  = $true
            CheckOpenParen                  = $true
            CheckOperator                   = $true
            CheckPipe                       = $true
            CheckPipeForRedundantWhitespace = $true
            CheckSeparator                  = $true
            CheckParameter                  = $false
        }

        # Align assignment statements
        PSAlignAssignmentStatement = @{
            Enable         = $true
            CheckHashtable = $true
        }

        # Use correct casing for cmdlets
        PSUseCorrectCasing = @{
            Enable = $true
        }

        # Avoid using positional parameters
        PSAvoidUsingPositionalParameters = @{
            Enable           = $true
            CommandAllowList = @()  # Add exceptions if needed
        }

        # Use declared parameters
        PSUseDeclaredVarsMoreThanAssignments = @{
            Enable = $true
        }

        # Security: Avoid using plain text passwords
        PSAvoidUsingPlainTextForPassword = @{
            Enable = $true
        }

        # Security: Avoid using ConvertTo-SecureString with plain text
        PSAvoidUsingConvertToSecureStringWithPlainText = @{
            Enable = $true
        }

        # Security: Avoid using -Force in production code
        PSAvoidUsingWMICmdlet = @{
            Enable = $true
        }

        # Performance: Avoid using += for arrays in loops
        PSAvoidUsingEmptyCatchBlock = @{
            Enable = $true
        }

        # Use parameter type constraints
        PSUseShouldProcessForStateChangingFunctions = @{
            Enable = $true
        }

        # Use OutputType attribute
        PSUseOutputTypeCorrectly = @{
            Enable = $true
        }

        # Use BOM encoding for PowerShell files
        PSUseBOMForUnicodeEncodedFile = @{
            Enable = $true
        }

        # Use literal path when possible
        PSUseLiteralInitializerForHashtable = @{
            Enable = $true
        }

        # Avoid using Invoke-Expression
        PSAvoidUsingInvokeExpression = @{
            Enable = $true
        }

        # Use process block for pipeline functions
        PSUseProcessBlockForPipelineCommand = @{
            Enable = $true
        }
    }

    # Custom rule paths (loaded from .vscode/scripts)
    CustomRulePath = @(
        '.\\.vscode\\scripts\\PSScriptAnalyzerCustomRules.psm1'
    )

    # Include/Exclude file patterns
    IncludeRules = @(
        'PS*'
    )
}
