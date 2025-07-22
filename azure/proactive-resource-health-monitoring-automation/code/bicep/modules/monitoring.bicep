@description('Monitoring module for health monitoring system including Action Groups and Resource Health alerts')

// Parameters
@description('Name of the Action Group')
param actionGroupName string

@description('Azure region for deployment')
param location string

@description('Resource tags')
param tags object

@description('Logic App trigger URL for webhook')
@secure()
param logicAppTriggerUrl string

@description('Log Analytics workspace ID')
param workspaceId string

@description('Email address for notifications')
param notificationEmail string = ''

@description('SMS phone number for critical alerts')
param smsPhoneNumber string = ''

@description('Enable email notifications')
param enableEmailNotifications bool = false

@description('Enable SMS notifications')
param enableSmsNotifications bool = false

// Action Group for Health Alerts
resource healthActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: substring(actionGroupName, 0, min(12, length(actionGroupName)))
    enabled: true
    emailReceivers: enableEmailNotifications && !empty(notificationEmail) ? [
      {
        name: 'EmailNotification'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ] : []
    smsReceivers: enableSmsNotifications && !empty(smsPhoneNumber) ? [
      {
        name: 'SmsNotification'
        countryCode: '1'
        phoneNumber: smsPhoneNumber
      }
    ] : []
    webhookReceivers: [
      {
        name: 'LogicAppWebhook'
        serviceUri: logicAppTriggerUrl
        useCommonAlertSchema: true
      }
    ]
    logicAppReceivers: []
    azureFunctionReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
  }
}

// Activity Log Alert for Resource Health Events
resource resourceHealthAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'ResourceHealthAlert-${uniqueString(resourceGroup().id)}'
  location: 'Global'
  tags: tags
  properties: {
    enabled: true
    description: 'Alert when any resource health status changes'
    scopes: [
      resourceGroup().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ResourceHealth'
        }
        {
          field: 'properties.currentHealthStatus'
          containsAny: [
            'Unavailable'
            'Degraded'
            'Unknown'
          ]
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: healthActionGroup.id
          webhookProperties: {}
        }
      ]
    }
  }
}

// Activity Log Alert for Service Health Events
resource serviceHealthAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'ServiceHealthAlert-${uniqueString(resourceGroup().id)}'
  location: 'Global'
  tags: tags
  properties: {
    enabled: true
    description: 'Alert when Azure service health events occur'
    scopes: [
      '/subscriptions/${subscription().subscriptionId}'
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
        {
          field: 'properties.incidentType'
          containsAny: [
            'Incident'
            'Maintenance'
            'Information'
            'ActionRequired'
          ]
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: healthActionGroup.id
          webhookProperties: {}
        }
      ]
    }
  }
}

// Metric Alert for Logic App Failed Runs
resource logicAppFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'LogicAppFailureAlert-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    description: 'Alert when Logic App runs fail'
    severity: 2
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'LogicAppFailures'
          metricNamespace: 'Microsoft.Logic/workflows'
          metricName: 'RunsFailed'
          operator: 'GreaterThan'
          threshold: 1
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: healthActionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// Service Bus Queue Depth Alert
resource serviceBusQueueAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'ServiceBusQueueDepthAlert-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    description: 'Alert when Service Bus queue depth is high'
    severity: 3
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'QueueDepth'
          metricNamespace: 'Microsoft.ServiceBus/namespaces'
          metricName: 'ActiveMessages'
          operator: 'GreaterThan'
          threshold: 100
          timeAggregation: 'Maximum'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'EntityName'
              operator: 'Include'
              values: ['*']
            }
          ]
        }
      ]
    }
    actions: [
      {
        actionGroupId: healthActionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// Log Analytics Query Alert for Health Event Processing
resource healthEventProcessingAlert 'Microsoft.Insights/scheduledQueryRules@2021-08-01' = {
  name: 'HealthEventProcessingAlert-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    displayName: 'Health Event Processing Failure Alert'
    description: 'Alert when health event processing fails or takes too long'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT10M'
    windowSize: 'PT30M'
    scopes: [
      '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/${workspaceId}'
    ]
    criteria: {
      allOf: [
        {
          query: '''
AzureActivity
| where CategoryValue == "ResourceHealth"
| where ActivityStatusValue == "Failed"
| summarize count() by bin(TimeGenerated, 10m)
| where count_ > 5
'''
          timeAggregation: 'Count'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        healthActionGroup.id
      ]
      customProperties: {}
    }
    autoMitigate: true
  }
}

// Budget Alert for Cost Monitoring
resource budgetAlert 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: 'HealthMonitoringBudget-${uniqueString(resourceGroup().id)}'
  properties: {
    displayName: 'Health Monitoring System Budget'
    amount: 200
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: '2025-01-01'
      endDate: '2025-12-31'
    }
    filter: {
      dimensions: {
        name: 'ResourceGroupName'
        operator: 'In'
        values: [
          resourceGroup().name
        ]
      }
    }
    notifications: {
      actual80: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: enableEmailNotifications && !empty(notificationEmail) ? [
          notificationEmail
        ] : []
        contactGroups: [
          healthActionGroup.id
        ]
        thresholdType: 'Actual'
      }
      forecasted100: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: enableEmailNotifications && !empty(notificationEmail) ? [
          notificationEmail
        ] : []
        contactGroups: [
          healthActionGroup.id
        ]
        thresholdType: 'Forecasted'
      }
    }
  }
}

// Application Insights for enhanced monitoring (optional)
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-health-monitoring-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'IbizaAIExtension'
    WorkspaceResourceId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/${workspaceId}'
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Workbook for Health Monitoring Dashboard
resource healthMonitoringWorkbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid('health-monitoring-workbook', resourceGroup().id)
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Health Monitoring Dashboard'
    description: 'Comprehensive dashboard for health monitoring system'
    category: 'workbook'
    serializedData: '''
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# Health Monitoring Dashboard\\n\\nThis dashboard provides insights into your health monitoring system performance and resource health status."
      },
      "name": "text - title"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureActivity\\n| where CategoryValue == \\"ResourceHealth\\"\\n| summarize count() by bin(TimeGenerated, 1h), Status_s\\n| render timechart",
        "size": 0,
        "title": "Resource Health Events Over Time",
        "timeContext": {
          "durationMs": 86400000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      },
      "name": "query - health events"
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureActivity\\n| where OperationNameValue contains \\"Logic\\"\\n| where ResourceProvider == \\"Microsoft.Logic\\"\\n| summarize count() by bin(TimeGenerated, 1h), ActivityStatusValue\\n| render timechart",
        "size": 0,
        "title": "Logic App Executions",
        "timeContext": {
          "durationMs": 86400000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      },
      "name": "query - logic apps"
    }
  ],
  "isLocked": false,
  "fallbackResourceIds": [
    "/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/${workspaceId}"
  ]
}
'''
    sourceId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/${workspaceId}'
  }
}

// Outputs
@description('Action Group resource ID')
output actionGroupId string = healthActionGroup.id

@description('Action Group name')
output actionGroupName string = healthActionGroup.name

@description('Resource Health alert resource ID')
output resourceHealthAlertId string = resourceHealthAlert.id

@description('Service Health alert resource ID')
output serviceHealthAlertId string = serviceHealthAlert.id

@description('Application Insights resource ID')
output applicationInsightsId string = applicationInsights.id

@description('Application Insights instrumentation key')
@secure()
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Health monitoring workbook resource ID')
output workbookId string = healthMonitoringWorkbook.id