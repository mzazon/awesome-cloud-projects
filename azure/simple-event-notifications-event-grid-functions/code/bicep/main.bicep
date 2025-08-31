@description('The name of the resource group where resources will be deployed')
param resourceGroupName string = 'rg-recipe-${uniqueString(subscription().subscriptionId)}'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('The prefix to use for naming resources')
param resourcePrefix string = 'recipe'

@description('The unique suffix to append to resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('The name of the Event Grid custom topic')
param eventGridTopicName string = '${resourcePrefix}-topic-notifications-${uniqueSuffix}'

@description('The name of the Azure Function App')
param functionAppName string = '${resourcePrefix}-func-processor-${uniqueSuffix}'

@description('The name of the storage account for the Function App')
param storageAccountName string = '${resourcePrefix}${uniqueSuffix}func'

@description('The name of the Event Grid subscription')
param eventSubscriptionName string = 'sub-event-processor'

@description('The Event Grid input schema type')
@allowed([
  'EventGridSchema'
  'CustomEventSchema'
  'CloudEventSchemaV1_0'
])
param inputSchema string = 'CloudEventSchemaV1_0'

@description('The Azure Functions runtime version')
@allowed([
  '~4'
  '~3'
])
param functionsVersion string = '~4'

@description('The Node.js runtime version for the Function App')
@allowed([
  '18'
  '20'
])
param nodeVersion string = '20'

@description('The pricing tier for the App Service Plan (Consumption plan)')
@allowed([
  'Y1'
  'EP1'
  'EP2'
  'EP3'
])
param functionAppSku string = 'Y1'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'recipe'
  environment: 'demo'
  solution: 'event-notifications'
  provider: 'azure'
}

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
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
    }
  }
}

// Application Insights for monitoring
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

// App Service Plan for Function App (Consumption plan)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${functionAppName}-plan'
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    name: functionAppSku
    tier: functionAppSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  properties: {
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
          value: functionsVersion
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~${nodeVersion}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
  }
}

// Event Grid Custom Topic
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: tags
  properties: {
    inputSchema: inputSchema
    publicNetworkAccess: 'Enabled'
  }
}

// Event Grid Subscription
resource eventGridSubscription 'Microsoft.EventGrid/eventSubscriptions@2023-12-15-preview' = {
  name: eventSubscriptionName
  scope: eventGridTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${functionApp.properties.defaultHostName}/runtime/webhooks/eventgrid?functionName=eventProcessor'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: []
      subjectBeginsWith: ''
      subjectEndsWith: ''
      isSubjectCaseSensitive: false
    }
    eventDeliverySchema: inputSchema
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
  dependsOn: [
    functionApp
  ]
}

// Dead letter container in storage account
resource deadLetterContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/deadletter'
  properties: {
    publicAccess: 'None'
  }
}

// Role assignment for Event Grid to access storage account for dead lettering
resource eventGridStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, eventGridTopic.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: eventGridTopic.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs for validation and integration
@description('The name of the deployed resource group')
output resourceGroupName string = resourceGroup().name

@description('The location where resources were deployed')
output location string = location

@description('The name of the Event Grid topic')
output eventGridTopicName string = eventGridTopic.name

@description('The endpoint URL of the Event Grid topic')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('The primary access key for the Event Grid topic')
output eventGridTopicKey string = eventGridTopic.listKeys().key1

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The URL of the Function App')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The name of the Event Grid subscription')
output eventSubscriptionName string = eventGridSubscription.name

@description('The Application Insights instrumentation key')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('The Application Insights connection string')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('The resource IDs for monitoring and management')
output resourceIds object = {
  eventGridTopic: eventGridTopic.id
  functionApp: functionApp.id
  storageAccount: storageAccount.id
  appInsights: appInsights.id
  eventSubscription: eventGridSubscription.id
}

@description('Connection information for testing')
output testingInfo object = {
  topicEndpoint: eventGridTopic.properties.endpoint
  topicKey: eventGridTopic.listKeys().key1
  functionUrl: 'https://${functionApp.properties.defaultHostName}'
  portalUrl: 'https://portal.azure.com/#@/resource${functionApp.id}'
  appInsightsUrl: 'https://portal.azure.com/#@/resource${appInsights.id}'
}