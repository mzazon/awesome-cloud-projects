// ===================================================================================================
// Simple File Compression with Functions and Storage - Bicep Template
// ===================================================================================================
// This template deploys a serverless file compression solution using Azure Functions and Blob Storage
// with Event Grid integration for automatic file processing.

targetScope = 'resourceGroup'

// ===================================================================================================
// PARAMETERS
// ===================================================================================================

@description('Environment prefix for resource naming (e.g., dev, test, prod)')
@maxLength(10)
param environmentPrefix string = 'recipe'

@description('Unique suffix for resource names to ensure global uniqueness')
@maxLength(6)
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Storage account SKU for blob storage and function app storage')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Storage account access tier for blob containers')
@allowed([
  'Hot'
  'Cool'
])
param storageAccountAccessTier string = 'Hot'

@description('Azure Functions runtime version')
@allowed([
  '~4'
  '~3'
])
param functionsVersion string = '~4'

@description('Python runtime version for Azure Functions')
@allowed([
  '3.9'
  '3.10'
  '3.11'
])
param pythonVersion string = '3.11'

@description('Application Insights workspace retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('Tags to apply to all resources')
param resourceTags object = {
  Environment: environmentPrefix
  Project: 'FileCompression'
  Recipe: 'simple-file-compression-functions-storage'
  CostCenter: 'Demo'
  Owner: 'DevOps'
}

// ===================================================================================================
// VARIABLES
// ===================================================================================================

var storageAccountName = 'compress${uniqueSuffix}'
var functionAppName = '${environmentPrefix}-file-compressor-${uniqueSuffix}'
var appServicePlanName = '${functionAppName}-plan'
var applicationInsightsName = '${functionAppName}-insights'
var logAnalyticsWorkspaceName = '${functionAppName}-logs'
var eventGridSystemTopicName = '${storageAccountName}-topic'
var eventGridSubscriptionName = 'blob-compression-subscription'

// Container names for input and output files
var inputContainerName = 'raw-files'
var outputContainerName = 'compressed-files'

// Function app configuration
var functionAppSettings = [
  {
    name: 'AzureWebJobsStorage'
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
  }
  {
    name: 'STORAGE_CONNECTION_STRING'
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
    value: functionsVersion
  }
  {
    name: 'WEBSITE_NODE_DEFAULT_VERSION'
    value: '~18'
  }
  {
    name: 'FUNCTIONS_WORKER_RUNTIME'
    value: 'python'
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
    name: 'WEBSITE_RUN_FROM_PACKAGE'
    value: '1'
  }
]

// ===================================================================================================
// RESOURCES
// ===================================================================================================

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for monitoring and telemetry
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  tags: resourceTags
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: logRetentionDays
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for blob storage and function app storage
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: storageAccountAccessTier
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
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

// Blob Service for the storage account
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
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
  }
}

// Input container for raw files
resource inputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: inputContainerName
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Input container for raw files to be compressed'
      recipe: 'simple-file-compression-functions-storage'
    }
  }
}

// Output container for compressed files
resource outputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: outputContainerName
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Output container for compressed files'
      recipe: 'simple-file-compression-functions-storage'
    }
  }
}

// App Service Plan for Azure Functions (Consumption plan)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
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
    reserved: true
  }
}

// Function App for file compression
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  tags: resourceTags
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'Python|${pythonVersion}'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      appSettings: functionAppSettings
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    containerSize: 1536
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Function App configuration for blob trigger settings
resource functionAppConfig 'Microsoft.Web/sites/config@2023-01-01' = {
  parent: functionApp
  name: 'web'
  properties: {
    numberOfWorkers: 1
    defaultDocuments: [
      'Default.htm'
      'Default.html'
      'index.html'
    ]
    netFrameworkVersion: 'v4.0'
    linuxFxVersion: 'Python|${pythonVersion}'
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
    }
    localMySqlEnabled: false
    managedServiceIdentityId: 563
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

// Event Grid System Topic for storage account events
resource eventGridSystemTopic 'Microsoft.EventGrid/systemTopics@2023-12-15-preview' = {
  name: eventGridSystemTopicName
  location: location
  tags: resourceTags
  properties: {
    source: storageAccount.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

// Event Grid Subscription to trigger function on blob creation
resource eventGridSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2023-12-15-preview' = {
  parent: eventGridSystemTopic
  name: eventGridSubscriptionName
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${functionApp.properties.defaultHostName}/runtime/webhooks/blobs?functionName=Host.Functions.BlobTrigger&code=${listKeys('${functionApp.id}/host/default', '2023-01-01').systemKeys.blobs_extension}'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/${inputContainerName}/'
      enableAdvancedFilteringOnArrays: true
    }
    labels: []
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
    deadLetterDestination: {
      endpointType: 'StorageBlob'
      properties: {
        resourceId: storageAccount.id
        blobContainerName: 'deadletter'
      }
    }
  }
  dependsOn: [
    inputContainer
    outputContainer
  ]
}

// Dead letter container for failed event processing
resource deadLetterContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'deadletter'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Dead letter container for failed event processing'
      recipe: 'simple-file-compression-functions-storage'
    }
  }
}

// Storage Blob Data Contributor role assignment for Function App
resource functionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(resourceGroup().id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ===================================================================================================
// OUTPUTS
// ===================================================================================================

@description('The name of the created resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the created storage account')
output storageAccountName string = storageAccount.name

@description('The name of the created Function App')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppHostName string = functionApp.properties.defaultHostName

@description('The URL of the Function App')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the input container for raw files')
output inputContainerName string = inputContainerName

@description('The name of the output container for compressed files')
output outputContainerName string = outputContainerName

@description('The name of the Event Grid system topic')
output eventGridSystemTopicName string = eventGridSystemTopic.name

@description('The name of the Event Grid subscription')
output eventGridSubscriptionName string = eventGridSubscription.name

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Storage account connection string for manual configuration')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('Primary storage account key')
output storageAccountKey string = storageAccount.listKeys().keys[0].value

@description('Storage account blob endpoint')
output storageAccountBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Function App system-assigned managed identity principal ID')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('Log Analytics workspace ID for monitoring queries')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Resource tags applied to all resources')
output appliedResourceTags object = resourceTags

@description('Deployment timestamp')
output deploymentTimestamp string = utcNow('yyyy-MM-dd HH:mm:ss UTC')