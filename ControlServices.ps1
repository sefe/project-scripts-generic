Try {
# global catch block start
. ".\Common\Initialize-DeployModule.ps1"
Install-DeployModuleFromRepo "DOrcDeployModule"

Test-RequiredProperties @("action", "serverTypes", "services")
$svcList = $services.split(";")
$serverTypes = $serverTypes.split(";")
if ($retryCount -eq $null) {$retryCount = 10} #exceptionless check if var doesn't exist
if ($retryTime -eq $null) {$retryTime = 10}
Write-host "[Retry count] $retryCount"
Write-host "[Retry time] $retryTime"

foreach ($serverType in $serverTypes)
{
    $ServerInfo = new-object "System.Data.DataTable"
    $ServerInfo = GetServersOfType $EnvironmentName $serverType
    if ($ServerInfo.Rows.Count -gt 0)
    {
        foreach ($Row in $ServerInfo)
        {
            $serverName = $Row.Server_Name.Trim()
            $remoteExplorer = "\\" + $serverName + "\C$\Windows\Explorer.exe"
            if (Test-Path $remoteExplorer)
            {
                if ($action.ToLower() -eq "stop") { Stop-Services $svcList $ServerName $retryCount $retryTime}
                if ($action.ToLower() -eq "start") { 
                    $OS_version = (Get-CimInstance -ClassName CIM_OperatingSystem -ComputerName $ServerName).Caption
                    if ($OS_version -notlike '*2022*') {StartServices $svcList $ServerName}
                    else {
						Write-Host "Starting services on Windows 2022..."
						Start-Services $svcList $ServerName
					}
                }
            }
            else { throw "Suspect no admin rights on: $serverName" }
        }
    }
    else
    {
        Write-Host "No servers of type:" $serverType
    }
    $ServerInfo = $null
}

# global catch block end
} Catch {
	Write-Host "Unexpected Error:"
	Write-Host $_
	throw
}