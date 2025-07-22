// =====================================================================================
// Azure Industrial Training Platform with Remote Rendering and Object Anchors
// =====================================================================================
// This Bicep template deploys a complete industrial training platform using:
// - Azure Remote Rendering for cloud-based 3D model rendering
// - Azure Spatial Anchors for persistent spatial positioning
// - Azure Object Anchors for real-world object alignment
// - Azure Storage for 3D models and training content
// - Azure AD application for authentication
// =====================================================================================

@description('The Azure region where all resources will be deployed')
param location string = resourceGroup().location

@description('A unique suffix for resource naming to avoid conflicts')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('The name prefix for all resources')
param namePrefix string = 'industrial-training'

@description('The environment type (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environmentType string = 'dev'

@description('The storage account tier for 3D models and training content')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('The access tier for storage account (Hot for frequently accessed content)')
@allowed(['Hot', 'Cool'])
param storageAccessTier string = 'Hot'

@description('Enable Azure AD authentication for the training platform')
param enableAzureAD bool = true

@description('The display name for the Azure AD application')
param azureADAppDisplayName string = 'Industrial Training Platform'

@description('Tags to apply to all resources')
param resourceTags object = {
  Purpose: 'Industrial Training'
  Environment: environmentType
  Project: 'Mixed Reality Training'
  Technology: 'Azure Remote Rendering'
}

// =====================================================================================
// VARIABLES
// =====================================================================================

var resourceNames = {
  storageAccount: 'st${namePrefix}${uniqueSuffix}'
  remoteRenderingAccount: 'arr-${namePrefix}-${uniqueSuffix}'
  spatialAnchorsAccount: 'sa-${namePrefix}-${uniqueSuffix}'
  objectAnchorsAccount: 'oa-${namePrefix}-${uniqueSuffix}'
  keyVault: 'kv-${namePrefix}-${uniqueSuffix}'
  applicationInsights: 'ai-${namePrefix}-${uniqueSuffix}'
  logAnalyticsWorkspace: 'log-${namePrefix}-${uniqueSuffix}'
}

var storageContainers = [
  {
    name: '3d-models'
    publicAccess: 'None'
  }
  {
    name: 'training-content'
    publicAccess: 'None'
  }
  {
    name: 'user-data'
    publicAccess: 'None'
  }
  {
    name: 'analytics'
    publicAccess: 'None'
  }
]

// =====================================================================================
// AZURE STORAGE ACCOUNT
// =====================================================================================

@description('Storage account for 3D models, training content, and user data')
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
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
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
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

@description('Blob services configuration for the storage account')
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
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
      enabled: true
    }
  }
}

@description('Storage containers for organizing training platform content')
resource storageContainers_resource 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for container in storageContainers: {
  parent: blobServices
  name: container.name
  properties: {
    publicAccess: container.publicAccess
    metadata: {
      purpose: 'Industrial training content'
      environment: environmentType
    }
  }
}]

// =====================================================================================
// AZURE REMOTE RENDERING ACCOUNT
// =====================================================================================

@description('Azure Remote Rendering account for cloud-based 3D model rendering')
resource remoteRenderingAccount 'Microsoft.MixedReality/remoteRenderingAccounts@2021-03-01-preview' = {
  name: resourceNames.remoteRenderingAccount
  location: location
  tags: resourceTags
  properties: {
    storageAccountName: storageAccount.name
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// =====================================================================================
// AZURE SPATIAL ANCHORS ACCOUNT
// =====================================================================================

@description('Azure Spatial Anchors account for persistent spatial positioning')
resource spatialAnchorsAccount 'Microsoft.MixedReality/spatialAnchorsAccounts@2021-03-01-preview' = {
  name: resourceNames.spatialAnchorsAccount
  location: location
  tags: resourceTags
  properties: {}
  identity: {
    type: 'SystemAssigned'
  }
}

// =====================================================================================
// AZURE OBJECT ANCHORS ACCOUNT
// =====================================================================================

@description('Azure Object Anchors account for real-world object alignment')
resource objectAnchorsAccount 'Microsoft.MixedReality/objectAnchorsAccounts@2021-03-01-preview' = {
  name: resourceNames.objectAnchorsAccount
  location: location
  tags: resourceTags
  properties: {}
  identity: {
    type: 'SystemAssigned'
  }
}

// =====================================================================================
// LOG ANALYTICS WORKSPACE
// =====================================================================================

@description('Log Analytics workspace for monitoring and analytics')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: resourceTags
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

// =====================================================================================
// APPLICATION INSIGHTS
// =====================================================================================

@description('Application Insights for application monitoring and telemetry')
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =====================================================================================
// KEY VAULT
// =====================================================================================

@description('Key Vault for storing sensitive configuration and secrets')
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: resourceTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableRbacAuthorization: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// =====================================================================================
// ROLE ASSIGNMENTS
// =====================================================================================

@description('Storage Blob Data Contributor role assignment for Remote Rendering')
resource storageRoleAssignmentRemoteRendering 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, remoteRenderingAccount.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    principalId: remoteRenderingAccount.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  }
}

// =====================================================================================
// KEY VAULT SECRETS
// =====================================================================================

@description('Storage account connection string secret')
resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'StorageConnectionString'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

@description('Remote Rendering account key secret')
resource remoteRenderingKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'RemoteRenderingAccountKey'
  properties: {
    value: remoteRenderingAccount.listKeys().primaryKey
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

@description('Spatial Anchors account key secret')
resource spatialAnchorsKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'SpatialAnchorsAccountKey'
  properties: {
    value: spatialAnchorsAccount.listKeys().primaryKey
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

@description('Object Anchors account key secret')
resource objectAnchorsKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ObjectAnchorsAccountKey'
  properties: {
    value: objectAnchorsAccount.listKeys().primaryKey
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

@description('Application Insights instrumentation key secret')
resource applicationInsightsKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ApplicationInsightsInstrumentationKey'
  properties: {
    value: applicationInsights.properties.InstrumentationKey
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// =====================================================================================
// AZURE AD APPLICATION (Conditional)
// =====================================================================================

@description('Azure AD application for authentication (if enabled)')
resource azureADApplication 'Microsoft.Graph/applications@v1.0' = if (enableAzureAD) {
  displayName: azureADAppDisplayName
  signInAudience: 'AzureADMyOrg'
  requiredResourceAccess: [
    {
      resourceAppId: '00000003-0000-0000-c000-000000000000'
      resourceAccess: [
        {
          id: '14dad69e-099b-42c9-810b-d002981feec1'
          type: 'Role'
        }
      ]
    }
  ]
  web: {
    redirectUris: [
      'ms-appx-web://microsoft.aad.brokerplugin/${guid()}'
    ]
    implicitGrantSettings: {
      enableIdTokenIssuance: true
    }
  }
}

// =====================================================================================
// OUTPUTS
// =====================================================================================

@description('The name of the created resource group')
output resourceGroupName string = resourceGroup().name

@description('The location where resources were deployed')
output location string = location

@description('Storage account configuration')
output storageAccount object = {
  name: storageAccount.name
  id: storageAccount.id
  primaryEndpoints: storageAccount.properties.primaryEndpoints
  containers: [for container in storageContainers: container.name]
}

@description('Azure Remote Rendering account configuration')
output remoteRenderingAccount object = {
  name: remoteRenderingAccount.name
  id: remoteRenderingAccount.id
  accountId: remoteRenderingAccount.properties.accountId
  accountDomain: remoteRenderingAccount.properties.accountDomain
}

@description('Azure Spatial Anchors account configuration')
output spatialAnchorsAccount object = {
  name: spatialAnchorsAccount.name
  id: spatialAnchorsAccount.id
  accountId: spatialAnchorsAccount.properties.accountId
  accountDomain: spatialAnchorsAccount.properties.accountDomain
}

@description('Azure Object Anchors account configuration')
output objectAnchorsAccount object = {
  name: objectAnchorsAccount.name
  id: objectAnchorsAccount.id
  accountId: objectAnchorsAccount.properties.accountId
  accountDomain: objectAnchorsAccount.properties.accountDomain
}

@description('Key Vault configuration')
output keyVault object = {
  name: keyVault.name
  id: keyVault.id
  vaultUri: keyVault.properties.vaultUri
}

@description('Application Insights configuration')
output applicationInsights object = {
  name: applicationInsights.name
  id: applicationInsights.id
  instrumentationKey: applicationInsights.properties.InstrumentationKey
  connectionString: applicationInsights.properties.ConnectionString
}

@description('Log Analytics workspace configuration')
output logAnalyticsWorkspace object = {
  name: logAnalyticsWorkspace.name
  id: logAnalyticsWorkspace.id
  customerId: logAnalyticsWorkspace.properties.customerId
}

@description('Azure AD application configuration (if enabled)')
output azureADApplication object = enableAzureAD ? {
  displayName: azureADApplication.displayName
  appId: azureADApplication.appId
  objectId: azureADApplication.id
} : {}

@description('Unity configuration settings for the training platform')
output unityConfiguration object = {
  azureServices: {
    remoteRendering: {
      accountId: remoteRenderingAccount.properties.accountId
      accountDomain: remoteRenderingAccount.properties.accountDomain
      serviceEndpoint: 'https://remoterendering.${location}.mixedreality.azure.com'
    }
    spatialAnchors: {
      accountId: spatialAnchorsAccount.properties.accountId
      accountDomain: spatialAnchorsAccount.properties.accountDomain
      serviceEndpoint: 'https://sts.${location}.mixedreality.azure.com'
    }
    objectAnchors: {
      accountId: objectAnchorsAccount.properties.accountId
      accountDomain: objectAnchorsAccount.properties.accountDomain
    }
    storage: {
      accountName: storageAccount.name
      modelsContainer: '3d-models'
      trainingContainer: 'training-content'
      userDataContainer: 'user-data'
      analyticsContainer: 'analytics'
    }
    keyVault: {
      vaultUri: keyVault.properties.vaultUri
    }
    applicationInsights: {
      connectionString: applicationInsights.properties.ConnectionString
    }
  }
  trainingPlatform: {
    sessionSettings: {
      maxConcurrentUsers: 10
      sessionTimeout: 3600
      renderingQuality: 'high'
      enableCollaboration: true
    }
    modelSettings: {
      lodLevels: ['high', 'medium', 'low']
      textureQuality: 'high'
      enablePhysics: true
      enableInteraction: true
    }
    spatialSettings: {
      anchorPersistence: true
      roomScale: true
      trackingAccuracy: 'high'
      enableWorldMapping: true
    }
  }
}

@description('Deployment summary and next steps')
output deploymentSummary object = {
  status: 'Complete'
  resourcesCreated: [
    'Azure Storage Account with containers for 3D models and training content'
    'Azure Remote Rendering account for cloud-based 3D rendering'
    'Azure Spatial Anchors account for persistent spatial positioning'
    'Azure Object Anchors account for real-world object alignment'
    'Key Vault for secure storage of service keys and configuration'
    'Application Insights for monitoring and telemetry'
    'Log Analytics workspace for centralized logging'
    enableAzureAD ? 'Azure AD application for authentication' : null
  ]
  nextSteps: [
    'Configure Unity project with the provided configuration settings'
    'Install Mixed Reality Toolkit (MRTK) 3.0 for HoloLens 2 development'
    'Upload 3D industrial models to the storage account containers'
    'Configure training scenarios and assessment criteria'
    'Set up HoloLens 2 devices for development and testing'
    'Implement spatial anchoring for equipment positioning'
    'Test remote rendering sessions with sample 3D models'
    'Deploy and validate the training platform on target devices'
  ]
  importantNotes: [
    'Azure Remote Rendering will be retired on September 30, 2025 - plan migration accordingly'
    'Ensure proper IAM permissions are configured for production deployments'
    'Monitor usage and costs for Remote Rendering sessions'
    'Implement proper error handling and retry logic in Unity applications'
    'Consider implementing user authentication and authorization for production use'
  ]
}