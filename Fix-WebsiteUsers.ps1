#!/opt/microsoft/powershell/6/pwsh
Param (
    [string] $ConfigurationFile = 'Settings.json',
    [string] $GroupName = $(Get-Date -Format "yyyy"),
    [switch] $DryRun
)

. (Join-Path 'libs' 'WebsiteUsers.ps1') -ConfigurationFile $ConfigurationFile

$input | Test-WebsiteUser | Restore-WebsiteUser -GroupName $GroupName -DryRun:$DryRun
