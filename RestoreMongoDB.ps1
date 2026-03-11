Try {
# global catch block start
. ".\Common\Initialize-DeployModule.ps1"
Install-DeployModuleFromRepo -moduleName "DOrcDeployModule"

#SQL module to reach data from Environment tracker
$SQLServerModuleVer = "22.3.0"
if ((Get-InstalledModule -Name "SqlServer" -Erroraction SilentlyCOntinue).version -ne $SQLServerModuleVer) {    
        if (Get-Module -Name "SqlServer") {
        Remove-Module -Name "SqlServer"
    }
    Uninstall-Module -Name "SqlServer" -AllVersions
	Install-Module -Name "SqlServer" -RequiredVersion $SQLServerModuleVer -Repository "PowerShellModules"    
}
Import-Module SqlServer -RequiredVersion $SQLServerModuleVer -DisableNameChecking -WarningAction SilentlyContinue
#Module for mongoDB management
if ((Get-InstalledModule -Name mdbc -Erroraction SilentlyCOntinue).version -ne "6.5.6") {
	Install-Module -Name MDBC -RequiredVersion "6.5.6"
}
Import-Module -Name MDBC

Test-RequiredProperties @("MongoDB_Dump_Folder", "EnvMgtDBServer", "EnvMgtDBName", "MongoDB_Source_Connection_String", "MongoDB_Source_Database", "MongoDB_Destination_Connection_String", "MongoDB_Database_type", "MongoDB_Collections")

If (!($MongoDB_mongodump_executable)) {$MongoDB_mongodump_executable = "mongodump"}
If (!($MongoDB_mongorestore_executable)) {$MongoDB_mongorestore_executable = "mongorestore"}

#Get Database name for restore
$TargetInfo = (GetDbInfoByTypeForEnv $EnvironmentName $MongoDB_Database_type)
if (!($TargetInfo.Contains(":"))) {write-host "Target database information could not be retrived for db type:" $jsonParams.DatabaseType "in" $EnvironmentName;throw ""}

$MongoDB_Target_Database = ($TargetInfo.Split(":"))[-1]

Connect-Mdbc -ConnectionString "$MongoDB_Destination_Connection_String"

#Select folder with current date
[string]$currentDate = "" + (Get-Date).Year + "-" + (Get-Date).Month + "-" + (Get-Date).Day
$backupFolderName = $EnvironmentName + $currentDate
$backupFolder = Join-Path -Path $MongoDB_Dump_Folder -ChildPath $backupFolderName
$MongoDB_Collection_List = $MongoDB_Collections.Split(",")

Write-Host "Creating dump from" $MongoDB_Source_Database "to" $backupFolder
Foreach ($MongoDB_Collection in $MongoDB_Collection_List) {
	Write-Host "Creating dump from collection $MongoDB_Collection"
	$backup = $ExecutionContext.InvokeCommand.ExpandString($MongoDB_mongodump_executable) + ' --uri="$MongoDB_Source_Connection_String" --db="$MongoDB_Source_Database" --out=$backupFolder --collection=$MongoDB_Collection'
	Invoke-Expression -Command $backup
}
 
Write-Host "Restoring data from" $backupFolder "to" $MongoDB_Target_Database
Foreach ($MongoDB_Collection in $MongoDB_Collection_List) {
	Write-Host "Restoring collection $MongoDB_Collection"
	$bsonName = $MongoDB_Collection + ".bson"
	$bsonPath = Join-Path (Join-Path $backupFolder $MongoDB_Source_Database) $bsonName
	$restore = $ExecutionContext.InvokeCommand.ExpandString($MongoDB_mongorestore_executable) + ' --uri="$MongoDB_Destination_Connection_String" --db="$MongoDB_Target_Database" --drop --collection=$MongoDB_Collection $bsonPath'
	Invoke-Expression -Command $restore
}

#Check if restore completed successfully
$databasesList = Get-MdbcDatabase
Foreach ($destinationDatabase in $databasesList) {
	if ($destinationDatabase.DatabaseNamespace -eq "$MongoDB_Target_Database") {Break}
}
If (!($destinationDatabase.DatabaseNamespace -eq $MongoDB_Target_Database)) {
	Write-Host "Something went wrong and database was not restored"
}

Write-Host "Removing dump from" $backupFolder
Remove-Item $backupFolder -Recurse

# Remove older data if $MongoDB_Days_Remain property set
If ($MongoDB_Days_Remain) {
	$deletionDate = (Get-Date).adddays(-$MongoDB_Days_Remain)
	Write-Host "Removing all data with creation date older than " $deletionDate

	# To limit memroy usage in case of huge collections data processed in steps with limited number of records
	$step = 200

	Foreach ($collection in $MongoDB_Collection_List) {
		$collectionRecordsCount = Get-MdbcData -Collection $collection -Count

		# This need to be done to process collections with number of records less than $step
		if ($collectionRecordsCount  -lt $step) {
			$collectionRecordsCount = 0
		}
		else {
			$collectionRecordsCount = $collectionRecordsCount - $step
		}

		# Here used For instead of ForEach to limit memory usage because ForEach load whole collection in memory
		For ($collectionRecordsCount; $collectionRecordsCount -gt -1; ) {
			$collectionData = Get-MdbcData -Collection $collection -First $step -Skip $collectionRecordsCount
			Foreach ($collectionDataRecord in $collectionData) {
				if ($collectionDataRecord._id.CreationTime -lt $deletionDate) {
					Remove-MdbcData $collectionDataRecord -Collection $collection
				}
			}
			$collectionRecordsCount = $collectionRecordsCount - $step
	
			# This hack used to process all data in last step then counter is on 0
			if ($collectionRecordsCount -lt "0") {
				$collectionRecordsCount = "0"
			}
			elseif ($collectionRecordsCount -eq "0"){
				$collectionRecordsCount = -1
			}
		}
	}
}
# global catch block end
} Catch {
	Write-Host "Unexpected Error:"
	Write-Host $_
	throw
}