Set-StrictMode -Version Latest

function Grant-AzdRiskCaIdentityRiskPermission {
    [CmdletBinding()] param([Parameter(Mandatory)][guid]$PrincipalId)
    $graph = Invoke-AzdRiskCaGraphRequest GET 'https://graph.microsoft.com/v1.0/servicePrincipals(appId=''00000003-0000-0000-c000-000000000000'')?$select=id,appRoles'
    $role=@($graph.appRoles | Where-Object { $_.value -eq 'IdentityRiskEvent.Read.All' -and $_.isEnabled -and 'Application' -in @($_.allowedMemberTypes) })
    if ($role.Count -ne 1) { throw 'Microsoft Graph application role IdentityRiskEvent.Read.All could not be resolved.' }
    $existing=@(Get-AzdRiskCaGraphCollection "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments") | Where-Object { $_.resourceId -eq $graph.id -and $_.appRoleId -eq $role[0].id }
    if (-not $existing) {
        Invoke-AzdRiskCaGraphRequest POST "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" @{ principalId=$PrincipalId.Guid; resourceId=$graph.id; appRoleId=$role[0].id } | Out-Null
    }
}

function Publish-AzdRiskCaGraphFunction {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$FunctionName)
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { throw 'npm is required to package the Graph notification Function.' }
    $source=Join-Path (Split-Path -Parent $PSScriptRoot) 'src/risk-notification-poller'
    npm install --omit=dev --ignore-scripts --no-audit --no-fund --prefix $source | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'npm install failed for the notification Function.' }
    $archive=Join-Path ([System.IO.Path]::GetTempPath()) "azd-risk-ca-$([guid]::NewGuid().ToString('N')).zip"
    try {
        Compress-Archive -Path (Join-Path $source '*') -DestinationPath $archive -Force
        az functionapp deployment source config-zip --name $FunctionName --resource-group $env:AZURE_RESOURCE_GROUP --src $archive --only-show-errors | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Function zip deployment failed.' }
    } finally { if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force } }
}

Export-ModuleMember -Function *
