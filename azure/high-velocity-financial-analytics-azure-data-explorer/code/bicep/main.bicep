// ============================================================================
// Main Bicep Template for Real-Time Financial Market Data Processing
// with Azure Data Explorer and Azure Event Hubs
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Prefix for all resource names to ensure uniqueness')
@minLength(3)
@maxLength(10)
param resourcePrefix string = 'market'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Owner tag for resource management')
param owner string = 'finance-team'

@description('Azure Data Explorer cluster SKU configuration')
param adxClusterSku object = {
  name: 'Dev(No SLA)_Standard_D11_v2'
  tier: 'Basic'
  capacity: 1
}

@description('Event Hubs namespace SKU and configuration')
param eventHubsConfig object = {
  sku: 'Standard'
  throughputUnits: 2
  maxThroughputUnits: 10
  autoInflateEnabled: true
}

@description('Function App runtime configuration')
param functionAppConfig object = {
  runtime: 'python'
  runtimeVersion: '3.9'
  functionsVersion: '4'
}

@description('Database retention and cache policies (in days)')
param databaseConfig object = {
  softDeletePeriod: 30
  hotCachePeriod: 7
}

@description('Market data Event Hub partition count')
@minValue(2)
@maxValue(32)
param marketDataPartitions int = 8

@description('Trading events Event Hub partition count')
@minValue(2)
@maxValue(32)
param tradingEventsPartitions int = 4

@description('Enable Application Insights monitoring')
param enableApplicationInsights bool = true

@description('Enable Log Analytics workspace')
param enableLogAnalytics bool = true

// ============================================================================
// VARIABLES
// ============================================================================

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var commonTags = {
  Environment: environment
  Owner: owner
  Purpose: 'financial-market-data'
  Solution: 'real-time-analytics'
  'Created-By': 'bicep-template'
}

// Resource naming with proper Azure naming conventions
var adxClusterName = '${resourcePrefix}-adx-${uniqueSuffix}'
var eventHubNamespaceName = '${resourcePrefix}-evhns-${uniqueSuffix}'
var functionAppName = '${resourcePrefix}-func-${uniqueSuffix}'
var storageAccountName = '${resourcePrefix}st${uniqueSuffix}'
var eventGridTopicName = '${resourcePrefix}-egt-${uniqueSuffix}'
var appInsightsName = '${resourcePrefix}-ai-${uniqueSuffix}'
var logAnalyticsName = '${resourcePrefix}-law-${uniqueSuffix}'
var appServicePlanName = '${resourcePrefix}-asp-${uniqueSuffix}'

// Event Hub names
var marketDataHubName = 'market-data-hub'
var tradingEventsHubName = 'trading-events-hub'

// Database and table names
var databaseName = 'MarketData'
var consumerGroupName = 'trading-consumer-group'

// ============================================================================
// AZURE DATA EXPLORER CLUSTER
// ============================================================================

resource adxCluster 'Microsoft.Kusto/clusters@2023-08-15' = {
  name: adxClusterName
  location: location
  tags: commonTags
  sku: {
    name: adxClusterSku.name
    tier: adxClusterSku.tier
    capacity: adxClusterSku.capacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enableDiskEncryption: true
    enableStreamingIngest: true
    enablePurge: true
    enableDoubleEncryption: false
    optimizedAutoscale: {
      version: 1
      isEnabled: environment == 'prod'
      minimum: adxClusterSku.capacity
      maximum: environment == 'prod' ? 10 : 2
    }
  }
}

// Azure Data Explorer Database
resource adxDatabase 'Microsoft.Kusto/clusters/databases@2023-08-15' = {
  parent: adxCluster
  name: databaseName
  location: location
  kind: 'ReadWrite'
  properties: {
    softDeletePeriod: 'P${databaseConfig.softDeletePeriod}D'
    hotCachePeriod: 'P${databaseConfig.hotCachePeriod}D'
  }
}

// ============================================================================
// STORAGE ACCOUNT FOR AZURE FUNCTIONS
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
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
    allowBlobPublicAccess: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// ============================================================================
// EVENT HUBS NAMESPACE AND HUBS
// ============================================================================

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: eventHubNamespaceName
  location: location
  tags: commonTags
  sku: {
    name: eventHubsConfig.sku
    tier: eventHubsConfig.sku
    capacity: eventHubsConfig.throughputUnits
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: environment == 'prod'
    isAutoInflateEnabled: eventHubsConfig.autoInflateEnabled
    maximumThroughputUnits: eventHubsConfig.maxThroughputUnits
    kafkaEnabled: true
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Market Data Event Hub
resource marketDataEventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubNamespace
  name: marketDataHubName
  properties: {
    messageRetentionInDays: 1
    partitionCount: marketDataPartitions
    status: 'Active'
    captureDescription: {
      enabled: false
    }
  }
}

// Trading Events Event Hub
resource tradingEventsEventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubNamespace
  name: tradingEventsHubName
  properties: {
    messageRetentionInDays: 1
    partitionCount: tradingEventsPartitions
    status: 'Active'
    captureDescription: {
      enabled: false
    }
  }
}

// Consumer group for trading events
resource tradingConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  parent: tradingEventsEventHub
  name: consumerGroupName
  properties: {
    userMetadata: 'Consumer group for trading event processing'
  }
}

// Authorization rule for Event Hub access
resource eventHubAuthRule 'Microsoft.EventHub/namespaces/authorizationRules@2024-01-01' = {
  parent: eventHubNamespace
  name: 'FunctionAppAccessRule'
  properties: {
    rights: [
      'Listen'
      'Send'
    ]
  }
}

// ============================================================================
// DATA CONNECTION FROM EVENT HUBS TO AZURE DATA EXPLORER
// ============================================================================

resource dataConnection 'Microsoft.Kusto/clusters/databases/dataConnections@2023-08-15' = {
  parent: adxDatabase
  name: 'market-data-connection'
  location: location
  kind: 'EventHub'
  properties: {
    eventHubResourceId: marketDataEventHub.id
    consumerGroup: '$Default'
    tableName: 'MarketDataRaw'
    dataFormat: 'JSON'
    mappingRuleName: 'MarketDataMapping'
    compression: 'None'
    eventSystemProperties: [
      'x-opt-enqueued-time'
      'x-opt-sequence-number'
      'x-opt-partition-key'
    ]
  }
  dependsOn: [
    adxCluster
    marketDataEventHub
  ]
}

// ============================================================================
// LOG ANALYTICS WORKSPACE (OPTIONAL)
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableLogAnalytics) {
  name: logAnalyticsName
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// APPLICATION INSIGHTS
// ============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: location
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableLogAnalytics ? logAnalyticsWorkspace.id : null
    IngestionMode: enableLogAnalytics ? 'LogAnalytics' : 'ApplicationInsights'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// APP SERVICE PLAN FOR AZURE FUNCTIONS
// ============================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: commonTags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    computeMode: 'Dynamic'
    reserved: true // Required for Linux consumption plan
  }
}

// ============================================================================
// AZURE FUNCTIONS APP
// ============================================================================

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: commonTags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: '${upper(functionAppConfig.runtime)}|${functionAppConfig.runtimeVersion}'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~${functionAppConfig.functionsVersion}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionAppConfig.runtime
        }
        {
          name: 'EventHubConnectionString'
          value: eventHubAuthRule.listKeys().primaryConnectionString
        }
        {
          name: 'ADX_CLUSTER_URI'
          value: adxCluster.properties.uri
        }
        {
          name: 'ADX_DATABASE'
          value: databaseName
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
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
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
    }
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// ============================================================================
// EVENT GRID TOPIC
// ============================================================================

resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    dataResidencyBoundary: 'WithinGeopair'
  }
}

// ============================================================================
// RBAC ASSIGNMENTS
// ============================================================================

// Grant Function App access to Event Hubs
resource functionAppEventHubRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, eventHubNamespace.id, 'Azure Event Hubs Data Receiver')
  scope: eventHubNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde') // Azure Event Hubs Data Receiver
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to ADX
resource functionAppAdxRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, adxCluster.id, 'Azure Data Explorer User')
  scope: adxCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '76199698-9eea-4c19-bc75-cec21354c6b6') // Azure Data Explorer User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to Event Grid
resource functionAppEventGridRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, eventGridTopic.id, 'EventGrid Data Sender')
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7') // EventGrid Data Sender
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Azure Data Explorer cluster name')
output adxClusterName string = adxCluster.name

@description('Azure Data Explorer cluster URI')
output adxClusterUri string = adxCluster.properties.uri

@description('Azure Data Explorer database name')
output adxDatabaseName string = databaseName

@description('Event Hubs namespace name')
output eventHubNamespaceName string = eventHubNamespace.name

@description('Event Hubs namespace connection string')
output eventHubConnectionString string = eventHubAuthRule.listKeys().primaryConnectionString

@description('Market data Event Hub name')
output marketDataHubName string = marketDataEventHub.name

@description('Trading events Event Hub name')
output tradingEventsHubName string = tradingEventsEventHub.name

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Event Grid topic name')
output eventGridTopicName string = eventGridTopic.name

@description('Event Grid topic endpoint')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('Application Insights name')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = enableLogAnalytics ? logAnalyticsWorkspace.name : ''

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = enableLogAnalytics ? logAnalyticsWorkspace.id : ''

@description('Deployment environment')
output environment string = environment

@description('Resource tags applied')
output resourceTags object = commonTags