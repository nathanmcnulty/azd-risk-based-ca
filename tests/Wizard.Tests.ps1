Describe 'First-run administrator wizard' {
    BeforeAll {
        $script:modulePath = Join-Path $PSScriptRoot '../scripts/AzdRiskCa.Wizard.psm1'
        $script:source = Get-Content $script:modulePath -Raw
        Import-Module $script:modulePath -Force
    }

    BeforeEach {
        $script:priorNonInteractive = $env:AZD_NON_INTERACTIVE
        $script:priorComplete = $env:AZD_CA_SETUP_COMPLETE
        $script:configuredNames = @('AZD_CA_POLICY_STATE','AZD_CA_EMERGENCY_ACCESS_GROUP_ID','AZD_CA_ADMIN_COVERAGE_GROUP_ID','AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS','AZD_CA_USE_TAP_AUTH_STRENGTH','AZD_CA_NOTIFICATION_MODE','AZD_CA_ADMIN_TEAMS_DELIVERY_MODE','AZD_CA_ADMIN_TEAMS_WORKFLOW_URL','AZD_CA_USER_TEAMS_WORKFLOW_URL','AZD_CA_ADMIN_TEAMS_CHANNEL_LINK','AZD_CA_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID','AZD_CA_LOG_ANALYTICS_WORKSPACE_LOCATION')
        $script:priorConfigured = @{}
        foreach ($name in $script:configuredNames) { $script:priorConfigured[$name] = [Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name, $null) }
        $env:AZD_NON_INTERACTIVE = 'true'
        Remove-Item Env:AZD_CA_SETUP_COMPLETE -ErrorAction SilentlyContinue
    }

    AfterEach {
        if ($null -eq $script:priorNonInteractive) { Remove-Item Env:AZD_NON_INTERACTIVE -ErrorAction SilentlyContinue } else { $env:AZD_NON_INTERACTIVE = $script:priorNonInteractive }
        if ($null -eq $script:priorComplete) { Remove-Item Env:AZD_CA_SETUP_COMPLETE -ErrorAction SilentlyContinue } else { $env:AZD_CA_SETUP_COMPLETE = $script:priorComplete }
        foreach ($name in $script:configuredNames) { [Environment]::SetEnvironmentVariable($name, $script:priorConfigured[$name]) }
    }

    It 'skips prompts in noninteractive mode without invoking azd' {
        Invoke-AzdRiskCaFirstRunWizard | Should -BeFalse
    }

    It 'saves an interactive answer sequence transactionally' {
        Remove-Item Env:AZD_NON_INTERACTIVE -ErrorAction SilentlyContinue
        $script:answers = [System.Collections.Generic.Queue[string]]::new()
        foreach ($answer in @('', '', '', 'no', 'none', 'yes')) { $script:answers.Enqueue($answer) }
        Mock Read-Host { $script:answers.Dequeue() } -ModuleName AzdRiskCa.Wizard
        Mock Set-AzdRiskCaWizardEnvironmentValue {
            param($Name, $Value)
            Set-Item -Path "env:$Name" -Value $Value
        } -ModuleName AzdRiskCa.Wizard
        Mock Test-AzdRiskCaInteractiveSession { return $true } -ModuleName AzdRiskCa.Wizard

        Invoke-AzdRiskCaFirstRunWizard | Should -BeTrue
        $env:AZD_CA_POLICY_STATE | Should -Be 'reportOnly'
        $env:AZD_CA_NOTIFICATION_MODE | Should -Be 'none'
        $env:AZD_CA_USE_TAP_AUTH_STRENGTH | Should -Be 'false'
        $env:AZD_CA_SETUP_COMPLETE | Should -Be 'true'
        Should -Invoke Set-AzdRiskCaWizardEnvironmentValue -Times 14 -ModuleName AzdRiskCa.Wizard
    }

    It 'skips prompts when an operator preconfigured a meaningful value' {
        Remove-Item Env:AZD_NON_INTERACTIVE -ErrorAction SilentlyContinue
        $env:AZD_CA_NOTIFICATION_MODE = 'none'
        Mock Test-AzdRiskCaInteractiveSession { return $true } -ModuleName AzdRiskCa.Wizard

        Invoke-AzdRiskCaFirstRunWizard | Should -BeFalse
    }

    It 'contains local-only restartable choices and the required safety gates' {
        $script:source | Should -Match 'AZD_CA_SETUP_COMPLETE'
        $script:source | Should -Match "AZD_CA_SETUP_COMPLETE inProgress"
        $script:source | Should -Match 'AZD_CA_EMERGENCY_ACCESS_GROUP_ID'
        $script:source | Should -Match 'AZD_CA_USE_TAP_AUTH_STRENGTH'
        $script:source | Should -Match 'AZD_CA_NOTIFICATION_MODE'
        $script:source | Should -Match 'Save these choices to the azd environment'
        $script:source | Should -Match 'does not sign in or change Azure, Graph, or Conditional Access'
    }

    It 'runs before Graph module availability and tenant authentication checks' {
        $pre = Get-Content (Join-Path $PSScriptRoot '../scripts/Pre-Provision.ps1') -Raw
        $pre.IndexOf('Invoke-AzdRiskCaFirstRunWizard') | Should -BeLessThan $pre.IndexOf('Get-Module -ListAvailable Microsoft.Graph.Authentication')
        $pre.IndexOf('Invoke-AzdRiskCaFirstRunWizard') | Should -BeLessThan $pre.IndexOf('az account show')
    }
}
