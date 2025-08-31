@description('Main Bicep template for Content Personalization Engine with AI Foundry and Cosmos DB')

// Parameters
@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure uniqueness')
@minLength(3)
@maxLength(6)
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('OpenAI model deployment configurations')
param openAiModels object = {
  gpt4: {
    name: 'gpt-4-content'
    modelName: 'gpt-4'
    modelVersion: '0613'
    skuCapacity: 10
  }
  embedding: {
    name: 'text-embedding'
    modelName: 'text-embedding-ada-002'
    modelVersion: '2'
    skuCapacity: 10
  }
}

@description('Cosmos DB configuration')
param cosmosDbConfig object = {
  databaseName: 'PersonalizationDB'
  containers: [
    {
      name: 'UserProfiles'
      partitionKeyPath: '/userId'
      throughput: 400
    }
    {
      name: 'ContentItems'
      partitionKeyPath: '/category'
      throughput: 400
    }
  ]
}

@description('Function App runtime configuration')
param functionAppConfig object = {
  runtime: 'python'
  runtimeVersion: '3.12'
  functionsVersion: '4'
  osType: 'Linux'
}

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'content-personalization'
  environment: environment
  'created-by': 'bicep-template'
}

// Variables
var resourcePrefix = 'personalization-${uniqueSuffix}'
var cosmosAccountName = 'cosmos-${resourcePrefix}'
var openAiServiceName = 'openai-${resourcePrefix}'
var functionAppName = 'func-${resourcePrefix}'
var storageAccountName = 'st${replace(resourcePrefix, '-', '')}'
var aiFoundryWorkspaceName = 'ai-${resourcePrefix}'
var appServicePlanName = 'plan-${resourcePrefix}'
var applicationInsightsName = 'appi-${resourcePrefix}'
var logAnalyticsWorkspaceName = 'log-${resourcePrefix}'

// Modules

// Storage Account for Azure Functions
module storageAccount 'modules/storage.bicep' = {
  name: 'storageAccountDeployment'
  params: {
    storageAccountName: storageAccountName
    location: location
    tags: tags
  }
}

// Log Analytics Workspace for Application Insights
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'logAnalyticsDeployment'
  params: {
    workspaceName: logAnalyticsWorkspaceName
    location: location
    tags: tags
  }
}

// Application Insights for monitoring
module applicationInsights 'modules/application-insights.bicep' = {
  name: 'applicationInsightsDeployment'
  params: {
    applicationInsightsName: applicationInsightsName
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: tags
  }
  dependsOn: [
    logAnalytics
  ]
}

// Cosmos DB Account with vector search capabilities
module cosmosDb 'modules/cosmos-db.bicep' = {
  name: 'cosmosDbDeployment'
  params: {
    accountName: cosmosAccountName
    location: location
    databaseName: cosmosDbConfig.databaseName
    containers: cosmosDbConfig.containers
    tags: tags
  }
}

// Azure OpenAI Service
module openAiService 'modules/openai.bicep' = {
  name: 'openAiServiceDeployment'
  params: {
    openAiServiceName: openAiServiceName
    location: location
    models: openAiModels
    tags: tags
  }
}

// AI Foundry Workspace (Machine Learning Workspace)
module aiFoundryWorkspace 'modules/ai-foundry.bicep' = {
  name: 'aiFoundryWorkspaceDeployment'
  params: {
    workspaceName: aiFoundryWorkspaceName
    location: location
    storageAccountId: storageAccount.outputs.storageAccountId
    applicationInsightsId: applicationInsights.outputs.applicationInsightsId
    tags: tags
  }
  dependsOn: [
    storageAccount
    applicationInsights
  ]
}

// App Service Plan for Azure Functions
module appServicePlan 'modules/app-service-plan.bicep' = {
  name: 'appServicePlanDeployment'
  params: {
    planName: appServicePlanName
    location: location
    tags: tags
  }
}

// Azure Functions App
module functionApp 'modules/function-app.bicep' = {
  name: 'functionAppDeployment'
  params: {
    functionAppName: functionAppName
    location: location
    appServicePlanId: appServicePlan.outputs.appServicePlanId
    storageAccountConnectionString: storageAccount.outputs.connectionString
    applicationInsightsConnectionString: applicationInsights.outputs.connectionString
    cosmosDbConnectionString: cosmosDb.outputs.connectionString
    openAiEndpoint: openAiService.outputs.endpoint
    openAiApiKey: openAiService.outputs.apiKey
    aiFoundryWorkspaceName: aiFoundryWorkspaceName
    runtimeConfig: functionAppConfig
    tags: tags
  }
  dependsOn: [
    appServicePlan
    storageAccount
    applicationInsights
    cosmosDb
    openAiService
    aiFoundryWorkspace
  ]
}

// Outputs
@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Cosmos DB Account Name')
output cosmosDbAccountName string = cosmosDb.outputs.accountName

@description('Cosmos DB Connection String')
@secure()
output cosmosDbConnectionString string = cosmosDb.outputs.connectionString

@description('Azure OpenAI Service Name')
output openAiServiceName string = openAiService.outputs.serviceName

@description('Azure OpenAI Endpoint')
output openAiEndpoint string = openAiService.outputs.endpoint

@description('Azure OpenAI API Key')
@secure()
output openAiApiKey string = openAiService.outputs.apiKey

@description('Function App Name')
output functionAppName string = functionApp.outputs.functionAppName

@description('Function App URL')
output functionAppUrl string = functionApp.outputs.functionAppUrl

@description('AI Foundry Workspace Name')
output aiFoundryWorkspaceName string = aiFoundryWorkspace.outputs.workspaceName

@description('Storage Account Name')
output storageAccountName string = storageAccount.outputs.storageAccountName

@description('Application Insights Name')
output applicationInsightsName string = applicationInsights.outputs.applicationInsightsName

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName

@description('Deployment Summary')
output deploymentSummary object = {
  resourcePrefix: resourcePrefix
  location: location
  environment: environment
  cosmosDbDatabase: cosmosDbConfig.databaseName
  openAiModels: [
    openAiModels.gpt4.name
    openAiModels.embedding.name
  ]
  functionRuntime: '${functionAppConfig.runtime} ${functionAppConfig.runtimeVersion}'
}