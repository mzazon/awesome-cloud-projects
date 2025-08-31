@description('Main Bicep template for AI Code Review Assistant with Reasoning and Functions')

// Parameters
@description('The location where resources will be deployed')
param location string = resourceGroup().location

@description('A unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = take(uniqueString(resourceGroup().id), 6)

@description('The pricing tier for the Azure OpenAI service')
@allowed(['S0'])
param openAiSkuName string = 'S0'

@description('The pricing tier for the Function App')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppSkuName string = 'Y1'

@description('The version of the o1-mini model to deploy')
param modelVersion string = '2024-09-12'

@description('The capacity for the o1-mini model deployment')
@minValue(1)
@maxValue(100)
param modelCapacity int = 10

@description('Environment tags for resource management')
param tags object = {
  purpose: 'recipe'
  environment: 'demo'
  solution: 'ai-code-review'
}

@description('The Python version for the Function App')
@allowed(['3.11'])
param pythonVersion string = '3.11'

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Storage account replication type')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountReplication string = 'Standard_LRS'

// Variables
var resourceNamePrefix = 'ai-code-review'
var storageAccountName = 'st${resourceNamePrefix}${uniqueSuffix}'
var functionAppName = 'func-${resourceNamePrefix}-${uniqueSuffix}'
var appServicePlanName = 'asp-${resourceNamePrefix}-${uniqueSuffix}'
var openAiAccountName = 'oai-${resourceNamePrefix}-${uniqueSuffix}'
var applicationInsightsName = 'appi-${resourceNamePrefix}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-${resourceNamePrefix}-${uniqueSuffix}'

// Storage Account for code files and reports
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountReplication
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
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
    }
  }
}

// Blob containers for code files and review reports
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource codeFilesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'code-files'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Store uploaded code files for review'
    }
  }
}

resource reviewReportsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'review-reports'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Store generated AI code review reports'
    }
  }
}

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableApplicationInsights) {
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

// Application Insights for monitoring and diagnostics
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
  }
}

// Azure Cognitive Services account for OpenAI
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAiAccountName
  location: location
  tags: tags
  sku: {
    name: openAiSkuName
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openAiAccountName
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Deploy o1-mini model for code analysis
resource openAiModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAiAccount
  name: 'o1-mini-code-review'
  properties: {
    model: {
      format: 'OpenAI'
      name: 'o1-mini'
      version: modelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'Standard'
    capacity: modelCapacity
  }
}

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: functionAppSkuName
    tier: functionAppSkuName == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  kind: 'functionapp'
  properties: {
    reserved: true // Linux
  }
}

// Function App for code review processing
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    httpsOnly: true
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
          name: 'AZURE_OPENAI_ENDPOINT'
          value: openAiAccount.properties.endpoint
        }
        {
          name: 'AZURE_OPENAI_KEY'
          value: openAiAccount.listKeys().key1
        }
        {
          name: 'AZURE_STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'OPENAI_DEPLOYMENT_NAME'
          value: openAiModelDeployment.name
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATION_KEY'
          value: enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      use32BitWorkerProcess: false
      alwaysOn: functionAppSkuName != 'Y1'
    }
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

// Role assignment for Function App to access Storage Account
resource functionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, storageAccount.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the Azure OpenAI account')
output openAiAccountName string = openAiAccount.name

@description('The Azure OpenAI endpoint URL')
output openAiEndpoint string = openAiAccount.properties.endpoint

@description('The name of the deployed o1-mini model')
output openAiModelDeploymentName string = openAiModelDeployment.name

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('The storage connection string for application configuration')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('The code files container URL')
output codeFilesContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}${codeFilesContainer.name}'

@description('The review reports container URL')
output reviewReportsContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}${reviewReportsContainer.name}'

@description('Log Analytics Workspace ID for monitoring')
output logAnalyticsWorkspaceId string = enableApplicationInsights ? logAnalyticsWorkspace.id : ''

@description('Resource deployment summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  functionApp: functionApp.name
  functionAppUrl: 'https://${functionApp.properties.defaultHostName}'
  storageAccount: storageAccount.name
  openAiAccount: openAiAccount.name
  modelDeployment: openAiModelDeployment.name
  applicationInsights: enableApplicationInsights ? applicationInsights.name : 'Not deployed'
  estimatedMonthlyCost: 'Monitor usage - primarily based on OpenAI API calls and Function execution time'
}