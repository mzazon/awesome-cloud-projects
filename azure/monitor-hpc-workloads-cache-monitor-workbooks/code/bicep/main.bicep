@description('Main Bicep template for HPC Cache and Azure Monitor Workbooks monitoring solution')

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Prefix for resource naming')
@minLength(3)
@maxLength(10)
param resourcePrefix string

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('HPC Cache size in GB')
@allowed([3072, 6144, 12288, 24576, 49152])
param hpcCacheSize int = 3072

@description('HPC Cache SKU')
@allowed(['Standard_2G', 'Standard_4G', 'Standard_8G'])
param hpcCacheSku string = 'Standard_2G'

@description('Batch account storage account type')
@allowed(['Standard_LRS', 'Premium_LRS'])
param batchStorageAccountType string = 'Standard_LRS'

@description('Batch pool VM size')
param batchVmSize string = 'Standard_HC44rs'

@description('Initial number of Batch pool nodes')
@minValue(0)
@maxValue(100)
param batchPoolNodeCount int = 2

@description('Log Analytics workspace retention days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 90

@description('Enable diagnostic settings')
param enableDiagnostics bool = true

@description('Email address for alert notifications')
param alertEmailAddress string

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'HPC-Monitoring'
  Recipe: 'monitoring-high-performance-computing-workloads'
}

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var storageAccountName = '${resourcePrefix}hpcstorage${uniqueSuffix}'
var batchAccountName = '${resourcePrefix}batch${uniqueSuffix}'
var hpcCacheName = '${resourcePrefix}-hpc-cache-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-hpc-workspace-${uniqueSuffix}'
var virtualNetworkName = '${resourcePrefix}-hpc-vnet-${uniqueSuffix}'
var subnetName = 'hpc-subnet'
var actionGroupName = '${resourcePrefix}-hpc-alerts-${uniqueSuffix}'
var workbookName = '${resourcePrefix}-hpc-monitoring-workbook-${uniqueSuffix}'

// Virtual Network for HPC Cache
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          delegations: [
            {
              name: 'Microsoft.StorageCache/caches'
              properties: {
                serviceName: 'Microsoft.StorageCache/caches'
              }
            }
          ]
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
        }
      }
    ]
  }
}

// Storage Account for HPC workloads
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: batchStorageAccountType
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

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

// HPC Cache
resource hpcCache 'Microsoft.StorageCache/caches@2023-05-01' = {
  name: hpcCacheName
  location: location
  tags: tags
  sku: {
    name: hpcCacheSku
  }
  properties: {
    cacheSizeGB: hpcCacheSize
    subnet: '${virtualNetwork.id}/subnets/${subnetName}'
    upgradeSettings: {
      upgradeScheduleEnabled: true
      scheduledTime: '22:00'
    }
    securitySettings: {
      accessPolicies: [
        {
          name: 'default'
          accessRules: [
            {
              scope: 'default'
              access: 'rw'
              suid: false
              submountAccess: true
              rootSquash: false
            }
          ]
        }
      ]
    }
  }
}

// Batch Account
resource batchAccount 'Microsoft.Batch/batchAccounts@2023-11-01' = {
  name: batchAccountName
  location: location
  tags: tags
  properties: {
    autoStorage: {
      storageAccountId: storageAccount.id
    }
    poolAllocationMode: 'BatchService'
    publicNetworkAccess: 'Enabled'
    networkProfile: {
      nodeManagementAccess: {
        defaultAction: 'Allow'
      }
    }
    encryption: {
      keySource: 'Microsoft.Batch'
    }
  }
}

// Batch Pool
resource batchPool 'Microsoft.Batch/batchAccounts/pools@2023-11-01' = {
  name: 'hpc-pool'
  parent: batchAccount
  properties: {
    vmSize: batchVmSize
    deploymentConfiguration: {
      virtualMachineConfiguration: {
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-focal'
          sku: '20_04-lts-gen2'
          version: 'latest'
        }
        nodeAgentSkuId: 'batch.node.ubuntu 20.04'
      }
    }
    scaleSettings: {
      fixedScale: {
        targetDedicatedNodes: batchPoolNodeCount
        resizeTimeout: 'PT15M'
      }
    }
    networkConfiguration: {
      subnetId: '${virtualNetwork.id}/subnets/${subnetName}'
    }
    interNodeCommunication: 'Enabled'
    taskSlotsPerNode: 1
    taskSchedulingPolicy: {
      nodeFillType: 'Spread'
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
  }
}

// Metric Alert for Cache Hit Rate
resource cacheHitRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'low-cache-hit-rate'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when cache hit rate drops below 80%'
    severity: 2
    enabled: true
    scopes: [
      hpcCache.id
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
resource computeUtilizationAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'high-compute-utilization'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when running nodes exceed 90% of target'
    severity: 2
    enabled: true
    scopes: [
      batchAccount.id
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
          threshold: (batchPoolNodeCount * 90) / 100
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

// Diagnostic Settings for HPC Cache
resource hpcCacheDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'hpc-cache-diagnostics'
  scope: hpcCache
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ServiceLog'
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

// Diagnostic Settings for Batch Account
resource batchAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'batch-diagnostics'
  scope: batchAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ServiceLog'
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

// Diagnostic Settings for Storage Account
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'storage-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
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

// Azure Monitor Workbook for HPC Monitoring
resource monitoringWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, workbookName)
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: workbookName
    serializedData: '{"version":"Notebook/1.0","items":[{"type":1,"content":{"json":"## HPC Cache Performance Dashboard\\n\\nThis dashboard provides comprehensive monitoring for Azure HPC Cache, Batch compute clusters, and storage performance metrics."}},{"type":3,"content":{"version":"KqlItem/1.0","query":"AzureMetrics\\n| where ResourceProvider == \\"MICROSOFT.STORAGECACHE\\"\\n| where MetricName == \\"CacheHitPercent\\"\\n| summarize avg(Average) by bin(TimeGenerated, 5m)\\n| render timechart","size":0,"title":"Cache Hit Rate Over Time","timeContext":{"durationMs":3600000}}},{"type":3,"content":{"version":"KqlItem/1.0","query":"AzureMetrics\\n| where ResourceProvider == \\"MICROSOFT.BATCH\\"\\n| where MetricName == \\"RunningNodeCount\\"\\n| summarize avg(Average) by bin(TimeGenerated, 5m)\\n| render timechart","size":0,"title":"Active Compute Nodes","timeContext":{"durationMs":3600000}}},{"type":3,"content":{"version":"KqlItem/1.0","query":"AzureMetrics\\n| where ResourceProvider == \\"MICROSOFT.STORAGE\\"\\n| where MetricName == \\"Transactions\\"\\n| summarize sum(Total) by bin(TimeGenerated, 5m)\\n| render timechart","size":0,"title":"Storage Transactions","timeContext":{"durationMs":3600000}}},{"type":3,"content":{"version":"KqlItem/1.0","query":"AzureMetrics\\n| where ResourceProvider == \\"MICROSOFT.STORAGECACHE\\"\\n| where MetricName == \\"ReadThroughputBytesPerSecond\\"\\n| summarize avg(Average) by bin(TimeGenerated, 5m)\\n| render timechart","size":0,"title":"Cache Read Throughput","timeContext":{"durationMs":3600000}}},{"type":3,"content":{"version":"KqlItem/1.0","query":"AzureMetrics\\n| where ResourceProvider == \\"MICROSOFT.BATCH\\"\\n| where MetricName == \\"CompletedTaskCount\\"\\n| summarize sum(Total) by bin(TimeGenerated, 5m)\\n| render timechart","size":0,"title":"Completed Tasks","timeContext":{"durationMs":3600000}}}],"styleSettings":{"showBorder":true},"links":[],"fallbackResourceIds":[],"fromTemplateId":"Community-Workbooks/Azure Monitor - Getting Started/Getting Started"}'
    version: '1.0'
    sourceId: logAnalyticsWorkspace.id
    category: 'HPC'
    description: 'Comprehensive monitoring dashboard for HPC Cache, Batch compute clusters, and storage performance metrics'
  }
}

// Outputs
@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('HPC Cache Name')
output hpcCacheName string = hpcCache.name

@description('HPC Cache ID')
output hpcCacheId string = hpcCache.id

@description('Batch Account Name')
output batchAccountName string = batchAccount.name

@description('Batch Account Endpoint')
output batchAccountEndpoint string = batchAccount.properties.accountEndpoint

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('Storage Account Primary Key')
@secure()
output storageAccountKey string = storageAccount.listKeys().keys[0].value

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Virtual Network Name')
output virtualNetworkName string = virtualNetwork.name

@description('Subnet ID')
output subnetId string = '${virtualNetwork.id}/subnets/${subnetName}'

@description('Action Group Name')
output actionGroupName string = actionGroup.name

@description('Workbook Name')
output workbookName string = monitoringWorkbook.properties.displayName

@description('Workbook ID')
output workbookId string = monitoringWorkbook.id

@description('Resource Tags')
output resourceTags object = tags

@description('Deployment Summary')
output deploymentSummary object = {
  hpcCache: {
    name: hpcCache.name
    size: hpcCacheSize
    sku: hpcCacheSku
    status: 'Deployed'
  }
  batchAccount: {
    name: batchAccount.name
    poolName: 'hpc-pool'
    vmSize: batchVmSize
    nodeCount: batchPoolNodeCount
    status: 'Deployed'
  }
  monitoring: {
    workspaceName: logAnalyticsWorkspace.name
    workbookName: monitoringWorkbook.properties.displayName
    diagnosticsEnabled: enableDiagnostics
    alertsConfigured: true
    status: 'Deployed'
  }
}