@description('Main Bicep template for Voice Recording Analysis with AI Speech and Functions')

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('A unique suffix to append to resource names to ensure global uniqueness')
@minLength(3)
@maxLength(8)
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('The pricing tier for the Speech service')
@allowed(['F0', 'S0'])
param speechServiceSku string = 'F0'

@description('The pricing tier for the storage account')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('The pricing tier for the Function App hosting plan')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppSku string = 'Y1'

@description('The Python version to use for the Function App')
@allowed(['3.9', '3.10', '3.11'])
param pythonVersion string = '3.11'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'voice-analysis-recipe'
  environment: environment
  'created-by': 'bicep-template'
}

// Variables
var resourceNames = {
  storageAccount: 'voicestorage${uniqueSuffix}'
  speechService: 'voice-speech-${uniqueSuffix}'
  functionApp: 'voice-function-${uniqueSuffix}'
  hostingPlan: 'voice-plan-${uniqueSuffix}'
  applicationInsights: 'voice-insights-${uniqueSuffix}'
  logAnalyticsWorkspace: 'voice-logs-${uniqueSuffix}'
}

var containerNames = {
  audioInput: 'audio-input'
  transcripts: 'transcripts'
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
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

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
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

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
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
    allowBlobPublicAccess: false
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

// Blob Service
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    changeFeed: {
      enabled: false
    }
    restorePolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: true
      days: 7
    }
    isVersioningEnabled: false
  }
}

// Audio Input Container
resource audioInputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerNames.audioInput
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Transcripts Container
resource transcriptsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerNames.transcripts
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Cognitive Services Account (Speech)
resource speechService 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: resourceNames.speechService
  location: location
  tags: tags
  sku: {
    name: speechServiceSku
  }
  kind: 'SpeechServices'
  properties: {
    apiProperties: {}
    customSubDomainName: resourceNames.speechService
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: false
    disableLocalAuth: false
  }
}

// App Service Plan for Function App
resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: resourceNames.hostingPlan
  location: location
  tags: tags
  sku: {
    name: functionAppSku
    tier: functionAppSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  kind: 'functionapp'
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: true
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: resourceNames.functionApp
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    enabled: true
    hostNameSslStates: [
      {
        name: '${resourceNames.functionApp}.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Standard'
      }
      {
        name: '${resourceNames.functionApp}.scm.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Repository'
      }
    ]
    serverFarmId: hostingPlan.id
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
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
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
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
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
          name: 'SPEECH_KEY'
          value: speechService.listKeys().key1
        }
        {
          name: 'SPEECH_REGION'
          value: location
        }
        {
          name: 'SPEECH_ENDPOINT'
          value: speechService.properties.endpoint
        }
        {
          name: 'STORAGE_CONNECTION'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
        }
      ]
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    containerSize: 1536
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Function App Configuration
resource functionAppConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'web'
  properties: {
    numberOfWorkers: 1
    defaultDocuments: [
      'Default.htm'
      'Default.html'
      'Default.asp'
      'index.htm'
      'index.html'
      'iisstart.htm'
      'default.aspx'
      'index.php'
    ]
    netFrameworkVersion: 'v4.0'
    linuxFxVersion: 'Python|${pythonVersion}'
    requestTracingEnabled: false
    remoteDebuggingEnabled: false
    httpLoggingEnabled: false
    acrUseManagedIdentityCreds: false
    logsDirectorySizeLimit: 35
    detailedErrorLoggingEnabled: false
    publishingUsername: '$${resourceNames.functionApp}'
    scmType: 'None'
    use32BitWorkerProcess: false
    webSocketsEnabled: false
    alwaysOn: false
    managedPipelineMode: 'Integrated'
    virtualApplications: [
      {
        virtualPath: '/'
        physicalPath: 'site\\wwwroot'
        preloadEnabled: false
      }
    ]
    loadBalancing: 'LeastRequests'
    experiments: {
      rampUpRules: []
    }
    autoHealEnabled: false
    vnetRouteAllEnabled: false
    vnetPrivatePortsCount: 0
    cors: {
      allowedOrigins: [
        'https://portal.azure.com'
      ]
      supportCredentials: false
    }
    localMySqlEnabled: false
    ipSecurityRestrictions: [
      {
        ipAddress: 'Any'
        action: 'Allow'
        priority: 2147483647
        name: 'Allow all'
        description: 'Allow all access'
      }
    ]
    scmIpSecurityRestrictions: [
      {
        ipAddress: 'Any'
        action: 'Allow'
        priority: 2147483647
        name: 'Allow all'
        description: 'Allow all access'
      }
    ]
    scmIpSecurityRestrictionsUseMain: false
    http20Enabled: false
    minTlsVersion: '1.2'
    scmMinTlsVersion: '1.2'
    ftpsState: 'FtpsOnly'
    preWarmedInstanceCount: 0
    functionAppScaleLimit: 200
    functionsRuntimeScaleMonitoringEnabled: false
    minimumElasticInstanceCount: 0
    azureStorageAccounts: {}
  }
}

// Outputs
@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The connection string for the storage account')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'

@description('The name of the Speech service')
output speechServiceName string = speechService.name

@description('The endpoint URL for the Speech service')
output speechServiceEndpoint string = speechService.properties.endpoint

@description('The primary key for the Speech service')
@secure()
output speechServiceKey string = speechService.listKeys().key1

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The Application Insights instrumentation key')
@secure()
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The Application Insights connection string')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Container names for audio processing')
output containerNames object = {
  audioInput: audioInputContainer.name
  transcripts: transcriptsContainer.name
}

@description('Resource names created by this template')
output resourceNames object = resourceNames

@description('Function App transcription endpoint URL (after deployment)')
output transcriptionEndpointUrl string = 'https://${functionApp.properties.defaultHostName}/api/transcribe'

@description('Instructions for testing the deployment')
output testingInstructions object = {
  step1: 'Upload an audio file to the ${audioInputContainer.name} container'
  step2: 'Call the transcription endpoint at ${functionApp.properties.defaultHostName}/api/transcribe'
  step3: 'Check the ${transcriptsContainer.name} container for results'
  note: 'Function code needs to be deployed separately using Azure Functions Core Tools or VS Code'
}