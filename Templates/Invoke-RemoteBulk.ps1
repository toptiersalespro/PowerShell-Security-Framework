#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Bulk remote execution template.

.DESCRIPTION
    Reads a list of computers and runs a script block on each.
    Captures success/failure and writes results to CSV.
    Uses typed collections for O(1) performance.
    Follows TPRS v1.1 and 40 Laws compliance.

.PARAMETER ComputerListFile
    Path to a file with one computer name per line.

.PARAMETER ScriptBlockFile
    Path to a .ps1 file containing the script block to run remotely.

.PARAMETER CredentialFile
    Optional path to an exported credential (CLIXML).

.PARAMETER ConfigFile
    Optional JSON config.

.OUTPUTS
    [PSCustomObject[]] - Array of execution results per computer

.EXAMPLE
    .\Invoke-RemoteBulk.ps1 -ComputerListFile .\servers.txt -ScriptBlockFile .\check-service.ps1
    Runs the script on all servers listed.

.EXAMPLE
    .\Invoke-RemoteBulk.ps1 -ComputerListFile .\servers.txt -ScriptBlockFile .\check-service.ps1 -CredentialFile .\admin.cred
    Runs with specified credentials.

.NOTES
    Author: Kyle Thompson
    Version: 1.0.0
    Compliance: TPRS v1.1 | 40 Laws | Zero-Defect
#>

#region Module Constants

$script:LogPath = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
$script:LogFile = Join-Path -Path $script:LogPath -ChildPath 'remote.log'

#endregion

#region Parameters

[CmdletBinding()]
[OutputType([PSCustomObject[]])]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ComputerListFile,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$ScriptBlockFile,

    [Parameter()]
    [string]$CredentialFile,

    [Parameter()]
    [string]$ConfigFile = '.\remote-config.json'
)

#endregion

#region Private Functions

function Write-RemoteLog {
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

    if (-not (Test-Path $script:LogPath)) {
        New-Item -ItemType Directory -Path $script:LogPath -Force | Out-Null
    }

    $entry | Out-File -FilePath $script:LogFile -Append -Encoding UTF8

    switch ($Level) {
        'INFO'  { Write-Verbose $entry }
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Error $Message }
    }
}

function Import-RemoteConfig {
    <#
    .SYNOPSIS
        Imports and validates configuration.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    try {
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) {
            return $null
        }
        return $content | ConvertFrom-Json
    }
    catch {
        Write-RemoteLog -Message "Failed to parse config: $($_.Exception.Message)" -Level 'ERROR'
        return $null
    }
}

function Import-StoredCredential {
    <#
    .SYNOPSIS
        Safely imports a stored credential.
    #>
    [CmdletBinding()]
    [OutputType([PSCredential])]
    param (
        [Parameter()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if (-not (Test-Path $Path)) {
        Write-RemoteLog -Message "Credential file not found: $Path" -Level 'WARN'
        return $null
    }

    try {
        return Import-Clixml -Path $Path -ErrorAction Stop
    }
    catch {
        Write-RemoteLog -Message "Failed to import credential: $($_.Exception.Message)" -Level 'ERROR'
        return $null
    }
}

#endregion

#region Main Execution

# Merge config
$config = Import-RemoteConfig -Path $ConfigFile
if ($config) {
    if (-not [string]::IsNullOrWhiteSpace($config.ComputerListFile)) { $ComputerListFile = $config.ComputerListFile }
    if (-not [string]::IsNullOrWhiteSpace($config.ScriptBlockFile)) { $ScriptBlockFile = $config.ScriptBlockFile }
    if (-not [string]::IsNullOrWhiteSpace($config.CredentialFile)) { $CredentialFile = $config.CredentialFile }
}

# Load computers with null-safe filtering
$rawComputers = Get-Content -Path $ComputerListFile -ErrorAction Stop
$computers = $rawComputers | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_)
} | ForEach-Object {
    $_.Trim()
}

if ($computers.Count -eq 0) {
    Write-RemoteLog -Message 'No valid computers found in list.' -Level 'WARN'
    exit 0
}

# Load script
$scriptText = Get-Content -Path $ScriptBlockFile -Raw -ErrorAction Stop
if ([string]::IsNullOrWhiteSpace($scriptText)) {
    Write-RemoteLog -Message 'ScriptBlockFile is empty.' -Level 'ERROR'
    exit 1
}

Write-RemoteLog -Message "Loaded $($computers.Count) target(s)."

# Load credential
$cred = Import-StoredCredential -Path $CredentialFile
if (-not $cred) {
    Write-RemoteLog -Message 'No credential loaded. Using current user context.' -Level 'WARN'
}

# FIX: Use typed List instead of @() += (O(n²) anti-pattern)
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($comp in $computers) {
    Write-RemoteLog -Message "Running on $comp..."

    $status = 'Unknown'
    $errorMessage = $null
    $output = $null

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
        $status = 'Failed'
        $errorMessage = $_.Exception.Message
        Write-RemoteLog -Message "Error on ${comp}: $errorMessage" -Level 'ERROR'
    }

    # Safe output join with null check
    $outputString = if ($null -eq $output) {
        ''
    }
    elseif ($output -is [array]) {
        $output -join '; '
    }
    else {
        $output.ToString()
    }

    $results.Add([PSCustomObject]@{
        Computer  = $comp
        Status    = $status
        Error     = $errorMessage
        Output    = $outputString
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    })
}

$outFile = Join-Path -Path $PSScriptRoot -ChildPath 'remote-results.csv'
$results.ToArray() | Export-Csv -Path $outFile -NoTypeInformation
Write-RemoteLog -Message "Results written to $outFile"

# SIN #3 FIX: Consistent return type
$results.ToArray()

#endregion
