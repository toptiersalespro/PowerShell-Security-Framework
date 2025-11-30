#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-TemplateLog {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO',

        [Parameter()]
        [string]$LogFile = '.\logs\watcher.log'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "$timestamp [$Level] $Message"

    switch ($Level) {
        'INFO'  { Write-Information -MessageData $entry -InformationAction Continue }
        'WARN'  { Write-Warning -Message $entry }
        'ERROR' { Write-Warning -Message "[ERROR] $entry" }
    }

    $logDir = Split-Path -Path $LogFile -Parent
    if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
        $null = New-Item -ItemType Directory -Path $logDir -Force
    }

    $entry | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter()]
    [string]$Filter = '*.*',

    [Parameter()]
    [string]$HandlerScript,

    [Parameter()]
    [int]$TimeoutSeconds = 0
)

$logFile = '.\logs\watcher.log'

if (-not (Test-Path -LiteralPath $Path)) {
    Write-TemplateLog -Message "Path does not exist: $Path" -Level 'ERROR' -LogFile $logFile
    exit 1
}

$hasHandler  = -not [string]::IsNullOrWhiteSpace($HandlerScript)
$handlerPath = $null

if ($hasHandler) {
    if (-not (Test-Path -LiteralPath $HandlerScript)) {
        Write-TemplateLog -Message "HandlerScript not found: $HandlerScript" -Level 'ERROR' -LogFile $logFile
        exit 1
    }
    $handlerPath = (Resolve-Path -LiteralPath $HandlerScript).Path
    Write-TemplateLog -Message "Using handler script: $handlerPath" -LogFile $logFile
} else {
    Write-TemplateLog -Message 'No handler script specified; events will only be logged.' -Level 'WARN' -LogFile $logFile
}

$fsw = [System.IO.FileSystemWatcher]::new()
$fsw.Path                  = (Resolve-Path -LiteralPath $Path).Path
$fsw.Filter                = $Filter
$fsw.IncludeSubdirectories = $true
$fsw.EnableRaisingEvents   = $true

Write-TemplateLog -Message \"Watching '\$(\$fsw.Path)' for filter '\$Filter'...\" -LogFile \$logFile

# Event action scriptblock - $source required by .NET event signature (PSScriptAnalyzer false positive)
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'source', Justification = 'Required by .NET event delegate signature')]
$action = {
    # $source is required by .NET event signature but not used
    param([object]$source, [System.IO.FileSystemEventArgs]$e)

    $msg = "File event: ChangeType=$($e.ChangeType); Name=$($e.Name); FullPath=$($e.FullPath)"
    Write-TemplateLog -Message $msg -LogFile $using:logFile

    if ($using:hasHandler -and $using:handlerPath) {
        try {
            & $using:handlerPath -FullPath $e.FullPath -ChangeType $e.ChangeType
        }
        catch {
            Write-TemplateLog -Message "HandlerScript error: $_" -Level 'ERROR' -LogFile $using:logFile
        }
    }
}

$createdReg = Register-ObjectEvent -InputObject $fsw -EventName Created -Action $action
$changedReg = Register-ObjectEvent -InputObject $fsw -EventName Changed -Action $action
$deletedReg = Register-ObjectEvent -InputObject $fsw -EventName Deleted -Action $action
$renamedReg = Register-ObjectEvent -InputObject $fsw -EventName Renamed -Action $action

try {
    if ($TimeoutSeconds -gt 0) {
        Write-TemplateLog -Message "Watcher will run for $TimeoutSeconds second(s)..." -LogFile $logFile
        Start-Sleep -Seconds $TimeoutSeconds
    } else {
        Write-TemplateLog -Message 'Press Ctrl+C to stop watching.' -LogFile $logFile
        while ($true) {
            Start-Sleep -Seconds 5
        }
    }
}
finally {
    Write-TemplateLog -Message 'Stopping watcher and unregistering events.' -LogFile $logFile

    $createdReg | Unregister-Event -ErrorAction SilentlyContinue
    $changedReg | Unregister-Event -ErrorAction SilentlyContinue
    $deletedReg | Unregister-Event -ErrorAction SilentlyContinue
    $renamedReg | Unregister-Event -ErrorAction SilentlyContinue

    $fsw.Dispose()
}
