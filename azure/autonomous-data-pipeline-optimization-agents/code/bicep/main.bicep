// Azure Bicep template for Autonomous Data Pipeline Optimization with AI Agents
// This template creates a comprehensive solution for intelligent data pipeline automation

@description('The environment name. Will be used as a prefix for all resources.')
@minLength(3)
@maxLength(10)
param environmentName string = 'aiagents'

@description('The location for all resources.')
@allowed(['eastus', 'westus2', 'northeurope', 'uksouth'])
param location string = resourceGroup().location

@description('The name of the Azure AI Foundry Hub.')
@minLength(3)
@maxLength(50)
param aiFoundryHubName string = '${environmentName}-ai-hub-${uniqueString(resourceGroup().id)}'

@description('The name of the Azure AI Foundry Project.')
@minLength(3)
@maxLength(50)
param aiFoundryProjectName string = '${environmentName}-ai-project-${uniqueString(resourceGroup().id)}'

@description('The name of the Azure Data Factory.')
@minLength(3)
@maxLength(63)
param dataFactoryName string = '${environmentName}-adf-${uniqueString(resourceGroup().id)}'

@description('The name of the Azure Storage Account.')
@minLength(3)
@maxLength(24)
param storageAccountName string = '${environmentName}st${uniqueString(resourceGroup().id)}'

@description('The name of the Azure Key Vault.')
@minLength(3)
@maxLength(24)
param keyVaultName string = '${environmentName}-kv-${uniqueString(resourceGroup().id)}'

@description('The name of the Log Analytics workspace.')
@minLength(4)
@maxLength(63)
param logAnalyticsName string = '${environmentName}-la-${uniqueString(resourceGroup().id)}'

@description('The name of the Application Insights instance.')
@minLength(1)
@maxLength(255)
param applicationInsightsName string = '${environmentName}-ai-${uniqueString(resourceGroup().id)}'

@description('The name of the Event Grid Topic.')
@minLength(3)
@maxLength(128)
param eventGridTopicName string = '${environmentName}-eg-${uniqueString(resourceGroup().id)}'

@description('The name of the Azure AI Search service.')
@minLength(2)
@maxLength(60)
param aiSearchName string = '${environmentName}-search-${uniqueString(resourceGroup().id)}'

@description('The name of the Cosmos DB account.')
@minLength(3)
@maxLength(44)
param cosmosDbAccountName string = '${environmentName}-cosmos-${uniqueString(resourceGroup().id)}'

@description('The pricing tier for the Azure AI Search service.')
@allowed(['free', 'basic', 'standard', 'standard2', 'standard3', 'storage_optimized_l1', 'storage_optimized_l2'])
param aiSearchSku string = 'standard'

@description('The SKU for the Azure Data Factory.')
@allowed(['Standard', 'Premium'])
param dataFactorySku string = 'Standard'

@description('The name of the managed identity.')
@minLength(3)
@maxLength(128)
param managedIdentityName string = '${environmentName}-identity-${uniqueString(resourceGroup().id)}'

@description('Tags to be applied to all resources.')
param tags object = {
  environment: environmentName
  purpose: 'intelligent-pipeline-automation'
  solution: 'autonomous-data-pipeline-optimization'
  'deployment-date': utcNow('yyyy-MM-dd')
}

// Variables
var tenantId = subscription().tenantId
var subscriptionId = subscription().subscriptionId

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'pergb2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
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

// Managed Identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: true
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    isHnsEnabled: true
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

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    vaultUri: 'https://${keyVaultName}.vault.azure.net/'
    provisioningState: 'Succeeded'
    publicNetworkAccess: 'Enabled'
  }
}

// Azure AI Search
resource aiSearch 'Microsoft.Search/searchServices@2023-11-01' = {
  name: aiSearchName
  location: location
  tags: tags
  sku: {
    name: aiSearchSku
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    networkRuleSet: {
      ipRules: []
      bypass: 'AzurePortal'
    }
    disableLocalAuth: false
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
  }
}

// Cosmos DB Account
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: cosmosDbAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    publicNetworkAccess: 'Enabled'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    isVirtualNetworkFilterEnabled: false
    virtualNetworkRules: []
    disableKeyBasedMetadataWriteAccess: false
    enableFreeTier: false
    enableAnalyticalStorage: false
    analyticalStorageConfiguration: {
      schemaType: 'WellDefined'
    }
    databaseAccountOfferType: 'Standard'
    defaultIdentity: 'FirstPartyIdentity'
    networkAclBypass: 'None'
    disableLocalAuth: false
    enablePartitionMerge: false
    enableBurstCapacity: false
    minimalTlsVersion: 'Tls12'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
      maxIntervalInSeconds: 5
      maxStalenessPrefix: 100
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    cors: []
    capabilities: []
    ipRules: []
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Geo'
      }
    }
    networkAclBypassResourceIds: []
  }
}

// Cosmos DB Database
resource cosmosDbDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-11-15' = {
  parent: cosmosDbAccount
  name: 'AgentDatabase'
  properties: {
    resource: {
      id: 'AgentDatabase'
    }
  }
}

// Cosmos DB Container
resource cosmosDbContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = {
  parent: cosmosDbDatabase
  name: 'AgentData'
  properties: {
    resource: {
      id: 'AgentData'
      partitionKey: {
        paths: [
          '/agentId'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
    }
  }
}

// Azure AI Foundry Hub (Cognitive Services Account)
resource aiFoundryHub 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: aiFoundryHubName
  location: location
  tags: tags
  sku: {
    name: 'S0'
  }
  kind: 'AIServices'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
    customSubDomainName: aiFoundryHubName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    restore: false
    restrictOutboundNetworkAccess: false
    allowedFqdnList: []
    userOwnedStorage: [
      {
        resourceId: storageAccount.id
      }
    ]
    aiServicesResourceId: '${subscription().id}/resourceGroups/${resourceGroup().name}/providers/Microsoft.CognitiveServices/accounts/${aiFoundryHubName}'
  }
}

// Azure AI Foundry Project
resource aiFoundryProject 'Microsoft.CognitiveServices/accounts/projects@2023-10-01-preview' = {
  parent: aiFoundryHub
  name: aiFoundryProjectName
  properties: {
    description: 'AI Foundry Project for Autonomous Data Pipeline Optimization'
    friendlyName: aiFoundryProjectName
    aiServicesResourceId: aiFoundryHub.id
    storageAccountResourceId: storageAccount.id
    keyVaultResourceId: keyVault.id
    applicationInsightsResourceId: applicationInsights.id
    aiSearchResourceId: aiSearch.id
    cosmosDbResourceId: cosmosDbAccount.id
  }
}

// Azure Data Factory
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    encryption: {
      identity: {
        userAssignedIdentity: managedIdentity.id
      }
      keyVaultProperties: {
        keyVaultUri: keyVault.properties.vaultUri
        keyName: 'DataFactoryKey'
        keyVersion: ''
      }
    }
  }
}

// Event Grid Topic
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    dataResidencyBoundary: 'WithinGeopair'
  }
}

// Data Factory Diagnostic Settings
resource dataFactoryDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'DataFactoryDiagnostics'
  scope: dataFactory
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ActivityRuns'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'PipelineRuns'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'TriggerRuns'
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

// Storage Account Diagnostic Settings
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'StorageAccountDiagnostics'
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

// AI Search Diagnostic Settings
resource aiSearchDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'AISearchDiagnostics'
  scope: aiSearch
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'OperationLogs'
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

// Role Assignments
// Managed Identity as Storage Blob Data Contributor
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Managed Identity as Key Vault Secrets User
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentity.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Managed Identity as AI Search Service Contributor
resource aiSearchRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiSearch.id, managedIdentity.id, '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  scope: aiSearch
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Managed Identity as Cosmos DB Built-in Data Contributor
resource cosmosRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosDbAccount.id, managedIdentity.id, '00000000-0000-0000-0000-000000000002')
  scope: cosmosDbAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00000000-0000-0000-0000-000000000002')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Managed Identity as Event Grid Data Sender
resource eventGridRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, managedIdentity.id, 'd5a91429-5739-47e2-a06b-3470a27159e7')
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Managed Identity as Data Factory Contributor
resource dataFactoryRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataFactory.id, managedIdentity.id, '673868aa-7521-48a0-acc6-0f60742d39f5')
  scope: dataFactory
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '673868aa-7521-48a0-acc6-0f60742d39f5')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('The resource ID of the Azure AI Foundry Hub')
output aiFoundryHubId string = aiFoundryHub.id

@description('The resource ID of the Azure AI Foundry Project')
output aiFoundryProjectId string = aiFoundryProject.id

@description('The resource ID of the Azure Data Factory')
output dataFactoryId string = dataFactory.id

@description('The resource ID of the Storage Account')
output storageAccountId string = storageAccount.id

@description('The resource ID of the Key Vault')
output keyVaultId string = keyVault.id

@description('The resource ID of the Log Analytics Workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The resource ID of the Application Insights')
output applicationInsightsId string = applicationInsights.id

@description('The resource ID of the Event Grid Topic')
output eventGridTopicId string = eventGridTopic.id

@description('The resource ID of the AI Search Service')
output aiSearchId string = aiSearch.id

@description('The resource ID of the Cosmos DB Account')
output cosmosDbAccountId string = cosmosDbAccount.id

@description('The resource ID of the Managed Identity')
output managedIdentityId string = managedIdentity.id

@description('The principal ID of the Managed Identity')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('The client ID of the Managed Identity')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('The Azure AI Foundry Hub name')
output aiFoundryHubName string = aiFoundryHub.name

@description('The Azure AI Foundry Project name')
output aiFoundryProjectName string = aiFoundryProject.name

@description('The Azure Data Factory name')
output dataFactoryName string = dataFactory.name

@description('The Storage Account name')
output storageAccountName string = storageAccount.name

@description('The Key Vault name')
output keyVaultName string = keyVault.name

@description('The Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('The Event Grid Topic name')
output eventGridTopicName string = eventGridTopic.name

@description('The AI Search Service name')
output aiSearchName string = aiSearch.name

@description('The Cosmos DB Account name')
output cosmosDbAccountName string = cosmosDbAccount.name

@description('The Managed Identity name')
output managedIdentityName string = managedIdentity.name

@description('The Event Grid Topic endpoint')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('The Storage Account primary endpoint')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The AI Search Service URL')
output aiSearchServiceUrl string = 'https://${aiSearch.name}.search.windows.net'

@description('The Cosmos DB Account endpoint')
output cosmosDbAccountEndpoint string = cosmosDbAccount.properties.documentEndpoint

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The Log Analytics Workspace ID')
output logAnalyticsWorkspaceWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('The deployment location')
output deploymentLocation string = location

@description('The subscription ID')
output subscriptionId string = subscriptionId

@description('The tenant ID')
output tenantId string = tenantId