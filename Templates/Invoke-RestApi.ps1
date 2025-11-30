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
        [string]$LogFile = '.\logs\restapi.log'
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
        [string]$LogFile = '.\logs\restapi.log'
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
[OutputType([psobject])]
param (
    [Parameter(Mandatory = $true)]
    [string]$Endpoint,

    [Parameter(Mandatory = $true)]
    [ValidateSet('GET','POST','PUT','DELETE','PATCH')]
    [string]$Method,

    [Parameter()]
    [string]$BodyFile,

    [Parameter()]
    [string]$ConfigFile = '.\api-config.json'
)

$logFile = '.\logs\restapi.log'

$config = Import-Config -Path $ConfigFile -LogFile $logFile
if (-not $config -or [string]::IsNullOrWhiteSpace($config.BaseUrl)) {
    Write-TemplateLog -Message "BaseUrl not defined in config '$ConfigFile'." -Level 'ERROR' -LogFile $logFile
    exit 1
}

$baseUrl = $config.BaseUrl
if (-not [string]::IsNullOrWhiteSpace($baseUrl)) {
    $baseUrl = $baseUrl.TrimEnd('/')
}

$endpointPart = if ([string]::IsNullOrWhiteSpace($Endpoint)) {
    ''
} else {
    $Endpoint.TrimStart('/')
}

$uri = if ($endpointPart) { "$baseUrl/$endpointPart" } else { $baseUrl }

Write-TemplateLog -Message "Target URI: $uri (Method: $Method)" -LogFile $logFile

# Build headers
$headers = @{}
if ($config.Headers) {
    $config.Headers.PSObject.Properties | ForEach-Object {
        $headers[$_.Name] = $_.Value
    }
}

if ($config.ApiKey -and $config.ApiKeyHeaderName) {
    $headers[$config.ApiKeyHeaderName] = $config.ApiKey
}

$body = $null
if ($BodyFile) {
    if (-not (Test-Path -LiteralPath $BodyFile)) {
        Write-TemplateLog -Message "BodyFile not found: $BodyFile" -Level 'ERROR' -LogFile $logFile
        exit 1
    }
    $body = Get-Content -LiteralPath $BodyFile -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($body)) {
        Write-TemplateLog -Message "Body file '$BodyFile' is empty." -Level 'WARN' -LogFile $logFile
        $body = $null
    } else {
        Write-TemplateLog -Message "Loaded body from $BodyFile" -LogFile $logFile
    }
}

try {
    $invokeParams = @{
        Uri         = $uri
        Method      = $Method
        Headers     = $headers
        ErrorAction = 'Stop'
    }

    if ($body) {
        $invokeParams['Body']        = $body
        $invokeParams['ContentType'] = 'application/json'
    }

    Write-TemplateLog -Message 'Sending HTTP request...' -LogFile $logFile
    $response = Invoke-RestMethod @invokeParams
    Write-TemplateLog -Message 'Request completed successfully.' -LogFile $logFile

    $response
}
catch {
    Write-TemplateLog -Message "HTTP request failed: $_" -Level 'ERROR' -LogFile $logFile
    exit 1
}
