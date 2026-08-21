$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Common.psm1') -Force
Import-AzdEnvironment
$configuration=Get-AzdRiskCaConfiguration
if (-not $configuration.Cleanup) { Write-Host 'Preserving Conditional Access policies and authentication strengths. Set AZD_CA_CLEANUP=true for explicit cleanup.'; return }
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Authentication.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Graph.psm1') -Force
Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.30.0 -Force
$state=Get-AzdRiskCaState
if (-not $state) { Write-Host 'No managed tenant state was found.'; return }
$tenantId=(az account show --query tenantId -o tsv).Trim()
if ($state.tenantId -ne $tenantId) { throw 'Saved state belongs to a different tenant; cleanup refused.' }
Connect-AzdRiskCaGraph ([guid]$tenantId) $configuration | Out-Null
Remove-AzdRiskCaManagedObjects $state -Confirm:$false
$statePath=Get-AzdRiskCaDataPath 'azd-risk-ca-state.json'
Remove-Item -LiteralPath $statePath -Force
Write-Host 'Solution-created tenant objects were deleted and adopted objects were restored. Local ownership state was removed.'
