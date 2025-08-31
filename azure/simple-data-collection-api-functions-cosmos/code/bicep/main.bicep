@description('The name of the resource group. Will be used for resource naming.')
param resourceGroupName string = resourceGroup().name

@description('The Azure region where resources will be deployed.')
param location string = resourceGroup().location

@description('Environment designation (e.g., dev, test, prod).')
@allowed([
  'dev'
  'test'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness.')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('The pricing tier for the Cosmos DB account.')
@allowed([
  'Free'
  'Standard'
])
param cosmosDbAccountTier string = 'Free'

@description('The default consistency level for the Cosmos DB account.')
@allowed([
  'Eventual'
  'ConsistentPrefix'
  'Session'
  'BoundedStaleness'
  'Strong'
])
param cosmosDbConsistencyLevel string = 'Session'

@description('Enable automatic failover for the Cosmos DB account.')
param cosmosDbEnableAutomaticFailover bool = false

@description('The database name for Cosmos DB.')
param databaseName string = 'DataCollectionDB'

@description('The container name for Cosmos DB.')
param containerName string = 'records'

@description('The partition key path for the Cosmos DB container.')
param partitionKeyPath string = '/id'

@description('The throughput (RU/s) for the Cosmos DB container.')
@minValue(400)
@maxValue(100000)
param containerThroughput int = 400

@description('The SKU for the storage account.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('The Node.js runtime version for the Function App.')
@allowed([
  '18'
  '20'
])
param nodeJsVersion string = '20'

@description('The Azure Functions runtime version.')
@allowed([
  '~4'
])
param functionsVersion string = '~4'

@description('Tags to apply to all resources.')
param resourceTags object = {
  Environment: environment
  Purpose: 'DataCollectionAPI'
  Recipe: 'SimpleDataCollectionAPI'
  ManagedBy: 'Bicep'
}

// Variables for resource naming
var namingPrefix = 'data-api-${environment}'
var cosmosAccountName = 'cosmos-${namingPrefix}-${uniqueSuffix}'
var functionAppName = 'func-${namingPrefix}-${uniqueSuffix}'
var storageAccountName = 'st${replace(namingPrefix, '-', '')}${uniqueSuffix}'
var appServicePlanName = 'asp-${namingPrefix}-${uniqueSuffix}'
var applicationInsightsName = 'ai-${namingPrefix}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'log-${namingPrefix}-${uniqueSuffix}'

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: resourceTags
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

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for Azure Functions
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    encryption: {
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
      keySource: 'Microsoft.Storage'
    }
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
  }
}

// Cosmos DB Account
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosAccountName
  location: location
  tags: resourceTags
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
    databaseAccountOfferType: cosmosDbAccountTier
    enableAutomaticFailover: cosmosDbEnableAutomaticFailover
    enableMultipleWriteLocations: false
    capabilities: []
    publicNetworkAccess: 'Enabled'
    networkAclBypass: 'None'
    disableKeyBasedMetadataWriteAccess: false
    enableFreeTier: cosmosDbAccountTier == 'Free'
    analyticalStorageConfiguration: {
      schemaType: 'WellDefined'
    }
    capacity: {
      totalThroughputLimit: cosmosDbAccountTier == 'Free' ? 1000 : -1
    }
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
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosDbAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
    options: cosmosDbAccountTier == 'Free' ? {} : {
      throughput: 400
    }
  }
}

// Cosmos DB Container
resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDatabase
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          partitionKeyPath
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
    options: {
      throughput: containerThroughput
    }
  }
}

// App Service Plan for Azure Functions (Consumption)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: resourceTags
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

// Azure Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: resourceTags
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
          value: functionsVersion
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~${nodeJsVersion}'
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
          name: 'COSMOS_DB_CONNECTION_STRING'
          value: cosmosDbAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
        {
          name: 'COSMOS_DB_DATABASE_NAME'
          value: databaseName
        }
        {
          name: 'COSMOS_DB_CONTAINER_NAME'
          value: containerName
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      cors: {
        allowedOrigins: [
          '*'
        ]
        supportCredentials: false
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
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
  }
}

// Outputs
@description('The name of the resource group.')
output resourceGroupName string = resourceGroup().name

@description('The Azure region where resources were deployed.')
output location string = location

@description('The name of the Cosmos DB account.')
output cosmosDbAccountName string = cosmosDbAccount.name

@description('The endpoint URL for the Cosmos DB account.')
output cosmosDbAccountEndpoint string = cosmosDbAccount.properties.documentEndpoint

@description('The name of the Cosmos DB database.')
output cosmosDbDatabaseName string = cosmosDatabase.name

@description('The name of the Cosmos DB container.')
output cosmosDbContainerName string = cosmosContainer.name

@description('The name of the storage account.')
output storageAccountName string = storageAccount.name

@description('The primary endpoint for the storage account.')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The name of the Function App.')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App.')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The URL of the Function App.')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The base URL for the API endpoints.')
output apiBaseUrl string = 'https://${functionApp.properties.defaultHostName}/api'

@description('The name of the Application Insights instance.')
output applicationInsightsName string = applicationInsights.name

@description('The instrumentation key for Application Insights.')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The connection string for Application Insights.')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Example API endpoints for testing.')
output apiEndpoints object = {
  createRecord: 'POST ${functionApp.properties.defaultHostName}/api/records'
  getRecords: 'GET ${functionApp.properties.defaultHostName}/api/records'
  getRecord: 'GET ${functionApp.properties.defaultHostName}/api/records/{id}'
  updateRecord: 'PUT ${functionApp.properties.defaultHostName}/api/records/{id}'
  deleteRecord: 'DELETE ${functionApp.properties.defaultHostName}/api/records/{id}'
}

@description('Resource tags applied to all resources.')
output resourceTags object = resourceTags

@description('Estimated monthly cost information.')
output estimatedMonthlyCost object = {
  cosmosDb: 'Free tier: $0/month, Standard: ~$24/month (400 RU/s)'
  functionApp: 'Consumption plan: $0 for first 1M executions, then $0.20 per 1M executions'
  storageAccount: 'Standard_LRS: ~$0.02/GB/month'
  applicationInsights: 'First 5GB/month free, then $2.30/GB'
  totalEstimate: '$3-8/month for typical development workloads'
}