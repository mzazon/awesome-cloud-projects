@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Unique suffix for globally unique resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Project name for resource naming and tagging')
param projectName string = 'qr-generator'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageSkuName string = 'Standard_LRS'

@description('Function App plan SKU')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppSkuName string = 'Y1'

@description('Python runtime version for the Function App')
@allowed(['3.8', '3.9', '3.10', '3.11'])
param pythonVersion string = '3.11'

@description('Enable blob public access for QR code sharing')
param allowBlobPublicAccess bool = true

@description('Minimum TLS version for storage account')
@allowed(['TLS1_0', 'TLS1_1', 'TLS1_2'])
param minimumTlsVersion string = 'TLS1_2'

// Variables for resource naming
var storageAccountName = 'st${projectName}${uniqueSuffix}'
var functionAppName = 'func-${projectName}-${uniqueSuffix}'
var hostingPlanName = 'asp-${projectName}-${uniqueSuffix}'
var applicationInsightsName = 'appi-${projectName}-${uniqueSuffix}'
var blobContainerName = 'qr-codes'

// Common tags for all resources
var commonTags = {
  Environment: environment
  Project: projectName
  Purpose: 'QR Code Generator'
  ManagedBy: 'Bicep'
}

// Storage Account for QR code images and Function App storage
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
  sku: {
    name: storageSkuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: allowBlobPublicAccess
    allowSharedKeyAccess: true
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
    minimumTlsVersion: minimumTlsVersion
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
  }
}

// Blob Service Configuration
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'POST', 'PUT']
          allowedHeaders: ['*']
          exposedHeaders: ['*']
          maxAgeInSeconds: 3600
        }
      ]
    }
  }
}

// Container for QR code images with public blob access
resource qrCodesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: blobContainerName
  properties: {
    publicAccess: allowBlobPublicAccess ? 'Blob' : 'None'
    metadata: {
      description: 'Container for storing generated QR code images'
    }
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// App Service Plan (Consumption Plan for serverless)
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: hostingPlanName
  location: location
  tags: commonTags
  sku: {
    name: functionAppSkuName
    tier: functionAppSkuName == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  kind: 'functionapp'
  properties: {
    reserved: true // Linux
  }
}

// Function App for QR code generation
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: commonTags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    reserved: true
    isXenon: false
    hyperV: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'Python|${pythonVersion}'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

// Function App Configuration Settings
resource functionAppConfig 'Microsoft.Web/sites/config@2023-01-01' = {
  parent: functionApp
  name: 'appsettings'
  properties: {
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    WEBSITE_CONTENTSHARE: toLower(functionAppName)
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'python'
    APPINSIGHTS_INSTRUMENTATIONKEY: applicationInsights.properties.InstrumentationKey
    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
    STORAGE_CONNECTION_STRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    BLOB_CONTAINER_NAME: blobContainerName
    WEBSITE_RUN_FROM_PACKAGE: '1'
    ENABLE_ORYX_BUILD: 'true'
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    BUILD_FLAGS: 'UseExpressBuild'
    XDG_CACHE_HOME: '/tmp/.cache'
  }
}

// Storage Blob Data Contributor role assignment for Function App
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs for verification and integration
@description('The name of the created resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The name of the blob container for QR codes')
output blobContainerName string = blobContainerName

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The Function App hostname')
output functionAppHostName string = functionApp.properties.defaultHostName

@description('The QR code generation endpoint URL')
output qrGenerationEndpoint string = 'https://${functionApp.properties.defaultHostName}/api/generate-qr'

@description('The storage account primary endpoint for blobs')
output storageAccountBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Storage account connection string for external access')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('The Function App system-assigned managed identity principal ID')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('Resource deployment status and configuration summary')
output deploymentSummary object = {
  environment: environment
  location: location
  storageAccount: storageAccountName
  functionApp: functionAppName
  containerName: blobContainerName
  pythonVersion: pythonVersion
  planSku: functionAppSkuName
  publicBlobAccess: allowBlobPublicAccess
  httpsOnly: true
  managedIdentityEnabled: true
}