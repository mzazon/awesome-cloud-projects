// ==============================================================================
// Satellite Imagery Analytics with Azure Orbital and AI Services
// Main Bicep Template
// ==============================================================================

@description('The primary Azure region for resource deployment')
param location string = resourceGroup().location

@description('Unique suffix for resource naming to ensure global uniqueness')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Environment designation for resource tagging and naming')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Administrator username for Synapse Analytics workspace')
param synapseAdminUsername string = 'synadmin'

@description('Administrator password for Synapse Analytics workspace')
@secure()
param synapseAdminPassword string

@description('Your IP address for firewall configuration (format: xxx.xxx.xxx.xxx)')
param clientIpAddress string

@description('Pricing tier for Azure AI Services')
@allowed(['S0', 'S1', 'S2'])
param aiServicesSku string = 'S0'

@description('Pricing tier for Azure Maps account')
@allowed(['S0', 'S1'])
param mapsSku string = 'S1'

@description('Performance level for Synapse SQL pool')
@allowed(['DW100c', 'DW200c', 'DW300c'])
param sqlPoolPerformanceLevel string = 'DW100c'

@description('Enable auto-pause for Synapse Spark pool')
param enableSparkAutoScale bool = true

@description('Common tags applied to all resources')
param tags object = {
  environment: environment
  project: 'orbital-analytics'
  purpose: 'satellite-data-processing'
  createdBy: 'bicep-template'
}

// ==============================================================================
// Variables
// ==============================================================================

var resourceNames = {
  storageAccount: 'storbitdata${resourceSuffix}'
  synapseWorkspace: 'syn-orbital-${resourceSuffix}'
  eventHubNamespace: 'eh-orbital-${resourceSuffix}'
  aiServicesAccount: 'ai-orbital-${resourceSuffix}'
  customVisionAccount: 'cv-orbital-${resourceSuffix}'
  mapsAccount: 'maps-orbital-${resourceSuffix}'
  cosmosAccount: 'cosmos-orbital-${resourceSuffix}'
  keyVault: 'kv-orbital-${resourceSuffix}'
  logAnalytics: 'log-orbital-${resourceSuffix}'
  applicationInsights: 'ai-insights-${resourceSuffix}'
}

var containerNames = [
  'raw-satellite-data'
  'processed-imagery'
  'ai-analysis-results'
  'synapse-fs'
]

var eventHubNames = [
  'satellite-imagery-stream'
  'satellite-telemetry-stream'
]

var cosmosContainers = [
  {
    name: 'ImageryMetadata'
    partitionKey: '/satelliteId'
    throughput: 400
  }
  {
    name: 'AIAnalysisResults'
    partitionKey: '/imageId'
    throughput: 400
  }
  {
    name: 'GeospatialIndex'
    partitionKey: '/gridCell'
    throughput: 400
  }
]

// ==============================================================================
// Data Lake Storage Gen2
// ==============================================================================

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
    isHnsEnabled: true // Enable hierarchical namespace for Data Lake Gen2
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
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
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
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

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for containerName in containerNames: {
  parent: blobServices
  name: containerName
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'satellite-data-analytics'
    }
  }
}]

// ==============================================================================
// Key Vault for Secure Credential Storage
// ==============================================================================

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
    enabledForDeployment: false
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ==============================================================================
// Event Hubs for Real-time Data Ingestion
// ==============================================================================

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2023-01-01-preview' = {
  name: resourceNames.eventHubNamespace
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    isAutoInflateEnabled: true
    maximumThroughputUnits: 10
    kafkaEnabled: true
  }
}

resource eventHubs 'Microsoft.EventHub/namespaces/eventhubs@2023-01-01-preview' = [for (eventHubName, index) in eventHubNames: {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: index == 0 ? 7 : 3 // 7 days for imagery, 3 for telemetry
    partitionCount: index == 0 ? 8 : 4 // 8 partitions for imagery, 4 for telemetry
    status: 'Active'
  }
}]

// ==============================================================================
// Log Analytics and Application Insights
// ==============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalytics
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// ==============================================================================
// Azure Synapse Analytics Workspace
// ==============================================================================

resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: resourceNames.synapseWorkspace
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: storageAccount.properties.primaryEndpoints.dfs
      filesystem: 'synapse-fs'
      resourceId: storageAccount.id
      createManagedPrivateEndpoint: false
    }
    sqlAdministratorLogin: synapseAdminUsername
    sqlAdministratorLoginPassword: synapseAdminPassword
    managedVirtualNetwork: 'default'
    managedVirtualNetworkSettings: {
      preventDataExfiltration: false
      linkedAccessCheckOnTargetResource: false
      allowedAadTenantIdsForLinking: []
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Firewall rule for client IP access
resource synapseFirewallRule 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = {
  parent: synapseWorkspace
  name: 'ClientIpRule'
  properties: {
    startIpAddress: clientIpAddress
    endIpAddress: clientIpAddress
  }
}

// Allow Azure services firewall rule
resource synapseFirewallRuleAzure 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = {
  parent: synapseWorkspace
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Apache Spark Pool for image processing
resource sparkPool 'Microsoft.Synapse/workspaces/bigDataPools@2021-06-01' = {
  parent: synapseWorkspace
  name: 'sparkpool01'
  location: location
  tags: tags
  properties: {
    sparkVersion: '3.3'
    nodeCount: 3
    nodeSizeFamily: 'MemoryOptimized'
    nodeSize: 'Medium'
    autoScale: {
      enabled: enableSparkAutoScale
      minNodeCount: 3
      maxNodeCount: 10
    }
    autoPause: {
      enabled: true
      delayInMinutes: 15
    }
    isComputeIsolationEnabled: false
    sessionLevelPackagesEnabled: true
    dynamicExecutorAllocation: {
      enabled: false
    }
    cacheSize: 0
  }
}

// SQL Pool for structured analytics
resource sqlPool 'Microsoft.Synapse/workspaces/sqlPools@2021-06-01' = {
  parent: synapseWorkspace
  name: 'sqlpool01'
  location: location
  tags: tags
  sku: {
    name: sqlPoolPerformanceLevel
  }
  properties: {
    createMode: 'Default'
    collation: 'SQL_Latin1_General_CP1_CI_AS'
  }
}

// ==============================================================================
// Azure AI Services
// ==============================================================================

resource aiServicesAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: resourceNames.aiServicesAccount
  location: location
  tags: tags
  sku: {
    name: aiServicesSku
  }
  kind: 'CognitiveServices'
  properties: {
    customSubDomainName: resourceNames.aiServicesAccount
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    disableLocalAuth: false
  }
}

// Custom Vision Training Resource
resource customVisionAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: resourceNames.customVisionAccount
  location: location
  tags: tags
  sku: {
    name: aiServicesSku
  }
  kind: 'CustomVision.Training'
  properties: {
    customSubDomainName: resourceNames.customVisionAccount
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    disableLocalAuth: false
  }
}

// ==============================================================================
// Azure Maps
// ==============================================================================

resource mapsAccount 'Microsoft.Maps/accounts@2023-06-01' = {
  name: resourceNames.mapsAccount
  location: 'global'
  tags: tags
  sku: {
    name: mapsSku
  }
  kind: 'Gen2'
  properties: {
    disableLocalAuth: false
  }
}

// ==============================================================================
// Azure Cosmos DB
// ==============================================================================

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: resourceNames.cosmosAccount
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: true
    enableMultipleWriteLocations: false
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 720
        backupStorageRedundancy: 'Local'
      }
    }
  }
}

// Cosmos DB Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-11-15' = {
  parent: cosmosAccount
  name: 'SatelliteAnalytics'
  properties: {
    resource: {
      id: 'SatelliteAnalytics'
    }
  }
}

// Cosmos DB Containers
resource cosmosContainersResource 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = [for container in cosmosContainers: {
  parent: cosmosDatabase
  name: container.name
  properties: {
    resource: {
      id: container.name
      partitionKey: {
        paths: [
          container.partitionKey
        ]
        kind: 'Hash'
      }
    }
    options: {
      throughput: container.throughput
    }
  }
}]

// ==============================================================================
// Role Assignments and Permissions
// ==============================================================================

// Synapse workspace managed identity access to storage
resource synapseStorageDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, synapseWorkspace.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: synapseWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Synapse workspace access to Key Vault
resource synapseKeyVaultAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, synapseWorkspace.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: synapseWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ==============================================================================
// Key Vault Secrets
// ==============================================================================

resource eventHubConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'EventHubConnection'
  properties: {
    value: listKeys(resourceId('Microsoft.EventHub/namespaces/authorizationRules', eventHubNamespace.name, 'RootManageSharedAccessKey'), '2023-01-01-preview').primaryConnectionString
  }
  dependsOn: [
    synapseKeyVaultAccess
  ]
}

resource aiServicesEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'AIServicesEndpoint'
  properties: {
    value: aiServicesAccount.properties.endpoint
  }
  dependsOn: [
    synapseKeyVaultAccess
  ]
}

resource aiServicesKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'AIServicesKey'
  properties: {
    value: aiServicesAccount.listKeys().key1
  }
  dependsOn: [
    synapseKeyVaultAccess
  ]
}

resource mapsKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'MapsSubscriptionKey'
  properties: {
    value: mapsAccount.listKeys().primaryKey
  }
  dependsOn: [
    synapseKeyVaultAccess
  ]
}

resource cosmosEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'CosmosEndpoint'
  properties: {
    value: cosmosAccount.properties.documentEndpoint
  }
  dependsOn: [
    synapseKeyVaultAccess
  ]
}

resource cosmosKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'CosmosKey'
  properties: {
    value: cosmosAccount.listKeys().primaryMasterKey
  }
  dependsOn: [
    synapseKeyVaultAccess
  ]
}

resource storageConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'StorageConnectionString'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
  }
  dependsOn: [
    synapseKeyVaultAccess
  ]
}

// ==============================================================================
// Outputs
// ==============================================================================

@description('Resource group name containing all resources')
output resourceGroupName string = resourceGroup().name

@description('Azure region where resources are deployed')
output location string = location

@description('Data Lake Storage account name for satellite data')
output storageAccountName string = storageAccount.name

@description('Data Lake Storage account primary endpoint')
output storageAccountEndpoint string = storageAccount.properties.primaryEndpoints.dfs

@description('Synapse Analytics workspace name')
output synapseWorkspaceName string = synapseWorkspace.name

@description('Synapse workspace web URL for development and monitoring')
output synapseWorkspaceUrl string = 'https://${synapseWorkspace.name}.dev.azuresynapse.net'

@description('Event Hubs namespace for real-time data ingestion')
output eventHubNamespace string = eventHubNamespace.name

@description('Azure AI Services account name for image analysis')
output aiServicesAccountName string = aiServicesAccount.name

@description('Azure AI Services endpoint URL')
output aiServicesEndpoint string = aiServicesAccount.properties.endpoint

@description('Custom Vision account name for satellite object detection')
output customVisionAccountName string = customVisionAccount.name

@description('Azure Maps account name for geospatial visualization')
output mapsAccountName string = mapsAccount.name

@description('Cosmos DB account name for metadata storage')
output cosmosAccountName string = cosmosAccount.name

@description('Cosmos DB endpoint for application connectivity')
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint

@description('Key Vault name containing all service credentials')
output keyVaultName string = keyVault.name

@description('Key Vault URI for secure credential access')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Log Analytics workspace ID for monitoring')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Application Insights instrumentation key for telemetry')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Connection information for Azure Orbital integration')
output orbitalIntegration object = {
  eventHubNamespace: eventHubNamespace.name
  imageryEventHub: eventHubs[0].name
  telemetryEventHub: eventHubs[1].name
  storageAccount: storageAccount.name
  rawDataContainer: containers[0].name
}

@description('Quick start commands for validation and testing')
output quickStartCommands object = {
  validateStorage: 'az storage container list --account-name ${storageAccount.name} --output table'
  validateSynapse: 'az synapse workspace show --name ${synapseWorkspace.name} --resource-group ${resourceGroup().name} --output table'
  validateEventHubs: 'az eventhubs eventhub list --namespace-name ${eventHubNamespace.name} --resource-group ${resourceGroup().name} --output table'
  validateAI: 'az cognitiveservices account show --name ${aiServicesAccount.name} --resource-group ${resourceGroup().name} --output table'
  validateCosmos: 'az cosmosdb sql container list --account-name ${cosmosAccount.name} --resource-group ${resourceGroup().name} --database-name SatelliteAnalytics --output table'
}