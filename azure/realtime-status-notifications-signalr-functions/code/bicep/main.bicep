@description('The name prefix for all resources. This will be used to generate unique resource names.')
param namePrefix string = 'signalr'

@description('The Azure region where resources will be deployed.')
param location string = resourceGroup().location

@description('The SKU name for SignalR Service. Use Free_F1 for development or Standard_S1 for production.')
@allowed([
  'Free_F1'
  'Standard_S1'
])
param signalRSkuName string = 'Free_F1'

@description('The capacity (number of units) for SignalR Service.')
@minValue(1)
@maxValue(100)
param signalRCapacity int = 1

@description('The service mode for SignalR Service. Serverless mode is required for Azure Functions integration.')
@allowed([
  'Default'
  'Serverless'
  'Classic'
])
param signalRServiceMode string = 'Serverless'

@description('The pricing tier for the Function App hosting plan.')
@allowed([
  'Y1'
  'EP1'
  'EP2'
  'EP3'
])
param functionAppSkuName string = 'Y1'

@description('The Node.js runtime version for Azure Functions.')
@allowed([
  '18'
  '20'
])
param nodeVersion string = '18'

@description('Tags to apply to all resources.')
param tags object = {
  purpose: 'recipe'
  environment: 'demo'
  solution: 'realtime-notifications'
}

@description('Enable CORS for all origins. Set to false for production and configure specific origins.')
param enableCorsForAllOrigins bool = true

@description('Specific CORS origins if enableCorsForAllOrigins is false.')
param corsOrigins array = []

// Generate unique suffix for resource names to avoid conflicts
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)

// Resource names with unique suffix
var signalRName = '${namePrefix}-signalr-${uniqueSuffix}'
var functionAppName = '${namePrefix}-func-${uniqueSuffix}'
var storageAccountName = '${namePrefix}storage${uniqueSuffix}'
var hostingPlanName = '${namePrefix}-plan-${uniqueSuffix}'
var applicationInsightsName = '${namePrefix}-insights-${uniqueSuffix}'
var logAnalyticsName = '${namePrefix}-logs-${uniqueSuffix}'

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
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

// Application Insights for Function App monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Storage Account for Function App (required for Azure Functions)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    encryption: {
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
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
  }
}

// Azure SignalR Service for real-time messaging
resource signalRService 'Microsoft.SignalRService/signalR@2023-02-01' = {
  name: signalRName
  location: location
  tags: tags
  sku: {
    name: signalRSkuName
    capacity: signalRCapacity
  }
  properties: {
    serviceMode: signalRServiceMode
    features: [
      {
        flag: 'ServiceMode'
        value: signalRServiceMode
        properties: {}
      }
    ]
    cors: {
      allowedOrigins: enableCorsForAllOrigins ? ['*'] : corsOrigins
    }
    upstream: {
      templates: []
    }
    networkACLs: {
      defaultAction: 'Allow'
    }
  }
}

// App Service Plan for Function App (Consumption plan for serverless)
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  sku: {
    name: functionAppSkuName
  }
  properties: {
    reserved: false
  }
}

// Function App for hosting SignalR integration functions
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: [
        // Storage account connection string (required for Functions)
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        // Function runtime settings
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
          value: '~${nodeVersion}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        // SignalR Service connection string
        {
          name: 'AzureSignalRConnectionString'
          value: signalRService.listKeys().primaryConnectionString
        }
        // Application Insights configuration
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
      ]
      cors: {
        allowedOrigins: enableCorsForAllOrigins ? ['*'] : corsOrigins
      }
      use32BitWorkerProcess: false
      netFrameworkVersion: 'v6.0'
      nodeVersion: '~${nodeVersion}'
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

// Outputs for reference and integration
@description('The name of the SignalR Service.')
output signalRServiceName string = signalRService.name

@description('The hostname of the SignalR Service.')
output signalRServiceHostname string = signalRService.properties.hostName

@description('The primary connection string for SignalR Service.')
@secure()
output signalRConnectionString string = signalRService.listKeys().primaryConnectionString

@description('The name of the Function App.')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App.')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The URL for the negotiate function endpoint.')
output negotiateEndpointUrl string = 'https://${functionApp.properties.defaultHostName}/api/negotiate'

@description('The name of the storage account used by the Function App.')
output storageAccountName string = storageAccount.name

@description('The name of the Application Insights instance.')
output applicationInsightsName string = applicationInsights.name

@description('The instrumentation key for Application Insights.')
@secure()
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The connection string for Application Insights.')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The resource group name where resources were deployed.')
output resourceGroupName string = resourceGroup().name

@description('The Azure region where resources were deployed.')
output deploymentLocation string = location