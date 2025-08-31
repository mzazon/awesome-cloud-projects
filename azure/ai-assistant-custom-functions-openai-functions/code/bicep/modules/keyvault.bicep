@description('Bicep module for Azure Key Vault to securely store OpenAI keys and other secrets')

// Parameters
@description('The location/region where resources will be deployed')
param location string

@description('Key Vault name (must be globally unique)')
param keyVaultName string

@description('Tags to apply to resources')
param tags object = {}

@description('Enable Key Vault for deployment access')
param enabledForDeployment bool = false

@description('Enable Key Vault for disk encryption access')
param enabledForDiskEncryption bool = false

@description('Enable Key Vault for template deployment access')
param enabledForTemplateDeployment bool = true

@description('Key Vault SKU')
@allowed(['standard', 'premium'])
param skuName string = 'standard'

// Get current user/service principal for access policy
var tenantId = tenant().tenantId
var currentUserObjectId = '00000000-0000-0000-0000-000000000000' // Will be overridden by deployment

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    enabledForDeployment: enabledForDeployment
    enabledForDiskEncryption: enabledForDiskEncryption
    enabledForTemplateDeployment: enabledForTemplateDeployment
    tenantId: tenantId
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true // Use RBAC instead of access policies
    sku: {
      name: skuName
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Diagnostic Settings for Key Vault
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: keyVault
  properties: {
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Key Vault Secret for OpenAI API Key (placeholder - actual value set in main template)
resource openAIApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'openai-api-key'
  properties: {
    attributes: {
      enabled: true
    }
    value: 'placeholder-will-be-updated-by-main-template'
  }
}

// Key Vault Secret for Storage Connection String (placeholder)
resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-connection-string'
  properties: {
    attributes: {
      enabled: true
    }
    value: 'placeholder-will-be-updated-by-main-template'
  }
}

// Outputs
@description('Key Vault ID')
output keyVaultId string = keyVault.id

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('OpenAI API Key secret name')
output openAIKeySecretName string = openAIApiKeySecret.name

@description('Storage connection string secret name')
output storageConnectionStringSecretName string = storageConnectionStringSecret.name

@description('Key Vault references for application settings')
output secretReferences object = {
  openAIApiKey: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${openAIApiKeySecret.name})'
  storageConnectionString: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${storageConnectionStringSecret.name})'
}