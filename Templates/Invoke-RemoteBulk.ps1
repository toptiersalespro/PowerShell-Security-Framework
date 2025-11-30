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
        [string]$LogFile = '.\logs\remote.log'
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
        [string]$LogFile = '.\logs\remote.log'
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

function Import-Credential {
    [CmdletBinding()]
    [OutputType([pscredential])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$LogFile = '.\logs\remote.log'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-TemplateLog -Message "Credential file not found: $Path" -Level 'WARN' -LogFile $LogFile
        return $null
    }

    try {
        return Import-Clixml -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        Write-TemplateLog -Message "Failed to import credential from $Path. $_" -Level 'ERROR' -LogFile $LogFile
        return $null
    }
}

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ComputerListFile,

    [Parameter(Mandatory = $true)]
    [string]$ScriptBlockFile,

    [Parameter()]
    [string]$CredentialFile,

    [Parameter()]
    [string]$ConfigFile = '.\remote-config.json'
)

$logFile = '.\logs\remote.log'

$config = Import-Config -Path $ConfigFile -LogFile $logFile
if ($config) {
    if ($config.ComputerListFile) { $ComputerListFile = $config.ComputerListFile }
    if ($config.ScriptBlockFile)  { $ScriptBlockFile  = $config.ScriptBlockFile }
    if ($config.CredentialFile)   { $CredentialFile   = $config.CredentialFile }
}

if (-not (Test-Path -LiteralPath $ComputerListFile)) {
    Write-TemplateLog -Message "ComputerListFile not found: $ComputerListFile" -Level 'ERROR' -LogFile $logFile
    exit 1
}

if (-not (Test-Path -LiteralPath $ScriptBlockFile)) {
    Write-TemplateLog -Message "ScriptBlockFile not found: $ScriptBlockFile" -Level 'ERROR' -LogFile $logFile
    exit 1
}

$computers = Get-Content -LiteralPath $ComputerListFile -ErrorAction Stop |
             Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

$scriptText = Get-Content -LiteralPath $ScriptBlockFile -Raw -ErrorAction Stop

Write-TemplateLog -Message "Loaded $($computers.Count) target(s)." -LogFile $logFile

$cred = $null
if ($CredentialFile) {
    $cred = Import-Credential -Path $CredentialFile -LogFile $logFile
    if (-not $cred) {
        Write-TemplateLog -Message 'Falling back to current user context (credential import failed).' -Level 'WARN' -LogFile $logFile
    }
}

$results = [System.Collections.Generic.List[psobject]]::new()

foreach ($comp in $computers) {
    Write-TemplateLog -Message "Running on $comp..." -LogFile $logFile
    $status       = 'Unknown'
    $errorMessage = $null
    $output       = $null

    try {
        $invokeParams = @{
            ComputerName = $comp
            ScriptBlock  = [scriptblock]::Create($scriptText)
            ErrorAction  = 'Stop'
        }
        if ($cred) {
            $invokeParams['Credential'] = $cred
        }

        $output = Invoke-Command @invokeParams
        $status = 'Success'
    }
    catch {
        $status       = 'Failed'
        $errorMessage = "$_"
        Write-TemplateLog -Message "Error on $comp`: $_" -Level 'ERROR' -LogFile $logFile
    }

    $null = $results.Add(
        [pscustomobject]@{
            Computer = $comp
            Status   = $status
            Error    = $errorMessage
            Output   = if ($output) { ($output -join '; ') } else { $null }
        }
    )
}

$outFile = '.\remote-results.csv'
$results | Export-Csv -Path $outFile -NoTypeInformation
Write-TemplateLog -Message "Results written to $outFile" -LogFile $logFile
