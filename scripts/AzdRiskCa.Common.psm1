Set-StrictMode -Version Latest

function Import-AzdEnvironment {
    [CmdletBinding()] param()
    if (-not (Get-Command azd -ErrorAction SilentlyContinue)) { throw 'Azure Developer CLI (azd) was not found on PATH.' }
    foreach ($line in (azd env get-values)) {
        if ([string]::IsNullOrWhiteSpace($line) -or -not $line.Contains('=')) { continue }
        $parts = $line.Split('=', 2)
        $value = $parts[1]
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2).Replace('\"', '"')
        }
        Set-Item -Path "env:$($parts[0])" -Value $value
    }
}

function Set-AzdEnvironmentValue {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    azd env set $Name $Value | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Unable to set azd environment value '$Name'." }
    Set-Item -Path "env:$Name" -Value $Value
}

function ConvertTo-AzdRiskCaBoolean {
    [CmdletBinding()] param([AllowNull()][AllowEmptyString()][string]$Value, [bool]$Default = $false, [string]$Name = 'value')
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Default }
    switch ($Value.Trim().ToLowerInvariant()) {
        { $_ -in @('1','true','yes') } { return $true }
        { $_ -in @('0','false','no') } { return $false }
        default { throw "$Name must be true or false." }
    }
}

function Resolve-AzdRiskCaChoice {
    [CmdletBinding()] param([AllowNull()][AllowEmptyString()][string]$Value, [Parameter(Mandatory)][string]$Default, [Parameter(Mandatory)][string[]]$Allowed, [Parameter(Mandatory)][string]$Name)
    $candidate = if ([string]::IsNullOrWhiteSpace($Value)) { $Default } else { $Value.Trim() }
    $match = @($Allowed | Where-Object { $_ -ieq $candidate }) | Select-Object -First 1
    if (-not $match) { throw "$Name must be one of: $($Allowed -join ', ')." }
    return $match
}

function ConvertFrom-AzdRiskCaList {
    [CmdletBinding()] param([AllowNull()][AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    $trimmed = $Value.Trim()
    if ($trimmed.StartsWith('[')) {
        try { $items = @($trimmed | ConvertFrom-Json -ErrorAction Stop) } catch { throw "List value is not valid JSON: $($_.Exception.Message)" }
    } else { $items = @($trimmed -split '[;,\r\n]+') }
    return @($items | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Sort-Object -Unique)
}

function Assert-AzdRiskCaGuidList {
    [CmdletBinding()] param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Values, [Parameter(Mandatory)][string]$Name)
    foreach ($value in $Values) {
        $parsed = [guid]::Empty
        if (-not [guid]::TryParse($value, [ref]$parsed)) { throw "$Name contains an invalid GUID: '$value'." }
    }
}

function Assert-AzdRiskCaHttpsSecret {
    [CmdletBinding()] param([AllowNull()][string]$Value, [Parameter(Mandatory)][string]$Name, [switch]$Required)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        if ($Required) { throw "$Name is required when notifications are enabled." }
        return
    }
    $uri = $null
    if (-not [uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') { throw "$Name must be an absolute HTTPS URL." }
}

function Assert-AzdRiskCaTenantConfirmation {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$ExpectedTenantId, [AllowNull()][AllowEmptyString()][string]$Actual)
    if ([string]::IsNullOrWhiteSpace($Actual) -or $Actual.Trim() -ne $ExpectedTenantId) { throw 'Tenant confirmation did not match. The requested state transition was cancelled.' }
}

function ConvertFrom-AzdRiskCaTeamsChannelLink {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$ChannelLink, [Parameter(Mandatory)][guid]$TenantId)
    try {
        $channelUri=[uri]$ChannelLink
        if ($channelUri.Scheme -ne 'https') { throw 'unsupported scheme' }
        $segments=@($channelUri.AbsolutePath.Trim('/').Split('/') | ForEach-Object { [uri]::UnescapeDataString($_) })
        if ($segments.Count -lt 4 -or $segments[0] -ne 'l' -or $segments[1] -ne 'channel') { throw 'unsupported path' }
        $query=[System.Web.HttpUtility]::ParseQueryString($channelUri.Query)
        $channelId=$segments[2]
        $teamId=$query['groupId']
        $channelTenantId=$query['tenantId']
    } catch { throw 'AZD_CA_ADMIN_TEAMS_CHANNEL_LINK must be a channel link copied from Microsoft Teams.' }
    $parsedTeamId=[guid]::Empty
    $parsedTenantId=[guid]::Empty
    if (-not [guid]::TryParse($teamId,[ref]$parsedTeamId) -or [string]::IsNullOrWhiteSpace($channelId) -or -not [guid]::TryParse($channelTenantId,[ref]$parsedTenantId)) {
        throw 'Unable to resolve the team, channel, and tenant IDs from AZD_CA_ADMIN_TEAMS_CHANNEL_LINK.'
    }
    if ($parsedTenantId -ne $TenantId) { throw "The Teams channel tenant '$parsedTenantId' does not match deployment tenant '$TenantId'." }
    return [pscustomobject]@{ TeamId=$parsedTeamId.Guid; ChannelId=$channelId; TenantId=$parsedTenantId.Guid }
}

function Get-AzdRiskCaConfiguration {
    [CmdletBinding()] param()
    $additional = @(ConvertFrom-AzdRiskCaList $env:AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS)
    Assert-AzdRiskCaGuidList $additional 'AZD_CA_ADDITIONAL_EXCLUDE_GROUP_IDS'
    foreach ($name in @('AZD_CA_EMERGENCY_ACCESS_GROUP_ID','AZD_CA_ADMIN_COVERAGE_GROUP_ID')) {
        $value = [string][Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) { Assert-AzdRiskCaGuidList @($value.Trim()) $name }
    }
    $configuration = [ordered]@{
        PolicyState = Resolve-AzdRiskCaChoice $env:AZD_CA_POLICY_STATE 'reportOnly' @('reportOnly','enabled') 'AZD_CA_POLICY_STATE'
        EmergencyAccessGroupId = ([string]$env:AZD_CA_EMERGENCY_ACCESS_GROUP_ID).Trim()
        AdminCoverageGroupId = ([string]$env:AZD_CA_ADMIN_COVERAGE_GROUP_ID).Trim()
        AdditionalExcludeGroupIds = $additional
        UseTapAuthenticationStrength = ConvertTo-AzdRiskCaBoolean $env:AZD_CA_USE_TAP_AUTH_STRENGTH $false 'AZD_CA_USE_TAP_AUTH_STRENGTH'
        AdoptExisting = ConvertTo-AzdRiskCaBoolean $env:AZD_CA_ADOPT_EXISTING $false 'AZD_CA_ADOPT_EXISTING'
        GraphAuthenticationMethod = Resolve-AzdRiskCaChoice $env:AZD_CA_GRAPH_AUTHENTICATION_METHOD 'browser' @('browser') 'AZD_CA_GRAPH_AUTHENTICATION_METHOD'
        NotificationMode = Resolve-AzdRiskCaChoice $env:AZD_CA_NOTIFICATION_MODE 'none' @('none','graph','logAnalytics') 'AZD_CA_NOTIFICATION_MODE'
        AdminTeamsDeliveryMode = Resolve-AzdRiskCaChoice $env:AZD_CA_ADMIN_TEAMS_DELIVERY_MODE 'adminConfigured' @('adminConfigured','workflowWebhook') 'AZD_CA_ADMIN_TEAMS_DELIVERY_MODE'
        AdminTeamsWorkflowUrl = ([string]$env:AZD_CA_ADMIN_TEAMS_WORKFLOW_URL).Trim()
        UserTeamsWorkflowUrl = ([string]$env:AZD_CA_USER_TEAMS_WORKFLOW_URL).Trim()
        AdminTeamsChannelLink = ([string]$env:AZD_CA_ADMIN_TEAMS_CHANNEL_LINK).Trim()
        AdminTeamsTeamId = ([string]$env:AZD_CA_ADMIN_TEAMS_TEAM_ID).Trim()
        AdminTeamsChannelId = ([string]$env:AZD_CA_ADMIN_TEAMS_CHANNEL_ID).Trim()
        LogAnalyticsWorkspaceResourceId = ([string]$env:AZD_CA_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID).Trim()
        LogAnalyticsWorkspaceLocation = ([string]$env:AZD_CA_LOG_ANALYTICS_WORKSPACE_LOCATION).Trim()
        Cleanup = ConvertTo-AzdRiskCaBoolean $env:AZD_CA_CLEANUP $false 'AZD_CA_CLEANUP'
    }
    if ($configuration.NotificationMode -ne 'none') {
        Assert-AzdRiskCaHttpsSecret $configuration.UserTeamsWorkflowUrl 'AZD_CA_USER_TEAMS_WORKFLOW_URL'
        if ($configuration.AdminTeamsDeliveryMode -eq 'workflowWebhook') {
            Assert-AzdRiskCaHttpsSecret $configuration.AdminTeamsWorkflowUrl 'AZD_CA_ADMIN_TEAMS_WORKFLOW_URL' -Required
            if ($configuration.AdminTeamsChannelLink -or $configuration.AdminTeamsTeamId -or $configuration.AdminTeamsChannelId) { throw 'Teams channel inputs must be empty when workflowWebhook delivery is selected.' }
        } else {
            if ($configuration.AdminTeamsWorkflowUrl) { throw 'AZD_CA_ADMIN_TEAMS_WORKFLOW_URL must be empty when adminConfigured delivery is selected.' }
            if ($configuration.AdminTeamsTeamId) { Assert-AzdRiskCaGuidList @($configuration.AdminTeamsTeamId) 'AZD_CA_ADMIN_TEAMS_TEAM_ID' }
        }
    }
    if ($configuration.NotificationMode -eq 'logAnalytics') {
        if ($configuration.LogAnalyticsWorkspaceResourceId -notmatch '^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft\.OperationalInsights/workspaces/[^/]+$') { throw 'AZD_CA_LOG_ANALYTICS_WORKSPACE_RESOURCE_ID must be an existing Log Analytics workspace resource ID.' }
        if ([string]::IsNullOrWhiteSpace($configuration.LogAnalyticsWorkspaceLocation)) { throw 'AZD_CA_LOG_ANALYTICS_WORKSPACE_LOCATION is required for logAnalytics mode.' }
    }
    return [pscustomobject]$configuration
}

function Get-AzdRiskCaDataPath {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Name)
    $root = Split-Path -Parent $PSScriptRoot
    $environment = if ($env:AZURE_ENV_NAME) { $env:AZURE_ENV_NAME } else { 'default' }
    return Join-Path $root ".azure/$environment/$Name"
}

function Get-AzdRiskCaState { [CmdletBinding()] param() $path = Get-AzdRiskCaDataPath 'azd-risk-ca-state.json'; if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100 } }
function Save-AzdRiskCaJson {
    [CmdletBinding()] param([Parameter(Mandatory)][object]$Value, [Parameter(Mandatory)][string]$Path)
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = "$Path.tmp"
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $temporary -Encoding utf8NoBOM
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}
function Save-AzdRiskCaState { [CmdletBinding()] param([Parameter(Mandatory)][object]$State) Save-AzdRiskCaJson $State (Get-AzdRiskCaDataPath 'azd-risk-ca-state.json') }

Export-ModuleMember -Function *
