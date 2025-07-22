@description('Module for creating monitoring and alerting components')

// Parameters
@description('Location for monitoring resources')
param location string

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 90

@description('Action group name')
param actionGroupName string

@description('Email address for alerts')
param alertEmailAddress string

@description('Workbook name')
param workbookName string

@description('Tags to apply to resources')
param tags object = {}

@description('Resources to monitor')
param monitoredResources object = {}

@description('Enable diagnostic settings')
param enableDiagnostics bool = true

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 10
    }
  }
}

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'HPCAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'admin'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
    eventHubReceivers: []
  }
}

// Metric Alert for Cache Hit Rate
resource cacheHitRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (contains(monitoredResources, 'hpcCache')) {
  name: 'low-cache-hit-rate'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when cache hit rate drops below 80%'
    severity: 2
    enabled: true
    scopes: [
      monitoredResources.hpcCache.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CacheHitPercent'
          metricName: 'CacheHitPercent'
          operator: 'LessThan'
          threshold: 80
          timeAggregation: 'Average'
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

// Metric Alert for High Compute Utilization
resource computeUtilizationAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (contains(monitoredResources, 'batchAccount')) {
  name: 'high-compute-utilization'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when running nodes exceed 90% of target'
    severity: 2
    enabled: true
    scopes: [
      monitoredResources.batchAccount.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'RunningNodeCount'
          metricName: 'RunningNodeCount'
          operator: 'GreaterThan'
          threshold: (monitoredResources.batchAccount.nodeCount * 90) / 100
          timeAggregation: 'Average'
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

// Storage Account Alert for High Transaction Rate
resource storageTransactionAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (contains(monitoredResources, 'storageAccount')) {
  name: 'high-storage-transactions'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when storage transactions exceed threshold'
    severity: 3
    enabled: true
    scopes: [
      monitoredResources.storageAccount.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Transactions'
          metricName: 'Transactions'
          operator: 'GreaterThan'
          threshold: 10000
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

// Azure Monitor Workbook for HPC Monitoring
resource monitoringWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, workbookName)
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: workbookName
    serializedData: '{"version":"Notebook/1.0","items":[{"type":1,"content":{"json":"## HPC Cache Performance Dashboard\\n\\nThis dashboard provides comprehensive monitoring for Azure HPC Cache, Batch compute clusters, and storage performance metrics.\\n\\n### Key Metrics\\n- **Cache Hit Rate**: Percentage of cache hits vs misses\\n- **Compute Utilization**: Number of active compute nodes\\n- **Storage Throughput**: Read/write operations per second\\n- **Task Completion**: Batch job completion rates"}},{"type":3,"content":{"version":"KqlItem/1.0","query":"AzureMetrics\\n| where ResourceProvider == \\"MICROSOFT.STORAGECACHE\\"\\n| where MetricName == \\"CacheHitPercent\\"\\n| summarize avg(Average) by bin(TimeGenerated, 5m)\\n| render timechart with (title=\\"Cache Hit Rate Over Time\\", xtitle=\\"Time\\", ytitle=\\"Hit Rate (%)\\" )","size":0,"title":"Cache Hit Rate Over Time","timeContext":{"durationMs":3600000},"queryType":0,"resourceType":"microsoft.operationalinsights/workspaces"}},{"type":3,"content":{"version":"KqlItem/1.0","query":"AzureMetrics\\n| where ResourceProvider == \\"MICROSOFT.BATCH\\"\\n| where MetricName == \\"RunningNodeCount\\"\\n| summarize avg(Average) by bin(TimeGenerated, 5m)\\n| render timechart with (title=\\"Active Compute Nodes\\", xtitle=\\"Time\\", ytitle=\\"Node Count\\")","size":0,"title":"Active Compute Nodes","timeContext":{"durationMs":3600000},"queryType":0,"resourceType":"microsoft.operationalinsights/workspaces"}},{"type":3,"content":{"version":"KqlItem/1.0","query":"AzureMetrics\\n| where ResourceProvider == \\"MICROSOFT.STORAGE\\"\\n| where MetricName == \\"Transactions\\"\\n| summarize sum(Total) by bin(TimeGenerated, 5m)\\n| render timechart with (title=\\"Storage Transactions\\", xtitle=\\"Time\\", ytitle=\\"Transactions/min\\")","size":0,"title":"Storage Transactions","timeContext":{"durationMs":3600000},"queryType":0,"resourceType":"microsoft.operationalinsights/workspaces"}},{"type":3,"content":{"version":"KqlItem/1.0","query":"AzureMetrics\\n| where ResourceProvider == \\"MICROSOFT.STORAGECACHE\\"\\n| where MetricName == \\"ReadThroughputBytesPerSecond\\"\\n| summarize avg(Average) by bin(TimeGenerated, 5m)\\n| render timechart with (title=\\"Cache Read Throughput\\", xtitle=\\"Time\\", ytitle=\\"Bytes/sec\\")","size":0,"title":"Cache Read Throughput","timeContext":{"durationMs":3600000},"queryType":0,"resourceType":"microsoft.operationalinsights/workspaces"}},{"type":3,"content":{"version":"KqlItem/1.0","query":"AzureMetrics\\n| where ResourceProvider == \\"MICROSOFT.BATCH\\"\\n| where MetricName == \\"CompletedTaskCount\\"\\n| summarize sum(Total) by bin(TimeGenerated, 5m)\\n| render timechart with (title=\\"Completed Tasks\\", xtitle=\\"Time\\", ytitle=\\"Tasks/min\\")","size":0,"title":"Completed Tasks","timeContext":{"durationMs":3600000},"queryType":0,"resourceType":"microsoft.operationalinsights/workspaces"}},{"type":3,"content":{"version":"KqlItem/1.0","query":"AzureMetrics\\n| where ResourceProvider == \\"MICROSOFT.STORAGECACHE\\"\\n| where MetricName == \\"WriteThroughputBytesPerSecond\\"\\n| summarize avg(Average) by bin(TimeGenerated, 5m)\\n| render timechart with (title=\\"Cache Write Throughput\\", xtitle=\\"Time\\", ytitle=\\"Bytes/sec\\")","size":0,"title":"Cache Write Throughput","timeContext":{"durationMs":3600000},"queryType":0,"resourceType":"microsoft.operationalinsights/workspaces"}}],"styleSettings":{"showBorder":true},"links":[],"fallbackResourceIds":[],"fromTemplateId":"Community-Workbooks/Azure Monitor - Getting Started/Getting Started"}'
    version: '1.0'
    sourceId: logAnalyticsWorkspace.id
    category: 'HPC'
    description: 'Comprehensive monitoring dashboard for HPC Cache, Batch compute clusters, and storage performance metrics'
  }
}

// Outputs
@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Action Group ID')
output actionGroupId string = actionGroup.id

@description('Action Group Name')
output actionGroupName string = actionGroup.name

@description('Workbook ID')
output workbookId string = monitoringWorkbook.id

@description('Workbook Name')
output workbookName string = monitoringWorkbook.properties.displayName

@description('Alert Rules Created')
output alertRulesCreated array = [
  {
    name: 'low-cache-hit-rate'
    enabled: contains(monitoredResources, 'hpcCache')
    threshold: 80
    metric: 'CacheHitPercent'
  }
  {
    name: 'high-compute-utilization'
    enabled: contains(monitoredResources, 'batchAccount')
    threshold: 90
    metric: 'RunningNodeCount'
  }
  {
    name: 'high-storage-transactions'
    enabled: contains(monitoredResources, 'storageAccount')
    threshold: 10000
    metric: 'Transactions'
  }
]