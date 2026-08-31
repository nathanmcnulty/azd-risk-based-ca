Describe 'Component governance baseline' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $lockPath = Join-Path $repositoryRoot 'azd-components.lock.json'
        $schemaPath = Join-Path $repositoryRoot 'schemas/azd-components-lock.schema.json'
    }

    It 'keeps the component inventory compatible with the checked-in contract' {
        $lockJson = Get-Content -LiteralPath $lockPath -Raw
        ($lockJson | Test-Json -SchemaFile $schemaPath -ErrorAction Stop) | Should -BeTrue
    }

    It 'rejects noncanonical top-level lock properties' {
        $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json -AsHashtable
        $lock.unexpectedProperty = $true
        $invalidJson = $lock | ConvertTo-Json -Depth 100

        { $invalidJson | Test-Json -SchemaFile $schemaPath -ErrorAction Stop } | Should -Throw
    }

    It 'pins the Azure Monitor notification pilot to its reviewed release and exact vendored bytes' {
        $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json -AsHashtable
        $component = @($lock.components | Where-Object { $_.id -eq 'azure-monitor-scheduled-query-notifications' })

        $component.Count | Should -Be 1
        $component[0].version | Should -Be '0.1.0'
        $component[0].sourceRepository | Should -Be 'https://github.com/nathanmcnulty/azd-reference'
        $component[0].sourceRevision | Should -Be '3424613b6b1ba38a1af60c2ab9bea9ef973c5bed'
        @($component[0].files.target) | Should -Be @(
            'infra/vendor/Azd.AzureMonitorNotifications/logic-app-action-group.bicep',
            'infra/vendor/Azd.AzureMonitorNotifications/scheduled-query-alert.bicep'
        )

        foreach ($file in $component[0].files) {
            $actual = (Get-FileHash -LiteralPath (Join-Path $repositoryRoot $file.target) -Algorithm SHA256).Hash.ToLowerInvariant()
            $actual | Should -Be $file.sha256
        }
    }
}
