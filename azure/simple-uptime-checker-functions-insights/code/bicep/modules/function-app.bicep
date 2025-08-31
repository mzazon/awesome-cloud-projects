@description('Function App module for uptime checker')

@description('Name of the Function App')
param functionAppName string

@description('Azure region')
param location string = resourceGroup().location

@description('Storage account name for Function App')
param storageAccountName string

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Node.js runtime version')
param nodeVersion string = '18'

@description('Hosting plan resource ID')
param hostingPlanId string

@description('Websites to monitor')
param websitesToMonitor string

@description('Monitoring interval in minutes')
param monitoringIntervalMinutes int

@description('Function timeout in minutes')
param functionTimeoutMinutes int = 5

@description('Tags to apply')
param tags object = {}

// Storage account reference
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlanId
    httpsOnly: true
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
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
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~${nodeVersion}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'WEBSITES_TO_MONITOR'
          value: websitesToMonitor
        }
        {
          name: 'MONITORING_INTERVAL'
          value: string(monitoringIntervalMinutes)
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      nodeVersion: '~${nodeVersion}'
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
      netFrameworkVersion: 'v6.0'
      powerShellVersion: '~7'
      linuxFxVersion: ''
      requestTracingEnabled: true
      httpLoggingEnabled: true
      logsDirectorySizeLimit: 35
      detailedErrorLoggingEnabled: true
      remoteDebuggingEnabled: false
      azureStorageAccounts: {}
    }
  }
}

// Function App host configuration
resource hostConfig 'Microsoft.Web/sites/config@2023-01-01' = {
  parent: functionApp
  name: 'host'
  properties: {
    version: '2.0'
    functionTimeout: '00:0${functionTimeoutMinutes}:00'
    extensionBundle: {
      id: 'Microsoft.Azure.Functions.ExtensionBundle'
      version: '[3.*, 4.0.0)'
    }
    logging: {
      applicationInsights: {
        samplingSettings: {
          isEnabled: true
          maxTelemetryItemsPerSecond: 20
        }
      }
      logLevel: {
        default: 'Information'
      }
    }
    managedDependency: {
      enabled: true
    }
    functionAppScaleLimit: 200
    functions: []
  }
}

// Output
output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output functionAppIdentity object = functionApp.identity