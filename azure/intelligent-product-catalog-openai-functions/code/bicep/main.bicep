@description('Deploys an intelligent product catalog system using Azure Functions, OpenAI Service, and Blob Storage')

// Parameters
@description('Environment name (dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('OpenAI model deployment name')
param openAiModelDeployment string = 'gpt-4o-deployment'

@description('OpenAI model name')
param openAiModelName string = 'gpt-4o'

@description('OpenAI model version')
param openAiModelVersion string = '2024-11-20'

@description('OpenAI SKU capacity')
@minValue(1)
@maxValue(100)
param openAiSkuCapacity int = 1

@description('Storage account access tier')
@allowed([
  'Hot'
  'Cool'
])
param storageAccessTier string = 'Hot'

@description('Function App runtime version')
param functionsRuntimeVersion string = '~4'

@description('Python runtime version')
param pythonVersion string = '3.11'

@description('Enable Application Insights')
param enableApplicationInsights bool = true

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'recipe'
  environment: environment
  solution: 'intelligent-product-catalog'
}

// Variables
var resourcePrefix = 'catalog-${environment}-${uniqueSuffix}'
var storageAccountName = 'st${replace(resourcePrefix, '-', '')}'
var functionAppName = 'func-${resourcePrefix}'
var openAiAccountName = 'openai-${resourcePrefix}'
var appInsightsName = 'appi-${resourcePrefix}'
var logAnalyticsName = 'law-${resourcePrefix}'
var appServicePlanName = 'asp-${resourcePrefix}'

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: storageAccessTier
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
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

// Blob Service
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
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
  }
}

// Product Images Container
resource productImagesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'product-images'
  properties: {
    publicAccess: 'None'
    metadata: {
      description: 'Container for uploaded product images'
    }
  }
}

// Catalog Results Container
resource catalogResultsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'catalog-results'
  properties: {
    publicAccess: 'None'
    metadata: {
      description: 'Container for generated product catalog data'
    }
  }
}

// Log Analytics Workspace (for Application Insights)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableApplicationInsights) {
  name: logAnalyticsName
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

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Azure OpenAI Service
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openAiAccountName
  location: location
  tags: tags
  sku: {
    name: 'S0'
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openAiAccountName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    disableLocalAuth: false
  }
}

// GPT-4o Model Deployment
resource gpt4oDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAiAccount
  name: openAiModelDeployment
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiModelName
      version: openAiModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'Standard'
    capacity: openAiSkuCapacity
  }
}

// App Service Plan (Consumption plan for Functions)
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
    reserved: true // Linux
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
    reserved: true
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'Python|${pythonVersion}'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
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
          value: functionsRuntimeVersion
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'AZURE_OPENAI_ENDPOINT'
          value: openAiAccount.properties.endpoint
        }
        {
          name: 'AZURE_OPENAI_KEY'
          value: openAiAccount.listKeys().key1
        }
        {
          name: 'AZURE_OPENAI_DEPLOYMENT'
          value: openAiModelDeployment
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_Mode'
          value: 'Recommended'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
    }
  }
  dependsOn: [
    gpt4oDeployment
  ]
}

// Outputs
@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('Storage Account Connection String')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('Product Images Container Name')
output productImagesContainer string = productImagesContainer.name

@description('Catalog Results Container Name')
output catalogResultsContainer string = catalogResultsContainer.name

@description('Function App Name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('OpenAI Account Name')
output openAiAccountName string = openAiAccount.name

@description('OpenAI Endpoint')
output openAiEndpoint string = openAiAccount.properties.endpoint

@description('OpenAI Model Deployment Name')
output openAiModelDeployment string = gpt4oDeployment.name

@description('Application Insights Name')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = enableApplicationInsights ? logAnalyticsWorkspace.name : ''

@description('Deployment Summary')
output deploymentSummary object = {
  environment: environment
  location: location
  resourcePrefix: resourcePrefix
  storageAccount: storageAccount.name
  functionApp: functionApp.name
  openAiAccount: openAiAccount.name
  modelDeployment: gpt4oDeployment.name
  containers: [
    productImagesContainer.name
    catalogResultsContainer.name
  ]
  applicationInsights: enableApplicationInsights ? applicationInsights.name : 'disabled'
}