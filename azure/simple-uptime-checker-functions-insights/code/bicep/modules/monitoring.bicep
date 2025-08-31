@description('Monitoring module for Application Insights and alerting')

@description('Application Insights name')
param appInsightsName string

@description('Azure region')
param location string = resourceGroup().location

@description('Log Analytics Workspace resource ID (optional)')
param logAnalyticsWorkspaceId string = ''

@description('Enable alerting')
param enableAlerting bool = true

@description('Alert severity (0-4)')
param alertSeverity int = 2

@description('Action group name for alerts')
param actionGroupName string

@description('Email address for alerts (optional)')
param alertEmailAddress string = ''

@description('Tags to apply')
param tags object = {}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 90
    WorkspaceResourceId: !empty(logAnalyticsWorkspaceId) ? logAnalyticsWorkspaceId : null
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    DisableIpMasking: false
    DisableLocalAuth: false
    ForceCustomerStorageForProfiler: false
  }
}

// Action Group for alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (enableAlerting) {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: take(actionGroupName, 12)
    enabled: true
    emailReceivers: !empty(alertEmailAddress) ? [
      {
        name: 'UptimeAlert'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ] : []
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
    eventHubReceivers: []
  }
}

// Alert rule for website failures
resource websiteDownAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (enableAlerting) {
  name: 'alert-website-down-${appInsightsName}'
  location: location
  tags: tags
  properties: {
    displayName: 'Website Down Alert - ${appInsightsName}'
    description: 'Alert when websites are detected as down by the uptime checker function'
    severity: alertSeverity
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    targetResourceTypes: [
      'Microsoft.Insights/components'
    ]
    scopes: [
      appInsights.id
    ]
    criteria: {
      allOf: [
        {
          query: 'traces | where timestamp > ago(10m) | where message contains "❌" | summarize count()'
          timeAggregation: 'Total'
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
    actions: enableAlerting ? {
      actionGroups: [
        actionGroup.id
      ]
    } : {}
    autoMitigate: true
    checkWorkspaceAlertsStorageConfigured: false
  }
}

// Alert rule for high response times
resource highResponseTimeAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (enableAlerting) {
  name: 'alert-high-response-time-${appInsightsName}'
  location: location
  tags: tags
  properties: {
    displayName: 'High Response Time Alert - ${appInsightsName}'
    description: 'Alert when website response times are consistently high'
    severity: alertSeverity + 1 > 4 ? 4 : alertSeverity + 1
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT30M'
    targetResourceTypes: [
      'Microsoft.Insights/components'
    ]
    scopes: [
      appInsights.id
    ]
    criteria: {
      allOf: [
        {
          query: 'traces | where timestamp > ago(30m) | where message contains "✅" | extend ResponseTime = extract(@"\\((\\d+)ms\\)", 1, message) | where isnotnull(ResponseTime) | summarize AvgResponseTime = avg(toreal(ResponseTime)) | where AvgResponseTime > 5000'
          timeAggregation: 'Count'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 2
          }
        }
      ]
    }
    actions: enableAlerting ? {
      actionGroups: [
        actionGroup.id
      ]
    } : {}
    autoMitigate: true
  }
}

// Outputs
output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output actionGroupId string = enableAlerting ? actionGroup.id : ''
output websiteDownAlertId string = enableAlerting ? websiteDownAlert.id : ''
output highResponseTimeAlertId string = enableAlerting ? highResponseTimeAlert.id : ''