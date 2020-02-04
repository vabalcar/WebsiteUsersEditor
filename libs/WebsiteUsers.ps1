Param (
    [Parameter(Mandatory=$true)] [string] $ConfigurationFile
)

$config = Get-Content -Path $ConfigurationFile | ConvertFrom-Json

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

function Get-DBName {
    Param (
        [Parameter(Mandatory=$true)] [string] $Name
    )
    
    process {
        return $Name -replace '[\.\\\/]', '_'
    }
}

function Get-GroupName {
    Param (
        [Parameter(Mandatory=$true)] [string] $Name
    )
    
    process {
        $homedirEntry = & virtualmin list-users --domain seup.lnxserver.com --multiline --user $Name | Select-String -Pattern 'Home directory:'
        $homdirEntryStructured = $homedirEntry -Split '/'
        return $homdirEntryStructured[$homdirEntryStructured.Length - 2]
    }
}

function New-WebsiteUser {
    Param (
        [Parameter(Mandatory=$true)] [string] $GroupName,
        [Parameter(ValueFromPipeline=$true)] [string] $Name
    )
    
    begin {
        $usersCreated = 0
        $locationBase = Join-Path $config.websitesLocation $GroupName
        $homeDirBase = Join-Path $config.apacheServerDocumentRoot $locationBase
		if (!(Test-Path -PathType Container -Path $homeDirBase)) {
            New-Item -ItemType 'Directory' -Path $homeDirBase | Out-Null
			& chown -R "$($config.serverUser):$($config.serverGoup)" $homeDirBase
        }
    }

    process {
        "Creating user $Name in group $GroupName..." | Out-Host
        $homeDir = Join-Path $homeDirBase $Name
        $apacheUserConfTemplate = @"
<Directory "$homeDir">
php_admin_value open_basedir "$homeDir"
php_admin_value upload_tmp_dir "$homeDir/.tmp"
</Directory>

Redirect "/$Name" "https://$($config.domain)/$locationBase/$Name"
"@
        if (!(Test-Path -PathType Container -Path $homeDir)) {
            New-Item -ItemType 'Directory' -Path $homeDir | Out-Null
        }
        if (!(Test-Path -PathType Container -Path "$homeDir/.tmp")) {
            New-Item -Force -ItemType Directory -Path "$homeDir/.tmp" | Out-Null
        }
        $apacheUserConfTemplate | Out-File -Path (Join-Path $config.apacheUsersSettings "$Name.conf")
        $dbname = Get-DBName -Name $Name
        & virtualmin create-database --domain $config.domain --name $dbName --type mysql
        & virtualmin create-user --domain $config.domain --user $Name --pass $config.defaultUserPassword --ftp --noemail --mysql $dbName --web --home (Join-Path 'public_html' $locationBase $Name)
        & chown -R "$($config.serverUser):$($config.serverGoup)" $homeDir
        ++$usersCreated
    }
    
    end {
        if ($usersCreated -gt 0) {
            & /etc/init.d/apache2 restart
        }
    }
}

function Restore-WebsiteUser {
    Param (
        [Parameter(Mandatory=$true)] [string] $GroupName,
        [Parameter(ValueFromPipeline=$true)] [string] $Name
    )

    begin {
        $usersFixed = 0
        $locationBase = Join-Path $config.websitesLocation $GroupName
        $homeDirBase = Join-Path $config.apacheServerDocumentRoot $locationBase
    }

    process {
        "Fixing user $Name in group $GroupName..." | Out-Host
        $homeDir = Join-Path $homeDirBase $Name
        $apacheUserConfTemplate = @"
<Directory "$homeDir">
php_admin_value open_basedir "$homeDir"
php_admin_value upload_tmp_dir "$homeDir/.tmp"
</Directory>

Redirect "/$Name" "https://$($config.domain)/$locationBase/$Name"
"@

        New-Item -Force -ItemType Directory -Path $homeDir/.tmp
        & chown -R "$($config.serverUser):$($config.serverGoup)" $homeDir
        $apacheUserConfTemplate | Out-File -Path (Join-Path $config.apacheUsersSettings "$Name.conf")
        ++$usersFixed
    }
    
    end {
        if ($usersFixed -gt 0) {
            & /etc/init.d/apache2 restart
        }
    }
}

function Remove-WebsiteUser {
    Param (
        [Parameter(ValueFromPipeline=$true)] [string] $Name
    )
    
    begin {
        $usersRemoved = 0
    }
    
    process {
		$groupName = Get-GroupName -Name $Name
        "Removing user $_ from group $groupName..." | Out-Host
        $homeDirBase = Join-Path $config.apacheServerDocumentRoot $config.websitesLocation $groupName
        $homeDir = Join-Path $homeDirBase $Name
        $dbname = Get-DBName -Name $Name
        & virtualmin delete-user --domain $config.domain --user $Name
        & virtualmin delete-database --domain $config.domain --name $dbName --type mysql
        Remove-Item -Force -Path (Join-Path $config.apacheUsersSettings "$Name.conf")
        if (Test-Path -PathType Container -Path $homeDir) {
            Remove-Item -Recurse -Force -Path $homeDir
        }
        if ((!(Test-Path -Path (Join-Path $homeDirBase '*'))) -and (Test-Path -Path $homeDirBase)) {
            Remove-Item -Recurse -Force -Path $homeDirBase
        }
        ++$usersRemoved
    }
    
    end {
        if ($usersRemoved -gt 0) {
            & /etc/init.d/apache2 restart
        }
    }
}

function Backup-WebsiteUser {
    Param (
        [Parameter(ValueFromPipeline=$true)] [string] $Name
    )
    
    process {
        $groupName = Get-GroupName -Name $Name
		"Backing up data of user $Name from group $groupName..." | Out-Host
        $locationBase = Join-Path $config.websitesLocation $groupName
        $homeDirBase = Join-Path $config.apacheServerDocumentRoot $locationBase
        $homeDir = Join-Path $homeDirBase $Name
        $backupDir = Join-Path $config.backupDir $locationBase
        $dbname = Get-DBName -Name $Name
        if (!(Test-Path -PathType Container -Path $backupDir)) {
            New-Item -ItemType 'Directory' -Path $backupDir | Out-Null
        }
        if (Test-Path -PathType Container -Path $homeDir) {
            & zip -r (Join-Path $backupDir "$Name.zip") (Join-Path $homeDir '*')
        }
        & mysqldump --databases $dbName | Out-File -Path (Join-Path $backupDir "$dbName.sql")
        & chown -R "$($config.serverUser):$($config.serverGoup)" $backupDir
    }
}