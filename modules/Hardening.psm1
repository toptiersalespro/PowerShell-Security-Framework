#Requires -Version 7.0
<#
.SYNOPSIS
    Hardening module for system security configuration.
.DESCRIPTION
    Provides functions for enabling security logging, configuring audit settings,
    and hardening Windows systems.
.NOTES
    Module: Hardening
    Author: PowerShell Security Framework
    Based on: PowerShell-Automation-and-Scripting-for-Cybersecurity (Packt)
#>

function Enable-PSTranscription {
    <#
    .SYNOPSIS
        Enables PowerShell transcription via registry.
    .DESCRIPTION
        Configures registry keys to enable PowerShell transcription logging,
        capturing all command input/output to transcript files.
    .PARAMETER OutputDirectory
        Directory where transcript files will be saved.
    .EXAMPLE
        Enable-PSTranscription -OutputDirectory "C:\Transcripts"
    .EXAMPLE
        Enable-PSTranscription -WhatIf
    .NOTES
        Requires administrative privileges.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$OutputDirectory = "C:\ProgramData\WindowsPowerShell\Transcripts"
    )

    $registryPath = "HKLM:\SOFTWARE\WOW6432Node\Policies\Microsoft\Windows\PowerShell\Transcription"

    if ($PSCmdlet.ShouldProcess($registryPath, "Enable PowerShell Transcription")) {
        try {
            if (-not (Test-Path -Path $registryPath)) {
                New-Item -Path $registryPath -Force -ErrorAction Stop | Out-Null
                Write-Verbose "Created registry path: $registryPath"
            }

            New-ItemProperty -Path $registryPath -Name "EnableTranscripting" -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
            New-ItemProperty -Path $registryPath -Name "EnableInvocationHeader" -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
            New-ItemProperty -Path $registryPath -Name "OutputDirectory" -PropertyType String -Value $OutputDirectory -Force -ErrorAction Stop | Out-Null

            Write-Verbose "Transcription enabled. Output: $OutputDirectory"

            [PSCustomObject]@{
                Success         = $true
                OutputDirectory = $OutputDirectory
                RegistryPath    = $registryPath
            }
        } catch {
            Write-Error "Failed to enable transcription: $($_.Exception.Message)"
            throw
        }
    }
}

function Enable-ScriptBlockLogging {
    <#
    .SYNOPSIS
        Enables PowerShell script block logging via registry.
    .DESCRIPTION
        Configures registry to enable script block logging (Event ID 4104),
        which captures executed PowerShell code for security monitoring.
    .EXAMPLE
        Enable-ScriptBlockLogging
    .NOTES
        Requires administrative privileges.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"

    if ($PSCmdlet.ShouldProcess($registryPath, "Enable Script Block Logging")) {
        try {
            if (-not (Test-Path -Path $registryPath)) {
                New-Item -Path $registryPath -Force -ErrorAction Stop | Out-Null
            }
            Set-ItemProperty -Path $registryPath -Name "EnableScriptBlockLogging" -Value 1 -Force -ErrorAction Stop

            Write-Verbose "Script block logging enabled"
            [PSCustomObject]@{ Success = $true; RegistryPath = $registryPath }
        } catch {
            Write-Error "Failed to enable script block logging: $($_.Exception.Message)"
            throw
        }
    }
}

Export-ModuleMember -Function Enable-PSTranscription, Enable-ScriptBlockLogging
