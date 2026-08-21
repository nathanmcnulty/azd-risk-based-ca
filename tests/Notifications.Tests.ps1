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
