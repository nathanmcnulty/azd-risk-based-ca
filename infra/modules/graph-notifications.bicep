param environmentName string
param location string
@secure()
param adminTeamsWorkflowUrl string
@secure()
param userTeamsWorkflowUrl string = ''
param tags object = {}

var suffix = uniqueString(subscription().id, resourceGroup().id, environmentName)
var storageName = take('striskca${suffix}', 24)
var functionName = take('func-risk-ca-${suffix}', 60)
var connection = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}
resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: { deleteRetentionPolicy: { enabled: true, days: 14 } }
}
resource releases 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blob
  name: 'function-releases'
  properties: { publicAccess: 'None' }
}
resource state 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blob
  name: 'risk-state'
  properties: { publicAccess: 'None' }
}
resource deadletter 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blob
  name: 'risk-dead-letter'
  properties: { publicAccess: 'None' }
}

resource insightsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-risk-ca-${suffix}'
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    sku: { name: 'PerGB2018' }
  }
}
resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-risk-ca-${suffix}'
  location: location
  tags: tags
  kind: 'web'
  properties: { Application_Type: 'web', IngestionMode: 'LogAnalytics', WorkspaceResourceId: insightsWorkspace.id }
}
resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-risk-ca-${suffix}'
  location: location
  tags: tags
  kind: 'functionapp'
  sku: { tier: 'FlexConsumption', name: 'FC1' }
  properties: { reserved: true }
}
resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionName
  location: location
  tags: union(tags, { 'azd-service-name': 'risk-notification-poller' })
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        { name: 'AzureWebJobsStorage', value: connection }
        { name: 'DEPLOYMENT_STORAGE_CONNECTION_STRING', value: connection }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: insights.properties.ConnectionString }
        { name: 'AZD_CA_STORAGE_ACCOUNT_NAME', value: storage.name }
        { name: 'AZD_CA_STATE_CONTAINER', value: state.name }
        { name: 'AZD_CA_DEAD_LETTER_CONTAINER', value: deadletter.name }
        { name: 'AZD_CA_ADMIN_TEAMS_WORKFLOW_URL', value: adminTeamsWorkflowUrl }
        { name: 'AZD_CA_USER_TEAMS_WORKFLOW_URL', value: userTeamsWorkflowUrl }
        { name: 'AZD_CA_POLLING_SCHEDULE', value: '0 */5 * * * *' }
      ]
    }
    functionAppConfig: {
      runtime: { name: 'node', version: '22' }
      scaleAndConcurrency: { maximumInstanceCount: 10, instanceMemoryMB: 2048, alwaysReady: [] }
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${releases.name}'
          authentication: {
            type: 'StorageAccountConnectionString'
            storageAccountConnectionStringName: 'DEPLOYMENT_STORAGE_CONNECTION_STRING'
          }
        }
      }
    }
  }
}
resource blobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionApp.id, 'Storage Blob Data Contributor')
  scope: storage
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
  }
}
output functionAppName string = functionApp.name
output functionAppPrincipalId string = functionApp.identity.principalId
