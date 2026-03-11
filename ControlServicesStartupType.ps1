Try {
    # global catch block start
    . ".\Common\Initialize-DeployModule.ps1"
    Install-DeployModuleFromRepo "DOrcDeployModule"

    Test-RequiredProperties @("ServerTypes", "Services","ServiceStartupType")
    $svcList = $services.split(";")
    $serverTypes = $serverTypes.split(";")
    if ($retryCount -eq $null) {$retryCount = 10} #exceptionless check if var doesn't exist
    if ($retryTime -eq $null) {$retryTime = 10}
    Write-host "[Retry count] $retryCount"
    Write-host "[Retry time] $retryTime"

    Write-Host "[Services]" $Services
    Write-Host "[ServerTypes]" $ServerTypes
    Write-Host "[ServiceStartupType]" $ServiceStartupType

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
                    foreach ($svc in $svcList) 
                    {
                    Write-Host "Setting" $serverName $svc "to" $ServiceStartupType
                        set-service -name $svc -ComputerName $serverName -StartupType $ServiceStartupType
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