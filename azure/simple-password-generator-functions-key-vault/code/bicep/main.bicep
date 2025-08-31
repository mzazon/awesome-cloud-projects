// ============================================================================
// Main Bicep Template: Simple Password Generator with Functions and Key Vault
// ============================================================================
// This template deploys a serverless password generator using Azure Functions
// and Azure Key Vault for secure password storage with managed identity.

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment designation for resource naming and tagging')
@allowed(['dev', 'test', 'staging', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Function App runtime version')
@allowed(['18', '20'])
param functionAppNodeVersion string = '20'

@description('Enable soft delete for Key Vault (recommended for production)')
param enableKeyVaultSoftDelete bool = true

@description('Soft delete retention period in days (7-90)')
@minValue(7)
@maxValue(90)
param keyVaultRetentionDays int = 7

@description('Enable purge protection for Key Vault (recommended for production)')
param enableKeyVaultPurgeProtection bool = false

@description('Tags to apply to all resources')
param resourceTags object = {
  Environment: environment
  Project: 'password-generator'
  Purpose: 'recipe-demo'
  ManagedBy: 'bicep'
}

// Variables
var resourcePrefix = 'passgen-${environment}'
var keyVaultName = 'kv-${resourcePrefix}-${uniqueSuffix}'
var storageAccountName = 'st${replace(resourcePrefix, '-', '')}${uniqueSuffix}'
var functionAppName = 'func-${resourcePrefix}-${uniqueSuffix}'
var appServicePlanName = 'asp-${resourcePrefix}-${uniqueSuffix}'
var applicationInsightsName = 'ai-${resourcePrefix}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-${resourcePrefix}-${uniqueSuffix}'

// ============================================================================
// Log Analytics Workspace for Application Insights
// ============================================================================
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

// ============================================================================
// Application Insights for Function App monitoring
// ============================================================================
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// Storage Account for Function App runtime
// ============================================================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// ============================================================================
// App Service Plan (Consumption) for Function App
// ============================================================================
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: resourceTags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    reserved: false
  }
}

// ============================================================================
// Azure Key Vault for secure password storage
// ============================================================================
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableRbacAuthorization: true
    enableSoftDelete: enableKeyVaultSoftDelete
    enablePurgeProtection: enableKeyVaultPurgeProtection ? true : null
    softDeleteRetentionInDays: enableKeyVaultSoftDelete ? keyVaultRetentionDays : null
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ============================================================================
// Function App with system-assigned managed identity
// ============================================================================
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: resourceTags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~${functionAppNodeVersion}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'KEY_VAULT_URI'
          value: keyVault.properties.vaultUri
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
  }
}

// ============================================================================
// RBAC: Grant Key Vault Secrets Officer role to Function App managed identity
// ============================================================================
resource keyVaultSecretsOfficerRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // Key Vault Secrets Officer
}

resource functionAppKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, functionApp.id, keyVaultSecretsOfficerRoleDefinition.id)
  properties: {
    roleDefinitionId: keyVaultSecretsOfficerRoleDefinition.id
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================
@description('The resource group name where resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('The Function App name')
output functionAppName string = functionApp.name

@description('The Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The Key Vault name')
output keyVaultName string = keyVault.name

@description('The Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The Function App managed identity principal ID')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('The Storage Account name')
output storageAccountName string = storageAccount.name

@description('The Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Resource tags applied to all resources')
output resourceTags object = resourceTags

@description('Deployment summary with all key information')
output deploymentSummary object = {
  functionApp: {
    name: functionApp.name
    url: 'https://${functionApp.properties.defaultHostName}'
    principalId: functionApp.identity.principalId
  }
  keyVault: {
    name: keyVault.name
    uri: keyVault.properties.vaultUri
  }
  monitoring: {
    applicationInsights: applicationInsights.name
    logAnalytics: logAnalyticsWorkspace.name
  }
  storage: {
    name: storageAccount.name
  }
}