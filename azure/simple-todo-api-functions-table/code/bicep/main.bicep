// Simple Todo API with Azure Functions and Table Storage
// This template creates a serverless REST API using Azure Functions with Table Storage

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Prefix for resource names')
@minLength(3)
@maxLength(10)
param resourcePrefix string

@description('Enable Application Insights monitoring')
param enableApplicationInsights bool = true

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Function App runtime stack')
@allowed(['node', 'python', 'dotnet'])
param runtimeStack string = 'node'

@description('Function App runtime version')
param runtimeVersion string = '18'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: 'SimpleTodoAPI'
  ManagedBy: 'Bicep'
}

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id, resourcePrefix), 0, 6)
var storageAccountName = toLower('${resourcePrefix}storage${uniqueSuffix}')
var functionAppName = toLower('${resourcePrefix}-todoapi-${environment}-${uniqueSuffix}')
var appServicePlanName = toLower('${resourcePrefix}-plan-${environment}-${uniqueSuffix}')
var applicationInsightsName = toLower('${resourcePrefix}-ai-${environment}-${uniqueSuffix}')

// Storage Account for both Function App and Table Storage
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: storageAccountSku
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    allowCrossTenantReplication: false
    defaultToOAuthAuthentication: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    supportsHttpsTrafficOnly: true
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
        table: {
          enabled: true
          keyType: 'Account'
        }
        queue: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
      requireInfrastructureEncryption: true
    }
  }
  tags: tags
}

// Table Service for Todo storage
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

// Todos table
resource todosTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  parent: tableService
  name: 'todos'
  properties: {}
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 30
    WorkspaceResourceId: null
    IngestionMode: 'ApplicationInsights'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: tags
}

// App Service Plan for Function App (Consumption Plan)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    reserved: runtimeStack == 'python' || runtimeStack == 'node'
  }
  tags: tags
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    enabled: true
    httpsOnly: true
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
    redundancyMode: 'None'
    siteConfig: {
      alwaysOn: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      remoteDebuggingEnabled: false
      webSocketsEnabled: false
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
      use32BitWorkerProcess: false
      linuxFxVersion: runtimeStack == 'node' ? 'Node|${runtimeVersion}' : (runtimeStack == 'python' ? 'Python|${runtimeVersion}' : '')
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
          value: runtimeStack
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: runtimeStack == 'node' ? '~${runtimeVersion}' : ''
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
          name: 'AZURE_STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'WEBSITE_ENABLE_SYNC_UPDATE_SITE'
          value: 'true'
        }
      ]
    }
  }
  tags: tags

  // Function App configuration
  resource config 'config@2023-01-01' = {
    name: 'web'
    properties: {
      numberOfWorkers: 1
      defaultDocuments: []
      netFrameworkVersion: 'v4.0'
      phpVersion: 'OFF'
      requestTracingEnabled: false
      remoteDebuggingEnabled: false
      httpLoggingEnabled: false
      logsDirectorySizeLimit: 35
      detailedErrorLoggingEnabled: false
      publishingUsername: '$${functionAppName}'
      scmType: 'None'
      use32BitWorkerProcess: false
      webSocketsEnabled: false
      alwaysOn: false
      managedPipelineMode: 'Integrated'
      virtualApplications: [
        {
          virtualPath: '/'
          physicalPath: 'site\\wwwroot'
          preloadEnabled: false
        }
      ]
      loadBalancing: 'LeastRequests'
      experiments: {
        rampUpRules: []
      }
      autoHealEnabled: false
      localMySqlEnabled: false
      ipSecurityRestrictions: [
        {
          ipAddress: 'Any'
          action: 'Allow'
          priority: 2147483647
          name: 'Allow all'
          description: 'Allow all access'
        }
      ]
      scmIpSecurityRestrictions: [
        {
          ipAddress: 'Any'
          action: 'Allow'
          priority: 2147483647
          name: 'Allow all'
          description: 'Allow all access'
        }
      ]
      scmIpSecurityRestrictionsUseMain: false
      http20Enabled: true
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      preWarmedInstanceCount: 0
      functionAppScaleLimit: 200
      functionsRuntimeScaleMonitoringEnabled: false
      minimumElasticInstanceCount: 0
    }
  }
}

// Storage Account role assignment for Function App
resource storageContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '17d1049b-9a84-46fb-8f53-869881c3d3ab' // Storage Account Contributor
}

resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionApp.id, storageContributorRoleDefinition.id)
  properties: {
    roleDefinitionId: storageContributorRoleDefinition.id
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Table Storage role assignment for Function App
resource storageTableDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Storage Table Data Contributor
}

resource tableStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionApp.id, storageTableDataContributorRoleDefinition.id)
  properties: {
    roleDefinitionId: storageTableDataContributorRoleDefinition.id
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The URL of the Function App')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the Storage Account')
output storageAccountName string = storageAccount.name

@description('The name of the Todos table')
output todosTableName string = todosTable.name

@description('Function App Principal ID for additional role assignments')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Storage Connection String (for local development)')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('API Base URL for testing')
output apiBaseUrl string = 'https://${functionApp.properties.defaultHostName}/api'

@description('Sample curl commands for testing the API')
output testCommands object = {
  createTodo: 'curl -X POST "${apiBaseUrl}/todos" -H "Content-Type: application/json" -d \'{"title": "Learn Azure Functions", "description": "Complete the serverless tutorial", "completed": false}\''
  getTodos: 'curl -X GET "${apiBaseUrl}/todos"'
  updateTodo: 'curl -X PUT "${apiBaseUrl}/todos/{id}" -H "Content-Type: application/json" -d \'{"title": "Learn Azure Functions", "description": "Complete the serverless tutorial", "completed": true}\''
  deleteTodo: 'curl -X DELETE "${apiBaseUrl}/todos/{id}"'
}