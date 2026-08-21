BeforeAll { Import-Module (Join-Path $PSScriptRoot '../scripts/AzdRiskCa.Common.psm1') -Force }

Describe 'Configuration parsing and safety gates' {
    BeforeEach {
        $script:names=@('AZD_CA_POLICY_STATE','AZD_CA_EMERGENCY_ACCESS_GROUP_ID','AZD_CA_ADMIN_COVERAGE_GROUP_ID','AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS','AZD_CA_USE_TAP_AUTH_STRENGTH','AZD_CA_ADOPT_EXISTING','AZD_CA_GRAPH_AUTHENTICATION_METHOD','AZD_CA_NOTIFICATION_MODE','AZD_CA_ADMIN_TEAMS_DELIVERY_MODE','AZD_CA_ADMIN_TEAMS_WORKFLOW_URL','AZD_CA_USER_TEAMS_WORKFLOW_URL','AZD_CA_ADMIN_TEAMS_CHANNEL_LINK','AZD_CA_ADMIN_TEAMS_TEAM_ID','AZD_CA_ADMIN_TEAMS_CHANNEL_ID','AZD_CA_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID','AZD_CA_LOG_ANALYTICS_WORKSPACE_LOCATION','AZD_CA_CLEANUP')
        $script:prior=@{}; foreach($name in $script:names){$script:prior[$name]=[Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name,$null)}
    }
    AfterEach { foreach($name in $script:names){[Environment]::SetEnvironmentVariable($name,$script:prior[$name])} }

    It 'defaults policies to report-only, notifications to none, and guided Teams delivery' { $c=Get-AzdRiskCaConfiguration; $c.PolicyState | Should -Be 'reportOnly'; $c.NotificationMode | Should -Be 'none'; $c.AdminTeamsDeliveryMode | Should -Be 'adminConfigured' }
    It 'allows enabled mode to defer a missing emergency group to the operator fallback plan' { $env:AZD_CA_POLICY_STATE='enabled'; (Get-AzdRiskCaConfiguration).PolicyState | Should -Be 'enabled' }
    It 'parses deterministic unique exclusion GUIDs' { $env:AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS='22222222-2222-2222-2222-222222222222,11111111-1111-1111-1111-111111111111,22222222-2222-2222-2222-222222222222'; (Get-AzdRiskCaConfiguration).AdditionalExcludeGroupIds | Should -Be @('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222') }
    It 'rejects malformed group IDs' { $env:AZD_CA_ADMIN_COVERAGE_GROUP_ID='not-a-guid'; { Get-AzdRiskCaConfiguration } | Should -Throw '*invalid GUID*' }
    It 'requires the admin callback for workflow webhook delivery' { $env:AZD_CA_NOTIFICATION_MODE='graph'; $env:AZD_CA_ADMIN_TEAMS_DELIVERY_MODE='workflowWebhook'; { Get-AzdRiskCaConfiguration } | Should -Throw '*ADMIN_TEAMS_WORKFLOW_URL*' }
    It 'accepts a copied Teams channel link for guided delivery' { $env:AZD_CA_NOTIFICATION_MODE='graph'; $env:AZD_CA_ADMIN_TEAMS_CHANNEL_LINK='https://teams.microsoft.com/l/channel/19%3Aabc%40thread.tacv2/Alerts?groupId=11111111-1111-1111-1111-111111111111&tenantId=22222222-2222-2222-2222-222222222222'; (Get-AzdRiskCaConfiguration).AdminTeamsDeliveryMode | Should -Be 'adminConfigured' }
    It 'resolves and tenant-validates copied Teams channel links' { $target=ConvertFrom-AzdRiskCaTeamsChannelLink 'https://teams.microsoft.com/l/channel/19%3Aabc%40thread.tacv2/Alerts?groupId=11111111-1111-1111-1111-111111111111&tenantId=22222222-2222-2222-2222-222222222222' ([guid]'22222222-2222-2222-2222-222222222222'); $target.TeamId | Should -Be '11111111-1111-1111-1111-111111111111'; $target.ChannelId | Should -Be '19:abc@thread.tacv2' }
    It 'rejects a Teams channel from another tenant' { { ConvertFrom-AzdRiskCaTeamsChannelLink 'https://teams.microsoft.com/l/channel/19%3Aabc%40thread.tacv2/Alerts?groupId=11111111-1111-1111-1111-111111111111&tenantId=22222222-2222-2222-2222-222222222222' ([guid]'33333333-3333-3333-3333-333333333333') } | Should -Throw '*does not match deployment tenant*' }
    It 'requires an existing workspace for Log Analytics mode' { $env:AZD_CA_NOTIFICATION_MODE='logAnalytics'; { Get-AzdRiskCaConfiguration } | Should -Throw '*WORKSPACE_RESOURCE_ID*' }
    It 'rejects undocumented policy states and pilot mode' { $env:AZD_CA_POLICY_STATE='pilot'; { Get-AzdRiskCaConfiguration } | Should -Throw '*reportOnly, enabled*' }
    It 'rejects device-code authentication' { $env:AZD_CA_GRAPH_AUTHENTICATION_METHOD='deviceCode'; { Get-AzdRiskCaConfiguration } | Should -Throw '*must be one of: browser*' }
    It 'requires an exact tenant-ID confirmation' { Assert-AzdRiskCaTenantConfirmation '11111111-1111-1111-1111-111111111111' '11111111-1111-1111-1111-111111111111'; { Assert-AzdRiskCaTenantConfirmation '11111111-1111-1111-1111-111111111111' '22222222-2222-2222-2222-222222222222' } | Should -Throw '*cancelled*' }
}
