// Main Bicep template for Serverless Event Processing Pipeline with Auto-Scaling
// This template creates a serverless event processing pipeline with automatic scaling

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, test, prod)')
param environment string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Event Hubs namespace SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param eventHubsSkuName string = 'Basic'

@description('Event Hubs namespace capacity (throughput units)')
@minValue(1)
@maxValue(20)
param eventHubsCapacity int = 1

@description('Event Hub partition count for parallel processing')
@minValue(1)
@maxValue(32)
param eventHubPartitionCount int = 4

@description('Event Hub message retention in days')
@minValue(1)
@maxValue(7)
param eventHubMessageRetentionDays int = 1

@description('Function App runtime stack')
@allowed([
  'node'
  'python'
  'dotnet'
  'java'
])
param functionAppRuntime string = 'node'

@description('Function App runtime version')
param functionAppRuntimeVersion string = '18'

@description('Storage account SKU for Function App')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Application Insights retention period in days')
@minValue(30)
@maxValue(730)
param appInsightsRetentionDays int = 90

@description('Resource tags to apply to all resources')
param tags object = {
  Environment: environment
  Solution: 'Real-time Data Processing'
  Recipe: 'implementing-real-time-data-processing-azure-functions-event-hubs'
}

// Generate resource names with proper Azure naming conventions
var resourceNames = {
  eventHubNamespace: 'eh-ns-${environment}-${uniqueSuffix}'
  eventHub: 'events-hub'
  functionApp: 'func-processor-${environment}-${uniqueSuffix}'
  storageAccount: 'st${environment}${uniqueSuffix}'
  appInsights: 'ai-processor-${environment}-${uniqueSuffix}'
  hostingPlan: 'plan-${environment}-${uniqueSuffix}'
  logAnalytics: 'law-${environment}-${uniqueSuffix}'
}

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: resourceNames.logAnalytics
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: appInsightsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for comprehensive monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.appInsights
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

// Storage Account for Function App runtime and checkpointing
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
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

// Event Hubs Namespace for event ingestion
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2022-10-01-preview' = {
  name: resourceNames.eventHubNamespace
  location: location
  tags: tags
  sku: {
    name: eventHubsSkuName
    tier: eventHubsSkuName
    capacity: eventHubsCapacity
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: false
    kafkaEnabled: false
  }
}

// Event Hub for receiving events
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2022-10-01-preview' = {
  parent: eventHubNamespace
  name: resourceNames.eventHub
  properties: {
    partitionCount: eventHubPartitionCount
    messageRetentionInDays: eventHubMessageRetentionDays
    status: 'Active'
    captureDescription: {
      enabled: false
    }
  }
}

// Authorization rule for Event Hub access
resource eventHubAuthRule 'Microsoft.EventHub/namespaces/authorizationRules@2022-10-01-preview' = {
  parent: eventHubNamespace
  name: 'RootManageSharedAccessKey'
  properties: {
    rights: [
      'Listen'
      'Manage'
      'Send'
    ]
  }
}

// Consumer Group for Function App
resource eventHubConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2022-10-01-preview' = {
  parent: eventHub
  name: 'functionapp-consumer-group'
  properties: {
    userMetadata: 'Consumer group for Azure Functions processing'
  }
}

// App Service Plan for Function App (Consumption Plan)
resource hostingPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: resourceNames.hostingPlan
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  kind: 'functionapp'
  properties: {
    computeMode: 'Dynamic'
    reserved: false
  }
}

// Function App for event processing
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: resourceNames.functionApp
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      use32BitWorkerProcess: false
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
          value: toLower(resourceNames.functionApp)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionAppRuntime
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: functionAppRuntimeVersion == '18' ? '~18' : '~16'
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
          name: 'EventHubConnectionString'
          value: eventHubAuthRule.listKeys().primaryConnectionString
        }
        {
          name: 'EventHubName'
          value: eventHub.name
        }
        {
          name: 'EventHubConsumerGroup'
          value: eventHubConsumerGroup.name
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
    }
  }
}

// Output values for validation and integration
output resourceGroupName string = resourceGroup().name
output location string = location
output eventHubNamespaceName string = eventHubNamespace.name
output eventHubName string = eventHub.name
output functionAppName string = functionApp.name
output storageAccountName string = storageAccount.name
output applicationInsightsName string = applicationInsights.name
output eventHubConnectionString string = eventHubAuthRule.listKeys().primaryConnectionString
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output eventHubNamespaceEndpoint string = eventHubNamespace.properties.serviceBusEndpoint
output storageAccountEndpoint string = storageAccount.properties.primaryEndpoints.blob
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output tags object = tags