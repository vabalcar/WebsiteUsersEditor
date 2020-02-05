<#
.SYNOPSIS
The library for batch managing website users in Virtualmin

.PARAMETER ConfigurationFile
A configuration file to load
#>

Param (
    [Parameter(Mandatory=$true)] [string] $ConfigurationFile
)

# Load configuration.
$config = Get-Content -Path $ConfigurationFile | ConvertFrom-Json

<#
.SYNOPSIS
Tests if a website user exists in a domain from a configuration.

.PARAMETER Negate
Negates the output.

.INPUTS
Name of the user to be tested.
#>
filter Test-WebsiteUser {
    Param(
        [switch] $Negate,
        [Parameter(ValueFromPipeline=$true)] [string] $Name
    )
    
    if ((([string](& virtualmin list-users --domain $config.domain --name-only --user $Name)).Length -gt 0) -xor $Negate) {
        $Name
    } elseif ($Negate) {
        "User $Name already exists at $($config.domain)!" | Out-Host
    } else {
        "User $Name doesn't exist at $($config.domain)!" | Out-Host
    }
}

<#
.SYNOPSIS
Tests if a supplied DB exists.

.PARAMETER Negate
Negates the output.

.INPUTS
Name of DB to be tested
#>
filter Test-DB {
    Param(
        [switch] $Negate,
        [Parameter(ValueFromPipeline=$true)] [string] $Name
    )
    
    $db = & mysqlshow | ForEach-Object { $_.Split(' ')[1] } | Select-Object -Skip 2 | Select-String -Pattern "^$Name$"
    if (($db -eq $Name) -xor $Negate) {
        $Name
    } elseif ($Negate) {
        "DB $Name already exists!" | Out-Host
    } else {
        "DB $Name does not exists!" | Out-Host
    }
}

<#
.SYNOPSIS
Creates an MYSQL-safe name from a potentially unsafe one.

.PARAMETER Name
Potentially unsafe name of a DB

.INPUTS
You cannot pipe objects to Get-DBName.

.OUTPUTS
Name of a DB based on given one
#>
function Get-DBName {
    Param (
        [Parameter(Mandatory=$true)] [string] $Name
    )
    
    process {
        return $Name -replace '[\.\\\/]', '_'
    }
}

<#
.SYNOPSIS
Retrieves a name of a group in which a user with a supplied name belongs.

.PARAMETER Name
The name of the user

.INPUTS
You cannot pipe objects to Get-Group.

.OUTPUTS
The name of the group in which the user with the supplied name belongs
#>
function Get-Group {
    Param (
        [Parameter(Mandatory=$true)] [string] $Name
    )
    
    process {
        $homedirEntry = & virtualmin list-users --domain seup.lnxserver.com --multiline --user $Name | Select-String -Pattern 'Home directory:'
        $homdirEntryStructured = $homedirEntry -Split '/'
        return $homdirEntryStructured[$homdirEntryStructured.Length - 2]
    }
}

<#
.SYNOPSIS
Creates Apache configuration for a user.

.PARAMETER Name
The name of the user

.PARAMETER HomeDir
The home dir of the user

.PARAMETER LocationBase
The path in the URL of the user's website

.INPUTS
You cannot pipe objects to Get-ApacheUserConfig.

.OUTPUTS
Apache configuration for a user
#>
function Get-ApacheUserConfig {
    Param(
        [Parameter(Mandatory=$true)] [string] $Name,
        [Parameter(Mandatory=$true)] [string] $HomeDir,
        [Parameter(Mandatory=$true)] [string] $LocationBase
    )

    return @"
<Directory "$HomeDir">
php_admin_value open_basedir "$HomeDir"
php_admin_value upload_tmp_dir "$HomeDir/.tmp"
</Directory>

Redirect "/$Name" "https://$($config.domain)/$LocationBase/$Name"
"@

}

<#
.SYNOPSIS
Creates a website user on the server.

.PARAMETER Group
A group in which the user has to be created

.PARAMETER Name
The name of the user

.PARAMETER DryRun
If set, nothing will be created and only output messages will be shown.

.INPUTS
You cannot pipe objects to New-WebsiteUser.

.OUTPUTS
Nothing
#>
function New-WebsiteUser {
    Param (
        [Parameter(Mandatory=$true)] [string] $Group,
        [Parameter(ValueFromPipeline=$true)] [string] $Name,
        [switch] $DryRun
    )
    
    begin {
        $usersCreated = 0
        if (!$DryRun) {
            $locationBase = Join-Path $config.websitesLocation $Group
            $homeDirBase = Join-Path $config.apacheServerDocumentRoot $locationBase
            
            # Create a group's dir iff necessary.
            if (!(Test-Path -PathType Container -Path $homeDirBase)) {
                New-Item -ItemType 'Directory' -Path $homeDirBase | Out-Null
                & chown -R "$($config.serverUser):$($config.serverGoup)" $homeDirBase
            }
        }
    }

    process {
        "Creating user $Name in group $Group..." | Out-Host
        if ($DryRun) { return }
        
        # Create a user's home dir structure.
        $homeDir = Join-Path $homeDirBase $Name
        if (!(Test-Path -PathType Container -Path $homeDir)) {
            New-Item -ItemType 'Directory' -Path $homeDir | Out-Null
        }
        if (!(Test-Path -PathType Container -Path "$homeDir/.tmp")) {
            New-Item -Force -ItemType Directory -Path "$homeDir/.tmp" | Out-Null
        }
        
        # Give ownership of the user's home dir to the server user.
        & chown -R "$($config.serverUser):$($config.serverGoup)" $homeDir
        
        # Create a user's database.
        $dbname = Get-DBName -Name $Name
        & virtualmin create-database --domain $config.domain --name $dbName --type mysql
        
        # Create the user itself.
        & virtualmin create-user --domain $config.domain --user $Name --pass $config.defaultUserPassword --ftp --noemail --mysql $dbName --web --home (Join-Path 'public_html' $locationBase $Name)

        # Create a user's Apache configuration.
        Get-ApacheUserConfig -Name $Name -HomeDir $homeDir -LocationBase $locationBase | Out-File -Path (Join-Path $config.apacheUsersSettings "$Name.conf")
        
        ++$usersCreated
    }
    
    end {
        # Restart Apache iff it's necessary.
        if ($usersCreated -gt 0) {
            & /etc/init.d/apache2 restart
        }
    }
}

<#
.SYNOPSIS
Removes a website user on the server.

.PARAMETER Name
The name of the user

.PARAMETER DryRun
If set, nothing will be removed and only output messages will be shown.

.INPUTS
You cannot pipe objects to Remove-WebsiteUser.

.OUTPUTS
Nothing
#>
function Remove-WebsiteUser {
    Param (
        [Parameter(ValueFromPipeline=$true)] [string] $Name,
        [switch] $DryRun
    )
    
    begin {
        $usersRemoved = 0
    }
    
    process {
        $group = Get-Group -Name $Name
        "Removing user $_ from group $group..." | Out-Host
        if ($DryRun) { return }

        # Remove the user's Apache configuration.
        Remove-Item -Force -Path (Join-Path $config.apacheUsersSettings "$Name.conf")

        # Remove user itself.
        & virtualmin delete-user --domain $config.domain --user $Name

        # Remove the user's database.
        $dbname = Get-DBName -Name $Name
        & virtualmin delete-database --domain $config.domain --name $dbName --type mysql

        # Remove the user's home dir.
        $homeDirBase = Join-Path $config.apacheServerDocumentRoot $config.websitesLocation $group
        $homeDir = Join-Path $homeDirBase $Name
        if (Test-Path -PathType Container -Path $homeDir) {
            Remove-Item -Recurse -Force -Path $homeDir
        }

        # Remove the group's dir iff it's empty.
        if ((!(Test-Path -Path (Join-Path $homeDirBase '*'))) -and (Test-Path -Path $homeDirBase)) {
            Remove-Item -Recurse -Force -Path $homeDirBase
        }

        ++$usersRemoved
    }
    
    end {
        # Restart Apache iff it's necessary.
        if ($usersRemoved -gt 0) {
            & /etc/init.d/apache2 restart
        }
    }
}

<#
.SYNOPSIS
Backups a website user on the server.

.PARAMETER Name
The name of the user

.PARAMETER DryRun
If set, nothing will be created and only output messages will be shown.

.INPUTS
You cannot pipe objects to Backup-WebsiteUser.

.OUTPUTS
Nothing
#>
function Backup-WebsiteUser {
    Param (
        [Parameter(ValueFromPipeline=$true)] [string] $Name,
        [switch] $DryRun
    )
    
    process {
        $group = Get-Group -Name $Name
        "Backing up data of user $Name from group $group..." | Out-Host
        if ($DryRun) { return }

        # Create a backup dir iff it's necessary.
        $locationBase = Join-Path $config.websitesLocation $group
        $backupDir = Join-Path $config.backupDir $locationBase
        if (!(Test-Path -PathType Container -Path $backupDir)) {
            New-Item -ItemType 'Directory' -Path $backupDir | Out-Null
        }

        # Backup the user's home dir to zip archive in the backup dir iff it's necessary.
        $homeDirBase = Join-Path $config.apacheServerDocumentRoot $locationBase
        $homeDir = Join-Path $homeDirBase $Name
        if ((Test-Path -PathType Container -Path $homeDir) -and ((Get-ChildItem -Path $homeDir -Attributes !H | Measure-Object).Count -ne 0)) {
            $originalLocation = Get-Location
            Set-Location $homeDir
            $zipFile = Join-Path $backupDir "$Name.zip"
            "Backing up $homeDir into $zipFile..." | Out-Host
            & zip -r $zipFile '*'
            Set-Location $originalLocation
        }
        
        # Backup the user's database to a SQL script iff it's necessary.
        $dbName = Get-DBName -Name $Name
        if (Test-DB -Name $dbName) {
            $sqlDumpFile = Join-Path $backupDir "$dbName.sql"
            "Dumping DB $dbName into $sqlDumpFile..." | Out-Host
            & mysqldump --databases $dbName | Out-File -Path $sqlDumpFile
        }
        
        # Give ownership of the backup dir to the server user.
        & chown -R "$($config.serverUser):$($config.serverGoup)" $backupDir
    }
}