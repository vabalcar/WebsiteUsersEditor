#!/opt/microsoft/powershell/6/pwsh

<#
.SYNOPSIS
Backups website users on the server.

.PARAMETER ConfigurationFile
A configuration file to load; "Settings.json" is the default.

.PARAMETER DryRun
If set, nothing will be created and only output messages will be shown.

.INPUTS
List of website users to backup in a user per line format

.EXAMPLE
Command
./Remove-WebsiteUsers.ps1 < usersLists/group-2020.txt
backups users from the "usersLists/group-2020.txt" file by the "Settings.json" configuration file.
#>

Param (
    [string] $ConfigurationFile = 'Settings.json',
    [switch] $DryRun
)

. (Join-Path 'libs' 'WebsiteUsers.ps1') -ConfigurationFile $ConfigurationFile

$input | Test-WebsiteUser | Backup-WebsiteUser -DryRun:$DryRun