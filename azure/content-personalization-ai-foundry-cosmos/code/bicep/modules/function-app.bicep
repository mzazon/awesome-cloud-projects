@description('Azure Functions App module for personalization API and processing')

// Parameters
@description('Name of the Function App')
param functionAppName string

@description('Azure region for resource deployment')
param location string

@description('Resource ID of the App Service Plan')
param appServicePlanId string

@description('Storage Account connection string')
@secure()
param storageAccountConnectionString string

@description('Application Insights connection string')
@secure()
param applicationInsightsConnectionString string

@description('Cosmos DB connection string')
@secure()
param cosmosDbConnectionString string

@description('Azure OpenAI endpoint')
param openAiEndpoint string

@description('Azure OpenAI API key')
@secure()
param openAiApiKey string

@description('AI Foundry workspace name')
param aiFoundryWorkspaceName string

@description('Function App runtime configuration')
param runtimeConfig object

@description('Tags to apply to the resource')
param tags object = {}

@description('Enable Application Insights')
param enableApplicationInsights bool = true

@description('HTTPS only enforcement')
param httpsOnly bool = true

// Variables
var functionAppSettings = [
  {
    name: 'AzureWebJobsStorage'
    value: storageAccountConnectionString
  }
  {
    name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
    value: storageAccountConnectionString
  }
  {
    name: 'WEBSITE_CONTENTSHARE'
    value: toLower(functionAppName)
  }
  {
    name: 'FUNCTIONS_EXTENSION_VERSION'
    value: '~${runtimeConfig.functionsVersion}'
  }
  {
    name: 'FUNCTIONS_WORKER_RUNTIME'
    value: runtimeConfig.runtime
  }
  {
    name: 'WEBSITE_RUN_FROM_PACKAGE'
    value: '1'
  }
  {
    name: 'COSMOS_CONNECTION_STRING'
    value: cosmosDbConnectionString
  }
  {
    name: 'OPENAI_ENDPOINT'
    value: openAiEndpoint
  }
  {
    name: 'OPENAI_API_KEY'
    value: openAiApiKey
  }
  {
    name: 'AI_FOUNDRY_WORKSPACE'
    value: aiFoundryWorkspaceName
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: enableApplicationInsights ? applicationInsightsConnectionString : ''
  }
  {
    name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
    value: enableApplicationInsights ? split(applicationInsightsConnectionString, ';')[0] : ''
  }
  {
    name: 'WEBSITE_PYTHON_VERSION'
    value: runtimeConfig.runtimeVersion
  }
  {
    name: 'ENABLE_ORYX_BUILD'
    value: 'true'
  }
  {
    name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
    value: 'true'
  }
  {
    name: 'WEBSITE_USE_PLACEHOLDER_DOTNETISOLATED'
    value: '0'
  }
]

// Resources
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: httpsOnly
    reserved: true
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: '${upper(runtimeConfig.runtime)}|${runtimeConfig.runtimeVersion}'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      appSettings: functionAppSettings
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      powerShellVersion: ''
      netFrameworkVersion: ''
      remoteDebuggingEnabled: false
      publicNetworkAccess: 'Enabled'
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    containerSize: 1536
    dailyMemoryTimeQuota: 0
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
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
    defaultDocuments: []
    netFrameworkVersion: ''
    phpVersion: ''
    pythonVersion: ''
    nodeVersion: ''
    powerShellVersion: ''
    linuxFxVersion: '${upper(runtimeConfig.runtime)}|${runtimeConfig.runtimeVersion}'
    windowsFxVersion: ''
    requestTracingEnabled: false
    remoteDebuggingEnabled: false
    remoteDebuggingVersion: 'VS2019'
    httpLoggingEnabled: false
    acrUseManagedIdentityCreds: false
    logsDirectorySizeLimit: 35
    detailedErrorLoggingEnabled: false
    publishingUsername: '$${functionAppName}'
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
    managedServiceIdentityId: null
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
@description('Function App Resource ID')
output functionAppId string = functionApp.id

@description('Function App Name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Function App Principal ID for RBAC assignments')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('Function App Default Hostname')
output defaultHostName string = functionApp.properties.defaultHostName

@description('Function App Outbound IP Addresses')
output outboundIpAddresses string = functionApp.properties.outboundIpAddresses

@description('Function App Configuration Summary')
output functionConfig object = {
  name: functionApp.name
  runtime: runtimeConfig.runtime
  runtimeVersion: runtimeConfig.runtimeVersion
  functionsVersion: runtimeConfig.functionsVersion
  osType: runtimeConfig.osType
  httpsOnly: httpsOnly
  url: 'https://${functionApp.properties.defaultHostName}'
}