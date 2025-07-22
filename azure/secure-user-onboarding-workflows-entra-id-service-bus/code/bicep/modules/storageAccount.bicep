// ==============================================================================
// Storage Account Module for Logic Apps State Management
// ==============================================================================
// This module creates an Azure Storage Account optimized for Logic Apps
// with security features and monitoring capabilities
// ==============================================================================

@description('Storage Account name')
param storageAccountName string

@description('Location for Storage Account')
param location string

@description('Storage Account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Premium_LRS'])
param skuName string = 'Standard_LRS'

@description('Storage Account kind')
@allowed(['Storage', 'StorageV2', 'BlobStorage', 'FileStorage', 'BlockBlobStorage'])
param kind string = 'StorageV2'

@description('Access tier for the storage account')
@allowed(['Hot', 'Cool'])
param accessTier string = 'Hot'

@description('Minimum TLS version')
@allowed(['TLS1_0', 'TLS1_1', 'TLS1_2'])
param minimumTlsVersion string = 'TLS1_2'

@description('Enable HTTPS only')
param supportsHttpsTrafficOnly bool = true

@description('Enable hierarchical namespace')
param isHnsEnabled bool = false

@description('Enable blob public access')
param allowBlobPublicAccess bool = false

@description('Enable shared key access')
param allowSharedKeyAccess bool = true

@description('Tags to apply to the Storage Account')
param tags object = {}

@description('Enable diagnostic logs')
param enableDiagnostics bool = true

@description('Log Analytics workspace ID for diagnostics')
param logAnalyticsWorkspaceId string = ''

@description('Network access rules')
param networkAcls object = {
  defaultAction: 'Allow'
  bypass: 'AzureServices'
}

@description('Enable delete protection')
param enableDeleteProtection bool = true

@description('Delete protection retention days')
@minValue(1)
@maxValue(365)
param deleteRetentionDays int = 7

// ==============================================================================
// VARIABLES
// ==============================================================================

var storageAccountProperties = {
  minimumTlsVersion: minimumTlsVersion
  allowBlobPublicAccess: allowBlobPublicAccess
  allowSharedKeyAccess: allowSharedKeyAccess
  supportsHttpsTrafficOnly: supportsHttpsTrafficOnly
  accessTier: accessTier
  isHnsEnabled: isHnsEnabled
  networkAcls: networkAcls
  encryption: {
    services: {
      file: {
        keyType: 'Account'
        enabled: true
      }
      blob: {
        keyType: 'Account'
        enabled: true
      }
    }
    keySource: 'Microsoft.Storage'
  }
}

// ==============================================================================
// RESOURCES
// ==============================================================================

// Create Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: kind
  properties: storageAccountProperties
}

// Create blob service with delete protection
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: enableDeleteProtection
      days: deleteRetentionDays
    }
    containerDeleteRetentionPolicy: {
      enabled: enableDeleteProtection
      days: deleteRetentionDays
    }
    changeFeed: {
      enabled: true
      retentionInDays: deleteRetentionDays
    }
    versioning: {
      enabled: true
    }
    isVersioningEnabled: true
    cors: {
      corsRules: []
    }
  }
}

// Create file service
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: enableDeleteProtection
      days: deleteRetentionDays
    }
    cors: {
      corsRules: []
    }
  }
}

// Create queue service
resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

// Create table service
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

// Diagnostic settings for Storage Account
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && !empty(logAnalyticsWorkspaceId)) {
  name: 'storage-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Diagnostic settings for Blob Service
resource blobServiceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && !empty(logAnalyticsWorkspaceId)) {
  name: 'blob-diagnostics'
  scope: blobService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'StorageRead'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'StorageWrite'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'StorageDelete'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('Storage Account resource ID')
output storageAccountResourceId string = storageAccount.id

@description('Storage Account resource reference')
output storageAccountResource resource = storageAccount

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Storage Account primary endpoint')
output primaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Storage Account connection string')
@secure()
output connectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'

@description('Storage Account primary key')
@secure()
output primaryKey string = storageAccount.listKeys().keys[0].value

@description('Storage Account secondary key')
@secure()
output secondaryKey string = storageAccount.listKeys().keys[1].value

@description('Storage Account SKU')
output skuName string = storageAccount.sku.name

@description('Storage Account kind')
output kind string = storageAccount.kind

@description('Storage Account access tier')
output accessTier string = storageAccount.properties.accessTier

@description('Storage Account HTTPS only status')
output httpsOnly bool = storageAccount.properties.supportsHttpsTrafficOnly

@description('Storage Account minimum TLS version')
output minimumTlsVersion string = storageAccount.properties.minimumTlsVersion