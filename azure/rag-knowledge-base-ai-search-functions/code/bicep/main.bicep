@description('Main Bicep template for RAG Knowledge Base with AI Search and Functions')

// Parameters
@description('Prefix for all resource names')
@minLength(2)
@maxLength(10)
param resourcePrefix string = 'ragkb'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Environment suffix (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('AI Search service SKU')
@allowed(['free', 'basic', 'standard', 'standard2', 'standard3', 'storage_optimized_l1', 'storage_optimized_l2'])
param searchServiceSku string = 'basic'

@description('OpenAI service SKU')
@allowed(['S0'])
param openAiSku string = 'S0'

@description('Function App runtime version')
@allowed(['3.11'])
param functionRuntimeVersion string = '3.11'

@description('OpenAI model deployment name')
param openAiModelName string = 'gpt-4o'

@description('OpenAI model version')
param openAiModelVersion string = '2024-11-20'

@description('OpenAI deployment capacity')
@minValue(1)
@maxValue(120)
param openAiDeploymentCapacity int = 10

@description('Tags to apply to all resources')
param tags object = {
  Purpose: 'RAG Knowledge Base'
  Environment: environment
  Project: 'Azure Recipe'
}

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id)
var storageAccountName = '${resourcePrefix}storage${uniqueSuffix}'
var searchServiceName = '${resourcePrefix}-search-${uniqueSuffix}'
var functionAppName = '${resourcePrefix}-func-${uniqueSuffix}'
var openAiServiceName = '${resourcePrefix}-openai-${uniqueSuffix}'
var appServicePlanName = '${resourcePrefix}-plan-${uniqueSuffix}'
var applicationInsightsName = '${resourcePrefix}-insights-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-logs-${uniqueSuffix}'

// Log Analytics Workspace
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

// Application Insights
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

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
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
    isHnsEnabled: true // Enable hierarchical namespace for Data Lake
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
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
  }
}

// Storage Account Blob Services
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    changeFeed: {
      enabled: false
    }
    restorePolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: true
      days: 7
    }
    isVersioningEnabled: false
  }
}

// Documents Container
resource documentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'documents'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// AI Search Service
resource searchService 'Microsoft.Search/searchServices@2023-11-01' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: {
    name: searchServiceSku
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    networkRuleSet: {
      ipRules: []
    }
    disableLocalAuth: false
    authOptions: {
      apiKeyOnly: {}
    }
    semanticSearch: 'free' // Enable semantic search capabilities
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// OpenAI Service
resource openAiService 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: openAiServiceName
  location: location
  tags: tags
  sku: {
    name: openAiSku
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openAiServiceName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// OpenAI Model Deployment
resource openAiDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openAiService
  name: openAiModelName
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiModelName
      version: openAiModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'Standard'
    capacity: openAiDeploymentCapacity
  }
}

// App Service Plan (Consumption)
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
    reserved: true // Linux
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
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
      linuxFxVersion: 'Python|${functionRuntimeVersion}'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 0
      minimumElasticInstanceCount: 0
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
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
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'SEARCH_ENDPOINT'
          value: 'https://${searchService.name}.search.windows.net'
        }
        {
          name: 'SEARCH_API_KEY'
          value: searchService.listAdminKeys().primaryKey
        }
        {
          name: 'OPENAI_ENDPOINT'
          value: openAiService.properties.endpoint
        }
        {
          name: 'OPENAI_API_KEY'
          value: openAiService.listKeys().key1
        }
        {
          name: 'OPENAI_DEPLOYMENT'
          value: openAiModelName
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      }
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    containerSize: 1536
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// RBAC Assignments for Function App to access services
resource functionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionApp.id, 'Storage Blob Data Reader')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1') // Storage Blob Data Reader
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppSearchRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: searchService
  name: guid(searchService.id, functionApp.id, 'Search Service Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0') // Search Service Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppOpenAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: openAiService
  name: guid(openAiService.id, functionApp.id, 'Cognitive Services OpenAI User')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC Assignment for Search Service to access Storage
resource searchServiceStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, searchService.id, 'Storage Blob Data Reader')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1') // Storage Blob Data Reader
    principalId: searchService.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('Storage Account Primary Endpoint')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Documents Container Name')
output documentsContainerName string = documentsContainer.name

@description('AI Search Service Name')
output searchServiceName string = searchService.name

@description('AI Search Service Endpoint')
output searchServiceEndpoint string = 'https://${searchService.name}.search.windows.net'

@description('Function App Name')
output functionAppName string = functionApp.name

@description('Function App Default Hostname')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('OpenAI Service Name')
output openAiServiceName string = openAiService.name

@description('OpenAI Service Endpoint')
output openAiServiceEndpoint string = openAiService.properties.endpoint

@description('OpenAI Model Deployment Name')
output openAiDeploymentName string = openAiDeployment.name

@description('Application Insights Name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Deployment Summary')
output deploymentSummary object = {
  resourcePrefix: resourcePrefix
  environment: environment
  location: location
  uniqueSuffix: uniqueSuffix
  resourcesCreated: {
    storageAccount: storageAccountName
    searchService: searchServiceName
    functionApp: functionAppName
    openAiService: openAiServiceName
    applicationInsights: applicationInsightsName
    logAnalyticsWorkspace: logAnalyticsWorkspaceName
  }
  endpoints: {
    functionApp: 'https://${functionApp.properties.defaultHostName}'
    searchService: 'https://${searchService.name}.search.windows.net'
    openAiService: openAiService.properties.endpoint
    storageAccount: storageAccount.properties.primaryEndpoints.blob
  }
}