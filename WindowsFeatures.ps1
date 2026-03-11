Try {
# global catch block start
. ".\Common\Initialize-DeployModule.ps1"
Install-DeployModuleFromRepo -moduleName "DOrcDeployModule"
$reqdProperties = @("DeploymentServiceAccount", "DeploymentServiceAccountPassword", "CoreCodeSxSFolder", "BaseBuildFeatures")
Test-RequiredProperties $reqdProperties
$IsError = $Null
Install-WindowsFeaturesDorc -targetServerType $BaseBuildServerType -baseBuildFeatures $BaseBuildFeatures -deploymentServiceAccount $DeploymentServiceAccount `
    -deploymentServiceAccountPassword $DeploymentServiceAccountPassword -coreCodeSxSFolder $CoreCodeSxSFolder -ErrorVariable IsError

Foreach ($exception in $IsError) {Write-Host "[Install-WindowsFeaturesDorc] Exception: $($Exception.Exception.Message)"}
# global catch block end
} Catch {
	Write-Host "Unexpected Error:"
	Write-Host $_
	throw
}