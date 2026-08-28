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
    $source=Join-Path (Split-Path -Parent $PSScriptRoot) 'src/risk-notification-poller'
    $archive=Join-Path ([System.IO.Path]::GetTempPath()) "azd-risk-ca-$([guid]::NewGuid().ToString('N')).zip"
    try {
        # Keep the source package reproducible and let Azure Functions Flex build
        # package-lock.json dependencies remotely. Administrators do not need Node.
        $packageItems=@(Get-ChildItem -LiteralPath $source -Force | Where-Object Name -notin @('node_modules','dist'))
        if (-not $packageItems) { throw 'The Graph notification Function source package is empty.' }
        Compress-Archive -Path $packageItems.FullName -DestinationPath $archive -Force
        az functionapp deployment source config-zip --name $FunctionName --resource-group $env:AZURE_RESOURCE_GROUP --src $archive --build-remote true --only-show-errors | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Function zip deployment failed.' }
    } finally { if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force } }
}

function Get-AzdRiskCaArmAccessToken {
    [CmdletBinding()] param()
    $token=az account get-access-token --subscription $env:AZURE_SUBSCRIPTION_ID --resource https://management.azure.com/ --query accessToken --output tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or -not $token) { throw 'Unable to acquire a cached Azure Resource Manager token for Teams connection setup.' }
    return $token
}

function Invoke-AzdRiskCaArmJson {
    [CmdletBinding()] param([Parameter(Mandatory)][ValidateSet('GET','POST')][string]$Method,[Parameter(Mandatory)][string]$Uri,[object]$Body)
    $parameters=@{Method=$Method;Uri=$Uri;Headers=@{Authorization="Bearer $(Get-AzdRiskCaArmAccessToken)"};ErrorAction='Stop'}
    if ($null -ne $Body) { $parameters.Body=$Body | ConvertTo-Json -Depth 20 -Compress; $parameters.ContentType='application/json' }
    return Invoke-RestMethod @parameters
}

function Get-AzdRiskCaTeamsConnectionStatus {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$ConnectionResourceId)
    $connection=Invoke-AzdRiskCaArmJson GET "https://management.azure.com$ConnectionResourceId`?api-version=2016-06-01"
    return @($connection.properties.statuses)[0].status
}

function Get-AzdRiskCaTeamsConsentLink {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$ConnectionResourceId,[Parameter(Mandatory)][guid]$TenantId)
    $currentUser=Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=id,userPrincipalName' -OutputType PSObject -ErrorAction Stop
    if (-not $currentUser.id) { throw 'Unable to resolve the current Microsoft Graph user for Teams connection authorization.' }
    $response=Invoke-AzdRiskCaArmJson POST "https://management.azure.com$ConnectionResourceId/listConsentLinks?api-version=2016-06-01" @{
        parameters=@(@{parameterName='token';redirectUrl='https://portal.azure.com';objectId=$currentUser.id;tenantId=$TenantId.Guid})
    }
    return @($response.value) | Select-Object -First 1
}

function Open-AzdRiskCaConsentUrl {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Url)
    try {
        if ($IsWindows) { Start-Process $Url | Out-Null }
        elseif ($IsMacOS) { & open $Url }
        else { & xdg-open $Url }
    } catch { throw 'The Teams consent page could not be opened automatically. Rerun from an interactive desktop session that can launch the default browser.' }
}

function Complete-AzdRiskCaTeamsConnectionAuthorization {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$ConnectionResourceId,[Parameter(Mandatory)][guid]$TenantId)
    $ready=@('Authenticated','Connected','Ready')
    $status=Get-AzdRiskCaTeamsConnectionStatus $ConnectionResourceId
    if ($status -in $ready) { return $true }
    $consent=Get-AzdRiskCaTeamsConsentLink $ConnectionResourceId $TenantId
    if (-not $consent.link) { throw "The Teams connection is '$status', but Azure did not return an authorization link." }
    Write-Host ''
    Write-Warning 'One browser authorization is required for Teams risk notifications.'
    Write-Warning 'Sign in as the durable Teams notification account that should appear as the card sender.'
    if ($env:CI -or $env:AZD_NON_INTERACTIVE -eq 'true' -or [Console]::IsInputRedirected) {
        throw "The Teams delivery workflow remains disabled. Rerun 'azd hooks run postprovision' from an interactive desktop session so the authorization URL can open directly in the default browser. The URL is intentionally not printed."
    }
    Open-AzdRiskCaConsentUrl $consent.link
    while ($true) {
        $response=Read-Host 'Complete the browser authorization, then press Enter to continue (or type skip)'
        if ($response.Trim() -eq 'skip') { return $false }
        $status=Get-AzdRiskCaTeamsConnectionStatus $ConnectionResourceId
        if ($status -in $ready) { return $true }
        Write-Warning "The Teams connection is still '$status'. Complete the browser authorization, then press Enter again."
    }
}

function Enable-AzdRiskCaTeamsWorkflow {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$WorkflowResourceId)
    az resource update --ids $WorkflowResourceId --api-version 2019-05-01 --set properties.state=Enabled --only-show-errors | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The Teams connection was authorized, but the delivery workflow could not be enabled.' }
}

function Test-AzdRiskCaTeamsWorkflowDelivery {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$WorkflowResourceId)
    $managementBase="https://management.azure.com$WorkflowResourceId"
    $callback=Invoke-AzdRiskCaArmJson POST "$managementBase/triggers/manual/listCallbackUrl?api-version=2019-05-01"
    if (-not $callback.value) { throw 'Unable to obtain the Teams delivery workflow callback for smoke testing.' }
    $eventId="synthetic-$([guid]::NewGuid())"
    $payload=@{type='message';attachments=@(@{contentType='application/vnd.microsoft.card.adaptive';contentUrl=$null;content=@{'$schema'='http://adaptivecards.io/schemas/adaptive-card.json';type='AdaptiveCard';version='1.4';body=@(@{type='TextBlock';text='Synthetic Microsoft Entra risk test';weight='Bolder';wrap=$true},@{type='FactSet';facts=@(@{title='Event';value=$eventId},@{title='Source';value='azd-risk-based-ca delivery validation'})})}})}
    $started=[DateTimeOffset]::UtcNow
    try { $response=Invoke-WebRequest -Method POST -Uri $callback.value -ContentType 'application/json' -Body ($payload|ConvertTo-Json -Depth 20 -Compress) -ErrorAction Stop }
    catch { throw "The Teams delivery workflow rejected the smoke test. $($_.Exception.Message)" }
    if ([int]$response.StatusCode -ne 200) { throw "The Teams delivery workflow returned HTTP $([int]$response.StatusCode) for the smoke test." }
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(60); $run=$null
    do {
        Start-Sleep -Seconds 3
        $runs=Invoke-AzdRiskCaArmJson GET "$managementBase/runs?api-version=2019-05-01"
        $run=@($runs.value)|Where-Object{[DateTimeOffset]$_.properties.startTime -ge $started.AddSeconds(-2)}|Sort-Object{[DateTimeOffset]$_.properties.startTime} -Descending|Select-Object -First 1
    } while ((-not $run -or $run.properties.status -in @('Running','Waiting')) -and [DateTimeOffset]::UtcNow -lt $deadline)
    if (-not $run) { throw 'No Teams delivery workflow run appeared within 60 seconds.' }
    if ($run.properties.status -ne 'Succeeded') { throw "Teams delivery smoke test ended with status '$($run.properties.status)'." }
    Write-Host "Verified live Teams card delivery with synthetic event ID $eventId."
}

Export-ModuleMember -Function *
