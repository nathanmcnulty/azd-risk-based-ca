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

if ($configuration.NotificationMode -ne 'none' -and $configuration.AdminTeamsDeliveryMode -eq 'adminConfigured') {
    if (-not $env:AZD_CA_TEAMS_CONNECTION_RESOURCE_ID -or -not $env:AZD_CA_TEAMS_WORKFLOW_RESOURCE_ID) { throw 'Teams delivery infrastructure outputs are missing.' }
    if (-not (Complete-AzdRiskCaTeamsConnectionAuthorization $env:AZD_CA_TEAMS_CONNECTION_RESOURCE_ID ([guid]$tenantId))) { throw 'Teams connection authorization was skipped; the delivery workflow remains disabled.' }
    Enable-AzdRiskCaTeamsWorkflow $env:AZD_CA_TEAMS_WORKFLOW_RESOURCE_ID
    $testDelivery=ConvertTo-AzdRiskCaBoolean $env:AZD_CA_TEST_TEAMS_DELIVERY $false 'AZD_CA_TEST_TEAMS_DELIVERY'
    if ($testDelivery -or $env:AZD_CA_TEAMS_AUTHORIZED -ne 'true') {
        Test-AzdRiskCaTeamsWorkflowDelivery $env:AZD_CA_TEAMS_WORKFLOW_RESOURCE_ID
        Set-AzdEnvironmentValue AZD_CA_TEAMS_AUTHORIZED 'true'
    }
}

$existingState=Get-AzdRiskCaState
$plan=New-AzdRiskCaPlan $configuration $existingState
try {
    $state=Invoke-AzdRiskCaApply $plan $existingState -Checkpoint { param($checkpointState) Save-AzdRiskCaState $checkpointState } -Confirm:$false
} catch {
    $statePath=Get-AzdRiskCaDataPath 'azd-risk-ca-state.json'
    if(-not $_.Exception.Data['AzdRiskCaRollbackIncomplete']){
        if($existingState){ Save-AzdRiskCaState $existingState }
        elseif(Test-Path -LiteralPath $statePath){ Remove-Item -LiteralPath $statePath -Force }
    }
    throw
}
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
