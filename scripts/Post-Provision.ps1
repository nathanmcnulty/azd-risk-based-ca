$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Authentication.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Graph.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Notifications.psm1') -Force
Import-AzdEnvironment
Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.30.0 -Force
$configuration=Get-AzdRiskCaConfiguration
$tenantId=(az account show --query tenantId -o tsv).Trim()
Connect-AzdRiskCaGraph ([guid]$tenantId) $configuration | Out-Null
$existingState=Get-AzdRiskCaState
$plan=New-AzdRiskCaPlan $configuration $existingState
$state=Invoke-AzdRiskCaApply $plan $existingState -Checkpoint { param($checkpointState) Save-AzdRiskCaState $checkpointState } -Confirm:$false
Save-AzdRiskCaState $state

if ($configuration.NotificationMode -eq 'graph') {
    if ([string]::IsNullOrWhiteSpace($env:AZD_CA_GRAPH_FUNCTION_PRINCIPAL_ID) -or [string]::IsNullOrWhiteSpace($env:AZD_CA_GRAPH_FUNCTION_NAME)) { throw 'Graph notification infrastructure outputs are missing.' }
    Grant-AzdRiskCaIdentityRiskPermission $env:AZD_CA_GRAPH_FUNCTION_PRINCIPAL_ID
    Publish-AzdRiskCaGraphFunction $env:AZD_CA_GRAPH_FUNCTION_NAME
}

$validationPlan=New-AzdRiskCaPlan $configuration $state
$validation=Test-AzdRiskCaAppliedState $validationPlan $state
$report=[pscustomobject]@{ schemaVersion='1.0'; validatedAt=[DateTimeOffset]::UtcNow.ToString('o'); tenantId=$tenantId; policyState=$configuration.PolicyState; valid=$validation.valid; failures=$validation.failures; policyCount=@($validationPlan.policies).Count; notificationMode=$configuration.NotificationMode }
$reportPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'reports/azd-risk-ca-applied.json'
Save-AzdRiskCaJson $report $reportPath
if (-not $validation.valid) { throw "Post-deployment validation failed: $($validation.failures -join '; ')" }
Write-Host "Nine Conditional Access policies are reconciled and verified in $($configuration.PolicyState) state. Report: $reportPath"
