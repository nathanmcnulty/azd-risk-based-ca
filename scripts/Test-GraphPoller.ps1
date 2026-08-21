[CmdletBinding()]
param([int]$TimeoutSeconds=60)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'AzdRiskCa.Common.psm1') -Force
Import-AzdEnvironment
if ($env:AZD_CA_NOTIFICATION_MODE -ne 'graph') { throw 'Graph poller validation requires AZD_CA_NOTIFICATION_MODE=graph.' }
if (-not $env:AZD_CA_GRAPH_FUNCTION_NAME -or -not $env:AZURE_RESOURCE_GROUP) { throw 'Graph Function deployment outputs are missing.' }

$hostName=(az resource show --name $env:AZD_CA_GRAPH_FUNCTION_NAME --resource-group $env:AZURE_RESOURCE_GROUP --resource-type Microsoft.Web/sites --api-version 2024-04-01 --query properties.defaultHostName -o tsv --only-show-errors).Trim()
$keys=az functionapp keys list --name $env:AZD_CA_GRAPH_FUNCTION_NAME --resource-group $env:AZURE_RESOURCE_GROUP -o json --only-show-errors | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $hostName -or -not $keys.masterKey) { throw 'Unable to acquire Function host metadata for the smoke test.' }
$invokeUri="https://$hostName/admin/functions/pollRiskDetections?code=$([uri]::EscapeDataString($keys.masterKey))"
Invoke-RestMethod -Method POST -Uri $invokeUri -ContentType 'application/json' -Body '{"input":null}' | Out-Null

$storageName=(az resource list --resource-group $env:AZURE_RESOURCE_GROUP --resource-type Microsoft.Storage/storageAccounts --query '[0].name' -o tsv --only-show-errors).Trim()
$storageKey=(az storage account keys list --resource-group $env:AZURE_RESOURCE_GROUP --account-name $storageName --query '[0].value' -o tsv --only-show-errors).Trim()
if ($LASTEXITCODE -ne 0 -or -not $storageName -or -not $storageKey) { throw 'Unable to acquire temporary Storage access for checkpoint validation.' }

$deadline=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
do {
    $names=@(az storage blob list --account-name $storageName --container-name risk-state --account-key $storageKey --query '[].name' -o tsv --only-show-errors)
    if ($names -contains 'risk-notification-state.json') { break }
    Start-Sleep -Seconds 3
} while ([DateTimeOffset]::UtcNow -lt $deadline)
if ($names -notcontains 'risk-notification-state.json') { throw "Function checkpoint did not appear within $TimeoutSeconds seconds." }

$temporary=Join-Path ([System.IO.Path]::GetTempPath()) "risk-state-$([guid]::NewGuid().ToString('N')).json"
try {
    az storage blob download --account-name $storageName --container-name risk-state --name risk-notification-state.json --account-key $storageKey --file $temporary --overwrite true --only-show-errors | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read the Function checkpoint.' }
    $state=Get-Content -LiteralPath $temporary -Raw | ConvertFrom-Json -Depth 100
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
}

$records=@($state.deliveries.psobject.Properties | ForEach-Object { $_.Value })
$summary=[pscustomobject]@{
    schemaVersion=$state.schemaVersion
    seededAt=$state.seededAt
    lastRunAt=$state.lastRunAt
    seeded=@($records|Where-Object status -eq 'seeded').Count
    pending=@($records|Where-Object status -eq 'pending').Count
    delivered=@($records|Where-Object status -eq 'delivered').Count
    deadLettered=@($records|Where-Object status -eq 'deadLettered').Count
}
$summary | Format-List
if (-not $summary.seededAt -or -not $summary.lastRunAt) { throw 'Function checkpoint is missing seed or run timestamps.' }
Write-Host 'Verified Graph poller execution and durable checkpoint state without displaying access keys.'
