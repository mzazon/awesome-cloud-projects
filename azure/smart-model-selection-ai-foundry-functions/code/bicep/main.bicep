// Smart Model Selection with AI Foundry and Functions
// This Bicep template deploys an intelligent model selection system using Azure AI Foundry's Model Router
// to automatically choose the optimal AI model for each request based on complexity and cost considerations.

@description('Location for all resources. Must be East US 2 or Sweden Central for Model Router support.')
@allowed([
  'eastus2'
  'swedencentral'
])
param location string = 'eastus2'

@description('Base name for all resources. Resources will be named with this prefix plus a suffix.')
@minLength(3)
@maxLength(10)
param baseName string = 'smartmodel'

@description('Unique suffix for resource names to ensure global uniqueness.')
@minLength(3)
@maxLength(6)
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment tag for all resources.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Azure AI Services SKU.')
@allowed([
  'S0'
  'S1'
  'S2'
])
param cognitiveServicesSku string = 'S0'

@description('Model Router deployment capacity.')
@minValue(1)
@maxValue(100)
param modelRouterCapacity int = 10

@description('Storage account SKU.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Function App runtime version.')
@allowed([
  '3.9'
  '3.10'
  '3.11'
])
param pythonVersion string = '3.11'

@description('Tags to be applied to all resources.')
param tags object = {
  purpose: 'smart-model-selection'
  environment: environment
  recipe: 'ai-foundry-functions'
}

// Variables for consistent naming
var aiServicesName = '${baseName}ai${uniqueSuffix}'
var functionAppName = '${baseName}func${uniqueSuffix}'
var storageAccountName = '${baseName}stor${uniqueSuffix}' // Must be lowercase and alphanumeric only
var appInsightsName = '${baseName}insights${uniqueSuffix}'
var hostingPlanName = '${baseName}plan${uniqueSuffix}'
var modelRouterDeploymentName = 'model-router'

// Storage Account for Function App and Analytics
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Azure AI Services for Model Router
resource cognitiveServices 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: aiServicesName
  location: location
  tags: tags
  sku: {
    name: cognitiveServicesSku
  }
  kind: 'AIServices'
  properties: {
    customSubDomainName: aiServicesName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    disableLocalAuth: false
  }
}

// Model Router Deployment
resource modelRouterDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: cognitiveServices
  name: modelRouterDeploymentName
  properties: {
    model: {
      format: 'OpenAI'
      name: 'model-router'
      version: '2025-05-19'
    }
    sku: {
      name: 'GlobalStandard'
      capacity: modelRouterCapacity
    }
  }
}

// Application Insights for monitoring
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 90
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${baseName}logs${uniqueSuffix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Consumption Plan for Azure Functions
resource hostingPlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {}
}

// Function App for smart model selection
resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
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
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'WEBSITE_PYTHON_DEFAULT_VERSION'
          value: pythonVersion
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'AI_FOUNDRY_ENDPOINT'
          value: cognitiveServices.properties.endpoint
        }
        {
          name: 'AI_FOUNDRY_KEY'
          value: cognitiveServices.listKeys().key1
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
      ]
      pythonVersion: pythonVersion
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
  dependsOn: [
    modelRouterDeployment
  ]
}

// Storage Tables for analytics (created via deployment script)
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${baseName}tables${uniqueSuffix}'
  location: location
  tags: tags
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.60.0'
    retentionInterval: 'PT1H'
    scriptContent: '''
      # Create storage tables for analytics
      az storage table create --name "modelmetrics" --connection-string "$STORAGE_CONNECTION_STRING" --output none
      az storage table create --name "costtracking" --connection-string "$STORAGE_CONNECTION_STRING" --output none
      echo "Storage tables created successfully"
    '''
    environmentVariables: [
      {
        name: 'STORAGE_CONNECTION_STRING'
        value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
      }
    ]
  }
  dependsOn: [
    storageAccount
  ]
}

// Outputs for verification and integration
output resourceGroupName string = resourceGroup().name
output location string = location
output aiServicesName string = cognitiveServices.name
output aiServicesEndpoint string = cognitiveServices.properties.endpoint
output modelRouterDeploymentName string = modelRouterDeployment.name
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output storageAccountName string = storageAccount.name
output appInsightsName string = appInsights.name
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString

// Outputs for connection strings (use carefully in production)
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
output aiServicesKey string = cognitiveServices.listKeys().key1