param environmentName string
param location string
@secure()
param adminTeamsWorkflowUrl string
@secure()
param userTeamsWorkflowUrl string = ''
param tags object = {}

var suffix = uniqueString(subscription().id, resourceGroup().id, environmentName)

module pollerHost '../vendor/Azd.FlexScheduledPoller/flex-scheduled-poller-host.bicep' = {
  name: 'risk-notification-poller-host'
  params: {
    storageAccountName: take('striskca${suffix}', 24)
    functionPlanName: 'plan-risk-ca-${suffix}'
    functionAppName: take('func-risk-ca-${suffix}', 60)
    location: location
    environmentName: environmentName
    serviceName: 'risk-notification-poller'
    deploymentContainerName: 'function-releases'
    stateContainerName: 'risk-state'
    deadLetterContainerName: 'risk-dead-letter'
    applicationSettings: {
      AZD_CA_ADMIN_TEAMS_WORKFLOW_URL: adminTeamsWorkflowUrl
      AZD_CA_USER_TEAMS_WORKFLOW_URL: userTeamsWorkflowUrl
      AZD_CA_POLLING_SCHEDULE: '0 */5 * * * *'
    }
    storageAccountSettingAliases: [
      'AZD_CA_STORAGE_ACCOUNT_NAME'
    ]
    stateContainerSettingAliases: [
      'AZD_CA_STATE_CONTAINER'
    ]
    deadLetterContainerSettingAliases: [
      'AZD_CA_DEAD_LETTER_CONTAINER'
    ]
    instanceMemoryMB: 512
    maximumInstanceCount: 1
    blobDeleteRetentionDays: 14
    tags: tags
  }
}

output functionAppName string = pollerHost.outputs.functionAppName
output functionAppPrincipalId string = pollerHost.outputs.functionAppPrincipalId
