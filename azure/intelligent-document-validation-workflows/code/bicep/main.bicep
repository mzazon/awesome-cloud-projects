@description('Main Bicep template for Enterprise-Grade Data Validation Workflows with Azure Dataverse and Azure AI Document Intelligence')

// Parameters
@description('The location where all resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'prod'

@description('Unique suffix for resource names')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Tags to apply to all resources')
param tags object = {
  environment: environment
  purpose: 'document-validation'
  solution: 'dataverse-document-intelligence'
}

@description('Azure AI Document Intelligence service tier')
@allowed(['F0', 'S0'])
param documentIntelligenceTier string = 'S0'

@description('Storage account tier for document processing')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Key Vault SKU')
@allowed(['standard', 'premium'])
param keyVaultSku string = 'standard'

@description('Logic App plan SKU')
@allowed(['WS1', 'WS2', 'WS3'])
param logicAppPlanSku string = 'WS1'

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 90

// Variables
var resourcePrefix = 'docval-${environment}-${uniqueSuffix}'
var documentIntelligenceName = '${resourcePrefix}-docint'
var storageAccountName = replace('${resourcePrefix}storage', '-', '')
var keyVaultName = '${resourcePrefix}-kv'
var logicAppName = '${resourcePrefix}-logic'
var logAnalyticsWorkspaceName = '${resourcePrefix}-law'
var applicationInsightsName = '${resourcePrefix}-ai'
var logicAppPlanName = '${resourcePrefix}-plan'

// Storage Account for document processing
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: take(storageAccountName, 24)
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: true
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
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Blob containers for document processing
resource documentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/documents'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'document-uploads'
    }
  }
}

resource trainingDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/training-data'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'custom-model-training'
    }
  }
}

resource processedContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/processed'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'processed-documents'
    }
  }
}

// Azure AI Document Intelligence Service
resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: documentIntelligenceName
  location: location
  tags: tags
  sku: {
    name: documentIntelligenceTier
  }
  kind: 'FormRecognizer'
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
    customSubDomainName: documentIntelligenceName
    encryption: {
      keySource: 'Microsoft.KeyVault'
    }
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: false
  }
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
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

// Key Vault for secure credential storage
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    tenantId: tenant().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Store Document Intelligence endpoint and key in Key Vault
resource documentIntelligenceEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'DocumentIntelligenceEndpoint'
  properties: {
    value: documentIntelligence.properties.endpoint
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
  }
}

resource documentIntelligenceKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'DocumentIntelligenceKey'
  properties: {
    value: documentIntelligence.listKeys().key1
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
  }
}

// Store storage account connection string in Key Vault
resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'StorageConnectionString'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
  }
}

// Logic App Service Plan
resource logicAppPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: logicAppPlanName
  location: location
  tags: tags
  sku: {
    name: logicAppPlanSku
    tier: 'WorkflowStandard'
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: 20
    isSpot: false
    reserved: false
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
  }
}

// Logic App for workflow orchestration
resource logicApp 'Microsoft.Web/sites@2023-12-01' = {
  name: logicAppName
  location: location
  tags: tags
  kind: 'functionapp,workflowapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: logicAppPlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      functionsRuntimeScaleMonitoringEnabled: false
      use32BitWorkerProcess: false
      appSettings: [
        {
          name: 'APP_KIND'
          value: 'workflowApp'
        }
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
          value: '${logicAppName}-content'
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
          name: 'AzureFunctionsJobHost__extensionBundle__id'
          value: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__version'
          value: '[1.*, 2.0.0)'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'WORKFLOWS_SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
        {
          name: 'WORKFLOWS_RESOURCE_GROUP_NAME'
          value: resourceGroup().name
        }
        {
          name: 'WORKFLOWS_LOCATION_NAME'
          value: location
        }
        {
          name: 'WORKFLOWS_MANAGEMENT_BASE_URI'
          value: environment().resourceManager
        }
        {
          name: 'KEYVAULT_URI'
          value: keyVault.properties.vaultUri
        }
        {
          name: 'DOCUMENT_INTELLIGENCE_ENDPOINT'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/DocumentIntelligenceEndpoint/)'
        }
        {
          name: 'DOCUMENT_INTELLIGENCE_KEY'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/DocumentIntelligenceKey/)'
        }
      ]
    }
  }
}

// Grant Logic App access to Key Vault
resource keyVaultAccessPolicy 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, logicApp.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Logic App access to Storage Account
resource storageAccessPolicy 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, logicApp.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Logic App access to Document Intelligence
resource documentIntelligenceAccessPolicy 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(documentIntelligence.id, logicApp.id, 'Cognitive Services User')
  scope: documentIntelligence
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908') // Cognitive Services User
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Diagnostic settings for Document Intelligence
resource documentIntelligenceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableApplicationInsights) {
  name: 'documentIntelligenceDiagnostics'
  scope: documentIntelligence
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
  }
}

// Diagnostic settings for Logic App
resource logicAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableApplicationInsights) {
  name: 'logicAppDiagnostics'
  scope: logicApp
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
  }
}

// Outputs
@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Azure AI Document Intelligence service name')
output documentIntelligenceName string = documentIntelligence.name

@description('Azure AI Document Intelligence endpoint')
output documentIntelligenceEndpoint string = documentIntelligence.properties.endpoint

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Storage Account blob endpoint')
output storageAccountBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Logic App name')
output logicAppName string = logicApp.name

@description('Logic App default hostname')
output logicAppHostname string = logicApp.properties.defaultHostName

@description('Logic App principal ID for RBAC assignments')
output logicAppPrincipalId string = logicApp.identity.principalId

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Application Insights name (if enabled)')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''

@description('Application Insights Instrumentation Key (if enabled)')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Application Insights Connection String (if enabled)')
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('Document container URL')
output documentsContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}documents'

@description('Training data container URL')
output trainingDataContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}training-data'

@description('Processed documents container URL')
output processedContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}processed'

@description('Resource tags applied to all resources')
output resourceTags object = tags