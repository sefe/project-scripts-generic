
Try {
  . ".\Common\Initialize-DeployModule.ps1"
  Install-DeployModuleFromRepo -moduleName "DOrcDeployModule"
  $reqdProperties = @("SQLPackagePath","DACPACPublishProfile", "DACPACBlackList","DACPACEnvironmentPostSQL","DACPACRollbackMode")
  Test-RequiredProperties $reqdProperties
 
  
   $dacpacFile = $DropFolder + "\drop\database\" + $dacpacName
   write-host "Looking for:     " $dacpacFile
   $jsonFile = $dacpacFile + ".json"
   $jsonFile
   If (!(Test-Path $dacpacFile)) { write-host "Cannont find:" $dacpacName ; throw "" }
   If (!(Test-Path $jsonFile)) { write-host "Cannont find JSON " $jsonFile ; throw "" }
   
   write-host "DACPAC file:" $dacpacFile
   write-host "JSON file:" $jsonFile
   Write-Host ""
 
   if (-not (Test-Path $sqlPackagePath)) {
       Write-Host "SqlPackage.exe not found at $sqlPackagePath"
       throw "SqlPackage.exe not found"
   }
 
   $AccessToken = (Get-AzAccessTokenToResource -ClientID $DacpacDeployClientId -ClientSecret $DacpacDeployClientSecret -TenantDomain $DacpacDeployTenantDomain -ResourceUrl $ResourceUrl).Token
   
   $jsonParams = LoadJSONFromFile $jsonFile
   $arrVariables = New-Object System.Collections.ArrayList($null)
   $TMParrVariables = New-Object System.Collections.ArrayList($null)
   [System.Collections.ArrayList]$TMParrVariables = $jsonParams.Parameters
   
   # Collect all DACPAC_ENVVAR_* variables for passing to deployment
   $variableList = @{}
   Get-Variable | Where-Object { $_.Name -like 'DACPAC_ENVVAR_*' } | ForEach-Object {
       $variableList[$_.Name] = $_.Value
   }
   Write-Host "List of DACPAC variables:"
   $variableList.GetEnumerator() | ForEach-Object { Write-Host "  $($_.Key)=$($_.Value)" }
   
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
 
     $instCount = 0
     foreach ($instance in $targetInstances) {
     write-host "Using:           " $SQLPackagePath
     Write-Host ""
     DeployDACPACToAzureSQL -sqlPackagePath $sqlPackagePath -TargetServerName $instance -TargetDatabaseName $targetDatabases[$instCount] -dacpacPath $dacpacFile -AccessToken $AccessToken -Variables $variableList
     $instCount++
     } 
   } else {
     write-host "Unable to find any database entries for:" $dbType
     throw ""
   }
 
 } Catch {
   Write-Host "An error occurred during the deployment process."
   Write-Host $_.Exception.Message
   throw $_
 }