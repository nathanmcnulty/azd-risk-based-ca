Describe 'Azure Deployment Studio manifest' {
    BeforeAll {
        $script:manifestPath=Join-Path $PSScriptRoot '../azd-gui.json'
        $script:manifest=Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json -Depth 100
    }

    It 'registers delegated Graph consent as a blocking preflight check' {
        $check=@($script:manifest.permissionChecks | Where-Object id -eq 'graph-delegated-scopes')
        $check.Count | Should -Be 1
        $check[0].provider | Should -Be 'graph'
        $check[0].required | Should -BeTrue
    }

    It 'declares baseline scopes without eagerly requesting notification-only consent' {
        $connection=$script:manifest.connections | Where-Object id -eq 'graphPowerShell'
        $connection.scopes | Should -Contain 'Policy.ReadWrite.ConditionalAccess'
        $connection.scopes | Should -Contain 'RoleManagement.Read.Directory'
        $connection.scopes | Should -Contain 'AuditLog.Read.All'
        $connection.scopes | Should -Contain 'IdentityRiskyUser.Read.All'
        $connection.scopes | Should -Not -Contain 'User.Read.All'
        $connection.scopes | Should -Not -Contain 'Application.Read.All'
        $connection.scopes | Should -Not -Contain 'AppRoleAssignment.ReadWrite.All'
    }

    It 'does not expose a device-code authentication option' {
        $graphAuth=$script:manifest.configuration.groups.fields | Where-Object id -eq 'graphAuth'
        @($graphAuth.options.value) | Should -Be @('browser')
    }
}
