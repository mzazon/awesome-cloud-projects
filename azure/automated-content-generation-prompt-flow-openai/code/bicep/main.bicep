// ==================================================================================================
// Azure Bicep Template: Automated Content Generation with Prompt Flow and OpenAI
// ==================================================================================================
// This template deploys a complete serverless content generation system using Azure AI services
// including Prompt Flow, OpenAI Service, Functions, and supporting infrastructure.

@description('Specifies the Azure region for all resources')
param location string = resourceGroup().location

@description('Environment designation for resource naming and configuration')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'content-generation'
  environment: environment
  deployedBy: 'bicep'
  recipe: 'automated-content-generation-prompt-flow-openai'
}

@description('Azure OpenAI Service pricing tier')
@allowed(['S0'])
param openAiSku string = 'S0'

@description('Cosmos DB throughput for the content metadata container')
@minValue(400)
@maxValue(4000)
param cosmosDbThroughput int = 400

@description('Storage account SKU for content assets')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Function App pricing tier')
@allowed(['Y1', 'EP1', 'EP2'])
param functionAppPlanSku string = 'Y1'

// ==================================================================================================
// Variables
// ==================================================================================================

var resourceNames = {
  mlWorkspace: 'ml-contentgen-${uniqueSuffix}'
  storageAccount: 'storcontentgen${uniqueSuffix}'
  openAiAccount: 'aoai-contentgen-${uniqueSuffix}'
  functionApp: 'func-contentgen-${uniqueSuffix}'
  functionAppPlan: 'plan-contentgen-${uniqueSuffix}'
  cosmosAccount: 'cosmos-contentgen-${uniqueSuffix}'
  keyVault: 'kv-contentgen-${uniqueSuffix}'
  applicationInsights: 'appi-contentgen-${uniqueSuffix}'
  logAnalytics: 'log-contentgen-${uniqueSuffix}'
}

var openAiDeployments = [
  {
    name: 'gpt-4o-content'
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-11-20'
    }
    sku: {
      name: 'Standard'
      capacity: 10
    }
  }
  {
    name: 'text-embedding-ada-002'
    model: {
      format: 'OpenAI'
      name: 'text-embedding-ada-002'
      version: '2'
    }
    sku: {
      name: 'Standard'
      capacity: 10
    }
  }
]

// ==================================================================================================
// Log Analytics Workspace for Application Insights
// ==================================================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
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

// ==================================================================================================
// Application Insights for Function App monitoring
// ==================================================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
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

// ==================================================================================================
// Key Vault for secure credential storage
// ==================================================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    accessPolicies: []
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ==================================================================================================
// Storage Account for content assets and function app storage
// ==================================================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true // Enable hierarchical namespace for Data Lake capabilities
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
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

// Content template container
resource contentTemplatesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: storageAccount::blobServices
  name: 'content-templates'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'content-template-storage'
    }
  }
}

// Generated content container
resource generatedContentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: storageAccount::blobServices
  name: 'generated-content'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'generated-content-storage'
    }
  }
}

// Blob services (required for containers)
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// ==================================================================================================
// Cosmos DB Account for content metadata and analytics
// ==================================================================================================

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: resourceNames.cosmosAccount
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Eventual'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    capabilities: []
    publicNetworkAccess: 'Enabled'
    networkAclBypass: 'AzureServices'
  }
}

// Content Generation database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosDbAccount
  name: 'ContentGeneration'
  properties: {
    resource: {
      id: 'ContentGeneration'
    }
  }
}

// Content metadata container with campaign-based partitioning
resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDatabase
  name: 'ContentMetadata'
  properties: {
    resource: {
      id: 'ContentMetadata'
      partitionKey: {
        paths: ['/campaignId']
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
      throughput: cosmosDbThroughput
    }
  }
}

// ==================================================================================================
// Azure OpenAI Service for content generation AI models
// ==================================================================================================

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = {
  name: resourceNames.openAiAccount
  location: location
  tags: tags
  sku: {
    name: openAiSku
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: resourceNames.openAiAccount
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Deploy AI models for content generation
resource openAiDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-04-01-preview' = [for deployment in openAiDeployments: {
  parent: openAiAccount
  name: deployment.name
  properties: {
    model: deployment.model
    raiPolicyName: null
  }
  sku: deployment.sku
}]

// ==================================================================================================
// Azure Machine Learning Workspace for Prompt Flow
// ==================================================================================================

resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: resourceNames.mlWorkspace
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'Content Generation ML Workspace'
    description: 'Azure Machine Learning workspace for AI-powered content generation workflows'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: applicationInsights.id
    publicNetworkAccess: 'Enabled'
    v1LegacyMode: false
    managedNetwork: {
      isolationMode: 'Disabled'
    }
  }
}

// ==================================================================================================
// Function App for serverless orchestration
// ==================================================================================================

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: resourceNames.functionAppPlan
  location: location
  tags: tags
  sku: {
    name: functionAppPlanSku
    tier: functionAppPlanSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  kind: 'functionapp'
  properties: {
    reserved: true // Linux hosting
  }
}

// Function App for content generation orchestration
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: resourceNames.functionApp
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
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
          value: 'python'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        // Environment variables for AI service integration
        {
          name: 'ML_WORKSPACE_NAME'
          value: mlWorkspace.name
        }
        {
          name: 'RESOURCE_GROUP'
          value: resourceGroup().name
        }
        {
          name: 'SUBSCRIPTION_ID'
          value: subscription().subscriptionId
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
          name: 'STORAGE_CONNECTION'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'OPENAI_ENDPOINT'
          value: openAiAccount.properties.endpoint
        }
        {
          name: 'OPENAI_KEY'
          value: openAiAccount.listKeys().key1
        }
      ]
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

// ==================================================================================================
// Role Assignments for Function App System Identity
// ==================================================================================================

// Cognitive Services User role for OpenAI access
resource cognitiveServicesUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, openAiAccount.id, 'CognitiveServicesUser')
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908') // Cognitive Services User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Data Contributor role for content storage
resource storageBlobDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, storageAccount.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Cosmos DB Built-in Data Contributor role
resource cosmosDbDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, cosmosDbAccount.id, 'CosmosDBDataContributor')
  scope: cosmosDbAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00000000-0000-0000-0000-000000000002') // Cosmos DB Built-in Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Machine Learning Workspace Contributor for Prompt Flow access
resource mlWorkspaceContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, mlWorkspace.id, 'MLWorkspaceContributor')
  scope: mlWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ==================================================================================================
// Outputs
// ==================================================================================================

@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The location where resources were deployed')
output location string = location

@description('The name of the ML workspace for Prompt Flow')
output mlWorkspaceName string = mlWorkspace.name

@description('The endpoint URL of the Azure OpenAI service')
output openAiEndpoint string = openAiAccount.properties.endpoint

@description('The name of the Azure OpenAI account')
output openAiAccountName string = openAiAccount.name

@description('The endpoint URL of the Cosmos DB account')
output cosmosDbEndpoint string = cosmosDbAccount.properties.documentEndpoint

@description('The name of the Cosmos DB account')
output cosmosDbAccountName string = cosmosDbAccount.name

@description('The name of the storage account for content assets')
output storageAccountName string = storageAccount.name

@description('The name of the Function App for content generation')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The Key Vault URI for secure credential storage')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Resource names for reference and debugging')
output resourceNames object = resourceNames

@description('OpenAI model deployments information')
output openAiDeployments array = [for (deployment, i) in openAiDeployments: {
  name: deployment.name
  modelName: deployment.model.name
  modelVersion: deployment.model.version
  endpoint: '${openAiAccount.properties.endpoint}deployments/${deployment.name}'
}]

@description('Storage container information')
output storageContainers object = {
  contentTemplates: {
    name: contentTemplatesContainer.name
    url: '${storageAccount.properties.primaryEndpoints.blob}${contentTemplatesContainer.name}'
  }
  generatedContent: {
    name: generatedContentContainer.name
    url: '${storageAccount.properties.primaryEndpoints.blob}${generatedContentContainer.name}'
  }
}

@description('Cosmos DB database and container information')
output cosmosDbInfo object = {
  databaseName: cosmosDatabase.name
  containerName: cosmosContainer.name
  partitionKey: '/campaignId'
  throughput: cosmosDbThroughput
}

@description('Deployment summary with key information')
output deploymentSummary object = {
  environment: environment
  uniqueSuffix: uniqueSuffix
  functionAppUrl: 'https://${functionApp.properties.defaultHostName}'
  mlWorkspace: mlWorkspace.name
  openAiEndpoint: openAiAccount.properties.endpoint
  cosmosDbEndpoint: cosmosDbAccount.properties.documentEndpoint
  storageAccount: storageAccount.name
  deploymentTimestamp: utcNow()
}