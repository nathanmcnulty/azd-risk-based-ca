param environmentName string
param location string
param workspaceResourceId string
param workspaceLocation string
@secure()
param adminTeamsWorkflowUrl string
@secure()
param userTeamsWorkflowUrl string = ''
param tags object = {}

var suffix = uniqueString(subscription().id, resourceGroup().id, environmentName)
var storageName = take('striskla${suffix}', 24)
var riskQuery = '''
union withsource=SourceTable isfuzzy=true AADRiskyUsers, AADUserRiskEvents
| where TimeGenerated > ago(10m)
| extend RawId=tostring(column_ifexists("Id", "")), RiskEventId=tostring(column_ifexists("RiskEventId", "")), UserId=tostring(column_ifexists("UserId", "")), UPN=tostring(column_ifexists("UserPrincipalName", "")), RiskLevel=tostring(column_ifexists("RiskLevel", "unknown")), RiskState=tostring(column_ifexists("RiskState", "unknown")), RawRiskType=tostring(column_ifexists("RiskEventType", ""))
| extend EventId=iff(isnotempty(RawId),RawId,iff(isnotempty(RiskEventId),RiskEventId,strcat("riskyUser-",UserId,"-",format_datetime(TimeGenerated,"yyyyMMddHHmm")))), RiskType=iff(isnotempty(RawRiskType),RawRiskType,"riskyUser")
| extend Envelope=tostring(pack("schemaVersion","1.0","eventId",EventId,"detectedAt",TimeGenerated,"userId",UserId,"userPrincipalName",UPN,"userDisplayName",tostring(column_ifexists("UserDisplayName", "")),"riskType",RiskType,"riskLevel",RiskLevel,"riskState",RiskState,"source","logAnalytics","investigationUrl","https://entra.microsoft.com/#view/Microsoft_AAD_IAM/RiskyUsersBlade"))
| summarize arg_max(TimeGenerated, *) by EventId
| project TimeGenerated, EventId, Envelope
'''

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}
resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {}
}
resource delivered 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blob
  name: 'delivered'
  properties: { publicAccess: 'None' }
}
resource deadletter 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blob
  name: 'dead-letter'
  properties: { publicAccess: 'None' }
}

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'risk-la-notify-${suffix}'
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    state: 'Enabled'
    parameters: {
      adminUrl: { value: adminTeamsWorkflowUrl }
      userUrl: { value: userTeamsWorkflowUrl }
      checkpointBase: { value: '${storage.properties.primaryEndpoints.blob}${delivered.name}' }
      deadLetterBase: { value: '${storage.properties.primaryEndpoints.blob}${deadletter.name}' }
    }
    definition: loadJsonContent('logic-app-definition.json')
  }
}
resource blobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, workflow.id, 'Storage Blob Data Contributor')
  scope: storage
  properties: {
    principalId: workflow.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
  }
}
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'risk-la-${suffix}'
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'Entra risk'
    enabled: true
    logicAppReceivers: [
      {
        name: 'Risk notification workflow'
        resourceId: workflow.id
        callbackUrl: listCallbackUrl('${workflow.id}/triggers/manual', '2019-05-01').value
        useCommonAlertSchema: true
      }
    ]
  }
}
resource alert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'entra-risk-${suffix}'
  location: workspaceLocation
  tags: tags
  properties: {
    displayName: 'Microsoft Entra risk detection'
    description: 'Uses existing RiskyUsers and UserRiskEvents logs; does not create a workspace or require Sentinel.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [workspaceResourceId]
    criteria: {
      allOf: [
        {
          query: riskQuery
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: { numberOfEvaluationPeriods: 1, minFailingPeriodsToAlert: 1 }
          dimensions: [
            { name: 'Envelope', operator: 'Include', values: ['*'] }
          ]
        }
      ]
    }
    autoMitigate: false
    actions: { actionGroups: [actionGroup.id] }
  }
}
