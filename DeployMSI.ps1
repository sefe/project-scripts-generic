Try {
# global catch block start
. ".\Common\Initialize-DeployModule.ps1"
Install-DeployModuleFromRepo -moduleName "DOrcDeployModule"
Test-RequiredProperties @("DropFolder", "EnvMgtDBServer", "EnvMgtDBName", "msiName", "productNames", "DeploymentServiceAccountPassword", "DeploymentServiceAccount")
Write-Host "Required system properties found....Deploying MSI";
if (![String]::IsNullOrEmpty($productNamesEnvironment))
{
    # 2016-12-06 - Added because LTRM use a variable product name
    $tmp = (get-variable ((get-variable productNamesEnvironment).Value)).Value 
    $productNames = $productNames + $tmp
}
If ($ServerTag) 
    {
    DeployMSI -MSIFile $msiName -DropFolder $DropFolder -ProductNames @($productNames) -ServerTag $ServerTag
    }
Else 
    {
    DeployMSI -MSIFile $msiName -DropFolder $DropFolder -ProductNames @($productNames)
    }
# global catch block end
} Catch {
	Write-Host "Unexpected Error:"
	Write-Host $_
	throw
}