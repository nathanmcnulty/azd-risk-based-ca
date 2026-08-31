BeforeAll { Import-Module (Join-Path $PSScriptRoot '../scripts/AzdRiskCa.Notifications.psm1') -Force }

Describe 'Guided Teams API connection' {
    BeforeAll {
        $script:main=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../infra/main.bicep') -Raw
        $script:adapter=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../infra/modules/teams-delivery.bicep') -Raw
        $script:post=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../scripts/Post-Provision.ps1') -Raw
    }
    It 'creates a disabled Teams connection adapter and never outputs its callback' {
        $script:adapter | Should -Match "Microsoft.Web/connections@2016-06-01"
        $script:adapter | Should -Match "state: 'Disabled'"
        $script:adapter | Should -Match '@secure\(\)\s*output callbackUrl string = listCallbackUrl'
        $script:main | Should -Not -Match '(?im)^\s*output\s+\S*callback'
    }
    It 'uses the Teams adaptive-card connector contract' {
        $script:adapter | Should -Match '/v1.0/teams/conversation/adaptivecard/poster/'
        $script:adapter | Should -Match "messageBody: '@triggerBody"
        $script:adapter | Should -Match "statusCode: 502"
    }
    It 'performs browser OAuth authorization before enabling and testing delivery' {
        $module=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../scripts/AzdRiskCa.Notifications.psm1') -Raw
        $module | Should -Match 'listConsentLinks\?api-version=2016-06-01'
        $module | Should -Match 'Start-Process \$Url'
        $module | Should -Not -Match 'UseDevice'
        $script:post.IndexOf('Complete-AzdRiskCaTeamsConnectionAuthorization') | Should -BeLessThan $script:post.IndexOf('Invoke-AzdRiskCaApply')
        $script:post.IndexOf('Enable-AzdRiskCaTeamsWorkflow') | Should -BeLessThan $script:post.IndexOf('Test-AzdRiskCaTeamsWorkflowDelivery')
    }
    It 'keeps Function and Storage keys out of poller validation output' {
        $poller=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../scripts/Test-GraphPoller.ps1') -Raw
        $poller | Should -Match 'keys\.masterKey'
        $poller | Should -Match 'storage account keys list'
        $poller | Should -Not -Match 'Write-(Host|Output).*masterKey'
        $poller | Should -Not -Match 'Write-(Host|Output).*storageKey'
    }
    It 'never prints the Teams consent bearer URL' {
        $module=Get-Content -LiteralPath (Join-Path $PSScriptRoot '../scripts/AzdRiskCa.Notifications.psm1') -Raw
        $module | Should -Not -Match 'Write-(Host|Output)\s+\$consent\.link'
        $module | Should -Match 'URL is intentionally not printed'
    }
}

Describe 'Azure Monitor scheduled-query notification boundary' {
    BeforeAll {
        $script:logAnalyticsNotifications = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../infra/modules/log-analytics-notifications.bicep') -Raw
        $script:actionGroupModule = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../infra/vendor/Azd.AzureMonitorNotifications/logic-app-action-group.bicep') -Raw
        $script:scheduledQueryAlertModule = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../infra/vendor/Azd.AzureMonitorNotifications/scheduled-query-alert.bicep') -Raw
    }

    It 'delegates only the reviewed Azure Monitor resources to the vendored pilot modules' {
        $script:logAnalyticsNotifications | Should -Match "module actionGroup '../vendor/Azd\.AzureMonitorNotifications/logic-app-action-group\.bicep'"
        $script:logAnalyticsNotifications | Should -Match "module alert '../vendor/Azd\.AzureMonitorNotifications/scheduled-query-alert\.bicep'"
        $script:logAnalyticsNotifications | Should -Not -Match "resource actionGroup 'Microsoft\.Insights/actionGroups@"
        $script:logAnalyticsNotifications | Should -Not -Match "resource alert 'Microsoft\.Insights/scheduledQueryRules@"
    }

    It 'preserves the risk-specific notification contract and resource dependencies' {
        $script:logAnalyticsNotifications | Should -Match "actionGroupName: 'risk-la-\$\{suffix\}'"
        $script:logAnalyticsNotifications | Should -Match "groupShortName: 'Entra risk'"
        $script:logAnalyticsNotifications | Should -Match 'logicAppResourceId: workflow\.id'
        $script:logAnalyticsNotifications | Should -Match "receiverName: 'Risk notification workflow'"
        $script:logAnalyticsNotifications | Should -Match "alertRuleName: 'entra-risk-\$\{suffix\}'"
        $script:logAnalyticsNotifications | Should -Match 'workspaceResourceId: workspaceResourceId'
        $script:logAnalyticsNotifications | Should -Match 'actionGroupResourceId: actionGroup\.outputs\.actionGroupResourceId'
        $script:logAnalyticsNotifications | Should -Match "displayName: 'Microsoft Entra risk detection'"
        $script:logAnalyticsNotifications | Should -Match "alertDescription: 'Uses existing RiskyUsers and UserRiskEvents logs; does not create a workspace or require Sentinel\.'"
        $script:logAnalyticsNotifications | Should -Match "evaluationFrequency: 'PT5M'"
        $script:logAnalyticsNotifications | Should -Match "windowSize: 'PT10M'"
        $script:logAnalyticsNotifications | Should -Match 'autoMitigate: false'
        $script:logAnalyticsNotifications | Should -Match "name: 'Envelope'"
        $script:logAnalyticsNotifications | Should -Match "operator: 'Include'"
        $script:logAnalyticsNotifications | Should -Match "values: \['\*'\]"
        $script:logAnalyticsNotifications | Should -Match 'query: riskQuery'
        $script:logAnalyticsNotifications | Should -Match 'tags: tags'
    }

    It 'keeps the shared resources at the existing API versions and Azure Monitor semantics' {
        $script:actionGroupModule | Should -Match "Microsoft\.Insights/actionGroups@2023-01-01"
        $script:actionGroupModule | Should -Match "logicAppTriggerName string = 'manual'"
        $script:actionGroupModule | Should -Match 'useCommonAlertSchema: true'
        $script:scheduledQueryAlertModule | Should -Match "Microsoft\.Insights/scheduledQueryRules@2023-12-01"
        $script:scheduledQueryAlertModule | Should -Match "timeAggregation: 'Count'"
        $script:scheduledQueryAlertModule | Should -Match "operator: 'GreaterThan'"
        $script:scheduledQueryAlertModule | Should -Match 'threshold: 0'
        $script:scheduledQueryAlertModule | Should -Match 'numberOfEvaluationPeriods: 1'
        $script:scheduledQueryAlertModule | Should -Match 'minFailingPeriodsToAlert: 1'
        $script:scheduledQueryAlertModule | Should -Match 'enabled: true'
    }
}
