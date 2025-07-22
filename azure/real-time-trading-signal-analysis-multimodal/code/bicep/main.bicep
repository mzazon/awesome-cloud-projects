// ============================================================================
// Azure Intelligent Financial Trading Signal Analysis with AI Content Understanding
// ============================================================================
// This Bicep template deploys a comprehensive real-time trading signal analysis system
// that combines Azure AI Content Understanding with Azure Stream Analytics for 
// intelligent financial decision making.

targetScope = 'resourceGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('The base name for all resources. Will be used to generate unique names.')
@minLength(3)
@maxLength(10)
param baseName string = 'trading'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('The pricing tier for AI Services (S0 for production, F0 for development)')
@allowed(['F0', 'S0'])
param aiServicesSku string = 'S0'

@description('The SKU for Event Hubs namespace')
@allowed(['Basic', 'Standard', 'Premium'])
param eventHubsNamespaceSku string = 'Standard'

@description('The number of partitions for the main Event Hub')
@minValue(1)
@maxValue(32)
param eventHubPartitionCount int = 8

@description('The number of streaming units for Stream Analytics')
@minValue(1)
@maxValue(120)
param streamAnalyticsStreamingUnits int = 6

@description('The SKU for Service Bus namespace')
@allowed(['Basic', 'Standard', 'Premium'])
param serviceBusNamespaceSku string = 'Premium'

@description('The capacity for Service Bus Premium namespace')
@minValue(1)
@maxValue(16)
param serviceBusCapacity int = 1

@description('The SKU for Function App hosting plan')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppSku string = 'EP1'

@description('The throughput for Cosmos DB container (RU/s)')
@minValue(400)
@maxValue(100000)
param cosmosDbThroughput int = 1000

@description('The default TTL for Cosmos DB documents (in seconds)')
@minValue(60)
@maxValue(2147483647)
param cosmosDbDefaultTtl int = 604800

@description('Tags to be applied to all resources')
param tags object = {
  Environment: environment
  Application: 'TradingSignals'
  Owner: 'TradingTeam'
  CostCenter: 'QuantitativeResearch'
}

// ============================================================================
// Variables
// ============================================================================

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var resourceNames = {
  aiServices: 'ais-${baseName}-${uniqueSuffix}'
  storageAccount: 'st${baseName}${uniqueSuffix}'
  eventHubNamespace: 'ehns-${baseName}-${uniqueSuffix}'
  eventHub: 'eh-market-data'
  streamAnalyticsJob: 'saj-${baseName}-signals'
  functionApp: 'func-${baseName}-${uniqueSuffix}'
  cosmosDbAccount: 'cosmos-${baseName}-${uniqueSuffix}'
  serviceBusNamespace: 'sb-${baseName}-${uniqueSuffix}'
  applicationInsights: 'ai-${baseName}-${uniqueSuffix}'
  keyVault: 'kv-${baseName}-${uniqueSuffix}'
  logAnalytics: 'la-${baseName}-${uniqueSuffix}'
}

var storageContainers = [
  'financial-videos'
  'research-documents'
  'processed-insights'
]

var eventHubConsumerGroups = [
  'stream-analytics-consumer'
  'function-app-consumer'
  'backup-consumer'
]

// ============================================================================
// Log Analytics Workspace
// ============================================================================

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalytics
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

// ============================================================================
// Application Insights
// ============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// Key Vault
// ============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: false
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ============================================================================
// Storage Account
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    allowCrossTenantReplication: false
    defaultToOAuthAuthentication: false
    encryption: {
      requireInfrastructureEncryption: false
      keySource: 'Microsoft.Storage'
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
    }
    isHnsEnabled: false
    isNfsV3Enabled: false
    keyPolicy: {
      keyExpirationPeriodInDays: 90
    }
    largeFileSharesState: 'Disabled'
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
}

// Storage containers for different content types
resource storageContainerResources 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for containerName in storageContainers: {
  name: '${storageAccount.name}/default/${containerName}'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'financial-content-processing'
      environment: environment
    }
  }
}]

// Storage lifecycle management policy for cost optimization
resource storageLifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    policy: {
      rules: [
        {
          enabled: true
          name: 'ArchiveOldContent'
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
            }
            actions: {
              baseBlob: {
                tierToCool: {
                  daysAfterModificationGreaterThan: 30
                }
                tierToArchive: {
                  daysAfterModificationGreaterThan: 90
                }
                delete: {
                  daysAfterModificationGreaterThan: 365
                }
              }
            }
          }
        }
      ]
    }
  }
}

// ============================================================================
// Azure AI Services
// ============================================================================

resource aiServices 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: resourceNames.aiServices
  location: location
  tags: tags
  sku: {
    name: aiServicesSku
  }
  kind: 'CognitiveServices'
  properties: {
    customSubDomainName: resourceNames.aiServices
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Enabled'
    encryption: {
      keySource: 'Microsoft.CognitiveServices'
    }
    disableLocalAuth: false
    restrictOutboundNetworkAccess: false
  }
}

// ============================================================================
// Event Hubs
// ============================================================================

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-05-01-preview' = {
  name: resourceNames.eventHubNamespace
  location: location
  tags: tags
  sku: {
    name: eventHubsNamespaceSku
    tier: eventHubsNamespaceSku
    capacity: eventHubsNamespaceSku == 'Premium' ? 1 : null
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: eventHubsNamespaceSku == 'Standard' ? true : false
    maximumThroughputUnits: eventHubsNamespaceSku == 'Standard' ? 10 : null
    kafkaEnabled: true
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-05-01-preview' = {
  parent: eventHubNamespace
  name: resourceNames.eventHub
  properties: {
    messageRetentionInDays: 3
    partitionCount: eventHubPartitionCount
    status: 'Active'
    captureDescription: {
      enabled: false
    }
  }
}

// Consumer groups for different services
resource eventHubConsumerGroupResources 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-05-01-preview' = [for consumerGroup in eventHubConsumerGroups: {
  parent: eventHub
  name: consumerGroup
  properties: {
    userMetadata: 'Consumer group for ${consumerGroup}'
  }
}]

// ============================================================================
// Cosmos DB
// ============================================================================

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: resourceNames.cosmosDbAccount
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: true
    enableMultipleWriteLocations: false
    enableFreeTier: false
    enableAnalyticalStorage: false
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    publicNetworkAccess: 'Enabled'
    networkAclBypass: 'AzureServices'
    disableKeyBasedMetadataWriteAccess: false
    enablePartitionMerge: false
    minimalTlsVersion: 'Tls12'
    backup: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Local'
      }
    }
  }
}

resource cosmosDbDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosDbAccount
  name: 'TradingSignals'
  properties: {
    resource: {
      id: 'TradingSignals'
    }
  }
}

resource cosmosDbContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDbDatabase
  name: 'Signals'
  properties: {
    resource: {
      id: 'Signals'
      partitionKey: {
        paths: ['/symbol']
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
        compositeIndexes: [
          [
            {
              path: '/symbol'
              order: 'ascending'
            }
            {
              path: '/timestamp'
              order: 'descending'
            }
          ]
        ]
      }
      defaultTtl: cosmosDbDefaultTtl
      uniqueKeyPolicy: {
        uniqueKeys: []
      }
      conflictResolutionPolicy: {
        mode: 'LastWriterWins'
        conflictResolutionPath: '/_ts'
      }
    }
    options: {
      throughput: environment == 'prod' ? cosmosDbThroughput : 400
    }
  }
}

// ============================================================================
// Service Bus
// ============================================================================

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: resourceNames.serviceBusNamespace
  location: location
  tags: tags
  sku: {
    name: serviceBusNamespaceSku
    tier: serviceBusNamespaceSku
    capacity: serviceBusNamespaceSku == 'Premium' ? serviceBusCapacity : null
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    premiumMessagingPartitions: serviceBusNamespaceSku == 'Premium' ? 1 : null
  }
}

resource serviceBusTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'trading-signals'
  properties: {
    maxSizeInMegabytes: 5120
    defaultMessageTimeToLive: 'P7D'
    enableBatchedOperations: true
    enableExpress: serviceBusNamespaceSku != 'Premium'
    enablePartitioning: serviceBusNamespaceSku != 'Premium'
    requiresDuplicateDetection: false
    supportOrdering: false
    status: 'Active'
  }
}

resource serviceBusSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: serviceBusTopic
  name: 'high-priority-signals'
  properties: {
    maxDeliveryCount: 3
    defaultMessageTimeToLive: 'P7D'
    enableBatchedOperations: true
    requiresSession: false
    deadLetteringOnMessageExpiration: true
    deadLetteringOnFilterEvaluationExceptions: true
    status: 'Active'
  }
}

resource serviceBusSubscriptionRule 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2022-10-01-preview' = {
  parent: serviceBusSubscription
  name: 'strong-signals-only'
  properties: {
    filterType: 'SqlFilter'
    sqlFilter: {
      sqlExpression: 'signal IN (\'STRONG_BUY\', \'STRONG_SELL\')'
    }
  }
}

// ============================================================================
// Function App
// ============================================================================

resource functionAppPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'plan-${resourceNames.functionApp}'
  location: location
  tags: tags
  sku: {
    name: functionAppSku
    tier: functionAppSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
    size: functionAppSku
    family: functionAppSku == 'Y1' ? 'Y' : 'EP'
    capacity: functionAppSku == 'Y1' ? 0 : 1
  }
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: true
    maximumElasticWorkerCount: 20
    isSpot: false
    reserved: false
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: resourceNames.functionApp
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: functionAppPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
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
          value: 'dotnet'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${applicationInsights.properties.InstrumentationKey}'
        }
        {
          name: 'CosmosDB_Endpoint'
          value: cosmosDbAccount.properties.documentEndpoint
        }
        {
          name: 'CosmosDB_Key'
          value: cosmosDbAccount.listKeys().primaryMasterKey
        }
        {
          name: 'EventHub_ConnectionString'
          value: eventHubNamespace.listKeys().primaryConnectionString
        }
        {
          name: 'AzureAI_Endpoint'
          value: aiServices.properties.endpoint
        }
        {
          name: 'AzureAI_Key'
          value: aiServices.listKeys().key1
        }
        {
          name: 'ServiceBus_ConnectionString'
          value: serviceBusNamespace.listKeys().primaryConnectionString
        }
      ]
      netFrameworkVersion: 'v6.0'
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: functionAppSku == 'Y1' ? 0 : 1
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      powerShellVersion: '~7'
      publicNetworkAccess: 'Enabled'
    }
    httpsOnly: true
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ============================================================================
// Stream Analytics
// ============================================================================

resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: resourceNames.streamAnalyticsJob
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'Standard'
    }
    outputErrorPolicy: 'Stop'
    eventsOutOfOrderPolicy: 'Adjust'
    eventsOutOfOrderMaxDelayInSeconds: 0
    eventsLateArrivalMaxDelayInSeconds: 5
    dataLocale: 'en-US'
    transformation: {
      name: 'TradingSignalsTransformation'
      properties: {
        streamingUnits: streamAnalyticsStreamingUnits
        query: '''
          WITH PriceMovements AS (
              SELECT 
                  symbol,
                  price,
                  volume,
                  LAG(price, 1) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime) as prev_price,
                  AVG(price) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime 
                      RANGE BETWEEN INTERVAL '5' MINUTE PRECEDING AND CURRENT ROW) as sma_5min,
                  STDEV(price) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime 
                      RANGE BETWEEN INTERVAL '5' MINUTE PRECEDING AND CURRENT ROW) as volatility_5min,
                  EventEnqueuedUtcTime,
                  System.Timestamp() as WindowEnd
              FROM MarketDataInput
          ),
          TradingSignals AS (
              SELECT 
                  symbol,
                  price,
                  volume,
                  prev_price,
                  sma_5min,
                  volatility_5min,
                  CASE 
                      WHEN price > prev_price * 1.02 AND volume > LAG(volume, 1) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime) * 1.5 
                      THEN 'STRONG_BUY'
                      WHEN price > sma_5min * 1.01 AND volatility_5min < 0.02 
                      THEN 'BUY'
                      WHEN price < prev_price * 0.98 AND volume > LAG(volume, 1) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime) * 1.5 
                      THEN 'STRONG_SELL'
                      WHEN price < sma_5min * 0.99 
                      THEN 'SELL'
                      ELSE 'HOLD'
                  END as signal,
                  (price - prev_price) / prev_price * 100 as price_change_pct,
                  volatility_5min as risk_score,
                  WindowEnd as signal_timestamp
              FROM PriceMovements
              WHERE prev_price IS NOT NULL
          )
          SELECT * INTO SignalOutput FROM TradingSignals
          WHERE signal IN ('STRONG_BUY', 'BUY', 'STRONG_SELL', 'SELL')
        '''
      }
    }
  }
}

resource streamAnalyticsInput 'Microsoft.StreamAnalytics/streamingjobs/inputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'MarketDataInput'
  properties: {
    type: 'Stream'
    datasource: {
      type: 'Microsoft.ServiceBus/EventHub'
      properties: {
        eventHubName: eventHub.name
        serviceBusNamespace: eventHubNamespace.name
        sharedAccessPolicyName: 'RootManageSharedAccessKey'
        sharedAccessPolicyKey: eventHubNamespace.listKeys().primaryKey
        consumerGroupName: 'stream-analytics-consumer'
      }
    }
    serialization: {
      type: 'Json'
      properties: {
        encoding: 'UTF8'
      }
    }
  }
}

resource streamAnalyticsOutput 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'SignalOutput'
  properties: {
    datasource: {
      type: 'Microsoft.Storage/DocumentDB'
      properties: {
        accountId: cosmosDbAccount.name
        accountKey: cosmosDbAccount.listKeys().primaryMasterKey
        database: cosmosDbDatabase.name
        collectionNamePattern: cosmosDbContainer.name
        documentId: 'signal_id'
      }
    }
    serialization: {
      type: 'Json'
      properties: {
        encoding: 'UTF8'
        format: 'LineSeparated'
      }
    }
  }
}

// ============================================================================
// Monitoring and Alerts
// ============================================================================

resource eventHubMetricAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'EventHub-IncomingMessages-Alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when Event Hub incoming messages exceed threshold'
    severity: 2
    enabled: true
    scopes: [
      eventHub.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 1000
          name: 'IncomingMessages'
          metricNamespace: 'Microsoft.EventHub/namespaces'
          metricName: 'IncomingMessages'
          operator: 'GreaterThan'
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

resource streamAnalyticsMetricAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'StreamAnalytics-RuntimeErrors-Alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when Stream Analytics job has runtime errors'
    severity: 1
    enabled: true
    scopes: [
      streamAnalyticsJob.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 0
          name: 'RuntimeErrors'
          metricNamespace: 'Microsoft.StreamAnalytics/streamingjobs'
          metricName: 'Errors'
          operator: 'GreaterThan'
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the deployed resource group')
output resourceGroupName string = resourceGroup().name

@description('The Azure region where resources were deployed')
output location string = location

@description('The name of the AI Services account')
output aiServicesName string = aiServices.name

@description('The endpoint URL for AI Services')
output aiServicesEndpoint string = aiServices.properties.endpoint

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The primary endpoint for the storage account')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The name of the Event Hub namespace')
output eventHubNamespaceName string = eventHubNamespace.name

@description('The name of the Event Hub')
output eventHubName string = eventHub.name

@description('The Event Hub connection string')
output eventHubConnectionString string = eventHubNamespace.listKeys().primaryConnectionString

@description('The name of the Stream Analytics job')
output streamAnalyticsJobName string = streamAnalyticsJob.name

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The Function App default hostname')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The name of the Cosmos DB account')
output cosmosDbAccountName string = cosmosDbAccount.name

@description('The Cosmos DB document endpoint')
output cosmosDbEndpoint string = cosmosDbAccount.properties.documentEndpoint

@description('The name of the Service Bus namespace')
output serviceBusNamespaceName string = serviceBusNamespace.name

@description('The Service Bus connection string')
output serviceBusConnectionString string = serviceBusNamespace.listKeys().primaryConnectionString

@description('The name of the Application Insights component')
output applicationInsightsName string = applicationInsights.name

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalytics.name

@description('Summary of all created resources')
output resourceSummary object = {
  aiServices: {
    name: aiServices.name
    endpoint: aiServices.properties.endpoint
    sku: aiServices.sku.name
  }
  eventHub: {
    namespace: eventHubNamespace.name
    hubName: eventHub.name
    partitions: eventHub.properties.partitionCount
    sku: eventHubNamespace.sku.name
  }
  streamAnalytics: {
    name: streamAnalyticsJob.name
    streamingUnits: streamAnalyticsJob.properties.transformation.properties.streamingUnits
  }
  cosmosDb: {
    name: cosmosDbAccount.name
    endpoint: cosmosDbAccount.properties.documentEndpoint
    database: cosmosDbDatabase.name
    container: cosmosDbContainer.name
  }
  functionApp: {
    name: functionApp.name
    hostname: functionApp.properties.defaultHostName
    plan: functionAppPlan.name
  }
  serviceBus: {
    namespace: serviceBusNamespace.name
    sku: serviceBusNamespace.sku.name
  }
  storage: {
    name: storageAccount.name
    containers: storageContainers
  }
}