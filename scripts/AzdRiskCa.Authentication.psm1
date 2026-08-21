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
    Connect-MgGraph @parameters | Out-Null
    $context = Get-MgContext
    if (-not $context -or $context.TenantId -ne $TenantId.Guid) { throw 'Microsoft Graph did not connect to the requested tenant.' }
    $missing = @($scopes | Where-Object { $_ -notin @($context.Scopes) })
    if ($missing.Count) { throw "Microsoft Graph connected without required delegated scopes: $($missing -join ', ')." }
    try {
        Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=id' -OutputType PSObject -ErrorAction Stop | Out-Null
    } catch {
        $detail=$_.Exception.Message
        if ($detail -match 'window handle|InteractiveBrowserCredential') {
            throw 'Standard cached WAM/browser authentication could not initialize in this host. Run the command from an interactive terminal so Connect-MgGraph can use the OS broker or browser. Device-code authentication is not supported.'
        }
        throw "Microsoft Graph connection validation failed. $detail"
    }
    return $context
}

Export-ModuleMember -Function *
