// ================================================================
// Azure Multi-Modal Content Generation Infrastructure
// ================================================================
// This template deploys a complete multi-modal content generation
// solution using Azure AI Foundry, Container Registry, Event Grid,
// and supporting services for orchestrated AI workflows.

targetScope = 'resourceGroup'

// ================================================================
// PARAMETERS
// ================================================================

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environmentName string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names (3-6 characters)')
@minLength(3)
@maxLength(6)
param uniqueSuffix string

@description('Tags to apply to all resources')
param tags object = {
  environment: environmentName
  workload: 'multi-modal-content'
  'managed-by': 'bicep'
}

@description('SKU for Azure Container Registry')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string = 'Premium'

@description('Enable system-assigned managed identity for resources')
param enableSystemManagedIdentity bool = true

@description('Event Grid topic schema type')
@allowed(['CloudEventSchemaV1_0', 'EventGridSchema'])
param eventGridSchemaType string = 'CloudEventSchemaV1_0'

@description('Function App runtime version')
@allowed(['3.9', '3.10', '3.11'])
param pythonVersion string = '3.9'

@description('AI Foundry compute instance type for model deployments')
@allowed(['Standard_DS3_v2', 'Standard_NC6s_v3', 'Standard_NC12s_v3', 'Standard_NC24s_v3'])
param computeInstanceType string = 'Standard_NC6s_v3'

@description('Enable Key Vault soft delete and purge protection')
param enableKeyVaultProtection bool = true

// ================================================================
// VARIABLES
// ================================================================

var resourceNames = {
  storageAccount: 'stcontent${uniqueSuffix}'
  keyVault: 'kv-content-${uniqueSuffix}'
  containerRegistry: 'acr${uniqueSuffix}'
  aiFoundryHub: 'aif-hub-${uniqueSuffix}'
  aiFoundryProject: 'aif-project-${uniqueSuffix}'
  eventGridTopic: 'egt-content-${uniqueSuffix}'
  functionApp: 'func-content-${uniqueSuffix}'
  appServicePlan: 'plan-content-${uniqueSuffix}'
  applicationInsights: 'ai-content-${uniqueSuffix}'
  logAnalyticsWorkspace: 'law-content-${uniqueSuffix}'
}

var contentTypes = [
  'text'
  'image'
  'audio'
  'video'
]

// ================================================================
// EXISTING RESOURCES
// ================================================================

// Get current user for Key Vault access policy
var currentUserId = 'current-user-object-id' // This should be passed as parameter in production

// ================================================================
// STORAGE RESOURCES
// ================================================================

@description('Storage account for content output and AI Foundry workspace')
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    dnsEndpointType: 'Standard'
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
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
    }
  }
}

@description('Blob containers for different content types')
resource blobContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for contentType in contentTypes: {
  name: '${storageAccount.name}/default/generated-${contentType}'
  properties: {
    publicAccess: 'None'
    metadata: {
      contentType: contentType
      purpose: 'ai-generated-content'
    }
  }
}]

// ================================================================
// SECURITY RESOURCES
// ================================================================

@description('Key Vault for secure configuration and secret management')
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: enableKeyVaultProtection
    enablePurgeProtection: enableKeyVaultProtection ? true : null
    softDeleteRetentionInDays: enableKeyVaultProtection ? 90 : null
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    publicNetworkAccess: 'Enabled'
  }
}

// ================================================================
// CONTAINER REGISTRY
// ================================================================

@description('Azure Container Registry for custom AI model containers')
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: resourceNames.containerRegistry
  location: location
  tags: tags
  sku: {
    name: acrSku
  }
  identity: enableSystemManagedIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    adminUserEnabled: false
    dataEndpointEnabled: false
    networkRuleBypassOptions: 'AzureServices'
    policies: {
      quarantinePolicy: {
        status: 'enabled'
      }
      trustPolicy: {
        status: 'enabled'
        type: 'Notary'
      }
      retentionPolicy: {
        status: 'enabled'
        days: 30
      }
      exportPolicy: {
        status: 'enabled'
      }
      azureADAuthenticationAsArmPolicy: {
        status: 'enabled'
      }
      softDeletePolicy: {
        retentionDays: 7
        status: 'enabled'
      }
    }
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
  }
}

// ================================================================
// MONITORING RESOURCES
// ================================================================

@description('Log Analytics Workspace for monitoring and diagnostics')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
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
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

@description('Application Insights for Function App monitoring')
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ================================================================
// AI FOUNDRY RESOURCES
// ================================================================

@description('Azure AI Foundry Hub for multi-modal AI orchestration')
resource aiFoundryHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: resourceNames.aiFoundryHub
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  kind: 'Hub'
  identity: enableSystemManagedIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    friendlyName: 'Multi-Modal Content Generation Hub'
    description: 'AI Foundry Hub for orchestrating multi-modal content generation workflows'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    containerRegistry: containerRegistry.id
    applicationInsights: applicationInsights.id
    hbiWorkspace: false
    publicNetworkAccess: 'Enabled'
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
    mlFlowTrackingUri: 'azureml://${location}.api.azureml.ms/mlflow/v1.0/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.MachineLearningServices/workspaces/${resourceNames.aiFoundryHub}'
  }
}

@description('Azure AI Foundry Project for content generation workflows')
resource aiFoundryProject 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: resourceNames.aiFoundryProject
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  kind: 'Project'
  identity: enableSystemManagedIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    friendlyName: 'Multi-Modal Content Generation Project'
    description: 'AI Foundry Project for developing and deploying content generation models'
    hubResourceId: aiFoundryHub.id
    hbiWorkspace: false
    publicNetworkAccess: 'Enabled'
  }
  dependsOn: [
    aiFoundryHub
  ]
}

// ================================================================
// EVENT GRID RESOURCES
// ================================================================

@description('Event Grid Topic for workflow orchestration')
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: resourceNames.eventGridTopic
  location: location
  tags: tags
  identity: enableSystemManagedIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    inputSchema: eventGridSchemaType
    publicNetworkAccess: 'Enabled'
    dataResidencyBoundary: 'WithinGeopair'
    eventTypeInfo: {
      kind: 'inline'
      inlineEventTypes: {
        'content.generation.requested': {
          description: 'Triggered when new content generation is requested'
          displayName: 'Content Generation Requested'
          documentationUrl: 'https://docs.microsoft.com/azure/event-grid/'
        }
        'content.generation.completed': {
          description: 'Triggered when content generation is completed'
          displayName: 'Content Generation Completed'
          documentationUrl: 'https://docs.microsoft.com/azure/event-grid/'
        }
        'content.generation.failed': {
          description: 'Triggered when content generation fails'
          displayName: 'Content Generation Failed'
          documentationUrl: 'https://docs.microsoft.com/azure/event-grid/'
        }
      }
    }
  }
}

// ================================================================
// FUNCTION APP RESOURCES
// ================================================================

@description('App Service Plan for Function App (Consumption Plan)')
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: resourceNames.appServicePlan
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  kind: 'functionapp'
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: true // Required for Linux
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
  }
}

@description('Function App for content generation workflow orchestration')
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: resourceNames.functionApp
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: enableSystemManagedIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true // Required for Linux
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
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
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
          value: toLower(resourceNames.functionApp)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
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
          name: 'AI_FOUNDRY_WORKSPACE_NAME'
          value: aiFoundryProject.name
        }
        {
          name: 'AI_FOUNDRY_RESOURCE_GROUP'
          value: resourceGroup().name
        }
        {
          name: 'AI_FOUNDRY_SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'KEY_VAULT_URL'
          value: keyVault.properties.vaultUri
        }
        {
          name: 'CONTAINER_REGISTRY_URL'
          value: containerRegistry.properties.loginServer
        }
        {
          name: 'EVENT_GRID_TOPIC_ENDPOINT'
          value: eventGridTopic.properties.endpoint
        }
      ]
    }
    httpsOnly: true
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
  dependsOn: [
    appServicePlan
    storageAccount
    applicationInsights
    keyVault
    aiFoundryProject
  ]
}

// ================================================================
// EVENT GRID SUBSCRIPTIONS
// ================================================================

@description('Event Grid subscription for Function App workflow triggering')
resource eventGridSubscription 'Microsoft.EventGrid/topics/eventSubscriptions@2023-12-15-preview' = {
  name: 'content-generation-subscription'
  parent: eventGridTopic
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/ContentGenerationOrchestrator'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'content.generation.requested'
      ]
      enableAdvancedFilteringOnArrays: true
    }
    labels: [
      'content-generation'
      'ai-workflow'
    ]
    eventDeliverySchema: eventGridSchemaType
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
    deadLetterDestination: {
      endpointType: 'StorageBlob'
      properties: {
        resourceId: storageAccount.id
        blobContainerName: 'dead-letter-events'
      }
    }
  }
}

// ================================================================
// RBAC ASSIGNMENTS
// ================================================================

// Function App permissions for AI Foundry
@description('Assign AzureML Data Scientist role to Function App for AI Foundry access')
resource functionAppAiFoundryRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableSystemManagedIdentity) {
  name: guid(resourceGroup().id, functionApp.id, 'AzureML Data Scientist')
  scope: aiFoundryProject
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f6c7c914-8db3-469d-8ca1-694a8f32e121') // AzureML Data Scientist
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Function App permissions for Storage Account
@description('Assign Storage Blob Data Contributor role to Function App')
resource functionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableSystemManagedIdentity) {
  name: guid(resourceGroup().id, functionApp.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Function App permissions for Key Vault
@description('Assign Key Vault Secrets User role to Function App')
resource functionAppKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableSystemManagedIdentity) {
  name: guid(resourceGroup().id, functionApp.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Function App permissions for Event Grid
@description('Assign EventGrid Data Sender role to Function App')
resource functionAppEventGridRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableSystemManagedIdentity) {
  name: guid(resourceGroup().id, functionApp.id, 'EventGrid Data Sender')
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7') // EventGrid Data Sender
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// AI Foundry Hub permissions for Container Registry
@description('Assign AcrPull role to AI Foundry Hub for container access')
resource aiFoundryAcrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableSystemManagedIdentity) {
  name: guid(resourceGroup().id, aiFoundryHub.id, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: aiFoundryHub.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ================================================================
// OUTPUTS
// ================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Storage account name and connection string')
output storageAccount object = {
  name: storageAccount.name
  connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
  primaryEndpoints: storageAccount.properties.primaryEndpoints
}

@description('Key Vault details')
output keyVault object = {
  name: keyVault.name
  uri: keyVault.properties.vaultUri
  resourceId: keyVault.id
}

@description('Azure Container Registry details')
output containerRegistry object = {
  name: containerRegistry.name
  loginServer: containerRegistry.properties.loginServer
  resourceId: containerRegistry.id
}

@description('Azure AI Foundry workspace details')
output aiFoundry object = {
  hubName: aiFoundryHub.name
  projectName: aiFoundryProject.name
  hubResourceId: aiFoundryHub.id
  projectResourceId: aiFoundryProject.id
  discoveryUrl: aiFoundryHub.properties.discoveryUrl
  mlFlowTrackingUri: aiFoundryHub.properties.mlFlowTrackingUri
}

@description('Event Grid topic details')
output eventGridTopic object = {
  name: eventGridTopic.name
  endpoint: eventGridTopic.properties.endpoint
  resourceId: eventGridTopic.id
}

@description('Function App details')
output functionApp object = {
  name: functionApp.name
  defaultHostName: functionApp.properties.defaultHostName
  resourceId: functionApp.id
  principalId: enableSystemManagedIdentity ? functionApp.identity.principalId : null
}

@description('Application Insights details')
output applicationInsights object = {
  name: applicationInsights.name
  instrumentationKey: applicationInsights.properties.InstrumentationKey
  connectionString: applicationInsights.properties.ConnectionString
}

@description('Log Analytics Workspace details')
output logAnalyticsWorkspace object = {
  name: logAnalyticsWorkspace.name
  customerId: logAnalyticsWorkspace.properties.customerId
  resourceId: logAnalyticsWorkspace.id
}

@description('Content container URLs for different media types')
output contentContainers object = {
  text: '${storageAccount.properties.primaryEndpoints.blob}generated-text'
  image: '${storageAccount.properties.primaryEndpoints.blob}generated-image'
  audio: '${storageAccount.properties.primaryEndpoints.blob}generated-audio'
  video: '${storageAccount.properties.primaryEndpoints.blob}generated-video'
}

@description('Next steps and configuration guidance')
output nextSteps array = [
  'Configure AI model deployments in Azure AI Foundry Project'
  'Deploy Function App code for content generation orchestration'
  'Build and push custom AI model containers to Azure Container Registry'
  'Test Event Grid workflow by publishing sample events'
  'Configure monitoring dashboards in Application Insights'
  'Set up content approval workflows and governance policies'
]