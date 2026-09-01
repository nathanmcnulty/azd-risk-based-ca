@description('Name of the Storage account used for Function host, deployment, state, and dead-letter data.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Name of the Flex Consumption plan.')
@minLength(1)
@maxLength(60)
param functionPlanName string

@description('Name of the Function App.')
@minLength(2)
@maxLength(60)
param functionAppName string

@description('Azure region for the poller resources.')
@minLength(1)
param location string

@description('AZD environment name exposed to the poller runtime.')
@minLength(1)
param environmentName string

@description('AZD service name applied to the Function App tag.')
@minLength(1)
param serviceName string

@description('Blob container used for Function deployment packages.')
@minLength(3)
param deploymentContainerName string = 'function-releases'

@description('Blob container used for durable poller state.')
@minLength(3)
param stateContainerName string = 'poller-state'

@description('Blob container used for dead-letter records.')
@minLength(3)
param deadLetterContainerName string = 'poller-dead-letter'

@description('Solution-owned Function application settings. Component-owned host and storage settings take precedence.')
@secure()
param applicationSettings object = {}

@description('Temporary consumer-specific aliases for the storage-account setting during an in-place migration.')
param storageAccountSettingAliases array = []

@description('Temporary consumer-specific aliases for the state-container setting during an in-place migration.')
param stateContainerSettingAliases array = []

@description('Temporary consumer-specific aliases for the dead-letter-container setting during an in-place migration.')
param deadLetterContainerSettingAliases array = []

@description('Flex instance memory. Start at 512 MB and increase only with measured workload evidence.')
@allowed([
  512
  2048
  4096
])
param instanceMemoryMB int = 512

@description('Maximum Flex instance count. Timer triggers remain singleton across scaled-out instances.')
@minValue(1)
@maxValue(1000)
param maximumInstanceCount int = 1

@description('Blob soft-delete retention for poller deployment and state containers.')
@minValue(1)
@maxValue(365)
param blobDeleteRetentionDays int = 7

@description('Resource tags applied to all poller resources.')
param tags object = {}

var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}'
var solutionSettings = [for setting in items(applicationSettings): {
  name: setting.key
  value: string(setting.value)
}]
var storageAccountCompatibilitySettings = [for settingName in storageAccountSettingAliases: {
  name: settingName
  value: storage.name
}]
var stateContainerCompatibilitySettings = [for settingName in stateContainerSettingAliases: {
  name: settingName
  value: stateContainer.name
}]
var deadLetterContainerCompatibilitySettings = [for settingName in deadLetterContainerSettingAliases: {
  name: settingName
  value: deadLetterContainer.name
}]
var compatibilitySettings = concat(
  storageAccountCompatibilitySettings,
  stateContainerCompatibilitySettings,
  deadLetterContainerCompatibilitySettings
)

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: blobDeleteRetentionDays
    }
  }
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: deploymentContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource stateContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: stateContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource deadLetterContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: deadLetterContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource functionPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: functionPlanName
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    tier: 'FlexConsumption'
    name: 'FC1'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  tags: union(tags, {
    'azd-service-name': serviceName
  })
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionPlan.id
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: concat(solutionSettings, compatibilitySettings, [
        { name: 'AzureWebJobsStorage', value: storageConnectionString }
        { name: 'DEPLOYMENT_STORAGE_CONNECTION_STRING', value: storageConnectionString }
        { name: 'AZD_POLLER_STORAGE_ACCOUNT_NAME', value: storage.name }
        { name: 'AZD_POLLER_STATE_CONTAINER', value: stateContainer.name }
        { name: 'AZD_POLLER_DEAD_LETTER_CONTAINER', value: deadLetterContainer.name }
        { name: 'AZURE_ENV_NAME', value: environmentName }
      ])
    }
    functionAppConfig: {
      runtime: {
        name: 'node'
        version: '22'
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
        alwaysReady: []
      }
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.properties.primaryEndpoints.blob}${deploymentContainer.name}'
          authentication: {
            type: 'StorageAccountConnectionString'
            storageAccountConnectionStringName: 'DEPLOYMENT_STORAGE_CONNECTION_STRING'
          }
        }
      }
    }
  }
}

resource stateBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
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
output functionAppResourceId string = functionApp.id
output functionAppPrincipalId string = functionApp.identity.principalId
output storageAccountName string = storage.name
