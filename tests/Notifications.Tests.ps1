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

Describe 'Graph poller solution boundary' {
    BeforeAll {
        $script:graphNotifications = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../infra/modules/graph-notifications.bicep') -Raw
        $script:pollerHost = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../infra/vendor/Azd.FlexScheduledPoller/flex-scheduled-poller-host.bicep') -Raw
        $script:pollerSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../src/risk-notification-poller/src/index.js') -Raw
    }

    It 'vendors the independently versioned Flex host behind a thin risk wrapper' {
        $script:graphNotifications | Should -Match "module pollerHost '../vendor/Azd\.FlexScheduledPoller/flex-scheduled-poller-host\.bicep'"
        $script:graphNotifications | Should -Not -Match "resource\s+\w+\s+'Microsoft\.(?:Web|Storage|Authorization)/"
        $script:pollerHost | Should -Match "Microsoft\.Web/sites@"
        $script:pollerHost | Should -Match "Microsoft\.Storage/storageAccounts@"
    }

    It 'uses the minimum Flex host size and a singleton ceiling while preserving existing state' {
        $script:graphNotifications | Should -Match 'maximumInstanceCount: 1'
        $script:graphNotifications | Should -Match 'instanceMemoryMB: 512'
        $script:pollerHost | Should -Match 'alwaysReady: \[\]'
        $script:graphNotifications | Should -Match "deploymentContainerName: 'function-releases'"
        $script:graphNotifications | Should -Match "stateContainerName: 'risk-state'"
        $script:graphNotifications | Should -Match "deadLetterContainerName: 'risk-dead-letter'"
        $script:graphNotifications | Should -Match 'blobDeleteRetentionDays: 14'
    }

    It 'does not pull Azure Monitor or Log Analytics into the polling solution' {
        $script:graphNotifications | Should -Not -Match 'Microsoft\.OperationalInsights/workspaces'
        $script:graphNotifications | Should -Not -Match 'Microsoft\.Insights/components'
        $script:graphNotifications | Should -Not -Match 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    }

    It 'uses the generic scheduled-poller storage contract' {
        $script:pollerHost | Should -Match 'AZD_POLLER_STORAGE_ACCOUNT_NAME'
        $script:pollerHost | Should -Match 'AZD_POLLER_STATE_CONTAINER'
        $script:pollerHost | Should -Match 'AZD_POLLER_DEAD_LETTER_CONTAINER'
        $script:graphNotifications | Should -Match "'AZD_CA_STORAGE_ACCOUNT_NAME'"
        $script:graphNotifications | Should -Match "'AZD_CA_STATE_CONTAINER'"
        $script:graphNotifications | Should -Match "'AZD_CA_DEAD_LETTER_CONTAINER'"
        $script:pollerSource | Should -Match 'AZD_POLLER_STORAGE_ACCOUNT_NAME'
        $script:pollerSource | Should -Match 'AZD_POLLER_STATE_CONTAINER'
        $script:pollerSource | Should -Match 'AZD_POLLER_DEAD_LETTER_CONTAINER'
        $script:pollerSource | Should -Not -Match 'AZD_CA_(?:STORAGE_ACCOUNT_NAME|STATE_CONTAINER|DEAD_LETTER_CONTAINER)'
    }
}
