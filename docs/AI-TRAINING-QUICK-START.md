# AI Training Guide: PowerShell Module Development

## 🎯 For AI Models: Read This First

When generating PowerShell module code, you MUST follow these rules to avoid the 3 critical failure patterns.

---

## The 3 Deadly Sins (What Causes 90% of Bugs)

### ❌ SIN #1: Uninitialized Script Variables in Defaults

**WRONG:**
```powershell
function Write-Log {
    param(
        [string]$TraceId = $script:CurrentTraceId  # ❌ EVALUATED AT MODULE LOAD
    )
}

# Later in file...
$script:CurrentTraceId = [guid]::NewGuid()  # ⚠️ TOO LATE!
```

**RIGHT:**
```powershell
# AT THE TOP OF THE MODULE, BEFORE ANY FUNCTIONS:
$script:CurrentTraceId = ([guid]::NewGuid().ToString('N').Substring(0, 8))

function Write-Log {
    param(
        [string]$TraceId = $script:CurrentTraceId  # ✅ NOW IT WORKS
    )
}
```

**WHY IT MATTERS:**
- PowerShell compiles function parameter defaults ONCE at module load
- If variable is uninitialized at that moment, it captures `$null` forever
- Every function call uses that captured `$null` value
- StrictMode doesn't catch this because it's "technically" initialized (to `$null`)

---

### ❌ SIN #2: Calling Methods on Potentially Null Strings

**WRONG:**
```powershell
$threatName = ($event.Message -split "`n" |
    Where-Object { $_ -match 'Name:' } |
    Select-Object -First 1) -replace '.*Name:\s*', ''

$results.Add([PSCustomObject]@{
    ThreatName = $threatName.Trim()  # ❌ BOOM if $threatName is $null or empty
})
```

**RIGHT:**
```powershell
$threatName = ($event.Message -split "`n" |
    Where-Object { $_ -match 'Name:' } |
    Select-Object -First 1) -replace '.*Name:\s*', ''

# Safe null/empty handling
$safeThreatName = if ([string]::IsNullOrWhiteSpace($threatName)) {
    'Unknown'
} else {
    $threatName.Trim()
}

$results.Add([PSCustomObject]@{
    ThreatName = $safeThreatName  # ✅ SAFE
})
```

**WHY IT MATTERS:**
- `-replace` on empty strings can return `$null` (not empty string)
- Real-world data (event logs, APIs) is often malformed
- `.Trim()` on `$null` throws `MethodInvocationException`
- Crashes entire function, losing all previous results

**UNIVERSAL RULE:**
Before calling `.Trim()`, `.ToUpper()`, `.Replace()`, etc., ALWAYS check:
```powershell
if ([string]::IsNullOrWhiteSpace($variable)) { /* handle it */ }
```

---

### ❌ SIN #3: Inconsistent Return Types

**WRONG:**
```powershell
function Get-Results {
    [OutputType([PSCustomObject[]])]
    param()

    begin {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        try {
            # ... collect results ...
        } catch {
            return @()  # ❌ WRONG TYPE (Object[] vs PSCustomObject[])
        }
    }

    end {
        return $results.ToArray()  # ✅ RIGHT TYPE
    }
}
```

**RIGHT:**
```powershell
function Get-Results {
    [OutputType([PSCustomObject[]])]
    param()

    begin {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        try {
            # ... collect results ...
        } catch {
            # Don't return here - let end block handle it
            Write-Error $_
        }
    }

    end {
        # ALWAYS return same type (even if empty)
        return $results.ToArray()  # ✅ CONSISTENT
    }
}
```

**WHY IT MATTERS:**
- `@()` returns `Object[]` (untyped)
- `$list.ToArray()` returns `PSCustomObject[]` (typed)
- SIEM/JSON serialization breaks on type mismatches
- `-is [PSCustomObject[]]` checks fail intermittently
- Downstream scripts silently lose data

**UNIVERSAL RULE:**
- Declare result collection in `begin {}`
- Never use `return @()` in error paths
- Always return `$results.ToArray()` from `end {}` block

---

## ✅ The Golden Template (Copy-Paste This)

```powershell
#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Module Constants

# ✅ CRITICAL: Initialize ALL script-scoped variables FIRST
$script:CurrentTraceId = ([guid]::NewGuid().ToString('N').Substring(0, 8))
$script:ModuleConfig = @{
    MaxRetries = 3
}

#endregion

function Verb-Noun {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]  # ✅ Declare output type
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Parameter,

        [Parameter()]
        [string]$TraceId = $script:CurrentTraceId  # ✅ Safe now
    )

    begin {
        Write-Verbose "[$TraceId] Starting Verb-Noun"

        # ✅ Use typed collections for performance
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        try {
            # Get data (might be null/empty)
            $rawData = Get-SomeData

            # ✅ ALWAYS check before calling methods
            $safeData = if ([string]::IsNullOrWhiteSpace($rawData)) {
                'DefaultValue'
            } else {
                $rawData.Trim()
            }

            $results.Add(
                [PSCustomObject]@{
                    Data    = $safeData
                    TraceId = $TraceId
                }
            )
        }
        catch {
            Write-Error "Processing failed: $($_.Exception.Message)"
            # ✅ DON'T return here - let end block handle it
        }
    }

    end {
        Write-Verbose "[$TraceId] Completed with $($results.Count) results"

        # ✅ ALWAYS return same type
        return $results.ToArray()
    }
}
```

---

## 🤖 AI Prompt Template (For Humans to Use)

When asking AI to generate PowerShell modules, use this prompt:

```
Generate a production-grade PowerShell module with these MANDATORY requirements:

1. INITIALIZATION ORDER:
   - Set-StrictMode -Version Latest at the top
   - Initialize ALL $script: variables BEFORE function declarations
   - Never use uninitialized variables in parameter defaults

2. NULL SAFETY:
   - Use [string]::IsNullOrWhiteSpace() before calling .Trim(), .ToUpper(), etc.
   - Provide default values for all potentially null strings
   - Never assume external data (event logs, APIs) is well-formed

3. TYPE CONSISTENCY:
   - Use [System.Collections.Generic.List[PSCustomObject]] for collections
   - Declare [OutputType()] on all functions
   - NEVER use @() in error paths - always return $results.ToArray()

4. ERROR HANDLING:
   - $ErrorActionPreference = 'Stop'
   - Try-catch in process block, but don't return from catch
   - Log errors with structured data (exception type, stack trace)

5. TESTING:
   - Include Pester tests for BOTH success AND error paths
   - Test with null/empty inputs
   - Verify return type consistency

Follow the template in docs/AI-TRAINING-QUICK-START.md exactly.
```

---

## 🔧 Automated Validation (Setup Once)

To prevent these issues automatically:

### 1. Install Tools
```powershell
.\.vscode\scripts\Install-DevelopmentTools.ps1
```

### 2. Use VSCode Tasks (Press `Ctrl+Shift+B`)
- **🔍 Validate PowerShell Module (Full)** - Complete validation
- **⚡ Quick Syntax Check** - Fast syntax-only check
- **🛡️ PSScriptAnalyzer** - Security & style analysis
- **🔬 Check Module Initialization Order** - Detects the 3 sins

### 3. Pre-Commit Hook (Auto-runs on `git commit`)
Blocks commits if critical issues found. Located at: `.githooks/pre-commit`

---

## 📊 Quick Reference: Before/After

### Before (Broken Code)
```powershell
function Get-Events {
    param([string]$Id = $script:EventId)  # ❌ Not initialized yet

    $events = Get-WinEvent
    $name = $events[0].Message.Trim()     # ❌ Might be null

    if ($error) { return @() }            # ❌ Wrong type
    return $events
}

$script:EventId = 'default'               # ❌ TOO LATE!
```

**Problems:**
1. `$script:EventId` is `$null` in parameter default
2. `.Trim()` crashes if Message is null
3. Returns `Object[]` on error, but collection on success

### After (Fixed Code)
```powershell
$script:EventId = 'default'               # ✅ FIRST!

function Get-Events {
    [OutputType([PSCustomObject[]])]
    param([string]$Id = $script:EventId)  # ✅ Now safe

    begin {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        try {
            $events = Get-WinEvent

            foreach ($event in $events) {
                $safeName = if ([string]::IsNullOrWhiteSpace($event.Message)) {
                    'Unknown'
                } else {
                    $event.Message.Trim()  # ✅ Safe
                }

                $results.Add([PSCustomObject]@{ Name = $safeName })
            }
        } catch {
            Write-Error $_
        }
    }

    end {
        return $results.ToArray()          # ✅ Consistent type
    }
}
```

---

## 🚨 Detection Checklist (Code Review)

Use this checklist when reviewing PowerShell modules:

- [ ] `Set-StrictMode -Version Latest` at top of file?
- [ ] All `$script:` variables initialized before functions?
- [ ] No method calls (`.Trim()`, `.Replace()`, etc.) without null checks?
- [ ] `[OutputType()]` attribute on all functions?
- [ ] Collections use `[System.Collections.Generic.List[T]]`?
- [ ] No `@()` returns in error paths?
- [ ] All end blocks return `.ToArray()` or consistent type?
- [ ] Pester tests exist for error paths?

---

## 📚 Additional Resources

- **Full Root Cause Analysis**: [AI-TRAINING-ROOT-CAUSE-ANALYSIS.md](./AI-TRAINING-ROOT-CAUSE-ANALYSIS.md)
- **Custom PSScriptAnalyzer Rules**: `.vscode/scripts/PSScriptAnalyzerCustomRules.psm1`
- **Validation Script**: `.vscode/scripts/Test-ModuleInitialization.ps1`
- **VSCode Snippets**: Type `func-safe` in .psm1 files

---

## 💡 Key Insight for AI Models

**The fundamental problem**: PowerShell's module loading is NOT sequential execution.

**What you think happens**:
1. Line 1 runs
2. Line 2 runs
3. Functions become available
4. Line 50 runs

**What actually happens**:
1. **PARSE PHASE**: Entire file parsed, function defaults compiled
2. **COMPILE PHASE**: Parameter defaults evaluated (variables must exist NOW)
3. **EXECUTION PHASE**: Script-level code runs top-to-bottom
4. **RUNTIME PHASE**: Functions callable

This is why initialization order matters - defaults are "baked in" during COMPILE phase, before EXECUTION phase sets variables.

**Train on this**: Always ask "Is this variable initialized before the PARSE phase completes?" If unsure, initialize at module level.
