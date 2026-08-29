Describe 'Administrator documentation and deployment packaging' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        $script:readme = Get-Content (Join-Path $script:root 'README.md') -Raw
        $script:notifications = Get-Content (Join-Path $script:root 'scripts/AzdRiskCa.Notifications.psm1') -Raw
        $script:postprovision = Get-Content (Join-Path $script:root 'scripts/Post-Provision.ps1') -Raw
        $script:configurationGuide = Get-Content (Join-Path $script:root 'docs/configuration.md') -Raw
        $script:policyGuide = Get-Content (Join-Path $script:root 'docs/policies-and-safety.md') -Raw
    }

    It 'keeps every deployed policy definition in this repository' {
        $manifest = Get-Content (Join-Path $script:root 'policies/manifest.json') -Raw | ConvertFrom-Json
        $manifest.schemaVersion | Should -Be '1.0'
        @($manifest.policies).Count | Should -Be 9
        @($manifest.policies | Sort-Object -Unique).Count | Should -Be 9
        foreach ($file in $manifest.policies) {
            $path = Join-Path $script:root "policies/$file"
            (Test-Path -LiteralPath $path -PathType Leaf) | Should -BeTrue
            $definition = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $definition.displayName | Should -Be ([IO.Path]::GetFileNameWithoutExtension($file))
        }
        $script:policyGuide | Should -Not -Match 'nathanmcnulty/nathanmcnulty'
        $script:policyGuide | Should -Match 'No policy definition is downloaded from another repository'
    }

    It 'keeps the administrator quickstart free of Node prerequisites' {
        $script:readme | Should -Match 'azd init -t nathanmcnulty/azd-risk-based-ca && azd up'
        $script:readme | Should -Not -Match '(?i)Node\.js.*(required|prerequisite)'
        $script:readme | Should -Match 'docs/development\.md'
    }

    It 'links every focused administrator guide' {
        foreach ($path in @(
            'docs/policies-and-safety.md', 'docs/identity-and-permissions.md',
            'docs/configuration.md', 'docs/historical-impact.md', 'docs/notifications.md',
            'docs/legacy-migration.md', 'docs/operations-and-cleanup.md',
            'docs/development.md', 'docs/agent-assisted-deployment.md')) {
            (Test-Path (Join-Path $script:root $path)) | Should -BeTrue
            $script:readme | Should -Match ([regex]::Escape($path))
        }
    }

    It 'documents every administrator-facing configuration value' {
        foreach ($name in @(
            'AZD_CA_POLICY_STATE', 'AZD_CA_EMERGENCY_ACCESS_GROUP_ID',
            'AZD_CA_ADMIN_COVERAGE_GROUP_ID', 'AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS',
            'AZD_CA_USE_TAP_AUTH_STRENGTH', 'AZD_CA_ADOPT_EXISTING',
            'AZD_CA_GRAPH_AUTHENTICATION_METHOD', 'AZD_CA_NOTIFICATION_MODE',
            'AZD_CA_ADMIN_TEAMS_DELIVERY_MODE', 'AZD_CA_ADMIN_TEAMS_WORKFLOW_URL',
            'AZD_CA_USER_TEAMS_WORKFLOW_URL', 'AZD_CA_ADMIN_TEAMS_CHANNEL_LINK',
            'AZD_CA_ADMIN_TEAMS_TEAM_ID', 'AZD_CA_ADMIN_TEAMS_CHANNEL_ID',
            'AZD_CA_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID', 'AZD_CA_LOG_ANALYTICS_WORKSPACE_LOCATION',
            'AZD_CA_TEST_TEAMS_DELIVERY', 'AZD_CA_CLEANUP', 'AZD_CA_SETUP_COMPLETE')) {
            $script:configurationGuide | Should -Match ([regex]::Escape($name))
        }
    }

    It 'uses Azure remote build and does not run npm during deployment' {
        $script:notifications | Should -Match '--build-remote true'
        $script:notifications | Should -Not -Match '(?m)^\s*npm\s+(install|ci)\b'
        $script:notifications | Should -Match "Name -notin @\('node_modules','dist'\)"
    }

    It 'prepares Graph notification deployment before Conditional Access apply' {
        $publish = $script:postprovision.IndexOf('Publish-AzdRiskCaGraphFunction')
        $grant = $script:postprovision.IndexOf('Grant-AzdRiskCaIdentityRiskPermission')
        $apply = $script:postprovision.IndexOf('Invoke-AzdRiskCaApply')
        $publish | Should -BeGreaterThan -1
        $grant | Should -BeGreaterThan -1
        $apply | Should -BeGreaterThan -1
        $publish | Should -BeLessThan $apply
        $publish | Should -BeLessThan $grant
        $grant | Should -BeLessThan $apply
    }
}
