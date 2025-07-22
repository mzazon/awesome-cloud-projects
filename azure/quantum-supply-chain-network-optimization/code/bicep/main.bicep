// ==============================================================================
// Azure Quantum Supply Chain Network Optimization Infrastructure
// ==============================================================================
// This Bicep template deploys a complete quantum supply chain optimization
// solution with Azure Quantum, Digital Twins, Stream Analytics, and Functions
// ==============================================================================

@description('The name of the project. Used as a prefix for resource names.')
@minLength(2)
@maxLength(10)
param projectName string = 'quantum'

@description('The Azure region where resources will be deployed.')
param location string = resourceGroup().location

@description('The environment name (dev, test, prod).')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('The pricing tier for the Azure Functions app service plan.')
@allowed([
  'Y1'
  'EP1'
  'EP2'
  'EP3'
])
param functionAppSkuName string = 'Y1'

@description('The SKU for the Stream Analytics job.')
@allowed([
  'Standard'
])
param streamAnalyticsSkuName string = 'Standard'

@description('The number of streaming units for the Stream Analytics job.')
@minValue(1)
@maxValue(48)
param streamAnalyticsStreamingUnits int = 1

@description('The SKU for the Event Hubs namespace.')
@allowed([
  'Basic'
  'Standard'
])
param eventHubsSkuName string = 'Standard'

@description('The throughput units for the Event Hubs namespace.')
@minValue(1)
@maxValue(20)
param eventHubsThroughputUnits int = 1

@description('The replication type for the storage account.')
@allowed([
  'LRS'
  'GRS'
  'ZRS'
  'RAGRS'
])
param storageReplication string = 'LRS'

@description('Enable Cosmos DB serverless mode for cost optimization.')
param cosmosServerlessMode bool = true

@description('Tags to apply to all resources.')
param tags object = {
  Environment: environment
  Project: 'QuantumSupplyChain'
  Purpose: 'QuantumOptimization'
  DeployedBy: 'bicep-template'
}

// Variables for resource naming with uniqueness
var uniqueSuffix = uniqueString(resourceGroup().id)
var quantumWorkspaceName = 'quantum-${projectName}-${environment}-${uniqueSuffix}'
var digitalTwinsInstanceName = 'dt-${projectName}-${environment}-${uniqueSuffix}'
var functionAppName = 'func-${projectName}-${environment}-${uniqueSuffix}'
var streamAnalyticsJobName = 'asa-${projectName}-${environment}-${uniqueSuffix}'
var storageAccountName = 'st${projectName}${environment}${uniqueSuffix}'
var cosmosDbAccountName = 'cosmos-${projectName}-${environment}-${uniqueSuffix}'
var eventHubsNamespaceName = 'eh-${projectName}-${environment}-${uniqueSuffix}'
var eventHubName = 'supply-chain-events'
var appInsightsName = 'insights-${projectName}-${environment}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'la-${projectName}-${environment}-${uniqueSuffix}'

// Additional resource names
var functionAppServicePlanName = 'asp-${functionAppName}'
var eventHubConsumerGroupName = 'stream-analytics'

// ==============================================================================
// STORAGE ACCOUNT
// ==============================================================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_${storageReplication}'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
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
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
  }
}

// ==============================================================================
// COSMOS DB ACCOUNT
// ==============================================================================
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-02-15-preview' = {
  name: cosmosDbAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
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
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: true
    enableMultipleWriteLocations: false
    capabilities: cosmosServerlessMode ? [
      {
        name: 'EnableServerless'
      }
    ] : []
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Local'
      }
    }
    publicNetworkAccess: 'Enabled'
    networkAclBypass: 'None'
  }
}

// Cosmos DB Database for supply chain data
resource cosmosDbDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-02-15-preview' = {
  name: 'supplychain'
  parent: cosmosDbAccount
  properties: {
    resource: {
      id: 'supplychain'
    }
    options: cosmosServerlessMode ? {} : {
      throughput: 400
    }
  }
}

// Cosmos DB Container for optimization results
resource cosmosDbContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-02-15-preview' = {
  name: 'optimization-results'
  parent: cosmosDbDatabase
  properties: {
    resource: {
      id: 'optimization-results'
      partitionKey: {
        paths: [
          '/optimizationId'
        ]
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
    }
  }
}

// ==============================================================================
// EVENT HUB NAMESPACE AND HUB
// ==============================================================================
resource eventHubsNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: eventHubsNamespaceName
  location: location
  tags: tags
  sku: {
    name: eventHubsSkuName
    tier: eventHubsSkuName
    capacity: eventHubsThroughputUnits
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: true
    maximumThroughputUnits: 20
    kafkaEnabled: false
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  name: eventHubName
  parent: eventHubsNamespace
  properties: {
    messageRetentionInDays: 1
    partitionCount: 4
    status: 'Active'
    captureDescription: {
      enabled: false
    }
  }
}

// Event Hub Consumer Group for Stream Analytics
resource eventHubConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  name: eventHubConsumerGroupName
  parent: eventHub
  properties: {
    userMetadata: 'Consumer group for Stream Analytics job'
  }
}

// ==============================================================================
// LOG ANALYTICS WORKSPACE
// ==============================================================================
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
    workspaceCapping: {
      dailyQuotaGb: 5
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ==============================================================================
// APPLICATION INSIGHTS
// ==============================================================================
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
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

// ==============================================================================
// AZURE DIGITAL TWINS
// ==============================================================================
resource digitalTwinsInstance 'Microsoft.DigitalTwins/digitalTwinsInstances@2023-01-31' = {
  name: digitalTwinsInstanceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// Configure diagnostic settings for Digital Twins
resource digitalTwinsDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'digital-twins-diagnostics'
  scope: digitalTwinsInstance
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'DigitalTwinsOperation'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'EventRoutesOperation'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// ==============================================================================
// AZURE QUANTUM WORKSPACE
// ==============================================================================
resource quantumWorkspace 'Microsoft.Quantum/workspaces@2023-11-13-preview' = {
  name: quantumWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    providers: [
      {
        providerId: 'microsoft-qio'
        providerSku: 'standard'
      }
      {
        providerId: '1qbit'
        providerSku: 'standard'
      }
    ]
    storageAccount: storageAccount.id
    usable: 'Yes'
  }
}

// ==============================================================================
// AZURE FUNCTIONS APP SERVICE PLAN
// ==============================================================================
resource functionAppServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: functionAppServicePlanName
  location: location
  tags: tags
  sku: {
    name: functionAppSkuName
  }
  properties: {
    reserved: true
  }
  kind: 'functionapp'
}

// ==============================================================================
// AZURE FUNCTIONS APP
// ==============================================================================
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
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
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
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'AZURE_QUANTUM_WORKSPACE_NAME'
          value: quantumWorkspace.name
        }
        {
          name: 'AZURE_QUANTUM_WORKSPACE_LOCATION'
          value: location
        }
        {
          name: 'AZURE_QUANTUM_RESOURCE_GROUP'
          value: resourceGroup().name
        }
        {
          name: 'AZURE_QUANTUM_SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
        {
          name: 'AZURE_DIGITAL_TWINS_ENDPOINT'
          value: digitalTwinsInstance.properties.hostName
        }
        {
          name: 'COSMOS_DB_CONNECTION_STRING'
          value: cosmosDbAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
        {
          name: 'COSMOS_DB_DATABASE_NAME'
          value: cosmosDbDatabase.name
        }
        {
          name: 'COSMOS_DB_CONTAINER_NAME'
          value: cosmosDbContainer.name
        }
        {
          name: 'EVENT_HUB_CONNECTION_STRING'
          value: listKeys(resourceId('Microsoft.EventHub/namespaces/authorizationRules', eventHubsNamespace.name, 'RootManageSharedAccessKey'), '2024-01-01').primaryConnectionString
        }
        {
          name: 'EVENT_HUB_NAME'
          value: eventHub.name
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
          'https://ms.portal.azure.com'
        ]
        supportCredentials: false
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
  }
}

// ==============================================================================
// STREAM ANALYTICS JOB
// ==============================================================================
resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: streamAnalyticsJobName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: streamAnalyticsSkuName
    }
    outputErrorPolicy: 'Stop'
    eventsOutOfOrderPolicy: 'Adjust'
    eventsOutOfOrderMaxDelayInSeconds: 0
    eventsLateArrivalMaxDelayInSeconds: 5
    dataLocale: 'en-US'
    transformation: {
      name: 'Transformation'
      properties: {
        streamingUnits: streamAnalyticsStreamingUnits
        query: '''
          WITH FilteredEvents AS (
            SELECT
              supplier_id,
              warehouse_id,
              inventory_level,
              location,
              EventProcessedUtcTime as timestamp,
              event_type
            FROM [supply-chain-input]
            WHERE event_type IN ('inventory_update', 'location_change', 'demand_forecast')
          ),
          AggregatedData AS (
            SELECT
              supplier_id,
              warehouse_id,
              AVG(inventory_level) AS avg_inventory,
              MAX(timestamp) AS last_update,
              COUNT(*) AS event_count
            FROM FilteredEvents
            GROUP BY supplier_id, warehouse_id, TumblingWindow(minute, 5)
          )
          SELECT 
            supplier_id,
            warehouse_id,
            avg_inventory,
            last_update,
            event_count,
            'aggregated_supply_chain_data' as output_type
          INTO [digital-twins-output] 
          FROM AggregatedData;
          
          SELECT 
            supplier_id,
            warehouse_id,
            inventory_level,
            location,
            timestamp,
            event_type,
            'optimization_trigger' as output_type
          INTO [optimization-trigger] 
          FROM FilteredEvents
          WHERE inventory_level < 100 OR event_type = 'demand_forecast';
        '''
      }
    }
    inputs: [
      {
        name: 'supply-chain-input'
        properties: {
          type: 'Stream'
          dataSource: {
            type: 'Microsoft.ServiceBus/EventHub'
            properties: {
              eventHubName: eventHub.name
              serviceBusNamespace: eventHubsNamespace.name
              sharedAccessPolicyName: 'RootManageSharedAccessKey'
              sharedAccessPolicyKey: listKeys(resourceId('Microsoft.EventHub/namespaces/authorizationRules', eventHubsNamespace.name, 'RootManageSharedAccessKey'), '2024-01-01').primaryKey
              authenticationMode: 'ConnectionString'
              consumerGroupName: eventHubConsumerGroup.name
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
    ]
    outputs: [
      {
        name: 'digital-twins-output'
        properties: {
          dataSource: {
            type: 'Microsoft.AzureFunction'
            properties: {
              functionAppName: functionApp.name
              functionName: 'UpdateDigitalTwins'
              maxBatchCount: 100
              maxBatchSize: 262144
            }
          }
          serialization: {
            type: 'Json'
            properties: {
              encoding: 'UTF8'
              format: 'Array'
            }
          }
        }
      }
      {
        name: 'optimization-trigger'
        properties: {
          dataSource: {
            type: 'Microsoft.AzureFunction'
            properties: {
              functionAppName: functionApp.name
              functionName: 'TriggerOptimization'
              maxBatchCount: 10
              maxBatchSize: 65536
            }
          }
          serialization: {
            type: 'Json'
            properties: {
              encoding: 'UTF8'
              format: 'Array'
            }
          }
        }
      }
    ]
  }
}

// ==============================================================================
// RBAC ASSIGNMENTS
// ==============================================================================

// Grant Quantum Workspace Contributor access to Storage Account
resource quantumWorkspaceStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(quantumWorkspace.id, storageAccount.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: quantumWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to Digital Twins
resource functionAppDigitalTwinsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, digitalTwinsInstance.id, 'bcd981a7-7f74-457b-83e1-cceb9e632bbe')
  scope: digitalTwinsInstance
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'bcd981a7-7f74-457b-83e1-cceb9e632bbe') // Azure Digital Twins Data Owner
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to Quantum Workspace
resource functionAppQuantumRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, quantumWorkspace.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: quantumWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Stream Analytics access to Event Hub
resource streamAnalyticsEventHubRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(streamAnalyticsJob.id, eventHubsNamespace.id, 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde')
  scope: eventHubsNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde') // Azure Event Hubs Data Reader
    principalId: streamAnalyticsJob.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ==============================================================================
// DIAGNOSTIC SETTINGS
// ==============================================================================

// Diagnostic settings for Stream Analytics
resource streamAnalyticsDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'stream-analytics-diagnostics'
  scope: streamAnalyticsJob
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'Execution'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'Authoring'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('The name of the deployed Quantum Workspace.')
output quantumWorkspaceName string = quantumWorkspace.name

@description('The name of the deployed Digital Twins instance.')
output digitalTwinsInstanceName string = digitalTwinsInstance.name

@description('The hostname of the Digital Twins instance.')
output digitalTwinsHostName string = digitalTwinsInstance.properties.hostName

@description('The name of the deployed Function App.')
output functionAppName string = functionApp.name

@description('The name of the deployed Stream Analytics job.')
output streamAnalyticsJobName string = streamAnalyticsJob.name

@description('The name of the deployed storage account.')
output storageAccountName string = storageAccount.name

@description('The name of the deployed Cosmos DB account.')
output cosmosDbAccountName string = cosmosDbAccount.name

@description('The name of the deployed Event Hubs namespace.')
output eventHubsNamespaceName string = eventHubsNamespace.name

@description('The name of the deployed Event Hub.')
output eventHubName string = eventHub.name

@description('The Application Insights instrumentation key.')
@secure()
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('The Application Insights connection string.')
@secure()
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('The Log Analytics workspace ID.')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The resource group name.')
output resourceGroupName string = resourceGroup().name

@description('The subscription ID.')
output subscriptionId string = subscription().subscriptionId

@description('The Azure region where resources were deployed.')
output location string = location

@description('The unique suffix used for resource naming.')
output uniqueSuffix string = uniqueSuffix