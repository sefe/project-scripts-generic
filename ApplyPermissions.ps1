Try {
# global catch block start
. ".\Common\Initialize-DeployModule.ps1"
Install-DeployModuleFromRepo -moduleName "DOrcDeployModule"
Install-DeployModuleFromRepo -moduleName "Internal-DBAAdmin" 
$reqdProperties = @("SQLPackagePath","DACPACPublishProfile", "DACPACBlackList","DACPACEnvironmentPostSQL","DACPACRollbackMode")
Test-RequiredProperties $reqdProperties

$dacpacFile = $DropFolder + "\drop\database\" + $dacpacName
write-host "Looking for:     " $dacpacFile
$jsonFile = $dacpacFile + ".json"
If (!(Test-Path $dacpacFile)) { write-host "Cannont find:" $dacpacName ; throw "" }
If (!(Test-Path $jsonFile)) { write-host "Cannont find JSON " $jsonFile ; throw "" }

write-host "DACPAC file:" $dacpacFile
write-host "JSON file:" $jsonFile
Write-Host ""

$jsonParams = LoadJSONFromFile $jsonFile

$dbType = $jsonParams.DatabaseType.Replace(" ","_")
[array]$targetDatabases = Get-Variable -Name "DbName_$dbType" -ValueOnly
[array]$targetInstances = Get-Variable -Name "DbServer_$dbType" -ValueOnly
if ($targetInstances.Count -gt 0) {
  $instCount = 0
  foreach ($instance in $targetInstances) {
    Apply-DatabasePermissions $instance $targetDatabases[$instCount]
    $instCount++
  }
} else {
  write-host "Unable to find any database entries for:" $dbType
  throw ""
}
# global catch block end
} Catch {
	Write-Host "Unexpected Error:"
	Write-Host $_
	throw
}