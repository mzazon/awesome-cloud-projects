@description('Main Bicep template for Customer Support Assistant with OpenAI and Azure Functions')

// ============================================================================
// PARAMETERS
// ============================================================================

@description('The location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Application name prefix for resource naming')
@minLength(3)
@maxLength(10)
param appName string = 'support'

@description('Unique suffix for resource names to ensure global uniqueness')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Azure OpenAI Service pricing tier')
@allowed(['S0'])
param openAiSkuName string = 'S0'

@description('GPT model deployment name')
param gptModelName string = 'gpt-4o'

@description('GPT model version to deploy')
param gptModelVersion string = '2024-11-20'

@description('Function App runtime version')
param functionAppRuntime string = 'node'

@description('Function App runtime version')
param functionAppRuntimeVersion string = '20'

@description('Storage account type')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountType string = 'Standard_LRS'

@description('Enable Azure OpenAI content filtering')
param enableContentFilter bool = true

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Application: 'CustomerSupportAssistant'
  Purpose: 'Recipe'
}

// ============================================================================
// VARIABLES
// ============================================================================

var resourcePrefix = '${appName}-${environment}'
var storageAccountName = '${replace(resourcePrefix, '-', '')}data${resourceSuffix}'
var functionAppName = '${resourcePrefix}-functions-${resourceSuffix}'
var openAiAccountName = '${resourcePrefix}-openai-${resourceSuffix}'
var appServicePlanName = '${resourcePrefix}-plan-${resourceSuffix}'
var applicationInsightsName = '${resourcePrefix}-insights-${resourceSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-logs-${resourceSuffix}'

// Function names as defined in the recipe
var functionNames = [
  'ticketLookup'
  'faqRetrieval'
  'ticketCreation'
  'escalation'
]

// ============================================================================
// RESOURCES
// ============================================================================

// Log Analytics Workspace for Application Insights
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
      searchVersion: 1
      legacy: 0
    }
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
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

// Storage Account for Functions and support data
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountType
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
        }
        file: {
          enabled: true
        }
        table: {
          enabled: true
        }
        queue: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Table Storage for tickets and customers
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

resource ticketsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  parent: tableService
  name: 'tickets'
  properties: {}
}

resource customersTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  parent: tableService
  name: 'customers'
  properties: {}
}

// Blob Storage for FAQ documents
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource faqContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'faqs'
  properties: {
    publicAccess: 'None'
  }
}

// Queue Storage for escalations
resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

resource escalationQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-01-01' = {
  parent: queueService
  name: 'escalations'
  properties: {
    metadata: {
      purpose: 'Support ticket escalation queue'
    }
  }
}

// Azure OpenAI Service
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-06-01-preview' = {
  name: openAiAccountName
  location: location
  tags: tags
  sku: {
    name: openAiSkuName
  }
  kind: 'OpenAI'
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
    customSubDomainName: openAiAccountName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
}

// GPT-4o Model Deployment
resource gptModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-06-01-preview' = {
  parent: openAiAccount
  name: gptModelName
  properties: {
    model: {
      format: 'OpenAI'
      name: gptModelName
      version: gptModelVersion
    }
    scaleSettings: {
      scaleType: 'Standard'
    }
  }
}

// App Service Plan for Functions (Consumption)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
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

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
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
          value: '~20'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionAppRuntime
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
          name: 'OPENAI_ENDPOINT'
          value: openAiAccount.properties.endpoint
        }
        {
          name: 'OPENAI_KEY'
          value: openAiAccount.listKeys().key1
        }
        {
          name: 'OPENAI_MODEL_DEPLOYMENT'
          value: gptModelName
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
    }
  }
}

// Managed Identity for Function App
resource functionAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${functionAppName}-identity'
  location: location
  tags: tags
}

// Role assignments for Function App to access OpenAI and Storage
resource openAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: openAiAccount
  name: guid(openAiAccount.id, functionApp.id, 'OpenAI User')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionApp.id, 'Storage Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The location of the deployed resources')
output location string = location

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The connection string for the storage account')
@secure()
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppHostName string = functionApp.properties.defaultHostName

@description('The URL of the Function App')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the Azure OpenAI account')
output openAiAccountName string = openAiAccount.name

@description('The endpoint URL for the Azure OpenAI service')
output openAiEndpoint string = openAiAccount.properties.endpoint

@description('The deployed model name')
output gptModelDeploymentName string = gptModelDeployment.name

@description('Application Insights Instrumentation Key')
@secure()
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights Connection String')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Resource naming information for reference')
output resourceInfo object = {
  storageAccount: storageAccountName
  functionApp: functionAppName
  openAiAccount: openAiAccountName
  appServicePlan: appServicePlanName
  applicationInsights: applicationInsightsName
  logAnalyticsWorkspace: logAnalyticsWorkspaceName
}

@description('Storage service endpoints')
output storageEndpoints object = {
  blob: storageAccount.properties.primaryEndpoints.blob
  table: storageAccount.properties.primaryEndpoints.table
  queue: storageAccount.properties.primaryEndpoints.queue
  file: storageAccount.properties.primaryEndpoints.file
}

@description('Function authentication information')
output functionAuthInfo object = {
  functionAppResourceId: functionApp.id
  principalId: functionApp.identity.principalId
  tenantId: functionApp.identity.tenantId
}

@description('Deployment summary')
output deploymentSummary object = {
  environment: environment
  resourcePrefix: resourcePrefix
  resourceSuffix: resourceSuffix
  functionsDeployed: functionNames
  tablesCreated: ['tickets', 'customers']
  containersCreated: ['faqs']
  queuesCreated: ['escalations']
  openAiModel: '${gptModelName}:${gptModelVersion}'
}