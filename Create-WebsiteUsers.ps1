#!/opt/microsoft/powershell/6/pwsh

<#
.SYNOPSIS
Creates website users on the server.

.PARAMETER Group
A name of a group in which users have to be created; Current year is the default.

.PARAMETER ConfigurationFile
A configuration file to load; "Settings.json" is the default.

.PARAMETER DryRun
If set, nothing will be created and only output messages will be shown.

.INPUTS
List of website users to create in a user per line format

.EXAMPLE
Command
./Create-WebsiteUsers.ps1 < usersLists/group-2020.txt
creates users from the "usersLists/group-2020.txt" file in the group called "2020" by the "Settings.json" configuration file.

.EXAMPLE
Command
./Create-WebsiteUsers.ps1 -Group 'WebApps-2020' < usersLists/group-2020.txt
creates users from the "usersLists/group-2020.txt" file in the group called "WebApps-2020" by the "Settings.json" configuration file.
#>

Param (
    [string] $Group = $(Get-Date -Format "yyyy"),
    [string] $ConfigurationFile = 'Settings.json',
    [switch] $DryRun
)

. (Join-Path 'libs' 'WebsiteUsers.ps1') -ConfigurationFile $ConfigurationFile

$input | Test-WebsiteUser -Negate | New-WebsiteUser -Group $Group -DryRun:$DryRun
