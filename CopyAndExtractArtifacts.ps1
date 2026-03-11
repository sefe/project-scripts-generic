Try {
# global catch block start
. ".\Common\Initialize-DeployModule.ps1"

Install-DeployModuleFromRepo -moduleName "DOrcDeployModule"

Test-RequiredProperties @("DropFolder", "DeploymentServiceAccountPassword", "DeploymentServiceAccount", "DestinationToCopyPath")
Write-Host "Required system properties found....";

if (-not (Test-Path -Path $DropFolder)) {
    throw "Error: The $DropFolder path does not exist"
}

$ErrorActionPreference = "Stop"

$filesInDropFolder = Get-ChildItem -Path $DropFolder -Recurse
if ($filesInDropFolder.Count -eq 0) {
    throw "No files or folders found in $DropFolder."
} else {
    Write-Host "Files in $DropFolder. Proceeding with copying to destination."
}

$DestinationPaths = $DestinationToCopyPath -split ';'

foreach ($folder in $DestinationPaths){

    try {
        if (-not (Test-Path -Path $folder)) {
            throw "Error: Path $folder path does not exist"
        }

    }
    catch {
        Write-Host "Error: $_" 
        throw
    }

    $filesInDestination = Get-ChildItem -LiteralPath $folder -Recurse
    If ($filesInDestination.Count -gt 0){
    Write-host "Removing $($filesInDestination.Count) files found in $folder"
    Remove-Item -Path "$folder\*" -Recurse -Force
    }

    Copy-Item -Path "$DropFolder\drop\*" -Destination $folder -Recurse -Force
    Write-Host "All content from $DropFolder has been copied to $folder."

    $DestinationZipFiles = Get-ChildItem -Path $folder -Filter *.zip
    if ($DestinationZipFiles.Count -eq 0) {
        Write-Host "No zip files found in $folder."
    } else {
        Write-Host "$($DestinationZipFiles.Count) zip file(s) found in $folder."
        
        foreach ($ZipFile in $DestinationZipFiles) {
            try {
                $ExtractionPath = $ZipFile.DirectoryName
                Write-Host "Extracting: $($ZipFile.FullName) to $ExtractionPath"
                
                Expand-Archive -Path $ZipFile.FullName -DestinationPath $ExtractionPath -Force

                Remove-Item -Path $ZipFile.FullName -Force
                Write-Host "Extracted and removed: $($ZipFile.FullName)"
            } catch {
                Write-Host "An error occurred while extracting $($ZipFile.FullName): $_"
            }
        }
    }
}
# global catch block end
} Catch {
	Write-Host "Unexpected Error:"
	Write-Host $_
	throw
}
