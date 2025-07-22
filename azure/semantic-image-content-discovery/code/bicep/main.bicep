// Main Bicep template for Intelligent Image Content Discovery with Azure AI Vision and Azure AI Search
// This template deploys a complete solution for AI-powered image analysis and searchable content discovery

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment suffix for resource naming (e.g., dev, prod)')
@minLength(2)
@maxLength(10)
param environmentSuffix string

@description('Project prefix for resource naming')
@minLength(2)
@maxLength(10)
param projectPrefix string = 'imgdiscov'

@description('Storage account tier for image storage')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Azure AI Vision service pricing tier')
@allowed([
  'F0'
  'S1'
])
param aiVisionSku string = 'S1'

@description('Azure AI Search service pricing tier')
@allowed([
  'free'
  'basic'
  'standard'
  'standard2'
  'standard3'
])
param searchServiceSku string = 'basic'

@description('Azure Functions hosting plan type')
@allowed([
  'Consumption'
  'Premium'
])
param functionPlanType string = 'Consumption'

@description('Function App runtime version')
@allowed([
  '~4'
  '~3'
])
param functionsVersion string = '~4'

@description('Tags to apply to all resources')
param tags object = {
  environment: environmentSuffix
  project: 'intelligent-image-discovery'
  solution: 'ai-vision-search'
}

// Variables for resource naming with consistent pattern
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var storageAccountName = '${projectPrefix}st${environmentSuffix}${uniqueSuffix}'
var aiVisionServiceName = '${projectPrefix}-aivision-${environmentSuffix}-${uniqueSuffix}'
var searchServiceName = '${projectPrefix}-aisearch-${environmentSuffix}-${uniqueSuffix}'
var functionAppName = '${projectPrefix}-func-${environmentSuffix}-${uniqueSuffix}'
var appServicePlanName = '${projectPrefix}-plan-${environmentSuffix}-${uniqueSuffix}'
var applicationInsightsName = '${projectPrefix}-ai-${environmentSuffix}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${projectPrefix}-law-${environmentSuffix}-${uniqueSuffix}'

// Storage Account for image repository
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
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
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Blob service configuration for image storage
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
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
    versioning: {
      enabled: true
    }
  }
}

// Container for storing images that will be processed
resource imagesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'images'
  properties: {
    publicAccess: 'None'
    metadata: {
      description: 'Container for image files to be analyzed by AI Vision'
    }
  }
}

// Azure AI Vision service for image analysis
resource aiVisionService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: aiVisionServiceName
  location: location
  tags: tags
  kind: 'ComputerVision'
  sku: {
    name: aiVisionSku
  }
  properties: {
    customSubDomainName: aiVisionServiceName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    disableLocalAuth: false
  }
}

// Azure AI Search service for intelligent content indexing
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
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    disableLocalAuth: false
    authOptions: {
      apiKeyOnly: {}
    }
  }
}

// Log Analytics Workspace for monitoring and diagnostics
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
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for application monitoring
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

// App Service Plan for Azure Functions
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = if (functionPlanType == 'Premium') {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    family: 'EP'
    capacity: 1
  }
  kind: 'elastic'
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: true
    maximumElasticWorkerCount: 20
    isSpot: false
    reserved: true
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
  }
}

// Function App for serverless image processing
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    enabled: true
    hostNameSslStates: [
      {
        name: '${functionAppName}.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Standard'
      }
    ]
    serverFarmId: functionPlanType == 'Premium' ? appServicePlan.id : null
    reserved: true
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'PYTHON|3.11'
      acrUseManagedIdentityCreds: false
      alwaysOn: functionPlanType == 'Premium'
      http20Enabled: false
      functionAppScaleLimit: functionPlanType == 'Consumption' ? 200 : 0
      minimumElasticInstanceCount: functionPlanType == 'Premium' ? 1 : 0
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
          name: 'VISION_ENDPOINT'
          value: aiVisionService.properties.endpoint
        }
        {
          name: 'VISION_KEY'
          value: aiVisionService.listKeys().key1
        }
        {
          name: 'SEARCH_ENDPOINT'
          value: 'https://${searchService.name}.search.windows.net'
        }
        {
          name: 'SEARCH_KEY'
          value: searchService.listAdminKeys().primaryKey
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
      ]
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
    publicNetworkAccess: 'Enabled'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Diagnostic settings for monitoring and alerting
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'storage-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

resource functionAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'function-diagnostics'
  scope: functionApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// RBAC assignments for Function App to access resources
resource functionAppStorageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppCognitiveServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiVisionService.id, functionApp.id, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: aiVisionService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908') // Cognitive Services User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppSearchIndexDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, functionApp.id, '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7') // Search Index Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs for reference and integration
@description('Storage account name for image uploads')
output storageAccountName string = storageAccount.name

@description('Storage account connection string')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('Images container name')
output imagesContainerName string = imagesContainer.name

@description('AI Vision service endpoint')
output aiVisionEndpoint string = aiVisionService.properties.endpoint

@description('AI Vision service name')
output aiVisionServiceName string = aiVisionService.name

@description('Azure AI Search service endpoint')
output searchServiceEndpoint string = 'https://${searchService.name}.search.windows.net'

@description('Azure AI Search service name')
output searchServiceName string = searchService.name

@description('Function App name for image processing')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Resource group location')
output deploymentLocation string = location

@description('Search service admin key (sensitive)')
@secure()
output searchServiceAdminKey string = searchService.listAdminKeys().primaryKey

@description('AI Vision service key (sensitive)')
@secure()
output aiVisionServiceKey string = aiVisionService.listKeys().key1

@description('Next steps and configuration guidance')
output nextSteps object = {
  step1: 'Deploy the Function App code for image processing using the provided Python functions'
  step2: 'Create the search index schema using the Azure AI Search REST API or Azure Portal'
  step3: 'Upload test images to the storage container to trigger automatic processing'
  step4: 'Configure search frontend application using the provided search endpoint and keys'
  step5: 'Monitor the solution using Application Insights and Log Analytics'
  documentation: 'Refer to the recipe documentation for detailed implementation steps'
}