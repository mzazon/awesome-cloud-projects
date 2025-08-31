@description('The name prefix for all resources')
param namePrefix string = 'sentiment'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('The pricing tier for the Cognitive Services Language resource')
@allowed(['F0', 'S0', 'S1', 'S2', 'S3', 'S4'])
param languageServiceSku string = 'S0'

@description('The SKU for the Storage Account')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS', 'Premium_LRS'])
param storageAccountSku string = 'Standard_LRS'

@description('The pricing tier for the Function App Service Plan')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppPlanSku string = 'Y1'

@description('The Python version for the Function App')
@allowed(['3.8', '3.9', '3.10', '3.11'])
param pythonVersion string = '3.11'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: 'SentimentAnalysis'
  Purpose: 'Recipe'
}

// Generate unique suffix for resource names
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var languageServiceName = '${namePrefix}-lang-${uniqueSuffix}'
var functionAppName = '${namePrefix}-func-${uniqueSuffix}'
var storageAccountName = '${namePrefix}st${uniqueSuffix}'
var appServicePlanName = '${namePrefix}-plan-${uniqueSuffix}'
var applicationInsightsName = '${namePrefix}-ai-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${namePrefix}-law-${uniqueSuffix}'

// Log Analytics Workspace for Application Insights
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
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for monitoring and telemetry
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
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

// Storage Account for Function App runtime and storage needs
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
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
  }
}

// Azure Cognitive Services Language resource for sentiment analysis
resource languageService 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: languageServiceName
  location: location
  tags: tags
  sku: {
    name: languageServiceSku
  }
  kind: 'TextAnalytics'
  properties: {
    customSubDomainName: languageServiceName
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// App Service Plan for Function App (Consumption plan for serverless)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: functionAppPlanSku
    tier: functionAppPlanSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  kind: functionAppPlanSku == 'Y1' ? 'functionapp' : 'elastic'
  properties: {
    reserved: true // Required for Linux
  }
}

// Function App for sentiment analysis processing
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|${pythonVersion}'
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
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'LANGUAGE_ENDPOINT'
          value: languageService.properties.endpoint
        }
        {
          name: 'LANGUAGE_KEY'
          value: languageService.listKeys().key1
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
      cors: {
        allowedOrigins: [
          '*'
        ]
        supportCredentials: false
      }
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      use32BitWorkerProcess: false
      http20Enabled: true
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

// Function App configuration for additional settings
resource functionAppConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'web'
  properties: {
    numberOfWorkers: 1
    defaultDocuments: []
    netFrameworkVersion: 'v6.0'
    requestTracingEnabled: false
    remoteDebuggingEnabled: false
    remoteDebuggingVersion: 'VS2019'
    httpLoggingEnabled: true
    detailedErrorLoggingEnabled: false
    publishingUsername: '$${functionAppName}'
    scmType: 'None'
    use32BitWorkerProcess: false
    webSocketsEnabled: false
    alwaysOn: functionAppPlanSku != 'Y1' ? true : false
    managedPipelineMode: 'Integrated'
    virtualApplications: [
      {
        virtualPath: '/'
        physicalPath: 'site\\wwwroot'
        preloadEnabled: functionAppPlanSku != 'Y1' ? true : false
      }
    ]
    loadBalancing: 'LeastRequests'
    autoHealEnabled: false
    vnetRouteAllEnabled: false
    vnetPrivatePortsCount: 0
    publicNetworkAccess: 'Enabled'
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
    http20Enabled: true
    minTlsVersion: '1.2'
    scmMinTlsVersion: '1.2'
    ftpsState: 'Disabled'
    preWarmedInstanceCount: 0
    functionAppScaleLimit: 200
    functionsRuntimeScaleMonitoringEnabled: false
    minimumElasticInstanceCount: 0
    azureStorageAccounts: {}
  }
}

// Outputs for reference and integration
@description('The name of the created resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the Language Service resource')
output languageServiceName string = languageService.name

@description('The endpoint URL of the Language Service')
output languageServiceEndpoint string = languageService.properties.endpoint

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The Function endpoint URL for sentiment analysis')
output sentimentAnalysisEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/analyze'

@description('The name of the Storage Account')
output storageAccountName string = storageAccount.name

@description('The name of the Application Insights resource')
output applicationInsightsName string = applicationInsights.name

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The name of the App Service Plan')
output appServicePlanName string = appServicePlan.name

@description('The Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Resource deployment summary')
output deploymentSummary object = {
  languageService: {
    name: languageService.name
    endpoint: languageService.properties.endpoint
    sku: languageServiceSku
  }
  functionApp: {
    name: functionApp.name
    url: 'https://${functionApp.properties.defaultHostName}'
    runtime: 'Python ${pythonVersion}'
    plan: functionAppPlanSku
  }
  monitoring: {
    applicationInsights: applicationInsights.name
    logAnalytics: logAnalyticsWorkspace.name
  }
  storage: {
    name: storageAccount.name
    sku: storageAccountSku
  }
}