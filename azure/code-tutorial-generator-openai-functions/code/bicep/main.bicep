// Azure Bicep template for Code Tutorial Generator with OpenAI and Functions
// This template deploys a serverless tutorial generation system using Azure OpenAI, Functions, and Blob Storage

@description('Specifies the Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment designation for resource naming (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Name of the Azure OpenAI model deployment')
param openAiModelName string = 'gpt-4o-mini'

@description('Version of the Azure OpenAI model')
param openAiModelVersion string = '2024-07-18'

@description('Capacity for the Azure OpenAI model deployment')
param openAiModelCapacity int = 10

@description('SKU for the Azure OpenAI service')
@allowed(['S0'])
param openAiSku string = 'S0'

@description('SKU for the storage account')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageSku string = 'Standard_LRS'

@description('Access tier for blob storage')
@allowed(['Hot', 'Cool'])
param storageAccessTier string = 'Hot'

@description('Runtime version for Azure Functions')
param functionsRuntimeVersion string = '4'

@description('Python version for Azure Functions')
param functionsPythonVersion string = '3.11'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'recipe'
  environment: environment
  project: 'tutorial-generator'
}

// Variables for resource naming
var storageAccountName = 'tutorialstorage${uniqueSuffix}'
var functionAppName = 'tutorial-generator-${uniqueSuffix}'
var openAiAccountName = 'tutorial-openai-${uniqueSuffix}'
var appServicePlanName = 'asp-tutorial-${uniqueSuffix}'
var applicationInsightsName = 'ai-tutorial-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-tutorial-${uniqueSuffix}'

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for tutorial content and function app
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: storageAccessTier
  }
}

// Blob Services configuration
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    changeFeed: {
      enabled: false
    }
    restorePolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: true
      days: 7
    }
  }
}

// Container for tutorial content (public read access)
resource tutorialsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'tutorials'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'Blob'
  }
}

// Container for metadata (private access)
resource metadataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'metadata'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Azure OpenAI Service
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openAiAccountName
  location: location
  tags: tags
  sku: {
    name: openAiSku
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openAiAccountName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    apiProperties: {
      statisticsEnabled: false
    }
  }
}

// OpenAI Model Deployment
resource openAiModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAiAccount
  name: openAiModelName
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiModelName
      version: openAiModelVersion
    }
  }
  sku: {
    name: 'Standard'
    capacity: openAiModelCapacity
  }
}

// App Service Plan for Functions (Consumption Plan)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    computeMode: 'Dynamic'
    reserved: true
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'Python|${functionsPythonVersion}'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~${functionsRuntimeVersion}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
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
          name: 'OPENAI_ENDPOINT'
          value: openAiAccount.properties.endpoint
        }
        {
          name: 'OPENAI_KEY'
          value: openAiAccount.listKeys().key1
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'STORAGE_ACCOUNT_KEY'
          value: storageAccount.listKeys().keys[0].value
        }
        {
          name: 'DEPLOYMENT_NAME'
          value: openAiModelName
        }
      ]
      cors: {
        allowedOrigins: [
          '*'
        ]
        supportCredentials: false
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Function App Configuration for additional settings
resource functionAppConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'appsettings'
  properties: {
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    WEBSITE_CONTENTSHARE: toLower(functionAppName)
    FUNCTIONS_EXTENSION_VERSION: '~${functionsRuntimeVersion}'
    FUNCTIONS_WORKER_RUNTIME: 'python'
    APPINSIGHTS_INSTRUMENTATIONKEY: applicationInsights.properties.InstrumentationKey
    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
    OPENAI_ENDPOINT: openAiAccount.properties.endpoint
    OPENAI_KEY: openAiAccount.listKeys().key1
    STORAGE_ACCOUNT_NAME: storageAccount.name
    STORAGE_ACCOUNT_KEY: storageAccount.listKeys().keys[0].value
    DEPLOYMENT_NAME: openAiModelName
  }
}

// Outputs for reference and validation
@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The primary endpoint of the storage account')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppHostName string = functionApp.properties.defaultHostName

@description('The Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the Azure OpenAI account')
output openAiAccountName string = openAiAccount.name

@description('The endpoint of the Azure OpenAI service')
output openAiEndpoint string = openAiAccount.properties.endpoint

@description('The name of the deployed OpenAI model')
output openAiModelDeploymentName string = openAiModelDeployment.name

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Tutorial generation endpoint')
output tutorialGenerationEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/generate'

@description('Tutorial retrieval endpoint pattern')
output tutorialRetrievalEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/tutorial/{tutorial_id}'

@description('Tutorials container URL')
output tutorialsContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}tutorials/'

@description('Storage account connection string')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'