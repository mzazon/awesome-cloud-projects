@description('The name prefix for all resources')
param namePrefix string = 'prod-desc'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('The SKU for the Computer Vision service')
@allowed(['F0', 'S1'])
param visionSku string = 'S1'

@description('The SKU for the OpenAI service')
@allowed(['S0'])
param openAiSku string = 'S0'

@description('The SKU for the Storage Account')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageSku string = 'Standard_LRS'

@description('The SKU for the Function App hosting plan')
@allowed(['Y1'])
param functionAppSku string = 'Y1'

@description('The Python version for the Function App')
@allowed(['3.9', '3.10', '3.11'])
param pythonVersion string = '3.11'

@description('The OpenAI model name to deploy')
param openAiModelName string = 'gpt-4o'

@description('The OpenAI model version to deploy')
param openAiModelVersion string = '2024-11-20'

@description('The capacity for the OpenAI model deployment')
@minValue(1)
@maxValue(100)
param openAiModelCapacity int = 10

@description('Container name for product images')
param imageContainerName string = 'product-images'

@description('Container name for generated descriptions')
param outputContainerName string = 'descriptions'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'recipe'
  environment: 'demo'
  category: 'ai-ml'
  solution: 'product-description-generation'
}

// Generate unique suffix for resource names
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var storageAccountName = 'st${namePrefix}${uniqueSuffix}'
var functionAppName = 'func-${namePrefix}-${uniqueSuffix}'
var appServicePlanName = 'asp-${namePrefix}-${uniqueSuffix}'
var computerVisionName = 'cv-${namePrefix}-${uniqueSuffix}'
var openAiName = 'oai-${namePrefix}-${uniqueSuffix}'
var applicationInsightsName = 'ai-${namePrefix}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-${namePrefix}-${uniqueSuffix}'

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
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

// Application Insights for Function App monitoring
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

// Storage Account for Function App and blob storage
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
    }
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

// Blob Services for the Storage Account
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
  }
}

// Container for product images
resource imageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: imageContainerName
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'product-images'
      description: 'Container for uploaded product images'
    }
  }
}

// Container for generated descriptions
resource outputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: outputContainerName
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'generated-descriptions'
      description: 'Container for AI-generated product descriptions'
    }
  }
}

// Computer Vision service
resource computerVision 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: computerVisionName
  location: location
  tags: tags
  sku: {
    name: visionSku
  }
  kind: 'ComputerVision'
  properties: {
    customSubDomainName: computerVisionName
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: false
  }
}

// OpenAI service
resource openAi 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAiName
  location: location
  tags: tags
  sku: {
    name: openAiSku
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openAiName
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: false
  }
}

// OpenAI model deployment
resource openAiModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAi
  name: openAiModelName
  sku: {
    name: 'Standard'
    capacity: openAiModelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiModelName
      version: openAiModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
}

// App Service Plan for Function App (Consumption plan)
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: functionAppSku
    tier: 'Dynamic'
  }
  properties: {
    reserved: true // Linux
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'Python|${pythonVersion}'
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
          value: 'python'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'VISION_ENDPOINT'
          value: computerVision.properties.endpoint
        }
        {
          name: 'VISION_KEY'
          value: computerVision.listKeys().key1
        }
        {
          name: 'OPENAI_ENDPOINT'
          value: openAi.properties.endpoint
        }
        {
          name: 'OPENAI_KEY'
          value: openAi.listKeys().key1
        }
        {
          name: 'OUTPUT_CONTAINER'
          value: outputContainerName
        }
        {
          name: 'OPENAI_MODEL_NAME'
          value: openAiModelName
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: 'true'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

// Event Grid System Topic for Storage Account
resource eventGridSystemTopic 'Microsoft.EventGrid/systemTopics@2023-12-15-preview' = {
  name: 'eg-${namePrefix}-${uniqueSuffix}'
  location: location
  tags: tags
  properties: {
    source: storageAccount.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

// Event Grid Subscription for blob created events
resource eventGridSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2023-12-15-preview' = {
  parent: eventGridSystemTopic
  name: 'product-image-processor'
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/ProductDescriptionGenerator'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/${imageContainerName}/blobs/'
      advancedFilters: [
        {
          operatorType: 'StringContains'
          key: 'data.contentType'
          values: [
            'image/'
          ]
        }
      ]
    }
    labels: [
      'product-description-generation'
    ]
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
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

// Dead letter container for failed events
resource deadLetterContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'deadletter'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'dead-letter'
      description: 'Container for failed Event Grid events'
    }
  }
}

// Outputs
@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The Computer Vision endpoint')
output computerVisionEndpoint string = computerVision.properties.endpoint

@description('The OpenAI endpoint')
output openAiEndpoint string = openAi.properties.endpoint

@description('The name of the image container')
output imageContainerName string = imageContainer.name

@description('The name of the output container')
output outputContainerName string = outputContainer.name

@description('The Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Storage account connection string')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('Computer Vision service key')
output computerVisionKey string = computerVision.listKeys().key1

@description('OpenAI service key')
output openAiKey string = openAi.listKeys().key1

@description('Event Grid System Topic name')
output eventGridSystemTopicName string = eventGridSystemTopic.name

@description('Deployment summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  storageAccount: storageAccount.name
  functionApp: functionApp.name
  computerVision: computerVision.name
  openAi: openAi.name
  imageContainer: imageContainer.name
  outputContainer: outputContainer.name
  eventGridTopic: eventGridSystemTopic.name
  applicationInsights: applicationInsights.name
  deployed: utcNow()
}