$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Authentication.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Graph.psm1') -Force
Import-AzdEnvironment
Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.30.0 -Force
$configuration=Get-AzdRiskCaConfiguration
$tenantId=(az account show --query tenantId -o tsv).Trim()
Connect-AzdRiskCaGraph ([guid]$tenantId) $configuration | Out-Null
$state=Get-AzdRiskCaState
if (-not $state) { throw 'No managed state exists. Run azd provision first.' }
$plan=New-AzdRiskCaPlan $configuration $state
$validation=Test-AzdRiskCaAppliedState $plan $state
$status=[pscustomobject]@{ schemaVersion='1.0'; checkedAt=[DateTimeOffset]::UtcNow.ToString('o'); tenantId=$tenantId; valid=$validation.valid; failures=$validation.failures; policies=@($plan.policies | Select-Object displayName,id,action); warnings=$plan.warnings }
$path=Join-Path (Split-Path -Parent $PSScriptRoot) 'reports/azd-risk-ca-status.json'
Save-AzdRiskCaJson $status $path
$status | ConvertTo-Json -Depth 20
