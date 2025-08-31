/*
 * Azure Bicep Template for Simple Text Translation with Functions and Translator
 * 
 * This template deploys the complete infrastructure for a serverless text translation
 * API using Azure Functions and Azure AI Translator services.
 * 
 * Resources deployed:
 * - Azure AI Translator (Cognitive Services)
 * - Azure Storage Account (for Function App)
 * - Azure Function App with Consumption Plan
 * - Application Insights (for monitoring)
 * 
 * Author: Azure Recipe Generator
 * Version: 1.0
 */

// ============================================================================
// PARAMETERS
// ============================================================================

@description('The name prefix for all resources. Must be between 3-11 characters, lowercase letters and numbers only.')
@minLength(3)
@maxLength(11)
param namePrefix string = 'translate'

@description('Location for all resources.')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'centralus'
  'northcentralus'
  'southcentralus'
  'westcentralus'
  'canadacentral'
  'canadaeast'
  'brazilsouth'
  'northeurope'
  'westeurope'
  'uksouth'
  'ukwest'
  'francecentral'
  'germanywestcentral'
  'switzerlandnorth'
  'norwayeast'
  'australiaeast'
  'australiasoutheast'
  'southeastasia'
  'eastasia'
  'japaneast'
  'japanwest'
  'koreacentral'
  'southafricanorth'
  'uaenorth'
  'centralindia'
  'southindia'
  'westindia'
])
param location string = resourceGroup().location

@description('SKU for the Translator service.')
@allowed([
  'F0'   // Free tier: 2M characters/month
  'S1'   // Standard tier: Pay-as-you-go
])
param translatorSku string = 'F0'

@description('Runtime for the Function App.')
@allowed([
  'node'
  'dotnet'
  'java'
  'python'
  'powershell'
])
param functionAppRuntime string = 'node'

@description('Runtime version for the Function App.')
param functionAppRuntimeVersion string = '20'

@description('Functions version for the Function App.')
@allowed([
  '4'
])
param functionsVersion string = '4'

@description('Storage account type.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
])
param storageAccountType string = 'Standard_LRS'

@description('Environment tags to apply to all resources.')
param tags object = {
  Environment: 'Development'
  Project: 'TextTranslation'
  Recipe: 'simple-text-translation-functions-translator'
}

// ============================================================================
// VARIABLES
// ============================================================================

// Generate unique suffix for resource names
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)

// Resource names
var translatorName = '${namePrefix}-translator-${uniqueSuffix}'
var storageAccountName = '${namePrefix}stor${uniqueSuffix}'
var functionAppName = '${namePrefix}-func-${uniqueSuffix}'
var appInsightsName = '${namePrefix}-insights-${uniqueSuffix}'
var hostingPlanName = '${namePrefix}-plan-${uniqueSuffix}'

// Function App configuration
var functionAppSettings = [
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
    value: functionAppName
  }
  {
    name: 'FUNCTIONS_EXTENSION_VERSION'
    value: '~${functionsVersion}'
  }
  {
    name: 'FUNCTIONS_WORKER_RUNTIME'
    value: functionAppRuntime
  }
  {
    name: 'WEBSITE_NODE_DEFAULT_VERSION'
    value: '~${functionAppRuntimeVersion}'
  }
  {
    name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
    value: appInsights.properties.InstrumentationKey
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsights.properties.ConnectionString
  }
  {
    name: 'TRANSLATOR_ENDPOINT'
    value: translator.properties.endpoint
  }
  {
    name: 'TRANSLATOR_KEY'
    value: translator.listKeys().key1
  }
]

// ============================================================================
// RESOURCES
// ============================================================================

// Azure AI Translator (Cognitive Services)
resource translator 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: translatorName
  location: location
  tags: tags
  kind: 'TextTranslation'
  sku: {
    name: translatorSku
  }
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
    customSubDomainName: translatorName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    allowCrossTenantReplication: false
    defaultToOAuthAuthentication: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
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
      keySource: 'Microsoft.Storage'
    }
  }
}

// Application Insights for monitoring
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

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${namePrefix}-logs-${uniqueSuffix}'
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
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Consumption Plan for Function App
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    computeMode: 'Dynamic'
    reserved: false
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: functionAppSettings
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
  
  // Function App Configuration
  resource functionAppConfig 'config@2023-01-01' = {
    name: 'web'
    properties: {
      numberOfWorkers: 1
      defaultDocuments: []
      netFrameworkVersion: 'v6.0'
      requestTracingEnabled: false
      remoteDebuggingEnabled: false
      remoteDebuggingVersion: 'VS2019'
      httpLoggingEnabled: false
      logsDirectorySizeLimit: 35
      detailedErrorLoggingEnabled: false
      publishingUsername: '$${functionAppName}'
      appSettings: functionAppSettings
      metadata: [
        {
          name: 'CURRENT_STACK'
          value: functionAppRuntime
        }
      ]
      connectionStrings: []
      machineKey: {
        validation: 'HMACSHA256'
        validationKey: ''
        decryption: 'AES'
        decryptionKey: ''
      }
      handlerMappings: []
      documentRoot: ''
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
      ftpsState: 'FtpsOnly'
      preWarmedInstanceCount: 0
      functionAppScaleLimit: 200
      functionsRuntimeScaleMonitoringEnabled: false
      minimumElasticInstanceCount: 0
      azureStorageAccounts: {}
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('The resource group location.')
output location string = location

@description('The name of the Translator service.')
output translatorName string = translator.name

@description('The endpoint URL of the Translator service.')
output translatorEndpoint string = translator.properties.endpoint

@description('The name of the storage account.')
output storageAccountName string = storageAccount.name

@description('The name of the Function App.')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App.')
output functionAppDefaultHostName string = functionApp.properties.defaultHostName

@description('The URL of the Function App.')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the Application Insights instance.')
output applicationInsightsName string = appInsights.name

@description('The instrumentation key for Application Insights.')
output applicationInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('The connection string for Application Insights.')
output applicationInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Resource IDs for all created resources.')
output resourceIds object = {
  translator: translator.id
  storageAccount: storageAccount.id
  functionApp: functionApp.id
  appInsights: appInsights.id
  logAnalyticsWorkspace: logAnalyticsWorkspace.id
  hostingPlan: hostingPlan.id
}

@description('Configuration summary for the deployed resources.')
output deploymentSummary object = {
  translatorSku: translatorSku
  functionAppRuntime: functionAppRuntime
  functionAppRuntimeVersion: functionAppRuntimeVersion
  functionsVersion: functionsVersion
  storageAccountType: storageAccountType
  location: location
}