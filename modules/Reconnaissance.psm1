#Requires -Version 7.0
<#
.SYNOPSIS
    Reconnaissance module for security enumeration.
.DESCRIPTION
    Provides functions for enumerating local/AD users, groups, permissions,
    GPO ACLs, and other security-relevant information.
.NOTES
    Module: Reconnaissance
    Author: PowerShell Security Framework
    Based on: PowerShell-Automation-and-Scripting-for-Cybersecurity (Packt)
#>

function Get-LocalUsersAndGroups {
    <#
    .SYNOPSIS
        Enumerates all local groups and their members.
    .DESCRIPTION
        Retrieves all local groups and displays group membership information.
    .EXAMPLE
        Get-LocalUsersAndGroups | Where-Object { $_.GroupName -eq 'Administrators' }
    .OUTPUTS
        PSCustomObject with GroupName, Name, ObjectClass, PrincipalSource
    #>
    [CmdletBinding()]
    param()

    try {
        Get-LocalGroup -ErrorAction Stop | ForEach-Object {
            $groupName = $_.Name
            Get-LocalGroupMember -Group $_.Name -ErrorAction SilentlyContinue | ForEach-Object {
                [PSCustomObject]@{
                    GroupName = $groupName
                    Name = $_.Name
                    ObjectClass = $_.ObjectClass
                    PrincipalSource = $_.PrincipalSource
                    SID = $_.SID
                }
            }
        }
    }
    catch {
        Write-Error "Failed to enumerate local users/groups: $($_.Exception.Message)"
        throw
    }
}

function Get-ADUsersAndGroups {
    <#
    .SYNOPSIS
        Enumerates all AD groups and their members.
    .DESCRIPTION
        Retrieves all Active Directory groups and displays membership.
        Requires the ActiveDirectory module.
    .EXAMPLE
        Get-ADUsersAndGroups | Where-Object { $_.GroupName -eq 'Domain Admins' }
    .OUTPUTS
        PSCustomObject with GroupName, Name, SamAccountName, SID, ObjectClass
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Warning "ActiveDirectory module not available. Install RSAT or run on a domain controller."
        return
    }

    Import-Module ActiveDirectory -ErrorAction Stop

    Get-ADGroup -Filter * -ErrorAction Stop | ForEach-Object {
        $groupName = $_.SamAccountName
        Get-ADGroupMember -Identity $_.SamAccountName -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{
                GroupName = $groupName
                DistinguishedName = $_.distinguishedName
                Name = $_.name
                ObjectClass = $_.objectClass
                SamAccountName = $_.SamAccountName
                SID = $_.SID
            }
        }
    }
}

function Get-ADUsersAndGroupsWithAdsi {
    <#
    .SYNOPSIS
        Enumerates AD groups using ADSI (no module required).
    .DESCRIPTION
        Uses ADSI searcher to enumerate AD groups without requiring
        the ActiveDirectory module.
    .EXAMPLE
        Get-ADUsersAndGroupsWithAdsi | Export-Csv -Path "ADGroups.csv"
    .OUTPUTS
        PSCustomObject with GroupName, Name, SamAccountName, ObjectClass
    #>
    [CmdletBinding()]
    param()

    try {
        ([adsisearcher]"(objectClass=group)").FindAll() | ForEach-Object {
            $groupName = $_.Properties.samaccountname
            $members = $_.Properties.member

            if ($members) {
                foreach ($dn in $members) {
                    $member = ([adsisearcher]"(distinguishedName=$dn)").FindOne()
                    if ($member) {
                        [PSCustomObject]@{
                            GroupName = [string]$groupName
                            DistinguishedName = $dn
                            Name = [string]$member.Properties.name
                            ObjectClass = [string]$member.Properties.objectclass[-1]
                            SamAccountName = [string]$member.Properties.samaccountname
                        }
                    }
                }
            }
        }
    }
    catch {
        Write-Error "ADSI query failed: $($_.Exception.Message)"
        throw
    }
}

function Get-UserRightsAssignment {
    <#
    .SYNOPSIS
        Retrieves local user rights assignments using secedit.
    .DESCRIPTION
        Exports security policy and parses user rights assignments,
        resolving SIDs to account names.
    .PARAMETER ExportPath
        Path for temporary secedit export file.
    .EXAMPLE
        Get-UserRightsAssignment | Where-Object { $_.RightName -like '*Logon*' }
    .OUTPUTS
        PSCustomObject with RightName, Accounts, SID
    .NOTES
        Requires administrative privileges.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ExportPath = "$env:TEMP\secedit_$(Get-Date -Format 'yyyyMMddHHmmss').txt"
    )

    try {
        $null = Start-Process -FilePath secedit.exe -ArgumentList "/export /cfg `"$ExportPath`"" -Wait -NoNewWindow -PassThru

        Get-Content -Path $ExportPath -ErrorAction Stop | Where-Object { $_ -match "^Se" } | ForEach-Object {
            $parts = $_ -split "="
            $rightName = $parts[0].Trim()
            $sids = ($parts[1] -replace '\*', '').Trim() -split ","

            foreach ($sid in $sids) {
                $sid = $sid.Trim()
                $entityName = ""

                # Try to resolve SID
                try {
                    if ($sid -match '^S-1-') {
                        $objSID = New-Object System.Security.Principal.SecurityIdentifier($sid)
                        $entityName = $objSID.Translate([System.Security.Principal.NTAccount]).Value
                    }
                    else {
                        $entityName = $sid
                    }
                }
                catch {
                    $entityName = $sid
                }

                [PSCustomObject]@{
                    RightName = $rightName
                    Account = $entityName
                    SID = $sid
                }
            }
        }
    }
    finally {
        if (Test-Path -Path $ExportPath) {
            Remove-Item -Path $ExportPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-OuACLSecurity {
    <#
    .SYNOPSIS
        Retrieves ACL security for all Organizational Units.
    .DESCRIPTION
        Enumerates all OUs and their access control lists.
        Requires the ActiveDirectory module.
    .EXAMPLE
        Get-OuACLSecurity | Where-Object { $_.AccessControlType -eq 'Allow' }
    .OUTPUTS
        PSCustomObject with OU DN and ACL properties
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Warning "ActiveDirectory module not available."
        return
    }

    Import-Module ActiveDirectory -ErrorAction Stop

    Get-ADOrganizationalUnit -Filter * -ErrorAction Stop | ForEach-Object {
        $dn = $_.DistinguishedName
        (Get-Acl -Path "AD:\$dn" -ErrorAction SilentlyContinue).Access | ForEach-Object {
            [PSCustomObject]@{
                DistinguishedName = $dn
                ActiveDirectoryRights = $_.ActiveDirectoryRights
                AccessControlType = $_.AccessControlType
                IdentityReference = $_.IdentityReference
                IsInherited = $_.IsInherited
                InheritanceType = $_.InheritanceType
            }
        }
    }
}

function Get-GpoPermissions {
    <#
    .SYNOPSIS
        Retrieves permissions for all Group Policy Objects.
    .DESCRIPTION
        Enumerates all GPOs and their permission settings.
        Requires the GroupPolicy module.
    .EXAMPLE
        Get-GpoPermissions | Where-Object { $_.Permission -eq 'GpoEditDeleteModifySecurity' }
    .OUTPUTS
        PSCustomObject with GPO details and permissions
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
        Write-Warning "GroupPolicy module not available."
        return
    }

    Import-Module GroupPolicy -ErrorAction Stop

    Get-GPO -All -ErrorAction Stop | ForEach-Object {
        $gpo = $_
        Get-GPPermission -Guid $_.Id -All -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{
                DisplayName = $gpo.DisplayName
                GpoId = $gpo.Id
                Owner = $gpo.Owner
                GpoStatus = $gpo.GpoStatus
                CreationTime = $gpo.CreationTime
                ModificationTime = $gpo.ModificationTime
                Trustee = $_.Trustee.Name
                TrusteeType = $_.TrusteeType
                Permission = $_.Permission
                Inherited = $_.Inherited
            }
        }
    }
}

function Get-CimNamespace {
    <#
    .SYNOPSIS
        Enumerates WMI/CIM namespaces.
    .DESCRIPTION
        Recursively enumerates CIM namespaces for security analysis.
    .PARAMETER Namespace
        Starting namespace. Default is 'root'.
    .PARAMETER Recurse
        Recursively enumerate child namespaces.
    .EXAMPLE
        Get-CimNamespace -Namespace 'root' -Recurse
    .OUTPUTS
        String namespace paths
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Namespace = 'root',

        [Parameter()]
        [switch]$Recurse
    )

    Get-CimInstance -Namespace $Namespace -ClassName '__NAMESPACE' -ErrorAction SilentlyContinue | ForEach-Object {
        $childNs = "$Namespace\$($_.Name)"
        Write-Output $childNs
        if ($Recurse) {
            Get-CimNamespace -Namespace $childNs -Recurse
        }
    }
}

Export-ModuleMember -Function Get-LocalUsersAndGroups, Get-ADUsersAndGroups, Get-ADUsersAndGroupsWithAdsi,
    Get-UserRightsAssignment, Get-OuACLSecurity, Get-GpoPermissions, Get-CimNamespace
