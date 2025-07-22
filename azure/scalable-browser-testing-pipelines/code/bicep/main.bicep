@description('Main Bicep template for Azure Playwright Testing and Azure DevOps integration')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environmentName string = 'dev'

@description('Project name for resource naming')
@minLength(3)
@maxLength(15)
param projectName string

@description('Playwright workspace configuration')
param playwrightWorkspace object = {
  name: 'pw-workspace-${uniqueString(resourceGroup().id)}'
  quotaName: 'Microsoft.Playwright/quotas/Playwright'
  quotaProvisioningState: 'Succeeded'
  quotaCurrentUsage: 0
  quotaLimit: 10
  quotaName2: 'Microsoft.Playwright/quotas/Reporting'
  quotaProvisioningState2: 'Succeeded'
  quotaCurrentUsage2: 0
  quotaLimit2: 10
}

@description('Azure Container Registry configuration')
param containerRegistry object = {
  name: 'acr${uniqueString(resourceGroup().id)}'
  sku: 'Basic'
  adminUserEnabled: true
  publicNetworkAccess: 'Enabled'
  anonymousPullEnabled: false
  dataEndpointEnabled: false
  encryption: {
    status: 'disabled'
  }
  networkRuleBypassOptions: 'AzureServices'
  policies: {
    quarantinePolicy: {
      status: 'disabled'
    }
    trustPolicy: {
      type: 'Notary'
      status: 'disabled'
    }
    retentionPolicy: {
      days: 7
      status: 'disabled'
    }
  }
}

@description('Azure Key Vault configuration')
param keyVault object = {
  name: 'kv-${projectName}-${environmentName}-${uniqueString(resourceGroup().id)}'
  sku: 'standard'
  enableSoftDelete: true
  softDeleteRetentionInDays: 90
  enablePurgeProtection: true
  enableRbacAuthorization: true
  enabledForDeployment: false
  enabledForDiskEncryption: false
  enabledForTemplateDeployment: false
  publicNetworkAccess: 'Enabled'
  networkAcls: {
    defaultAction: 'Allow'
    bypass: 'AzureServices'
  }
}

@description('Log Analytics workspace configuration')
param logAnalyticsWorkspace object = {
  name: 'law-${projectName}-${environmentName}-${uniqueString(resourceGroup().id)}'
  sku: 'PerGB2018'
  retentionInDays: 30
  dailyQuotaGb: 1
  publicNetworkAccessForIngestion: 'Enabled'
  publicNetworkAccessForQuery: 'Enabled'
}

@description('Application Insights configuration')
param applicationInsights object = {
  name: 'ai-${projectName}-${environmentName}-${uniqueString(resourceGroup().id)}'
  kind: 'web'
  applicationType: 'web'
  publicNetworkAccessForIngestion: 'Enabled'
  publicNetworkAccessForQuery: 'Enabled'
  ingestionMode: 'LogAnalytics'
}

@description('Storage Account configuration for test artifacts')
param storageAccount object = {
  name: 'st${projectName}${environmentName}${uniqueString(resourceGroup().id)}'
  sku: 'Standard_LRS'
  kind: 'StorageV2'
  accessTier: 'Hot'
  allowBlobPublicAccess: false
  allowSharedKeyAccess: true
  minimumTlsVersion: 'TLS1_2'
  supportsHttpsTrafficOnly: true
  publicNetworkAccess: 'Enabled'
  allowCrossTenantReplication: false
  defaultToOAuthAuthentication: false
  networkAcls: {
    defaultAction: 'Allow'
    bypass: 'AzureServices'
  }
}

@description('Common resource tags')
param tags object = {
  Environment: environmentName
  Project: projectName
  Purpose: 'browser-testing'
  ManagedBy: 'Bicep'
  CostCenter: 'Engineering'
}

// Variables for computed values
var playwrightWorkspaceName = playwrightWorkspace.name
var containerRegistryName = containerRegistry.name
var keyVaultName = keyVault.name
var logAnalyticsWorkspaceName = logAnalyticsWorkspace.name
var applicationInsightsName = applicationInsights.name
var storageAccountName = storageAccount.name

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsWorkspace.sku
    }
    retentionInDays: logAnalyticsWorkspace.retentionInDays
    workspaceCapping: {
      dailyQuotaGb: logAnalyticsWorkspace.dailyQuotaGb
    }
    publicNetworkAccessForIngestion: logAnalyticsWorkspace.publicNetworkAccessForIngestion
    publicNetworkAccessForQuery: logAnalyticsWorkspace.publicNetworkAccessForQuery
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: applicationInsights.kind
  properties: {
    Application_Type: applicationInsights.applicationType
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: applicationInsights.ingestionMode
    publicNetworkAccessForIngestion: applicationInsights.publicNetworkAccessForIngestion
    publicNetworkAccessForQuery: applicationInsights.publicNetworkAccessForQuery
  }
}

// Storage Account for test artifacts
resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccount.sku
  }
  kind: storageAccount.kind
  properties: {
    accessTier: storageAccount.accessTier
    allowBlobPublicAccess: storageAccount.allowBlobPublicAccess
    allowSharedKeyAccess: storageAccount.allowSharedKeyAccess
    minimumTlsVersion: storageAccount.minimumTlsVersion
    supportsHttpsTrafficOnly: storageAccount.supportsHttpsTrafficOnly
    publicNetworkAccess: storageAccount.publicNetworkAccess
    allowCrossTenantReplication: storageAccount.allowCrossTenantReplication
    defaultToOAuthAuthentication: storageAccount.defaultToOAuthAuthentication
    networkAcls: storageAccount.networkAcls
  }
}

// Storage Account Blob Service
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storage
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
    changeFeed: {
      enabled: false
    }
    versioning: {
      enabled: false
    }
  }
}

// Blob containers for test artifacts
resource testArtifactsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'test-artifacts'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'playwright-test-artifacts'
    }
  }
}

resource testReportsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'test-reports'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'playwright-test-reports'
    }
  }
}

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: containerRegistry.sku
  }
  properties: {
    adminUserEnabled: containerRegistry.adminUserEnabled
    publicNetworkAccess: containerRegistry.publicNetworkAccess
    anonymousPullEnabled: containerRegistry.anonymousPullEnabled
    dataEndpointEnabled: containerRegistry.dataEndpointEnabled
    encryption: containerRegistry.encryption
    networkRuleBypassOptions: containerRegistry.networkRuleBypassOptions
    policies: containerRegistry.policies
  }
}

// Azure Key Vault
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: keyVault.sku
    }
    tenantId: subscription().tenantId
    enableSoftDelete: keyVault.enableSoftDelete
    softDeleteRetentionInDays: keyVault.softDeleteRetentionInDays
    enablePurgeProtection: keyVault.enablePurgeProtection
    enableRbacAuthorization: keyVault.enableRbacAuthorization
    enabledForDeployment: keyVault.enabledForDeployment
    enabledForDiskEncryption: keyVault.enabledForDiskEncryption
    enabledForTemplateDeployment: keyVault.enabledForTemplateDeployment
    publicNetworkAccess: keyVault.publicNetworkAccess
    networkAcls: keyVault.networkAcls
  }
}

// Azure Playwright Testing Workspace
resource playwrightWorkspaceResource 'Microsoft.AzurePlaywrightService/accounts@2023-10-01-preview' = {
  name: playwrightWorkspaceName
  location: location
  tags: tags
  properties: {
    reporting: 'Enabled'
    regionalAffinity: 'Enabled'
  }
}

// User-assigned managed identity for DevOps integration
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-${projectName}-${environmentName}-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
}

// Role assignments for managed identity
resource storageContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, managedIdentity.id, 'Storage Blob Data Contributor')
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, managedIdentity.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, managedIdentity.id, 'Key Vault Secrets User')
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Store important values in Key Vault
resource playwrightServiceUrlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'playwright-service-url'
  properties: {
    value: playwrightWorkspaceResource.properties.dashboardUri
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'storage-connection-string'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource acrLoginServerSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'acr-login-server'
  properties: {
    value: acr.properties.loginServer
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource acrUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'acr-username'
  properties: {
    value: acr.name
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource acrPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'acr-password'
  properties: {
    value: acr.listCredentials().passwords[0].value
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource appInsightsInstrumentationKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'appinsights-instrumentation-key'
  properties: {
    value: appInsights.properties.InstrumentationKey
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource appInsightsConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'appinsights-connection-string'
  properties: {
    value: appInsights.properties.ConnectionString
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Outputs for integration with Azure DevOps
output playwrightWorkspaceName string = playwrightWorkspaceResource.name
output playwrightWorkspaceId string = playwrightWorkspaceResource.id
output playwrightDashboardUri string = playwrightWorkspaceResource.properties.dashboardUri
output playwrightServiceEndpoint string = playwrightWorkspaceResource.properties.dashboardUri

output containerRegistryName string = acr.name
output containerRegistryId string = acr.id
output containerRegistryLoginServer string = acr.properties.loginServer
output containerRegistryUsername string = acr.name

output keyVaultName string = kv.name
output keyVaultId string = kv.id
output keyVaultUri string = kv.properties.vaultUri

output storageAccountName string = storage.name
output storageAccountId string = storage.id
output storageAccountPrimaryEndpoint string = storage.properties.primaryEndpoints.blob

output logAnalyticsWorkspaceName string = logAnalytics.name
output logAnalyticsWorkspaceId string = logAnalytics.id
output logAnalyticsCustomerId string = logAnalytics.properties.customerId

output applicationInsightsName string = appInsights.name
output applicationInsightsId string = appInsights.id
output applicationInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output applicationInsightsConnectionString string = appInsights.properties.ConnectionString

output managedIdentityName string = managedIdentity.name
output managedIdentityId string = managedIdentity.id
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output managedIdentityClientId string = managedIdentity.properties.clientId

output resourceGroupName string = resourceGroup().name
output resourceGroupId string = resourceGroup().id
output location string = location
output environment string = environmentName
output projectName string = projectName

// Output for DevOps variable groups
output devopsVariables object = {
  PLAYWRIGHT_SERVICE_URL: playwrightWorkspaceResource.properties.dashboardUri
  AZURE_SUBSCRIPTION_ID: subscription().subscriptionId
  AZURE_TENANT_ID: subscription().tenantId
  AZURE_CLIENT_ID: managedIdentity.properties.clientId
  RESOURCE_GROUP_NAME: resourceGroup().name
  STORAGE_ACCOUNT_NAME: storage.name
  CONTAINER_REGISTRY_NAME: acr.name
  KEY_VAULT_NAME: kv.name
  APPLICATION_INSIGHTS_NAME: appInsights.name
  LOG_ANALYTICS_WORKSPACE_NAME: logAnalytics.name
}