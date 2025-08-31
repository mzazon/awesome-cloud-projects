// AI Application Testing with Evaluation Flows and AI Foundry
// This template deploys the infrastructure for automated AI application testing
// using Azure AI Foundry's evaluation flows and Prompt Flow integration

@description('The base name for all resources')
param baseName string = 'ai-testing'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('The SKU for the AI Services resource')
@allowed(['S0', 'S1', 'S2', 'S3'])
param aiServicesSku string = 'S0'

@description('The capacity for the OpenAI model deployment')
@minValue(1)
@maxValue(1000)
param modelDeploymentCapacity int = 10

@description('The OpenAI model name for evaluation')
@allowed(['gpt-4o-mini', 'gpt-4', 'gpt-35-turbo'])
param evaluationModelName string = 'gpt-4o-mini'

@description('The version of the OpenAI model')
param modelVersion string = '2024-07-18'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'ai-testing'
  environment: environment
  'recipe-name': 'ai-application-testing-evaluation-flows-foundry'
}

@description('Enable diagnostic settings for monitoring')
param enableDiagnostics bool = true

// Generate unique suffix for resource names
var uniqueSuffix = uniqueString(resourceGroup().id, baseName)
var resourceBaseName = '${baseName}-${environment}-${uniqueSuffix}'

// Resource names
var aiServicesName = '${resourceBaseName}-aisvc'
var storageAccountName = replace('${resourceBaseName}stor', '-', '')
var keyVaultName = '${resourceBaseName}-kv'
var logAnalyticsWorkspaceName = '${resourceBaseName}-logs'
var appInsightsName = '${resourceBaseName}-insights'
var modelDeploymentName = 'gpt-4o-mini-eval'

// Storage container names
var testDatasetContainer = 'test-datasets'
var evaluationResultsContainer = 'evaluation-results'
var flowPackagesContainer = 'flow-packages'

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for application monitoring
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Key Vault for storing secrets and API keys
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
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

// Storage Account for test data, evaluation results, and flow packages
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: True
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

// Blob service configuration
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: true
      days: 7
    }
  }
}

// Container for test datasets
resource testDatasetContainer_resource 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: testDatasetContainer
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Container for evaluation results
resource evaluationResultsContainer_resource 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: evaluationResultsContainer
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Container for flow packages
resource flowPackagesContainer_resource 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: flowPackagesContainer
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Azure AI Services resource (Multi-service AI resource for AI Foundry)
resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: aiServicesName
  location: location
  tags: tags
  sku: {
    name: aiServicesSku
  }
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: aiServicesName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    apiProperties: {
      statisticsEnabled: false
    }
    disableLocalAuth: false
  }
}

// OpenAI model deployment for evaluation
resource openAIModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiServices
  name: modelDeploymentName
  sku: {
    name: 'Standard'
    capacity: modelDeploymentCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: evaluationModelName
      version: modelVersion
    }
    raiPolicyName: 'Microsoft.DefaultHeader'
  }
}

// Store AI Services key in Key Vault
resource aiServicesKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ai-services-key'
  properties: {
    value: aiServices.listKeys().key1
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Store AI Services endpoint in Key Vault
resource aiServicesEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ai-services-endpoint'
  properties: {
    value: aiServices.properties.endpoint
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Store storage account connection string in Key Vault
resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-connection-string'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Diagnostic settings for AI Services
resource aiServicesDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  scope: aiServices
  name: 'ai-services-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Diagnostic settings for Storage Account
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  scope: storageAccount
  name: 'storage-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Diagnostic settings for Key Vault
resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  scope: keyVault
  name: 'keyvault-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'AzurePolicyEvaluationDetails'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Outputs for integration with external systems
@description('The name of the deployed AI Services resource')
output aiServicesName string = aiServices.name

@description('The endpoint URL of the AI Services resource')
output aiServicesEndpoint string = aiServices.properties.endpoint

@description('The name of the OpenAI model deployment')
output modelDeploymentName string = openAIModelDeployment.name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The name of the Application Insights instance')
output appInsightsName string = appInsights.name

@description('The instrumentation key for Application Insights')
output appInsightsinstrumentationKey string = appInsights.properties.InstrumentationKey

@description('The connection string for Application Insights')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('The primary endpoint of the storage account')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The names of the created storage containers')
output storageContainers object = {
  testDatasets: testDatasetContainer
  evaluationResults: evaluationResultsContainer
  flowPackages: flowPackagesContainer
}

@description('Resource group name for reference')
output resourceGroupName string = resourceGroup().name

@description('Resource group location')
output resourceGroupLocation string = resourceGroup().location

@description('The system-assigned managed identity of the AI Services resource')
output aiServicesIdentityPrincipalId string = aiServices.identity.principalId

@description('Environment variables for Azure DevOps pipeline integration')
output pipelineEnvironmentVariables object = {
  AZURE_SUBSCRIPTION_ID: subscription().subscriptionId
  AZURE_RESOURCE_GROUP: resourceGroup().name
  AZURE_AI_SERVICES_NAME: aiServices.name
  AZURE_AI_SERVICES_ENDPOINT: aiServices.properties.endpoint
  AZURE_OPENAI_DEPLOYMENT: openAIModelDeployment.name
  AZURE_STORAGE_ACCOUNT: storageAccount.name
  AZURE_KEY_VAULT_NAME: keyVault.name
  AZURE_APPLICATION_INSIGHTS_NAME: appInsights.name
}