@description('Resource location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environmentName string = 'dev'

@description('Project name for resource naming')
param projectName string = 'infra-bot'

@description('Log Analytics workspace pricing tier')
@allowed(['PerGB2018', 'CapacityReservation'])
param logAnalyticsSkuName string = 'PerGB2018'

@description('Application Insights sampling percentage')
@minValue(0)
@maxValue(100)
param appInsightsSamplingPercentage int = 100

@description('Function App runtime stack')
@allowed(['python', 'node', 'dotnet'])
param functionAppRuntime string = 'python'

@description('Function App runtime version')
param functionAppRuntimeVersion string = '3.9'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Tags to apply to all resources')
param resourceTags object = {
  Purpose: 'infrastructure-chatbot'
  Environment: environmentName
  Project: projectName
}

// Variables for resource naming
var resourceGroupName = resourceGroup().name
var logAnalyticsWorkspaceName = 'law-${projectName}-${uniqueSuffix}'
var appInsightsName = 'ai-${projectName}-${uniqueSuffix}'
var storageAccountName = 'st${projectName}${uniqueSuffix}'
var functionAppName = 'func-${projectName}-${uniqueSuffix}'
var appServicePlanName = 'asp-${projectName}-${uniqueSuffix}'

// Log Analytics Workspace - Foundation for monitoring and logging
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: logAnalyticsSkuName
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 5
    }
  }
}

// Application Insights - Application performance monitoring
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    SamplingPercentage: appInsightsSamplingPercentage
    RetentionInDays: 30
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account - Required for Azure Functions
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
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

// App Service Plan - Consumption plan for serverless Azure Functions
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
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
    reserved: functionAppRuntime == 'python' ? true : false
  }
}

// Function App - Serverless compute for query processing
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  tags: resourceTags
  kind: functionAppRuntime == 'python' ? 'functionapp,linux' : 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
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
          value: '~18'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionAppRuntime
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
          name: 'LOG_ANALYTICS_WORKSPACE_ID'
          value: logAnalyticsWorkspace.properties.customerId
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: functionApp.identity.principalId
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
          'https://web.powerapps.com'
          'https://copilotstudio.microsoft.com'
        ]
        supportCredentials: false
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      netFrameworkVersion: functionAppRuntime == 'dotnet' ? 'v6.0' : null
      linuxFxVersion: functionAppRuntime == 'python' ? 'Python|${functionAppRuntimeVersion}' : null
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      httpLoggingEnabled: true
      logsDirectorySizeLimit: 35
      detailedErrorLoggingEnabled: true
      remoteDebuggingEnabled: false
      alwaysOn: false
    }
    httpsOnly: true
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Role Assignment - Grant Function App access to Log Analytics Workspace
resource logAnalyticsReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalyticsWorkspace.id, functionApp.id, 'Log Analytics Reader')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893') // Log Analytics Reader
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment - Grant Function App access to Monitor Metrics Reader
resource monitorReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'Monitoring Reader')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05') // Monitoring Reader
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Diagnostic Settings for Function App
resource functionAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'functionapp-diagnostics'
  scope: functionApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Diagnostic Settings for Storage Account
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'storage-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Outputs for use in Azure Copilot Studio configuration
@description('Resource group name')
output resourceGroupName string = resourceGroupName

@description('Log Analytics workspace ID for monitoring queries')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Application Insights instrumentation key')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('Application Insights connection string')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App default hostname')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('Function App principal ID for role assignments')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Function App endpoint for Azure Copilot Studio webhook')
output functionAppEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/QueryProcessor'

@description('App Service Plan name')
output appServicePlanName string = appServicePlan.name

@description('Function App managed identity object ID')
output functionAppIdentityObjectId string = functionApp.identity.principalId

@description('Configuration summary for Azure Copilot Studio setup')
output copilotStudioConfig object = {
  functionEndpoint: 'https://${functionApp.properties.defaultHostName}/api/QueryProcessor'
  workspaceId: logAnalyticsWorkspace.properties.customerId
  appInsightsKey: appInsights.properties.InstrumentationKey
  resourceGroupName: resourceGroupName
  location: location
}