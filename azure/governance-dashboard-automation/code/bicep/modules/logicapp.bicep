// ======================================================================================
// Logic App Module for Governance Automation
// ======================================================================================
// This module creates a Logic App workflow for automated governance responses,
// including Slack notifications and Log Analytics integration.
// ======================================================================================

@description('The Azure region where the Logic App should be deployed')
param location string = resourceGroup().location

@description('The name of the Logic App')
param logicAppName string

@description('Tags to apply to the Logic App')
param resourceTags object = {}

@description('Log Analytics Workspace ID for logging alerts')
param logAnalyticsWorkspaceId string

@description('Log Analytics Customer ID for API calls')
param logAnalyticsCustomerId string

@description('Log Analytics Primary Shared Key for authentication')
@secure()
param logAnalyticsPrimaryKey string

@description('Slack webhook URL for notifications (optional)')
param slackWebhookUrl string = ''

@description('Environment name for tagging and identification')
param environment string = 'dev'

// ======================================================================================
// Logic App Workflow Definition
// ======================================================================================

var logicAppDefinition = {
  '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
  contentVersion: '1.0.0.0'
  parameters: {
    slackWebhookUrl: {
      type: 'string'
      defaultValue: slackWebhookUrl
    }
    logAnalyticsCustomerId: {
      type: 'string'
      defaultValue: logAnalyticsCustomerId
    }
    logAnalyticsPrimaryKey: {
      type: 'securestring'
      defaultValue: logAnalyticsPrimaryKey
    }
  }
  triggers: {
    manual: {
      type: 'Request'
      kind: 'Http'
      inputs: {
        schema: {
          type: 'object'
          properties: {
            alertType: {
              type: 'string'
            }
            resourceId: {
              type: 'string'
            }
            severity: {
              type: 'string'
            }
            description: {
              type: 'string'
            }
            subscriptionId: {
              type: 'string'
            }
            resourceGroup: {
              type: 'string'
            }
            timestamp: {
              type: 'string'
            }
            policyName: {
              type: 'string'
            }
            complianceState: {
              type: 'string'
            }
          }
          required: [
            'alertType'
            'resourceId'
            'severity'
          ]
        }
      }
    }
  }
  actions: {
    'Initialize_Alert_Context': {
      type: 'InitializeVariable'
      inputs: {
        variables: [
          {
            name: 'alertContext'
            type: 'object'
            value: {
              alertType: '@triggerBody()?[\'alertType\']'
              resourceId: '@triggerBody()?[\'resourceId\']'
              severity: '@triggerBody()?[\'severity\']'
              description: '@triggerBody()?[\'description\']'
              subscriptionId: '@triggerBody()?[\'subscriptionId\']'
              resourceGroup: '@triggerBody()?[\'resourceGroup\']'
              timestamp: '@triggerBody()?[\'timestamp\']'
              policyName: '@triggerBody()?[\'policyName\']'
              complianceState: '@triggerBody()?[\'complianceState\']'
            }
          }
        ]
      }
      runAfter: {}
    }
    'Initialize_Alert_Message': {
      type: 'InitializeVariable'
      inputs: {
        variables: [
          {
            name: 'alertMessage'
            type: 'string'
            value: '🚨 *Azure Governance Alert* 🚨\n\n*Type:* @{variables(\'alertContext\').alertType}\n*Resource:* @{variables(\'alertContext\').resourceId}\n*Severity:* @{variables(\'alertContext\').severity}\n*Description:* @{variables(\'alertContext\').description}\n*Subscription:* @{variables(\'alertContext\').subscriptionId}\n*Resource Group:* @{variables(\'alertContext\').resourceGroup}\n*Policy:* @{variables(\'alertContext\').policyName}\n*Compliance State:* @{variables(\'alertContext\').complianceState}\n*Timestamp:* @{variables(\'alertContext\').timestamp}\n\n*Action Required:* Please investigate and remediate this governance violation immediately.\n\n*Portal Link:* https://portal.azure.com/#@tenant/resource@{variables(\'alertContext\').resourceId}'
          }
        ]
      }
      runAfter: {
        'Initialize_Alert_Context': [
          'Succeeded'
        ]
      }
    }
    'Determine_Severity_Level': {
      type: 'Switch'
      expression: '@variables(\'alertContext\').severity'
      cases: {
        'High': {
          actions: {
            'Set_High_Priority_Icon': {
              type: 'SetVariable'
              inputs: {
                name: 'severityIcon'
                value: '🔴'
              }
            }
          }
        }
        'Medium': {
          actions: {
            'Set_Medium_Priority_Icon': {
              type: 'SetVariable'
              inputs: {
                name: 'severityIcon'
                value: '🟡'
              }
            }
          }
        }
        'Low': {
          actions: {
            'Set_Low_Priority_Icon': {
              type: 'SetVariable'
              inputs: {
                name: 'severityIcon'
                value: '🟢'
              }
            }
          }
        }
      }
      default: {
        actions: {
          'Set_Default_Icon': {
            type: 'SetVariable'
            inputs: {
              name: 'severityIcon'
              value: '⚪'
            }
          }
        }
      }
      runAfter: {
        'Initialize_Severity_Icon': [
          'Succeeded'
        ]
      }
    }
    'Initialize_Severity_Icon': {
      type: 'InitializeVariable'
      inputs: {
        variables: [
          {
            name: 'severityIcon'
            type: 'string'
            value: '⚪'
          }
        ]
      }
      runAfter: {
        'Initialize_Alert_Message': [
          'Succeeded'
        ]
      }
    }
    'Condition_Check_Slack_Webhook': {
      type: 'If'
      expression: {
        and: [
          {
            not: {
              equals: [
                '@parameters(\'slackWebhookUrl\')'
                ''
              ]
            }
          }
        ]
      }
      actions: {
        'Send_Slack_Notification': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '@parameters(\'slackWebhookUrl\')'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              text: '@{variables(\'severityIcon\')} @{variables(\'alertMessage\')}'
              username: 'Azure Governance Bot'
              icon_emoji: ':warning:'
              channel: '#governance-alerts'
              attachments: [
                {
                  color: '@{if(equals(variables(\'alertContext\').severity, \'High\'), \'danger\', if(equals(variables(\'alertContext\').severity, \'Medium\'), \'warning\', \'good\'))}'
                  fields: [
                    {
                      title: 'Alert Type'
                      value: '@{variables(\'alertContext\').alertType}'
                      short: true
                    }
                    {
                      title: 'Severity'
                      value: '@{variables(\'alertContext\').severity}'
                      short: true
                    }
                    {
                      title: 'Resource'
                      value: '@{variables(\'alertContext\').resourceId}'
                      short: false
                    }
                    {
                      title: 'Policy'
                      value: '@{variables(\'alertContext\').policyName}'
                      short: true
                    }
                    {
                      title: 'Compliance State'
                      value: '@{variables(\'alertContext\').complianceState}'
                      short: true
                    }
                  ]
                  footer: 'Azure Governance Dashboard'
                  ts: '@{div(ticks(utcnow()), 10000000)}'
                }
              ]
            }
          }
        }
      }
      else: {
        actions: {
          'Log_No_Slack_Webhook': {
            type: 'Compose'
            inputs: 'Slack webhook not configured. Alert will be logged to Log Analytics only.'
          }
        }
      }
      runAfter: {
        'Determine_Severity_Level': [
          'Succeeded'
        ]
      }
    }
    'Log_Alert_to_Analytics': {
      type: 'Http'
      inputs: {
        method: 'POST'
        uri: 'https://@{parameters(\'logAnalyticsCustomerId\')}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01'
        headers: {
          'Authorization': 'SharedKey @{parameters(\'logAnalyticsCustomerId\')}:@{parameters(\'logAnalyticsPrimaryKey\')}'
          'Content-Type': 'application/json'
          'Log-Type': 'GovernanceAlert'
          'time-generated-field': 'timestamp'
        }
        body: [
          {
            alertType: '@{variables(\'alertContext\').alertType}'
            resourceId: '@{variables(\'alertContext\').resourceId}'
            severity: '@{variables(\'alertContext\').severity}'
            description: '@{variables(\'alertContext\').description}'
            subscriptionId: '@{variables(\'alertContext\').subscriptionId}'
            resourceGroup: '@{variables(\'alertContext\').resourceGroup}'
            policyName: '@{variables(\'alertContext\').policyName}'
            complianceState: '@{variables(\'alertContext\').complianceState}'
            timestamp: '@{variables(\'alertContext\').timestamp}'
            processedTimestamp: '@{utcnow()}'
            environment: environment
            logicAppName: logicAppName
          }
        ]
      }
      runAfter: {
        'Condition_Check_Slack_Webhook': [
          'Succeeded'
          'Failed'
          'Skipped'
        ]
      }
    }
    'Create_Alert_Response': {
      type: 'Response'
      kind: 'Http'
      inputs: {
        statusCode: 200
        headers: {
          'Content-Type': 'application/json'
        }
        body: {
          status: 'success'
          message: 'Governance alert processed successfully'
          alertId: '@{guid()}'
          timestamp: '@{utcnow()}'
          processedAlert: '@{variables(\'alertContext\')}'
          notificationsSent: {
            slack: '@{if(empty(parameters(\'slackWebhookUrl\')), false, true)}'
            logAnalytics: true
          }
        }
      }
      runAfter: {
        'Log_Alert_to_Analytics': [
          'Succeeded'
        ]
      }
    }
  }
  outputs: {}
}

// ======================================================================================
// Logic App Resource
// ======================================================================================

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: logicAppDefinition
    parameters: {}
  }
}

// ======================================================================================
// Outputs
// ======================================================================================

@description('The resource ID of the Logic App')
output logicAppId string = logicApp.id

@description('The name of the Logic App')
output logicAppName string = logicApp.name

@description('The trigger URL for the Logic App')
output logicAppTriggerUrl string = listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicApp.name, 'manual'), '2019-05-01').value

@description('The principal ID of the Logic App managed identity')
output logicAppPrincipalId string = logicApp.identity.principalId

@description('The Logic App state')
output logicAppState string = logicApp.properties.state