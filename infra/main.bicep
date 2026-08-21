targetScope = 'resourceGroup'

param environmentName string
param location string = resourceGroup().location
@allowed(['none', 'graph', 'logAnalytics'])
param notificationMode string = 'none'
@secure()
param adminTeamsWorkflowUrl string = ''
@secure()
param userTeamsWorkflowUrl string = ''
param logAnalyticsWorkspaceResourceId string = ''
param logAnalyticsWorkspaceLocation string = ''

var tags = { 'azd-env-name': environmentName, 'azd-risk-based-ca-managed': 'true' }

module graphNotifications 'modules/graph-notifications.bicep' = if (notificationMode == 'graph') {
  name: 'graph-risk-notifications'
  params: {
    environmentName: environmentName
    location: location
    adminTeamsWorkflowUrl: adminTeamsWorkflowUrl
    userTeamsWorkflowUrl: userTeamsWorkflowUrl
    tags: tags
  }
}

module logAnalyticsNotifications 'modules/log-analytics-notifications.bicep' = if (notificationMode == 'logAnalytics') {
  name: 'log-analytics-risk-notifications'
  params: {
    environmentName: environmentName
    location: location
    workspaceResourceId: logAnalyticsWorkspaceResourceId
    workspaceLocation: logAnalyticsWorkspaceLocation
    adminTeamsWorkflowUrl: adminTeamsWorkflowUrl
    userTeamsWorkflowUrl: userTeamsWorkflowUrl
    tags: tags
  }
}

output AZD_CA_NOTIFICATION_MODE string = notificationMode
output AZD_CA_GRAPH_FUNCTION_NAME string = notificationMode == 'graph'
  ? graphNotifications!.outputs.functionAppName
  : ''
output AZD_CA_GRAPH_FUNCTION_PRINCIPAL_ID string = notificationMode == 'graph'
  ? graphNotifications!.outputs.functionAppPrincipalId
  : ''
