param([string]$InputPath)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Authentication.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Graph.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Legacy.psm1') -Force
Import-AzdEnvironment; Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.30.0 -Force
$configuration=Get-AzdRiskCaConfiguration
if (-not $InputPath) { $InputPath=Get-AzdRiskCaDataPath 'legacy-capture.json' }
if (-not (Test-Path -LiteralPath $InputPath)) { throw "Legacy capture file not found: $InputPath. Copy docs/legacy-capture.example.json and record settings from both legacy portal pages." }
$capture=Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json -Depth 100
$tenantId=(az account show --query tenantId -o tsv).Trim(); Connect-AzdRiskCaGraph ([guid]$tenantId) $configuration | Out-Null
$migrationPath=Get-AzdRiskCaDataPath 'legacy-migration-state.json'
$existing=if(Test-Path -LiteralPath $migrationPath){Get-Content -LiteralPath $migrationPath -Raw | ConvertFrom-Json -Depth 100}else{$null}
$state=Invoke-AzdRiskCaLegacyStage $capture $configuration $tenantId $existing -Checkpoint { param($checkpointState) Save-AzdRiskCaJson $checkpointState $migrationPath }
Save-AzdRiskCaJson $state $migrationPath
Write-Host "Staged $(@($state.policies.PSObject.Properties).Count) report-only legacy replica(s). Review them before cutover."
