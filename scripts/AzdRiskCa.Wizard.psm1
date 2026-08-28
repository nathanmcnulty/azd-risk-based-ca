Set-StrictMode -Version Latest

function Test-AzdRiskCaInteractiveSession {
    return -not ($env:CI -or $env:AZD_NON_INTERACTIVE -eq 'true' -or [Console]::IsInputRedirected)
}

function Read-AzdRiskCaRequiredChoice {
    param([string]$Prompt, [string]$Default, [string[]]$Allowed)
    while ($true) {
        $suffix = if ($Default) { " [$Default]" } else { '' }
        $answer = Read-Host "$Prompt$suffix"
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
        $match = @($Allowed | Where-Object { $_ -ieq $answer.Trim() }) | Select-Object -First 1
        if ($match) { return $match }
        Write-Warning "Choose one of: $($Allowed -join ', ')."
    }
}

function Read-AzdRiskCaOptionalGuid {
    param([string]$Prompt)
    while ($true) {
        $answer = (Read-Host "$Prompt [optional]").Trim()
        if (-not $answer) { return '' }
        $parsed = [guid]::Empty
        if ([guid]::TryParse($answer, [ref]$parsed)) { return $parsed.Guid }
        Write-Warning 'Enter a valid Microsoft Entra object ID (GUID), or leave it blank.'
    }
}

function Read-AzdRiskCaExcludeGroups {
    while ($true) {
        $answer = (Read-Host 'Additional exclusion group object IDs, separated by commas [optional]').Trim()
        if (-not $answer) { return '' }
        $values = @($answer -split '[;,]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        $valid = $true
        foreach ($value in $values) {
            $parsed = [guid]::Empty
            if (-not [guid]::TryParse($value, [ref]$parsed)) { $valid = $false; break }
        }
        if ($valid) { return ($values -join ';') }
        Write-Warning 'Every additional exclusion must be a valid Microsoft Entra group object ID.'
    }
}

function Read-AzdRiskCaHttpsUrl {
    param([string]$Prompt, [switch]$Required)
    while ($true) {
        $answer = (Read-Host $Prompt).Trim()
        if (-not $answer -and -not $Required) { return '' }
        $uri = $null
        if ([uri]::TryCreate($answer, [System.UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -eq 'https') { return $answer }
        Write-Warning 'Enter an absolute HTTPS URL.'
    }
}

function Read-AzdRiskCaWorkspaceId {
    while ($true) {
        $answer = (Read-Host 'Existing Log Analytics workspace resource ID').Trim()
        if ($answer -match '^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft\.OperationalInsights/workspaces/[^/]+$') { return $answer }
        Write-Warning 'Enter a complete Log Analytics workspace resource ID.'
    }
}

function Read-AzdRiskCaTeamsChannelLink {
    while ($true) {
        $answer = (Read-Host 'Teams administrator channel link (copy link from Teams)').Trim()
        $uri = $null
        if ([uri]::TryCreate($answer, [System.UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -eq 'https' -and $uri.Host -eq 'teams.microsoft.com' -and $uri.AbsolutePath -match '^/l/channel/') { return $answer }
        Write-Warning 'Enter the HTTPS channel link copied from Microsoft Teams.'
    }
}

function Invoke-AzdRiskCaFirstRunWizard {
    [CmdletBinding()] param()

    if ($env:AZD_CA_SETUP_COMPLETE -eq 'true' -or -not (Test-AzdRiskCaInteractiveSession)) { return $false }
    $resuming = $env:AZD_CA_SETUP_COMPLETE -eq 'inProgress'

    # Any meaningful preconfiguration is an explicit operator choice. Leave it
    # intact and let normal validation provide the precise error if incomplete.
    $configuredNames = @(
        'AZD_CA_POLICY_STATE','AZD_CA_EMERGENCY_ACCESS_GROUP_ID','AZD_CA_ADMIN_COVERAGE_GROUP_ID',
        'AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS','AZD_CA_USE_TAP_AUTH_STRENGTH','AZD_CA_NOTIFICATION_MODE',
        'AZD_CA_ADMIN_TEAMS_WORKFLOW_URL','AZD_CA_USER_TEAMS_WORKFLOW_URL',
        'AZD_CA_ADMIN_TEAMS_CHANNEL_LINK','AZD_CA_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID'
    )
    if (-not $resuming -and @($configuredNames | Where-Object { -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_)) }).Count -gt 0) { return $false }

    azd env set AZD_CA_SETUP_COMPLETE inProgress | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to save the first-run setup state.' }
    Set-Item env:AZD_CA_SETUP_COMPLETE inProgress

    Write-Host ''
    Write-Host 'azd-risk-based-ca first-run setup' -ForegroundColor Cyan
    Write-Host 'The wizard only saves local azd environment settings. It does not sign in or change Azure, Graph, or Conditional Access.'
    Write-Host 'Policies remain report-only until you explicitly change that setting and confirm the tenant ID.'

    $values = [ordered]@{}
    $values.AZD_CA_POLICY_STATE = 'reportOnly'
    $values.AZD_CA_EMERGENCY_ACCESS_GROUP_ID = Read-AzdRiskCaOptionalGuid 'Emergency access group object ID'
    if (-not $values.AZD_CA_EMERGENCY_ACCESS_GROUP_ID) {
        Write-Warning 'No emergency access group was selected. The signed-in operator will be excluded as a temporary single-user failsafe; prepare a durable emergency path before enablement.'
    }
    $values.AZD_CA_ADMIN_COVERAGE_GROUP_ID = Read-AzdRiskCaOptionalGuid 'Optional administrator coverage group object ID'
    $values.AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS = Read-AzdRiskCaExcludeGroups
    $values.AZD_CA_USE_TAP_AUTH_STRENGTH = (Read-AzdRiskCaRequiredChoice 'Use a Temporary Access Pass authentication strength for device registration? (yes/no)' 'no' @('yes','no')) -eq 'yes' ? 'true' : 'false'
    $values.AZD_CA_NOTIFICATION_MODE = Read-AzdRiskCaRequiredChoice 'Notification backend (none/graph/logAnalytics)' 'none' @('none','graph','logAnalytics')
    $values.AZD_CA_ADMIN_TEAMS_DELIVERY_MODE = 'adminConfigured'
    if ($values.AZD_CA_NOTIFICATION_MODE -ne 'none') {
        $values.AZD_CA_ADMIN_TEAMS_DELIVERY_MODE = Read-AzdRiskCaRequiredChoice 'Teams delivery (adminConfigured/workflowWebhook)' 'adminConfigured' @('adminConfigured','workflowWebhook')
        if ($values.AZD_CA_ADMIN_TEAMS_DELIVERY_MODE -eq 'adminConfigured') {
            $values.AZD_CA_ADMIN_TEAMS_CHANNEL_LINK = Read-AzdRiskCaTeamsChannelLink
            $values.AZD_CA_ADMIN_TEAMS_WORKFLOW_URL = ''
        } else {
            $values.AZD_CA_ADMIN_TEAMS_WORKFLOW_URL = Read-AzdRiskCaHttpsUrl 'Existing Teams administrator workflow callback URL' -Required
            $values.AZD_CA_ADMIN_TEAMS_CHANNEL_LINK = ''
        }
        $values.AZD_CA_USER_TEAMS_WORKFLOW_URL = Read-AzdRiskCaHttpsUrl 'Optional internal-user Teams workflow callback URL'
    } else {
        $values.AZD_CA_ADMIN_TEAMS_CHANNEL_LINK = ''
        $values.AZD_CA_ADMIN_TEAMS_WORKFLOW_URL = ''
        $values.AZD_CA_USER_TEAMS_WORKFLOW_URL = ''
    }
    if ($values.AZD_CA_NOTIFICATION_MODE -eq 'logAnalytics') {
        $values.AZD_CA_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID = Read-AzdRiskCaWorkspaceId
        $values.AZD_CA_LOG_ANALYTICS_WORKSPACE_LOCATION = (Read-Host 'Existing Log Analytics workspace location').Trim()
        while (-not $values.AZD_CA_LOG_ANALYTICS_WORKSPACE_LOCATION) { Write-Warning 'Workspace location is required.'; $values.AZD_CA_LOG_ANALYTICS_WORKSPACE_LOCATION = (Read-Host 'Existing Log Analytics workspace location').Trim() }
    } else { $values.AZD_CA_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID = ''; $values.AZD_CA_LOG_ANALYTICS_WORKSPACE_LOCATION = '' }

    Write-Host ''
    Write-Host 'Review local setup choices:' -ForegroundColor Cyan
    foreach ($entry in $values.GetEnumerator()) {
        $display = if ($entry.Key -match 'URL|LINK') { if ($entry.Value) { '<provided>' } else { '<empty>' } } else { if ($entry.Value) { $entry.Value } else { '<empty>' } }
        Write-Host ("  {0}: {1}" -f $entry.Key, $display)
    }
    $confirm = Read-Host 'Save these choices to the azd environment? (yes/no)'
    if ($confirm.Trim() -notin @('yes','y')) { throw 'First-run setup was cancelled. Run azd up again to restart the wizard.' }
    foreach ($entry in $values.GetEnumerator()) { azd env set $entry.Key $entry.Value | Out-Null; if ($LASTEXITCODE -ne 0) { throw "Unable to save '$($entry.Key)' to the azd environment." }; Set-Item -Path "env:$($entry.Key)" -Value $entry.Value }
    azd env set AZD_CA_SETUP_COMPLETE true | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to save the first-run completion marker.' }
    Set-Item env:AZD_CA_SETUP_COMPLETE true
    Write-Host 'Setup saved. Continuing with read-only preflight and the report-only deployment plan.' -ForegroundColor Green
    return $true
}

Export-ModuleMember -Function Invoke-AzdRiskCaFirstRunWizard
