#Requires -Version 7.4
<#
.SYNOPSIS
    Example handler script for Watch-Folder.ps1

.DESCRIPTION
    Called automatically when a file event occurs.

.PARAMETER FullPath
    Full path to the affected file.

.PARAMETER ChangeType
    Type of change (Created, Changed, Deleted, Renamed).
#>

[CmdletBinding()]
[OutputType([PSCustomObject])]
param (
    [Parameter(Mandatory)]
    [string]$FullPath,

    [Parameter(Mandatory)]
    [string]$ChangeType
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

Write-Information "[$timestamp] Handler executing: $ChangeType on $FullPath" -InformationAction Continue

# Add your custom processing logic here
switch ($ChangeType) {
    'Created' {
        # Example: Process new file
        Write-Information "  -> New file detected. Ready for processing." -InformationAction Continue
    }
    'Changed' {
        # Example: Re-process modified file
        Write-Information "  -> File modified. Consider re-processing." -InformationAction Continue
    }
    'Deleted' {
        # Example: Clean up references
        Write-Information "  -> File removed. Cleaning up references." -InformationAction Continue
    }
    'Renamed' {
        # Example: Update indexes
        Write-Information "  -> File renamed. Updating indexes." -InformationAction Continue
    }
}

# Return structured result
[PSCustomObject]@{
    Timestamp  = $timestamp
    FullPath   = $FullPath
    ChangeType = $ChangeType
    Processed  = $true
}
