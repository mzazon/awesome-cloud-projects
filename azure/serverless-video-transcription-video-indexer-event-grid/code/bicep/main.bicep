@description('Location for all resources')
param location string = resourceGroup().location

@description('Prefix for resource naming')
param resourcePrefix string = 'video'

@description('Environment suffix for resource naming')
param environmentSuffix string = uniqueString(resourceGroup().id)

@description('Storage account access tier')
@allowed(['Hot', 'Cool'])
param storageAccessTier string = 'Hot'

@description('Storage account replication type')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageReplicationType string = 'Standard_LRS'

@description('Function App runtime stack')
@allowed(['node', 'dotnet', 'python'])
param functionAppRuntime string = 'node'

@description('Function App runtime version')
param functionAppRuntimeVersion string = '18'

@description('Cosmos DB consistency level')
@allowed(['Session', 'Eventual', 'Strong', 'BoundedStaleness', 'ConsistentPrefix'])
param cosmosDbConsistencyLevel string = 'Session'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'video-transcription'
  environment: 'demo'
  recipe: 'serverless-video-indexer'
}

// Variables for resource names
var storageAccountName = '${resourcePrefix}st${environmentSuffix}'
var functionAppName = '${resourcePrefix}-func-${environmentSuffix}'
var cosmosAccountName = '${resourcePrefix}-cosmos-${environmentSuffix}'
var eventGridTopicName = '${resourcePrefix}-eg-${environmentSuffix}'
var appServicePlanName = '${resourcePrefix}-plan-${environmentSuffix}'
var applicationInsightsName = '${resourcePrefix}-ai-${environmentSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-law-${environmentSuffix}'

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
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
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Storage Account for videos and function app
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageReplicationType
  }
  kind: 'StorageV2'
  properties: {
    accessTier: storageAccessTier
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

// Blob Services for the storage account
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
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

// Container for video uploads
resource videosContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'videos'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'video-uploads'
    }
  }
}

// Container for analysis results
resource resultsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'results'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'analysis-results'
    }
  }
}

// Cosmos DB Account with serverless capacity
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: cosmosDbConsistencyLevel
      maxIntervalInSeconds: 300
      maxStalenessPrefix: 100000
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    isVirtualNetworkFilterEnabled: false
    virtualNetworkRules: []
    ipRules: []
    enableFreeTier: false
    encryption: {
      isEncryptionAtRestEnabled: true
    }
  }
}

// Cosmos DB SQL Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosAccount
  name: 'VideoAnalytics'
  properties: {
    resource: {
      id: 'VideoAnalytics'
    }
  }
}

// Cosmos DB SQL Container for video metadata
resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDatabase
  name: 'VideoMetadata'
  properties: {
    resource: {
      id: 'VideoMetadata'
      partitionKey: {
        paths: ['/videoId']
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
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
    }
  }
}

// Event Grid Topic for custom events
resource eventGridTopic 'Microsoft.EventGrid/topics@2022-06-15' = {
  name: eventGridTopicName
  location: location
  tags: tags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
  }
}

// App Service Plan for Function App (Consumption plan)
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
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
    reserved: false
  }
}

// Function App for processing logic
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
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
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionAppRuntime
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~${functionAppRuntimeVersion}'
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
          name: 'STORAGE_CONNECTION'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'COSMOS_CONNECTION'
          value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
        {
          name: 'EVENT_GRID_TOPIC_ENDPOINT'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EVENT_GRID_TOPIC_KEY'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'VI_LOCATION'
          value: location
        }
      ]
      cors: {
        allowedOrigins: ['https://portal.azure.com']
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
    redundancyMode: 'None'
  }
}

// System-assigned managed identity for Function App
resource functionAppIdentity 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: functionApp
  name: 'web'
  properties: {
    managedServiceIdentityId: functionApp.identity.principalId
  }
}

// Event Grid Subscription for blob created events
resource blobEventSubscription 'Microsoft.EventGrid/eventSubscriptions@2022-06-15' = {
  scope: storageAccount
  name: 'video-upload-subscription'
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/ProcessVideoUpload'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      subjectBeginsWith: '/blobServices/default/containers/videos/'
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      enableAdvancedFilteringOnArrays: true
    }
    labels: [
      'video-processing'
    ]
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
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
    videosContainer
  ]
}

// Event Grid Subscription for Video Indexer completion events
resource videoIndexerEventSubscription 'Microsoft.EventGrid/eventSubscriptions@2022-06-15' = {
  scope: eventGridTopic
  name: 'video-results-subscription'
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/ProcessVideoResults'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Media.VideoIndexerProcessingCompleted'
      ]
      enableAdvancedFilteringOnArrays: true
    }
    labels: [
      'video-results'
    ]
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
  }
}

// Outputs for verification and integration
@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Storage Account connection string')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App hostname')
output functionAppHostName string = functionApp.properties.defaultHostName

@description('Cosmos DB account name')
output cosmosAccountName string = cosmosAccount.name

@description('Cosmos DB connection string')
output cosmosConnectionString string = cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString

@description('Event Grid Topic name')
output eventGridTopicName string = eventGridTopic.name

@description('Event Grid Topic endpoint')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('Event Grid Topic access key')
output eventGridTopicKey string = eventGridTopic.listKeys().key1

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Videos container URL')
output videosContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}videos'

@description('Results container URL')
output resultsContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}results'

@description('Resource Group location')
output location string = location

@description('Environment suffix used for naming')
output environmentSuffix string = environmentSuffix