@description('Main Bicep template for real-time document processing with Azure Cosmos DB for MongoDB and Azure Event Hubs')

// Parameters
@description('Primary Azure region for resource deployment')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Project name used for resource naming')
@minLength(3)
@maxLength(10)
param projectName string = 'docproc'

@description('Unique suffix for resource names')
@minLength(3)
@maxLength(6)
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Event Hub namespace SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param eventHubSku string = 'Standard'

@description('Event Hub capacity (throughput units)')
@minValue(1)
@maxValue(20)
param eventHubCapacity int = 1

@description('Event Hub partition count')
@minValue(2)
@maxValue(32)
param eventHubPartitionCount int = 4

@description('Event Hub message retention in days')
@minValue(1)
@maxValue(7)
param eventHubMessageRetention int = 1

@description('Cosmos DB throughput (RU/s)')
@minValue(400)
@maxValue(100000)
param cosmosDbThroughput int = 400

@description('Cosmos DB consistency level')
@allowed(['Eventual', 'Session', 'Strong', 'BoundedStaleness', 'ConsistentPrefix'])
param cosmosDbConsistencyLevel string = 'Session'

@description('AI Document Intelligence SKU')
@allowed(['F0', 'S0'])
param aiDocumentSku string = 'S0'

@description('Function App hosting plan SKU')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppSku string = 'Y1'

@description('Function App runtime version')
@allowed(['~4'])
param functionAppVersion string = '~4'

@description('Function App Node.js version')
@allowed(['18', '20'])
param functionAppNodeVersion string = '18'

@description('Enable Application Insights')
param enableApplicationInsights bool = true

@description('Enable diagnostic logging')
param enableDiagnostics bool = true

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: projectName
  Purpose: 'document-processing'
  ManagedBy: 'bicep'
}

// Variables
var resourceNames = {
  eventHubNamespace: 'eh-${projectName}-${uniqueSuffix}'
  eventHubName: 'document-events'
  cosmosAccount: 'cosmos-${projectName}-${uniqueSuffix}'
  cosmosDatabase: 'DocumentProcessingDB'
  cosmosCollection: 'ProcessedDocuments'
  functionApp: 'func-${projectName}-${uniqueSuffix}'
  storageAccount: 'st${projectName}${uniqueSuffix}'
  aiDocument: 'ai-${projectName}-${uniqueSuffix}'
  appInsights: 'ai-${projectName}-${uniqueSuffix}'
  logAnalytics: 'log-${projectName}-${uniqueSuffix}'
  hostingPlan: 'plan-${projectName}-${uniqueSuffix}'
}

var eventHubConsumerGroup = 'functions-consumer'
var cosmosLeaseCollection = 'leases'

// Log Analytics Workspace (required for Application Insights)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableApplicationInsights) {
  name: resourceNames.logAnalytics
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: resourceNames.appInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
    DisableIpMasking: false
    DisableLocalAuth: false
    ForceCustomerStorageForProfiler: false
  }
}

// Event Hub Namespace
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: resourceNames.eventHubNamespace
  location: location
  tags: tags
  sku: {
    name: eventHubSku
    tier: eventHubSku
    capacity: eventHubCapacity
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: environment == 'prod'
    isAutoInflateEnabled: eventHubSku == 'Standard'
    maximumThroughputUnits: eventHubSku == 'Standard' ? 20 : null
    kafkaEnabled: true
  }
}

// Event Hub
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubNamespace
  name: resourceNames.eventHubName
  properties: {
    messageRetentionInDays: eventHubMessageRetention
    partitionCount: eventHubPartitionCount
    status: 'Active'
    captureDescription: {
      enabled: false
    }
  }
}

// Event Hub Consumer Group
resource eventHubConsumerGroupResource 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  parent: eventHub
  name: eventHubConsumerGroup
  properties: {
    userMetadata: 'Consumer group for Azure Functions'
  }
}

// Event Hub Authorization Rule
resource eventHubAuthRule 'Microsoft.EventHub/namespaces/authorizationRules@2024-01-01' = {
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

// Cosmos DB Account
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: resourceNames.cosmosAccount
  location: location
  tags: tags
  kind: 'MongoDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    apiProperties: {
      serverVersion: '4.2'
    }
    capabilities: [
      {
        name: 'EnableMongo'
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: cosmosDbConsistencyLevel
      maxIntervalInSeconds: cosmosDbConsistencyLevel == 'BoundedStaleness' ? 300 : null
      maxStalenessPrefix: cosmosDbConsistencyLevel == 'BoundedStaleness' ? 100000 : null
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: environment == 'prod'
      }
    ]
    enableAutomaticFailover: true
    enableMultipleWriteLocations: false
    enableFreeTier: environment == 'dev'
    enableAnalyticalStorage: false
    disableKeyBasedMetadataWriteAccess: false
    networkAclBypass: 'AzureServices'
    disableLocalAuth: false
    minimalTlsVersion: 'Tls12'
    publicNetworkAccess: 'Enabled'
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Geo'
      }
    }
  }
}

// Cosmos DB Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/mongodbDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: resourceNames.cosmosDatabase
  properties: {
    resource: {
      id: resourceNames.cosmosDatabase
    }
  }
}

// Cosmos DB Collection for Processed Documents
resource cosmosCollection 'Microsoft.DocumentDB/databaseAccounts/mongodbDatabases/collections@2024-05-15' = {
  parent: cosmosDatabase
  name: resourceNames.cosmosCollection
  properties: {
    resource: {
      id: resourceNames.cosmosCollection
      shardKey: {
        documentId: 'Hash'
      }
      indexes: [
        {
          key: {
            keys: [
              '_id'
            ]
          }
        }
        {
          key: {
            keys: [
              'documentId'
            ]
          }
        }
        {
          key: {
            keys: [
              'processingDate'
            ]
          }
        }
      ]
    }
    options: {
      throughput: cosmosDbThroughput
    }
  }
}

// Cosmos DB Collection for Change Feed Leases
resource cosmosLeaseCollectionResource 'Microsoft.DocumentDB/databaseAccounts/mongodbDatabases/collections@2024-05-15' = {
  parent: cosmosDatabase
  name: cosmosLeaseCollection
  properties: {
    resource: {
      id: cosmosLeaseCollection
      shardKey: {
        id: 'Hash'
      }
      indexes: [
        {
          key: {
            keys: [
              '_id'
            ]
          }
        }
      ]
    }
    options: {
      throughput: 400
    }
  }
}

// AI Document Intelligence Service
resource aiDocumentService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: resourceNames.aiDocument
  location: location
  tags: tags
  kind: 'FormRecognizer'
  sku: {
    name: aiDocumentSku
  }
  properties: {
    customSubDomainName: resourceNames.aiDocument
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    restrictOutboundNetworkAccess: false
  }
}

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
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
      keySource: 'Microsoft.Storage'
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
    }
    accessTier: 'Hot'
  }
}

// Function App Hosting Plan
resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: resourceNames.hostingPlan
  location: location
  tags: tags
  sku: {
    name: functionAppSku
  }
  properties: {
    reserved: false
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: resourceNames.functionApp
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlan.id
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
          value: functionAppVersion
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: functionAppNodeVersion
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'EventHubConnection'
          value: eventHubAuthRule.listKeys().primaryConnectionString
        }
        {
          name: 'CosmosDBConnection'
          value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
        {
          name: 'AIDocumentKey'
          value: aiDocumentService.listKeys().key1
        }
        {
          name: 'AIDocumentEndpoint'
          value: aiDocumentService.properties.endpoint
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
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      httpsOnly: true
      netFrameworkVersion: 'v6.0'
    }
    httpsOnly: true
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

// Diagnostic Settings for Event Hub Namespace
resource eventHubDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && enableApplicationInsights) {
  name: 'diagnostics'
  scope: eventHubNamespace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Diagnostic Settings for Cosmos DB
resource cosmosDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && enableApplicationInsights) {
  name: 'diagnostics'
  scope: cosmosAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'Requests'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Diagnostic Settings for Function App
resource functionAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && enableApplicationInsights) {
  name: 'diagnostics'
  scope: functionApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Outputs
@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Event Hub Namespace Name')
output eventHubNamespaceName string = eventHubNamespace.name

@description('Event Hub Name')
output eventHubName string = eventHub.name

@description('Event Hub Connection String')
output eventHubConnectionString string = eventHubAuthRule.listKeys().primaryConnectionString

@description('Cosmos DB Account Name')
output cosmosAccountName string = cosmosAccount.name

@description('Cosmos DB Database Name')
output cosmosDatabaseName string = cosmosDatabase.name

@description('Cosmos DB Collection Name')
output cosmosCollectionName string = cosmosCollection.name

@description('Cosmos DB Connection String')
output cosmosConnectionString string = cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString

@description('Function App Name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('AI Document Intelligence Service Name')
output aiDocumentServiceName string = aiDocumentService.name

@description('AI Document Intelligence Endpoint')
output aiDocumentEndpoint string = aiDocumentService.properties.endpoint

@description('Application Insights Name')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = enableApplicationInsights ? logAnalyticsWorkspace.name : ''

@description('Deployment Summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  environment: environment
  projectName: projectName
  uniqueSuffix: uniqueSuffix
  eventHubNamespace: eventHubNamespace.name
  cosmosAccount: cosmosAccount.name
  functionApp: functionApp.name
  aiDocumentService: aiDocumentService.name
  applicationInsights: enableApplicationInsights ? applicationInsights.name : 'disabled'
  deploymentTimestamp: utcNow()
}