$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Wizard.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Authentication.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Graph.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Impact.psm1') -Force

Import-AzdEnvironment
Invoke-AzdRiskCaFirstRunWizard | Out-Null
$defaults = [ordered]@{
    AZD_CA_POLICY_STATE='reportOnly'; AZD_CA_EMERGENCY_ACCESS_GROUP_ID=''; AZD_CA_ADMIN_COVERAGE_GROUP_ID=''
    AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS=''; AZD_CA_USE_TAP_AUTH_STRENGTH='false'; AZD_CA_ADOPT_EXISTING='false'
    AZD_CA_GRAPH_AUTHENTICATION_METHOD='browser'; AZD_CA_NOTIFICATION_MODE='none'; AZD_CA_ADMIN_TEAMS_WORKFLOW_URL=''
    AZD_CA_USER_TEAMS_WORKFLOW_URL=''; AZD_CA_ADMIN_TEAMS_DELIVERY_MODE='adminConfigured'; AZD_CA_ADMIN_TEAMS_CHANNEL_LINK=''
    AZD_CA_ADMIN_TEAMS_TEAM_ID=''; AZD_CA_ADMIN_TEAMS_CHANNEL_ID=''; AZD_CA_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID=''; AZD_CA_LOG_ANALYTICS_WORKSPACE_LOCATION=''
    AZD_CA_TEST_TEAMS_DELIVERY='false'; AZD_CA_TEAMS_AUTHORIZED='false'; AZD_CA_CLEANUP='false'
}
foreach ($entry in $defaults.GetEnumerator()) {
    if ($null -eq [Environment]::GetEnvironmentVariable($entry.Key)) { Set-AzdEnvironmentValue $entry.Key $entry.Value }
}

$module = Get-Module -ListAvailable Microsoft.Graph.Authentication | Sort-Object Version -Descending | Select-Object -First 1
if (-not $module -or $module.Version -lt [version]'2.30.0') { throw 'Microsoft.Graph.Authentication 2.30.0 or later is required. Install-PSResource Microsoft.Graph.Authentication -Scope CurrentUser' }
Import-Module Microsoft.Graph.Authentication -MinimumVersion 2.30.0 -Force
$configuration=Get-AzdRiskCaConfiguration
$tenantId=(az account show --query tenantId -o tsv)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tenantId)) { throw 'Azure CLI is not signed in. Run az login for the intended tenant.' }
$tenantId=$tenantId.Trim()
if ($configuration.NotificationMode -ne 'none' -and $configuration.AdminTeamsDeliveryMode -eq 'adminConfigured') {
    if (-not $configuration.AdminTeamsChannelLink -and (-not $configuration.AdminTeamsTeamId -or -not $configuration.AdminTeamsChannelId)) {
        if (-not [Console]::IsInputRedirected) {
            Write-Host 'In Microsoft Teams, right-click the target channel, select Copy link, then paste it here.'
            $channelLink=Read-Host 'Teams channel link'
            if ($channelLink) {
                Set-AzdEnvironmentValue AZD_CA_ADMIN_TEAMS_CHANNEL_LINK $channelLink
                $configuration.AdminTeamsChannelLink=$channelLink
            }
        }
    }
    if ($configuration.AdminTeamsChannelLink) {
        $target=ConvertFrom-AzdRiskCaTeamsChannelLink $configuration.AdminTeamsChannelLink ([guid]$tenantId)
        Set-AzdEnvironmentValue AZD_CA_ADMIN_TEAMS_TEAM_ID $target.TeamId
        Set-AzdEnvironmentValue AZD_CA_ADMIN_TEAMS_CHANNEL_ID $target.ChannelId
        $configuration.AdminTeamsTeamId=$target.TeamId
        $configuration.AdminTeamsChannelId=$target.ChannelId
    }
    if (-not $configuration.AdminTeamsTeamId -or -not $configuration.AdminTeamsChannelId) { throw 'Admin-configured Teams delivery could not resolve the team and channel IDs.' }
}
Connect-AzdRiskCaGraph ([guid]$tenantId) $configuration | Out-Null
$plan=New-AzdRiskCaPlan $configuration (Get-AzdRiskCaState)
$reportPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'reports/azd-risk-ca-plan.json'
Save-AzdRiskCaJson $plan $reportPath
$impactReportPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'reports/azd-risk-ca-historical-impact.json'
try {
    $impact=Get-AzdRiskCaHistoricalImpact $plan
    Save-AzdRiskCaJson $impact $impactReportPath
    Write-Host $impact.estimate.summary
    Write-Host "Historical impact report: $impactReportPath"
} catch {
    Write-Warning "Historical impact analysis was unavailable and did not block the Conditional Access plan. $($_.Exception.Message)"
}
$identityProtectionLinks=Get-AzdRiskCaIdentityProtectionLinks
Write-Host "Risky users report: $($identityProtectionLinks.riskyUsers)"
Write-Host "Risky sign-ins report: $($identityProtectionLinks.riskySignIns)"

Write-Host "Conditional Access plan for tenant ${tenantId}: $(@($plan.policies | Where-Object action -eq 'create').Count) create, $(@($plan.policies | Where-Object action -eq 'update').Count) update, $(@($plan.policies | Where-Object action -eq 'none').Count) unchanged."
foreach ($warning in $plan.warnings) { Write-Warning $warning }
Write-Host "Full plan: $reportPath"
if ($configuration.PolicyState -eq 'enabled') {
    $confirmation=Read-Host "Type tenant ID $tenantId to authorize enabled Conditional Access policies"
    Assert-AzdRiskCaTenantConfirmation $tenantId $confirmation
    $migrationPath=Get-AzdRiskCaDataPath 'legacy-migration-state.json'
    if (Test-Path -LiteralPath $migrationPath) {
        $migration=Get-Content -LiteralPath $migrationPath -Raw | ConvertFrom-Json -Depth 100
        if ($migration.stage -in @('staged','cutoverIncomplete')) { throw 'Legacy migration is pending. Complete cutover or retire the migration before enabling the nine recommended policies.' }
    }
}
