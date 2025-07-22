// Azure Real-Time Collaborative Applications Infrastructure
// This template deploys Azure Communication Services, Azure Fluid Relay, Azure Functions, and supporting resources

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environmentName string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Tags to apply to all resources')
param tags object = {
  environment: environmentName
  purpose: 'collaboration'
  solution: 'real-time-collaborative-app'
}

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS'])
param storageSku string = 'Standard_LRS'

@description('Function App runtime stack')
@allowed(['node', 'dotnet', 'python'])
param functionRuntime string = 'node'

@description('Function App runtime version')
param functionRuntimeVersion string = '18'

@description('Key Vault SKU')
@allowed(['standard', 'premium'])
param keyVaultSku string = 'standard'

@description('Fluid Relay SKU')
@allowed(['basic', 'standard'])
param fluidRelaySku string = 'basic'

@description('Enable Application Insights')
param enableApplicationInsights bool = true

@description('Enable CORS for Function App')
param enableCors bool = true

@description('Allowed CORS origins')
param corsOrigins array = ['*']

// Variables
var acsName = 'acs-collab-${resourceSuffix}'
var fluidRelayName = 'fluid-collab-${resourceSuffix}'
var functionAppName = 'func-collab-${resourceSuffix}'
var storageAccountName = 'stcollab${resourceSuffix}'
var keyVaultName = 'kv-collab-${resourceSuffix}'
var appInsightsName = 'ai-collab-${resourceSuffix}'
var appServicePlanName = 'asp-collab-${resourceSuffix}'

// Azure Communication Services
resource communicationService 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: acsName
  location: 'global'
  tags: tags
  properties: {
    dataLocation: 'United States'
  }
}

// Azure Fluid Relay
resource fluidRelayService 'Microsoft.FluidRelay/fluidRelayServers@2022-06-01' = {
  name: fluidRelayName
  location: location
  tags: tags
  properties: {
    encryption: {
      customerManagedKeyEncryption: {
        keyEncryptionKeyIdentity: {
          identityType: 'SystemAssigned'
        }
      }
    }
  }
  sku: {
    name: fluidRelaySku
  }
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Storage Containers
resource whiteboardsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/whiteboards'
  properties: {
    publicAccess: 'None'
  }
}

resource recordingsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/recordings'
  properties: {
    publicAccess: 'None'
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// App Service Plan (Consumption)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: false
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
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
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionRuntime
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~${functionRuntimeVersion}'
        }
        {
          name: 'ACS_CONNECTION_STRING'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=AcsConnectionString)'
        }
        {
          name: 'FLUID_RELAY_KEY'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=FluidRelayKey)'
        }
        {
          name: 'FLUID_ENDPOINT'
          value: fluidRelayService.properties.fluidRelayEndpoints.ordererEndpoints[0]
        }
        {
          name: 'FLUID_TENANT'
          value: fluidRelayService.properties.frsTenantId
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
      ]
      cors: enableCors ? {
        allowedOrigins: corsOrigins
        supportCredentials: false
      } : null
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      netFrameworkVersion: 'v6.0'
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

// Key Vault Secrets
resource acsConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'AcsConnectionString'
  properties: {
    value: communicationService.listKeys().primaryConnectionString
  }
}

resource fluidRelayKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'FluidRelayKey'
  properties: {
    value: fluidRelayService.listKeys().primaryKey
  }
}

// Role Assignments
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, functionApp.id, 'Key Vault Secrets User')
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalType: 'ServicePrincipal'
  }
}

resource storageBlobDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionApp.id, 'Storage Blob Data Contributor')
  properties: {
    principalId: functionApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('Azure Communication Services connection string')
output acsConnectionString string = communicationService.listKeys().primaryConnectionString

@description('Azure Communication Services resource name')
output acsResourceName string = communicationService.name

@description('Fluid Relay service endpoint')
output fluidRelayEndpoint string = fluidRelayService.properties.fluidRelayEndpoints.ordererEndpoints[0]

@description('Fluid Relay tenant ID')
output fluidRelayTenantId string = fluidRelayService.properties.frsTenantId

@description('Fluid Relay primary key')
output fluidRelayPrimaryKey string = fluidRelayService.listKeys().primaryKey

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Function App principal ID for additional role assignments')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('Token generation endpoint URL')
output tokenEndpointUrl string = 'https://${functionApp.properties.defaultHostName}/api/GetAcsToken'