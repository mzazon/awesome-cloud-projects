// ============================================================================
// Main Bicep template for Centralized Application Configuration Management
// with Azure App Configuration and Azure Key Vault
// ============================================================================

targetScope = 'resourceGroup'

// Parameters
@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environmentName string = 'dev'

@description('Application name used for resource naming')
@minLength(2)
@maxLength(10)
param applicationName string = 'configdemo'

@description('Primary Azure region for resource deployment')
param location string = resourceGroup().location

@description('App Configuration store SKU')
@allowed(['Free', 'Standard'])
param appConfigSku string = 'Standard'

@description('Key Vault SKU')
@allowed(['Standard', 'Premium'])
param keyVaultSku string = 'Standard'

@description('App Service Plan SKU')
@allowed(['B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1', 'P2', 'P3'])
param appServicePlanSku string = 'B1'

@description('Web App runtime stack')
@allowed(['NODE|18-lts', 'NODE|20-lts', 'DOTNETCORE|8.0', 'PYTHON|3.11'])
param webAppRuntime string = 'NODE|18-lts'

@description('Enable soft delete for Key Vault')
param enableKeyVaultSoftDelete bool = true

@description('Soft delete retention days for Key Vault')
@minValue(7)
@maxValue(90)
param keyVaultRetentionDays int = 7

@description('Enable purge protection for Key Vault')
param enableKeyVaultPurgeProtection bool = false

@description('Common tags to apply to all resources')
param tags object = {
  environment: environmentName
  project: 'config-management'
  purpose: 'recipe-demo'
}

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var appConfigName = 'ac-${applicationName}-${environmentName}-${uniqueSuffix}'
var keyVaultName = 'kv-${applicationName}-${environmentName}-${uniqueSuffix}'
var appServicePlanName = 'asp-${applicationName}-${environmentName}-${uniqueSuffix}'
var webAppName = 'wa-${applicationName}-${environmentName}-${uniqueSuffix}'

// Built-in role definitions
var appConfigDataReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '516239f1-63e1-4d78-a4de-a74fb236a071')
var keyVaultSecretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

// ============================================================================
// App Configuration Store
// ============================================================================

resource appConfigStore 'Microsoft.AppConfiguration/configurationStores@2023-03-01' = {
  name: appConfigName
  location: location
  tags: tags
  sku: {
    name: appConfigSku
  }
  properties: {
    disableLocalAuth: false
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ============================================================================
// Key Vault
// ============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    tenantId: subscription().tenantId
    accessPolicies: []
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: enableKeyVaultSoftDelete
    softDeleteRetentionInDays: keyVaultRetentionDays
    enablePurgeProtection: enableKeyVaultPurgeProtection ? true : null
    enableRbacAuthorization: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ============================================================================
// App Service Plan
// ============================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

// ============================================================================
// Web App
// ============================================================================

resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: webAppRuntime
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      use32BitWorkerProcess: false
      appSettings: [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
      ]
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ============================================================================
// Role Assignments
// ============================================================================

// Grant Web App access to App Configuration
resource appConfigRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: appConfigStore
  name: guid(appConfigStore.id, webApp.id, appConfigDataReaderRoleId)
  properties: {
    roleDefinitionId: appConfigDataReaderRoleId
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Web App access to Key Vault secrets
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, webApp.id, keyVaultSecretsUserRoleId)
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleId
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Sample Configuration Data
// ============================================================================

// App Configuration key-values
resource appConfigKeyValue1 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfigStore
  name: 'App:Name$Production'
  properties: {
    value: 'Demo Configuration App'
    contentType: 'text/plain'
  }
}

resource appConfigKeyValue2 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfigStore
  name: 'App:Version$Production'
  properties: {
    value: '1.0.0'
    contentType: 'text/plain'
  }
}

resource appConfigKeyValue3 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfigStore
  name: 'Features:EnableLogging$Production'
  properties: {
    value: 'true'
    contentType: 'text/plain'
  }
}

// Feature flag
resource featureFlag 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = {
  parent: appConfigStore
  name: '.appconfig.featureflag~2FBetaFeatures$Production'
  properties: {
    value: '{"id":"BetaFeatures","description":"","enabled":true,"conditions":{"client_filters":[]}}'
    contentType: 'application/vnd.microsoft.appconfig.ff+json;charset=utf-8'
  }
}

// Key Vault secrets
resource databaseConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'DatabaseConnection'
  properties: {
    value: 'Server=db.example.com;Database=prod;Uid=admin;Pwd=SecureP@ssw0rd123;'
    contentType: 'text/plain'
  }
}

resource apiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ApiKey'
  properties: {
    value: 'sk-1234567890abcdef1234567890abcdef'
    contentType: 'text/plain'
  }
}

// ============================================================================
// Web App Configuration
// ============================================================================

// Configure Web App settings with App Configuration and Key Vault references
resource webAppConfig 'Microsoft.Web/sites/config@2023-01-01' = {
  parent: webApp
  name: 'appsettings'
  properties: {
    // App Configuration connection
    AZURE_APP_CONFIG_ENDPOINT: appConfigStore.properties.endpoint
    
    // Key Vault references
    DATABASE_CONNECTION: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=DatabaseConnection)'
    API_KEY: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=ApiKey)'
    
    // Application settings
    WEBSITES_ENABLE_APP_SERVICE_STORAGE: 'false'
    PORT: '3000'
    
    // Environment identifier
    ENVIRONMENT: environmentName
  }
  dependsOn: [
    appConfigRoleAssignment
    keyVaultRoleAssignment
    databaseConnectionSecret
    apiKeySecret
  ]
}

// ============================================================================
// Outputs
// ============================================================================

@description('App Configuration store name')
output appConfigurationName string = appConfigStore.name

@description('App Configuration store endpoint')
output appConfigurationEndpoint string = appConfigStore.properties.endpoint

@description('App Configuration store ID')
output appConfigurationId string = appConfigStore.id

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Key Vault ID')
output keyVaultId string = keyVault.id

@description('Web App name')
output webAppName string = webApp.name

@description('Web App URL')
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'

@description('Web App ID')
output webAppId string = webApp.id

@description('Web App managed identity principal ID')
output webAppManagedIdentityPrincipalId string = webApp.identity.principalId

@description('App Service Plan name')
output appServicePlanName string = appServicePlan.name

@description('App Service Plan ID')
output appServicePlanId string = appServicePlan.id

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Deployment environment')
output environment string = environmentName

@description('Application name')
output applicationName string = applicationName

@description('Sample configuration values created')
output sampleConfigKeys array = [
  'App:Name'
  'App:Version'
  'Features:EnableLogging'
  'BetaFeatures (Feature Flag)'
]

@description('Sample secrets created in Key Vault')
output sampleSecrets array = [
  'DatabaseConnection'
  'ApiKey'
]