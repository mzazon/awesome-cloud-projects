@description('Main Bicep template for Simple Expense Tracker with Cosmos DB and Functions')

// Parameters
@description('The Azure region for resource deployment')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Application name prefix for resource naming')
@maxLength(8)
param appName string = 'expenses'

@description('Unique suffix for resource naming (3-6 characters)')
@minLength(3)
@maxLength(6)
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'recipe'
  environment: environment
  application: 'expense-tracker'
}

@description('Cosmos DB consistency level')
@allowed(['Eventual', 'Session', 'BoundedStaleness', 'Strong', 'ConsistentPrefix'])
param cosmosConsistencyLevel string = 'Session'

@description('Enable Cosmos DB automatic failover')
param cosmosAutomaticFailover bool = false

@description('Function App runtime stack')
@allowed(['node', 'dotnet', 'python'])
param functionRuntime string = 'node'

@description('Function App runtime version')
param functionRuntimeVersion string = '~4'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

// Variables
var resourceNames = {
  cosmosAccount: 'cosmos-${appName}-${uniqueSuffix}'
  functionApp: 'func-${appName}-${uniqueSuffix}'
  storageAccount: 'st${appName}${uniqueSuffix}'
  hostingPlan: 'plan-${appName}-${uniqueSuffix}'
  applicationInsights: 'ai-${appName}-${uniqueSuffix}'
  logAnalyticsWorkspace: 'law-${appName}-${uniqueSuffix}'
}

var cosmosDbSettings = {
  databaseName: 'ExpenseDB'
  containerName: 'Expenses'
  partitionKeyPath: '/userId'
}

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
  }
}

// Storage Account for Function App
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
  }
}

// Cosmos DB Account (Serverless)
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: resourceNames.cosmosAccount
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: cosmosConsistencyLevel
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: cosmosAutomaticFailover
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    backupPolicy: {
      type: 'Continuous'
    }
    networkAclBypass: 'AzureServices'
    disableKeyBasedMetadataWriteAccess: false
  }
}

// Cosmos DB Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosAccount
  name: cosmosDbSettings.databaseName
  properties: {
    resource: {
      id: cosmosDbSettings.databaseName
    }
  }
}

// Cosmos DB Container
resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDatabase
  name: cosmosDbSettings.containerName
  properties: {
    resource: {
      id: cosmosDbSettings.containerName
      partitionKey: {
        paths: [
          cosmosDbSettings.partitionKeyPath
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

// App Service Plan (Consumption)
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
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
  properties: {
    reserved: true
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: resourceNames.functionApp
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: hostingPlan.id
    reserved: true
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
          value: '${resourceNames.functionApp}-content'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: functionRuntimeVersion
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionRuntime
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
          name: 'CosmosDBConnection'
          value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
        {
          name: 'COSMOS_DB_DATABASE_NAME'
          value: cosmosDbSettings.databaseName
        }
        {
          name: 'COSMOS_DB_CONTAINER_NAME'
          value: cosmosDbSettings.containerName
        }
      ]
      linuxFxVersion: '${upper(functionRuntime)}|18'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Role assignment for Function App to access Cosmos DB
resource functionAppCosmosRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosAccount.id, functionApp.id, 'DocumentDB Account Contributor')
  scope: cosmosAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5bd9cd88-fe45-4216-938b-f97437e15450') // DocumentDB Account Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Cosmos DB Account name')
output cosmosAccountName string = cosmosAccount.name

@description('Cosmos DB Account endpoint')
output cosmosAccountEndpoint string = cosmosAccount.properties.documentEndpoint

@description('Cosmos DB Database name')
output cosmosDatabaseName string = cosmosDatabase.name

@description('Cosmos DB Container name')
output cosmosContainerName string = cosmosContainer.name

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Function App principal ID for role assignments')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Function keys for API access')
output functionKeys object = {
  description: 'Retrieve function keys using: az functionapp keys list --name ${functionApp.name} --resource-group ${resourceGroup().name}'
  createExpenseUrl: 'https://${functionApp.properties.defaultHostName}/api/CreateExpense'
  getExpensesUrl: 'https://${functionApp.properties.defaultHostName}/api/GetExpenses'
}

@description('Deployment summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  environment: environment
  cosmosAccount: cosmosAccount.name
  functionApp: functionApp.name
  storageAccount: storageAccount.name
  applicationInsights: applicationInsights.name
  estimatedMonthlyCost: 'Serverless tiers: $0.01-$5.00 for light usage'
}