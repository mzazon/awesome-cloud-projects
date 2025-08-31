@description('The location where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Application name used for resource naming')
param applicationName string = 'configdemo'

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('App Service plan SKU')
@allowed(['F1', 'B1', 'B2', 'S1', 'S2', 'P1v2', 'P2v2'])
param appServicePlanSku string = 'F1'

@description('App Configuration SKU')
@allowed(['free', 'standard'])
param appConfigSku string = 'free'

@description('Configuration key-value pairs to set in App Configuration')
param configurationValues object = {
  'DemoApp:Settings:Title': 'Configuration Management Demo'
  'DemoApp:Settings:BackgroundColor': '#2563eb'
  'DemoApp:Settings:Message': 'Hello from Azure App Configuration!'
  'DemoApp:Settings:RefreshInterval': '30'
}

@description('Tags to apply to all resources')
param tags object = {
  environment: environment
  application: applicationName
  purpose: 'recipe-demo'
}

// Variables for resource names
var appConfigName = 'appconfig-${applicationName}-${environment}-${uniqueSuffix}'
var appServicePlanName = 'plan-${applicationName}-${environment}-${uniqueSuffix}'
var webAppName = 'webapp-${applicationName}-${environment}-${uniqueSuffix}'

// Azure App Configuration Store
resource appConfiguration 'Microsoft.AppConfiguration/configurationStores@2023-03-01' = {
  name: appConfigName
  location: location
  tags: tags
  sku: {
    name: appConfigSku
  }
  properties: {
    encryption: {
      keyVaultProperties: null
    }
    disableLocalAuth: false
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
  }
  identity: {
    type: 'None'
  }
}

// Add configuration key-value pairs to App Configuration
resource configurationKeyValues 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-03-01' = [for item in items(configurationValues): {
  parent: appConfiguration
  name: item.key
  properties: {
    value: item.value
    contentType: 'text/plain'
  }
}]

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
    tier: appServicePlanSku == 'F1' ? 'Free' : (appServicePlanSku == 'B1' || appServicePlanSku == 'B2' ? 'Basic' : 'Standard')
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true
    targetWorkerCount: 1
    targetWorkerSizeId: 0
  }
}

// Web App
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|8.0'
      alwaysOn: appServicePlanSku != 'F1' // alwaysOn not available for Free tier
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      webSocketsEnabled: false
      requestTracingEnabled: false
      httpLoggingEnabled: false
      detailedErrorLoggingEnabled: false
      use32BitWorkerProcess: appServicePlanSku == 'F1' // Free tier requires 32-bit
      appSettings: [
        {
          name: 'APP_CONFIG_ENDPOINT'
          value: appConfiguration.properties.endpoint
        }
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: environment == 'prod' ? 'Production' : 'Development'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
    }
    clientAffinityEnabled: false
  }
}

// Role assignment for Web App to access App Configuration
resource appConfigDataReaderRoleDefinition 'Microsoft.Authorization/roleDefinitions@2018-01-01-preview' existing = {
  scope: subscription()
  name: '516239f1-63e1-4d78-a4de-a74fb236a071' // App Configuration Data Reader role
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: appConfiguration
  name: guid(appConfiguration.id, webApp.id, appConfigDataReaderRoleDefinition.id)
  properties: {
    roleDefinitionId: appConfigDataReaderRoleDefinition.id
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Web App Configuration (additional settings that can be set after creation)
resource webAppConfig 'Microsoft.Web/sites/config@2023-01-01' = {
  parent: webApp
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
    netFrameworkVersion: 'v8.0'
    phpVersion: ''
    pythonVersion: ''
    nodeVersion: ''
    powerShellVersion: ''
    linuxFxVersion: 'DOTNETCORE|8.0'
    windowsFxVersion: ''
    requestTracingEnabled: false
    remoteDebuggingEnabled: false
    remoteDebuggingVersion: 'VS2019'
    httpLoggingEnabled: false
    acrUseManagedIdentityCreds: false
    logsDirectorySizeLimit: 35
    detailedErrorLoggingEnabled: false
    publishingUsername: '$${webAppName}'
    scmType: 'None'
    use32BitWorkerProcess: appServicePlanSku == 'F1'
    webSocketsEnabled: false
    alwaysOn: appServicePlanSku != 'F1'
    managedPipelineMode: 'Integrated'
    virtualApplications: [
      {
        virtualPath: '/'
        physicalPath: 'site\\wwwroot'
        preloadEnabled: appServicePlanSku != 'F1'
      }
    ]
    loadBalancing: 'LeastRequests'
    experiments: {
      rampUpRules: []
    }
    autoHealEnabled: false
    vnetRouteAllEnabled: false
    vnetPrivatePortsCount: 0
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
    functionAppScaleLimit: 0
    functionsRuntimeScaleMonitoringEnabled: false
    minimumElasticInstanceCount: 0
    azureStorageAccounts: {}
  }
}

// Outputs
@description('The name of the App Configuration store')
output appConfigurationName string = appConfiguration.name

@description('The endpoint URL of the App Configuration store')
output appConfigurationEndpoint string = appConfiguration.properties.endpoint

@description('The name of the App Service Plan')
output appServicePlanName string = appServicePlan.name

@description('The name of the Web App')
output webAppName string = webApp.name

@description('The default hostname of the Web App')
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'

@description('The principal ID of the Web App managed identity')
output webAppPrincipalId string = webApp.identity.principalId

@description('The resource group location')
output location string = location

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('Configuration values that were set in App Configuration')
output configurationKeys array = [for item in items(configurationValues): {
  key: item.key
  value: item.value
}]