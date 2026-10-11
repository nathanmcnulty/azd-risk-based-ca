BeforeAll {
    $script:root = Split-Path -Parent $PSScriptRoot
    $script:manifestJson = Get-Content (Join-Path $script:root 'azd-permissions.json') -Raw
    $script:manifest = $script:manifestJson | ConvertFrom-Json -Depth 30
    Import-Module (Join-Path $script:root 'scripts/AzdRiskCa.Authentication.psm1') -Force
}
Describe 'Optional feature permission inventory' {
    It 'satisfies the vendored canonical schema and retains explicit partial-coverage gaps' {
        $script:manifestJson | Test-Json -SchemaFile (Join-Path $script:root 'schemas/permission-requirements.schema.json') | Should -BeTrue
        $script:manifest.coverage | Should -Be 'partial'
        $script:manifest.gaps.Count | Should -BeGreaterThan 0
    }
    It 'binds every permission claim to the actual current source bytes' {
        foreach ($row in $script:manifest.requirements) {
            foreach ($evidence in $row.evidence) {
                (Get-FileHash (Join-Path $script:root $evidence.path) -Algorithm SHA256).Hash.ToLowerInvariant() |
                    Should -BeExactly $evidence.sha256
            }
        }
    }
    It 'matches delegated selection to the actual configuration function for each mode' -ForEach @('none','graph','logAnalytics') {
        $mode = $_
        $selected = @($script:manifest.requirements | Where-Object {
            $_.kind -eq 'delegated' -and ($_.defaultEnabled -or ($_.feature -eq 'graph' -and $mode -eq 'graph'))
        } | ForEach-Object permission | Sort-Object -Unique)
        $selected | Should -Be @(Get-AzdRiskCaGraphPermissionScope $mode)
    }
    It 'keeps runtime roles optional and separate from bootstrap consent scopes' {
        $runtime = @($script:manifest.requirements | Where-Object phase -eq runtime)
        $runtime.Count | Should -Be 3
        @($runtime | Where-Object defaultEnabled).Count | Should -Be 0
        @($runtime | Where-Object kind -eq delegated).Count | Should -Be 0
        @($runtime | Where-Object permission -eq 'AppRoleAssignment.ReadWrite.All').Count | Should -Be 0
    }
}
