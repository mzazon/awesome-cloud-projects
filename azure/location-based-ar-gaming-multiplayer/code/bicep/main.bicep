// ============================================================================
// Main Bicep template for Azure PlayFab and Spatial Anchors Gaming Platform
// ============================================================================

targetScope = 'resourceGroup'

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('PlayFab Title ID')
param playFabTitleId string

@description('PlayFab Secret Key')
@secure()
param playFabSecretKey string

@description('Function App runtime stack')
@allowed(['dotnet-isolated', 'dotnet', 'node', 'python'])
param functionRuntime string = 'dotnet-isolated'

@description('Function App plan SKU')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionPlanSku string = 'Y1'

@description('Storage account type')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountType string = 'Standard_LRS'

@description('Maximum players per location')
@minValue(1)
@maxValue(20)
param maxPlayersPerLocation int = 8

@description('Location radius in meters')
@minValue(10)
@maxValue(1000)
param locationRadius int = 100

@description('Enable Application Insights')
param enableApplicationInsights bool = true

@description('Tags to apply to all resources')
param resourceTags object = {
  Environment: environment
  Project: 'AR-Gaming'
  Recipe: 'PlayFab-SpatialAnchors'
  CreatedBy: 'Bicep'
}

// Variables
var uniqueId = toLower(resourceSuffix)
var storageAccountName = 'st${uniqueId}'
var functionAppName = 'func-ar-gaming-${uniqueId}'
var appServicePlanName = 'plan-ar-gaming-${uniqueId}'
var spatialAnchorsAccountName = 'sa-${uniqueId}'
var applicationInsightsName = 'ai-ar-gaming-${uniqueId}'
var logAnalyticsWorkspaceName = 'law-ar-gaming-${uniqueId}'
var eventGridTopicName = 'eg-spatial-events-${uniqueId}'
var keyVaultName = 'kv-ar-gaming-${uniqueId}'
var managedIdentityName = 'id-ar-gaming-${uniqueId}'

// User-assigned managed identity for secure access
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: resourceTags
}

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableApplicationInsights) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
  }
}

// Key Vault for secure storage of secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: false
    enabledForTemplateDeployment: false
    enabledForDiskEncryption: false
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Store PlayFab secret key in Key Vault
resource playFabSecretKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'PlayFabSecretKey'
  properties: {
    value: playFabSecretKey
    contentType: 'text/plain'
  }
}

// Storage Account for Function App and general storage
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Configure CORS for PlayFab integration
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: [
            'https://*.playfab.com'
          ]
          allowedMethods: [
            'GET'
            'POST'
            'PUT'
            'DELETE'
          ]
          allowedHeaders: [
            '*'
          ]
          exposedHeaders: [
            '*'
          ]
          maxAgeInSeconds: 3600
        }
      ]
    }
  }
}

// Azure Spatial Anchors Account
resource spatialAnchorsAccount 'Microsoft.MixedReality/spatialAnchorsAccounts@2021-01-01' = {
  name: spatialAnchorsAccountName
  location: location
  tags: resourceTags
  properties: {
    storageAccountName: storageAccount.name
  }
}

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: resourceTags
  sku: {
    name: functionPlanSku
  }
  properties: {
    reserved: false
  }
}

// Function App for AR Gaming backend
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: resourceTags
  kind: 'functionapp'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
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
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionRuntime
        }
        {
          name: 'PlayFabTitleId'
          value: playFabTitleId
        }
        {
          name: 'PlayFabSecretKey'
          value: '@Microsoft.KeyVault(SecretUri=${playFabSecretKeySecret.properties.secretUri})'
        }
        {
          name: 'SpatialAnchorsAccountId'
          value: spatialAnchorsAccount.properties.accountId
        }
        {
          name: 'SpatialAnchorsAccountDomain'
          value: spatialAnchorsAccount.properties.accountDomain
        }
        {
          name: 'SpatialAnchorsAccountKey'
          value: spatialAnchorsAccount.listKeys().primaryKey
        }
        {
          name: 'MaxPlayersPerLocation'
          value: string(maxPlayersPerLocation)
        }
        {
          name: 'LocationRadius'
          value: string(locationRadius)
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: managedIdentity.properties.clientId
        }
      ]
      netFrameworkVersion: 'v8.0'
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: [
          'https://*.playfab.com'
          'https://localhost:3000'
        ]
        supportCredentials: true
      }
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

// Event Grid Topic for spatial anchor events
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: resourceTags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
  }
}

// Event Grid Subscription for spatial anchor events
resource eventGridSubscription 'Microsoft.EventGrid/topics/eventSubscriptions@2023-12-15-preview' = {
  parent: eventGridTopic
  name: 'spatial-anchor-events'
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${functionApp.properties.defaultHostName}/api/ProcessSpatialEvent'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.MixedReality.SpatialAnchors.AnchorCreated'
        'Microsoft.MixedReality.SpatialAnchors.AnchorDeleted'
        'Microsoft.MixedReality.SpatialAnchors.AnchorUpdated'
      ]
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
  }
}

// RBAC assignments for managed identity
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentity.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource spatialAnchorsAccountReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(spatialAnchorsAccount.id, managedIdentity.id, 'Spatial Anchors Account Reader')
  scope: spatialAnchorsAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5d51204f-eb77-4b1c-b86a-2ec626c49413') // Spatial Anchors Account Reader
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource spatialAnchorsAccountOwnerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(spatialAnchorsAccount.id, managedIdentity.id, 'Spatial Anchors Account Owner')
  scope: spatialAnchorsAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '70bbe301-9835-447d-afdd-19eb3167307c') // Spatial Anchors Account Owner
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource eventGridDataSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, managedIdentity.id, 'EventGrid Data Sender')
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7') // EventGrid Data Sender
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output spatialAnchorsAccountId string = spatialAnchorsAccount.properties.accountId
output spatialAnchorsAccountDomain string = spatialAnchorsAccount.properties.accountDomain
output storageAccountName string = storageAccount.name
output keyVaultName string = keyVault.name
output eventGridTopicName string = eventGridTopic.name
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint
output managedIdentityClientId string = managedIdentity.properties.clientId
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
output resourceGroupName string = resourceGroup().name
output location string = location

// Unity client configuration output
output unityClientConfiguration object = {
  PlayFabSettings: {
    TitleId: playFabTitleId
  }
  SpatialAnchorsSettings: {
    AccountId: spatialAnchorsAccount.properties.accountId
    AccountDomain: spatialAnchorsAccount.properties.accountDomain
  }
  FunctionEndpoints: {
    BaseUrl: 'https://${functionApp.properties.defaultHostName}'
    CreateAnchor: 'https://${functionApp.properties.defaultHostName}/api/CreateAnchor'
    ConfigureLobby: 'https://${functionApp.properties.defaultHostName}/api/ConfigureLobby'
    ProcessSpatialEvent: 'https://${functionApp.properties.defaultHostName}/api/ProcessSpatialEvent'
  }
  EventGridSettings: {
    TopicEndpoint: eventGridTopic.properties.endpoint
  }
}