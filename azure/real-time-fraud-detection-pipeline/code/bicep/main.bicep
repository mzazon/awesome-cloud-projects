@description('Main Bicep template for Real-Time Fraud Detection Pipeline with Azure Stream Analytics and Azure Machine Learning')

// Parameters
@description('Environment prefix for resource naming')
@minLength(3)
@maxLength(8)
param environmentPrefix string = 'fraud'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Random suffix for unique resource names')
@minLength(3)
@maxLength(6)
param randomSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Event Hub namespace SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param eventHubSku string = 'Standard'

@description('Event Hub partition count')
@minValue(2)
@maxValue(32)
param eventHubPartitionCount int = 4

@description('Event Hub message retention in days')
@minValue(1)
@maxValue(7)
param eventHubMessageRetention int = 7

@description('Stream Analytics streaming units')
@minValue(1)
@maxValue(48)
param streamingUnits int = 3

@description('Cosmos DB consistency level')
@allowed(['Eventual', 'ConsistentPrefix', 'Session', 'BoundedStaleness', 'Strong'])
param cosmosDbConsistencyLevel string = 'Session'

@description('Function App SKU')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppSku string = 'Y1'

@description('Machine Learning compute instance SKU')
@allowed(['Standard_DS3_v2', 'Standard_DS4_v2', 'Standard_DS5_v2'])
param mlComputeSku string = 'Standard_DS3_v2'

@description('Tags to apply to all resources')
param tags object = {
  environment: 'demo'
  purpose: 'fraud-detection'
  recipe: 'real-time-fraud-detection'
}

// Variables
var eventHubNamespaceName = '${environmentPrefix}-eh-${randomSuffix}'
var eventHubName = 'transactions'
var streamAnalyticsJobName = '${environmentPrefix}-asa-${randomSuffix}'
var mlWorkspaceName = '${environmentPrefix}-ml-${randomSuffix}'
var functionAppName = '${environmentPrefix}-func-${randomSuffix}'
var cosmosDbAccountName = '${environmentPrefix}-cosmos-${randomSuffix}'
var storageAccountName = '${environmentPrefix}st${randomSuffix}'
var applicationInsightsName = '${environmentPrefix}-ai-${randomSuffix}'
var logAnalyticsWorkspaceName = '${environmentPrefix}-law-${randomSuffix}'
var keyVaultName = '${environmentPrefix}-kv-${randomSuffix}'

// Storage Account for Function App and ML Workspace
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
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
    defaultToOAuthAuthentication: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
    }
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
  }
}

// Key Vault for secure credential storage
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    accessPolicies: []
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
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

// Event Hubs Namespace
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: eventHubNamespaceName
  location: location
  tags: tags
  sku: {
    name: eventHubSku
    tier: eventHubSku
    capacity: eventHubSku == 'Premium' ? 1 : null
  }
  properties: {
    isAutoInflateEnabled: false
    maximumThroughputUnits: eventHubSku == 'Standard' ? 20 : null
    kafkaEnabled: eventHubSku != 'Basic'
    zoneRedundant: false
    encryption: {
      keySource: 'Microsoft.KeyVault'
    }
  }
}

// Event Hub for transaction data
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: eventHubMessageRetention
    partitionCount: eventHubPartitionCount
    status: 'Active'
    captureDescription: {
      enabled: false
    }
  }
}

// Event Hub authorization rule for Stream Analytics
resource eventHubAuthRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: eventHub
  name: 'StreamAnalyticsAccess'
  properties: {
    rights: [
      'Send'
      'Listen'
    ]
  }
}

// Cosmos DB Account
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosDbAccountName
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
        isZoneRedundant: false
      }
    ]
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    enableAutomaticFailover: true
    enableMultipleWriteLocations: false
    enableFreeTier: false
    analyticalStorageConfiguration: {
      schemaType: 'WellDefined'
    }
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

// Cosmos DB Database
resource cosmosDbDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosDbAccount
  name: 'fraud-detection'
  properties: {
    resource: {
      id: 'fraud-detection'
    }
  }
}

// Cosmos DB Container for transactions
resource cosmosDbTransactionsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDbDatabase
  name: 'transactions'
  properties: {
    resource: {
      id: 'transactions'
      partitionKey: {
        paths: [
          '/transactionId'
        ]
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

// Cosmos DB Container for fraud alerts
resource cosmosDbAlertsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDbDatabase
  name: 'fraud-alerts'
  properties: {
    resource: {
      id: 'fraud-alerts'
      partitionKey: {
        paths: [
          '/alertId'
        ]
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

// Azure Machine Learning Workspace
resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-07-01-preview' = {
  name: mlWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: 'Fraud detection ML workspace'
    friendlyName: 'Fraud Detection Workspace'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: applicationInsights.id
    containerRegistry: null
    discoveryUrl: null
    encryption: {
      status: 'Enabled'
      keyVaultProperties: {
        keyVaultArmId: keyVault.id
        keyIdentifier: null
      }
    }
    hbiWorkspace: false
    v1LegacyMode: false
    publicNetworkAccess: 'Enabled'
    allowPublicAccessWhenBehindVnet: false
    managedNetwork: {
      isolationMode: 'Disabled'
    }
  }
}

// ML Compute Instance
resource mlComputeInstance 'Microsoft.MachineLearningServices/workspaces/computes@2024-07-01-preview' = {
  parent: mlWorkspace
  name: 'fraud-compute'
  location: location
  properties: {
    computeType: 'ComputeInstance'
    properties: {
      vmSize: mlComputeSku
      subnet: null
      applicationSharingPolicy: 'Personal'
      computeInstanceAuthorizationType: 'personal'
      personalComputeInstanceSettings: {
        assignedUser: {
          objectId: 'placeholder-object-id'
          tenantId: tenant().tenantId
        }
      }
      schedules: {
        computeStartStop: [
          {
            action: 'Stop'
            triggerType: 'Cron'
            cron: {
              expression: '0 18 * * *'
              timeZone: 'UTC'
            }
            status: 'Enabled'
          }
        ]
      }
    }
  }
}

// Function App Service Plan
resource functionAppServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${functionAppName}-plan'
  location: location
  tags: tags
  sku: {
    name: functionAppSku
    tier: functionAppSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  kind: 'functionapp'
  properties: {
    reserved: true
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionAppServicePlan.id
    reserved: true
    siteConfig: {
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
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
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
          name: 'CosmosDBConnectionString'
          value: cosmosDbAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
      ]
      linuxFxVersion: 'NODE|18'
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      alwaysOn: functionAppSku != 'Y1'
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
  }
}

// Stream Analytics Job
resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: streamAnalyticsJobName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Standard'
      capacity: streamingUnits
    }
    outputStartMode: 'JobStartTime'
    outputStartTime: null
    eventsOutOfOrderPolicy: 'Adjust'
    outputErrorPolicy: 'Stop'
    eventsOutOfOrderMaxDelayInSeconds: 0
    eventsLateArrivalMaxDelayInSeconds: 5
    dataLocale: 'en-US'
    compatibilityLevel: '1.2'
    contentStoragePolicy: 'SystemAccount'
    jobType: 'Cloud'
  }
}

// Stream Analytics Input
resource streamAnalyticsInput 'Microsoft.StreamAnalytics/streamingjobs/inputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'TransactionInput'
  properties: {
    type: 'Stream'
    datasource: {
      type: 'Microsoft.ServiceBus/EventHub'
      properties: {
        eventHubName: eventHubName
        serviceBusNamespace: eventHubNamespaceName
        sharedAccessPolicyName: eventHubAuthRule.name
        sharedAccessPolicyKey: eventHubAuthRule.listKeys().primaryKey
        authenticationMode: 'ConnectionString'
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

// Stream Analytics Output - Cosmos DB
resource streamAnalyticsOutputCosmos 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'TransactionOutput'
  properties: {
    datasource: {
      type: 'Microsoft.Storage/DocumentDB'
      properties: {
        accountId: cosmosDbAccountName
        accountKey: cosmosDbAccount.listKeys().primaryMasterKey
        database: cosmosDbDatabase.name
        collectionNamePattern: cosmosDbTransactionsContainer.name
        documentId: 'transactionId'
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

// Stream Analytics Output - Function App
resource streamAnalyticsOutputFunction 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'AlertOutput'
  properties: {
    datasource: {
      type: 'Microsoft.Web/sites/functions'
      properties: {
        functionAppName: functionAppName
        functionName: 'ProcessFraudAlert'
        maxBatchCount: 100
        maxBatchSize: 262144
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

// Stream Analytics Transformation (Query)
resource streamAnalyticsTransformation 'Microsoft.StreamAnalytics/streamingjobs/transformations@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'FraudDetectionTransformation'
  properties: {
    streamingUnits: streamingUnits
    query: '''
      WITH TransactionAnalysis AS (
          SELECT
              transactionId,
              userId,
              amount,
              merchantId,
              location,
              timestamp,
              -- Calculate rolling averages for comparison
              AVG(amount) OVER (
                  PARTITION BY userId 
                  ORDER BY timestamp ASC
                  RANGE INTERVAL '24' HOUR PRECEDING
              ) as avg_daily_amount,
              COUNT(*) OVER (
                  PARTITION BY userId 
                  ORDER BY timestamp ASC
                  RANGE INTERVAL '1' HOUR PRECEDING
              ) as hourly_transaction_count,
              -- Detect velocity patterns
              COUNT(*) OVER (
                  PARTITION BY userId 
                  ORDER BY timestamp ASC
                  RANGE INTERVAL '10' MINUTE PRECEDING
              ) as velocity_count
          FROM TransactionInput
      ),
      
      FraudScoring AS (
          SELECT
              *,
              CASE 
                  WHEN amount > (avg_daily_amount * 10) THEN 50
                  WHEN hourly_transaction_count > 20 THEN 40
                  WHEN velocity_count > 5 THEN 60
                  ELSE 0
              END as fraud_score,
              CASE 
                  WHEN amount > (avg_daily_amount * 10) THEN 'UNUSUAL_AMOUNT'
                  WHEN hourly_transaction_count > 20 THEN 'HIGH_FREQUENCY'
                  WHEN velocity_count > 5 THEN 'RAPID_FIRE'
                  ELSE 'NORMAL'
              END as fraud_reason
          FROM TransactionAnalysis
      )
      
      -- Store all transactions
      SELECT * INTO TransactionOutput FROM FraudScoring;
      
      -- Send high-risk transactions to alert system
      SELECT 
          transactionId,
          userId,
          amount,
          merchantId,
          location,
          fraud_score,
          fraud_reason,
          timestamp
      INTO AlertOutput 
      FROM FraudScoring
      WHERE fraud_score > 30;
    '''
  }
}

// Role Assignments for Function App to access Cosmos DB
resource functionAppCosmosDbRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'CosmosDBDataContributor')
  scope: cosmosDbAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00000000-0000-0000-0000-000000000002') // Cosmos DB Built-in Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for Stream Analytics to access Event Hub
resource streamAnalyticsEventHubRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, streamAnalyticsJob.id, 'EventHubDataReceiver')
  scope: eventHub
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde') // Azure Event Hubs Data Receiver
    principalId: streamAnalyticsJob.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for Stream Analytics to access Function App
resource streamAnalyticsFunctionRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, streamAnalyticsJob.id, 'WebsiteContributor')
  scope: functionApp
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'de139f84-1756-47ae-9be6-808fbbe84772') // Website Contributor
    principalId: streamAnalyticsJob.identity.principalId
    principalType: 'ServicePrincipal'
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

@description('Stream Analytics Job Name')
output streamAnalyticsJobName string = streamAnalyticsJob.name

@description('Cosmos DB Account Name')
output cosmosDbAccountName string = cosmosDbAccount.name

@description('Cosmos DB Connection String')
output cosmosDbConnectionString string = cosmosDbAccount.listConnectionStrings().connectionStrings[0].connectionString

@description('Function App Name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Machine Learning Workspace Name')
output mlWorkspaceName string = mlWorkspace.name

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Key Vault Name')
output keyVaultName string = keyVault.name

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name