Try {
. ".\Common\Initialize-DeployModule.ps1"

Install-DeployModuleFromRepo "DOrcDeployModule"

Test-RequiredProperties @("DropFolder", "AzureStorageFileShareURI", "AzCopyClientId", "AzCopyClientSecret", "AzCopyTenantId", "DirectoryName")
Write-Host "Required system properties found....";

$ErrorActionPreference = "Stop"

if (-not (Test-Path -Path $DropFolder -PathType Container)) {
    throw "Source folder not found: '$DropFolder'."
}
if (-not (Get-ChildItem -Path $DropFolder -Recurse -Force | Select-Object -First 1)) {
    Write-Warning "Source folder '$DropFolder' appears to be empty."
}
Write-Host "Source folder OK: $DropFolder"

try {
    $destUri = [Uri]$AzureStorageFileShareURI
} catch {
    throw "Invalid URI in `$AzureStorageFileShareURI`: '$AzureStorageFileShareURI'. Expected format like 'https://<account>.file.core.windows.net/<share>'."
}

if ($destUri.Scheme -ne 'https') {
    throw "Destination URI must be HTTPS. Got: '$($destUri.Scheme)'."
}

try {
    $null = Resolve-DnsName -Name $destUri.Host -Type A -ErrorAction Stop
    Write-Host "DNS OK for host: $($destUri.Host)"
} catch {
    throw "DNS resolution failed for host '$($destUri.Host)'."
}

$azcopyCmd = Get-Command azcopy -ErrorAction SilentlyContinue
if (-not $azcopyCmd) {
    Write-Host "==> AzCopy not found. Installing..."

    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    $tempZip     = Join-Path $env:TEMP "AzCopy.zip"
    Invoke-WebRequest -Uri $downloadAzCopyUrl -OutFile $tempZip -UseBasicParsing

    $expandDir = Join-Path $env:TEMP "AzCopy_extracted"
    if (Test-Path $expandDir) { Remove-Item $expandDir -Recurse -Force }
    Expand-Archive -Path $tempZip -DestinationPath $expandDir

    $azExe = Get-ChildItem -Path $expandDir -Recurse -Filter 'azcopy.exe' | Select-Object -First 1
    if (-not $azExe) { throw "AzCopy executable not found after extraction." }

    $installDir = Join-Path ${env:ProgramFiles} "AzCopy"
    try {
        if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir | Out-Null }
        Copy-Item -Path $azExe.FullName -Destination (Join-Path $installDir 'azcopy.exe') -Force
    } catch {
        $installDir = Join-Path $env:USERPROFILE "AzCopy"
        if (-not (Test-Path $installDir)) { New-Item -ItemType Directory -Path $installDir | Out-Null }
        Copy-Item -Path $azExe.FullName -Destination (Join-Path $installDir 'azcopy.exe') -Force
    }

    $env:PATH = "$installDir;$env:PATH"
    try {
        $userPath = [Environment]::GetEnvironmentVariable('Path','User')
        if ($userPath -notlike "*$installDir*") {
            [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $installDir), 'User')
        }
    } catch {}

    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item $expandDir -Recurse -Force -ErrorAction SilentlyContinue

    $azcopyCmd = Get-Command azcopy -ErrorAction SilentlyContinue
    if (-not $azcopyCmd) { throw "AzCopy installation failed. 'azcopy' is still not available." }
    Write-Host "AzCopy installed at: $installDir"
} else {
    Write-Host "AzCopy found: $($azcopyCmd.Source)"
}


$Env:AZCOPY_SPA_CLIENT_SECRET = $AzCopyClientSecret

Write-Host "==> Logging in to AzCopy using service principal..."
& azcopy login --service-principal --application-id $AzCopyClientId --tenant-id $AzCopyTenantId | Write-Host


$artifactPath = Join-Path -Path $DropFolder -ChildPath "drop"
$destDirUrl = ($AzureStorageFileShareURI.TrimEnd('/')) + '/' + ($DirectoryName.TrimStart('/'))

Write-Host "we will copy here $artifactPath"
Write-Host "==> Copying from '$artifactPath' to '$destDirUrl' (recursive)..."
$copyArgs = @(
    'copy', $artifactPath, $destDirUrl,
    '--recursive=true',
    '--follow-symlinks=false'
)
 & azcopy @copyArgs
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    throw "AzCopy copy failed with exit code $exitCode."
}
Write-Host "Copy completed successfully."

} Catch {
	Write-Host "Unexpected Error:"
	Write-Host $_
	throw
}


