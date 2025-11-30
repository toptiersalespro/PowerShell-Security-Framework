#Requires -Version 7.0
<#
.SYNOPSIS
    JEA Management module for Just Enough Administration.
.DESCRIPTION
    Provides functions for monitoring JEA sessions, analyzing virtual account
    logons, and managing JEA configurations.
.NOTES
    Module: JEAManagement
    Author: PowerShell Security Framework
    Based on: PowerShell-Automation-and-Scripting-for-Cybersecurity (Packt)
#>

function Get-VirtualAccountLogons {
    <#
    .SYNOPSIS
        Retrieves information about JEA virtual account logons.
    .DESCRIPTION
        Queries CIM for WinRM virtual account logon sessions, useful for
        monitoring JEA endpoint usage.
    .EXAMPLE
        Get-VirtualAccountLogons | Where-Object { $_.ActiveSession }
    .EXAMPLE
        Get-VirtualAccountLogons | Format-Table -AutoSize
    .OUTPUTS
        PSCustomObject with Name, Domain, LogonType, SessionStartTime, ActiveSession
    #>
    [CmdletBinding()]
    param()

    $LogonTypeMap = @{
        "0" = "Local System"
        "2" = "Interactive"
        "3" = "Network"
        "4" = "Batch"
        "5" = "Service"
        "7" = "Unlock"
        "8" = "NetworkCleartext"
        "9" = "NewCredentials"
        "10" = "RemoteInteractive"
        "11" = "CachedInteractive"
    }

    try {
        $loggedOnUsers = Get-CimInstance -ClassName Win32_LoggedOnUser -ErrorAction Stop |
            Where-Object { $_.Antecedent -like "*WinRM VA*" }

        $loggedOnUsers | ForEach-Object {
            $logonSession = Get-CimInstance -ClassName Win32_LogonSession -Filter "LogonId = $($_.Dependent.LogonId)" -ErrorAction SilentlyContinue

            # Active if domain is NOT "WinRM Virtual Users" (that indicates terminated)
            $isActive = $_.Antecedent.Domain -ne "WinRM Virtual Users"

            [PSCustomObject]@{
                Name = $_.Antecedent.Name
                Domain = $_.Antecedent.Domain
                LogonTypeNumber = $logonSession.LogonType
                LogonTypeName = $LogonTypeMap[([string]$logonSession.LogonType)]
                SessionStartTime = $logonSession.StartTime
                AuthenticationPackage = $logonSession.AuthenticationPackage
                LogonId = $_.Dependent.LogonId
                ActiveSession = $isActive
            }
        }
    }
    catch {
        Write-Error "Failed to query virtual account logons: $($_.Exception.Message)"
        throw
    }
}

function New-JEAConfiguration {
    <#
    .SYNOPSIS
        Creates a new JEA endpoint configuration.
    .DESCRIPTION
        Generates JEA role capability and session configuration files
        for a specified set of allowed commands.
    .PARAMETER Name
        Name for the JEA configuration.
    .PARAMETER Path
        Base path for module files.
    .PARAMETER AllowedCmdlets
        Array of cmdlets to allow in the JEA session.
    .PARAMETER AllowedUsers
        Users/groups allowed to connect.
    .PARAMETER Register
        Register the configuration immediately.
    .EXAMPLE
        New-JEAConfiguration -Name "ServerOps" -AllowedCmdlets "Restart-Service","Get-Process" -AllowedUsers "DOMAIN\Operators"
    .OUTPUTS
        PSCustomObject with configuration paths
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [string]$Path = "$env:ProgramFiles\WindowsPowerShell\Modules\JEA-$Name",

        [Parameter(Mandatory)]
        [string[]]$AllowedCmdlets,

        [Parameter(Mandatory)]
        [string[]]$AllowedUsers,

        [Parameter()]
        [switch]$Register
    )

    $rolePath = Join-Path -Path $Path -ChildPath "RoleCapabilities"

    if ($PSCmdlet.ShouldProcess($Path, "Create JEA Configuration")) {
        # Create directories
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
        New-Item -Path $rolePath -ItemType Directory -Force | Out-Null

        # Module manifest
        $manifestPath = Join-Path -Path $Path -ChildPath "$Name.psd1"
        New-ModuleManifest -Path $manifestPath

        # Role capability file
        $roleCapPath = Join-Path -Path $rolePath -ChildPath "$Name-RoleCapability.psrc"
        $roleParams = @{
            Path = $roleCapPath
            Author = $env:USERNAME
            VisibleCmdlets = $AllowedCmdlets
            VisibleFunctions = 'TabExpansion2'
        }
        New-PSRoleCapabilityFile @roleParams

        # Session configuration file
        $sessionConfigPath = Join-Path -Path $Path -ChildPath "$Name-SessionConfig.pssc"
        $roleDefinitions = @{}
        foreach ($user in $AllowedUsers) {
            $roleDefinitions[$user] = @{ RoleCapabilities = "$Name-RoleCapability" }
        }

        $sessionParams = @{
            Path = $sessionConfigPath
            SessionType = 'RestrictedRemoteServer'
            RunAsVirtualAccount = $true
            RoleDefinitions = $roleDefinitions
        }
        New-PSSessionConfigurationFile @sessionParams

        # Register if requested
        if ($Register) {
            Register-PSSessionConfiguration -Name $Name -Path $sessionConfigPath -Force
            Restart-Service -Name WinRM
        }

        [PSCustomObject]@{
            Name = $Name
            ModulePath = $Path
            RoleCapabilityFile = $roleCapPath
            SessionConfigFile = $sessionConfigPath
            Registered = $Register
        }
    }
}

function Get-JEAEndpoints {
    <#
    .SYNOPSIS
        Lists all registered JEA endpoints.
    .DESCRIPTION
        Retrieves all PowerShell session configurations that use
        virtual accounts (JEA endpoints).
    .EXAMPLE
        Get-JEAEndpoints
    .OUTPUTS
        PSSessionConfiguration objects for JEA endpoints
    #>
    [CmdletBinding()]
    param()

    Get-PSSessionConfiguration | Where-Object {
        $_.RunAsVirtualAccount -eq $true -or
        $_.RunAsVirtualAccountGroups -ne $null
    } | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Name
            Permission = $_.Permission
            RunAsVirtualAccount = $_.RunAsVirtualAccount
            PSVersion = $_.PSVersion
            ConfigFilePath = $_.ConfigFilePath
        }
    }
}

Export-ModuleMember -Function Get-VirtualAccountLogons, New-JEAConfiguration, Get-JEAEndpoints
