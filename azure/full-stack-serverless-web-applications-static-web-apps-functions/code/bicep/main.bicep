@description('The name of the Static Web App')
param staticWebAppName string = 'swa-fullstack-app'

@description('The name of the Storage Account')
param storageAccountName string = 'stfullstack${uniqueString(resourceGroup().id)}'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The GitHub repository URL')
param repositoryUrl string = ''

@description('The GitHub branch to deploy from')
param branch string = 'main'

@description('The GitHub token for authentication')
@secure()
param repositoryToken string = ''

@description('The location of the app source code')
param appLocation string = '/'

@description('The location of the API source code')
param apiLocation string = 'api'

@description('The location of the built app content')
param outputLocation string = 'build'

@description('The SKU for the Static Web App')
@allowed([
  'Free'
  'Standard'
])
param staticWebAppSku string = 'Free'

@description('The SKU for the Storage Account')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
  'Premium_ZRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'recipe'
  environment: 'demo'
  recipe: 'building-full-stack-serverless-web-applications'
}

// Storage Account for data persistence
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
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
    allowCrossTenantReplication: true
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

// Table Service for task storage
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

// Tasks table for storing task data
resource tasksTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  parent: tableService
  name: 'tasks'
  properties: {}
}

// Static Web App with integrated Azure Functions
resource staticWebApp 'Microsoft.Web/staticSites@2023-01-01' = {
  name: staticWebAppName
  location: location
  tags: tags
  sku: {
    name: staticWebAppSku
    tier: staticWebAppSku
  }
  properties: {
    repositoryUrl: repositoryUrl
    branch: branch
    repositoryToken: repositoryToken
    buildProperties: {
      appLocation: appLocation
      apiLocation: apiLocation
      outputLocation: outputLocation
    }
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    templateProperties: {
      templateRepositoryUrl: repositoryUrl
      owner: ''
      repositoryName: ''
      branch: branch
      description: 'Full-stack serverless web application with Azure Static Web Apps and Azure Functions'
    }
    contentDistributionEndpoint: ''
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Application settings for the Static Web App's Azure Functions
resource staticWebAppSettings 'Microsoft.Web/staticSites/config@2023-01-01' = {
  parent: staticWebApp
  name: 'appsettings'
  properties: {
    STORAGE_CONNECTION_STRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    NODE_VERSION: '18'
    FUNCTIONS_WORKER_RUNTIME: 'node'
    WEBSITE_NODE_DEFAULT_VERSION: '18'
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
  }
}

// Custom domain configuration (optional)
resource customDomain 'Microsoft.Web/staticSites/customDomains@2023-01-01' = if (!empty(repositoryUrl)) {
  parent: staticWebApp
  name: 'default'
  properties: {
    domainName: staticWebApp.properties.defaultHostname
    validationMethod: 'cname-delegation'
  }
}

// Basic auth configuration for staging slots
resource basicAuth 'Microsoft.Web/staticSites/basicAuth@2023-01-01' = {
  parent: staticWebApp
  name: 'default'
  properties: {
    applicableEnvironmentsMode: 'SpecifiedEnvironments'
    environments: [
      'staging'
    ]
    password: uniqueString(resourceGroup().id, staticWebApp.name)
    secretUrl: ''
    secretState: 'Password'
  }
}

// Function app configuration for better performance
resource functionAppConfig 'Microsoft.Web/staticSites/config@2023-01-01' = {
  parent: staticWebApp
  name: 'functionappsettings'
  properties: {
    'FUNCTIONS_EXTENSION_VERSION': '~4'
    'FUNCTIONS_WORKER_RUNTIME': 'node'
    'WEBSITE_NODE_DEFAULT_VERSION': '18'
    'WEBSITE_RUN_FROM_PACKAGE': '1'
    'WEBSITE_ENABLE_SYNC_UPDATE_SITE': 'true'
    'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING': 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    'WEBSITE_CONTENTSHARE': toLower(staticWebAppName)
    'AzureWebJobsStorage': 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
  }
}

// Outputs for reference and integration
@description('The name of the Static Web App')
output staticWebAppName string = staticWebApp.name

@description('The default hostname of the Static Web App')
output staticWebAppUrl string = 'https://${staticWebApp.properties.defaultHostname}'

@description('The default hostname without protocol')
output staticWebAppHostname string = staticWebApp.properties.defaultHostname

@description('The resource ID of the Static Web App')
output staticWebAppId string = staticWebApp.id

@description('The name of the Storage Account')
output storageAccountName string = storageAccount.name

@description('The primary endpoint of the Storage Account')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The resource ID of the Storage Account')
output storageAccountId string = storageAccount.id

@description('The connection string for the Storage Account')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('The table endpoint for the Storage Account')
output storageTableEndpoint string = storageAccount.properties.primaryEndpoints.table

@description('The tasks table name')
output tasksTableName string = tasksTable.name

@description('The repository URL used for deployment')
output repositoryUrl string = repositoryUrl

@description('The branch used for deployment')
output deploymentBranch string = branch

@description('The API key for the Static Web App')
output apiKey string = staticWebApp.listSecrets().properties.apiKey

@description('The resource group location')
output location string = location

@description('The resource group name')
output resourceGroupName string = resourceGroup().name