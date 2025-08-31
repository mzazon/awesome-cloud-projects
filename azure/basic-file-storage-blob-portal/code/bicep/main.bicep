// =============================================================================
// Azure Basic File Storage with Blob Storage and Portal
// =============================================================================
//
// This Bicep template creates a complete Azure storage solution including:
// - Storage account with security best practices
// - Blob containers for file organization
// - RBAC role assignments for secure access
// - All resources follow Azure Well-Architected Framework principles
//
// Recipe: Basic File Storage with Blob Storage and Portal
// Version: 1.0
// Author: Recipe Infrastructure Generator
// Generated: 2025-01-XX
//
// =============================================================================

@minLength(3)
@maxLength(24)
@description('Name of the storage account. Must be globally unique and contain only lowercase letters and numbers.')
param storageAccountName string

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Premium_LRS'
])
@description('Storage account replication type. LRS recommended for cost-effective learning scenarios.')
param skuName string = 'Standard_LRS'

@allowed([
  'Hot'
  'Cool'
])
@description('Access tier for blob storage. Hot tier for frequently accessed data.')
param accessTier string = 'Hot'

@allowed([
  'TLS1_0'
  'TLS1_1'
  'TLS1_2'
])
@description('Minimum TLS version for enhanced security. TLS 1.2 required by Azure best practices.')
param minimumTlsVersion string = 'TLS1_2'

@description('Principal ID of the user or service principal to assign storage permissions')
param principalId string

@allowed([
  'User'
  'Group'
  'ServicePrincipal'
  'Unknown'
  'DirectoryRoleTemplate'
  'ForeignGroup'
  'Application'
  'MSI'
  'DirectoryObjectOrGroup'
  'Everyone'
])
@description('Type of principal (User, Group, ServicePrincipal, etc.)')
param principalType string = 'User'

@description('Array of container names to create in the storage account')
param containerNames array = [
  'documents'
  'images'
  'backups'
]

@description('Resource tags for governance and cost management')
param tags object = {
  purpose: 'demo'
  environment: 'learning'
  recipe: 'basic-file-storage-blob-portal'
  costCenter: 'training'
}

@description('Enable soft delete for blobs (days retention)')
param blobSoftDeleteRetentionDays int = 7

@description('Enable soft delete for containers (days retention)')
param containerSoftDeleteRetentionDays int = 7

@description('Enable versioning for blobs')
param enableVersioning bool = true

@description('Enable change feed for blob auditing')
param enableChangeFeed bool = false

// =============================================================================
// VARIABLES
// =============================================================================

// Built-in role definition IDs for Azure Storage
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

// Generate unique deployment suffix for role assignments
var roleAssignmentSuffix = uniqueString(resourceGroup().id, storageAccountName, principalId)

// =============================================================================
// RESOURCES
// =============================================================================

// Storage Account with security best practices
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  kind: 'StorageV2'
  properties: {
    // Security configurations following Azure best practices
    accessTier: accessTier
    minimumTlsVersion: minimumTlsVersion
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: true // Required for Azure Portal access
    
    // Network access rules - default to allow all networks for demo purposes
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    
    // Encryption configuration with Microsoft-managed keys
    encryption: {
      keySource: 'Microsoft.Storage'
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
      requireInfrastructureEncryption: false
    }
    
    // Enable Azure Defender for Storage (optional)
    // This can be enabled via Azure Security Center separately
  }
}

// Blob service configuration with data protection features
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    // Data protection settings
    deleteRetentionPolicy: {
      enabled: true
      days: blobSoftDeleteRetentionDays
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: containerSoftDeleteRetentionDays
    }
    
    // Versioning and change feed
    isVersioningEnabled: enableVersioning
    changeFeed: {
      enabled: enableChangeFeed
    }
    
    // Restore policy (requires versioning)
    restorePolicy: enableVersioning ? {
      enabled: true
      days: min(blobSoftDeleteRetentionDays - 1, 6)
    } : null
    
    // CORS rules for web access (optional)
    cors: {
      corsRules: []
    }
  }
}

// Create blob containers for organized file storage
resource blobContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for containerName in containerNames: {
  parent: blobServices
  name: containerName
  properties: {
    publicAccess: 'None' // Private containers requiring authentication
    metadata: {
      purpose: 'File organization container'
      createdBy: 'Bicep template'
      recipe: 'basic-file-storage-blob-portal'
    }
  }
}]

// RBAC Role Assignment: Storage Blob Data Contributor
// This role provides read, write, and delete permissions for blob data
resource storageBlobDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, principalId, storageBlobDataContributorRoleId, roleAssignmentSuffix)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: principalId
    principalType: principalType
    description: 'Grants blob data access for the basic file storage recipe'
  }
}

// RBAC Role Assignment: Reader
// This role is required for Azure Portal navigation to storage resources
resource readerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, principalId, readerRoleId, roleAssignmentSuffix)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: principalId
    principalType: principalType
    description: 'Grants read access to storage account metadata for portal navigation'
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('Resource ID of the created storage account')
output storageAccountId string = storageAccount.id

@description('Name of the created storage account')
output storageAccountName string = storageAccount.name

@description('Primary endpoint for blob service')
output blobServiceEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Primary endpoint for web access')
output webEndpoint string = storageAccount.properties.primaryEndpoints.web

@description('Azure portal URL for storage account management')
output portalUrl string = 'https://portal.azure.com/#@${tenant().tenantId}/resource${storageAccount.id}'

@description('Names of created blob containers')
output containerNames array = [for i in range(0, length(containerNames)): {
  name: containerNames[i]
  url: '${storageAccount.properties.primaryEndpoints.blob}${containerNames[i]}'
}]

@description('Storage account connection string (for development/testing only)')
output connectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Storage account primary access key (for development/testing only)')
output primaryKey string = storageAccount.listKeys().keys[0].value

@description('Resource group name containing the storage account')
output resourceGroupName string = resourceGroup().name

@description('Location where resources were deployed')
output location string = location

@description('Applied resource tags')
output tags object = tags

@description('Storage account properties summary')
output storageAccountProperties object = {
  skuName: storageAccount.sku.name
  accessTier: storageAccount.properties.accessTier
  minimumTlsVersion: storageAccount.properties.minimumTlsVersion
  httpsTrafficOnly: storageAccount.properties.supportsHttpsTrafficOnly
  allowBlobPublicAccess: storageAccount.properties.allowBlobPublicAccess
  allowSharedKeyAccess: storageAccount.properties.allowSharedKeyAccess
  isVersioningEnabled: blobServices.properties.isVersioningEnabled
  softDeleteEnabled: blobServices.properties.deleteRetentionPolicy.enabled
  softDeleteRetentionDays: blobServices.properties.deleteRetentionPolicy.days
}

@description('RBAC role assignments created')
output roleAssignments array = [
  {
    roleDefinitionName: 'Storage Blob Data Contributor'
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: principalId
    principalType: principalType
    scope: 'Storage Account'
  }
  {
    roleDefinitionName: 'Reader'
    roleDefinitionId: readerRoleId
    principalId: principalId
    principalType: principalType
    scope: 'Storage Account'
  }
]

@description('Next steps and usage guidance')
output nextSteps object = {
  portalAccess: 'Navigate to the Azure Portal using the provided portalUrl'
  cliAccess: 'Use Azure CLI with --auth-mode login for authenticated operations'
  containers: 'Upload files to the created containers: ${join(containerNames, ', ')}'
  security: 'TLS ${minimumTlsVersion} enforced, public access disabled for security'
  dataProtection: 'Soft delete enabled with ${blobSoftDeleteRetentionDays} days retention'
  monitoring: 'Consider enabling Azure Monitor and diagnostic settings for production use'
}