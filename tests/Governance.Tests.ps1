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
}
