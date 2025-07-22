// =========================================================================
// Azure Purview and Data Lake Storage Data Governance Infrastructure
// =========================================================================
// This Bicep template deploys a complete data governance solution using:
// - Azure Purview for data cataloging and classification
// - Azure Data Lake Storage Gen2 for scalable data storage
// - Azure Synapse Analytics for advanced analytics
// - Azure Key Vault for secrets management
// - Role-based access control (RBAC) for security
// =========================================================================

targetScope = 'resourceGroup'

// =========================================================================
// PARAMETERS
// =========================================================================

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names (auto-generated if not provided)')
param uniqueSuffix string = take(uniqueString(resourceGroup().id), 6)

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'data-governance'
  solution: 'purview-datalake'
  environment: environment
}

@description('Storage account configuration')
param storageConfig object = {
  sku: 'Standard_LRS'
  accessTier: 'Hot'
  enableVersioning: true
  enableSoftDelete: true
  softDeleteRetentionDays: 7
  enableHierarchicalNamespace: true
}

@description('Synapse workspace administrator credentials')
@secure()
param sqlAdminLogin string = 'sqladminuser'

@description('Synapse workspace administrator password')
@minLength(8)
@secure()
param sqlAdminPassword string

@description('Enable Synapse workspace deployment')
param enableSynapse bool = true

@description('Enable Key Vault deployment')
param enableKeyVault bool = true

@description('Client IP address for firewall rules (current user IP)')
param clientIpAddress string = ''

@description('Current user object ID for role assignments')
param currentUserObjectId string = ''

// =========================================================================
// VARIABLES
// =========================================================================

var resourceNames = {
  purviewAccount: 'purview-${uniqueSuffix}'
  storageAccount: 'datalake${uniqueSuffix}'
  synapseWorkspace: 'synapse-${uniqueSuffix}'
  keyVault: 'kv-${uniqueSuffix}'
  managedResourceGroup: 'managed-rg-purview-${uniqueSuffix}'
}

var storageContainers = [
  'raw-data'
  'processed-data'
  'sensitive-data'
  'synapse'
]

var dataClassificationRules = {
  emailPattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'
  phonePattern: '^\\+?[1-9]\\d{1,14}$|^\\(?\\d{3}\\)?[-\\s.]?\\d{3}[-\\s.]?\\d{4}$'
}

// =========================================================================
// AZURE STORAGE ACCOUNT (DATA LAKE GEN2)
// =========================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: storageConfig.sku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: storageConfig.accessTier
    isHnsEnabled: storageConfig.enableHierarchicalNamespace
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
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

// Storage Account Blob Services Configuration
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: storageConfig.enableSoftDelete
      days: storageConfig.softDeleteRetentionDays
    }
    isVersioningEnabled: storageConfig.enableVersioning
    changeFeed: {
      enabled: true
      retentionInDays: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Create containers for different data domains
resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for containerName in storageContainers: {
  parent: blobServices
  name: containerName
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'data-governance'
      environment: environment
    }
  }
}]

// =========================================================================
// AZURE PURVIEW ACCOUNT
// =========================================================================

resource purviewAccount 'Microsoft.Purview/accounts@2021-12-01' = {
  name: resourceNames.purviewAccount
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedResourceGroupName: resourceNames.managedResourceGroup
    publicNetworkAccess: 'Enabled'
  }
}

// =========================================================================
// AZURE KEY VAULT (OPTIONAL)
// =========================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = if (enableKeyVault) {
  name: resourceNames.keyVault
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Store storage account key in Key Vault
resource storageKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (enableKeyVault) {
  parent: keyVault
  name: 'storage-account-key'
  properties: {
    value: storageAccount.listKeys().keys[0].value
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// =========================================================================
// AZURE SYNAPSE ANALYTICS WORKSPACE (OPTIONAL)
// =========================================================================

resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = if (enableSynapse) {
  name: resourceNames.synapseWorkspace
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: storageAccount.properties.primaryEndpoints.dfs
      filesystem: 'synapse'
      createManagedPrivateEndpoint: false
    }
    sqlAdministratorLogin: sqlAdminLogin
    sqlAdministratorLoginPassword: sqlAdminPassword
    managedResourceGroupName: 'managed-rg-synapse-${uniqueSuffix}'
    publicNetworkAccess: 'Enabled'
    cspWorkspaceAdminProperties: {
      initialWorkspaceAdminObjectId: currentUserObjectId
    }
    purviewConfiguration: {
      purviewResourceId: purviewAccount.id
    }
  }
}

// Synapse Firewall Rules
resource synapseFirewallAllowAzure 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = if (enableSynapse) {
  parent: synapseWorkspace
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource synapseFirewallClientIP 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = if (enableSynapse && !empty(clientIpAddress)) {
  parent: synapseWorkspace
  name: 'AllowClientIP'
  properties: {
    startIpAddress: clientIpAddress
    endIpAddress: clientIpAddress
  }
}

// =========================================================================
// ROLE-BASED ACCESS CONTROL (RBAC)
// =========================================================================

// Purview Data Reader role assignment to storage account
resource purviewStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, purviewAccount.id, 'Storage Blob Data Reader')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1') // Storage Blob Data Reader
    principalId: purviewAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Purview Data Curator role assignment to current user
resource purviewDataCuratorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(currentUserObjectId)) {
  name: guid(purviewAccount.id, currentUserObjectId, 'Purview Data Curator')
  scope: purviewAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8a3c2885-9b38-4fd2-9d99-91af537c1347') // Purview Data Curator
    principalId: currentUserObjectId
    principalType: 'User'
  }
}

// Storage Blob Data Contributor role for current user
resource storageDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(currentUserObjectId)) {
  name: guid(storageAccount.id, currentUserObjectId, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: currentUserObjectId
    principalType: 'User'
  }
}

// Synapse Administrator role for current user
resource synapseAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableSynapse && !empty(currentUserObjectId)) {
  name: guid(synapseWorkspace.id, currentUserObjectId, 'Synapse Administrator')
  scope: synapseWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '6e4bf58a-b8e1-4cc3-bbf9-d73143322b78') // Synapse Administrator
    principalId: currentUserObjectId
    principalType: 'User'
  }
}

// Key Vault Secrets Officer role for current user
resource keyVaultSecretsOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableKeyVault && !empty(currentUserObjectId)) {
  name: guid(keyVault.id, currentUserObjectId, 'Key Vault Secrets Officer')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') // Key Vault Secrets Officer
    principalId: currentUserObjectId
    principalType: 'User'
  }
}

// Synapse to Purview connection (for lineage tracking)
resource synapsePurviewRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableSynapse) {
  name: guid(purviewAccount.id, synapseWorkspace.id, 'Purview Data Source Administrator')
  scope: purviewAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '200bba9e-f0c8-430f-892b-6f0794863803') // Purview Data Source Administrator
    principalId: synapseWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// =========================================================================
// OUTPUTS
// =========================================================================

@description('Azure Purview account details')
output purview object = {
  name: purviewAccount.name
  resourceId: purviewAccount.id
  catalogEndpoint: purviewAccount.properties.endpoints.catalog
  scanEndpoint: purviewAccount.properties.endpoints.scan
  managedIdentityPrincipalId: purviewAccount.identity.principalId
  portalUrl: 'https://web.purview.azure.com/resource/${purviewAccount.name}'
}

@description('Storage account details')
output storage object = {
  name: storageAccount.name
  resourceId: storageAccount.id
  primaryEndpoints: storageAccount.properties.primaryEndpoints
  containers: storageContainers
}

@description('Synapse workspace details')
output synapse object = enableSynapse ? {
  name: synapseWorkspace.name
  resourceId: synapseWorkspace.id
  webEndpoint: synapseWorkspace.properties.connectivityEndpoints.web
  devEndpoint: synapseWorkspace.properties.connectivityEndpoints.dev
  sqlEndpoint: synapseWorkspace.properties.connectivityEndpoints.sql
  sqlOnDemandEndpoint: synapseWorkspace.properties.connectivityEndpoints.sqlOnDemand
  managedIdentityPrincipalId: synapseWorkspace.identity.principalId
} : {}

@description('Key Vault details')
output keyVault object = enableKeyVault ? {
  name: keyVault.name
  resourceId: keyVault.id
  vaultUri: keyVault.properties.vaultUri
} : {}

@description('Resource group information')
output resourceGroup object = {
  name: resourceGroup().name
  location: resourceGroup().location
  tags: tags
}

@description('Data classification configuration')
output dataClassification object = {
  emailPattern: dataClassificationRules.emailPattern
  phonePattern: dataClassificationRules.phonePattern
  sensitivityLabels: [
    'Public'
    'Internal' 
    'Confidential'
    'Restricted'
  ]
}

@description('Next steps for manual configuration')
output nextSteps array = [
  'Configure data source registration in Azure Purview portal'
  'Set up automated scanning schedules for data discovery'
  'Configure custom classification rules and sensitivity labels'
  'Create data quality rules and monitoring dashboards'
  'Set up data lineage tracking for Synapse pipelines'
  'Configure compliance reporting and alerting'
]

@description('Important URLs for accessing services')
output serviceUrls object = {
  purviewPortal: 'https://web.purview.azure.com/resource/${purviewAccount.name}'
  synapseStudio: enableSynapse ? synapseWorkspace.properties.connectivityEndpoints.web : ''
  storageExplorer: 'https://portal.azure.com/#@/resource${storageAccount.id}/overview'
  keyVaultPortal: enableKeyVault ? 'https://portal.azure.com/#@/resource${keyVault.id}/overview' : ''
}