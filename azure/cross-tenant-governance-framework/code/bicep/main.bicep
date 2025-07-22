// ==============================================================================
// Azure Lighthouse and Azure Automanage Cross-Tenant Governance
// ==============================================================================
// This Bicep template deploys the infrastructure needed for cross-tenant
// resource governance using Azure Lighthouse and Azure Automanage.
// ==============================================================================

@description('The tenant ID of the MSP (Managed Service Provider)')
param mspTenantId string

@description('The name of the MSP offer for Lighthouse delegation')
param mspOfferName string = 'Cross-Tenant Resource Governance'

@description('Description of the MSP offer')
param mspOfferDescription string = 'Managed services for automated VM configuration, patching, and compliance monitoring'

@description('Array of authorization objects for Lighthouse delegation')
param authorizations array

@description('Location for all resources')
param location string = resourceGroup().location

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

@description('Name of the Automanage configuration profile')
param automanageProfileName string

@description('Name of the action group for alerting')
param actionGroupName string

@description('Email address for alert notifications')
param alertEmailAddress string

@description('Customer tenant ID (for cross-tenant scenarios)')
param customerTenantId string = ''

@description('Customer subscription ID (for cross-tenant scenarios)')
param customerSubscriptionId string = ''

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'lighthouse-governance'
  environment: 'production'
  managedBy: 'msp'
}

// ==============================================================================
// Variables
// ==============================================================================

var mspRegistrationName = guid(mspOfferName)
var mspAssignmentName = guid('${mspOfferName}-assignment')
var alertRuleName = 'vm-availability-cross-tenant'
var workbookName = 'lighthouse-cross-tenant-monitoring'

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
// Automanage Configuration Profile
// ==============================================================================

resource automanageProfile 'Microsoft.Automanage/configurationProfiles@2022-05-04' = {
  name: automanageProfileName
  location: location
  tags: tags
  properties: {
    configuration: {
      'Antimalware/Enable': 'true'
      'Antimalware/EnableRealTimeProtection': 'true'
      'Antimalware/RunScheduledScan': 'true'
      'AzureSecurityCenter/Enable': 'true'
      'Backup/Enable': 'true'
      'Backup/PolicyName': 'DefaultPolicy'
      'Backup/TimeZone': 'UTC'
      'BootDiagnostics/Enable': 'true'
      'ChangeTrackingAndInventory/Enable': 'true'
      'GuestConfiguration/Enable': 'true'
      'LogAnalytics/Enable': 'true'
      'LogAnalytics/WorkspaceId': logAnalyticsWorkspace.id
      'UpdateManagement/Enable': 'true'
      'UpdateManagement/ExcludeKbsRequiringReboot': 'false'
      'VMInsights/Enable': 'true'
    }
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
// Lighthouse Registration Definition
// ==============================================================================

resource lighthouseRegistrationDefinition 'Microsoft.ManagedServices/registrationDefinitions@2022-10-01' = {
  name: mspRegistrationName
  properties: {
    registrationDefinitionName: mspOfferName
    description: mspOfferDescription
    managedByTenantId: mspTenantId
    authorizations: authorizations
    eligibleAuthorizations: []
  }
}

// ==============================================================================
// Lighthouse Registration Assignment
// ==============================================================================

resource lighthouseRegistrationAssignment 'Microsoft.ManagedServices/registrationAssignments@2022-10-01' = {
  name: mspAssignmentName
  properties: {
    registrationDefinitionId: lighthouseRegistrationDefinition.id
  }
}

// ==============================================================================
// Azure Workbook for Cross-Tenant Monitoring
// ==============================================================================

resource monitoringWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(workbookName)
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: workbookName
    serializedData: loadTextContent('workbook-template.json')
    category: 'workbook'
    sourceId: logAnalyticsWorkspace.id
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
// Alert Rules for Cross-Tenant Monitoring
// ==============================================================================

resource cpuAlertRule 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${alertRuleName}-cpu'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when CPU usage is high across customer tenants'
    severity: 2
    enabled: true
    scopes: [
      logAnalyticsWorkspace.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 80
          name: 'HighCPUUsage'
          metricNamespace: 'Microsoft.OperationalInsights/workspaces'
          metricName: 'Average_% Processor Time'
          dimensions: []
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

resource memoryAlertRule 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${alertRuleName}-memory'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when memory usage is high across customer tenants'
    severity: 2
    enabled: true
    scopes: [
      logAnalyticsWorkspace.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 1000000000 // 1GB in bytes
          name: 'LowAvailableMemory'
          metricNamespace: 'Microsoft.OperationalInsights/workspaces'
          metricName: 'Average_Available MBytes'
          dimensions: []
          operator: 'LessThan'
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
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

// ==============================================================================
// Outputs
// ==============================================================================

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The resource ID of the Automanage configuration profile')
output automanageProfileId string = automanageProfile.id

@description('The resource ID of the Lighthouse registration definition')
output lighthouseRegistrationDefinitionId string = lighthouseRegistrationDefinition.id

@description('The resource ID of the Lighthouse registration assignment')
output lighthouseRegistrationAssignmentId string = lighthouseRegistrationAssignment.id

@description('The resource ID of the action group')
output actionGroupId string = actionGroup.id

@description('The resource ID of the monitoring workbook')
output monitoringWorkbookId string = monitoringWorkbook.id

@description('The resource ID of the data collection rule')
output dataCollectionRuleId string = dataCollectionRule.id

@description('The MSP registration name for reference')
output mspRegistrationName string = mspRegistrationName

@description('The MSP assignment name for reference')
output mspAssignmentName string = mspAssignmentName

@description('The Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The Automanage profile name')
output automanageProfileName string = automanageProfile.name