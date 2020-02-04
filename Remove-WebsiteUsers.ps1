#!/opt/microsoft/powershell/6/pwsh
Param (
    [string] $ConfigurationFile = 'Settings.json'
)

. (Join-Path 'libs' 'WebsiteUsers.ps1') -ConfigurationFile $ConfigurationFile 

$input | Test-WebsiteUser | Remove-WebsiteUser
