@description('Main Bicep template for AI Model Evaluation and Benchmarking with Azure AI Foundry')

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment type (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environmentType string = 'dev'

@description('Project name prefix for resource naming')
@minLength(3)
@maxLength(10)
param projectName string = 'ai-eval'

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Azure OpenAI model deployments configuration')
param modelDeployments array = [
  {
    name: 'gpt-4o-eval'
    modelName: 'gpt-4o'
    modelVersion: '2024-08-06'
    skuName: 'Standard'
    skuCapacity: 10
  }
  {
    name: 'gpt-35-turbo-eval'
    modelName: 'gpt-35-turbo'
    modelVersion: '0125'
    skuName: 'Standard'
    skuCapacity: 10
  }
  {
    name: 'gpt-4o-mini-eval'
    modelName: 'gpt-4o-mini'
    modelVersion: '2024-07-18'
    skuName: 'Standard'
    skuCapacity: 10
  }
]

@description('Enable diagnostic logging')
param enableDiagnostics bool = true

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

// Variables
var resourceNamingConvention = {
  openaiAccount: '${projectName}-openai-${uniqueSuffix}'
  storageAccount: replace('${projectName}storage${uniqueSuffix}', '-', '')
  mlWorkspace: '${projectName}-ml-${uniqueSuffix}'
  keyVault: '${projectName}-kv-${uniqueSuffix}'
  logAnalytics: '${projectName}-logs-${uniqueSuffix}'
  applicationInsights: '${projectName}-ai-${uniqueSuffix}'
}

var storageAccountType = environmentType == 'prod' ? 'Standard_GRS' : 'Standard_LRS'
var keyVaultSku = environmentType == 'prod' ? 'premium' : 'standard'

// Common tags
var commonTags = {
  Environment: environmentType
  Project: projectName
  Purpose: 'AI Model Evaluation'
  CreatedBy: 'Bicep Template'
  Recipe: 'ai-model-evaluation-benchmarking-foundry-openai'
}

// Log Analytics Workspace (required for diagnostics)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableDiagnostics) {
  name: resourceNamingConvention.logAnalytics
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights (for monitoring ML workloads)
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNamingConvention.applicationInsights
  location: location
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableDiagnostics ? logAnalyticsWorkspace.id : null
    RetentionInDays: logRetentionDays
  }
}

// Key Vault for secrets management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNamingConvention.keyVault
  location: location
  tags: commonTags
  properties: {
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: environmentType == 'prod'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Storage Account for datasets and evaluation results
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: resourceNamingConvention.storageAccount
  location: location
  tags: commonTags
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
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

// Blob containers for evaluation data
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource evaluationDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'evaluation-data'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Model evaluation datasets'
    }
  }
}

resource resultsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'evaluation-results'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Model evaluation results and reports'
    }
  }
}

resource modelsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'models'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Custom model artifacts and evaluation flows'
    }
  }
}

// Azure OpenAI Service
resource openaiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: resourceNamingConvention.openaiAccount
  location: location
  tags: commonTags
  sku: {
    name: 'S0'
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: resourceNamingConvention.openaiAccount
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// Azure OpenAI Model Deployments
resource openaiModelDeployments 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = [for deployment in modelDeployments: {
  parent: openaiAccount
  name: deployment.name
  sku: {
    name: deployment.skuName
    capacity: deployment.skuCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: deployment.modelName
      version: deployment.modelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
}]

// Azure Machine Learning Workspace (AI Foundry Project foundation)
resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-07-01-preview' = {
  name: resourceNamingConvention.mlWorkspace
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    friendlyName: '${projectName} AI Evaluation Project'
    description: 'Azure AI Foundry project for model evaluation and benchmarking'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: applicationInsights.id
    publicNetworkAccess: 'Enabled'
    imageBuildCompute: null
    allowPublicAccessWhenBehindVnet: false
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
    workspaceHubConfig: {
      additionalWorkspaceStorageAccounts: []
      defaultWorkspaceResourceGroup: resourceGroup().name
    }
  }
}

// Compute Instance for development and evaluation
resource computeInstance 'Microsoft.MachineLearningServices/workspaces/computes@2024-07-01-preview' = {
  parent: mlWorkspace
  name: 'eval-compute-${uniqueSuffix}'
  location: location
  properties: {
    computeType: 'ComputeInstance'
    properties: {
      vmSize: environmentType == 'prod' ? 'Standard_DS3_v2' : 'Standard_DS2_v2'
      subnet: null
      applicationSharingPolicy: 'Personal'
      sshSettings: {
        sshPublicAccess: 'Disabled'
      }
      personalComputeInstanceSettings: {
        assignedUser: null
      }
      setupScripts: null
      schedules: {
        computeStartStop: []
      }
    }
  }
}

// Role assignments for ML workspace to access OpenAI and Storage
resource mlWorkspaceOpenAIRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(mlWorkspace.id, openaiAccount.id, 'Cognitive Services OpenAI User')
  scope: openaiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalId: mlWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource mlWorkspaceStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(mlWorkspace.id, storageAccount.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: mlWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Store OpenAI connection details in Key Vault
resource openaiEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'openai-endpoint'
  properties: {
    value: openaiAccount.properties.endpoint
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource openaiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'openai-key'
  properties: {
    value: openaiAccount.listKeys().key1
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Diagnostic settings for monitoring
resource openaiDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'openai-diagnostics'
  scope: openaiAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

resource mlWorkspaceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'ml-workspace-diagnostics'
  scope: mlWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'storage-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// Outputs
@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The location of the deployed resources')
output location string = location

@description('Azure OpenAI account name')
output openaiAccountName string = openaiAccount.name

@description('Azure OpenAI endpoint URL')
output openaiEndpoint string = openaiAccount.properties.endpoint

@description('Azure OpenAI custom domain')
output openaiCustomDomain string = openaiAccount.properties.customSubDomainName

@description('Deployed model names and deployment names')
output modelDeployments array = [for (deployment, i) in modelDeployments: {
  modelName: deployment.modelName
  deploymentName: deployment.name
  endpoint: '${openaiAccount.properties.endpoint}openai/deployments/${deployment.name}'
}]

@description('Azure Machine Learning workspace name')
output mlWorkspaceName string = mlWorkspace.name

@description('Azure Machine Learning workspace URL')
output mlWorkspaceUrl string = 'https://ml.azure.com/?wsid=${mlWorkspace.id}'

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account primary endpoint')
output storageAccountEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Log Analytics workspace name (if diagnostics enabled)')
output logAnalyticsWorkspaceName string = enableDiagnostics ? logAnalyticsWorkspace.name : ''

@description('Compute instance name')
output computeInstanceName string = computeInstance.name

@description('Resource naming convention used')
output resourceNames object = resourceNamingConvention

@description('Connection strings and keys for application configuration')
output connectionInfo object = {
  openaiEndpoint: openaiAccount.properties.endpoint
  storageConnectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
  keyVaultUrl: keyVault.properties.vaultUri
  applicationInsightsConnectionString: applicationInsights.properties.ConnectionString
}

@description('Container names for evaluation data organization')
output containerNames object = {
  evaluationData: evaluationDataContainer.name
  results: resultsContainer.name
  models: modelsContainer.name
}

@description('Environment configuration summary')
output environmentInfo object = {
  environmentType: environmentType
  location: location
  projectName: projectName
  uniqueSuffix: uniqueSuffix
  diagnosticsEnabled: enableDiagnostics
  logRetentionDays: logRetentionDays
}