Set-StrictMode -Version Latest

function Get-AzdRiskCaGraphPermissionScope {
    [CmdletBinding()] param([ValidateSet('none','graph','logAnalytics')][string]$NotificationMode = 'none')
    $scopes = @('Policy.Read.All','Policy.ReadWrite.ConditionalAccess','Group.Read.All','RoleManagement.Read.Directory','User.Read')
    if ($NotificationMode -eq 'graph') { $scopes += @('Application.Read.All','AppRoleAssignment.ReadWrite.All') }
    return @($scopes | Sort-Object -Unique)
}

function Connect-AzdRiskCaGraph {
    [CmdletBinding()] param([Parameter(Mandatory)][guid]$TenantId, [Parameter(Mandatory)][object]$Configuration)
    $scopes = Get-AzdRiskCaGraphPermissionScope -NotificationMode $Configuration.NotificationMode
    # Each azd hook runs in a new PowerShell process. A persisted context can contain
    # matching metadata while its broker token has not been initialized in that process,
    # so always let the standard connection command hydrate or refresh the cached session.
    $parameters = @{ TenantId=$TenantId.Guid; Scopes=$scopes; ContextScope='CurrentUser'; NoWelcome=$true; ErrorAction='Stop' }
    try {
        Connect-MgGraph @parameters | Out-Null
    } catch {
        $detail=$_.Exception.Message
        if ($detail -match 'AADSTS65001|consent|required.*approval|Need admin approval') {
            throw "Microsoft Graph administrator consent is required for: $($scopes -join ', '). Run this deployment from an interactive terminal and complete the standard WAM/browser consent prompt. $detail"
        }
        if ($detail -match 'window handle|InteractiveBrowserCredential') {
            throw 'Standard cached WAM/browser authentication could not initialize in this host. Run the command from an interactive terminal so Connect-MgGraph can use the OS broker or browser. Device-code authentication is not supported.'
        }
        throw "Microsoft Graph connection failed. $detail"
    }
    $context = Get-MgContext
    if (-not $context -or $context.TenantId -ne $TenantId.Guid) { throw 'Microsoft Graph did not connect to the requested tenant.' }
    $missing = @($scopes | Where-Object { $_ -notin @($context.Scopes) })
    if ($missing.Count) { throw "Microsoft Graph connected without required delegated scopes: $($missing -join ', '). Reconnect with standard Connect-MgGraph and complete administrator consent in the WAM/browser prompt." }
    # Get-MgContext can return persisted account/scope metadata before this hook's
    # process has acquired a usable access token. Materialize the token now so a
    # broker or consent interruption fails before the read-only plan begins.
    try {
        Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=id' -OutputType PSObject -ErrorAction Stop | Out-Null
    } catch {
        $detail=$_.Exception.Message
        if ($detail -match 'AADSTS65001|consent|required.*approval|Need admin approval') {
            throw "Microsoft Graph administrator consent is required for: $($scopes -join ', '). Run this deployment from an interactive terminal and complete the standard WAM/browser consent prompt. $detail"
        }
        if ($detail -match 'window handle|InteractiveBrowserCredential|User canceled authentication') {
            throw 'The standard cached WAM/browser session did not provide a usable Microsoft Graph token. Run the deployment from an interactive terminal and complete the broker or browser prompt. Device-code authentication is not supported.'
        }
        throw "Microsoft Graph token validation failed. $detail"
    }
    return $context
}

Export-ModuleMember -Function *
