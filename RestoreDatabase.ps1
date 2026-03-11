Try {
# global catch block start
. ".\Common\Initialize-DeployModule.ps1"
Install-DeployModuleFromRepo "DOrcDeployModule"
Install-DeployModuleFromRepo "Internal-DBAAdmin"
# Code added to script to fix SqlServer module issue
$SQLServerModuleVer = "22.3.0"
if ((Get-InstalledModule -Name "SqlServer" -Erroraction SilentlyCOntinue).version -ne $SQLServerModuleVer) {    
        if (Get-Module -Name "SqlServer") {
        Remove-Module -Name "SqlServer"
    }
    Uninstall-Module -Name "SqlServer" -AllVersions
	Install-Module -Name "SqlServer" -RequiredVersion $SQLServerModuleVer -Repository "PowerShellModules"    
}
Import-Module SqlServer -RequiredVersion $SQLServerModuleVer -DisableNameChecking -WarningAction SilentlyContinue

#Install-DeployModuleFromRepo "DOrcDeployModule"
Test-RequiredProperties @("DropFolder", "EnvMgtDBServer", "EnvMgtDBName", "RestoreMode", "RestoreSource", "dacpacName", "DORC_RestoreDBExePath","DORC_DropDBExePath")

if ( ($EnvironmentName -Match (" PR")) -or ($EnvironmentName -Match (" Prod")) -or ($EnvironmentName -Match (" DR"))) {throw "Target environment can't be Prod"}

$rows = (Get-ChildItem -Path $DropFolder -Recurse)
$dacpacFile = $null
foreach ($row in $rows)
{
    if ($row.Name.Equals($dacpacName))
    {
        $dacpacFile = $row.FullName
    }   
}
if ([String]::IsNullOrEmpty($dacpacFile))
{
    write-host "Couldn't locate" $dacpacName "in" $DropFolder;throw ""
}
else
{
    $jsonFile = $dacpacFile.TrimEnd("dacpac") + "restore.json"
    $postRestoreFile = $dacpacFile.TrimEnd("dacpac") + "postrestore.sql"
    If (!(Test-Path $dacpacFile)) {write-host "Cannot find:" $dacpacName;throw ""}
    If (!(Test-Path $jsonFile)) {write-host "Cannot find JSON " $dacpacName;throw ""}
    write-host "JSON settings:" $jsonFile
}

$jsonParams = LoadJSONFromFile $jsonFile
switch ($RestoreSource.ToLower())
{
    "prod" 
    {
        $SourceInfo = (GetDbInfoByTypeForEnv  $jsonParams.SourceEnvProd $jsonParams.DatabaseType)
        if ($SourceInfo.Contains(":")) {write-host "check $SourceInfo"}
        else 
        {
            write-host "Source database information could not be retrived for db type:" $jsonParams.DatabaseType
            throw ""
        }
    }
    "staging" 
    {
        $SourceInfo = (GetDbInfoByTypeForEnv $jsonParams.SourceEnvStaging $jsonParams.DatabaseType)
        if (!($SourceInfo.Contains(":"))) {write-host "Source database information could not be retrived for db type:" $jsonParams.DatabaseType "in" $jsonParams.SourceEnvProd;throw ""}
    }
    default {throw "RestoreSource should be prod or staging..."}
}

$TargetInfo = (GetDbInfoByTypeForEnv  $EnvironmentName $jsonParams.DatabaseType)
if (!($TargetInfo.Contains(":"))) {write-host "Target database information could not be retrived for db type:" $jsonParams.DatabaseType "in" $EnvironmentName;throw ""}
if ($TargetInfo -eq $SourceInfo) {throw ""}

$TargetDB = ($TargetInfo.Split(":"))[-1]
$TargetInstance = GetSQLServerName ($TargetInfo.Split(":"))[0]
$SourceDB = ($SourceInfo.Split(":"))[-1]
$SourceInstance = GetSQLServerName ($SourceInfo.Split(":"))[0]
Write-Host "Source:" $SourceInstance"."$SourceDB
write-host "Target:" $TargetInstance"."$TargetDB

# Drop
#. \\DORCTOOLS\CLITools\DropDatabase\Tools.DropDatabaseCLI.exe /instance:$TargetInstance /database:$TargetDB
if (!(CheckBackup $SourceInstance $SourceDB $RestoreMode.ToLower())) {throw "Database won't be dropped because backup is not exist"}
else {write-host "Source database has a backup, target DB will be dropped and recreated"}
$drop = ". $DORC_DropDBExePath /instance:$TargetInstance /database:$TargetDB"
Invoke-Expression $drop | Write-Host

write-host "Restore exe path: $DORC_RestoreDBExePath"

# Restore
Switch ($RestoreMode.ToLower())
{
    "latest"
    {
        Write-Host "latest"
        $restore = ". $DORC_RestoreDBExePath /mode:latest /sourceinst:$SourceInstance /sourcedb:$SourceDB /targetinst:$TargetInstance /targetdb:$TargetDB /recoverymodel:Simple /shrinklogfile:true"
        Invoke-Expression $restore | Write-Host
        #. \\DORCTOOLS\CLITools\SQLRestore\Tools.SQLRestoreCLI.exe /mode:latest /sourceinst:$SourceInstance /sourcedb:$SourceDB /targetinst:$TargetInstance /targetdb:$TargetDB /recoverymodel:Simple /shrinklogfile:true

    }
    "now"
    {
        Write-Host "now"
        $restore = ". $DORC_RestoreDBExePath /mode:now /sourceinst:$SourceInstance /sourcedb:$SourceDB /targetinst:$TargetInstance /targetdb:$TargetDB /recoverymodel:Simple /shrinklogfile:true"
        Invoke-Expression $restore | Write-Host
        #. \\DORCTOOLS\CLITools\SQLRestore\Tools.SQLRestoreCLI.exe /mode:now /sourceinst:$SourceInstance /sourcedb:$SourceDB /targetinst:$TargetInstance /targetdb:$TargetDB /recoverymodel:Simple /shrinklogfile:true
    }
    "pit"
    {
        Write-Host "pit"
        $strDateTime = [char]34 + [char]34 + $RestorePointInTime + [char]34 + [char]34
        $restore = ". $DORC_RestoreDBExePath /mode:pit /datetime:$strDateTime /sourceinst:$SourceInstance /sourcedb:$SourceDB /targetinst:$TargetInstance /targetdb:$TargetDB /recoverymodel:Simple /shrinklogfile:true"
        Invoke-Expression $restore | Write-Host
    }
    default {throw "wrong RestoreMode, expected: latest/now/pit"}
}

# Permissions
$strStatus = GetDBStatus $TargetInstance $TargetDB 
if ($strStatus -eq "Normal")
{
    $TargetInstance = ($TargetInfo.Split(":"))[0]
	Write-Host $TargetInstance"."$TargetDB "is" $strStatus    
	Apply-DatabasePermissions $TargetInstance $TargetDB
}
else {throw "Database failed to restore..."}

# Post restore SQL
if (Test-Path $postRestoreFile)
{
	Write-Host "Applying:" $postRestoreFile "on" $TargetInstance"."$TargetDB
	$postRestoreresult = Invoke-Sqlcmd -TrustServerCertificate -ServerInstance "$TargetInstance" -Database "$TargetDB" -InputFile $postRestoreFile -QueryTimeout 600 -ErrorAction 'Stop' -OutputSqlErrors $true
	$postRestoreresult
}
else {write-host "$postRestoreFile not found..."}

# global catch block end
} Catch {
	Write-Host "Unexpected Error:"
	Write-Host $_
	throw
}
