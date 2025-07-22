@description('The location/region where resources will be deployed')
param location string = resourceGroup().location

@description('Base name for all resources')
param baseName string = 'bicep-eventgrid'

@description('Environment suffix for resource naming')
param environment string = 'demo'

@description('Tags to apply to all resources')
param tags object = {
  Purpose: 'recipe'
  Environment: environment
  Recipe: 'automating-infrastructure-deployments-with-azure-bicep-and-event-grid'
}

@description('Storage account name for Bicep templates')
param storageAccountName string = '${baseName}st${uniqueString(resourceGroup().id)}'

@description('Event Grid topic name')
param eventGridTopicName string = '${baseName}-topic-${uniqueString(resourceGroup().id)}'

@description('Container Registry name')
param containerRegistryName string = '${baseName}cr${uniqueString(resourceGroup().id)}'

@description('Key Vault name')
param keyVaultName string = '${baseName}-kv-${uniqueString(resourceGroup().id)}'

@description('Function App name')
param functionAppName string = '${baseName}-func-${uniqueString(resourceGroup().id)}'

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string = '${baseName}-log-${uniqueString(resourceGroup().id)}'

@description('Application Insights name')
param applicationInsightsName string = '${baseName}-ai-${uniqueString(resourceGroup().id)}'

@description('Current user object ID for Key Vault access')
param currentUserObjectId string

// Variables
var storageAccountNameSanitized = length(storageAccountName) > 24 ? substring(storageAccountName, 0, 24) : storageAccountName
var containerRegistryNameSanitized = length(containerRegistryName) > 50 ? substring(containerRegistryName, 0, 50) : containerRegistryName
var keyVaultNameSanitized = length(keyVaultName) > 24 ? substring(keyVaultName, 0, 24) : keyVaultName
var functionAppNameSanitized = length(functionAppName) > 60 ? substring(functionAppName, 0, 60) : functionAppName

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
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

// Application Insights for monitoring deployment activities
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
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

// Storage Account for hosting Bicep templates
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name: storageAccountNameSanitized
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
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

// Blob container for Bicep templates
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-04-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    versioning: {
      enabled: true
    }
  }
}

resource bicepTemplatesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = {
  parent: blobServices
  name: 'bicep-templates'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Bicep template storage for automated deployments'
    }
  }
}

// Event Grid Topic for deployment events
resource eventGridTopic 'Microsoft.EventGrid/topics@2024-06-01-preview' = {
  name: eventGridTopicName
  location: location
  tags: tags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
    dataResidencyBoundary: 'WithinGeopair'
    eventTypeInfo: {
      kind: 'inline'
      inlineEventTypes: {
        'Microsoft.EventGrid.CustomEvent': {
          description: 'Custom deployment events'
        }
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Container Registry for deployment runner images
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: containerRegistryNameSanitized
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
  }
}

// Key Vault for storing secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultNameSanitized
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    publicNetworkAccess: 'Enabled'
    accessPolicies: []
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Role assignment for current user to Key Vault
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, currentUserObjectId, 'Key Vault Administrator')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483') // Key Vault Administrator
    principalId: currentUserObjectId
    principalType: 'User'
  }
}

// Storage account for Function App
resource functionStorageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name: '${baseName}funcst${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'Storage'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// App Service Plan for Function App (Consumption)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${baseName}-asp-${uniqueString(resourceGroup().id)}'
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
    computeMode: 'Dynamic'
  }
}

// Function App for event processing
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppNameSanitized
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${functionStorageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${functionStorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${functionStorageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppNameSanitized)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
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
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'CONTAINER_REGISTRY_NAME'
          value: containerRegistry.name
        }
        {
          name: 'KEY_VAULT_URI'
          value: keyVault.properties.vaultUri
        }
        {
          name: 'EVENT_GRID_TOPIC_ENDPOINT'
          value: eventGridTopic.properties.endpoint
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      use32BitWorkerProcess: false
      netFrameworkVersion: 'v8.0'
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Role assignment for Function App to access storage account
resource functionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionApp.id, 'Storage Blob Data Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Function App to access Container Registry
resource functionAppAcrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(containerRegistry.id, functionApp.id, 'AcrPull')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Function App to access Key Vault
resource functionAppKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, functionApp.id, 'Key Vault Secrets User')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Function App to create Container Instances
resource functionAppContainerInstanceRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, functionApp.id, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Event Grid subscription to Function App
resource eventGridSubscription 'Microsoft.EventGrid/topics/eventSubscriptions@2024-06-01-preview' = {
  parent: eventGridTopic
  name: 'deployment-subscription'
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/DeploymentHandler'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      subjectBeginsWith: '/deployments/'
      includedEventTypes: [
        'Microsoft.EventGrid.CustomEvent'
      ]
    }
    retryPolicy: {
      maxDeliveryAttempts: 3
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
}

// Dead letter container for failed events
resource deadLetterContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = {
  parent: blobServices
  name: 'deadletter'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Dead letter queue for failed Event Grid events'
    }
  }
}

// Secret to store Event Grid access key
resource eventGridKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'EventGridKey'
  properties: {
    value: eventGridTopic.listKeys().key1
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
  dependsOn: [
    keyVaultRoleAssignment
  ]
}

// Secret to store Storage Account key
resource storageKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'StorageKey'
  properties: {
    value: storageAccount.listKeys().keys[0].value
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
  dependsOn: [
    keyVaultRoleAssignment
  ]
}

// Secret to store Container Registry credentials
resource acrUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'AcrUsername'
  properties: {
    value: containerRegistry.name
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
  dependsOn: [
    keyVaultRoleAssignment
  ]
}

resource acrPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'AcrPassword'
  properties: {
    value: containerRegistry.listCredentials().passwords[0].value
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
  dependsOn: [
    keyVaultRoleAssignment
  ]
}

// Outputs
@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Storage Account name for Bicep templates')
output storageAccountName string = storageAccount.name

@description('Bicep templates container name')
output bicepTemplatesContainerName string = bicepTemplatesContainer.name

@description('Event Grid topic name')
output eventGridTopicName string = eventGridTopic.name

@description('Event Grid topic endpoint')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('Container Registry name')
output containerRegistryName string = containerRegistry.name

@description('Container Registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App hostname')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Deployment instructions')
output deploymentInstructions object = {
  step1: 'Upload Bicep templates to the storage account container: ${bicepTemplatesContainer.name}'
  step2: 'Build and push container image to registry: ${containerRegistry.properties.loginServer}'
  step3: 'Deploy Function App code for event processing'
  step4: 'Test by publishing events to Event Grid topic: ${eventGridTopic.properties.endpoint}'
  step5: 'Monitor deployments via Application Insights: ${applicationInsights.name}'
}

@description('Sample event for testing')
output sampleEvent object = {
  id: 'test-001'
  eventType: 'Microsoft.EventGrid.CustomEvent'
  subject: '/deployments/test'
  eventTime: '2024-01-01T00:00:00.000Z'
  data: {
    templateName: 'storage-account'
    targetResourceGroup: resourceGroup().name
    parameters: {
      storageAccountName: 'sttest${uniqueString(resourceGroup().id)}'
    }
  }
}