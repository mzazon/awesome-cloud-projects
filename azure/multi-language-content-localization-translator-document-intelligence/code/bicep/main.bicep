@description('Main Bicep template for Azure Multi-Language Content Localization Workflow')
@description('Deploys Azure Translator, AI Document Intelligence, Logic Apps, and Storage Account')

// Parameters with default values and validation
@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Project name for resource naming')
@minLength(3)
@maxLength(10)
param projectName string = 'localize'

@description('Unique suffix for resource names (leave empty for auto-generation)')
param uniqueSuffix string = ''

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Translator service SKU')
@allowed(['F0', 'S1', 'S2', 'S3', 'S4'])
param translatorSku string = 'S1'

@description('Document Intelligence service SKU')
@allowed(['F0', 'S0'])
param documentIntelligenceSku string = 'S0'

@description('Logic App pricing tier')
@allowed(['Standard', 'Basic'])
param logicAppTier string = 'Standard'

@description('Enable monitoring and diagnostics')
param enableMonitoring bool = true

@description('Target languages for translation (comma-separated)')
param targetLanguages string = 'es,fr,de,it,pt'

@description('Tags to apply to all resources')
param resourceTags object = {
  Environment: environment
  Project: projectName
  Purpose: 'ContentLocalization'
  CreatedBy: 'BicepTemplate'
}

// Variables for resource naming
var suffix = empty(uniqueSuffix) ? uniqueString(resourceGroup().id) : uniqueSuffix
var storageAccountName = 'st${projectName}${suffix}'
var translatorServiceName = 'translator-${projectName}-${suffix}'
var documentIntelligenceName = 'docintel-${projectName}-${suffix}'
var logicAppName = 'logic-${projectName}-${suffix}'
var appServicePlanName = 'asp-${projectName}-${suffix}'
var applicationInsightsName = 'appi-${projectName}-${suffix}'
var logAnalyticsWorkspaceName = 'law-${projectName}-${suffix}'
var storageConnectionName = 'azureblob-${projectName}-${suffix}'

// Storage account containers
var storageContainers = [
  'source-documents'
  'processing-workspace'
  'localized-output'
  'workflow-logs'
]

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableMonitoring) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
  }
}

// Application Insights for application monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableMonitoring) {
  name: applicationInsightsName
  location: location
  kind: 'web'
  tags: resourceTags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableMonitoring ? logAnalyticsWorkspace.id : null
    IngestionMode: 'LogAnalytics'
  }
}

// Storage Account for document processing
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: false
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

// Blob service configuration
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
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
      enabled: true
      days: 7
    }
    isVersioningEnabled: false
  }
}

// Storage containers for document workflow
resource storageContainers_resource 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for container in storageContainers: {
  parent: blobService
  name: container
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}]

// Azure Translator Service
resource translatorService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: translatorServiceName
  location: location
  tags: resourceTags
  sku: {
    name: translatorSku
  }
  kind: 'TextTranslation'
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
    customSubDomainName: translatorServiceName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// Azure AI Document Intelligence Service
resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: documentIntelligenceName
  location: location
  tags: resourceTags
  sku: {
    name: documentIntelligenceSku
  }
  kind: 'FormRecognizer'
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
    customSubDomainName: documentIntelligenceName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// App Service Plan for Logic Apps
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: resourceTags
  sku: {
    name: logicAppTier == 'Standard' ? 'WS1' : 'WS1'
    tier: 'WorkflowStandard'
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: 20
    targetWorkerCount: 0
    targetWorkerSizeId: 0
  }
}

// API Connection for Azure Blob Storage
resource storageConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: storageConnectionName
  location: location
  tags: resourceTags
  properties: {
    displayName: 'Azure Blob Storage Connection'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
    }
    parameterValues: {
      accountName: storageAccount.name
      accessKey: storageAccount.listKeys().keys[0].value
    }
  }
}

// Logic App for workflow orchestration
resource logicApp 'Microsoft.Web/sites@2023-01-01' = {
  name: logicAppName
  location: location
  tags: resourceTags
  kind: 'functionapp,workflowapp'
  properties: {
    serverFarmId: appServicePlan.id
    reserved: false
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 0
      minimumElasticInstanceCount: 0
      appSettings: [
        {
          name: 'APP_KIND'
          value: 'workflowApp'
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
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(logicAppName)
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableMonitoring ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableMonitoring ? applicationInsights.properties.ConnectionString : ''
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
          name: 'DOCUMENT_INTELLIGENCE_ENDPOINT'
          value: documentIntelligence.properties.endpoint
        }
        {
          name: 'DOCUMENT_INTELLIGENCE_KEY'
          value: documentIntelligence.listKeys().key1
        }
        {
          name: 'TARGET_LANGUAGES'
          value: targetLanguages
        }
      ]
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Logic App configuration
resource logicAppConfig 'Microsoft.Web/sites/config@2023-01-01' = {
  parent: logicApp
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
    netFrameworkVersion: 'v6.0'
    requestTracingEnabled: false
    remoteDebuggingEnabled: false
    httpLoggingEnabled: false
    acrUseManagedIdentityCreds: false
    logsDirectorySizeLimit: 35
    detailedErrorLoggingEnabled: false
    publishingUsername: '$${logicAppName}'
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
        'https://afd.hosting.portal.azure.net'
        'https://afd.hosting-ms.portal.azure.net'
        'https://hosting.portal.azure.net'
        'https://ms.hosting.portal.azure.net'
        'https://ema-ms.hosting.portal.azure.net'
        'https://ema.hosting.portal.azure.net'
        'https://ema.hosting.portal.azure.net'
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
    functionAppScaleLimit: 0
    functionsRuntimeScaleMonitoringEnabled: false
    minimumElasticInstanceCount: 0
    azureStorageAccounts: {}
  }
}

// Diagnostic settings for Storage Account
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: 'storageAccountDiagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Diagnostic settings for Translator Service
resource translatorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: 'translatorDiagnostics'
  scope: translatorService
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

// Diagnostic settings for Document Intelligence
resource documentIntelligenceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: 'documentIntelligenceDiagnostics'
  scope: documentIntelligence
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

// Diagnostic settings for Logic App
resource logicAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: 'logicAppDiagnostics'
  scope: logicApp
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

// Outputs for reference and verification
@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account connection string')
@secure()
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('Translator service endpoint')
output translatorEndpoint string = translatorService.properties.endpoint

@description('Translator service key')
@secure()
output translatorKey string = translatorService.listKeys().key1

@description('Document Intelligence endpoint')
output documentIntelligenceEndpoint string = documentIntelligence.properties.endpoint

@description('Document Intelligence key')
@secure()
output documentIntelligenceKey string = documentIntelligence.listKeys().key1

@description('Logic App name')
output logicAppName string = logicApp.name

@description('Logic App default hostname')
output logicAppDefaultHostname string = logicApp.properties.defaultHostName

@description('Logic App resource ID')
output logicAppId string = logicApp.id

@description('Application Insights instrumentation key')
@secure()
output applicationInsightsInstrumentationKey string = enableMonitoring ? applicationInsights.properties.InstrumentationKey : ''

@description('Application Insights connection string')
@secure()
output applicationInsightsConnectionString string = enableMonitoring ? applicationInsights.properties.ConnectionString : ''

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Deployment location')
output deploymentLocation string = location

@description('Storage container URLs')
output storageContainerUrls object = {
  sourceDocuments: '${storageAccount.properties.primaryEndpoints.blob}source-documents'
  processingWorkspace: '${storageAccount.properties.primaryEndpoints.blob}processing-workspace'
  localizedOutput: '${storageAccount.properties.primaryEndpoints.blob}localized-output'
  workflowLogs: '${storageAccount.properties.primaryEndpoints.blob}workflow-logs'
}

@description('Service endpoints for integration')
output serviceEndpoints object = {
  translator: translatorService.properties.endpoint
  documentIntelligence: documentIntelligence.properties.endpoint
  logicApp: 'https://${logicApp.properties.defaultHostName}'
  storage: storageAccount.properties.primaryEndpoints.blob
}

@description('Monitoring resources')
output monitoringResources object = enableMonitoring ? {
  logAnalyticsWorkspace: logAnalyticsWorkspace.id
  applicationInsights: applicationInsights.id
  instrumentationKey: applicationInsights.properties.InstrumentationKey
} : {}

@description('Storage connection details for Logic App')
output storageConnectionDetails object = {
  name: storageConnection.name
  id: storageConnection.id
  displayName: storageConnection.properties.displayName
}

@description('Deployment summary')
output deploymentSummary object = {
  storageAccount: storageAccount.name
  translatorService: translatorService.name
  documentIntelligence: documentIntelligence.name
  logicApp: logicApp.name
  appServicePlan: appServicePlan.name
  containersCreated: length(storageContainers)
  monitoringEnabled: enableMonitoring
  targetLanguages: targetLanguages
}