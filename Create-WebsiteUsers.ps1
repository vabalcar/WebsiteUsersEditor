#!/opt/microsoft/powershell/6/pwsh
Param (
    [string] $ConfigurationFile = 'Settings.json',
    [string] $GroupName = $(Get-Date -Format "yyyy")
)

. (Join-Path 'libs' 'WebsiteUsers.ps1') -ConfigurationFile $ConfigurationFile

$input | Test-WebsiteUser -Negate | Create-WebsiteUser -GroupName $GroupName
