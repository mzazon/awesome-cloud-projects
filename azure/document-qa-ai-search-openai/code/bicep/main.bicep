@description('Main Bicep template for Document Q&A with AI Search and OpenAI')
param location string = resourceGroup().location

@description('Base name for all resources')
param baseName string = 'docqa'

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Tags to apply to all resources')
param resourceTags object = {
  environment: environment
  solution: 'document-qa-ai-search-openai'
  'cost-center': 'engineering'
}

@description('OpenAI Service configuration')
param openAiConfig object = {
  embeddingModelName: 'text-embedding-3-large'
  embeddingModelVersion: '1'
  chatModelName: 'gpt-4o'
  chatModelVersion: '2024-11-20'
  embeddingCapacity: 30
  chatCapacity: 10
}

@description('AI Search service tier')
@allowed(['basic', 'standard', 'standard2', 'standard3'])
param searchServiceTier string = 'basic'

@description('Storage account tier')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountSku string = 'Standard_ZRS'

@description('Function App runtime version')
param functionsWorkerRuntime string = 'python'
param functionsRuntimeVersion string = '~4'

// Generate unique suffix for resource names
var uniqueSuffix = uniqueString(resourceGroup().id, deployment().name)
var naming = {
  storageAccount: 'st${baseName}${uniqueSuffix}'
  searchService: 'srch-${baseName}-${uniqueSuffix}'
  openAiService: 'oai-${baseName}-${uniqueSuffix}'
  functionApp: 'func-${baseName}-${uniqueSuffix}'
  appServicePlan: 'asp-${baseName}-${uniqueSuffix}'
  applicationInsights: 'appi-${baseName}-${uniqueSuffix}'
  logAnalytics: 'law-${baseName}-${uniqueSuffix}'
}

// Storage Account for documents and function app
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: naming.storageAccount
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
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
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

// Blob service and container for documents
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource documentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'documents'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Document storage for Q&A system'
    }
  }
}

// Azure OpenAI Service
resource openAiService 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: naming.openAiService
  location: location
  tags: resourceTags
  sku: {
    name: 'S0'
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: naming.openAiService
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: false
    disableLocalAuth: false
    apiProperties: {
      statisticsEnabled: false
    }
  }
}

// OpenAI Model Deployments
resource embeddingModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openAiService
  name: openAiConfig.embeddingModelName
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiConfig.embeddingModelName
      version: openAiConfig.embeddingModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'Standard'
    capacity: openAiConfig.embeddingCapacity
  }
}

resource chatModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openAiService
  name: openAiConfig.chatModelName
  dependsOn: [embeddingModelDeployment]
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiConfig.chatModelName
      version: openAiConfig.chatModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'Standard'
    capacity: openAiConfig.chatCapacity
  }
}

// Azure AI Search Service
resource searchService 'Microsoft.Search/searchServices@2023-11-01' = {
  name: naming.searchService
  location: location
  tags: resourceTags
  sku: {
    name: searchServiceTier
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    networkRuleSet: {
      ipRules: []
      bypass: 'AzurePortal'
    }
    semanticSearch: 'free'
    disableLocalAuth: false
    authOptions: {
      apiKeyOnly: {}
    }
  }
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: naming.logAnalytics
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      legacy: 0
      searchVersion: 1
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights for function monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: naming.applicationInsights
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    RetentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// App Service Plan for Functions (Consumption)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: naming.appServicePlan
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
    reserved: true // Required for Linux consumption plans
  }
  kind: 'functionapp'
}

// Function App for Q&A API
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: naming.functionApp
  location: location
  tags: resourceTags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Python|3.12'
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
          value: toLower(naming.functionApp)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: functionsRuntimeVersion
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionsWorkerRuntime
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
          name: 'SEARCH_SERVICE_NAME'
          value: searchService.name
        }
        {
          name: 'SEARCH_ADMIN_KEY'
          value: searchService.listAdminKeys().primaryKey
        }
        {
          name: 'SEARCH_INDEX_NAME'
          value: 'documents-index'
        }
        {
          name: 'OPENAI_ENDPOINT'
          value: openAiService.properties.endpoint
        }
        {
          name: 'OPENAI_KEY'
          value: openAiService.listKeys().key1
        }
        {
          name: 'EMBEDDING_DEPLOYMENT_NAME'
          value: openAiConfig.embeddingModelName
        }
        {
          name: 'CHAT_DEPLOYMENT_NAME'
          value: openAiConfig.chatModelName
        }
      ]
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      use32BitWorkerProcess: false
      http20Enabled: true
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
    }
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
  }
  dependsOn: [
    applicationInsights
  ]
}

// Role assignments for Function App to access services
resource functionAppSearchContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, functionApp.id, 'Search Service Contributor')
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0') // Search Service Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppStorageContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppCognitiveServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiService.id, functionApp.id, 'Cognitive Services OpenAI User')
  scope: openAiService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}


// Outputs for verification and integration
output resourceGroupName string = resourceGroup().name
output storageAccountName string = storageAccount.name
output storageAccountKey string = storageAccount.listKeys().keys[0].value
output documentsContainerName string = documentsContainer.name
output searchServiceName string = searchService.name
output searchServiceEndpoint string = 'https://${searchService.name}.search.windows.net'
output searchAdminKey string = searchService.listAdminKeys().primaryKey
output openAiServiceName string = openAiService.name
output openAiEndpoint string = openAiService.properties.endpoint
output openAiKey string = openAiService.listKeys().key1
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output embeddingModelDeploymentName string = embeddingModelDeployment.name
output chatModelDeploymentName string = chatModelDeployment.name

// Configuration outputs for post-deployment setup
output deploymentConfiguration object = {
  searchIndexName: 'documents-index'
  skillsetName: 'documents-skillset'
  datasourceName: 'documents-datasource'
  indexerName: 'documents-indexer'
  containerName: documentsContainer.name
  embeddingModelName: openAiConfig.embeddingModelName
  chatModelName: openAiConfig.chatModelName
  functionApiUrl: 'https://${functionApp.properties.defaultHostName}/api/qa'
}