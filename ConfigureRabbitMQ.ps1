Try {
# global catch block start
# Based on https://stackoverflow.com/questions/781205/getting-a-url-with-an-url-encoded-slash
function CreateUri {
    Param ([System.String]$url)

    $uri = New-Object System.Uri -ArgumentList $url
    $paq = $uri.PathAndQuery
    $flagsFieldInfo = $uri.GetType().GetField("m_Flags", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
    $flags = [System.UInt64]$flagsFieldInfo.GetValue($uri)
    $flags = $flags -band (-bnot([System.UInt64] 0x30))
    $flagsFieldInfo.SetValue($uri, $flags)
    $uri
}
. ".\Common\Initialize-DeployModule.ps1"
# Code added to script to fix SqlServer module issue
$SQLServerModuleVer = "22.3.0"
if ((Get-InstalledModule -Name "SqlServer" -Erroraction SilentlyCOntinue).version -ne $SQLServerModuleVer) {    
        if (Get-Module -Name "SqlServer") {
        Remove-Module -Name "SqlServer"
    }
    Uninstall-Module -Name "SqlServer" -AllVersions
	Install-Module -Name "SqlServer" -RequiredVersion $SQLServerModuleVer -Repository "PowerShellModules"    
}
Import-Module SqlServer -RequiredVersion $SQLServerModuleVer -DisableNameChecking -WarningAction SilentlyContinue
Install-DeployModuleFromRepo -moduleName "DOrcDeployModule"
Test-RequiredProperties @("DropFolder", "RMQConfigFileName", "RMQConfigUsername", "RMQConfigPassword", "RMQManagementApiUrl")

$securePassword = ConvertTo-SecureString $RMQConfigPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($RMQConfigUsername, $securePassword)
if ($RMQVirtualHost -ne $null) {$virtualHost = $RMQVirtualHost;} else {$virtualHost = "/"}
$rmqConfigFile = Join-Path -Path (Join-Path -Path $DropFolder -ChildPath "Drop\Config\RabbitMQ") -ChildPath $RMQConfigFileName

$rmqConfig = Get-Content -Raw -Path $rmqConfigFile | ConvertFrom-Json

#Exchanges
$getUrl = CreateUri($RMQManagementApiUrl + "/exchanges/" + [System.Uri]::EscapeDataString($virtualHost))
$existingExchanges = @{}
(Invoke-RestMethod -Uri $getUrl -Method Get -Credential $cred -DisableKeepAlive) | ForEach-Object { $existingExchanges[$_.name] = $_ }

$rmqConfig.exchanges | ForEach-Object {
    $exchangeName = $_.name

    if (($existingExchanges.keys | Where-Object { $_ -eq $exchangeName }) -eq $null) {
        Write-Output "Creating exchange '$exchangeName'."

        $exchangeObj = New-Object System.Object
        $exchangeObj | Add-Member -type NoteProperty -name "type" -value $_.type
        $exchangeObj | Add-Member -type NoteProperty -name "durable" -value $_.durable

        $putUrl = CreateUri($RMQManagementApiUrl + "/exchanges/" + [System.Uri]::EscapeDataString($virtualHost) + "/" + [System.Uri]::EscapeDataString($exchangeName))

        $body = (ConvertTo-Json $exchangeObj)
        Invoke-RestMethod -Uri $putUrl -Method Put -Credential $cred -Body $body -ContentType "application/json" -DisableKeepAlive | Out-Null

    }
    else {
        Write-Output "Exchange '$exchangeName' already exists."
        
        $existingExchange = $existingExchanges[$exchangeName]

        if ($_.type -ne $existingExchange.type) {
            $expected = $_.type
            $actual = $existingExchange.type
            Write-Warning "The type of exchange '$exchangeName' does not match: expected '$expected', actual '$actual'"
        }

        if ($_.durable -ne $existingExchange.durable) {
            $expected = $_.durable
            $actual = $existingExchange.durable
            Write-Warning "The durability of exchange '$exchangeName' does not match: expected '$expected', actual '$actual'"
        }

        if ($existingExchange.auto_delete -ne $false) {
            Write-Warning "The auto-delete status of exchange '$exchangeName' does not match: expected 'False', actual 'True'"
        }

        if ($existingExchange.internal -ne $false) {
            Write-Warning "The internal status of exchange '$exchangeName' does not match: expected 'False', actual 'True'"
        }
    }
}


#Queues
$getUrl = CreateUri($RMQManagementApiUrl + "/queues/" + [System.Uri]::EscapeDataString($virtualHost))
$existingQueues = @{}
(Invoke-RestMethod -Uri $getUrl -Method Get -Credential $cred -DisableKeepAlive) | ForEach-Object { $existingQueues[$_.name] = $_ }

$rmqConfig.queues | ForEach-Object {
    $queueName = $_.name

    if (($existingQueues.keys | Where-Object { $_ -eq $queueName }) -eq $null) {
        Write-Output "Creating queue '$queueName'."

        $queueObj = New-Object System.Object
        $queueObj | Add-Member -type NoteProperty -name "durable" -value $_.durable

        $putUrl = CreateUri($RMQManagementApiUrl + "/queues/" + [System.Uri]::EscapeDataString($virtualHost) + "/" + [System.Uri]::EscapeDataString($queueName))
        Invoke-RestMethod -Uri $putUrl -Method Put -Credential $cred -Body (ConvertTo-Json $queueObj) -ContentType "application/json" -DisableKeepAlive | Out-Null

    }
    else {
        Write-Output "Queue '$queueName' already exists."

        $existingQueue = $existingQueues[$queueName]

        if ($_.durable -ne $existingQueue.durable) {
            $expected = $_.durable
            $actual = $existingQueue.durable
            Write-Warning "The durability of queue '$queueName' does not match: expected '$expected', actual '$actual'"
        }

        if ($existingQueue.auto_delete -ne $false) {
            Write-Warning "The auto-delete status of queue '$queueName' does not match: expected 'False', actual 'True'"
        }
    }
}


#Bindings
$getUrl = CreateUri($RMQManagementApiUrl + "/bindings/" + [System.Uri]::EscapeDataString($virtualHost))
$existingBindings = (Invoke-RestMethod -Uri $getUrl -Method Get -Credential $cred -DisableKeepAlive) | Where-Object { $_.destination_type -eq "queue" }  `
    | Select-Object  @{Name="exchange"; Expression = {$_.source}}, @{Name="queue"; Expression = {$_.destination}}, @{Name="routing_key"; Expression = { @{$true = $null; $false = $_.routing_key}[$_.routing_key -eq ""]}}

$rmqConfig.bindings | ForEach-Object {
    $exchange = $_.exchange
    $queue = $_.queue
    $routing_key = $_.routing_key

    if (($existingBindings | Where-Object { ($_.exchange -eq $exchange) -and ($_.queue -eq $queue) -and ((($_.routing_key -eq $null) -and ($routing_key -eq $null)) -or ($_.routing_key -eq $routing_key)) }) -eq $null) {
        
        if ($routing_key -eq $null) {
            Write-Output "Creating binding between '$exchange' and '$queue'."
        }
        else {
            Write-Output "Creating binding between '$exchange' and '$queue' using routing key '$routing_key'."
        }

        $bindingObj = New-Object System.Object
        if ($routing_key -ne $null) {
            $bindingObj | Add-Member -type NoteProperty -name "routing_key" -value $routing_key
        }

        $postUrl = CreateUri($RMQManagementApiUrl + "/bindings/" + [System.Uri]::EscapeDataString($virtualHost) + "/e/" + [System.Uri]::EscapeDataString($exchange) + "/q/" + [System.Uri]::EscapeDataString($queue))
        Invoke-RestMethod -Uri $postUrl -Method Post -Credential $cred -Body (ConvertTo-Json $bindingObj) -ContentType "application/json" -DisableKeepAlive | Out-Null

    }
    else {
        if ($routing_key -eq $null) {
            Write-Output "Binding between '$exchange' and '$queue' already exists."
        }
        else {
            Write-Output "Binding between '$exchange' and '$queue' using routing key '$routing_key' already exists."
        }
    }
}

#Policies
$getUrl = CreateUri($RMQManagementApiUrl + "/policies/" + [System.Uri]::EscapeDataString($virtualHost))
$existingPolicies = @{}
(Invoke-RestMethod -Uri $getUrl -Method Get -Credential $cred -DisableKeepAlive) | ForEach-Object { $existingPolicies[$_.name] = $_ }

$rmqConfig.policies | ForEach-Object {
    $policyName = $_.name

    if (($existingPolicies.keys | Where-Object { $_ -eq $policyName }) -eq $null) {
        Write-Output "Creating policy '$policyName'."

        $policyObj = New-Object System.Object
        $policyObj | Add-Member -type NoteProperty -name "pattern" -value $_.pattern
        $policyObj | Add-Member -type NoteProperty -name "apply-to" -value $_."apply-to"
        $policyObj | Add-Member -type NoteProperty -name "definition" -value $_.definition
        $policyObj | Add-Member -type NoteProperty -name "priority" -value $_.priority

        $putUrl = CreateUri($RMQManagementApiUrl + "/policies/" + [System.Uri]::EscapeDataString($virtualHost) + "/" + [System.Uri]::EscapeDataString($_.name))
        Invoke-RestMethod -Uri $putUrl -Method Put -Credential $cred -Body (ConvertTo-Json $policyObj) -ContentType "application/json" -DisableKeepAlive | Out-Null

    }
    else {
        Write-Output "Policy '$policyName' already exists."

        $existingPolicy = $existingPolicies[$policyName]

        if ($_.pattern -ne $existingPolicy.pattern) {
            $expected = $_.pattern
            $actual = $existingPolicy.pattern
            Write-Warning "The property 'pattern' of policy '$policyName' does not match: expected '$expected', actual '$actual'"
        }

        if ($_.'apply-to' -ne $existingPolicy.'apply-to') {
            $expected = $_.'apply-to'
            $actual = $existingPolicy.'apply-to'
            Write-Warning "The property 'apply-to' of policy '$policyName' does not match: expected '$expected', actual '$actual'"
        }

        if ((ConvertTo-Json $_.definition) -ne (ConvertTo-Json $existingPolicy.definition)) {
            $expected = ConvertTo-Json $_.definition
            $actual = ConvertTo-Json $existingPolicy.definition
            Write-Warning "The property 'definition' of policy '$policyName' does not match: expected '$expected', actual '$actual'"
        }

        if ($_.priority -ne $existingPolicy.priority) {
            $expected = $_.priority
            $actual = $existingPolicy.priority
            Write-Warning "The property 'priority' of policy '$policyName' does not match: expected '$expected', actual '$actual'"
        }
    }
}
# global catch block end
} Catch {
	Write-Host "Unexpected Error:"
	Write-Host $_
	throw
}