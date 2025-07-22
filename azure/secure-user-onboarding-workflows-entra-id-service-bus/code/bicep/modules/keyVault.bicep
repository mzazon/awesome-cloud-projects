// ==============================================================================
// Key Vault Module for Secure Credential Storage
// ==============================================================================
// This module creates an Azure Key Vault with enterprise security features
// including RBAC authorization, soft delete, and purge protection
// ==============================================================================

@description('Key Vault name')
param keyVaultName string

@description('Location for Key Vault')
param location string

@description('Key Vault SKU')
@allowed(['standard', 'premium'])
param skuName string = 'standard'

@description('Soft delete retention days')
@minValue(7)
@maxValue(90)
param retentionDays int = 90

@description('Enable RBAC authorization')
param enableRbacAuthorization bool = true

@description('Enable soft delete')
param enableSoftDelete bool = true

@description('Enable purge protection')
param enablePurgeProtection bool = true

@description('Tags to apply to the Key Vault')
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

@description('Tenant ID for the Key Vault')
param tenantId string = tenant().tenantId

// ==============================================================================
// VARIABLES
// ==============================================================================

var keyVaultProperties = {
  tenantId: tenantId
  sku: {
    family: 'A'
    name: skuName
  }
  enabledForDeployment: false
  enabledForDiskEncryption: false
  enabledForTemplateDeployment: true
  enableSoftDelete: enableSoftDelete
  softDeleteRetentionInDays: retentionDays
  enablePurgeProtection: enablePurgeProtection
  enableRbacAuthorization: enableRbacAuthorization
  networkAcls: networkAcls
  publicNetworkAccess: 'Enabled'
}

// ==============================================================================
// RESOURCES
// ==============================================================================

// Create Key Vault with security features
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: keyVaultProperties
}

// Diagnostic settings for Key Vault
resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && !empty(logAnalyticsWorkspaceId)) {
  name: 'keyvault-diagnostics'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
      {
        category: 'AzurePolicyEvaluationDetails'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
    ]
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('Key Vault resource ID')
output keyVaultResourceId string = keyVault.id

@description('Key Vault resource reference')
output keyVaultResource resource = keyVault

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Key Vault tenant ID')
output tenantId string = keyVault.properties.tenantId

@description('Key Vault SKU')
output skuName string = keyVault.properties.sku.name

@description('Soft delete retention days')
output softDeleteRetentionDays int = keyVault.properties.softDeleteRetentionInDays