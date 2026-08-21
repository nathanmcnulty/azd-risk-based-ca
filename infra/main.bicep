targetScope = 'resourceGroup'

param environmentName string
param location string = resourceGroup().location
@allowed(['none', 'graph', 'logAnalytics'])
param notificationMode string = 'none'
@allowed(['adminConfigured', 'workflowWebhook'])
param adminTeamsDeliveryMode string = 'adminConfigured'
@secure()
param adminTeamsWorkflowUrl string = ''
@secure()
param userTeamsWorkflowUrl string = ''
param adminTeamsTeamId string = ''
param adminTeamsChannelId string = ''
param logAnalyticsWorkspaceResourceId string = ''
param logAnalyticsWorkspaceLocation string = ''

var tags = { 'azd-env-name': environmentName, 'azd-risk-based-ca-managed': 'true' }

module teamsDelivery 'modules/teams-delivery.bicep' = if (notificationMode != 'none' && adminTeamsDeliveryMode == 'adminConfigured') {
  name: 'teams-risk-delivery'
  params: {
    environmentName: environmentName
    location: location
    teamId: adminTeamsTeamId
    channelId: adminTeamsChannelId
    tags: tags
  }
}

module graphNotificationsAdmin 'modules/graph-notifications.bicep' = if (notificationMode == 'graph' && adminTeamsDeliveryMode == 'adminConfigured') {
  name: 'graph-risk-notifications-admin'
  params: {
    environmentName: environmentName
    location: location
    // The matching conditions guarantee the conditional Teams module exists.
    #disable-next-line BCP318
    adminTeamsWorkflowUrl: teamsDelivery.outputs.callbackUrl
    userTeamsWorkflowUrl: userTeamsWorkflowUrl
    tags: tags
  }
}

module graphNotificationsWebhook 'modules/graph-notifications.bicep' = if (notificationMode == 'graph' && adminTeamsDeliveryMode == 'workflowWebhook') {
  name: 'graph-risk-notifications-webhook'
  params: {
    environmentName: environmentName
    location: location
    adminTeamsWorkflowUrl: adminTeamsWorkflowUrl
    userTeamsWorkflowUrl: userTeamsWorkflowUrl
    tags: tags
  }
}

module logAnalyticsNotificationsAdmin 'modules/log-analytics-notifications.bicep' = if (notificationMode == 'logAnalytics' && adminTeamsDeliveryMode == 'adminConfigured') {
  name: 'log-analytics-risk-notifications-admin'
  params: {
    environmentName: environmentName
    location: location
    workspaceResourceId: logAnalyticsWorkspaceResourceId
    workspaceLocation: logAnalyticsWorkspaceLocation
    // The matching conditions guarantee the conditional Teams module exists.
    #disable-next-line BCP318
    adminTeamsWorkflowUrl: teamsDelivery.outputs.callbackUrl
    userTeamsWorkflowUrl: userTeamsWorkflowUrl
    tags: tags
  }
}

module logAnalyticsNotificationsWebhook 'modules/log-analytics-notifications.bicep' = if (notificationMode == 'logAnalytics' && adminTeamsDeliveryMode == 'workflowWebhook') {
  name: 'log-analytics-risk-notifications-webhook'
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
  ? (adminTeamsDeliveryMode == 'adminConfigured' ? graphNotificationsAdmin!.outputs.functionAppName : graphNotificationsWebhook!.outputs.functionAppName)
  : ''
output AZD_CA_GRAPH_FUNCTION_PRINCIPAL_ID string = notificationMode == 'graph'
  ? (adminTeamsDeliveryMode == 'adminConfigured' ? graphNotificationsAdmin!.outputs.functionAppPrincipalId : graphNotificationsWebhook!.outputs.functionAppPrincipalId)
  : ''
output AZD_CA_TEAMS_CONNECTION_RESOURCE_ID string = notificationMode != 'none' && adminTeamsDeliveryMode == 'adminConfigured'
  ? teamsDelivery!.outputs.connectionResourceId
  : ''
output AZD_CA_TEAMS_WORKFLOW_RESOURCE_ID string = notificationMode != 'none' && adminTeamsDeliveryMode == 'adminConfigured'
  ? teamsDelivery!.outputs.workflowResourceId
  : ''
