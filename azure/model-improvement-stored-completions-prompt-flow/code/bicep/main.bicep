// ================================================================
// Azure Model Improvement Pipeline with Stored Completions and Prompt Flow
// ================================================================
// This template deploys a complete model improvement pipeline using:
// - Azure OpenAI Service with Stored Completions API
// - Azure Machine Learning workspace for Prompt Flow
// - Azure Functions for pipeline automation
// - Azure Storage for data persistence
// - Azure Monitor for observability

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environmentName string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Azure OpenAI Service pricing tier')
@allowed(['F0', 'S0'])
param openAIServiceSku string = 'S0'

@description('GPT model deployment configuration')
param gptModelConfig object = {
  name: 'gpt-4o'
  version: '2024-08-06'
  capacity: 10
}

@description('Function App pricing tier')
@allowed(['Y1', 'EP1', 'EP2'])
param functionAppSku string = 'Y1'

@description('Storage account configuration')
param storageConfig object = {
  sku: 'Standard_LRS'
  tier: 'Standard'
}

@description('Tags to apply to all resources')
param tags object = {
  project: 'ModelImprovementPipeline'
  environment: environmentName
  recipe: 'model-improvement-stored-completions-prompt-flow'
}

// ================================================================
// Variables
// ================================================================

var resourceNames = {
  openAIService: 'openai-service-${uniqueSuffix}'
  mlWorkspace: 'mlw-pipeline-${uniqueSuffix}'
  functionApp: 'func-insights-${uniqueSuffix}'
  storageAccount: 'st${uniqueSuffix}pipeline'
  hostingPlan: 'plan-${uniqueSuffix}'
  logAnalytics: 'law-${uniqueSuffix}'
  applicationInsights: 'appi-${uniqueSuffix}'
  keyVault: 'kv-${uniqueSuffix}'
  containerRegistry: 'cr${uniqueSuffix}pipeline'
}

// ================================================================
// Azure OpenAI Service with Stored Completions Support
// ================================================================

resource openAIService 'Microsoft.CognitiveServices/accounts@2024-06-01-preview' = {
  name: resourceNames.openAIService
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: openAIServiceSku
  }
  properties: {
    customSubDomainName: resourceNames.openAIService
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    // Enable stored completions feature
    apiProperties: {
      statisticsEnabled: true
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Deploy GPT model for conversation capture
resource gptModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-06-01-preview' = {
  parent: openAIService
  name: 'gpt-4o-deployment'
  sku: {
    name: 'Standard'
    capacity: gptModelConfig.capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: gptModelConfig.name
      version: gptModelConfig.version
    }
    raiPolicyName: 'Microsoft.Default'
  }
}

// ================================================================
// Storage Account for Pipeline Data
// ================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: storageConfig.sku
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
    supportsHttpsTrafficOnly: true
  }
}

// Create containers for pipeline data
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource conversationsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'conversations'
  properties: {
    publicAccess: 'None'
  }
}

resource insightsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'insights'
  properties: {
    publicAccess: 'None'
  }
}

// ================================================================
// Key Vault for Secure Configuration
// ================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Store OpenAI API key in Key Vault
resource openAIApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'openai-api-key'
  properties: {
    value: openAIService.listKeys().key1
    contentType: 'text/plain'
  }
}

// Store Storage connection string in Key Vault
resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-connection-string'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    contentType: 'text/plain'
  }
}

// ================================================================
// Container Registry for ML Components
// ================================================================

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: resourceNames.containerRegistry
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
  }
}

// ================================================================
// Azure Machine Learning Workspace for Prompt Flow
// ================================================================

resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-01-01-preview' = {
  name: resourceNames.mlWorkspace
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'Model Improvement Pipeline Workspace'
    description: 'ML workspace for Prompt Flow evaluation workflows'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: applicationInsights.id
    containerRegistry: containerRegistry.id
    publicNetworkAccess: 'Enabled'
    allowPublicAccessWhenBehindVnet: false
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
    // Enable Prompt Flow capabilities
    featureStoreSettings: {
      computeRuntime: {
        sparkRuntimeVersion: '3.3'
      }
    }
  }
  dependsOn: [
    applicationInsights
  ]
}

// ================================================================
// Monitoring and Observability
// ================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalytics
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ================================================================
// Azure Functions for Pipeline Automation
// ================================================================

resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: resourceNames.hostingPlan
  location: location
  tags: tags
  sku: {
    name: functionAppSku
    tier: functionAppSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  kind: 'functionapp'
  properties: {
    reserved: true // Linux hosting plan
  }
}

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: resourceNames.functionApp
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    reserved: true
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'Python|3.12'
      acrUseManagedIdentityCreds: false
      alwaysOn: functionAppSku != 'Y1'
      functionAppScaleLimit: functionAppSku == 'Y1' ? 200 : 0
      minimumElasticInstanceCount: functionAppSku != 'Y1' ? 1 : 0
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
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
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'OPENAI_ENDPOINT'
          value: openAIService.properties.endpoint
        }
        {
          name: 'OPENAI_API_KEY'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=openai-api-key)'
        }
        {
          name: 'ML_WORKSPACE_NAME'
          value: mlWorkspace.name
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=storage-connection-string)'
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: functionApp.identity.principalId
        }
      ]
    }
    httpsOnly: true
    redundancyMode: 'None'
  }
}

// ================================================================
// Role Assignments for Service Integration
// ================================================================

// Grant Function App access to OpenAI Service
resource functionAppOpenAIRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAIService.id, functionApp.id, 'CognitiveServicesOpenAIUser')
  scope: openAIService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to ML Workspace
resource functionAppMLRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(mlWorkspace.id, functionApp.id, 'AzureMLDataScientist')
  scope: mlWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f6c7c914-8db3-469d-8ca1-694a8f32e121') // AzureML Data Scientist
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to Key Vault
resource functionAppKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App access to Storage Account
resource functionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant ML Workspace access to OpenAI Service
resource mlWorkspaceOpenAIRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAIService.id, mlWorkspace.id, 'CognitiveServicesOpenAIUser')
  scope: openAIService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalId: mlWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ================================================================
// Diagnostic Settings for Monitoring
// ================================================================

resource functionAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'pipeline-monitoring'
  scope: functionApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

resource openAIDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'openai-monitoring'
  scope: openAIService
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'Audit'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'RequestResponse'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// ================================================================
// Outputs
// ================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Azure OpenAI Service name')
output openAIServiceName string = openAIService.name

@description('Azure OpenAI Service endpoint')
output openAIEndpoint string = openAIService.properties.endpoint

@description('GPT model deployment name')
output gptModelDeploymentName string = gptModelDeployment.name

@description('ML Workspace name')
output mlWorkspaceName string = mlWorkspace.name

@description('ML Workspace ID')
output mlWorkspaceId string = mlWorkspace.id

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App hostname')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Container Registry name')
output containerRegistryName string = containerRegistry.name

@description('Container Registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Pipeline monitoring dashboard URL')
output monitoringDashboardUrl string = 'https://portal.azure.com/#@${tenant().tenantId}/dashboard/arm/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Portal/dashboards/pipeline-dashboard'

@description('Deployment configuration summary')
output deploymentSummary object = {
  environmentName: environmentName
  resourceNames: resourceNames
  location: location
  uniqueSuffix: uniqueSuffix
  tags: tags
}