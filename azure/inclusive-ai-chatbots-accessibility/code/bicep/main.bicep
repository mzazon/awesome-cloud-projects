@description('Main Bicep template for Accessible AI-Powered Customer Service Bots with Azure Immersive Reader and Bot Framework')

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Bot name for the Azure Bot Framework registration')
param botName string = 'accessible-customer-bot'

@description('App Service Plan SKU')
@allowed(['B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1v2', 'P2v2', 'P3v2'])
param appServicePlanSku string = 'B1'

@description('Cognitive Services pricing tier')
@allowed(['F0', 'S0'])
param cognitiveServicesSku string = 'S0'

@description('LUIS authoring pricing tier')
@allowed(['F0', 'S0'])
param luisAuthoringSku string = 'F0'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Premium_LRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Key Vault SKU')
@allowed(['standard', 'premium'])
param keyVaultSku string = 'standard'

@description('Enable Application Insights')
param enableApplicationInsights bool = true

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'accessibility-demo'
  environment: environment
  compliance: 'accessibility'
  project: 'accessible-ai-bot'
}

// Variables
var immersiveReaderName = 'immersive-reader-${resourceSuffix}'
var luisAppName = 'customer-service-luis-${resourceSuffix}'
var luisRuntimeName = '${luisAppName}-runtime'
var keyVaultName = 'kv-bot-${resourceSuffix}'
var storageAccountName = 'stbot${resourceSuffix}'
var appServicePlanName = 'asp-accessible-bot-${resourceSuffix}'
var appServiceName = 'app-accessible-bot-${resourceSuffix}'
var applicationInsightsName = 'ai-accessible-bot-${resourceSuffix}'
var botAppName = '${botName}-${resourceSuffix}'

// Validate Key Vault name length (must be 3-24 characters)
var keyVaultNameValidated = length(keyVaultName) > 24 ? substring(keyVaultName, 0, 24) : keyVaultName

// Validate storage account name (must be 3-24 characters, lowercase, alphanumeric only)
var storageAccountNameValidated = length(storageAccountName) > 24 ? substring(storageAccountName, 0, 24) : storageAccountName

// Azure Immersive Reader Cognitive Service
resource immersiveReaderService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: immersiveReaderName
  location: location
  kind: 'ImmersiveReader'
  sku: {
    name: cognitiveServicesSku
  }
  properties: {
    customSubDomainName: immersiveReaderName
    publicNetworkAccess: 'Enabled'
  }
  tags: union(tags, {
    service: 'immersive-reader'
  })
}

// LUIS Authoring Resource
resource luisAuthoringService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: luisAppName
  location: location
  kind: 'LUIS.Authoring'
  sku: {
    name: luisAuthoringSku
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
  tags: union(tags, {
    service: 'luis-authoring'
  })
}

// LUIS Runtime Resource
resource luisRuntimeService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: luisRuntimeName
  location: location
  kind: 'LUIS'
  sku: {
    name: cognitiveServicesSku
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
  tags: union(tags, {
    service: 'luis-runtime'
  })
}

// Storage Account for Bot State Management
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountNameValidated
  location: location
  kind: 'StorageV2'
  sku: {
    name: storageAccountSku
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
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
      bypass: 'AzureServices'
    }
  }
  tags: union(tags, {
    service: 'storage'
  })
}

// Key Vault for Secure Configuration Management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultNameValidated
  location: location
  properties: {
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    tenantId: subscription().tenantId
    enabledForDeployment: false
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableRbacAuthorization: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    accessPolicies: []
  }
  tags: union(tags, {
    service: 'key-vault'
  })
}

// Application Insights for Monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    Request_Source: 'rest'
    RetentionInDays: 90
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: union(tags, {
    service: 'application-insights'
  })
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  sku: {
    name: appServicePlanSku
  }
  properties: {
    reserved: true
  }
  tags: union(tags, {
    service: 'app-service-plan'
  })
}

// App Service Web App
resource appService 'Microsoft.Web/sites@2023-01-01' = {
  name: appServiceName
  location: location
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|18-lts'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      appSettings: [
        {
          name: 'NODE_ENV'
          value: 'production'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '18-lts'
        }
        {
          name: 'MicrosoftAppId'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultNameValidated};SecretName=BotAppId)'
        }
        {
          name: 'ImmersiveReaderKey'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultNameValidated};SecretName=ImmersiveReaderKey)'
        }
        {
          name: 'ImmersiveReaderEndpoint'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultNameValidated};SecretName=ImmersiveReaderEndpoint)'
        }
        {
          name: 'LuisAuthoringKey'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultNameValidated};SecretName=LuisAuthoringKey)'
        }
        {
          name: 'LuisAuthoringEndpoint'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultNameValidated};SecretName=LuisAuthoringEndpoint)'
        }
        {
          name: 'StorageConnectionString'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultNameValidated};SecretName=StorageConnectionString)'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
      ]
    }
  }
  tags: union(tags, {
    service: 'app-service'
  })
}

// Key Vault Access Policy for App Service
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: appService.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
  }
}

// Bot Framework Registration
resource botService 'Microsoft.BotService/botServices@2022-09-15' = {
  name: botAppName
  location: 'global'
  kind: 'bot'
  sku: {
    name: 'F0'
  }
  properties: {
    displayName: botAppName
    description: 'Accessible AI-powered customer service bot with Azure Immersive Reader integration'
    endpoint: 'https://${appService.properties.defaultHostName}/api/messages'
    msaAppId: botRegistration.properties.appId
    msaAppType: 'UserAssignedMSI'
    msaAppMSIResourceId: botRegistration.id
    luisAppIds: []
    luisKey: ''
    isCmekEnabled: false
    publicNetworkAccess: 'Enabled'
    isStreamingSupported: false
    isDeveloperAppInsightsApiKeySet: false
    schemaTransformationVersion: '1.3'
  }
  tags: union(tags, {
    service: 'bot-framework'
  })
}

// Bot Registration (App Registration)
resource botRegistration 'Microsoft.BotService/botServices@2022-09-15' = {
  name: '${botAppName}-registration'
  location: 'global'
  kind: 'registration'
  sku: {
    name: 'F0'
  }
  properties: {
    displayName: '${botAppName} Registration'
    description: 'Bot registration for accessible customer service bot'
    endpoint: 'https://${appService.properties.defaultHostName}/api/messages'
    msaAppType: 'UserAssignedMSI'
    isCmekEnabled: false
    publicNetworkAccess: 'Enabled'
    isStreamingSupported: false
    isDeveloperAppInsightsApiKeySet: false
    schemaTransformationVersion: '1.3'
  }
  tags: union(tags, {
    service: 'bot-registration'
  })
}

// Key Vault Secrets
resource immersiveReaderKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ImmersiveReaderKey'
  properties: {
    value: immersiveReaderService.listKeys().key1
  }
}

resource immersiveReaderEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ImmersiveReaderEndpoint'
  properties: {
    value: immersiveReaderService.properties.endpoint
  }
}

resource luisAuthoringKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'LuisAuthoringKey'
  properties: {
    value: luisAuthoringService.listKeys().key1
  }
}

resource luisAuthoringEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'LuisAuthoringEndpoint'
  properties: {
    value: luisAuthoringService.properties.endpoint
  }
}

resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'StorageConnectionString'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
  }
}

resource botAppIdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'BotAppId'
  properties: {
    value: botRegistration.properties.appId
  }
}

// Outputs
@description('The resource group name where all resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('The location where resources were deployed')
output location string = location

@description('The Azure Immersive Reader service name')
output immersiveReaderName string = immersiveReaderService.name

@description('The Azure Immersive Reader endpoint')
output immersiveReaderEndpoint string = immersiveReaderService.properties.endpoint

@description('The LUIS authoring service name')
output luisAuthoringName string = luisAuthoringService.name

@description('The LUIS authoring endpoint')
output luisAuthoringEndpoint string = luisAuthoringService.properties.endpoint

@description('The LUIS runtime service name')
output luisRuntimeName string = luisRuntimeService.name

@description('The Key Vault name')
output keyVaultName string = keyVault.name

@description('The Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The storage account name')
output storageAccountName string = storageAccount.name

@description('The App Service Plan name')
output appServicePlanName string = appServicePlan.name

@description('The App Service name')
output appServiceName string = appService.name

@description('The App Service default hostname')
output appServiceUrl string = 'https://${appService.properties.defaultHostName}'

@description('The Bot Framework service name')
output botServiceName string = botService.name

@description('The Bot Framework registration name')
output botRegistrationName string = botRegistration.name

@description('The Bot Application ID')
output botAppId string = botRegistration.properties.appId

@description('The Bot endpoint URL')
output botEndpoint string = 'https://${appService.properties.defaultHostName}/api/messages'

@description('The Application Insights name (if enabled)')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''

@description('The Application Insights instrumentation key (if enabled)')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Resource deployment summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  environment: environment
  botName: botService.name
  botEndpoint: 'https://${appService.properties.defaultHostName}/api/messages'
  keyVaultName: keyVault.name
  immersiveReaderName: immersiveReaderService.name
  storageAccountName: storageAccount.name
  appServiceName: appService.name
  applicationInsightsEnabled: enableApplicationInsights
}