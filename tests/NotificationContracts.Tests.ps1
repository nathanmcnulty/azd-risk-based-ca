Describe 'Offline workflow audience contract' {
    BeforeAll {
        $script:contractGate = Join-Path $PSScriptRoot '../scripts/Test-NotificationContracts.ps1'
        $script:definitionPath = Join-Path $PSScriptRoot '../infra/modules/logic-app-definition.json'
    }
    It 'accepts the actual solution workflow definition' {
        { & $script:contractGate } | Should -Not -Throw
    }
    It 'rejects an empty definition instead of claiming that no audiences means valid' {
        { & $script:contractGate -Definition @{} } | Should -Throw '*no Storage managed-identity audience*'
    }
    It 'rejects missing or incorrect managed-identity audiences' -ForEach @('', 'https://graph.microsoft.com', $null) {
        $definition = Get-Content $script:definitionPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100
        $definition.actions.Check_seed_marker.inputs.authentication.audience = $_
        { & $script:contractGate -Definition $definition } | Should -Throw '*audience is missing or invalid*'
    }
    It 'inspects nested user actions rather than only top-level checkpoints' {
        $definition = Get-Content $script:definitionPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100
        $definition.actions.Send_minimized_user_card.actions.Check_user_checkpoint.inputs.authentication.Remove('audience')
        { & $script:contractGate -Definition $definition } | Should -Throw '*audience is missing or invalid*'
    }
}
