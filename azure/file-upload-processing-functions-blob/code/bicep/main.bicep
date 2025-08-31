// ================================================================================================
// Azure File Upload Processing with Functions and Blob Storage - Main Bicep Template
// ================================================================================================
// This template deploys a serverless file processing solution using Azure Functions and Blob Storage
// that automatically processes uploaded files using event-driven triggers.

targetScope = 'resourceGroup'

// ================================================================================================
// PARAMETERS
// ================================================================================================

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Application name prefix for resource naming')
@minLength(2)
@maxLength(10)
param applicationName string = 'fileproc'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Storage account access tier')
@allowed(['Hot', 'Cool'])
param storageAccessTier string = 'Hot'

@description('Blob container name for file uploads')
@minLength(3)
@maxLength(63)
param blobContainerName string = 'uploads'

@description('Function App runtime stack')
@allowed(['node', 'dotnet', 'python', 'java', 'powershell'])
param functionAppRuntime string = 'node'

@description('Function App runtime version')
param functionAppRuntimeVersion string = '18'

@description('Function App hosting plan')
@allowed(['Consumption', 'Premium'])
param functionAppHostingPlan string = 'Consumption'

@description('Enable Application Insights monitoring')
param enableApplicationInsights bool = true

@description('Resource tags for cost tracking and governance')
param resourceTags object = {
  Environment: environment
  Application: applicationName
  Purpose: 'ServerlessFileProcessing'
  CostCenter: 'IT'
  Owner: 'DevOps'
}

@description('Blob container public access level')
@allowed(['None', 'Blob', 'Container'])
param blobContainerPublicAccess string = 'None'

// ================================================================================================
// VARIABLES
// ================================================================================================

// Generate unique suffix for resource names to avoid conflicts
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)

// Resource naming with consistent convention
var storageAccountName = replace('st${applicationName}${environment}${uniqueSuffix}', '-', '')
var functionAppName = 'func-${applicationName}-${environment}-${uniqueSuffix}'
var hostingPlanName = 'plan-${applicationName}-${environment}-${uniqueSuffix}'
var applicationInsightsName = 'appi-${applicationName}-${environment}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'log-${applicationName}-${environment}-${uniqueSuffix}'

// Function App settings configuration
var functionAppSettings = [
  {
    name: 'AzureWebJobsStorage'
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
  }
  {
    name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
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
    value: functionAppRuntime
  }
  {
    name: 'WEBSITE_NODE_DEFAULT_VERSION'
    value: functionAppRuntime == 'node' ? '~${functionAppRuntimeVersion}' : null
  }
  {
    name: 'STORAGE_CONNECTION_STRING'
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
  }
  {
    name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
    value: enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : null
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : null
  }
]

// ================================================================================================
// RESOURCES
// ================================================================================================

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableApplicationInsights) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for Function App monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for blob storage and function app backend
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: storageAccessTier
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: blobContainerPublicAccess != 'None'
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
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

// Blob Service configuration
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Blob Container for file uploads
resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: blobContainerName
  properties: {
    publicAccess: blobContainerPublicAccess
    metadata: {
      purpose: 'file-upload-processing'
      environment: environment
    }
  }
}

// App Service Plan for Function App (Consumption or Premium)
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: hostingPlanName
  location: location
  tags: resourceTags
  sku: {
    name: functionAppHostingPlan == 'Consumption' ? 'Y1' : 'EP1'
    tier: functionAppHostingPlan == 'Consumption' ? 'Dynamic' : 'ElasticPremium'
  }
  properties: {
    reserved: false
  }
}

// Function App for serverless file processing
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: resourceTags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    reserved: false
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      appSettings: [for setting in functionAppSettings: {
        name: setting.name
        value: setting.value != null ? setting.value : ''
      }]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
      netFrameworkVersion: functionAppRuntime == 'dotnet' ? 'v6.0' : null
      nodeVersion: functionAppRuntime == 'node' ? '~${functionAppRuntimeVersion}' : null
      pythonVersion: functionAppRuntime == 'python' ? '3.9' : null
      javaVersion: functionAppRuntime == 'java' ? '11' : null
      powerShellVersion: functionAppRuntime == 'powershell' ? '7.2' : null
    }
  }
  dependsOn: [
    storageAccount
    applicationInsights
  ]
}

// Storage Blob Data Contributor role assignment for Function App system identity
resource functionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ================================================================================================
// OUTPUTS
// ================================================================================================

@description('Resource group name where resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('Storage account name for blob storage')
output storageAccountName string = storageAccount.name

@description('Storage account primary endpoint for blob access')
output storageAccountBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Blob container name for file uploads')
output blobContainerName string = blobContainer.name

@description('Function App name for serverless processing')
output functionAppName string = functionApp.name

@description('Function App default hostname')
output functionAppDefaultHostname string = functionApp.properties.defaultHostName

@description('Function App resource ID')
output functionAppResourceId string = functionApp.id

@description('Function App system-assigned managed identity principal ID')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('Application Insights instrumentation key (if enabled)')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Application Insights connection string (if enabled)')
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('Log Analytics Workspace ID (if Application Insights enabled)')
output logAnalyticsWorkspaceId string = enableApplicationInsights ? logAnalyticsWorkspace.id : ''

@description('Storage connection string for application configuration')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('Deployment summary with key information')
output deploymentSummary object = {
  applicationName: applicationName
  environment: environment
  location: location
  storageAccount: storageAccount.name
  functionApp: functionApp.name
  blobContainer: blobContainer.name
  hostingPlan: functionAppHostingPlan
  monitoringEnabled: enableApplicationInsights
  deploymentTimestamp: utcNow()
}