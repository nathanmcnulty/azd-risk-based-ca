@description('Name of the Azure Monitor action group.')
@minLength(1)
param actionGroupName string

@description('Action group short name. Azure Monitor limits this value to 12 characters.')
@minLength(1)
@maxLength(12)
param groupShortName string

@description('Resource ID of the solution-owned Logic App workflow.')
@minLength(1)
param logicAppResourceId string

@description('Display name of the Logic App receiver in the action group.')
@minLength(1)
param receiverName string

@description('Name of the HTTP request trigger in the solution-owned Logic App workflow.')
@minLength(1)
param logicAppTriggerName string = 'manual'

@description('Resource tags applied to the action group.')
param tags object = {}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: groupShortName
    enabled: true
    logicAppReceivers: [
      {
        name: receiverName
        resourceId: logicAppResourceId
        callbackUrl: listCallbackUrl('${logicAppResourceId}/triggers/${logicAppTriggerName}', '2019-05-01').value
        useCommonAlertSchema: true
      }
    ]
  }
}

output actionGroupResourceId string = actionGroup.id
