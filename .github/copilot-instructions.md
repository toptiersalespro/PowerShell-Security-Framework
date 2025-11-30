# GitHub Copilot Instructions - PowerShell Security Framework

## Primary Reference
**READ FIRST**: `docs/CANONICAL-AI-INSTRUCTION-SET.md`

## Quick Rules for PowerShell Code Generation

### The 3 Deadly Sins (Zero Tolerance)

1. **Script Variables in Parameter Defaults**
   - ❌ BAD: `function Foo { param($X = $script:Y) }` then later `$script:Y = 'val'`
   - ✅ GOOD: `$script:Y = 'val'` FIRST, then `function Foo { param($X = $script:Y) }`

2. **Method Calls Without Null Checks**
   - ❌ BAD: `$name.Trim()`
   - ✅ GOOD: `if ([string]::IsNullOrWhiteSpace($name)) { 'Unknown' } else { $name.Trim() }`

3. **Inconsistent Return Types**
   - ❌ BAD: `catch { return @() }` mixed with `return $list.ToArray()`
   - ✅ GOOD: Always return from `end{}` block: `return $results.ToArray()`

### Code Completion Patterns

When completing PowerShell functions:

```powershell
function Verb-Noun {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Parameter
    )

    begin {
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        try {
            # Safe null handling
            $safe = if ([string]::IsNullOrWhiteSpace($raw)) { 'default' } else { $raw.Trim() }

            $results.Add([PSCustomObject]@{ Data = $safe })
        } catch {
            Write-Error $_
        }
    }

    end {
        return $results.ToArray()
    }
}
```

### Module Structure

```powershell
#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# FIRST: Initialize script variables
$script:TraceId = ([guid]::NewGuid().ToString('N').Substring(0, 8))

# SECOND: Private functions
function Write-ModuleLog { }

# THIRD: Public functions
function Get-ModuleData { }

# FOURTH: Export
Export-ModuleMember -Function @('Get-ModuleData')
```

### Inline Suggestions

When suggesting code inline:
1. Prioritize null-safe patterns
2. Use typed collections
3. Include validation attributes
4. Follow begin/process/end pattern
5. Never suggest aliases or positional params

### Don't Suggest

- `Write-Host` (use `Write-Verbose` or `Write-Information`)
- `return @()` anywhere
- `$array += $item` in loops
- Method calls without null checks
- Functions without `[CmdletBinding()]`
- Parameters without validation

### Always Suggest

- `[string]::IsNullOrWhiteSpace()` checks
- `[System.Collections.Generic.List[T]]` for collections
- `[ValidateNotNullOrEmpty()]` on string parameters
- Complete comment-based help
- `Set-StrictMode -Version Latest`

## Context-Aware Rules

### When in `.psm1` files:
- Assume this is a module
- Initialize script variables at top
- Organize: constants → private → public → export
- Use `Export-ModuleMember` at end

### When in `.ps1` files:
- Assume this is a utility script
- Include entrypoint logic
- Support dot-sourcing

### When in `.Tests.ps1` files:
- Use Pester 5.x syntax
- Include BeforeAll/AfterAll
- Test both success and error paths
- Use `TestDrive:` for file operations

## Validation

Before suggesting any PowerShell code, verify:
- [ ] Script vars initialized before functions?
- [ ] String methods have null checks?
- [ ] Consistent return types?
- [ ] [CmdletBinding()] present?
- [ ] [OutputType()] declared?

## Learn More

- Canonical standard: `docs/CANONICAL-AI-INSTRUCTION-SET.md`
- Templates: `Templates/*.ps1`
- Examples: `docs/AI-TRAINING-QUICK-START.md`
