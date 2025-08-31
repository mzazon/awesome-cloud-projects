@description('Meeting Intelligence with Speech Services and OpenAI - Main Bicep Template')
@description('This template deploys a serverless meeting intelligence solution using Azure Speech Services for transcription with speaker diarization, Azure OpenAI for insight extraction, and Azure Service Bus with Functions for reliable processing workflows.')

// Parameters
@description('Resource prefix for naming consistency')
@minLength(3)
@maxLength(8)
param resourcePrefix string = 'meeting'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Speech Services pricing tier')
@allowed(['S0'])
param speechServicesSku string = 'S0'

@description('OpenAI Service pricing tier')
@allowed(['S0'])
param openAiSku string = 'S0'

@description('OpenAI model deployment configuration')
param openAiModelConfig object = {
  modelName: 'gpt-4o'
  modelVersion: '2024-11-20'
  deploymentName: 'gpt-4-meeting-analysis'
  capacity: 1
}

@description('Service Bus pricing tier')
@allowed(['Standard', 'Premium'])
param serviceBusSku string = 'Standard'

@description('Storage account replication type')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageReplication string = 'Standard_LRS'

@description('Function App pricing tier')
@allowed(['Y1', 'EP1', 'EP2'])
param functionAppSku string = 'Y1'

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Resource tags for governance')
param resourceTags object = {
  Environment: environment
  Solution: 'Meeting Intelligence'
  Purpose: 'AI-Powered Meeting Analysis'
  CostCenter: 'IT'
}

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var namingPrefix = '${resourcePrefix}-${environment}-${uniqueSuffix}'

var storageAccountName = replace('st${namingPrefix}', '-', '')
var speechServicesName = 'speech-${namingPrefix}'
var openAiServiceName = 'openai-${namingPrefix}'
var serviceBusNamespaceName = 'sb-${namingPrefix}'
var functionAppName = 'func-${namingPrefix}'
var appServicePlanName = 'asp-${namingPrefix}'
var applicationInsightsName = 'ai-${namingPrefix}'
var logAnalyticsWorkspaceName = 'law-${namingPrefix}'

// Storage Account for meeting recordings and function app
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageReplication
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
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

// Blob container for meeting recordings
resource meetingRecordingsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/meeting-recordings'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Meeting audio file storage'
      retention: '90 days'
    }
  }
}

// Speech Services for transcription with speaker diarization
resource speechServices 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: speechServicesName
  location: location
  tags: resourceTags
  sku: {
    name: speechServicesSku
  }
  kind: 'SpeechServices'
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
    customSubDomainName: speechServicesName
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

// Azure OpenAI Service for meeting intelligence extraction
resource openAiService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAiServiceName
  location: location
  tags: resourceTags
  sku: {
    name: openAiSku
  }
  kind: 'OpenAI'
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
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

// GPT-4 model deployment for meeting analysis
resource gpt4Deployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAiService
  name: openAiModelConfig.deploymentName
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiModelConfig.modelName
      version: openAiModelConfig.modelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'Standard'
    capacity: openAiModelConfig.capacity
  }
}

// Service Bus namespace for reliable messaging
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  tags: resourceTags
  sku: {
    name: serviceBusSku
    tier: serviceBusSku
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: serviceBusSku == 'Premium'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Queue for transcript processing
resource transcriptQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'transcript-processing'
  properties: {
    deadLetteringOnMessageExpiration: true
    defaultMessageTimeToLive: 'P14D'
    maxDeliveryCount: 5
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    requiresSession: false
    enableBatchedOperations: true
  }
}

// Topic for distributing meeting insights
resource meetingInsightsTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'meeting-insights'
  properties: {
    defaultMessageTimeToLive: 'P14D'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    enableBatchedOperations: true
    supportOrdering: false
  }
}

// Subscription for notification processing
resource notificationSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: meetingInsightsTopic
  name: 'notification-subscription'
  properties: {
    deadLetteringOnMessageExpiration: true
    defaultMessageTimeToLive: 'P14D'
    maxDeliveryCount: 5
    requiresSession: false
    enableBatchedOperations: true
  }
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableApplicationInsights) {
  name: logAnalyticsWorkspaceName
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

// Application Insights for Function App monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  tags: resourceTags
  sku: {
    name: functionAppSku
    tier: functionAppSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  kind: functionAppSku == 'Y1' ? 'functionapp' : 'elastic'
  properties: {
    reserved: true // Linux hosting
  }
}

// Function App for serverless processing
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  tags: resourceTags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
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
      linuxFxVersion: 'Python|3.11'
      alwaysOn: functionAppSku != 'Y1'
      functionAppScaleLimit: functionAppSku == 'Y1' ? 200 : 20
      minimumElasticInstanceCount: functionAppSku != 'Y1' ? 1 : 0
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      remoteDebuggingEnabled: false
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
          name: 'SPEECH_KEY'
          value: speechServices.listKeys().key1
        }
        {
          name: 'SPEECH_ENDPOINT'
          value: speechServices.properties.endpoint
        }
        {
          name: 'OPENAI_KEY'
          value: openAiService.listKeys().key1
        }
        {
          name: 'OPENAI_ENDPOINT'
          value: openAiService.properties.endpoint
        }
        {
          name: 'DEPLOYMENT_NAME'
          value: openAiModelConfig.deploymentName
        }
        {
          name: 'SERVICE_BUS_CONNECTION'
          value: listKeys('${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespace.apiVersion).primaryConnectionString
        }
        {
          name: 'TRANSCRIPT_QUEUE'
          value: transcriptQueue.name
        }
        {
          name: 'RESULTS_TOPIC'
          value: meetingInsightsTopic.name
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'STORAGE_CONNECTION'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
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
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: enableApplicationInsights ? '~3' : ''
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_Mode'
          value: enableApplicationInsights ? 'Recommended' : ''
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Role assignments for Function App access to services

// Storage Blob Data Contributor role for Function App
resource functionAppStorageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Cognitive Services User role for Function App to access Speech Services
resource functionAppSpeechServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(speechServices.id, functionApp.id, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: speechServices
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Cognitive Services User role for Function App to access OpenAI Service
resource functionAppOpenAiUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiService.id, functionApp.id, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: openAiService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Service Bus Data Owner role for Function App
resource functionAppServiceBusDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, functionApp.id, '090c5cfd-751d-490a-894a-3ce6f1109419')
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '090c5cfd-751d-490a-894a-3ce6f1109419')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('Meeting Recordings Container URL')
output meetingRecordingsUrl string = '${storageAccount.properties.primaryEndpoints.blob}${meetingRecordingsContainer.name}'

@description('Speech Services Name')
output speechServicesName string = speechServices.name

@description('Speech Services Endpoint')
output speechServicesEndpoint string = speechServices.properties.endpoint

@description('OpenAI Service Name')
output openAiServiceName string = openAiService.name

@description('OpenAI Service Endpoint')
output openAiServiceEndpoint string = openAiService.properties.endpoint

@description('GPT-4 Model Deployment Name')
output gpt4DeploymentName string = gpt4Deployment.name

@description('Service Bus Namespace Name')
output serviceBusNamespaceName string = serviceBusNamespace.name

@description('Service Bus Namespace Hostname')
output serviceBusNamespaceHostname string = '${serviceBusNamespace.name}.servicebus.windows.net'

@description('Transcript Processing Queue Name')
output transcriptQueueName string = transcriptQueue.name

@description('Meeting Insights Topic Name')
output meetingInsightsTopicName string = meetingInsightsTopic.name

@description('Function App Name')
output functionAppName string = functionApp.name

@description('Function App Default Hostname')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Application Insights Name')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = enableApplicationInsights ? logAnalyticsWorkspace.name : ''

@description('Deployment Summary')
output deploymentSummary object = {
  solution: 'Meeting Intelligence with Speech Services and OpenAI'
  environment: environment
  location: location
  resourcePrefix: resourcePrefix
  uniqueSuffix: uniqueSuffix
  componentsDeployed: {
    storageAccount: storageAccount.name
    speechServices: speechServices.name
    openAiService: openAiService.name
    gpt4Deployment: gpt4Deployment.name
    serviceBusNamespace: serviceBusNamespace.name
    functionApp: functionApp.name
    applicationInsights: enableApplicationInsights ? applicationInsights.name : 'Not deployed'
  }
  nextSteps: [
    'Upload meeting recordings to the meeting-recordings container'
    'Monitor Function App logs for processing status'
    'Review meeting insights in Service Bus topic messages'
    'Configure additional notification endpoints as needed'
  ]
}