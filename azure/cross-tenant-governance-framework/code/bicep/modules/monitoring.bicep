// ==============================================================================
// Monitoring Module
// ==============================================================================
// This module creates monitoring resources including Log Analytics workspace,
// alert rules, and action groups for cross-tenant monitoring.
// ==============================================================================

@description('Location for monitoring resources')
param location string

@description('Name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string

@description('SKU for the Log Analytics workspace')
@allowed([
  'CapacityReservation'
  'Free'
  'LACluster'
  'PerGB2018'
  'PerNode'
  'Premium'
  'Standalone'
  'Standard'
])
param logAnalyticsWorkspaceSku string = 'PerGB2018'

@description('Name of the action group for alerting')
param actionGroupName string

@description('Email address for alert notifications')
param alertEmailAddress string

@description('Tags to apply to monitoring resources')
param tags object = {}

// ==============================================================================
// Variables
// ==============================================================================

var alertRuleName = 'vm-availability-cross-tenant'

// ==============================================================================
// Log Analytics Workspace
// ==============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsWorkspaceSku
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 10
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ==============================================================================
// Action Group for Alerting
// ==============================================================================

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'LighthouseOps'
    enabled: true
    emailReceivers: [
      {
        name: 'MSP-Operations'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    eventHubReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

// ==============================================================================
// Data Collection Rule for VM Monitoring
// ==============================================================================

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-vm-monitoring-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  properties: {
    description: 'Data collection rule for VM monitoring across tenants'
    dataSources: {
      performanceCounters: [
        {
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor Information(_Total)\\% Processor Time'
            '\\Memory\\Available Bytes'
            '\\LogicalDisk(_Total)\\Disk Reads/sec'
            '\\LogicalDisk(_Total)\\Disk Writes/sec'
            '\\LogicalDisk(_Total)\\% Free Space'
            '\\Network Interface(*)\\Bytes Total/sec'
          ]
          name: 'VMPerfCounters'
        }
      ]
      windowsEventLogs: [
        {
          streams: [
            'Microsoft-WindowsEvent'
          ]
          xPathQueries: [
            'Application!*[System[(Level=1 or Level=2 or Level=3)]]'
            'System!*[System[(Level=1 or Level=2 or Level=3)]]'
          ]
          name: 'VMEventLogs'
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'VMMonitoringDestination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Perf'
          'Microsoft-WindowsEvent'
        ]
        destinations: [
          'VMMonitoringDestination'
        ]
      }
    ]
  }
}

// ==============================================================================
// Scheduled Query Rules for Advanced Monitoring
// ==============================================================================

resource vmAvailabilityQueryRule 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'vm-availability-query-rule'
  location: location
  tags: tags
  properties: {
    description: 'Monitor VM availability across all customer tenants'
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    severity: 1
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: '''
            Heartbeat
            | where TimeGenerated > ago(5m)
            | summarize LastHeartbeat = max(TimeGenerated) by Computer
            | where LastHeartbeat < ago(2m)
            | count
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
        actionGroup.id
      ]
      customProperties: {
        alertType: 'VMAvailability'
        severity: 'High'
      }
    }
  }
}

resource vmPerformanceQueryRule 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'vm-performance-query-rule'
  location: location
  tags: tags
  properties: {
    description: 'Monitor VM performance across all customer tenants'
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    severity: 2
    windowSize: 'PT10M'
    criteria: {
      allOf: [
        {
          query: '''
            Perf
            | where TimeGenerated > ago(10m)
            | where CounterName == "% Processor Time"
            | where InstanceName == "_Total"
            | summarize AvgCPU = avg(CounterValue) by Computer
            | where AvgCPU > 80
            | count
          '''
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
    actions: {
      actionGroups: [
        actionGroup.id
      ]
      customProperties: {
        alertType: 'VMPerformance'
        severity: 'Medium'
      }
    }
  }
}

// ==============================================================================
// Outputs
// ==============================================================================

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The resource ID of the action group')
output actionGroupId string = actionGroup.id

@description('The resource ID of the data collection rule')
output dataCollectionRuleId string = dataCollectionRule.id

@description('The Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The Log Analytics workspace customer ID')
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId