Try {
# global catch block start
. ".\Common\Initialize-DeployModule.ps1"
Install-DeployModuleFromRepo -moduleName "DOrcDeployModule"
Test-RequiredProperties @("EnvMgtDBServer", "EnvMgtDBName", "DeploymentServiceAccountPassword", "DeploymentServiceAccount")
$ServerInfo = new-object "System.Data.DataTable"
$ServerInfo = GetServersOfType $EnvironmentName ""
function Get-ServersStatus {
    param (
        $Servers
    )
    if ($ServerInfo.Rows.Count -gt 0)  {
        foreach ($Row in $Servers)  {
            $serverName = $Row.Server_Name.Trim()        
            if (Test-Connection $serverName -Count 1 -quiet) {
                try { 
                    if (Get-WmiObject -query "SELECT * FROM Win32_OperatingSystem" -ComputerName $ServerName -ErrorAction Stop) {
                        Write-Host "$ServerName is online and available for deployment"    
					}
                }
                catch {
                    Write-Host "Either $ServerName is not available or $DeploymentServiceAccount account doesn't have access to it"
                    $error[0]
					throw
                }	
            }
            else {
					Write-Host "`t$ServerName is not online!"
					$error[0]
					throw
				
                }
            }   
    }
    else
    {
        throw "No servers to target..."
    }

}
Get-ServersStatus  $ServerInfo
# global catch block end
} Catch {
	Write-Host "Unexpected Error:"
	Write-Host $_
	throw
}