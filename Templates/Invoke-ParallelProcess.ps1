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
        [string]$LogFile = '.\logs\parallel.log'
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

function Import-Config {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$LogFile = '.\logs\parallel.log'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-TemplateLog -Message "Config file not found at path: $Path" -Level 'WARN' -LogFile $LogFile
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-TemplateLog -Message "Config file at $Path is empty." -Level 'WARN' -LogFile $LogFile
            return $null
        }
        return $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-TemplateLog -Message "Failed to parse config at $Path. $_" -Level 'ERROR' -LogFile $LogFile
        return $null
    }
}

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter()]
    [int]$Throttle = 10,

    [Parameter()]
    [string]$ConfigFile = '.\parallel-config.json'
)

$logFile = '.\logs\parallel.log'

if (-not (Test-Path -LiteralPath $InputFile)) {
    Write-TemplateLog -Message "InputFile not found: $InputFile" -Level 'ERROR' -LogFile $logFile
    exit 1
}

$config = Import-Config -Path $ConfigFile -LogFile $logFile
if ($config -and $config.Throttle) {
    $Throttle = [int]$config.Throttle
}

$items = Get-Content -LiteralPath $InputFile -ErrorAction Stop |
         Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

Write-TemplateLog -Message "Loaded $($items.Count) item(s). Starting parallel processing with throttle $Throttle..." -LogFile $logFile

$results = $items | ForEach-Object -Parallel {
    $currentItem = $_

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $reachable = $false
    try {
        $reachable = Test-Connection -ComputerName $currentItem -Count 1 -Quiet -ErrorAction Stop
    }
    catch {
        $reachable = $false
    }

    [pscustomobject]@{
        Timestamp = $ts
        Target    = $currentItem
        Reachable = $reachable
    }

} -ThrottleLimit $Throttle

Write-TemplateLog -Message 'Parallel work complete. Writing results...' -LogFile $logFile

if ($results) {
    $outFile = '.\parallel-results.csv'
    $results | Sort-Object Target | Export-Csv -Path $outFile -NoTypeInformation
    Write-TemplateLog -Message "Results written to $outFile" -LogFile $logFile
} else {
    Write-TemplateLog -Message 'No results produced.' -Level 'WARN' -LogFile $logFile
}
