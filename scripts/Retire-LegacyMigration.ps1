$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Authentication.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Graph.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Legacy.psm1') -Force
Import-AzdEnvironment; Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.30.0 -Force
$configuration=Get-AzdRiskCaConfiguration; $migrationPath=Get-AzdRiskCaDataPath 'legacy-migration-state.json'
if (-not (Test-Path -LiteralPath $migrationPath)) { throw 'No legacy migration state exists.' }
$migration=Get-Content -LiteralPath $migrationPath -Raw | ConvertFrom-Json -Depth 100; $recommended=Get-AzdRiskCaState
if (-not $recommended) { throw 'No recommendation ownership state exists.' }
$tenantId=(az account show --query tenantId -o tsv).Trim(); Connect-AzdRiskCaGraph ([guid]$tenantId) $configuration | Out-Null
$confirmation=Read-Host "Type tenant ID $tenantId to verify all nine recommendations are enabled and disable the rollback replicas"
Assert-AzdRiskCaTenantConfirmation $tenantId $confirmation
$migration=Invoke-AzdRiskCaLegacyRetire $migration $recommended $tenantId
Save-AzdRiskCaJson $migration $migrationPath
Write-Host 'Legacy migrated replicas are disabled and retained for rollback. No replica was deleted.'
