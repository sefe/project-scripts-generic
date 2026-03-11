Try {
# global catch block start
. ".\Common\Initialize-DeployModule.ps1"
Install-DeployModuleFromRepo -moduleName "DOrcDeployModule"
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
$arrVariables = New-Object System.Collections.ArrayList($null)
$TMParrVariables = New-Object System.Collections.ArrayList($null)
[System.Collections.ArrayList]$TMParrVariables = $jsonParams.Parameters
foreach ($TMParrVariable in $TMParrVariables)
{
  $tmp = $TMParrVariable.DeployProperty
  $tmpValue = Get-Variable -Name "$tmp" -ValueOnly
  [Void]$arrVariables.add([char]34 + $TMParrVariable.DacpacParameter + [char]34 + "=" + [char]34 + $tmpValue + [char]34)    
}

$dbType = $jsonParams.DatabaseType.Replace(" ","_")
[array]$targetDatabases = Get-Variable -Name "DbName_$dbType" -ValueOnly
[array]$targetInstances = Get-Variable -Name "DbServer_$dbType" -ValueOnly
if ($targetInstances.Count -gt 0) {
  $defaultDeployDacpac = $false
  if ([String]::IsNullOrEmpty($DACPACSelectiveTargets)) { write-host "Non selective deployment..." ; $defaultDeployDacpac = $true } else { write-host "Selective deployment:" $DACPACSelectiveTargets }
  if ($DACPACSelectiveTargets -match ";") { $selectiveTargets = $DACPACSelectiveTargets.split(';') } else { $selectiveTargets = $DACPACSelectiveTargets }
  $instCount = 0
  foreach ($instance in $targetInstances) {
    $deployDacpac = $defaultDeployDacpac
    if (!$deployDacpac) {
      $fullTarget = $instance + "." + $targetDatabases[$instCount]
      write-host "Checking:" $fullTarget
      if ($selectiveTargets -Contains $fullTarget) {
        write-host "   Match:" $fullTarget
        $deployDacpac = $true
      } else { write-host " Skipped:"$fullTarget }
    }
    if ($deployDacpac) {
      write-host "Using:           " $SQLPackagePath
      Write-Host ""
      DeployDACPAC $SQLPackagePath $instance $targetDatabases[$instCount] $dacpacFile $DACPACPublishProfile $arrVariables $DACPACBlackList  $DACPACRollbackMode $DACPACEnvironmentPostSQL

    }
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