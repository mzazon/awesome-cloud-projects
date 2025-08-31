// =============================================================================
// Bicep template for Simple URL Shortener with Functions and Table Storage
// Deploys a complete serverless URL shortening service
// =============================================================================

@description('The location where resources will be deployed')
param location string = resourceGroup().location

@description('Base name for all resources (will have suffix appended)')
param baseName string = 'urlshortener'

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Function App plan SKU (Y1 for consumption)')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppPlanSku string = 'Y1'

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Table name for URL mappings')
param urlMappingsTableName string = 'urlmappings'

@description('Tags to apply to all resources')
param tags object = {
  Purpose: 'Recipe'
  Environment: environment
  Solution: 'URL-Shortener'
}

// =============================================================================
// Variables
// =============================================================================

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var storageAccountName = '${baseName}store${uniqueSuffix}'
var functionAppName = '${baseName}-func-${uniqueSuffix}'
var hostingPlanName = '${baseName}-plan-${uniqueSuffix}'
var applicationInsightsName = '${baseName}-insights-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${baseName}-logs-${uniqueSuffix}'

// =============================================================================
// Log Analytics Workspace (required for Application Insights)
// =============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableApplicationInsights) {
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

// =============================================================================
// Application Insights (for monitoring and diagnostics)
// =============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
  }
}

// =============================================================================
// Storage Account (for Function App and Table Storage)
// =============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
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
        table: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
  }
}

// =============================================================================
// Table Service (for URL mappings storage)
// =============================================================================

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

// =============================================================================
// URL Mappings Table
// =============================================================================

resource urlMappingsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: urlMappingsTableName
  properties: {}
}

// =============================================================================
// App Service Plan (Consumption Plan for serverless)
// =============================================================================

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  sku: {
    name: functionAppPlanSku
    tier: functionAppPlanSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  properties: {
    maximumElasticWorkerCount: functionAppPlanSku == 'Y1' ? null : 20
  }
}

// =============================================================================
// Function App
// =============================================================================

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
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
          value: '~20'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      functionAppScaleLimit: functionAppPlanSku == 'Y1' ? 200 : null
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

// =============================================================================
// Function App Configuration (additional settings)
// =============================================================================

resource functionAppConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'web'
  properties: {
    numberOfWorkers: 1
    defaultDocuments: [
      'Default.htm'
      'Default.html'
      'index.html'
    ]
    netFrameworkVersion: 'v6.0'
    requestTracingEnabled: false
    remoteDebuggingEnabled: false
    httpLoggingEnabled: false
    acrUseManagedIdentityCreds: false
    logsDirectorySizeLimit: 35
    detailedErrorLoggingEnabled: false
    publishingUsername: '$${functionAppName}'
    scmType: 'None'
    use32BitWorkerProcess: false
    webSocketsEnabled: false
    alwaysOn: functionAppPlanSku != 'Y1'
    managedPipelineMode: 'Integrated'
    virtualApplications: [
      {
        virtualPath: '/'
        physicalPath: 'site\\wwwroot'
        preloadEnabled: functionAppPlanSku != 'Y1'
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
    ftpsState: 'FtpsOnly'
    preWarmedInstanceCount: functionAppPlanSku != 'Y1' ? 1 : null
  }
}

// =============================================================================
// RBAC Assignment (Storage Table Data Contributor for Function App)
// =============================================================================

// Built-in role: Storage Table Data Contributor
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageTableDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppHostName string = functionApp.properties.defaultHostName

@description('The Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The name of the URL mappings table')
output urlMappingsTableName string = urlMappingsTable.name

@description('The Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('The Application Insights Connection String')
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('Storage account connection string for external access')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('Function App System Assigned Identity Principal ID')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('Sample API endpoints')
output apiEndpoints object = {
  shortenUrl: 'https://${functionApp.properties.defaultHostName}/api/shorten'
  redirectBase: 'https://${functionApp.properties.defaultHostName}/api/'
  example: 'POST to shorten endpoint with {"url": "https://example.com"}'
}