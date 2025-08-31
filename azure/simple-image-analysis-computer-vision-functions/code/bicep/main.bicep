// Azure Bicep template for Simple Image Analysis with Computer Vision and Functions
// This template deploys the complete infrastructure for an image analysis API using Azure Functions and Computer Vision

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('The primary region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment type for resource naming and configuration')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Project name used for resource naming conventions')
@minLength(3)
@maxLength(10)
param projectName string = 'imganalysis'

@description('Unique suffix for resource names to ensure global uniqueness')
@minLength(3)
@maxLength(6)
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('SKU for the Computer Vision service')
@allowed(['F0', 'S1'])
param computerVisionSku string = 'F0'

@description('Storage account SKU for the Function App')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Azure Functions runtime version')
@allowed(['~4'])
param functionsVersion string = '~4'

@description('Python runtime version for Azure Functions')
@allowed(['3.9', '3.10', '3.11'])
param pythonVersion string = '3.11'

@description('Tags to be applied to all resources')
param resourceTags object = {
  Project: 'ImageAnalysis'
  Environment: environment
  Purpose: 'Recipe'
  'Cost-Center': 'Engineering'
}

// ============================================================================
// VARIABLES
// ============================================================================

// Resource naming following Azure best practices
var resourceNames = {
  computerVision: 'cv-${projectName}-${environment}-${uniqueSuffix}'
  storageAccount: 'sa${replace(projectName, '-', '')}${environment}${uniqueSuffix}'
  functionApp: 'func-${projectName}-${environment}-${uniqueSuffix}'
  appServicePlan: 'asp-${projectName}-${environment}-${uniqueSuffix}'
  applicationInsights: 'appi-${projectName}-${environment}-${uniqueSuffix}'
  logAnalyticsWorkspace: 'law-${projectName}-${environment}-${uniqueSuffix}'
}

// Application settings for the Function App
var functionAppSettings = [
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
    value: functionsVersion
  }
  {
    name: 'FUNCTIONS_WORKER_RUNTIME'
    value: 'python'
  }
  {
    name: 'WEBSITE_PYTHON_DEFAULT_VERSION'
    value: pythonVersion
  }
  {
    name: 'COMPUTER_VISION_ENDPOINT'
    value: computerVisionAccount.properties.endpoint
  }
  {
    name: 'COMPUTER_VISION_KEY'
    value: computerVisionAccount.listKeys().key1
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
    name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
    value: '~3'
  }
  {
    name: 'XDT_MicrosoftApplicationInsights_Mode'
    value: 'Recommended'
  }
  {
    name: 'WEBSITE_RUN_FROM_PACKAGE'
    value: '1'
  }
]

// ============================================================================
// RESOURCES
// ============================================================================

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: resourceTags
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
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for Azure Functions runtime
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: resourceTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
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
  }
}

// Azure Computer Vision Service (Cognitive Services)
resource computerVisionAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: resourceNames.computerVision
  location: location
  tags: resourceTags
  sku: {
    name: computerVisionSku
  }
  kind: 'ComputerVision'
  properties: {
    apiProperties: {}
    customSubDomainName: resourceNames.computerVision
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: false
  }
}

// App Service Plan for Azure Functions (Consumption Plan)
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: resourceNames.appServicePlan
  location: location
  tags: resourceTags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    computeMode: 'Dynamic'
    reserved: true // Required for Linux
  }
}

// Azure Function App
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: resourceNames.functionApp
  location: location
  tags: resourceTags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    reserved: true // Required for Linux
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    clientAffinityEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'Python|${pythonVersion}'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      appSettings: functionAppSettings
    }
  }
  dependsOn: [
    storageAccount
    computerVisionAccount
    applicationInsights
  ]
}

// Function App Configuration (separate resource for better dependency management)
resource functionAppConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: functionApp
  name: 'appsettings'
  properties: {
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${az.environment().suffixes.storage}'
    WEBSITE_CONTENTSHARE: toLower(resourceNames.functionApp)
    FUNCTIONS_EXTENSION_VERSION: functionsVersion
    FUNCTIONS_WORKER_RUNTIME: 'python'
    WEBSITE_PYTHON_DEFAULT_VERSION: pythonVersion
    COMPUTER_VISION_ENDPOINT: computerVisionAccount.properties.endpoint
    COMPUTER_VISION_KEY: computerVisionAccount.listKeys().key1
    APPINSIGHTS_INSTRUMENTATIONKEY: applicationInsights.properties.InstrumentationKey
    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
    ApplicationInsightsAgent_EXTENSION_VERSION: '~3'
    XDT_MicrosoftApplicationInsights_Mode: 'Recommended'
    WEBSITE_RUN_FROM_PACKAGE: '1'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The location where resources were deployed')
output location string = location

@description('The name of the Computer Vision service')
output computerVisionName string = computerVisionAccount.name

@description('The endpoint URL for the Computer Vision service')
output computerVisionEndpoint string = computerVisionAccount.properties.endpoint

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The URL for the image analysis endpoint')
output imageAnalysisEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/analyze'

@description('The URL for the health check endpoint')
output healthCheckEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/health'

@description('The name of the Application Insights instance')
output applicationInsightsName string = applicationInsights.name

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The Application Insights connection string')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The Computer Vision service key (secure)')
@secure()
output computerVisionKey string = computerVisionAccount.listKeys().key1

@description('Resource information for verification')
output resourceInfo object = {
  computerVision: {
    name: computerVisionAccount.name
    sku: computerVisionAccount.sku.name
    endpoint: computerVisionAccount.properties.endpoint
  }
  functionApp: {
    name: functionApp.name
    url: 'https://${functionApp.properties.defaultHostName}'
    runtime: 'Python ${pythonVersion}'
  }
  storage: {
    name: storageAccount.name
    sku: storageAccount.sku.name
  }
  monitoring: {
    applicationInsights: applicationInsights.name
    logAnalytics: logAnalyticsWorkspace.name
  }
}