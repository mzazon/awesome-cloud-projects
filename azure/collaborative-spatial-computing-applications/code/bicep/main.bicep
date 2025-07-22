// ============================================================================
// Azure Spatial Computing Infrastructure Template
// Deploys Azure Remote Rendering, Azure Spatial Anchors, and supporting services
// for mixed reality and spatial computing applications
// ============================================================================

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Application name for resource naming')
@minLength(3)
@maxLength(10)
param applicationName string = 'spatialapp'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Unique suffix for globally unique resources (leave empty for auto-generation)')
param uniqueSuffix string = ''

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Application: applicationName
  Purpose: 'Spatial Computing'
  'Cost-Center': 'Innovation'
}

@description('Remote Rendering account SKU')
@allowed(['S1'])
param remoteRenderingSkuName string = 'S1'

@description('Spatial Anchors account SKU')
@allowed(['S0', 'S1'])
param spatialAnchorsSkuName string = 'S1'

@description('Storage account SKU for 3D assets')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountSkuName string = 'Standard_LRS'

@description('Enable storage account encryption with customer-managed keys')
param enableCustomerManagedEncryption bool = false

@description('Enable advanced threat protection for storage')
param enableStorageAdvancedThreatProtection bool = true

@description('Storage access tier for 3D model blobs')
@allowed(['Hot', 'Cool'])
param storageAccessTier string = 'Hot'

@description('Enable diagnostic logging')
param enableDiagnosticLogs bool = true

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

// ============================================================================
// Variables
// ============================================================================

// Generate unique suffix if not provided
var generatedSuffix = uniqueSuffix != '' ? uniqueSuffix : substring(uniqueString(resourceGroup().id), 0, 6)
var resourceSuffix = toLower('${applicationName}-${environment}-${generatedSuffix}')

// Resource names following Azure naming conventions
var remoteRenderingAccountName = 'arr-${resourceSuffix}'
var spatialAnchorsAccountName = 'asa-${resourceSuffix}'
var storageAccountName = replace('st3d${resourceSuffix}', '-', '')
var keyVaultName = 'kv-${resourceSuffix}'
var logAnalyticsWorkspaceName = 'log-${resourceSuffix}'
var applicationInsightsName = 'appi-${resourceSuffix}'

// Container names
var modelsContainerName = '3dmodels'
var convertedContainerName = 'converted'
var assetsContainerName = 'assets'

// Security and compliance settings
var storageAccountNetworkRulesBypass = 'AzureServices'
var storageAccountNetworkRuleDefaultAction = environment == 'prod' ? 'Deny' : 'Allow'

// ============================================================================
// Log Analytics Workspace (for diagnostic logs)
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableDiagnosticLogs) {
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
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// Application Insights (for application monitoring)
// ============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableDiagnosticLogs) {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'IbizaAIExtension'
    RetentionInDays: 90
    WorkspaceResourceId: enableDiagnosticLogs ? logAnalyticsWorkspace.id : null
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// Key Vault (for secure credential storage)
// ============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    enabledForDeployment: false
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 7
    tenantId: tenant().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: environment == 'prod' ? 'Deny' : 'Allow'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// ============================================================================
// Storage Account (for 3D models and assets)
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSkuName
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: storageAccountNetworkRulesBypass
      virtualNetworkRules: []
      ipRules: []
      defaultAction: storageAccountNetworkRuleDefaultAction
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      keySource: enableCustomerManagedEncryption ? 'Microsoft.Keyvault' : 'Microsoft.Storage'
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
    }
    accessTier: storageAccessTier
  }
}

// Blob service configuration
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    changeFeed: {
      enabled: false
    }
    restorePolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: [
        {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'HEAD', 'POST', 'PUT']
          maxAgeInSeconds: 86400
          exposedHeaders: ['*']
          allowedHeaders: ['*']
        }
      ]
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: true
      days: 7
    }
  }
}

// Container for original 3D models
resource modelsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: modelsContainerName
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Container for converted 3D models
resource convertedContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: convertedContainerName
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Container for additional assets
resource assetsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: assetsContainerName
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Advanced threat protection for storage account
resource storageAdvancedThreatProtection 'Microsoft.Security/advancedThreatProtectionSettings@2019-01-01' = if (enableStorageAdvancedThreatProtection) {
  name: 'current'
  scope: storageAccount
  properties: {
    isEnabled: enableStorageAdvancedThreatProtection
  }
}

// ============================================================================
// Azure Remote Rendering Account
// ============================================================================

resource remoteRenderingAccount 'Microsoft.MixedReality/remoteRenderingAccounts@2021-01-01' = {
  name: remoteRenderingAccountName
  location: location
  tags: tags
  sku: {
    name: remoteRenderingSkuName
    tier: 'Standard'
  }
  kind: 'RemoteRendering'
  properties: {
    storageAccountName: storageAccount.name
  }
}

// ============================================================================
// Azure Spatial Anchors Account
// ============================================================================

resource spatialAnchorsAccount 'Microsoft.MixedReality/spatialAnchorsAccounts@2021-01-01' = {
  name: spatialAnchorsAccountName
  location: location
  tags: tags
  sku: {
    name: spatialAnchorsSkuName
    tier: spatialAnchorsSkuName == 'S0' ? 'Free' : 'Standard'
  }
  kind: 'SpatialAnchors'
  properties: {}
}

// ============================================================================
// Diagnostic Settings (if enabled)
// ============================================================================

// Remote Rendering diagnostic settings
resource remoteRenderingDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnosticLogs) {
  name: 'diagnostics'
  scope: remoteRenderingAccount
  properties: {
    workspaceId: enableDiagnosticLogs ? logAnalyticsWorkspace.id : null
    logs: [
      {
        categoryGroup: 'allLogs'
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

// Spatial Anchors diagnostic settings
resource spatialAnchorsDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnosticLogs) {
  name: 'diagnostics'
  scope: spatialAnchorsAccount
  properties: {
    workspaceId: enableDiagnosticLogs ? logAnalyticsWorkspace.id : null
    logs: [
      {
        categoryGroup: 'allLogs'
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

// Storage account diagnostic settings
resource storageDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnosticLogs) {
  name: 'diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: enableDiagnosticLogs ? logAnalyticsWorkspace.id : null
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// ============================================================================
// Key Vault Secrets (for secure credential storage)
// ============================================================================

// Store Remote Rendering account key in Key Vault
resource remoteRenderingAccountKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'RemoteRenderingAccountKey'
  properties: {
    value: remoteRenderingAccount.listKeys().primaryKey
    contentType: 'Azure Remote Rendering Account Key'
    attributes: {
      enabled: true
    }
  }
}

// Store Spatial Anchors account key in Key Vault
resource spatialAnchorsAccountKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'SpatialAnchorsAccountKey'
  properties: {
    value: spatialAnchorsAccount.listKeys().primaryKey
    contentType: 'Azure Spatial Anchors Account Key'
    attributes: {
      enabled: true
    }
  }
}

// Store storage account connection string in Key Vault
resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'StorageConnectionString'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    contentType: 'Azure Storage Connection String'
    attributes: {
      enabled: true
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Azure Remote Rendering account name')
output remoteRenderingAccountName string = remoteRenderingAccount.name

@description('Azure Remote Rendering account ID')
output remoteRenderingAccountId string = remoteRenderingAccount.properties.accountId

@description('Azure Remote Rendering account domain')
output remoteRenderingAccountDomain string = remoteRenderingAccount.properties.accountDomain

@description('Azure Spatial Anchors account name')
output spatialAnchorsAccountName string = spatialAnchorsAccount.name

@description('Azure Spatial Anchors account ID')
output spatialAnchorsAccountId string = spatialAnchorsAccount.properties.accountId

@description('Azure Spatial Anchors account domain')
output spatialAnchorsAccountDomain string = spatialAnchorsAccount.properties.accountDomain

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account primary endpoint')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('3D models container name')
output modelsContainerName string = modelsContainer.name

@description('Converted models container name')
output convertedContainerName string = convertedContainer.name

@description('Assets container name')
output assetsContainerName string = assetsContainer.name

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Log Analytics workspace name (if enabled)')
output logAnalyticsWorkspaceName string = enableDiagnosticLogs ? logAnalyticsWorkspace.name : ''

@description('Application Insights name (if enabled)')
output applicationInsightsName string = enableDiagnosticLogs ? applicationInsights.name : ''

@description('Application Insights instrumentation key (if enabled)')
output applicationInsightsInstrumentationKey string = enableDiagnosticLogs ? applicationInsights.properties.InstrumentationKey : ''

@description('Configuration object for Unity applications')
output unityConfiguration object = {
  remoteRendering: {
    accountId: remoteRenderingAccount.properties.accountId
    accountDomain: remoteRenderingAccount.properties.accountDomain
    accountKeySecret: '${keyVault.properties.vaultUri}secrets/RemoteRenderingAccountKey'
  }
  spatialAnchors: {
    accountId: spatialAnchorsAccount.properties.accountId
    accountDomain: spatialAnchorsAccount.properties.accountDomain
    accountKeySecret: '${keyVault.properties.vaultUri}secrets/SpatialAnchorsAccountKey'
  }
  storage: {
    accountName: storageAccount.name
    containerEndpoint: '${storageAccount.properties.primaryEndpoints.blob}${modelsContainerName}'
    connectionStringSecret: '${keyVault.properties.vaultUri}secrets/StorageConnectionString'
  }
  monitoring: {
    applicationInsightsKey: enableDiagnosticLogs ? applicationInsights.properties.InstrumentationKey : ''
    logAnalyticsWorkspaceId: enableDiagnosticLogs ? logAnalyticsWorkspace.properties.customerId : ''
  }
}