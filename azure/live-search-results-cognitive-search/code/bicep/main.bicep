@description('The name of the solution deployment')
param solutionName string = 'realtimesearch'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('The SKU for the Cognitive Search service')
@allowed(['basic', 'standard', 'standard2', 'standard3'])
param searchServiceSku string = 'basic'

@description('The SKU for the SignalR service')
@allowed(['Free_F1', 'Standard_S1'])
param signalRSku string = 'Standard_S1'

@description('The number of SignalR service units')
@minValue(1)
@maxValue(100)
param signalRUnits int = 1

@description('The Cosmos DB consistency level')
@allowed(['Eventual', 'ConsistentPrefix', 'Session', 'BoundedStaleness', 'Strong'])
param cosmosDbConsistencyLevel string = 'Session'

@description('The Cosmos DB throughput in RU/s')
@minValue(400)
@maxValue(1000000)
param cosmosDbThroughput int = 400

@description('Tags to apply to all resources')
param tags object = {
  environment: environment
  solution: 'real-time-search'
  'managed-by': 'bicep'
}

// Generate unique resource names with random suffix
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var searchServiceName = 'search-${solutionName}-${environment}-${uniqueSuffix}'
var signalRServiceName = 'signalr-${solutionName}-${environment}-${uniqueSuffix}'
var storageAccountName = 'st${solutionName}${environment}${uniqueSuffix}'
var functionAppName = 'func-${solutionName}-${environment}-${uniqueSuffix}'
var eventGridTopicName = 'topic-${solutionName}-${environment}-${uniqueSuffix}'
var cosmosAccountName = 'cosmos-${solutionName}-${environment}-${uniqueSuffix}'
var appServicePlanName = 'plan-${solutionName}-${environment}-${uniqueSuffix}'
var applicationInsightsName = 'ai-${solutionName}-${environment}-${uniqueSuffix}'

// Storage Account for Function App
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
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Allow'
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
    Request_Source: 'rest'
    RetentionInDays: 90
  }
}

// App Service Plan for Function App
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

// Azure Cognitive Search Service
resource searchService 'Microsoft.Search/searchServices@2023-11-01' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: {
    name: searchServiceSku
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    networkRuleSet: {
      ipRules: []
    }
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    disableLocalAuth: false
    authOptions: {
      apiKeyOnly: {}
    }
  }
}

// Azure SignalR Service
resource signalRService 'Microsoft.SignalRService/signalR@2023-02-01' = {
  name: signalRServiceName
  location: location
  tags: tags
  sku: {
    name: signalRSku
    capacity: signalRUnits
  }
  kind: 'SignalR'
  properties: {
    features: [
      {
        flag: 'ServiceMode'
        value: 'Serverless'
      }
      {
        flag: 'EnableConnectivityLogs'
        value: 'true'
      }
      {
        flag: 'EnableMessagingLogs'
        value: 'true'
      }
    ]
    cors: {
      allowedOrigins: ['*']
    }
    networkACLs: {
      defaultAction: 'Allow'
    }
  }
}

// Azure Cosmos DB Account
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: cosmosDbConsistencyLevel
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    capabilities: []
    publicNetworkAccess: 'Enabled'
    networkAclBypass: 'None'
    disableKeyBasedMetadataWriteAccess: false
    enableFreeTier: false
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Local'
      }
    }
  }
}

// Cosmos DB Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  name: 'SearchDatabase'
  parent: cosmosAccount
  properties: {
    resource: {
      id: 'SearchDatabase'
    }
  }
}

// Cosmos DB Container
resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  name: 'Products'
  parent: cosmosDatabase
  properties: {
    resource: {
      id: 'Products'
      partitionKey: {
        paths: ['/category']
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
      defaultTtl: -1
    }
    options: {
      throughput: cosmosDbThroughput
    }
  }
}

// Event Grid Topic
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: tags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
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
          value: '~18'
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
          name: 'SearchEndpoint'
          value: 'https://${searchService.name}.search.windows.net'
        }
        {
          name: 'SearchAdminKey'
          value: searchService.listAdminKeys().primaryKey
        }
        {
          name: 'SignalRConnection'
          value: signalRService.listKeys().primaryConnectionString
        }
        {
          name: 'CosmosDBConnection'
          value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
        {
          name: 'EventGridEndpoint'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EventGridKey'
          value: eventGridTopic.listKeys().key1
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: ['*']
      }
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
  dependsOn: [
    storageAccount
    applicationInsights
    searchService
    signalRService
    cosmosAccount
    eventGridTopic
  ]
}

// Event Grid Subscription for Search Index Updates
resource eventGridSubscription 'Microsoft.EventGrid/topics/eventSubscriptions@2023-12-15-preview' = {
  name: 'search-notification-sub'
  parent: eventGridTopic
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/NotificationFunction'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: ['SearchIndexUpdated']
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
    deadLetterDestination: {
      endpointType: 'StorageBlob'
      properties: {
        resourceId: storageAccount.id
        blobContainerName: 'deadletter'
      }
    }
  }
  dependsOn: [
    functionApp
  ]
}

// Outputs for verification and integration
@description('The name of the Cognitive Search service')
output searchServiceName string = searchService.name

@description('The endpoint URL of the Cognitive Search service')
output searchServiceEndpoint string = 'https://${searchService.name}.search.windows.net'

@description('The name of the SignalR service')
output signalRServiceName string = signalRService.name

@description('The hostname of the SignalR service')
output signalRServiceHostname string = signalRService.properties.hostName

@description('The name of the Cosmos DB account')
output cosmosAccountName string = cosmosAccount.name

@description('The endpoint URL of the Cosmos DB account')
output cosmosAccountEndpoint string = cosmosAccount.properties.documentEndpoint

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The name of the Event Grid topic')
output eventGridTopicName string = eventGridTopic.name

@description('The endpoint URL of the Event Grid topic')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The name of the Application Insights component')
output applicationInsightsName string = applicationInsights.name

@description('Resource group location')
output resourceGroupLocation string = location

@description('Unique suffix used for resource naming')
output uniqueSuffix string = uniqueSuffix