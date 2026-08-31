@description('Name of the Azure Monitor scheduled-query rule.')
@minLength(1)
param alertRuleName string

@description('Azure region of the target Log Analytics workspace.')
@minLength(1)
param location string

@description('Resource ID of the target Log Analytics workspace.')
@minLength(1)
param workspaceResourceId string

@description('Resource ID of the action group invoked when the rule fires.')
@minLength(1)
param actionGroupResourceId string

@description('Display name shown for the scheduled-query rule.')
@minLength(1)
param displayName string

@description('Solution-owned description of the alert behavior.')
@minLength(1)
param alertDescription string

@description('Solution-owned KQL query evaluated by the rule.')
@minLength(1)
param query string

@description('Alert severity from 0 (critical) through 4 (verbose).')
@minValue(0)
@maxValue(4)
param severity int = 2

@description('ISO 8601 interval controlling how often the query is evaluated.')
@allowed([
  'PT5M'
])
param evaluationFrequency string = 'PT5M'

@description('ISO 8601 interval controlling the query lookback window.')
@allowed([
  'PT5M'
  'PT10M'
])
param windowSize string = 'PT5M'

@description('Whether Azure Monitor automatically resolves a fired alert after the condition clears.')
param autoMitigate bool

@description('Solution-owned dimensions emitted by the query and used to split alert instances.')
param dimensions array = []

@description('Resource tags applied to the scheduled-query rule.')
param tags object = {}

resource alert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: alertRuleName
  location: location
  tags: tags
  properties: {
    displayName: displayName
    description: alertDescription
    severity: severity
    enabled: true
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [
      workspaceResourceId
    ]
    criteria: {
      allOf: [
        {
          query: query
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
          dimensions: dimensions
        }
      ]
    }
    autoMitigate: autoMitigate
    actions: {
      actionGroups: [
        actionGroupResourceId
      ]
    }
  }
}

output alertRuleResourceId string = alert.id
