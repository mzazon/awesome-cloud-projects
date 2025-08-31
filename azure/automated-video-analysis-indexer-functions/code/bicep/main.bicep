@description('Main Bicep template for Automated Video Analysis with Video Indexer and Functions')

// Parameters with comprehensive validation
@description('The Azure region where resources will be deployed')
@allowed([
  'eastus'
  'eastus2'
  'westus2'
  'westeurope'
  'northeurope'
  'southeastasia'
  'australiaeast'
])
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Project name for resource naming')
@minLength(3)
@maxLength(10)
param projectName string = 'vidanalysis'

@description('Video Indexer account pricing tier')
@allowed(['S0'])
param videoIndexerSku string = 'S0'

@description('Storage account replication type')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageReplication string = 'Standard_LRS'

@description('Function App runtime version')
@allowed(['~4'])
param functionsVersion string = '~4'

@description('Python runtime version for Functions')
@allowed(['3.11'])
param pythonVersion string = '3.11'

@description('Enable Application Insights for monitoring')
param enableAppInsights bool = true

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: projectName
  Purpose: 'video-analysis'
  CreatedBy: 'bicep-template'
}

// Variables for consistent naming
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var storageAccountName = 'sa${projectName}${uniqueSuffix}'
var functionAppName = 'func-${projectName}-${environment}-${uniqueSuffix}'
var videoIndexerAccountName = 'vi-${projectName}-${environment}-${uniqueSuffix}'
var appServicePlanName = 'asp-${projectName}-${environment}-${uniqueSuffix}'
var appInsightsName = 'ai-${projectName}-${environment}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-${projectName}-${environment}-${uniqueSuffix}'

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableAppInsights) {
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

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableAppInsights) {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableAppInsights ? logAnalyticsWorkspace.id : null
    RetentionInDays: 30
    DisableIpMasking: false
    DisableLocalAuth: false
  }
}

// Storage Account for video files and insights
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageReplication
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
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

// Blob Services for the storage account
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    versioning: {
      enabled: true
    }
    changeFeed: {
      enabled: false
    }
  }
}

// Container for video uploads
resource videosContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'videos'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'video-uploads'
      environment: environment
    }
  }
}

// Container for analysis results
resource insightsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'insights'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'analysis-results'
      environment: environment
    }
  }
}

// Azure AI Video Indexer Account
resource videoIndexerAccount 'Microsoft.VideoIndexer/accounts@2024-01-01' = {
  name: videoIndexerAccountName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    accountName: videoIndexerAccountName
    accountId: guid(resourceGroup().id, videoIndexerAccountName)
  }
}

// App Service Plan for Function App (Consumption Plan)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
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
    reserved: true // Linux hosting
  }
}

// Function App for video processing
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|${pythonVersion}'
      functionsRuntimeScaleMonitoringEnabled: true
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      appSettings: [
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
          value: functionsVersion
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'VIDEO_INDEXER_ACCOUNT_ID'
          value: videoIndexerAccount.properties.accountId
        }
        {
          name: 'VIDEO_INDEXER_ACCOUNT_NAME'
          value: videoIndexerAccount.name
        }
        {
          name: 'VIDEO_INDEXER_LOCATION'
          value: location
        }
        {
          name: 'VIDEO_INDEXER_RESOURCE_GROUP'
          value: resourceGroup().name
        }
        {
          name: 'SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableAppInsights ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableAppInsights ? applicationInsights.properties.ConnectionString : ''
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'WEBSITE_ENABLE_SYNC_UPDATE_SITE'
          value: 'true'
        }
        {
          name: 'PYTHON_ISOLATE_WORKER_DEPENDENCIES'
          value: '1'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

// RBAC role assignment for Function App to access Video Indexer
resource videoIndexerContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'VideoIndexerContributor')
  scope: videoIndexerAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC role assignment for Function App to access Storage Account
resource storageContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Account Key access for Function App (required for blob triggers)
resource storageAccountKeyOperatorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'StorageAccountKeyOperator')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '81a9662b-bebf-436f-a333-f67b29880f12') // Storage Account Key Operator Service Role
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs for verification and integration
@description('The name of the storage account created')
output storageAccountName string = storageAccount.name

@description('The primary endpoint of the storage account')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The name of the Function App created')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppDefaultHostName string = functionApp.properties.defaultHostName

@description('The name of the Video Indexer account created')
output videoIndexerAccountName string = videoIndexerAccount.name

@description('The account ID of the Video Indexer account')
output videoIndexerAccountId string = videoIndexerAccount.properties.accountId

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = enableAppInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = enableAppInsights ? applicationInsights.properties.ConnectionString : ''

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('The Azure region where resources are deployed')
output location string = location

@description('The videos container URL')
output videosContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}videos'

@description('The insights container URL')
output insightsContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}insights'

@description('Function App system-assigned managed identity principal ID')
output functionAppPrincipalId string = functionApp.identity.principalId