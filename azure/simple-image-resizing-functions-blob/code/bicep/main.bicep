// ===========================================
// Simple Image Resizing with Functions and Blob Storage
// ===========================================
// This template creates all resources needed for an automated image resizing solution
// using Azure Functions and Blob Storage with Event Grid triggers

@description('Environment prefix for resource naming')
param environment string = 'dev'

@description('Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Unique suffix for globally unique resource names')
param uniqueSuffix string = take(uniqueString(resourceGroup().id, deployment().name), 6)

@description('Function App plan SKU')
@allowed([
  'Y1'  // Consumption plan
  'EP1' // Premium plan
  'EP2' // Premium plan
  'EP3' // Premium plan
])
param functionAppPlanSku string = 'Y1'

@description('Storage account tier')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Image processing configuration')
param imageProcessingConfig object = {
  thumbnailWidth: 150
  thumbnailHeight: 150
  mediumWidth: 800
  mediumHeight: 600
  jpegQuality: 85
}

@description('Enable Application Insights monitoring')
param enableApplicationInsights bool = true

@description('Resource tags for cost management and organization')
param resourceTags object = {
  Environment: environment
  Application: 'ImageResizing'
  CostCenter: 'IT'
  Owner: 'DevOps'
}

// ===========================================
// Variables
// ===========================================
var resourcePrefix = '${environment}-imgresiz-${uniqueSuffix}'
var storageAccountName = 'st${replace(resourcePrefix, '-', '')}'
var functionAppName = 'func-${resourcePrefix}'
var functionAppPlanName = 'plan-${resourcePrefix}'
var applicationInsightsName = 'appi-${resourcePrefix}'
var eventGridSystemTopicName = 'evgt-${resourcePrefix}'

var blobContainers = [
  {
    name: 'original-images'
    publicAccess: 'Blob'
  }
  {
    name: 'thumbnails'
    publicAccess: 'Blob'
  }
  {
    name: 'medium-images'
    publicAccess: 'Blob'
  }
]

// ===========================================
// Storage Account
// ===========================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: true
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
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ===========================================
// Blob Service and Containers
// ===========================================
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'HEAD', 'POST', 'PUT', 'OPTIONS']
          allowedHeaders: ['*']
          exposedHeaders: ['*']
          maxAgeInSeconds: 3600
        }
      ]
    }
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

resource blobContainersResource 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for container in blobContainers: {
  parent: blobServices
  name: container.name
  properties: {
    publicAccess: container.publicAccess
    metadata: {
      purpose: 'image-resizing-${container.name}'
      created: utcNow()
    }
  }
}]

// ===========================================
// Application Insights
// ===========================================
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
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

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableApplicationInsights) {
  name: 'law-${resourcePrefix}'
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
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ===========================================
// Function App Service Plan
// ===========================================
resource functionAppServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: functionAppPlanName
  location: location
  tags: resourceTags
  sku: {
    name: functionAppPlanSku
    tier: functionAppPlanSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  kind: 'functionapp'
  properties: {
    reserved: true // Required for Linux
  }
}

// ===========================================
// Function App
// ===========================================
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: resourceTags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionAppServicePlan.id
    reserved: true
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'Node|20'
      acrUseManagedIdentityCreds: false
      alwaysOn: functionAppPlanSku != 'Y1' // Not available on consumption plan
      http20Enabled: true
      functionAppScaleLimit: functionAppPlanSku == 'Y1' ? 200 : 100
      minimumElasticInstanceCount: functionAppPlanSku != 'Y1' ? 1 : 0
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
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
          value: 'node'
        }
        {
          name: 'StorageConnection'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'THUMBNAIL_WIDTH'
          value: string(imageProcessingConfig.thumbnailWidth)
        }
        {
          name: 'THUMBNAIL_HEIGHT'
          value: string(imageProcessingConfig.thumbnailHeight)
        }
        {
          name: 'MEDIUM_WIDTH'
          value: string(imageProcessingConfig.mediumWidth)
        }
        {
          name: 'MEDIUM_HEIGHT'
          value: string(imageProcessingConfig.mediumHeight)
        }
        {
          name: 'JPEG_QUALITY'
          value: string(imageProcessingConfig.jpegQuality)
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_Mode'
          value: 'Recommended'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
    }
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    keyVaultReferenceIdentity: 'SystemAssigned'
    httpsOnly: true
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
    storageAccountRequired: false
  }
}

// ===========================================
// Event Grid System Topic for Storage Account
// ===========================================
resource eventGridSystemTopic 'Microsoft.EventGrid/systemTopics@2023-12-15-preview' = {
  name: eventGridSystemTopicName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    source: storageAccount.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

// ===========================================
// Event Grid Subscription for Blob Created Events
// ===========================================
resource eventGridSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2023-12-15-preview' = {
  parent: eventGridSystemTopic
  name: 'blob-created-subscription'
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/ImageResize'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      subjectBeginsWith: '/blobServices/default/containers/original-images/'
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      enableAdvancedFilteringOnArrays: true
    }
    labels: [
      'image-processing'
      'blob-trigger'
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
        blobContainerName: 'event-grid-dead-letters'
      }
    }
  }
}

// ===========================================
// Dead Letter Queue Container
// ===========================================
resource deadLetterContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'event-grid-dead-letters'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'event-grid-dead-letter-queue'
      created: utcNow()
    }
  }
}

// ===========================================
// Role Assignments for Function App Managed Identity
// ===========================================

// Storage Blob Data Contributor role for the Function App
resource functionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// EventGrid Data Sender role for the Event Grid System Topic
resource eventGridFunctionRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: functionApp
  name: guid(functionApp.id, eventGridSystemTopic.id, 'd5a91429-5739-47e2-a06b-3470a27159e7')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7') // EventGrid Data Sender
    principalId: eventGridSystemTopic.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ===========================================
// Outputs
// ===========================================
@description('The name of the created resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The primary endpoint of the storage account')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The connection string for the storage account')
@secure()
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppHostName string = functionApp.properties.defaultHostName

@description('The Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the Event Grid System Topic')
output eventGridSystemTopicName string = eventGridSystemTopic.name

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('The Application Insights connection string')
@secure()
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('Container URLs for direct access')
output containerUrls object = {
  originalImages: '${storageAccount.properties.primaryEndpoints.blob}original-images/'
  thumbnails: '${storageAccount.properties.primaryEndpoints.blob}thumbnails/'
  mediumImages: '${storageAccount.properties.primaryEndpoints.blob}medium-images/'
}

@description('Resource IDs for integration with other systems')
output resourceIds object = {
  storageAccount: storageAccount.id
  functionApp: functionApp.id
  functionAppServicePlan: functionAppServicePlan.id
  eventGridSystemTopic: eventGridSystemTopic.id
  applicationInsights: enableApplicationInsights ? applicationInsights.id : ''
  logAnalyticsWorkspace: enableApplicationInsights ? logAnalyticsWorkspace.id : ''
}

@description('Image processing configuration settings')
output imageProcessingSettings object = imageProcessingConfig

@description('Deployment summary')
output deploymentSummary object = {
  environment: environment
  location: location
  functionAppPlan: functionAppPlanSku
  storageAccountSku: storageAccountSku
  applicationInsightsEnabled: enableApplicationInsights
  deployedAt: utcNow()
  estimatedMonthlyCost: functionAppPlanSku == 'Y1' ? 'Pay-per-execution (typically $1-5/month)' : 'Fixed cost based on plan size'
}