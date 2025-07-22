// Azure Data Share and Azure Purview Cross-Tenant Collaboration
// This template deploys infrastructure for secure cross-tenant data sharing with governance

@description('The location/region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
param environment string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('The role of this deployment (provider or consumer)')
@allowed([
  'provider'
  'consumer'
])
param deploymentRole string = 'provider'

@description('Storage account configuration')
param storageConfig object = {
  sku: 'Standard_LRS'
  kind: 'StorageV2'
  accessTier: 'Hot'
  enableHierarchicalNamespace: true
  enableHttpsTrafficOnly: true
  minimumTlsVersion: 'TLS1_2'
  allowBlobPublicAccess: false
  allowSharedKeyAccess: true
  networkAcls: {
    bypass: 'AzureServices'
    defaultAction: 'Allow'
  }
}

@description('Azure Purview configuration')
param purviewConfig object = {
  sku: 'Standard'
  capacity: 4
  managedResourceGroupName: 'rg-purview-managed-${uniqueSuffix}'
}

@description('Data Share configuration')
param dataShareConfig object = {
  description: 'Cross-tenant data collaboration and sharing'
  terms: 'Standard data sharing terms and conditions apply'
}

@description('Container names for the storage account')
param containerNames array = [
  'shared-datasets'
  'processed-data'
  'archived-data'
]

@description('Resource tags to apply to all resources')
param resourceTags object = {
  Environment: environment
  Purpose: 'DataShare-CrossTenant'
  Role: deploymentRole
  ManagedBy: 'Bicep'
}

// Variables for consistent naming
var storageAccountName = 'st${deploymentRole}${uniqueSuffix}'
var dataShareAccountName = 'share-${deploymentRole}-${uniqueSuffix}'
var purviewAccountName = 'purview-${deploymentRole}-${uniqueSuffix}'
var keyVaultName = 'kv-${deploymentRole}-${uniqueSuffix}'

// Storage Account for data hosting
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageConfig.sku
  }
  kind: storageConfig.kind
  properties: {
    accessTier: storageConfig.accessTier
    isHnsEnabled: storageConfig.enableHierarchicalNamespace
    supportsHttpsTrafficOnly: storageConfig.enableHttpsTrafficOnly
    minimumTlsVersion: storageConfig.minimumTlsVersion
    allowBlobPublicAccess: storageConfig.allowBlobPublicAccess
    allowSharedKeyAccess: storageConfig.allowSharedKeyAccess
    networkAcls: storageConfig.networkAcls
    encryption: {
      requireInfrastructureEncryption: true
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
    }
  }
}

// Blob Service configuration
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    versioning: {
      enabled: true
    }
    changeFeed: {
      enabled: true
    }
  }
}

// Storage containers for different data types
resource storageContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for containerName in containerNames: {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Cross-tenant data sharing'
      environment: environment
    }
  }
}]

// Key Vault for secrets management
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    accessPolicies: []
  }
}

// Azure Purview Account for data governance
resource purviewAccount 'Microsoft.Purview/accounts@2021-07-01' = {
  name: purviewAccountName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedResourceGroupName: purviewConfig.managedResourceGroupName
    cloudConnectors: {}
  }
  sku: {
    name: purviewConfig.sku
    capacity: purviewConfig.capacity
  }
}

// Azure Data Share Account
resource dataShareAccount 'Microsoft.DataShare/accounts@2021-08-01' = {
  name: dataShareAccountName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// Data Share for cross-tenant sharing
resource dataShare 'Microsoft.DataShare/accounts/shares@2021-08-01' = {
  parent: dataShareAccount
  name: 'cross-tenant-dataset'
  properties: {
    description: dataShareConfig.description
    terms: dataShareConfig.terms
    shareKind: 'CopyBased'
  }
}

// Role assignment for Purview to access Storage Account
resource purviewStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, purviewAccount.id, 'Storage Blob Data Reader')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1') // Storage Blob Data Reader
    principalId: purviewAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Data Share to access Storage Account
resource dataShareStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, dataShareAccount.id, 'Storage Blob Data Reader')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1') // Storage Blob Data Reader
    principalId: dataShareAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Data Share to contribute to Storage Account
resource dataShareStorageContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, dataShareAccount.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: dataShareAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Store connection strings in Key Vault
resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-02-01' = {
  parent: keyVault
  name: 'storage-connection-string'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
    contentType: 'text/plain'
  }
}

// Diagnostic settings for monitoring
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${storageAccount.name}-diagnostics'
  scope: storageAccount
  properties: {
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

// Outputs for reference and integration
@description('The name of the deployed storage account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the storage account')
output storageAccountId string = storageAccount.id

@description('The primary endpoint of the storage account')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The name of the Azure Purview account')
output purviewAccountName string = purviewAccount.name

@description('The resource ID of the Azure Purview account')
output purviewAccountId string = purviewAccount.id

@description('The Purview Studio URL')
output purviewStudioUrl string = 'https://${purviewAccount.name}.purview.azure.com'

@description('The Atlas endpoint URL for Purview')
output purviewAtlasEndpoint string = purviewAccount.properties.endpoints.catalog

@description('The name of the Data Share account')
output dataShareAccountName string = dataShareAccount.name

@description('The resource ID of the Data Share account')
output dataShareAccountId string = dataShareAccount.id

@description('The name of the created data share')
output dataShareName string = dataShare.name

@description('The resource ID of the created data share')
output dataShareId string = dataShare.id

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The resource ID of the Key Vault')
output keyVaultId string = keyVault.id

@description('The URI of the Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The principal ID of the Purview managed identity')
output purviewPrincipalId string = purviewAccount.identity.principalId

@description('The principal ID of the Data Share managed identity')
output dataSharePrincipalId string = dataShareAccount.identity.principalId

@description('Container names created in the storage account')
output containerNames array = containerNames

@description('Resource group name for easy reference')
output resourceGroupName string = resourceGroup().name

@description('Deployment role (provider or consumer)')
output deploymentRole string = deploymentRole

@description('Unique suffix used for resource naming')
output uniqueSuffix string = uniqueSuffix