// Multi-Tenant SaaS Performance and Cost Analytics Infrastructure
// This template deploys Application Insights, Data Explorer, and supporting resources
// for comprehensive multi-tenant SaaS monitoring and cost attribution

// Template metadata
metadata = {
  description: 'Deploys multi-tenant SaaS performance and cost analytics infrastructure with Application Insights and Data Explorer'
  author: 'Azure Recipes'
  version: '1.0.0'
}

// Target scope and required providers
targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (e.g., dev, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'prod'

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 90

@description('Log Analytics workspace SKU')
@allowed(['Free', 'Standard', 'Premium', 'PerNode', 'PerGB2018', 'Standalone'])
param logAnalyticsSku string = 'PerGB2018'

@description('Application Insights sampling percentage')
@minValue(0)
@maxValue(100)
param appInsightsSamplingPercentage int = 100

@description('Data Explorer cluster SKU name')
@allowed(['Standard_D11_v2', 'Standard_D12_v2', 'Standard_D13_v2', 'Standard_D14_v2'])
param dataExplorerSkuName string = 'Standard_D11_v2'

@description('Data Explorer cluster capacity (number of instances)')
@minValue(1)
@maxValue(10)
param dataExplorerCapacity int = 2

@description('Data Explorer database hot cache period in ISO 8601 format')
param hotCachePeriod string = 'P30D'

@description('Data Explorer database soft delete period in ISO 8601 format')
param softDeletePeriod string = 'P365D'

@description('Monthly budget amount for cost management')
@minValue(50)
@maxValue(10000)
param budgetAmount int = 200

@description('Budget alert email addresses (comma-separated)')
param alertEmailAddresses string = 'admin@company.com'

@description('Resource tags to apply to all resources')
param resourceTags object = {
  purpose: 'saas-analytics'
  environment: environment
  solution: 'multi-tenant-monitoring'
  'cost-center': 'engineering'
}

// Variables for resource naming
var logAnalyticsWorkspaceName = 'la-saas-analytics-${resourceSuffix}'
var appInsightsName = 'ai-saas-analytics-${resourceSuffix}'
var dataExplorerClusterName = 'adx-saas-${resourceSuffix}'
var dataExplorerDatabaseName = 'SaaSAnalytics'
var actionGroupName = 'cost-alert-group-${resourceSuffix}'
var budgetName = 'saas-analytics-budget-${resourceSuffix}'

// Log Analytics Workspace for centralized logging
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: logAnalyticsSku
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    workspaceCapping: {
      dailyQuotaGb: -1 // No daily quota limit
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights for application performance monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: union(resourceTags, {
    'tenant-enabled': 'true'
  })
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    SamplingPercentage: appInsightsSamplingPercentage
    RetentionInDays: logAnalyticsRetentionDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    DisableIpMasking: false
  }
}

// Data Explorer Cluster for advanced analytics
resource dataExplorerCluster 'Microsoft.Kusto/clusters@2023-08-15' = {
  name: dataExplorerClusterName
  location: location
  tags: union(resourceTags, {
    analytics: 'enabled'
  })
  sku: {
    name: dataExplorerSkuName
    tier: 'Standard'
    capacity: dataExplorerCapacity
  }
  properties: {
    enableDiskEncryption: true
    enableStreamingIngest: true
    enablePurge: true
    enableDoubleEncryption: false
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
    trustedExternalTenants: []
    optimizedAutoscale: {
      version: 1
      isEnabled: false
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Data Explorer Database within the cluster
resource dataExplorerDatabase 'Microsoft.Kusto/clusters/databases@2023-08-15' = {
  parent: dataExplorerCluster
  name: dataExplorerDatabaseName
  location: location
  kind: 'ReadWrite'
  properties: {
    hotCachePeriod: hotCachePeriod
    softDeletePeriod: softDeletePeriod
  }
}

// Data connection from Log Analytics to Data Explorer
resource dataConnection 'Microsoft.Kusto/clusters/databases/dataConnections@2023-08-15' = {
  parent: dataExplorerDatabase
  name: 'AppInsightsConnection'
  location: location
  kind: 'LogAnalytics'
  properties: {
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.id
    tableName: 'TenantMetrics'
    mappingRuleName: 'TenantMetricsMapping'
  }
}

// Action Group for cost alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: resourceTags
  properties: {
    groupShortName: 'CostAlert'
    enabled: true
    emailReceivers: [for email in split(alertEmailAddresses, ','): {
      name: 'admin-${uniqueString(email)}'
      emailAddress: trim(email)
      useCommonAlertSchema: true
    }]
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

// Budget for cost management
resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: budgetName
  properties: {
    timePeriod: {
      startDate: '${utcNow('yyyy-MM')}-01T00:00:00Z'
      endDate: '2030-12-31T23:59:59Z'
    }
    timeGrain: 'Monthly'
    amount: budgetAmount
    category: 'Cost'
    notifications: {
      Actual_GreaterThan_80_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: split(alertEmailAddresses, ',')
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Actual'
      }
      Forecasted_GreaterThan_100_Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: split(alertEmailAddresses, ',')
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Forecasted'
      }
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
  }
}

// Custom table creation script for Data Explorer
resource tenantMetricsTable 'Microsoft.Kusto/clusters/databases/scripts@2023-08-15' = {
  parent: dataExplorerDatabase
  name: 'CreateTenantMetricsTable'
  properties: {
    scriptContent: '''
      .create table TenantMetrics (
          Timestamp: datetime,
          TenantId: string,
          MetricName: string,
          MetricValue: real,
          ResourceId: string,
          Location: string,
          CostCenter: string
      )
      
      .create table TenantMetrics ingestion json mapping "TenantMetricsMapping" '[
        {"column":"Timestamp","path":"$.timestamp","datatype":"datetime"},
        {"column":"TenantId","path":"$.customDimensions.TenantId","datatype":"string"},
        {"column":"MetricName","path":"$.name","datatype":"string"},
        {"column":"MetricValue","path":"$.value","datatype":"real"},
        {"column":"ResourceId","path":"$.cloud_RoleInstance","datatype":"string"},
        {"column":"Location","path":"$.client_City","datatype":"string"},
        {"column":"CostCenter","path":"$.customDimensions.CostCenter","datatype":"string"}
      ]'
    '''
    forceUpdateTag: '1.0'
    continueOnErrors: false
  }
  dependsOn: [
    dataConnection
  ]
}

// Cost analysis function for Data Explorer
resource costAnalysisFunction 'Microsoft.Kusto/clusters/databases/scripts@2023-08-15' = {
  parent: dataExplorerDatabase
  name: 'CreateCostAnalysisFunction'
  properties: {
    scriptContent: '''
      .create function TenantCostAnalysis() {
          TenantMetrics
          | where Timestamp > ago(30d)
          | summarize TotalCost = sum(MetricValue) by TenantId, bin(Timestamp, 1d)
          | order by Timestamp desc
      }
      
      .create function TenantPerformanceAnalysis() {
          TenantMetrics
          | where Timestamp > ago(24h) and MetricName in ("RequestCount", "Duration", "FailureRate")
          | summarize 
              RequestCount = sumif(MetricValue, MetricName == "RequestCount"),
              AvgDuration = avgif(MetricValue, MetricName == "Duration"),
              FailureRate = avgif(MetricValue, MetricName == "FailureRate")
          by TenantId, bin(Timestamp, 1h)
          | order by Timestamp desc
      }
    '''
    forceUpdateTag: '1.0'
    continueOnErrors: false
  }
  dependsOn: [
    tenantMetricsTable
  ]
}

// Role assignment for Data Explorer to access Log Analytics
resource dataExplorerLogAnalyticsReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, dataExplorerCluster.id, 'LogAnalyticsReader')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893') // Log Analytics Reader
    principalId: dataExplorerCluster.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs for integration and verification
@description('Resource Group name where all resources are deployed')
output resourceGroupName string = resourceGroup().name

@description('Log Analytics Workspace ID for Application Insights integration')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Log Analytics Workspace resource ID')
output logAnalyticsWorkspaceResourceId string = logAnalyticsWorkspace.id

@description('Application Insights Instrumentation Key for SDK integration')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights Connection String for modern SDK integration')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Application Insights App ID for API access')
output applicationInsightsAppId string = applicationInsights.properties.AppId

@description('Data Explorer cluster name for query access')
output dataExplorerClusterName string = dataExplorerCluster.name

@description('Data Explorer cluster URI for client connections')
output dataExplorerClusterUri string = dataExplorerCluster.properties.uri

@description('Data Explorer database name for query context')
output dataExplorerDatabaseName string = dataExplorerDatabase.name

@description('Data Explorer cluster data ingestion URI')
output dataExplorerDataIngestionUri string = dataExplorerCluster.properties.dataIngestionUri

@description('Action Group resource ID for alert configuration')
output actionGroupResourceId string = actionGroup.id

@description('Budget name for cost monitoring')
output budgetName string = budget.name

@description('Sample KQL query for tenant performance analysis')
output samplePerformanceQuery string = '''
requests
| where timestamp > ago(24h)
| extend TenantId = tostring(customDimensions.TenantId)
| summarize 
    RequestCount = count(),
    AvgDuration = avg(duration),
    P95Duration = percentile(duration, 95),
    FailureRate = countif(success == false) * 100.0 / count()
by TenantId, bin(timestamp, 1h)
| order by timestamp desc
'''

@description('Sample KQL query for tenant cost correlation')
output sampleCostQuery string = '''
union 
(requests | extend MetricType = "Performance"),
(dependencies | extend MetricType = "Dependencies")
| where timestamp > ago(7d)
| extend TenantId = tostring(customDimensions.TenantId)
| summarize 
    TotalOperations = count(),
    EstimatedCost = count() * 0.001
by TenantId, MetricType, bin(timestamp, 1d)
| order by TotalOperations desc
'''

@description('Deployment summary with key information')
output deploymentSummary object = {
  applicationInsights: {
    name: applicationInsights.name
    instrumentationKey: applicationInsights.properties.InstrumentationKey
    connectionString: applicationInsights.properties.ConnectionString
  }
  dataExplorer: {
    clusterName: dataExplorerCluster.name
    databaseName: dataExplorerDatabase.name
    clusterUri: dataExplorerCluster.properties.uri
  }
  logAnalytics: {
    workspaceName: logAnalyticsWorkspace.name
    workspaceId: logAnalyticsWorkspace.properties.customerId
  }
  costManagement: {
    budgetName: budget.name
    budgetAmount: budgetAmount
    actionGroupName: actionGroup.name
  }
}