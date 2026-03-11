# Project Scripts (Generic)

PowerShell deployment and operations scripts used to automate application and infrastructure tasks across Windows environments.

All scripts in this repository use functions from the open-source DOrcDeployModule:

- https://github.com/sefe/DOrcDeployModule

These scripts are intended to run as part of a deployment pipeline (for example, a CI/CD job) where environment variables and shared modules are already available.

## What this repository contains

This repo provides script entry points for:

- Service control (start/stop and startup type)
- Artifact copy/extract and Azure file share upload
- MSI deployment
- SQL DACPAC deployment (on-prem and Azure SQL)
- SQL restore and snapshot-based restore
- MongoDB dump/restore
- RabbitMQ topology/configuration
- Windows feature installation
- Database permission application
- Target server reachability checks

## Prerequisites

## Operating system

- Windows (PowerShell 5.1+ recommended)

## PowerShell modules and shared code

Most scripts load shared bootstrap logic from:

- `./Common/Initialize-DeployModule.ps1`

And then install/import shared modules such as:

- `DOrcDeployModule`
- `PureSSSToolkit`
- `SqlServer`
- `dbatools`
- `MDBC`

`DOrcDeployModule` is the primary shared function library used by all scripts in this repo and is maintained as open source in the same GitHub project space:

- https://github.com/sefe/DOrcDeployModule

Note: the `Common` folder and some modules are expected to come from your internal deployment ecosystem and are not included in this repository.

## External tools

Depending on the script, you may also need:

- `SqlPackage.exe` (DACPAC deployment)
- `azcopy` (Azure file share upload; one script can install it automatically)
- `mongodump` / `mongorestore` (Mongo restore script)
- RabbitMQ Management API access

## Authentication and variables

Scripts rely heavily on runtime properties/variables (for example: `DropFolder`, `EnvironmentName`, DB server mappings, service account credentials).

Each script validates required properties using `Test-RequiredProperties` and exits on missing values.

## Execution model

Run scripts from a pipeline or shell that has all required variables preloaded.

Typical invocation pattern:

```powershell
# Example: run from repo root in a prepared deployment session
Set-Location .\project-scripts-generic

$EnvironmentName = "DEV"
$DropFolder = "C:\Deploy\Drops\Current"

.\ControlServices.ps1
```

Important:

- Scripts do not define explicit CLI parameters in `param(...)`; they read from pre-set variables.
- Most scripts throw on first error (`try/catch` with rethrow), which is pipeline-friendly.

## Script catalog

| Script | Purpose | Key expected properties (examples) |
|---|---|---|
| `ApplyPermissions.ps1` | Apply DB permissions to target databases based on DACPAC metadata. | `DropFolder`, `dacpacName`, DB target variables |
| `CheckIfServerIsLive.ps1` | Verify target servers are reachable and manageable before deployment. | `EnvironmentName`, EnvMgt DB settings, deployment account |
| `ConfigureRabbitMQ.ps1` | Create/validate exchanges/queues/bindings via RabbitMQ Management API from JSON config. | `DropFolder`, `RMQConfigFileName`, `RMQManagementApiUrl`, credentials |
| `ControlServices.ps1` | Start/stop services on servers by server type. | `action`, `serverTypes`, `services`, retry settings |
| `ControlServicesStartupType.ps1` | Set Windows service startup type on target servers. | `ServerTypes`, `Services`, `ServiceStartupType` |
| `CopyAndExtractArtifacts.ps1` | Copy build artifacts to destination paths, extract zip files, remove zips. | `DropFolder`, `DestinationToCopyPath` |
| `CopyArtifactsToStorageAccount.ps1` | Copy artifacts to Azure file share using AzCopy and service principal credentials. | `DropFolder`, `AzureStorageFileShareURI`, AzCopy SPN vars |
| `DeployDacpac.ps1` | Deploy DACPAC to SQL Server targets (supports selective target deployment). | `DropFolder`, `dacpacName`, `SQLPackagePath`, publish profile vars |
| `DeployDacpacAzure.ps1` | Deploy DACPAC to Azure SQL using access token auth. | `DropFolder`, `dacpacName`, `sqlPackagePath`, Azure token settings |
| `DeployMSI.ps1` | Deploy MSI package to target servers and validate product names. | `DropFolder`, `msiName`, `productNames`, EnvMgt vars |
| `RestoreDatabase.ps1` | Restore SQL database between environments with safety checks. | `RestoreMode`, `RestoreSource`, `dacpacName`, restore/drop tooling paths |
| `RestoreMongoDB.ps1` | Dump selected Mongo collections and restore into target DB, with optional cleanup. | Mongo connection vars, collection list, dump folder |
| `SnapRestoreDatabase.ps1` | Snapshot-based SQL restore using Pure toolkit (current versioned script). | `DropFolder`, EnvMgt vars, restore vars |
| `SnapRestoreDatabase_V1.ps1` | Legacy snapshot-based restore flow. | Similar to `SnapRestoreDatabase.ps1` |
| `WindowsFeatures.ps1` | Install Windows features on target server types. | deployment account vars, `BaseBuildFeatures`, `CoreCodeSxSFolder` |

## Common examples

## 1) Stop services on API and Worker server groups

```powershell
$EnvironmentName = "TEST"
$action = "stop"
$serverTypes = "API;Worker"
$services = "MyApiService;MyWorkerService"
$retryCount = 10
$retryTime = 15

.\ControlServices.ps1
```

## 2) Copy artifacts and extract packages

```powershell
$DropFolder = "C:\Deploy\Drop"
$DestinationToCopyPath = "D:\Apps\SiteA;D:\Apps\SiteB"

.\CopyAndExtractArtifacts.ps1
```

## 3) Deploy a DACPAC

```powershell
$DropFolder = "C:\Deploy\Drop"
$dacpacName = "MyDatabase.dacpac"
$SQLPackagePath = "C:\Tools\SqlPackage\SqlPackage.exe"

.\DeployDacpac.ps1
```

## Troubleshooting

- Missing property errors: check required variables for the script and ensure they are set in the current session/pipeline.
- Module import/install errors: verify access to your internal repository and PowerShell gallery sources used by your organization.
- Access/permission failures on remote servers: validate deployment account rights and network connectivity.
- Artifact path issues: ensure `DropFolder` and all destination paths exist and are accessible to the executing identity.

## Contributing

When adding or updating scripts:

- Keep the `try/catch` fail-fast pattern.
- Validate required properties early with `Test-RequiredProperties`.
- Prefer idempotent operations and clear `Write-Host`/`Write-Output` messages.
- Update this README script catalog with new scripts or changed prerequisites.
