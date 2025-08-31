@description('Main Bicep template for AI Assistant with Custom Functions using OpenAI and Azure Functions')

// Parameters
@description('The location/region where resources will be deployed')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('OpenAI model name to deploy')
@allowed(['gpt-4', 'gpt-4-32k', 'gpt-35-turbo'])
param openAIModelName string = 'gpt-4'

@description('OpenAI model version')
param openAIModelVersion string = '0613'

@description('OpenAI deployment capacity (TPM - Tokens per minute)')
@minValue(1)
@maxValue(120)
param openAIModelCapacity int = 10

@description('Function App runtime version')
@allowed(['3.9', '3.10', '3.11'])
param pythonVersion string = '3.11'

@description('Application Insights log retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 90

@description('Storage account replication type')
@allowed(['LRS', 'GRS', 'ZRS'])
param storageReplication string = 'LRS'

@description('Tags to apply to all resources')
param resourceTags object = {
  Environment: environment
  Application: 'AI-Assistant'
  Purpose: 'Recipe-Demo'
}

// Variables
var resourceNames = {
  cognitiveServices: 'openai-assistant-${uniqueSuffix}'
  functionApp: 'func-assistant-${uniqueSuffix}'
  appServicePlan: 'asp-assistant-${uniqueSuffix}'
  storageAccount: 'stassistant${uniqueSuffix}'
  applicationInsights: 'ai-assistant-${uniqueSuffix}'
  logAnalytics: 'law-assistant-${uniqueSuffix}'
  keyVault: 'kv-assistant-${uniqueSuffix}'
}

var storageAccountName = length(resourceNames.storageAccount) > 24 ? substring(resourceNames.storageAccount, 0, 24) : resourceNames.storageAccount
var keyVaultName = length(resourceNames.keyVault) > 24 ? substring(resourceNames.keyVault, 0, 24) : resourceNames.keyVault

// Deploy modules
module logging 'modules/logging.bicep' = {
  name: 'logging-deployment'
  params: {
    location: location
    logAnalyticsName: resourceNames.logAnalytics
    applicationInsightsName: resourceNames.applicationInsights
    retentionInDays: logRetentionDays
    tags: resourceTags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  params: {
    location: location
    storageAccountName: storageAccountName
    replicationType: storageReplication
    tags: resourceTags
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-deployment'
  params: {
    location: location
    keyVaultName: keyVaultName
    tags: resourceTags
  }
}

module cognitiveServices 'modules/cognitive-services.bicep' = {
  name: 'cognitive-services-deployment'
  params: {
    location: location
    cognitiveServicesName: resourceNames.cognitiveServices
    modelName: openAIModelName
    modelVersion: openAIModelVersion
    modelCapacity: openAIModelCapacity
    tags: resourceTags
  }
}

module functionApp 'modules/function-app.bicep' = {
  name: 'function-app-deployment'
  params: {
    location: location
    functionAppName: resourceNames.functionApp
    appServicePlanName: resourceNames.appServicePlan
    pythonVersion: pythonVersion
    storageAccountName: storage.outputs.storageAccountName
    storageConnectionString: storage.outputs.connectionString
    applicationInsightsInstrumentationKey: logging.outputs.applicationInsightsInstrumentationKey
    applicationInsightsConnectionString: logging.outputs.applicationInsightsConnectionString
    openAIEndpoint: cognitiveServices.outputs.endpoint
    openAIKeySecretUri: '@Microsoft.KeyVault(VaultName=${keyVault.outputs.keyVaultName};SecretName=${cognitiveServices.outputs.keySecretName})'
    keyVaultName: keyVault.outputs.keyVaultName
    tags: resourceTags
  }
  dependsOn: [
    keyVault
    cognitiveServices
  ]
}

// Store OpenAI key in Key Vault
resource openAIKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: '${keyVault.outputs.keyVaultName}/${cognitiveServices.outputs.keySecretName}'
  properties: {
    value: cognitiveServices.outputs.primaryKey
    attributes: {
      enabled: true
    }
  }
  dependsOn: [
    keyVault
    cognitiveServices
  ]
}

// Outputs
@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Azure OpenAI Service endpoint')
output openAIServiceEndpoint string = cognitiveServices.outputs.endpoint

@description('Azure OpenAI Service name')
output openAIServiceName string = cognitiveServices.outputs.cognitiveServicesName

@description('Azure OpenAI model deployment name')
output openAIModelDeploymentName string = cognitiveServices.outputs.modelDeploymentName

@description('Function App name')
output functionAppName string = functionApp.outputs.functionAppName

@description('Function App URL')
output functionAppUrl string = functionApp.outputs.functionAppUrl

@description('Storage Account name')
output storageAccountName string = storage.outputs.storageAccountName

@description('Storage Account connection string (for local development)')
@secure()
output storageConnectionString string = storage.outputs.connectionString

@description('Key Vault name')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('Application Insights instrumentation key')
@secure()
output applicationInsightsInstrumentationKey string = logging.outputs.applicationInsightsInstrumentationKey

@description('Application Insights connection string')
@secure()
output applicationInsightsConnectionString string = logging.outputs.applicationInsightsConnectionString

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logging.outputs.logAnalyticsWorkspaceName

@description('Function endpoints for testing')
output functionEndpoints object = {
  getCustomerInfo: '${functionApp.outputs.functionAppUrl}/api/GetCustomerInfo'
  analyzeMetrics: '${functionApp.outputs.functionAppUrl}/api/AnalyzeMetrics'
}

@description('Deployment summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  environment: environment
  uniqueSuffix: uniqueSuffix
  deployedServices: [
    'Azure OpenAI Service'
    'Azure Functions'
    'Azure Storage'
    'Azure Key Vault'
    'Application Insights'
    'Log Analytics Workspace'
  ]
  estimatedMonthlyCost: {
    openAI: 'Variable based on usage'
    functions: '$5-20 (Consumption plan)'
    storage: '$2-10 (Standard LRS)'
    keyVault: '$1-5'
    monitoring: '$5-15'
    total: '$13-50 USD/month'
  }
}