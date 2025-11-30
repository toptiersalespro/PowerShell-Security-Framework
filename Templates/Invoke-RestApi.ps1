#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Generic REST API caller with config, logging, and error handling.

.DESCRIPTION
    Uses JSON config for base URL, headers, and API keys. Supports GET/POST/PUT/DELETE/PATCH with JSON body.
    Follows TPRS v1.1 and 40 Laws compliance.

.PARAMETER Endpoint
    Relative API endpoint, e.g. "/v1/items"

.PARAMETER Method
    HTTP method (GET, POST, PUT, DELETE, PATCH)

.PARAMETER BodyFile
    Optional path to JSON file used as request body.

.PARAMETER ConfigFile
    JSON config file containing BaseUrl and Headers.

.OUTPUTS
    [PSCustomObject] - API response object

.EXAMPLE
    .\Invoke-RestApi.ps1 -Endpoint "/v1/items" -Method GET -ConfigFile .\api-config.json
    Retrieves items from the API.

.EXAMPLE
    .\Invoke-RestApi.ps1 -Endpoint "/v1/items" -Method POST -BodyFile ".\new-item.json"
    Creates a new item using the JSON body file.

.NOTES
    Author: Kyle Thompson
    Version: 1.0.0
    Compliance: TPRS v1.1 | 40 Laws | Zero-Defect
#>

#region Module Constants

$script:LogPath = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
$script:LogFile = Join-Path -Path $script:LogPath -ChildPath 'restapi.log'

#endregion

#region Parameters

[CmdletBinding()]
[OutputType([PSCustomObject])]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Endpoint,

    [Parameter(Mandatory)]
    [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'PATCH')]
    [string]$Method,

    [Parameter()]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$BodyFile,

    [Parameter()]
    [string]$ConfigFile = '.\api-config.json'
)

#endregion

#region Private Functions

function Write-ApiLog {
    <#
    .SYNOPSIS
        Writes structured log entries.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "$timestamp [$Level] $Message"

    # Ensure log directory exists
    if (-not (Test-Path $script:LogPath)) {
        New-Item -ItemType Directory -Path $script:LogPath -Force | Out-Null
    }

    # Write to file (pipeline-friendly, no Write-Host)
    $entry | Out-File -FilePath $script:LogFile -Append -Encoding UTF8

    # Use appropriate stream
    switch ($Level) {
        'INFO'  { Write-Verbose $entry }
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Error $Message }
    }
}

function Import-ApiConfig {
    <#
    .SYNOPSIS
        Imports and validates API configuration.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-ApiLog -Message "Config file not found: $Path" -Level 'ERROR'
        return $null
    }

    try {
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop

        # SIN #2 FIX: Null check before method call
        if ([string]::IsNullOrWhiteSpace($content)) {
            Write-ApiLog -Message "Config file is empty: $Path" -Level 'ERROR'
            return $null
        }

        return $content | ConvertFrom-Json
    }
    catch {
        Write-ApiLog -Message "Failed to parse config file: $($_.Exception.Message)" -Level 'ERROR'
        return $null
    }
}

#endregion

#region Main Execution

# Load configuration
$config = Import-ApiConfig -Path $ConfigFile
if (-not $config) {
    exit 1
}

# SIN #2 FIX: Null check before TrimEnd
$baseUrl = if ([string]::IsNullOrWhiteSpace($config.BaseUrl)) {
    Write-ApiLog -Message "BaseUrl not defined in config. Add 'BaseUrl' property." -Level 'ERROR'
    exit 1
} else {
    $config.BaseUrl.TrimEnd('/')
}

# SIN #2 FIX: Null check before TrimStart
$safeEndpoint = if ([string]::IsNullOrWhiteSpace($Endpoint)) {
    ''
} else {
    $Endpoint.TrimStart('/')
}

$uri = "$baseUrl/$safeEndpoint"
Write-ApiLog -Message "Target URI: $uri (Method: $Method)"

# Build headers
$headers = @{}
if ($config.Headers) {
    $config.Headers.PSObject.Properties | ForEach-Object {
        $headers[$_.Name] = $_.Value
    }
}

# Optional auth token
if (-not [string]::IsNullOrWhiteSpace($config.ApiKey) -and
    -not [string]::IsNullOrWhiteSpace($config.ApiKeyHeaderName)) {
    $headers[$config.ApiKeyHeaderName] = $config.ApiKey
}

# Request body
$body = $null
if (-not [string]::IsNullOrWhiteSpace($BodyFile)) {
    if (-not (Test-Path $BodyFile)) {
        Write-ApiLog -Message "BodyFile not found: $BodyFile" -Level 'ERROR'
        exit 1
    }
    $body = Get-Content -Path $BodyFile -Raw -ErrorAction Stop
    Write-ApiLog -Message "Loaded body from $BodyFile"
}

# Execute request
try {
    $invokeParams = @{
        Uri         = $uri
        Method      = $Method
        Headers     = $headers
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace($body)) {
        $invokeParams['Body'] = $body
        $invokeParams['ContentType'] = 'application/json'
    }

    Write-ApiLog -Message 'Sending HTTP request...'
    $response = Invoke-RestMethod @invokeParams
    Write-ApiLog -Message 'Request completed successfully.'

    # Output response object for pipeline
    $response
}
catch {
    Write-ApiLog -Message "HTTP request failed: $($_.Exception.Message)" -Level 'ERROR'
    exit 1
}

#endregion
