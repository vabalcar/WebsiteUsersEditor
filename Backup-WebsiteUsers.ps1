#!/opt/microsoft/powershell/6/pwsh
Param (
    [string] $ConfigurationFile = 'Settings.json',
    [switch] $DryRun
)

. (Join-Path 'libs' 'WebsiteUsers.ps1') -ConfigurationFile $ConfigurationFile

$input | Test-WebsiteUser | Backup-WebsiteUser -DryRun:$DryRun