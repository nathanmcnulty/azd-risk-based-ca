param environmentName string
param location string
param teamId string
param channelId string
param tags object = {}

var suffix = uniqueString(subscription().id, resourceGroup().id, environmentName)
var connectionName = take('teams-risk-ca-${suffix}', 80)
var workflowName = take('logic-risk-ca-teams-${suffix}', 80)
var teamsManagedApiId = subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'teams')

resource teamsConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: connectionName
  location: location
  tags: tags
  properties: {
    displayName: 'azd risk-based Conditional Access notifications'
    api: {
      id: teamsManagedApiId
    }
  }
}

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: workflowName
  location: location
  tags: tags
  properties: {
    state: 'Disabled'
    parameters: {
      '$connections': {
        value: {
          teams: {
            connectionId: teamsConnection.id
            connectionName: teamsConnection.name
            id: teamsManagedApiId
          }
        }
      }
    }
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          type: 'Object'
          defaultValue: {}
        }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              required: [
                'type'
                'attachments'
              ]
            }
          }
        }
      }
      actions: {
        Post_risk_card_to_Teams: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'teams\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v1.0/teams/conversation/adaptivecard/poster/@{encodeURIComponent(\'User\')}/location/@{encodeURIComponent(\'Channel\')}'
            body: {
              recipient: {
                groupId: teamId
                channelId: channelId
              }
              messageBody: '@triggerBody()?[\'attachments\']?[0]?[\'content\']'
            }
            retryPolicy: {
              type: 'exponential'
              count: 4
              interval: 'PT10S'
            }
          }
          runAfter: {}
        }
        Delivery_succeeded: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: {
              delivered: true
            }
          }
          runAfter: {
            Post_risk_card_to_Teams: [
              'Succeeded'
            ]
          }
        }
        Delivery_failed: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 502
            body: {
              delivered: false
            }
          }
          runAfter: {
            Post_risk_card_to_Teams: [
              'Failed'
              'TimedOut'
            ]
          }
        }
      }
      outputs: {}
    }
  }
}

output connectionResourceId string = teamsConnection.id
output workflowResourceId string = workflow.id
output workflowName string = workflow.name
@secure()
output callbackUrl string = listCallbackUrl('${workflow.id}/triggers/manual', '2019-05-01').value
