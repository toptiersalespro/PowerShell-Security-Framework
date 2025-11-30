#Requires -Version 7.5
#Requires -RunAsAdministrator
#Requires -Modules @{ ModuleName = 'Microsoft.PowerShell.Security'; ModuleVersion = '7.0.0' }
# cspell:ignore AMSI amsi Mimikatz sekurlsa

<#
.SYNOPSIS
    Threat Detection module for identifying malicious PowerShell activity.

.DESCRIPTION
    Production-grade security monitoring module providing:
    - AMSI bypass attempt detection
    - Suspicious script pattern analysis
    - Security evasion technique identification

    Designed for SOC integration with structured JSON logging and
    correlation IDs for SIEM ingestion.

.NOTES
    Module     : ThreatDetection
    Version    : 2.0.0
    Author     : Kyle (TopTierSalesPro)
    Compliance : TPRS v1.1 | 40 Laws Validated
    Reference  : PowerShell-Automation-and-Scripting-for-Cybersecurity (Packt)

    SECURITY NOTICE: Detection patterns are for DEFENSIVE purposes only.
    Misuse for bypass development violates acceptable use policy.

.LINK
    https://github.com/yourrepo/PowerShell-Security-Framework
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Module Constants

# [4.3] No magic numbers — all configurable constants
$script:ModuleConfig = @{
    MaxEventDefault     = 100
    MaxEventCeiling     = 10000
    CodeSnippetLength   = 200
    QueryTimeoutSeconds = 30
    LogPath             = Join-Path -Path $env:TEMP -ChildPath 'ThreatDetection'
}

# Risk level sort order for consistent prioritization
$script:RiskSortOrder = @{
    'Critical' = 1
    'High'     = 2
    'Medium'   = 3
    'Low'      = 4
    'Info'     = 5
}

# Initialize module-level trace ID to prevent uninitialized variable errors
$script:CurrentTraceId = ([guid]::NewGuid().ToString('N').Substring(0, 8))

# Threat detection patterns — primary source is ThreatPatterns.json
$patternFile = Join-Path -Path $PSScriptRoot -ChildPath 'ThreatPatterns.json'

if (Test-Path -Path $patternFile -PathType Leaf) {
    try {
        $script:ThreatPatterns = Get-Content -Path $patternFile -Raw |
            ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warning "Failed to load ThreatPatterns.json. Falling back to built-in patterns. Error: $($_.Exception.Message)"

        $script:ThreatPatterns = @(
            [PSCustomObject]@{ Name = 'AMSI Reference'; Pattern = 'amsi\.dll|AmsiScanBuffer|AmsiInitialize'; Risk = 'Critical'; Category = 'Evasion' }
            [PSCustomObject]@{ Name = 'Memory Manipulation'; Pattern = 'VirtualProtect|VirtualAlloc|WriteProcessMemory'; Risk = 'Critical'; Category = 'Injection' }
            [PSCustomObject]@{ Name = 'Mimikatz Indicators'; Pattern = 'mimikatz|sekurlsa|kerberos::'; Risk = 'Critical'; Category = 'CredTheft' }
            [PSCustomObject]@{ Name = 'Download Cradle'; Pattern = 'Invoke-WebRequest|Invoke-RestMethod|Net\.WebClient|DownloadString'; Risk = 'High'; Category = 'Delivery' }
            [PSCustomObject]@{ Name = 'Invoke-Expression'; Pattern = 'Invoke-Expression|IEX\s'; Risk = 'High'; Category = 'Execution' }
            [PSCustomObject]@{ Name = 'Reflection'; Pattern = 'System\.Reflection|GetMethod|Invoke\('; Risk = 'High'; Category = 'Evasion' }
            [PSCustomObject]@{ Name = 'Encoded Command'; Pattern = '-enc\s|-EncodedCommand'; Risk = 'High'; Category = 'Obfuscation' }
            [PSCustomObject]@{ Name = 'Base64 Decode'; Pattern = 'FromBase64String'; Risk = 'Medium'; Category = 'Obfuscation' }
            [PSCustomObject]@{ Name = 'Credential Access'; Pattern = 'Get-Credential|SecureString|NetworkCredential'; Risk = 'Medium'; Category = 'CredAccess' }
            [PSCustomObject]@{ Name = 'Hidden Window'; Pattern = '-WindowStyle\s+Hidden|-W\s+Hidden'; Risk = 'Medium'; Category = 'Stealth' }
        )
    }
} else {
    Write-Warning "ThreatPatterns.json not found. Using built-in default patterns."

    $script:ThreatPatterns = @(
        [PSCustomObject]@{ Name = 'AMSI Reference'; Pattern = 'amsi\.dll|AmsiScanBuffer|AmsiInitialize'; Risk = 'Critical'; Category = 'Evasion' }
        [PSCustomObject]@{ Name = 'Memory Manipulation'; Pattern = 'VirtualProtect|VirtualAlloc|WriteProcessMemory'; Risk = 'Critical'; Category = 'Injection' }
        [PSCustomObject]@{ Name = 'Mimikatz Indicators'; Pattern = 'mimikatz|sekurlsa|kerberos::'; Risk = 'Critical'; Category = 'CredTheft' }
        [PSCustomObject]@{ Name = 'Download Cradle'; Pattern = 'Invoke-WebRequest|Invoke-RestMethod|Net\.WebClient|DownloadString'; Risk = 'High'; Category = 'Delivery' }
        [PSCustomObject]@{ Name = 'Invoke-Expression'; Pattern = 'Invoke-Expression|IEX\s'; Risk = 'High'; Category = 'Execution' }
        [PSCustomObject]@{ Name = 'Reflection'; Pattern = 'System\.Reflection|GetMethod|Invoke\('; Risk = 'High'; Category = 'Evasion' }
        [PSCustomObject]@{ Name = 'Encoded Command'; Pattern = '-enc\s|-EncodedCommand'; Risk = 'High'; Category = 'Obfuscation' }
        [PSCustomObject]@{ Name = 'Base64 Decode'; Pattern = 'FromBase64String'; Risk = 'Medium'; Category = 'Obfuscation' }
        [PSCustomObject]@{ Name = 'Credential Access'; Pattern = 'Get-Credential|SecureString|NetworkCredential'; Risk = 'Medium'; Category = 'CredAccess' }
        [PSCustomObject]@{ Name = 'Hidden Window'; Pattern = '-WindowStyle\s+Hidden|-W\s+Hidden'; Risk = 'Medium'; Category = 'Stealth' }
    )
}

#endregion

#region Private Functions

function Write-ThreatLog {
    <#
    .SYNOPSIS
        Structured JSON logging for SIEM integration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'CRITICAL')]
        [string]$Level,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [string]$TraceId = $script:CurrentTraceId,

        [Parameter()]
        [hashtable]$Data = @{}
    )

    # Ensure log directory exists [6.3]
    if (-not (Test-Path -Path $script:ModuleConfig.LogPath -PathType Container)) {
        $null = New-Item -Path $script:ModuleConfig.LogPath -ItemType Directory -Force -ErrorAction Stop
    }

    $logFile = Join-Path -Path $script:ModuleConfig.LogPath -ChildPath "ThreatDetection_$(Get-Date -Format 'yyyyMMdd').jsonl"

    $logEntry = [ordered]@{
        timestamp = Get-Date -Format 'o'
        level     = $Level
        trace_id  = $TraceId
        message   = $Message
        computer  = $env:COMPUTERNAME
        user      = $env:USERNAME
        pid       = $PID
        module    = 'ThreatDetection'
    }

    # Merge additional data
    foreach ($key in $Data.Keys) {
        $logEntry[$key] = $Data[$key]
    }

    $jsonLine = $logEntry | ConvertTo-Json -Compress -Depth 5

    try {
        Add-Content -Path $logFile -Value $jsonLine -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Logging failed: $($_.Exception.Message)"
    }

    # Also output to appropriate stream
    switch ($Level) {
        'ERROR' { Write-Error -Message $Message }
        'CRITICAL' { Write-Error -Message $Message }
        'WARN' { Write-Warning -Message $Message }
        'DEBUG' { Write-Debug -Message $Message }
        default { Write-Verbose -Message $Message }
    }
}

function Get-RiskSortValue {
    <#
    .SYNOPSIS
        Returns numeric sort value for risk level.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$RiskLevel
    )

    if ($script:RiskSortOrder.ContainsKey($RiskLevel)) {
        return $script:RiskSortOrder[$RiskLevel]
    }

    return 99  # Unknown risks sort last
}

function Test-ValidRegexPattern {
    <#
    .SYNOPSIS
        Validates regex pattern is safe and compilable.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Pattern
    )

    try {
        $null = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Compiled)
        return $true
    } catch {
        Write-ThreatLog -Level 'WARN' -Message "Invalid regex pattern: $Pattern" -Data @{ error = $_.Exception.Message }
        return $false
    }
}

#endregion

#region Public Functions

function Get-AMSIDetectionEvents {
    <#
    .SYNOPSIS
        Retrieves AMSI detection events from Windows Defender logs.

    .DESCRIPTION
        Queries Windows Defender Operational log for AMSI-triggered
        detections (Event ID 1116). Returns structured objects suitable
        for SIEM ingestion with correlation IDs.

    .PARAMETER MaxEvents
        Maximum events to return. Range: 1-10000. Default: 100.

    .PARAMETER TraceId
        Correlation ID for log aggregation. Auto-generated if not provided.

    .EXAMPLE
        PS> Get-AMSIDetectionEvents -Verbose
        Retrieves up to 100 AMSI events with verbose output.

    .EXAMPLE
        PS> Get-AMSIDetectionEvents -MaxEvents 500 | Export-Csv -Path 'AMSI-Detections.csv' -NoTypeInformation
        Exports 500 events to CSV for analysis.

    .EXAMPLE
        PS> $traceId = [guid]::NewGuid().ToString('N').Substring(0,8)
        PS> Get-AMSIDetectionEvents -TraceId $traceId | ConvertTo-Json
        Retrieves events with custom trace ID for correlation.

    .OUTPUTS
        [PSCustomObject[]] Array of AMSI detection events with properties:
        - TimeCreated, EventId, Level, Message, ThreatName, TraceId
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Returns collection of detection events - plural is semantically correct')]
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$MaxEvents = $script:ModuleConfig.MaxEventDefault,

        [Parameter()]
        [ValidatePattern('^[a-f0-9]{8}$')]
        [string]$TraceId = ([guid]::NewGuid().ToString('N').Substring(0, 8))
    )

    begin {
        $script:CurrentTraceId = $TraceId

        Write-ThreatLog -Level 'INFO' -Message 'Get-AMSIDetectionEvents started' -Data @{
            max_events = $MaxEvents
        }

        # [5.1] Pre-allocate typed list for O(1) append
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    }

    process {
        try {
            # [6.1] ErrorAction Stop ensures catch block triggers
            $events = Get-WinEvent -LogName 'Microsoft-Windows-Windows Defender/Operational' `
                -MaxEvents $MaxEvents `
                -ErrorAction Stop |
                Where-Object { $_.Id -eq 1116 }

            foreach ($defenderEvent in $events) {
                $threatName = ($defenderEvent.Message -split "`n" |
                        Where-Object { $_ -match 'Name:' } |
                        Select-Object -First 1) -replace '.*Name:\s*', ''

                # Safely handle potentially null or empty threat names
                $safeThreatName = if ([string]::IsNullOrWhiteSpace($threatName)) {
                    'Unknown'
                } else {
                    $threatName.Trim()
                }

                $results.Add(
                    [PSCustomObject]@{
                        TimeCreated = $defenderEvent.TimeCreated
                        EventId     = $defenderEvent.Id
                        Level       = $defenderEvent.LevelDisplayName
                        Message     = $defenderEvent.Message
                        ThreatName  = $safeThreatName
                        TraceId     = $TraceId
                    }
                )
            }

            Write-ThreatLog -Level 'INFO' -Message 'AMSI events retrieved' -Data @{
                event_count = $results.Count
            }
        } catch {
            if ($_.Exception.Message -match 'No events were found') {
                Write-ThreatLog -Level 'INFO' -Message 'No AMSI detection events found'
                # Return empty typed collection, not @()
            } elseif ($_.Exception.Message -match 'Access is denied|privilege') {
                # [6.5] Actionable error message
                $errorMsg = 'Access denied querying Defender logs. Ensure script runs as Administrator with EventLog access.'

                Write-ThreatLog -Level 'ERROR' -Message $errorMsg -Data @{
                    exception_type = $_.Exception.GetType().FullName
                    original_error = $_.Exception.Message
                }

                throw $errorMsg
            } else {
                Write-ThreatLog -Level 'ERROR' -Message "Failed to query AMSI events: $($_.Exception.Message)" -Data @{
                    exception_type = $_.Exception.GetType().FullName
                    stack_trace    = $_.ScriptStackTrace
                }

                throw
            }
        }
    }

    end {
        Write-ThreatLog -Level 'DEBUG' -Message 'Get-AMSIDetectionEvents completed'
        return $results.ToArray()
    }
}

function Find-SuspiciousScriptPatterns {
    <#
    .SYNOPSIS
        Scans PowerShell script block logs for malicious patterns.

    .DESCRIPTION
        Analyzes executed PowerShell code from Windows Event Log (ID 4104)
        for patterns associated with malware, credential theft, and
        security evasion techniques.

        Results are sorted by risk level (Critical first) for triage.

    .PARAMETER MaxEvents
        Maximum script block events to analyze. Range: 1-10000. Default: 500.

    .PARAMETER MinimumRisk
        Filter results to this risk level or higher.
        Valid: Critical, High, Medium, Low

    .PARAMETER TraceId
        Correlation ID for log aggregation.

    .EXAMPLE
        PS> Find-SuspiciousScriptPatterns -MinimumRisk High
        Returns only High and Critical risk detections.

    .EXAMPLE
        PS> Find-SuspiciousScriptPatterns -MaxEvents 1000 | Group-Object -Property Category
        Groups detections by attack category.

    .EXAMPLE
        PS> Find-SuspiciousScriptPatterns | Where-Object { $_.RiskLevel -eq 'Critical' } | Format-Table -AutoSize
        Displays critical findings in table format.

    .OUTPUTS
        [PSCustomObject[]] Array of pattern matches with properties:
        - TimeCreated, PatternName, RiskLevel, Category, MatchedPattern, UserId, CodeSnippet, TraceId
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Scans for multiple suspicious patterns - plural is semantically correct')]
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$MaxEvents = 500,

        [Parameter()]
        [ValidateSet('Critical', 'High', 'Medium', 'Low')]
        [string]$MinimumRisk,

        [Parameter()]
        [ValidatePattern('^[a-f0-9]{8}$')]
        [string]$TraceId = ([guid]::NewGuid().ToString('N').Substring(0, 8))
    )

    begin {
        $script:CurrentTraceId = $TraceId

        Write-ThreatLog -Level 'INFO' -Message 'Find-SuspiciousScriptPatterns started' -Data @{
            max_events   = $MaxEvents
            minimum_risk = $MinimumRisk
        }

        # [5.1] Pre-allocate typed list
        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Pre-compile regex patterns for performance [5.3]
        $compiledPatterns = foreach ($p in $script:ThreatPatterns) {
            if (Test-ValidRegexPattern -Pattern $p.Pattern) {
                [PSCustomObject]@{
                    Name     = $p.Name
                    Regex    = [regex]::new(
                        $p.Pattern,
                        [System.Text.RegularExpressions.RegexOptions]::Compiled -bor
                        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
                    )
                    Risk     = $p.Risk
                    Category = $p.Category
                }
            }
        }

        # Determine risk filter threshold
        $riskThreshold = if ($MinimumRisk) {
            Get-RiskSortValue -RiskLevel $MinimumRisk
        } else {
            99
        }
    }

    process {
        # Query script block events
        $events = $null

        try {
            $filterHash = @{
                ProviderName = 'Microsoft-Windows-PowerShell'
                Id           = 4104
            }

            $events = Get-WinEvent -FilterHashtable $filterHash -MaxEvents $MaxEvents -ErrorAction Stop

            Write-ThreatLog -Level 'DEBUG' -Message "Retrieved $($events.Count) script block events"
        } catch {
            if ($_.Exception.Message -match 'No events were found') {
                Write-ThreatLog -Level 'INFO' -Message 'No script block events found'
                # Return empty array - results list is already initialized
            } elseif ($_.Exception.Message -match 'Access is denied') {
                $errorMsg = 'Access denied querying PowerShell logs. Run as Administrator.'

                Write-ThreatLog -Level 'ERROR' -Message $errorMsg
                throw $errorMsg
            } else {
                Write-ThreatLog -Level 'ERROR' -Message "Event query failed: $($_.Exception.Message)"
                throw
            }
        }

        # Analyze each event against patterns
        foreach ($scriptEvent in $events) {
            $code = $scriptEvent.Properties[2].Value

            if ([string]::IsNullOrWhiteSpace($code)) {
                continue
            }

            foreach ($pattern in $compiledPatterns) {
                # Skip if below risk threshold
                $patternRiskValue = Get-RiskSortValue -RiskLevel $pattern.Risk

                if ($patternRiskValue -gt $riskThreshold) {
                    continue
                }

                if ($pattern.Regex.IsMatch($code)) {
                    # Truncate code snippet safely
                    $snippetLength = $script:ModuleConfig.CodeSnippetLength

                    $snippet = if ($code.Length -gt $snippetLength) {
                        $code.Substring(0, $snippetLength) + '...'
                    } else {
                        $code
                    }

                    $results.Add(
                        [PSCustomObject]@{
                            TimeCreated    = $scriptEvent.TimeCreated
                            PatternName    = $pattern.Name
                            RiskLevel      = $pattern.Risk
                            Category       = $pattern.Category
                            MatchedPattern = $pattern.Regex.ToString()
                            UserId         = $scriptEvent.UserId
                            CodeSnippet    = $snippet
                            TraceId        = $TraceId
                        }
                    )

                    Write-ThreatLog -Level 'WARN' -Message "Suspicious pattern detected: $($pattern.Name)" -Data @{
                        risk_level = $pattern.Risk
                        category   = $pattern.Category
                        user_id    = $scriptEvent.UserId
                    }
                }
            }
        }
    }

    end {
        Write-ThreatLog -Level 'INFO' -Message 'Pattern scan completed' -Data @{
            detections_found = $results.Count
        }

        # Sort by risk (Critical first), then by time (newest first)
        $sorted = $results |
            Sort-Object -Property @{
                Expression = { Get-RiskSortValue -RiskLevel $_.RiskLevel }
            }, @{
                Expression = { $_.TimeCreated }
                Descending = $true
            }

        return @($sorted)
    }
}

function Test-AMSIStatus {
    <#
    .SYNOPSIS
        Validates AMSI is functioning and not bypassed.

    .DESCRIPTION
        Performs multiple checks to verify AMSI integrity:
        - Provider registration in registry
        - DLL presence and signature
        - Test scan capability

        Use for security posture assessment and bypass detection.

    .PARAMETER TraceId
        Correlation ID for log aggregation.

    .EXAMPLE
        PS> Test-AMSIStatus | Format-List
        Displays full AMSI status report.

    .EXAMPLE
        PS> if (-not (Test-AMSIStatus).AMSIEnabled) { Write-Warning 'AMSI may be compromised!' }
        Alerts if AMSI appears disabled.

    .OUTPUTS
        [PSCustomObject] Status object with properties:
        - AMSIEnabled, ProviderCount, TestResult, Details, Timestamp, TraceId
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [ValidatePattern('^[a-f0-9]{8}$')]
        [string]$TraceId = ([guid]::NewGuid().ToString('N').Substring(0, 8))
    )

    begin {
        $script:CurrentTraceId = $TraceId
        Write-ThreatLog -Level 'INFO' -Message 'Test-AMSIStatus started'
    }

    process {
        $result = [PSCustomObject]@{
            AMSIEnabled   = $false
            ProviderCount = 0
            DllPresent    = $false
            DllSigned     = $false
            TestResult    = 'Unknown'
            Details       = ''
            Timestamp     = Get-Date
            TraceId       = $TraceId
        }

        # Check 1: AMSI provider registration
        try {
            $providerPath = 'HKLM:\SOFTWARE\Microsoft\AMSI\Providers'

            if (Test-Path -Path $providerPath -PathType Container) {
                $providers = Get-ChildItem -Path $providerPath -ErrorAction Stop
                $result.ProviderCount = $providers.Count

                if ($providers.Count -gt 0) {
                    $result.AMSIEnabled = $true
                    $result.Details = "Found $($providers.Count) registered AMSI provider(s)"
                } else {
                    $result.Details = 'AMSI provider registry exists but no providers registered'
                }
            } else {
                $result.Details = 'AMSI provider registry key not found'
            }
        } catch {
            $result.Details = "Registry check failed: $($_.Exception.Message)"

            Write-ThreatLog -Level 'WARN' -Message 'AMSI registry check failed' -Data @{
                error = $_.Exception.Message
            }
        }

        # Check 2: AMSI DLL presence
        $amsiDllPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\amsi.dll'

        if (Test-Path -Path $amsiDllPath -PathType Leaf) {
            $result.DllPresent = $true

            # Check 3: DLL signature (Windows signed)
            try {
                $signature = Get-AuthenticodeSignature -FilePath $amsiDllPath -ErrorAction Stop
                $result.DllSigned = ($signature.Status -eq 'Valid')

                if (-not $result.DllSigned) {
                    Write-ThreatLog -Level 'CRITICAL' -Message 'AMSI DLL signature invalid - possible tampering!' -Data @{
                        signature_status = $signature.Status.ToString()
                    }
                }
            } catch {
                Write-ThreatLog -Level 'WARN' -Message 'Could not verify AMSI DLL signature'
            }
        } else {
            $result.Details += ' | amsi.dll not found in System32'

            Write-ThreatLog -Level 'CRITICAL' -Message 'amsi.dll missing from System32!'
        }

        # Final assessment
        $result.TestResult = if ($result.AMSIEnabled -and $result.DllPresent -and $result.DllSigned) {
            'Healthy'
        } elseif ($result.AMSIEnabled -and $result.DllPresent) {
            'Degraded'
        } else {
            'Compromised'
        }

        Write-ThreatLog -Level 'INFO' -Message "AMSI status: $($result.TestResult)" -Data @{
            amsi_enabled   = $result.AMSIEnabled
            provider_count = $result.ProviderCount
            dll_present    = $result.DllPresent
            dll_signed     = $result.DllSigned
        }
    }

    end {
        return $result
    }
}

#endregion

#region Module Export

Export-ModuleMember -Function @(
    'Get-AMSIDetectionEvents'
    'Find-SuspiciousScriptPatterns'
    'Test-AMSIStatus'
)

#endregion
