@description('Prefix for all resource names to ensure uniqueness')
param resourcePrefix string = 'poll'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Service Bus SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param serviceBusSku string = 'Basic'

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Function App runtime version')
@allowed([
  '~4'
  '~3'
])
param functionsVersion string = '~4'

@description('Node.js runtime version')
@allowed([
  '18'
  '16'
  '14'
])
param nodeVersion string = '18'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: 'TeamPollSystem'
  Purpose: 'Recipe'
}

// Variables for resource naming
var suffix = uniqueString(resourceGroup().id)
var serviceBusNamespaceName = '${resourcePrefix}-sb-${environment}-${suffix}'
var storageAccountName = '${resourcePrefix}sa${environment}${suffix}'
var functionAppName = '${resourcePrefix}-func-${environment}-${suffix}'
var appServicePlanName = '${resourcePrefix}-asp-${environment}-${suffix}'
var applicationInsightsName = '${resourcePrefix}-ai-${environment}-${suffix}'

// Service Bus Namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  tags: tags
  sku: {
    name: serviceBusSku
    tier: serviceBusSku
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// Service Bus Queue for votes
resource votesQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'votes'
  properties: {
    maxSizeInMegabytes: 1024
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
    enablePartitioning: false
    enableExpress: false
    requiresDuplicateDetection: false
  }
}

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Blob container for poll results
resource pollResultsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/poll-results'
  properties: {
    publicAccess: 'None'
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 90
    DisableIpMasking: false
    DisableLocalAuth: false
  }
}

// App Service Plan for Function App (Consumption plan)
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
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
    reserved: false
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      functionAppScaleLimit: 10
      minimumElasticInstanceCount: 0
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
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'ServiceBusConnection'
          value: listKeys('${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespace.apiVersion).primaryConnectionString
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'WEBSITE_TIME_ZONE'
          value: 'UTC'
        }
      ]
      cors: {
        allowedOrigins: [
          '*'
        ]
        supportCredentials: false
      }
      use32BitWorkerProcess: false
      netFrameworkVersion: 'v6.0'
    }
  }
  dependsOn: [
    pollResultsContainer
  ]
}

// Role assignment for Function App to access Service Bus
resource serviceBusDataOwnerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, functionApp.id, 'ServiceBusDataOwner')
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '090c5cfd-751d-490a-894a-3ce6f1109419')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Function App to access Storage Account
resource storageDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Service Bus namespace name')
output serviceBusNamespaceName string = serviceBusNamespace.name

@description('Service Bus connection string (for reference)')
output serviceBusConnectionString string = listKeys('${serviceBusNamespace.id}/AuthorizationRules/RootManageSharedAccessKey', serviceBusNamespace.apiVersion).primaryConnectionString

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Vote submission endpoint')
output voteSubmissionEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/SubmitVote'

@description('Results endpoint pattern')
output resultsEndpointPattern string = 'https://${functionApp.properties.defaultHostName}/api/results/{pollId}'

@description('Example usage commands')
output exampleUsage object = {
  submitVote: {
    method: 'POST'
    url: 'https://${functionApp.properties.defaultHostName}/api/SubmitVote'
    headers: {
      'Content-Type': 'application/json'
    }
    body: {
      pollId: 'team-lunch'
      option: 'Pizza'
      voterId: 'user@company.com'
    }
  }
  getResults: {
    method: 'GET'
    url: 'https://${functionApp.properties.defaultHostName}/api/results/team-lunch'
  }
}