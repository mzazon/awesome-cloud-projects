@description('The name of the Logic App workflow')
param logicAppName string = 'la-schedule-reminders-${uniqueString(resourceGroup().id)}'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The email address to send reminders to')
param recipientEmail string

@description('The subject for the reminder email')
param emailSubject string = 'Weekly Reminder - Team Meeting Today'

@description('The email body content (HTML format)')
param emailBody string = '<p>Hello Team,</p><p>This is your weekly reminder that we have our team meeting today at 2:00 PM.</p><p>Please prepare your weekly updates and join the meeting room.</p><p>Best regards,<br>Automated Reminder System</p>'

@description('The recurrence frequency (Week, Day, Hour, Minute)')
@allowed(['Week', 'Day', 'Hour', 'Minute'])
param recurrenceFrequency string = 'Week'

@description('The recurrence interval (number of frequency units)')
param recurrenceInterval int = 1

@description('The schedule - hours when to run (0-23, array)')
param scheduleHours array = [9]

@description('The schedule - minutes when to run (0-59, array)')
param scheduleMinutes array = [0]

@description('The schedule - days of week when to run (Monday, Tuesday, etc.)')
param scheduleWeekDays array = ['Monday']

@description('The timezone for the schedule (e.g., Eastern Standard Time, UTC)')
param timeZone string = 'Eastern Standard Time'

@description('Common tags for all resources')
param tags object = {
  purpose: 'recipe'
  environment: 'demo'
  service: 'logic-apps'
}

@description('Enable or disable the Logic App workflow')
param enableWorkflow bool = true

// Variables for the workflow definition
var workflowDefinition = {
  '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
  contentVersion: '1.0.0.0'
  parameters: {
    '$connections': {
      defaultValue: {
        office365: {
          connectionId: office365Connection.id
          connectionName: 'office365'
          id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
        }
      }
      type: 'Object'
    }
  }
  triggers: {
    Recurrence: {
      recurrence: {
        frequency: recurrenceFrequency
        interval: recurrenceInterval
        timeZone: timeZone
        schedule: recurrenceFrequency == 'Week' ? {
          hours: scheduleHours
          minutes: scheduleMinutes
          weekDays: scheduleWeekDays
        } : recurrenceFrequency == 'Day' ? {
          hours: scheduleHours
          minutes: scheduleMinutes
        } : {}
      }
      type: 'Recurrence'
    }
  }
  actions: {
    'Send_an_email_(V2)': {
      runAfter: {}
      type: 'ApiConnection'
      inputs: {
        body: {
          Body: emailBody
          Subject: emailSubject
          To: recipientEmail
        }
        host: {
          connection: {
            name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
          }
        }
        method: 'post'
        path: '/v2/Mail'
      }
    }
  }
  outputs: {}
}

// Office 365 Outlook Connection
resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'office365-connection-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    displayName: 'Office 365 Outlook Connection'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
    }
    parameterValues: {}
  }
}

// Logic App Workflow
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: tags
  properties: {
    state: enableWorkflow ? 'Enabled' : 'Disabled'
    definition: workflowDefinition
    parameters: {
      '$connections': {
        value: {
          office365: {
            connectionId: office365Connection.id
            connectionName: 'office365'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
          }
        }
      }
    }
  }
}

// Optional: Role assignment for Logic App to access Office 365 connection
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, logicApp.id, 'Logic App Contributor')
  scope: office365Connection
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '87a39d53-fc1b-424a-814c-f7e04687dc9e') // Logic App Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('The Logic App workflow name')
output logicAppName string = logicApp.name

@description('The Logic App resource ID')
output logicAppId string = logicApp.id

@description('The Logic App trigger URL for manual testing')
output triggerUrl string = listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicApp.name, 'Recurrence'), '2019-05-01').value

@description('The Office 365 connection name')
output office365ConnectionName string = office365Connection.name

@description('The Office 365 connection ID')
output office365ConnectionId string = office365Connection.id

@description('The Logic App callback URL for monitoring')
output logicAppUrl string = 'https://portal.azure.com/#@${tenant().tenantId}/resource${logicApp.id}'

@description('The Logic App state (Enabled/Disabled)')
output workflowState string = logicApp.properties.state

@description('Deployment information and next steps')
output deploymentInstructions object = {
  message: 'Logic App deployed successfully. Please complete the Office 365 connection authorization.'
  nextSteps: [
    'Navigate to the Azure portal'
    'Open the Logic App resource'
    'Go to API connections in the left menu'
    'Authorize the Office 365 Outlook connection'
    'Test the workflow manually or wait for the scheduled trigger'
  ]
  portalUrl: 'https://portal.azure.com/#@${tenant().tenantId}/resource${logicApp.id}'
  connectionAuthUrl: 'https://portal.azure.com/#@${tenant().tenantId}/resource${office365Connection.id}'
}