// Deploy script for the uptime checker solution
// This file contains the deployment configuration with additional settings

targetScope = 'resourceGroup'

@description('Deployment name for tracking')
param deploymentName string = 'uptime-checker-${utcNow()}'

@description('Name prefix for all resources')
param namePrefix string = 'uptime'

@description('Environment name (dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Websites to monitor (comma-separated URLs)')
param websitesToMonitor string = 'https://www.microsoft.com,https://azure.microsoft.com,https://github.com'

@description('Monitoring interval in minutes (5-60)')
@minValue(5)
@maxValue(60)
param monitoringIntervalMinutes int = 5

@description('Enable Application Insights alerts')
param enableAlerting bool = true

@description('Alert notification email address')
param alertEmailAddress string = ''

@description('Tags to apply to all resources')
param resourceTags object = {
  solution: 'uptime-checker'
  deployedBy: 'bicep'
  deploymentDate: utcNow('yyyy-MM-dd')
}

// Generate unique resource names
var uniqueSuffix = uniqueString(resourceGroup().id, namePrefix, environment)
var functionAppName = '${namePrefix}-func-${environment}-${uniqueSuffix}'
var appInsightsName = '${namePrefix}-ai-${environment}-${uniqueSuffix}'
var storageAccountName = take('${namePrefix}stg${environment}${uniqueSuffix}', 24)
var logAnalyticsWorkspaceName = '${namePrefix}-law-${environment}-${uniqueSuffix}'

// Merge default tags with provided tags
var allTags = union(resourceTags, {
  environment: environment
  namePrefix: namePrefix
})

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: allTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Main uptime checker deployment module
module uptimeChecker 'main.bicep' = {
  name: 'uptimeCheckerDeployment'
  params: {
    functionAppName: functionAppName
    appInsightsName: appInsightsName
    storageAccountName: storageAccountName
    location: location
    nodeVersion: '18'
    hostingPlanSku: environment == 'prod' ? 'EP1' : 'Y1'
    websitesToMonitor: websitesToMonitor
    monitoringIntervalMinutes: monitoringIntervalMinutes
    functionTimeoutMinutes: 5
    enableAlerting: enableAlerting
    alertSeverity: environment == 'prod' ? 1 : 2
    tags: allTags
  }
}

// Enhanced Action Group with email notification (if email provided)
resource enhancedActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (enableAlerting && !empty(alertEmailAddress)) {
  name: 'ag-uptime-enhanced-${uniqueSuffix}'
  location: 'global'
  tags: allTags
  properties: {
    groupShortName: 'uptimemail'
    enabled: true
    emailReceivers: [
      {
        name: 'UptimeAlert'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// Custom workbook for uptime monitoring dashboards
resource uptimeWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid('uptime-workbook-${uniqueSuffix}')
  location: location
  tags: allTags
  kind: 'shared'
  properties: {
    displayName: 'Uptime Monitoring Dashboard - ${environment}'
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        {
          type: 1
          content: {
            json: '# Website Uptime Monitoring Dashboard\n\nThis dashboard provides insights into website availability and performance monitoring.'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'traces\n| where timestamp > ago(24h)\n| where message contains "✅" or message contains "❌"\n| extend Status = case(message contains "✅", "UP", "DOWN")\n| extend Website = extract(@"(https?://[^:]+)", 1, message)\n| summarize Count = count() by Status, bin(timestamp, 1h)\n| render timechart'
            size: 0
            title: 'Website Status Over Time'
            queryType: 0
            resourceType: 'microsoft.insights/components'
            visualization: 'timechart'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'traces\n| where timestamp > ago(24h)\n| where message contains "Response time"\n| extend ResponseTime = extract(@"(\\d+)ms", 1, message)\n| extend Website = extract(@"(https?://[^:]+)", 1, message)\n| summarize AvgResponseTime = avg(toint(ResponseTime)) by Website\n| render barchart'
            size: 0
            title: 'Average Response Time by Website'
            queryType: 0
            resourceType: 'microsoft.insights/components'
            visualization: 'barchart'
          }
        }
      ]
    })
    category: 'workbook'
    sourceId: uptimeChecker.outputs.appInsightsName
  }
}

// Outputs
output deploymentName string = deploymentName
output functionAppName string = uptimeChecker.outputs.functionAppName
output functionAppUrl string = uptimeChecker.outputs.functionAppUrl
output appInsightsName string = uptimeChecker.outputs.appInsightsName
output storageAccountName string = uptimeChecker.outputs.storageAccountName
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output workbookId string = uptimeWorkbook.id
output resourceGroupName string = resourceGroup().name
output environment string = environment
output monitoringIntervalMinutes int = monitoringIntervalMinutes
output websitesMonitored array = split(websitesToMonitor, ',')

// Deployment summary
output deploymentSummary object = {
  functionApp: uptimeChecker.outputs.functionAppName
  appInsights: uptimeChecker.outputs.appInsightsName
  storageAccount: uptimeChecker.outputs.storageAccountName
  alertingEnabled: enableAlerting
  emailNotifications: !empty(alertEmailAddress)
  environment: environment
  deploymentDate: utcNow('yyyy-MM-dd HH:mm:ss')
}