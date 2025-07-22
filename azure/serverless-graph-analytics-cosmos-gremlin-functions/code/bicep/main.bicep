// Main Bicep template for Serverless Graph Analytics with Azure Cosmos DB for Apache Gremlin and Azure Functions
// This template deploys a complete serverless graph analytics solution

@description('The name prefix for all resources')
param namePrefix string = 'graph'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('The environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('The Cosmos DB consistency level')
@allowed(['Eventual', 'ConsistentPrefix', 'Session', 'BoundedStaleness', 'Strong'])
param cosmosDbConsistencyLevel string = 'Session'

@description('The initial throughput for the graph container (RU/s)')
@minValue(400)
@maxValue(100000)
param graphThroughput int = 400

@description('Enable automatic failover for Cosmos DB')
param enableAutomaticFailover bool = false

@description('The Node.js version for the Function App')
@allowed(['16', '18', '20'])
param nodeVersion string = '18'

@description('Application Insights workspace retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 90

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'graph-analytics'
  environment: environment
  managedBy: 'bicep'
}

// Generate unique suffix for resource names
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var cosmosAccountName = '${namePrefix}-cosmos-${uniqueSuffix}'
var functionAppName = '${namePrefix}-func-${uniqueSuffix}'
var storageAccountName = '${namePrefix}st${uniqueSuffix}'
var eventGridTopicName = '${namePrefix}-eg-${uniqueSuffix}'
var appInsightsName = '${namePrefix}-ai-${uniqueSuffix}'
var logAnalyticsName = '${namePrefix}-la-${uniqueSuffix}'
var appServicePlanName = '${namePrefix}-asp-${uniqueSuffix}'

// Database and container names
var databaseName = 'GraphAnalytics'
var graphContainerName = 'RelationshipGraph'

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for monitoring and logging
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
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

// Azure Cosmos DB Account with Gremlin API
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: cosmosDbConsistencyLevel
      maxIntervalInSeconds: 300
      maxStalenessPrefix: 100000
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: [
      {
        name: 'EnableGremlin'
      }
    ]
    enableAutomaticFailover: enableAutomaticFailover
    enableMultipleWriteLocations: false
    enableFreeTier: false
    enableAnalyticalStorage: false
    analyticalStorageConfiguration: {
      schemaType: 'WellDefined'
    }
    publicNetworkAccess: 'Enabled'
    networkAclBypass: 'None'
    disableKeyBasedMetadataWriteAccess: false
    enablePartitionMerge: false
    enableBurstCapacity: false
    minimalTlsVersion: 'Tls12'
    cors: []
    defaultIdentity: 'FirstPartyIdentity'
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

// Cosmos DB Gremlin Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases@2024-05-15' = {
  parent: cosmosDbAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

// Cosmos DB Gremlin Graph Container
resource cosmosGraphContainer 'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/graphs@2024-05-15' = {
  parent: cosmosDatabase
  name: graphContainerName
  properties: {
    resource: {
      id: graphContainerName
      partitionKey: {
        paths: ['/partitionKey']
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
            path: '/\"_etag\"/?'
          }
        ]
      }
    }
    options: {
      throughput: graphThroughput
    }
  }
}

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
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
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
  }
}

// App Service Plan for Function App (Consumption Plan)
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
    reserved: false
  }
}

// Function App for serverless graph processing
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
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
          value: '~${nodeVersion}'
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
          name: 'COSMOS_ENDPOINT'
          value: cosmosDbAccount.properties.documentEndpoint
        }
        {
          name: 'COSMOS_KEY'
          value: cosmosDbAccount.listKeys().primaryMasterKey
        }
        {
          name: 'DATABASE_NAME'
          value: databaseName
        }
        {
          name: 'GRAPH_NAME'
          value: graphContainerName
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
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
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
  }
  dependsOn: [
    storageAccount
    appServicePlan
    applicationInsights
  ]
}

// Event Grid Topic for event distribution
resource eventGridTopic 'Microsoft.EventGrid/topics@2024-06-01-preview' = {
  name: eventGridTopicName
  location: location
  tags: tags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    dataResidencyBoundary: 'WithinRegion'
  }
}

// Event Grid Subscription for GraphWriter Function
resource eventGridSubscription 'Microsoft.EventGrid/topics/eventSubscriptions@2024-06-01-preview' = {
  parent: eventGridTopic
  name: 'graph-writer-subscription'
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/GraphWriter'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: ['GraphDataEvent']
      enableAdvancedFilteringOnArrays: true
    }
    labels: []
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
    deadLetterDestination: {
      endpointType: 'StorageBlob'
      properties: {
        resourceId: storageAccount.id
        blobContainerName: 'deadletters'
      }
    }
  }
}

// Outputs for reference and integration
@description('The name of the Cosmos DB account')
output cosmosDbAccountName string = cosmosDbAccount.name

@description('The endpoint URL for the Cosmos DB account')
output cosmosDbEndpoint string = cosmosDbAccount.properties.documentEndpoint

@description('The name of the graph database')
output databaseName string = databaseName

@description('The name of the graph container')
output graphContainerName string = graphContainerName

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The hostname of the Function App')
output functionAppHostName string = functionApp.properties.defaultHostName

@description('The name of the Event Grid topic')
output eventGridTopicName string = eventGridTopic.name

@description('The endpoint URL for the Event Grid topic')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('The name of the Application Insights component')
output applicationInsightsName string = applicationInsights.name

@description('The instrumentation key for Application Insights')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The connection string for Application Insights')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('Sample Gremlin queries to test the solution')
output sampleGremlinQueries array = [
  'g.V().count() // Count all vertices'
  'g.V().hasLabel(\'person\').values(\'name\') // Get all person names'
  'g.V(\'user1\').out().values(\'name\') // Get friends of user1'
  'g.V().hasLabel(\'person\').outE().inV().path() // Show relationship paths'
]

@description('Test event JSON structure for Event Grid')
output testEventStructure object = {
  id: 'unique-event-id'
  eventType: 'GraphDataEvent'
  subject: 'users/relationships'
  eventTime: '2025-01-XX TXX:XX:XXZ'
  data: {
    action: 'addVertex'
    vertex: {
      id: 'user1'
      label: 'person'
      partitionKey: 'user1'
      properties: {
        name: 'Alice'
        age: 30
      }
    }
  }
  dataVersion: '1.0'
}