// Real-time AI Chat with WebRTC and Model Router
// Creates infrastructure for a real-time voice chat application using Azure OpenAI's WebRTC-enabled Realtime API
// with intelligent model routing between GPT-4o-mini and GPT-4o models based on conversation complexity

// Parameters for customization
@description('Name prefix for all resources')
param namePrefix string = 'realtimechat'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment tag value')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Custom domain name for Azure OpenAI service')
param openAICustomDomain string = '${namePrefix}${uniqueString(resourceGroup().id)}'

@description('SKU for Azure OpenAI service')
@allowed(['S0'])
param openAISku string = 'S0'

@description('SKU for SignalR Service')
@allowed(['Free_F1', 'Standard_S1'])
param signalRSku string = 'Standard_S1'

@description('Capacity for each OpenAI model deployment')
@minValue(1)
@maxValue(120)
param modelCapacity int = 10

@description('Enable Application Insights for monitoring')
param enableAppInsights bool = true

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'realtime-ai-chat'
  environment: environment
  recipe: 'a7f3b9c5'
}

// Variables for resource naming
var storageAccountName = '${namePrefix}st${uniqueString(resourceGroup().id)}'
var openAIServiceName = openAICustomDomain
var signalRServiceName = '${namePrefix}-signalr-${uniqueString(resourceGroup().id)}'
var functionAppName = '${namePrefix}-func-${uniqueString(resourceGroup().id)}'
var hostingPlanName = '${namePrefix}-plan-${uniqueString(resourceGroup().id)}'
var appInsightsName = '${namePrefix}-insights-${uniqueString(resourceGroup().id)}'

// Storage Account for Azure Functions
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Azure OpenAI Service with custom domain for WebRTC Realtime API
resource openAIService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAIServiceName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: openAISku
  }
  properties: {
    customSubDomainName: openAICustomDomain
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// GPT-4o-mini-realtime model deployment for cost-effective interactions
resource gpt4oMiniRealtimeDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAIService
  name: 'gpt-4o-mini-realtime'
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-mini-realtime-preview'
      version: '2024-12-17'
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
}

// GPT-4o-realtime model deployment for complex interactions
resource gpt4oRealtimeDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAIService
  name: 'gpt-4o-realtime'
  dependsOn: [
    gpt4oMiniRealtimeDeployment // Ensure sequential deployment to avoid conflicts
  ]
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-realtime-preview'
      version: '2024-12-17'
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
}

// Azure SignalR Service for real-time communication management
resource signalRService 'Microsoft.SignalRService/signalR@2023-02-01' = {
  name: signalRServiceName
  location: location
  tags: tags
  sku: {
    name: signalRSku
    capacity: 1
  }
  properties: {
    features: [
      {
        flag: 'ServiceMode'
        value: 'Serverless'
      }
      {
        flag: 'EnableConnectivityLogs'
        value: 'true'
      }
      {
        flag: 'EnableMessagingLogs'
        value: 'true'
      }
    ]
    cors: {
      allowedOrigins: ['*']
    }
    upstream: {
      templates: []
    }
  }
}

// Application Insights for monitoring and analytics
resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (enableAppInsights) {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Consumption plan for Azure Functions
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: false
  }
}

// Azure Function App for intelligent model routing
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
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
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'AzureSignalRConnectionString'
          value: signalRService.listKeys().primaryConnectionString
        }
        {
          name: 'AZURE_OPENAI_ENDPOINT'
          value: openAIService.properties.endpoint
        }
        {
          name: 'AZURE_OPENAI_KEY'
          value: openAIService.listKeys().key1
        }
        {
          name: 'OPENAI_API_VERSION'
          value: '2025-04-01-preview'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableAppInsights ? appInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableAppInsights ? appInsights.properties.ConnectionString : ''
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
          name: 'XDT_MicrosoftApplicationInsights_PreemptSdk'
          value: 'Disabled'
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

// System-assigned managed identity for the Function App
resource functionAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${functionAppName}-identity'
  location: location
  tags: tags
}

// Role assignment for Function App to access OpenAI Service
resource openAIRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'Cognitive Services OpenAI User')
  scope: openAIService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Function App to access SignalR Service
resource signalRRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'SignalR App Server')
  scope: signalRService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '420fcaa2-552c-430f-98ca-3264be4806c7')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs for verification and integration
@description('Azure OpenAI service endpoint URL')
output openAIEndpoint string = openAIService.properties.endpoint

@description('Azure OpenAI service name')
output openAIServiceName string = openAIService.name

@description('SignalR Service connection string (for client applications)')
output signalRConnectionString string = signalRService.listKeys().primaryConnectionString

@description('SignalR Service name')
output signalRServiceName string = signalRService.name

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App URL for API endpoints')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Model Router API endpoint')
output modelRouterEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/ModelRouter'

@description('SignalR Info API endpoint')
output signalRInfoEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/SignalRInfo'

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Application Insights instrumentation key (if enabled)')
output appInsightsKey string = enableAppInsights ? appInsights.properties.InstrumentationKey : ''

@description('Resource group location')
output location string = location

@description('Deployed model endpoints for validation')
output deployedModels object = {
  'gpt-4o-mini-realtime': {
    name: gpt4oMiniRealtimeDeployment.name
    model: gpt4oMiniRealtimeDeployment.properties.model
    capacity: gpt4oMiniRealtimeDeployment.sku.capacity
  }
  'gpt-4o-realtime': {
    name: gpt4oRealtimeDeployment.name
    model: gpt4oRealtimeDeployment.properties.model
    capacity: gpt4oRealtimeDeployment.sku.capacity
  }
}

@description('WebRTC endpoint URL based on deployment region')
output webRTCEndpoint string = location == 'eastus2' ? 'https://eastus2.realtimeapi-preview.ai.azure.com/v1/realtimertc' : 'https://swedencentral.realtimeapi-preview.ai.azure.com/v1/realtimertc'