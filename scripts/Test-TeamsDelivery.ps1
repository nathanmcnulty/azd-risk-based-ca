param([ValidateSet('admin','user')][string]$Destination='admin', [string]$UserPrincipalName='user@contoso.com')
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Common.psm1') -Force
Import-AzdEnvironment
$variable=if($Destination -eq 'admin'){'AZD_CA_ADMIN_TEAMS_WORKFLOW_URL'}else{'AZD_CA_USER_TEAMS_WORKFLOW_URL'}
$url=[Environment]::GetEnvironmentVariable($variable)
if ([string]::IsNullOrWhiteSpace($url)) { throw "$variable is not configured." }
$eventId="synthetic-$([guid]::NewGuid())"
if ($Destination -eq 'admin') {
    $payload=@{ type='message'; attachments=@(@{ contentType='application/vnd.microsoft.card.adaptive'; contentUrl=$null; content=@{ '$schema'='http://adaptivecards.io/schemas/adaptive-card.json'; type='AdaptiveCard'; version='1.4'; body=@(@{type='TextBlock';text='Synthetic Microsoft Entra risk test';weight='Bolder'},@{type='FactSet';facts=@(@{title='Event';value=$eventId},@{title='Source';value='azd-risk-based-ca synthetic test'})}) } }) }
} else {
    $payload=@{ schemaVersion='1.0'; recipientUpn=$UserPrincipalName; card=@{ type='message'; attachments=@(@{ contentType='application/vnd.microsoft.card.adaptive'; contentUrl=$null; content=@{ '$schema'='http://adaptivecards.io/schemas/adaptive-card.json'; type='AdaptiveCard'; version='1.4'; body=@(@{type='TextBlock';text='Synthetic account-security test';weight='Bolder'},@{type='TextBlock';text='This is a test of the minimized user notification path.'}) } }) } }
}
Invoke-RestMethod -Method Post -Uri $url -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 20) | Out-Null
Write-Host "Synthetic $Destination delivery submitted with event ID $eventId. The callback URL was not displayed."
