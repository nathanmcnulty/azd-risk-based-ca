BeforeAll { Import-Module (Join-Path $PSScriptRoot '../scripts/AzdRiskCa.Common.psm1') -Force }

Describe 'Configuration parsing and safety gates' {
    BeforeEach {
        $script:names=@('AZD_CA_POLICY_STATE','AZD_CA_EMERGENCY_ACCESS_GROUP_ID','AZD_CA_ADMIN_COVERAGE_GROUP_ID','AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS','AZD_CA_USE_TAP_AUTH_STRENGTH','AZD_CA_ADOPT_EXISTING','AZD_CA_GRAPH_AUTHENTICATION_METHOD','AZD_CA_NOTIFICATION_MODE','AZD_CA_ADMIN_TEAMS_WORKFLOW_URL','AZD_CA_USER_TEAMS_WORKFLOW_URL','AZD_CA_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID','AZD_CA_LOG_ANALYTICS_WORKSPACE_LOCATION','AZD_CA_CLEANUP')
        $script:prior=@{}; foreach($name in $script:names){$script:prior[$name]=[Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name,$null)}
    }
    AfterEach { foreach($name in $script:names){[Environment]::SetEnvironmentVariable($name,$script:prior[$name])} }

    It 'defaults policies to report-only and notifications to none' { $c=Get-AzdRiskCaConfiguration; $c.PolicyState | Should -Be 'reportOnly'; $c.NotificationMode | Should -Be 'none' }
    It 'allows enabled mode to defer a missing emergency group to the operator fallback plan' { $env:AZD_CA_POLICY_STATE='enabled'; (Get-AzdRiskCaConfiguration).PolicyState | Should -Be 'enabled' }
    It 'parses deterministic unique exclusion GUIDs' { $env:AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS='22222222-2222-2222-2222-222222222222,11111111-1111-1111-1111-111111111111,22222222-2222-2222-2222-222222222222'; (Get-AzdRiskCaConfiguration).AdditionalExcludeGroupIds | Should -Be @('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222') }
    It 'rejects malformed group IDs' { $env:AZD_CA_ADMIN_COVERAGE_GROUP_ID='not-a-guid'; { Get-AzdRiskCaConfiguration } | Should -Throw '*invalid GUID*' }
    It 'requires the admin callback for notifications' { $env:AZD_CA_NOTIFICATION_MODE='graph'; { Get-AzdRiskCaConfiguration } | Should -Throw '*ADMIN_TEAMS_WORKFLOW_URL*' }
    It 'requires an existing workspace for Log Analytics mode' { $env:AZD_CA_NOTIFICATION_MODE='logAnalytics'; $env:AZD_CA_ADMIN_TEAMS_WORKFLOW_URL='https://example.test/secret'; { Get-AzdRiskCaConfiguration } | Should -Throw '*WORKSPACE_RESOURCE_ID*' }
    It 'rejects undocumented policy states and pilot mode' { $env:AZD_CA_POLICY_STATE='pilot'; { Get-AzdRiskCaConfiguration } | Should -Throw '*reportOnly, enabled*' }
    It 'rejects device-code authentication' { $env:AZD_CA_GRAPH_AUTHENTICATION_METHOD='deviceCode'; { Get-AzdRiskCaConfiguration } | Should -Throw '*must be one of: browser*' }
    It 'requires an exact tenant-ID confirmation' { Assert-AzdRiskCaTenantConfirmation '11111111-1111-1111-1111-111111111111' '11111111-1111-1111-1111-111111111111'; { Assert-AzdRiskCaTenantConfirmation '11111111-1111-1111-1111-111111111111' '22222222-2222-2222-2222-222222222222' } | Should -Throw '*cancelled*' }
}
