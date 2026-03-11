Try {
# global catch block start
Import-Module dbatools
. ".\Common\Initialize-DeployModule.ps1"
Install-DeployModuleFromRepo "DOrcDeployModule"
Install-DeployModuleFromRepo "PureSSSToolkit"
Install-DeployModuleFromRepo "Internal-DBAAdmin"
Test-RequiredProperties @("DropFolder", "EnvMgtDBServer", "EnvMgtDBName", "RestoreMode", "RestoreSource", "dacpacName", "DBPermsOutput")
if (!(Snap-Database -dropFolder $DropFolder -dacpacName $dacpacName -envMgtDBServer $EnvMgtDBServer -envMgtDBName $EnvMgtDBName -restoreMode $RestoreMode -restoreSource $RestoreSource)) { throw "Snap failed..." }
# global catch block end
} Catch {
	Write-Host "Unexpected Error:"
	Write-Host $_
	throw
}
