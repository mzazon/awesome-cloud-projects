@description('Deploys Azure Communication Services with Application Insights monitoring')
@minLength(3)
@maxLength(24)
param resourceNamePrefix string = 'comm-monitor'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment tag for resources')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'communication-monitoring'
  environment: environment
  recipe: 'communication-monitoring-services-insights'
}

@description('Communication Services data location')
@allowed(['United States', 'Europe', 'Asia Pacific', 'Australia', 'United Kingdom'])
param dataLocation string = 'United States'

@description('Log Analytics workspace SKU')
@allowed(['Free', 'Standard', 'Premium', 'PerNode', 'PerGB2018', 'Standalone'])
param workspaceSku string = 'PerGB2018'

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param workspaceRetentionDays int = 30

@description('Enable diagnostic settings for Communication Services')
param enableDiagnostics bool = true

@description('Enable metric alerts')
param enableAlerts bool = true

@description('Alert email addresses for notifications')
param alertEmailAddresses array = []

// Generate unique suffix for resource names
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var resourceNames = {
  logAnalyticsWorkspace: '${resourceNamePrefix}-law-${uniqueSuffix}'
  applicationInsights: '${resourceNamePrefix}-ai-${uniqueSuffix}'
  communicationService: '${resourceNamePrefix}-cs-${uniqueSuffix}'
  actionGroup: '${resourceNamePrefix}-ag-${uniqueSuffix}'
}

// Log Analytics Workspace - Foundation for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: tags
  properties: {
    sku: {
      name: workspaceSku
    }
    retentionInDays: workspaceRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights - Advanced monitoring and analytics
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Communication Services - Core service for email and SMS
resource communicationService 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: resourceNames.communicationService
  location: 'global'
  tags: tags
  properties: {
    dataLocation: dataLocation
  }
}

// Action Group for alert notifications
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (enableAlerts && length(alertEmailAddresses) > 0) {
  name: resourceNames.actionGroup
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'CommAlerts'
    enabled: true
    emailReceivers: [for (email, i) in alertEmailAddresses: {
      name: 'email-${i}'
      emailAddress: email
      useCommonAlertSchema: true
    }]
  }
}

// Diagnostic Settings for Communication Services
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'CommServiceDiagnostics'
  scope: communicationService
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Metric Alert for API Request Failures
resource apiRequestAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableAlerts && length(alertEmailAddresses) > 0) {
  name: 'CommunicationServiceFailures'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when Communication Services API requests exceed failure threshold'
    severity: 2
    enabled: true
    scopes: [
      communicationService.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'APIRequestFailures'
          metricName: 'APIRequests'
          dimensions: [
            {
              name: 'StatusCode'
              operator: 'Include'
              values: [
                '4*'
                '5*'
              ]
            }
          ]
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Saved query for communication monitoring
resource savedQuery 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'CommunicationServiceMonitoring'
  properties: {
    displayName: 'Communication Services Monitoring Dashboard'
    category: 'Communication Monitoring'
    query: '''
// Communication Services Monitoring Dashboard Query
union 
(
    ACSEmailSendMailOperational
    | where TimeGenerated >= ago(24h)
    | summarize 
        EmailsSent = count(),
        EmailsSuccessful = countif(Level == "Informational"),
        EmailsFailed = countif(Level == "Error")
        by bin(TimeGenerated, 1h)
    | extend ServiceType = "Email"
),
(
    ACSSMSOperational  
    | where TimeGenerated >= ago(24h)
    | summarize 
        MessagesSent = count(),
        MessagesDelivered = countif(DeliveryStatus == "Delivered"),
        MessagesFailed = countif(DeliveryStatus == "Failed")
        by bin(TimeGenerated, 1h)
    | extend ServiceType = "SMS"
)
| project TimeGenerated,
          ServiceType, 
          TotalSent = coalesce(EmailsSent, MessagesSent),
          Successful = coalesce(EmailsSuccessful, MessagesDelivered), 
          Failed = coalesce(EmailsFailed, MessagesFailed)
| extend SuccessRate = round((todouble(Successful) / todouble(TotalSent)) * 100, 2)
| order by TimeGenerated desc
'''
    tags: tags
  }
}

// Workbook for advanced monitoring dashboard
resource monitoringWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'communication-monitoring-workbook')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Communication Services Monitoring Dashboard'
    serializedData: '''
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "union \\n(\\n    ACSEmailSendMailOperational\\n    | where TimeGenerated >= ago(24h)\\n    | summarize \\n        EmailsSent = count(),\\n        EmailsSuccessful = countif(Level == \\"Informational\\"),\\n        EmailsFailed = countif(Level == \\"Error\\")\\n    | extend ServiceType = \\"Email\\"\\n),\\n(\\n    ACSSMSOperational  \\n    | where TimeGenerated >= ago(24h)\\n    | summarize \\n        MessagesSent = count(),\\n        MessagesDelivered = countif(DeliveryStatus == \\"Delivered\\"),\\n        MessagesFailed = countif(DeliveryStatus == \\"Failed\\")\\n    | extend ServiceType = \\"SMS\\"\\n)\\n| project ServiceType, \\n          TotalSent = coalesce(EmailsSent, MessagesSent),\\n          Successful = coalesce(EmailsSuccessful, MessagesDelivered), \\n          Failed = coalesce(EmailsFailed, MessagesFailed)\\n| extend SuccessRate = round((todouble(Successful) / todouble(TotalSent)) * 100, 2)",
        "size": 0,
        "title": "Communication Services Performance Overview",
        "timeContext": {
          "durationMs": 86400000
        },
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces",
        "visualization": "table"
      }
    }
  ],
  "isLocked": false,
  "fallbackResourceIds": [
    "${logAnalyticsWorkspace.id}"
  ]
}
'''
    category: 'workbook'
    sourceId: logAnalyticsWorkspace.id
  }
}

// Outputs for integration and verification
@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Communication Services resource ID')
output communicationServiceId string = communicationService.id

@description('Communication Services name')
output communicationServiceName string = communicationService.name

@description('Communication Services connection string')
output communicationServiceConnectionString string = communicationService.listKeys().primaryConnectionString

@description('Action Group ID (if created)')
output actionGroupId string = enableAlerts && length(alertEmailAddresses) > 0 ? actionGroup.id : ''

@description('Workbook ID')
output workbookId string = monitoringWorkbook.id

@description('Monitoring query for custom dashboards')
output monitoringQuery string = savedQuery.properties.query