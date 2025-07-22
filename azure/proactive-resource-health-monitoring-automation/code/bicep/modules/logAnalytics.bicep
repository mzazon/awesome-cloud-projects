@description('Log Analytics workspace module for health monitoring system')

// Parameters
@description('Name of the Log Analytics workspace')
param workspaceName string

@description('Azure region for deployment')
param location string

@description('Resource tags')
param tags object

@description('Log Analytics workspace SKU')
@allowed(['Free', 'Standard', 'Premium', 'Standalone', 'PerNode', 'PerGB2018'])
param sku string = 'PerGB2018'

@description('Data retention period in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Saved Searches for Health Monitoring Analytics
resource healthEventsQuery 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'HealthEventsAnalysis'
  properties: {
    category: 'Health Monitoring'
    displayName: 'Health Events Analysis'
    query: '''
AzureActivity
| where CategoryValue == "ResourceHealth"
| summarize count() by ResourceId, Status, bin(TimeGenerated, 1h)
| order by TimeGenerated desc
'''
    functionAlias: 'HealthEventsAnalysis'
    functionParameters: ''
    version: 2
    tags: [
      {
        name: 'Purpose'
        value: 'Health Monitoring'
      }
    ]
  }
}

resource remediationActionsQuery 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'RemediationActionsTracking'
  properties: {
    category: 'Health Monitoring'
    displayName: 'Remediation Actions Tracking'
    query: '''
AzureActivity
| where OperationNameValue contains "Logic"
| where ResourceProvider == "Microsoft.Logic"
| summarize count() by bin(TimeGenerated, 1h), OperationNameValue
| order by TimeGenerated desc
'''
    functionAlias: 'RemediationActionsTracking'
    functionParameters: ''
    version: 2
    tags: [
      {
        name: 'Purpose'
        value: 'Health Monitoring'
      }
    ]
  }
}

resource serviceBusMetricsQuery 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'ServiceBusMessageProcessing'
  properties: {
    category: 'Health Monitoring'
    displayName: 'Service Bus Message Processing'
    query: '''
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SERVICEBUS"
| where Category == "OperationalLogs"
| summarize count() by bin(TimeGenerated, 15m), Status_s
| order by TimeGenerated desc
'''
    functionAlias: 'ServiceBusMessageProcessing'
    functionParameters: ''
    version: 2
    tags: [
      {
        name: 'Purpose'
        value: 'Health Monitoring'
      }
    ]
  }
}

resource healthMonitoringDashboardQuery 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'HealthMonitoringDashboard'
  properties: {
    category: 'Health Monitoring'
    displayName: 'Health Monitoring Dashboard Data'
    query: '''
let HealthEvents = AzureActivity
| where CategoryValue == "ResourceHealth"
| summarize HealthEventCount = count() by bin(TimeGenerated, 1h);
let RemediationActions = AzureActivity
| where OperationNameValue contains "Logic"
| where ResourceProvider == "Microsoft.Logic"
| summarize RemediationCount = count() by bin(TimeGenerated, 1h);
HealthEvents
| join kind=fullouter RemediationActions on TimeGenerated
| project TimeGenerated = coalesce(TimeGenerated, TimeGenerated1), 
          HealthEventCount = coalesce(HealthEventCount, 0),
          RemediationCount = coalesce(RemediationCount, 0)
| order by TimeGenerated desc
'''
    functionAlias: 'HealthMonitoringDashboard'
    functionParameters: ''
    version: 2
    tags: [
      {
        name: 'Purpose'
        value: 'Health Monitoring'
      }
    ]
  }
}

// Data Collection Rules for enhanced monitoring
resource healthMonitoringDCR 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: '${workspaceName}-health-monitoring-dcr'
  location: location
  tags: tags
  properties: {
    description: 'Data collection rule for health monitoring system'
    dataSources: {
      performanceCounters: [
        {
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\Memory\\Available MBytes'
            '\\Network Interface(*)\\Bytes Total/sec'
          ]
          name: 'perfCounterDataSource'
        }
      ]
      windowsEventLogs: [
        {
          streams: [
            'Microsoft-WindowsEvent'
          ]
          xPathQueries: [
            'System!*[System[(Level=1 or Level=2 or Level=3)]]'
            'Application!*[System[(Level=1 or Level=2 or Level=3)]]'
          ]
          name: 'eventLogsDataSource'
        }
      ]
      syslog: [
        {
          streams: [
            'Microsoft-Syslog'
          ]
          facilityNames: [
            'auth'
            'authpriv'
            'cron'
            'daemon'
            'mark'
            'kern'
            'local0'
            'local1'
            'local2'
            'local3'
            'local4'
            'local5'
            'local6'
            'local7'
            'lpr'
            'mail'
            'news'
            'syslog'
            'user'
            'uucp'
          ]
          logLevels: [
            'Debug'
            'Info'
            'Notice'
            'Warning'
            'Error'
            'Critical'
            'Alert'
            'Emergency'
          ]
          name: 'sysLogsDataSource'
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'la-destination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Perf'
          'Microsoft-Syslog'
          'Microsoft-WindowsEvent'
        ]
        destinations: [
          'la-destination'
        ]
      }
    ]
  }
}

// Outputs
@description('Log Analytics workspace ID')
output workspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Log Analytics workspace resource ID')
output workspaceResourceId string = logAnalyticsWorkspace.id

@description('Log Analytics workspace name')
output workspaceName string = logAnalyticsWorkspace.name

@description('Data Collection Rule resource ID')
output dataCollectionRuleId string = healthMonitoringDCR.id