// ============================================================================
// Voice-to-Multilingual Content Pipeline with Speech and OpenAI
// This Bicep template deploys a complete serverless pipeline for converting
// voice recordings into multilingual content using Azure AI services
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@minLength(3)
@maxLength(11)
@description('Prefix for all resource names')
param resourcePrefix string = 'voice${uniqueString(resourceGroup().id)}'

@description('Azure region for all resources')
param location string = resourceGroup().location

@allowed([
  'eastus'
  'eastus2'
  'westus2'
  'centralus'
  'northcentralus'
  'southcentralus'
  'westeurope'
  'northeurope'
  'uksouth'
  'francecentral'
  'germanywestcentral'
  'swedencentral'
  'norwayeast'
  'switzerlandnorth'
  'japaneast'
  'australiaeast'
  'southeastasia'
  'koreacentral'
  'canadacentral'
  'brazilsouth'
  'southafricanorth'
  'uaenorth'
])
@description('Region for Azure OpenAI Service deployment')
param openAiLocation string = 'eastus'

@description('Target languages for translation (comma-separated language codes)')
param targetLanguages string = 'es,fr,de,ja,pt'

@description('Speech service pricing tier')
@allowed(['F0', 'S0'])
param speechServiceSku string = 'S0'

@description('OpenAI service pricing tier')
@allowed(['S0'])
param openAiServiceSku string = 'S0'

@description('Translator service pricing tier')
@allowed(['F0', 'S1', 'S2', 'S3', 'S4'])
param translatorServiceSku string = 'S1'

@description('Storage account replication type')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Function app runtime')
@allowed(['python'])
param functionAppRuntime string = 'python'

@description('Function app runtime version')
param functionAppRuntimeVersion string = '3.11'

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Enable managed identity for secure access')
param enableManagedIdentity bool = true

@description('Tags to apply to all resources')
param tags object = {
  environment: 'demo'
  purpose: 'voice-multilingual-pipeline'
  deployment: 'bicep'
}

// ============================================================================
// VARIABLES
// ============================================================================

var resourceNames = {
  storageAccount: '${resourcePrefix}st${uniqueString(resourceGroup().id)}'
  functionApp: '${resourcePrefix}-func'
  hostingPlan: '${resourcePrefix}-plan'
  speechService: '${resourcePrefix}-speech'
  openAiService: '${resourcePrefix}-openai'
  translatorService: '${resourcePrefix}-translator'
  applicationInsights: '${resourcePrefix}-ai'
  logAnalyticsWorkspace: '${resourcePrefix}-logs'
  managedIdentity: '${resourcePrefix}-identity'
}

var containerNames = {
  audioInput: 'audio-input'
  contentOutput: 'content-output'
}

// ============================================================================
// MANAGED IDENTITY
// ============================================================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (enableManagedIdentity) {
  name: resourceNames.managedIdentity
  location: location
  tags: tags
}

// ============================================================================
// LOG ANALYTICS AND APPLICATION INSIGHTS
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableApplicationInsights) {
  name: resourceNames.logAnalyticsWorkspace
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

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// STORAGE ACCOUNT
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: storageAccountSku
  }
  properties: {
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
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

// Storage containers for audio input and content output
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource audioInputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: containerNames.audioInput
  properties: {
    publicAccess: 'None'
    metadata: {}
  }
}

resource contentOutputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: containerNames.contentOutput
  properties: {
    publicAccess: 'None'
    metadata: {}
  }
}

// ============================================================================
// COGNITIVE SERVICES
// ============================================================================

// Azure Speech Service
resource speechService 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: resourceNames.speechService
  location: location
  tags: tags
  kind: 'SpeechServices'
  sku: {
    name: speechServiceSku
  }
  properties: {
    customSubDomainName: resourceNames.speechService
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
  identity: enableManagedIdentity ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  } : null
}

// Azure OpenAI Service
resource openAiService 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: resourceNames.openAiService
  location: openAiLocation
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: openAiServiceSku
  }
  properties: {
    customSubDomainName: resourceNames.openAiService
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
  identity: enableManagedIdentity ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  } : null
}

// GPT-4 deployment for content enhancement
resource gpt4Deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAiService
  name: 'gpt-4-deployment'
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4'
      version: '0613'
    }
    raiPolicyName: 'Microsoft.DefaultV2'
    scaleSettings: {
      scaleType: 'Standard'
    }
  }
  sku: {
    name: 'Standard'
    capacity: 10
  }
}

// Azure Translator Service
resource translatorService 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: resourceNames.translatorService
  location: location
  tags: tags
  kind: 'TextTranslation'
  sku: {
    name: translatorServiceSku
  }
  properties: {
    customSubDomainName: resourceNames.translatorService
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
  identity: enableManagedIdentity ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  } : null
}

// ============================================================================
// RBAC ROLE ASSIGNMENTS FOR MANAGED IDENTITY
// ============================================================================

// Storage Blob Data Contributor role for managed identity
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableManagedIdentity) {
  name: guid(storageAccount.id, managedIdentity.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: enableManagedIdentity ? managedIdentity.properties.principalId : ''
    principalType: 'ServicePrincipal'
  }
}

// Cognitive Services User role for managed identity
resource speechRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableManagedIdentity) {
  name: guid(speechService.id, managedIdentity.id, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: speechService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
    principalId: enableManagedIdentity ? managedIdentity.properties.principalId : ''
    principalType: 'ServicePrincipal'
  }
}

resource openAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableManagedIdentity) {
  name: guid(openAiService.id, managedIdentity.id, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: openAiService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
    principalId: enableManagedIdentity ? managedIdentity.properties.principalId : ''
    principalType: 'ServicePrincipal'
  }
}

resource translatorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableManagedIdentity) {
  name: guid(translatorService.id, managedIdentity.id, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  scope: translatorService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
    principalId: enableManagedIdentity ? managedIdentity.properties.principalId : ''
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// AZURE FUNCTIONS
// ============================================================================

// Consumption plan for serverless functions
resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: resourceNames.hostingPlan
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  kind: 'functionapp'
  properties: {
    computeMode: 'Dynamic'
  }
}

// Function App for pipeline orchestration
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: resourceNames.functionApp
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
          value: toLower(resourceNames.functionApp)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionAppRuntime
        }
        {
          name: 'WEBSITE_PYTHON_DEFAULT_VERSION'
          value: functionAppRuntimeVersion
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
        // AI Service Configuration
        {
          name: 'SPEECH_ENDPOINT'
          value: speechService.properties.endpoint
        }
        {
          name: 'SPEECH_KEY'
          value: speechService.listKeys().key1
        }
        {
          name: 'OPENAI_ENDPOINT'
          value: openAiService.properties.endpoint
        }
        {
          name: 'OPENAI_KEY'
          value: openAiService.listKeys().key1
        }
        {
          name: 'OPENAI_DEPLOYMENT_NAME'
          value: gpt4Deployment.name
        }
        {
          name: 'TRANSLATOR_ENDPOINT'
          value: translatorService.properties.endpoint
        }
        {
          name: 'TRANSLATOR_KEY'
          value: translatorService.listKeys().key1
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'TARGET_LANGUAGES'
          value: targetLanguages
        }
        {
          name: 'AUDIO_INPUT_CONTAINER'
          value: containerNames.audioInput
        }
        {
          name: 'CONTENT_OUTPUT_CONTAINER'
          value: containerNames.contentOutput
        }
      ]
      pythonVersion: functionAppRuntimeVersion
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
  identity: enableManagedIdentity ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  } : null
  dependsOn: [
    storageRoleAssignment
    speechRoleAssignment
    openAiRoleAssignment
    translatorRoleAssignment
  ]
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Speech Service name')
output speechServiceName string = speechService.name

@description('Speech Service endpoint')
output speechServiceEndpoint string = speechService.properties.endpoint

@description('OpenAI Service name')
output openAiServiceName string = openAiService.name

@description('OpenAI Service endpoint')
output openAiServiceEndpoint string = openAiService.properties.endpoint

@description('Translator Service name')
output translatorServiceName string = translatorService.name

@description('Translator Service endpoint')
output translatorServiceEndpoint string = translatorService.properties.endpoint

@description('Application Insights name')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Audio input container name')
output audioInputContainer string = containerNames.audioInput

@description('Content output container name')
output contentOutputContainer string = containerNames.contentOutput

@description('Managed Identity Client ID')
output managedIdentityClientId string = enableManagedIdentity ? managedIdentity.properties.clientId : ''

@description('Target languages for translation')
output targetLanguages string = targetLanguages

@description('Resource prefix used for naming')
output resourcePrefix string = resourcePrefix

@description('Deployment location')
output location string = location

@description('OpenAI deployment location')
output openAiLocation string = openAiLocation