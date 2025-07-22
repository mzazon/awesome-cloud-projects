@description('Modular Bicep template for HPC Cache and Azure Monitor Workbooks monitoring solution')

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

// Deploy Networking Module
module networking 'modules/networking.bicep' = {
  name: 'networking-deployment'
  params: {
    location: location
    virtualNetworkName: virtualNetworkName
    subnetName: subnetName
    tags: tags
  }
}

// Deploy Storage Module
module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    location: location
    storageAccountName: storageAccountName
    storageAccountSku: batchStorageAccountType
    accessTier: 'Hot'
    tags: tags
  }
}

// Deploy HPC Cache Module
module hpcCache 'modules/hpc-cache.bicep' = {
  name: 'hpc-cache-deployment'
  params: {
    location: location
    hpcCacheName: hpcCacheName
    hpcCacheSize: hpcCacheSize
    hpcCacheSku: hpcCacheSku
    subnetId: networking.outputs.subnetId
    tags: tags
  }
  dependsOn: [
    networking
  ]
}

// Deploy Batch Module
module batch 'modules/batch.bicep' = {
  name: 'batch-deployment'
  params: {
    location: location
    batchAccountName: batchAccountName
    storageAccountId: storage.outputs.storageAccountId
    batchPoolName: 'hpc-pool'
    batchVmSize: batchVmSize
    batchPoolNodeCount: batchPoolNodeCount
    subnetId: networking.outputs.subnetId
    tags: tags
  }
  dependsOn: [
    storage
    networking
  ]
}

// Deploy Monitoring Module
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-deployment'
  params: {
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    logAnalyticsRetentionDays: logAnalyticsRetentionDays
    actionGroupName: actionGroupName
    alertEmailAddress: alertEmailAddress
    workbookName: workbookName
    tags: tags
    monitoredResources: {
      hpcCache: {
        id: hpcCache.outputs.hpcCacheId
      }
      batchAccount: {
        id: batch.outputs.batchAccountId
        nodeCount: batchPoolNodeCount
      }
      storageAccount: {
        id: storage.outputs.storageAccountId
      }
    }
    enableDiagnostics: enableDiagnostics
  }
  dependsOn: [
    hpcCache
    batch
    storage
  ]
}

// Diagnostic Settings for HPC Cache
resource hpcCacheDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'hpc-cache-diagnostics'
  scope: resourceId('Microsoft.StorageCache/caches', hpcCacheName)
  properties: {
    workspaceId: monitoring.outputs.logAnalyticsWorkspaceId
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
  dependsOn: [
    hpcCache
    monitoring
  ]
}

// Diagnostic Settings for Batch Account
resource batchAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'batch-diagnostics'
  scope: resourceId('Microsoft.Batch/batchAccounts', batchAccountName)
  properties: {
    workspaceId: monitoring.outputs.logAnalyticsWorkspaceId
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
  dependsOn: [
    batch
    monitoring
  ]
}

// Diagnostic Settings for Storage Account
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'storage-diagnostics'
  scope: resourceId('Microsoft.Storage/storageAccounts', storageAccountName)
  properties: {
    workspaceId: monitoring.outputs.logAnalyticsWorkspaceId
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
  dependsOn: [
    storage
    monitoring
  ]
}

// Outputs
@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Networking Outputs')
output networking object = {
  virtualNetworkName: networking.outputs.virtualNetworkName
  virtualNetworkId: networking.outputs.virtualNetworkId
  subnetId: networking.outputs.subnetId
  subnetName: networking.outputs.subnetName
}

@description('Storage Outputs')
output storage object = {
  storageAccountName: storage.outputs.storageAccountName
  storageAccountId: storage.outputs.storageAccountId
  blobServiceEndpoint: storage.outputs.blobServiceEndpoint
  fileServiceEndpoint: storage.outputs.fileServiceEndpoint
}

@description('HPC Cache Outputs')
output hpcCache object = {
  hpcCacheName: hpcCache.outputs.hpcCacheName
  hpcCacheId: hpcCache.outputs.hpcCacheId
  hpcCacheMountAddresses: hpcCache.outputs.hpcCacheMountAddresses
  hpcCacheHealthState: hpcCache.outputs.hpcCacheHealthState
  hpcCacheSize: hpcCache.outputs.hpcCacheSize
  hpcCacheSku: hpcCache.outputs.hpcCacheSku
}

@description('Batch Outputs')
output batch object = {
  batchAccountName: batch.outputs.batchAccountName
  batchAccountId: batch.outputs.batchAccountId
  batchAccountEndpoint: batch.outputs.batchAccountEndpoint
  batchPoolName: batch.outputs.batchPoolName
  batchPoolVmSize: batch.outputs.batchPoolVmSize
  batchPoolNodeCount: batch.outputs.batchPoolNodeCount
  batchPoolState: batch.outputs.batchPoolState
}

@description('Monitoring Outputs')
output monitoring object = {
  logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
  logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  actionGroupName: monitoring.outputs.actionGroupName
  actionGroupId: monitoring.outputs.actionGroupId
  workbookName: monitoring.outputs.workbookName
  workbookId: monitoring.outputs.workbookId
  alertRulesCreated: monitoring.outputs.alertRulesCreated
}

@description('Deployment Summary')
output deploymentSummary object = {
  resourceGroupName: resourceGroup().name
  location: location
  environment: environment
  resourcePrefix: resourcePrefix
  componentsDeployed: {
    networking: {
      virtualNetwork: networking.outputs.virtualNetworkName
      subnet: networking.outputs.subnetName
      status: 'Deployed'
    }
    storage: {
      storageAccount: storage.outputs.storageAccountName
      status: 'Deployed'
    }
    hpcCache: {
      name: hpcCache.outputs.hpcCacheName
      size: hpcCache.outputs.hpcCacheSize
      sku: hpcCache.outputs.hpcCacheSku
      status: 'Deployed'
    }
    batch: {
      account: batch.outputs.batchAccountName
      pool: batch.outputs.batchPoolName
      vmSize: batch.outputs.batchPoolVmSize
      nodeCount: batch.outputs.batchPoolNodeCount
      status: 'Deployed'
    }
    monitoring: {
      workspace: monitoring.outputs.logAnalyticsWorkspaceName
      workbook: monitoring.outputs.workbookName
      actionGroup: monitoring.outputs.actionGroupName
      diagnosticsEnabled: enableDiagnostics
      status: 'Deployed'
    }
  }
  tags: tags
}