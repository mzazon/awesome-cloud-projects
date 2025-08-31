// ============================================================================
// Intelligent Model Selection with Model Router and Event Grid
// ============================================================================
// This template deploys an event-driven AI orchestration system that
// automatically routes requests to optimal models based on complexity analysis
// ============================================================================

@description('Primary location for resource deployment')
param location string = resourceGroup().location

@description('Environment suffix for resource naming (e.g., dev, prod)')
@minLength(2)
@maxLength(8)
param environmentSuffix string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
@minLength(3)
@maxLength(6)
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('SKU for the AI Services resource')
@allowed(['S0', 'S1', 'S2'])
param aiServicesSku string = 'S0'

@description('Capacity for the Model Router deployment')
@minValue(1)
@maxValue(100)
param modelRouterCapacity int = 50

@description('Resource tags to apply to all resources')
param tags object = {
  environment: environmentSuffix
  purpose: 'intelligent-model-router'
  costCenter: 'ai-operations'
}

// ============================================================================
// VARIABLES
// ============================================================================

var resourceNames = {
  storageAccount: 'stmodelrt${uniqueSuffix}${environmentSuffix}'
  functionApp: 'func-router-${uniqueSuffix}-${environmentSuffix}'
  aiFoundryResource: 'ai-foundry-${uniqueSuffix}-${environmentSuffix}'
  eventGridTopic: 'egt-router-${uniqueSuffix}-${environmentSuffix}'
  appInsights: 'ai-router-${uniqueSuffix}-${environmentSuffix}'
  logAnalyticsWorkspace: 'law-router-${uniqueSuffix}-${environmentSuffix}'
  hostingPlan: 'asp-router-${uniqueSuffix}-${environmentSuffix}'
}

var modelRouterConfig = {
  deploymentName: 'model-router-deployment'
  modelName: 'model-router'
  modelVersion: '2025-05-19'
  modelFormat: 'OpenAI'
  skuName: 'Standard'
}

// ============================================================================
// LOG ANALYTICS WORKSPACE
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
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

// ============================================================================
// APPLICATION INSIGHTS
// ============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.appInsights
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

// ============================================================================
// STORAGE ACCOUNT
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
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

// ============================================================================
// EVENT GRID TOPIC
// ============================================================================

resource eventGridTopic 'Microsoft.EventGrid/topics@2024-06-01-preview' = {
  name: resourceNames.eventGridTopic
  location: location
  tags: tags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    dataResidencyBoundary: 'WithinGeopair'
  }
}

// ============================================================================
// AI SERVICES (AZURE AI FOUNDRY)
// ============================================================================

resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: resourceNames.aiFoundryResource
  location: location
  tags: tags
  sku: {
    name: aiServicesSku
  }
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: resourceNames.aiFoundryResource
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    apiProperties: {
      statisticsEnabled: false
    }
    disableLocalAuth: false
  }
}

// ============================================================================
// MODEL ROUTER DEPLOYMENT
// ============================================================================

resource modelRouterDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiServices
  name: modelRouterConfig.deploymentName
  properties: {
    model: {
      format: modelRouterConfig.modelFormat
      name: modelRouterConfig.modelName
      version: modelRouterConfig.modelVersion
    }
    raiPolicyName: 'Microsoft.Default'
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
  sku: {
    name: modelRouterConfig.skuName
    capacity: modelRouterCapacity
  }
}

// ============================================================================
// APP SERVICE PLAN
// ============================================================================

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
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
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: false
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
  }
}

// ============================================================================
// FUNCTION APP
// ============================================================================

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: resourceNames.functionApp
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
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
          value: toLower(resourceNames.functionApp)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'AzureWebJobsFeatureFlags'
          value: 'EnableWorkerIndexing'
        }
        {
          name: 'AI_FOUNDRY_ENDPOINT'
          value: aiServices.properties.endpoint
        }
        {
          name: 'AI_FOUNDRY_KEY'
          value: aiServices.listKeys().key1
        }
        {
          name: 'MODEL_DEPLOYMENT_NAME'
          value: modelRouterConfig.deploymentName
        }
        {
          name: 'EVENT_GRID_ENDPOINT'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EVENT_GRID_KEY'
          value: eventGridTopic.listKeys().key1
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      netFrameworkVersion: 'v4.0'
      pythonVersion: '3.11'
    }
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
  dependsOn: [
    modelRouterDeployment
  ]
}

// ============================================================================
// EVENT GRID SUBSCRIPTION
// ============================================================================

resource eventGridSubscription 'Microsoft.EventGrid/topics/eventSubscriptions@2024-06-01-preview' = {
  parent: eventGridTopic
  name: 'ai-router-subscription'
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/router_function'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'AIRequest.Submitted'
      ]
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 10
      eventTimeToLiveInMinutes: 1440
    }
    deadLetterDestination: {
      endpointType: 'StorageBlob'
      properties: {
        resourceId: storageAccount.id
        blobContainerName: 'deadletter'
      }
    }
  }
}

// ============================================================================
// RBAC ASSIGNMENTS
// ============================================================================

// Grant Function App access to AI Services
resource aiServicesRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aiServices
  name: guid(aiServices.id, functionApp.id, 'a001fd25-3aac-4a85-9d81-0c9da9ed2cee')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a001fd25-3aac-4a85-9d81-0c9da9ed2cee') // Cognitive Services OpenAI Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to Event Grid
resource eventGridRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: eventGridTopic
  name: guid(eventGridTopic.id, functionApp.id, '1e241071-0855-49ea-94dc-649edcd759de')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1e241071-0855-49ea-94dc-649edcd759de') // EventGrid Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The location where resources were deployed')
output location string = location

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The URL of the Function App')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the AI Foundry resource')
output aiFoundryResourceName string = aiServices.name

@description('The endpoint URL of the AI Foundry resource')
output aiFoundryEndpoint string = aiServices.properties.endpoint

@description('The name of the Model Router deployment')
output modelRouterDeploymentName string = modelRouterDeployment.name

@description('The name of the Event Grid topic')
output eventGridTopicName string = eventGridTopic.name

@description('The endpoint URL of the Event Grid topic')
output eventGridEndpoint string = eventGridTopic.properties.endpoint

@description('The name of the Application Insights resource')
output applicationInsightsName string = applicationInsights.name

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('Instructions for testing the deployment')
output testingInstructions object = {
  eventGridTestCommand: 'az eventgrid event send --topic-name ${eventGridTopic.name} --resource-group ${resourceGroup().name} --events \'[{"id": "test-001", "eventType": "AIRequest.Submitted", "subject": "test-request", "data": {"prompt": "What is artificial intelligence?", "request_id": "test-001"}, "dataVersion": "1.0"}]\''
  functionLogsCommand: 'az webapp log tail --name ${functionApp.name} --resource-group ${resourceGroup().name}'
  appInsightsQueryUrl: 'https://portal.azure.com/#@${tenant().tenantId}/resource${applicationInsights.id}/logs'
}