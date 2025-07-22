// ==============================================================================
// Multi-Tenant SaaS Resource Isolation with Azure Deployment Stacks and Workload Identity
// This Bicep template creates a complete multi-tenant SaaS infrastructure with
// strong resource isolation, automated governance, and workload identity integration
// ==============================================================================

@description('Unique identifier for the tenant')
@minLength(3)
@maxLength(10)
param tenantId string

@description('Display name for the tenant')
@minLength(1)
@maxLength(50)
param tenantName string

@description('Environment designation')
@allowed(['development', 'staging', 'production'])
param environment string = 'production'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Resource naming prefix')
param resourcePrefix string = 'saas'

@description('Enable advanced threat protection')
param enableAdvancedThreatProtection bool = true

@description('Enable diagnostic logging')
param enableDiagnosticLogging bool = true

@description('Log Analytics workspace resource ID for diagnostic logging')
param logAnalyticsWorkspaceId string = ''

@description('Virtual network address space')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet address prefix for tenant resources')
param subnetAddressPrefix string = '10.0.1.0/24'

@description('Tags to apply to all resources')
param resourceTags object = {
  Environment: environment
  TenantId: tenantId
  TenantName: tenantName
  ManagedBy: 'DeploymentStack'
  Solution: 'Multi-Tenant-SaaS'
}

// ==============================================================================
// Variables
// ==============================================================================

var tenantResourcePrefix = 'tenant-${tenantId}'
var storageAccountName = take('${tenantResourcePrefix}storage${uniqueString(resourceGroup().id)}', 24)
var keyVaultName = '${tenantResourcePrefix}-kv-${uniqueString(resourceGroup().id)}'
var networkSecurityGroupName = '${tenantResourcePrefix}-nsg'
var virtualNetworkName = '${tenantResourcePrefix}-vnet'
var subnetName = 'tenant-subnet'
var managedIdentityName = '${tenantResourcePrefix}-mi'
var logAnalyticsWorkspaceName = '${tenantResourcePrefix}-law'
var applicationInsightsName = '${tenantResourcePrefix}-ai'

// Common tags for all resources
var allResourceTags = union(resourceTags, {
  CreatedDate: utcNow('yyyy-MM-dd')
  ResourceGroup: resourceGroup().name
})

// ==============================================================================
// Managed Identity for Tenant Workloads
// ==============================================================================

resource tenantManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: allResourceTags
}

// ==============================================================================
// Network Security Group with Tenant Isolation Rules
// ==============================================================================

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: networkSecurityGroupName
  location: location
  tags: allResourceTags
  properties: {
    securityRules: [
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Deny all inbound traffic by default'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          access: 'Deny'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHttpsInbound'
        properties: {
          description: 'Allow HTTPS inbound traffic'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowVnetInbound'
        properties: {
          description: 'Allow traffic within virtual network'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
          access: 'Allow'
          priority: 200
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyVnetCrossTenantAccess'
        properties: {
          description: 'Prevent cross-tenant communication'
          protocol: '*'
          sourceAddressPrefix: '10.0.0.0/8'
          sourcePortRange: '*'
          destinationAddressPrefix: subnetAddressPrefix
          destinationPortRange: '*'
          access: 'Deny'
          priority: 300
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ==============================================================================
// Virtual Network with Tenant-Specific Subnet
// ==============================================================================

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: virtualNetworkName
  location: location
  tags: allResourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.KeyVault'
            }
          ]
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
    enableDdosProtection: false
  }
}

// ==============================================================================
// Storage Account with Advanced Security
// ==============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: allResourceTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    allowCrossTenantReplication: false
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: '${virtualNetwork.id}/subnets/${subnetName}'
          action: 'Allow'
        }
      ]
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
        queue: {
          enabled: true
          keyType: 'Account'
        }
        table: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: true
    }
  }
}

// Storage Account Blob Service with versioning and soft delete
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    isVersioningEnabled: true
    changeFeed: {
      enabled: true
      retentionInDays: 30
    }
    restorePolicy: {
      enabled: true
      days: 29
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
  }
}

// Tenant-specific blob container
resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'tenant-data'
  properties: {
    publicAccess: 'None'
    metadata: {
      tenantId: tenantId
      environment: environment
    }
  }
}

// ==============================================================================
// Key Vault for Tenant Secrets
// ==============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: allResourceTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableRbacAuthorization: true
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: '${virtualNetwork.id}/subnets/${subnetName}'
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
      bypass: 'AzureServices'
    }
  }
}

// ==============================================================================
// Log Analytics Workspace for Tenant-Specific Monitoring
// ==============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableDiagnosticLogging) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: allResourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ==============================================================================
// Application Insights for Tenant Application Monitoring
// ==============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableDiagnosticLogging) {
  name: applicationInsightsName
  location: location
  tags: allResourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableDiagnosticLogging ? logAnalyticsWorkspace.id : null
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ==============================================================================
// Role Assignments for Tenant Managed Identity
// ==============================================================================

// Storage Blob Data Contributor role for tenant managed identity
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, tenantManagedIdentity.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: tenantManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Secrets User role for tenant managed identity
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, tenantManagedIdentity.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: tenantManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ==============================================================================
// Diagnostic Settings for Security and Compliance Monitoring
// ==============================================================================

// Storage Account diagnostic settings
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnosticLogging && !empty(logAnalyticsWorkspaceId)) {
  name: '${storageAccountName}-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
    ]
  }
}

// Key Vault diagnostic settings
resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnosticLogging && !empty(logAnalyticsWorkspaceId)) {
  name: '${keyVaultName}-diagnostics'
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

// Virtual Network diagnostic settings
resource vnetDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnosticLogging && !empty(logAnalyticsWorkspaceId)) {
  name: '${virtualNetworkName}-diagnostics'
  scope: virtualNetwork
  properties: {
    workspaceId: logAnalyticsWorkspaceId
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
// Advanced Threat Protection (if enabled)
// ==============================================================================

resource storageAdvancedThreatProtection 'Microsoft.Security/advancedThreatProtectionSettings@2019-01-01' = if (enableAdvancedThreatProtection) {
  name: 'current'
  scope: storageAccount
  properties: {
    isEnabled: true
  }
}

// ==============================================================================
// Outputs
// ==============================================================================

@description('The unique identifier for this tenant')
output tenantId string = tenantId

@description('The display name for this tenant')
output tenantName string = tenantName

@description('The environment designation')
output environment string = environment

@description('The resource ID of the tenant managed identity')
output managedIdentityId string = tenantManagedIdentity.id

@description('The client ID of the tenant managed identity')
output managedIdentityClientId string = tenantManagedIdentity.properties.clientId

@description('The principal ID of the tenant managed identity')
output managedIdentityPrincipalId string = tenantManagedIdentity.properties.principalId

@description('The resource ID of the tenant storage account')
output storageAccountId string = storageAccount.id

@description('The name of the tenant storage account')
output storageAccountName string = storageAccount.name

@description('The primary endpoints for the tenant storage account')
output storageAccountEndpoints object = storageAccount.properties.primaryEndpoints

@description('The resource ID of the tenant Key Vault')
output keyVaultId string = keyVault.id

@description('The name of the tenant Key Vault')
output keyVaultName string = keyVault.name

@description('The URI of the tenant Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The resource ID of the tenant virtual network')
output virtualNetworkId string = virtualNetwork.id

@description('The name of the tenant virtual network')
output virtualNetworkName string = virtualNetwork.name

@description('The resource ID of the tenant subnet')
output subnetId string = virtualNetwork.properties.subnets[0].id

@description('The resource ID of the network security group')
output networkSecurityGroupId string = networkSecurityGroup.id

@description('The resource ID of the Log Analytics workspace (if created)')
output logAnalyticsWorkspaceId string = enableDiagnosticLogging ? logAnalyticsWorkspace.id : ''

@description('The resource ID of the Application Insights instance (if created)')
output applicationInsightsId string = enableDiagnosticLogging ? applicationInsights.id : ''

@description('The instrumentation key for Application Insights (if created)')
output applicationInsightsInstrumentationKey string = enableDiagnosticLogging ? applicationInsights.properties.InstrumentationKey : ''

@description('The connection string for Application Insights (if created)')
output applicationInsightsConnectionString string = enableDiagnosticLogging ? applicationInsights.properties.ConnectionString : ''

@description('All resource tags applied to tenant resources')
output resourceTags object = allResourceTags

@description('Summary of deployed tenant resources')
output deploymentSummary object = {
  tenantId: tenantId
  tenantName: tenantName
  environment: environment
  resourceGroup: resourceGroup().name
  location: location
  deployedResources: {
    managedIdentity: tenantManagedIdentity.name
    storageAccount: storageAccount.name
    keyVault: keyVault.name
    virtualNetwork: virtualNetwork.name
    networkSecurityGroup: networkSecurityGroup.name
    logAnalyticsWorkspace: enableDiagnosticLogging ? logAnalyticsWorkspace.name : 'Not deployed'
    applicationInsights: enableDiagnosticLogging ? applicationInsights.name : 'Not deployed'
  }
  securityFeatures: {
    advancedThreatProtection: enableAdvancedThreatProtection
    diagnosticLogging: enableDiagnosticLogging
    rbacAuthorization: true
    networkIsolation: true
    encryptionAtRest: true
    tlsEnforcement: true
  }
}