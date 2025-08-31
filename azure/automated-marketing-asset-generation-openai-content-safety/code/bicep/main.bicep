@description('The name prefix for all resources')
param namePrefix string = 'marketing-ai'

@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('The random suffix for unique resource names')
param randomSuffix string = uniqueString(resourceGroup().id)

@description('The pricing tier for the storage account')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('The pricing tier for Azure OpenAI Service')
@allowed([
  'S0'
])
param openAiSku string = 'S0'

@description('The pricing tier for Content Safety Service')
@allowed([
  'S0'
])
param contentSafetySku string = 'S0'

@description('The pricing tier for the Function App')
@allowed([
  'Y1'
  'EP1'
  'EP2'
  'EP3'
])
param functionAppSku string = 'Y1'

@description('The custom subdomain for the OpenAI service')
param openAiCustomDomain string = '${namePrefix}-openai-${randomSuffix}'

@description('The capacity for GPT-4 deployment')
@minValue(1)
@maxValue(100)
param gpt4Capacity int = 10

@description('The capacity for DALL-E 3 deployment')
@minValue(1)
@maxValue(10)
param dalleCapacity int = 1

@description('The Python runtime version for the Function App')
@allowed([
  '3.9'
  '3.10'
  '3.11'
])
param pythonVersion string = '3.11'

// Variables for consistent naming
var storageAccountName = 'st${namePrefix}${randomSuffix}'
var functionAppName = 'func-${namePrefix}-${randomSuffix}'
var appServicePlanName = 'plan-${namePrefix}-${randomSuffix}'
var openAiAccountName = '${namePrefix}-openai-${randomSuffix}'
var contentSafetyAccountName = '${namePrefix}-cs-${randomSuffix}'
var applicationInsightsName = 'appi-${namePrefix}-${randomSuffix}'
var logAnalyticsWorkspaceName = 'log-${namePrefix}-${randomSuffix}'

// Common tags for all resources
var commonTags = {
  Purpose: 'marketing-automation'
  Environment: 'demo'
  Recipe: 'automated-marketing-asset-generation'
  GeneratedBy: 'bicep-template'
}

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: commonTags
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

// Application Insights for Function App monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Storage Account for marketing assets and function app
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name: storageAccountName
  location: location
  tags: union(commonTags, {
    Usage: 'marketing-assets'
  })
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
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

// Blob containers for content workflow
resource marketingRequestsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = {
  name: '${storageAccount.name}/default/marketing-requests'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

resource marketingAssetsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = {
  name: '${storageAccount.name}/default/marketing-assets'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'Blob'
  }
}

resource rejectedContentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = {
  name: '${storageAccount.name}/default/rejected-content'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Azure OpenAI Service
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = {
  name: openAiAccountName
  location: location
  tags: union(commonTags, {
    Usage: 'marketing-content-generation'
  })
  sku: {
    name: openAiSku
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openAiCustomDomain
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
}

// GPT-4 Model Deployment
resource gpt4Deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-04-01-preview' = {
  parent: openAiAccount
  name: 'gpt-4-marketing'
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4'
      version: '0613'
    }
  }
  sku: {
    name: 'Standard'
    capacity: gpt4Capacity
  }
}

// DALL-E 3 Model Deployment
resource dalle3Deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-04-01-preview' = {
  parent: openAiAccount
  name: 'dalle-3-marketing'
  dependsOn: [
    gpt4Deployment
  ]
  properties: {
    model: {
      format: 'OpenAI'
      name: 'dall-e-3'
      version: '3.0'
    }
  }
  sku: {
    name: 'Standard'
    capacity: dalleCapacity
  }
}

// Content Safety Service
resource contentSafetyAccount 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = {
  name: contentSafetyAccountName
  location: location
  tags: union(commonTags, {
    Usage: 'marketing-content-moderation'
  })
  sku: {
    name: contentSafetySku
  }
  kind: 'ContentSafety'
  properties: {
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
}

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: commonTags
  sku: {
    name: functionAppSku
    tier: functionAppSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  properties: {
    reserved: true // Required for Linux
  }
}

// Function App for orchestration
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: union(commonTags, {
    Usage: 'marketing-automation'
  })
  kind: 'functionapp,linux'
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
      linuxFxVersion: 'Python|${pythonVersion}'
      acrUseManagedIdentityCreds: false
      alwaysOn: functionAppSku != 'Y1'
      http20Enabled: false
      functionAppScaleLimit: functionAppSku == 'Y1' ? 200 : 0
      minimumElasticInstanceCount: functionAppSku != 'Y1' ? 1 : 0
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    customDomainVerificationId: ''
    containerSize: 1536
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Function App Configuration
resource functionAppConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'appsettings'
  properties: {
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    WEBSITE_CONTENTSHARE: toLower(functionAppName)
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'python'
    WEBSITE_PYTHON_DEFAULT_VERSION: pythonVersion
    APPINSIGHTS_INSTRUMENTATIONKEY: applicationInsights.properties.InstrumentationKey
    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
    
    // Azure OpenAI Configuration
    AZURE_OPENAI_ENDPOINT: openAiAccount.properties.endpoint
    AZURE_OPENAI_KEY: openAiAccount.listKeys().key1
    
    // Content Safety Configuration
    CONTENT_SAFETY_ENDPOINT: contentSafetyAccount.properties.endpoint
    CONTENT_SAFETY_KEY: contentSafetyAccount.listKeys().key1
    
    // Storage Configuration
    STORAGE_CONNECTION_STRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    
    // Function Timeout Configuration
    functionTimeout: '00:05:00'
  }
}

// Outputs for verification and integration
output resourceGroupName string = resourceGroup().name
output storageAccountName string = storageAccount.name
output storageAccountKey string = storageAccount.listKeys().keys[0].value
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output openAiAccountName string = openAiAccount.name
output openAiEndpoint string = openAiAccount.properties.endpoint
output contentSafetyAccountName string = contentSafetyAccount.name
output contentSafetyEndpoint string = contentSafetyAccount.properties.endpoint
output applicationInsightsName string = applicationInsights.name
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output marketingRequestsContainerUrl string = 'https://${storageAccount.name}.blob.${environment().suffixes.storage}/marketing-requests'
output marketingAssetsContainerUrl string = 'https://${storageAccount.name}.blob.${environment().suffixes.storage}/marketing-assets'
output gpt4DeploymentName string = gpt4Deployment.name
output dalle3DeploymentName string = dalle3Deployment.name