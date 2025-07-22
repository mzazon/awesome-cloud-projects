@description('Main Bicep template for Multi-Agent AI Orchestration with Azure AI Foundry Agent Service and Container Apps')

// Parameters
@description('The location/region where all resources will be deployed')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, staging, prod)')
param environmentName string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'multi-agent-orchestration'
  environment: environmentName
  solution: 'ai-foundry-container-apps'
}

@description('AI Foundry service pricing tier')
@allowed(['F0', 'S0', 'S1', 'S2', 'S3'])
param aiFoundryPricingTier string = 'S0'

@description('Storage account replication type')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageReplication string = 'Standard_LRS'

@description('Cosmos DB consistency level')
@allowed(['Eventual', 'Session', 'Strong', 'ConsistentPrefix', 'BoundedStaleness'])
param cosmosConsistencyLevel string = 'Session'

@description('Container Apps environment workload profile')
@allowed(['Consumption', 'Dedicated'])
param containerWorkloadProfile string = 'Consumption'

@description('Log Analytics workspace retention in days')
param logAnalyticsRetentionDays int = 30

@description('Enable Application Insights sampling')
param enableAppInsightsSampling bool = true

@description('Event Grid topic pricing tier')
@allowed(['Basic', 'Premium'])
param eventGridPricingTier string = 'Basic'

// Variables
var resourceNames = {
  aiFoundry: 'aif-orchestration-${uniqueSuffix}'
  containerEnvironment: 'cae-agents-${uniqueSuffix}'
  storageAccount: 'stagentstg${uniqueSuffix}'
  eventGridTopic: 'egt-agent-events-${uniqueSuffix}'
  cosmosAccount: 'cosmos-agents-${uniqueSuffix}'
  logAnalyticsWorkspace: 'law-agents-${uniqueSuffix}'
  appInsights: 'ai-agents-${uniqueSuffix}'
  keyVault: 'kv-agents-${uniqueSuffix}'
  containerRegistry: 'cracragents${uniqueSuffix}'
  mlWorkspace: 'mlw-agents-${uniqueSuffix}'
}

var containerApps = {
  coordinatorAgent: {
    name: 'coordinator-agent'
    image: 'mcr.microsoft.com/azure-cognitive-services/language/agent-coordinator:latest'
    port: 8080
    cpu: '1.0'
    memory: '2.0Gi'
    minReplicas: 1
    maxReplicas: 5
    ingress: 'external'
  }
  documentAgent: {
    name: 'document-agent'
    image: 'mcr.microsoft.com/azure-cognitive-services/document-intelligence/agent:latest'
    port: 8080
    cpu: '2.0'
    memory: '4.0Gi'
    minReplicas: 0
    maxReplicas: 10
    ingress: 'internal'
  }
  dataAnalysisAgent: {
    name: 'data-analysis-agent'
    image: 'mcr.microsoft.com/azure-cognitive-services/data-analysis/agent:latest'
    port: 8080
    cpu: '4.0'
    memory: '8.0Gi'
    minReplicas: 0
    maxReplicas: 8
    ingress: 'internal'
  }
  customerServiceAgent: {
    name: 'customer-service-agent'
    image: 'mcr.microsoft.com/azure-cognitive-services/language/customer-service-agent:latest'
    port: 8080
    cpu: '1.0'
    memory: '2.0Gi'
    minReplicas: 1
    maxReplicas: 15
    ingress: 'internal'
  }
  apiGateway: {
    name: 'api-gateway'
    image: 'mcr.microsoft.com/azure-api-management/gateway:latest'
    port: 8080
    cpu: '0.5'
    memory: '1.0Gi'
    minReplicas: 2
    maxReplicas: 10
    ingress: 'external'
  }
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.appInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    SamplingPercentage: enableAppInsightsSampling ? 10 : 100
    RetentionInDays: 90
  }
}

// Key Vault
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
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: resourceNames.containerRegistry
  location: location
  tags: tags
  sku: {
    name: 'Standard'
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
  }
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: storageReplication
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
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

// Storage Container for dead letter events
resource deadLetterContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storageAccount.name}/default/deadletter-events'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Cosmos DB Account
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: resourceNames.cosmosAccount
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    enableAutomaticFailover: true
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
      defaultConsistencyLevel: cosmosConsistencyLevel
      maxIntervalInSeconds: 86400
      maxStalenessPrefix: 1000000
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
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

// Cosmos DB SQL Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  name: 'agent-orchestration'
  parent: cosmosAccount
  properties: {
    resource: {
      id: 'agent-orchestration'
    }
  }
}

// Cosmos DB Container for agent state
resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  name: 'agent-state'
  parent: cosmosDatabase
  properties: {
    resource: {
      id: 'agent-state'
      partitionKey: {
        paths: ['/agentId']
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
            path: '/\"_etag\"/?'
          }
        ]
      }
      defaultTtl: 86400
    }
  }
}

// Azure AI Foundry Resource (Cognitive Services)
resource aiFoundryResource 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: resourceNames.aiFoundry
  location: location
  tags: tags
  sku: {
    name: aiFoundryPricingTier
  }
  kind: 'AIServices'
  properties: {
    apiProperties: {}
    customSubDomainName: resourceNames.aiFoundry
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// Machine Learning Workspace
resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: resourceNames.mlWorkspace
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'Multi-Agent AI Orchestration Workspace'
    description: 'Machine Learning workspace for multi-agent AI orchestration'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: appInsights.id
    containerRegistry: containerRegistry.id
    hbiWorkspace: false
    v1LegacyMode: false
    publicNetworkAccess: 'Enabled'
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
  }
}

// Event Grid Topic
resource eventGridTopic 'Microsoft.EventGrid/topics@2024-06-01-preview' = {
  name: resourceNames.eventGridTopic
  location: location
  tags: tags
  sku: {
    name: eventGridPricingTier
  }
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// Container Apps Environment
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: resourceNames.containerEnvironment
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
    kedaConfiguration: {}
    daprConfiguration: {}
    workloadProfiles: [
      {
        name: containerWorkloadProfile
        workloadProfileType: containerWorkloadProfile
      }
    ]
  }
}

// Managed Identity for Container Apps
resource containerAppsManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-container-apps-${uniqueSuffix}'
  location: location
  tags: tags
}

// Role Assignment for Container Apps to access AI Foundry
resource aiFoundryRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundryResource.id, containerAppsManagedIdentity.id, 'Cognitive Services User')
  scope: aiFoundryResource
  properties: {
    principalId: containerAppsManagedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908') // Cognitive Services User
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for Container Apps to access Event Grid
resource eventGridRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, containerAppsManagedIdentity.id, 'EventGrid Data Sender')
  scope: eventGridTopic
  properties: {
    principalId: containerAppsManagedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7') // EventGrid Data Sender
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for Container Apps to access Cosmos DB
resource cosmosRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosAccount.id, containerAppsManagedIdentity.id, 'DocumentDB Account Contributor')
  scope: cosmosAccount
  properties: {
    principalId: containerAppsManagedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5bd9cd88-fe45-4216-938b-f97437e15450') // DocumentDB Account Contributor
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for Container Apps to access Storage
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, containerAppsManagedIdentity.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    principalId: containerAppsManagedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalType: 'ServicePrincipal'
  }
}

// Container Apps
resource coordinatorAgent 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerApps.coordinatorAgent.name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${containerAppsManagedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: containerWorkloadProfile
    configuration: {
      ingress: {
        external: containerApps.coordinatorAgent.ingress == 'external'
        targetPort: containerApps.coordinatorAgent.port
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: containerAppsManagedIdentity.id
        }
      ]
      secrets: [
        {
          name: 'ai-foundry-key'
          value: aiFoundryResource.listKeys().key1
        }
        {
          name: 'event-grid-key'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'cosmos-connection-string'
          value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
        {
          name: 'storage-connection-string'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
      ]
    }
    template: {
      containers: [
        {
          image: containerApps.coordinatorAgent.image
          name: containerApps.coordinatorAgent.name
          resources: {
            cpu: json(containerApps.coordinatorAgent.cpu)
            memory: containerApps.coordinatorAgent.memory
          }
          env: [
            {
              name: 'AI_FOUNDRY_ENDPOINT'
              value: aiFoundryResource.properties.endpoint
            }
            {
              name: 'AI_FOUNDRY_KEY'
              secretRef: 'ai-foundry-key'
            }
            {
              name: 'EVENT_GRID_ENDPOINT'
              value: eventGridTopic.properties.endpoint
            }
            {
              name: 'EVENT_GRID_KEY'
              secretRef: 'event-grid-key'
            }
            {
              name: 'COSMOS_CONNECTION_STRING'
              secretRef: 'cosmos-connection-string'
            }
            {
              name: 'STORAGE_CONNECTION_STRING'
              secretRef: 'storage-connection-string'
            }
            {
              name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
              value: appInsights.properties.InstrumentationKey
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: containerApps.coordinatorAgent.port
                scheme: 'HTTP'
              }
              initialDelaySeconds: 30
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/ready'
                port: containerApps.coordinatorAgent.port
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 5
              timeoutSeconds: 3
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: containerApps.coordinatorAgent.minReplicas
        maxReplicas: containerApps.coordinatorAgent.maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    aiFoundryRoleAssignment
    eventGridRoleAssignment
    cosmosRoleAssignment
    storageRoleAssignment
  ]
}

resource documentAgent 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerApps.documentAgent.name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${containerAppsManagedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: containerWorkloadProfile
    configuration: {
      ingress: {
        external: containerApps.documentAgent.ingress == 'external'
        targetPort: containerApps.documentAgent.port
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: containerAppsManagedIdentity.id
        }
      ]
      secrets: [
        {
          name: 'ai-foundry-key'
          value: aiFoundryResource.listKeys().key1
        }
        {
          name: 'event-grid-key'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'storage-connection-string'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
      ]
    }
    template: {
      containers: [
        {
          image: containerApps.documentAgent.image
          name: containerApps.documentAgent.name
          resources: {
            cpu: json(containerApps.documentAgent.cpu)
            memory: containerApps.documentAgent.memory
          }
          env: [
            {
              name: 'AI_FOUNDRY_ENDPOINT'
              value: aiFoundryResource.properties.endpoint
            }
            {
              name: 'AI_FOUNDRY_KEY'
              secretRef: 'ai-foundry-key'
            }
            {
              name: 'EVENT_GRID_ENDPOINT'
              value: eventGridTopic.properties.endpoint
            }
            {
              name: 'EVENT_GRID_KEY'
              secretRef: 'event-grid-key'
            }
            {
              name: 'STORAGE_CONNECTION_STRING'
              secretRef: 'storage-connection-string'
            }
            {
              name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
              value: appInsights.properties.InstrumentationKey
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: containerApps.documentAgent.port
                scheme: 'HTTP'
              }
              initialDelaySeconds: 30
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: containerApps.documentAgent.minReplicas
        maxReplicas: containerApps.documentAgent.maxReplicas
        rules: [
          {
            name: 'event-grid-scaling'
            custom: {
              type: 'azure-eventhub'
              metadata: {
                consumerGroup: '$Default'
                unprocessedEventThreshold: '5'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    coordinatorAgent
  ]
}

resource dataAnalysisAgent 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerApps.dataAnalysisAgent.name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${containerAppsManagedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: containerWorkloadProfile
    configuration: {
      ingress: {
        external: containerApps.dataAnalysisAgent.ingress == 'external'
        targetPort: containerApps.dataAnalysisAgent.port
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: containerAppsManagedIdentity.id
        }
      ]
      secrets: [
        {
          name: 'ai-foundry-key'
          value: aiFoundryResource.listKeys().key1
        }
        {
          name: 'event-grid-key'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'cosmos-connection-string'
          value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
        {
          name: 'storage-connection-string'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
      ]
    }
    template: {
      containers: [
        {
          image: containerApps.dataAnalysisAgent.image
          name: containerApps.dataAnalysisAgent.name
          resources: {
            cpu: json(containerApps.dataAnalysisAgent.cpu)
            memory: containerApps.dataAnalysisAgent.memory
          }
          env: [
            {
              name: 'AI_FOUNDRY_ENDPOINT'
              value: aiFoundryResource.properties.endpoint
            }
            {
              name: 'AI_FOUNDRY_KEY'
              secretRef: 'ai-foundry-key'
            }
            {
              name: 'EVENT_GRID_ENDPOINT'
              value: eventGridTopic.properties.endpoint
            }
            {
              name: 'EVENT_GRID_KEY'
              secretRef: 'event-grid-key'
            }
            {
              name: 'COSMOS_CONNECTION_STRING'
              secretRef: 'cosmos-connection-string'
            }
            {
              name: 'STORAGE_CONNECTION_STRING'
              secretRef: 'storage-connection-string'
            }
            {
              name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
              value: appInsights.properties.InstrumentationKey
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: containerApps.dataAnalysisAgent.port
                scheme: 'HTTP'
              }
              initialDelaySeconds: 30
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: containerApps.dataAnalysisAgent.minReplicas
        maxReplicas: containerApps.dataAnalysisAgent.maxReplicas
        rules: [
          {
            name: 'cpu-scaling'
            custom: {
              type: 'cpu'
              metadata: {
                type: 'Utilization'
                value: '70'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    coordinatorAgent
  ]
}

resource customerServiceAgent 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerApps.customerServiceAgent.name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${containerAppsManagedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: containerWorkloadProfile
    configuration: {
      ingress: {
        external: containerApps.customerServiceAgent.ingress == 'external'
        targetPort: containerApps.customerServiceAgent.port
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: containerAppsManagedIdentity.id
        }
      ]
      secrets: [
        {
          name: 'ai-foundry-key'
          value: aiFoundryResource.listKeys().key1
        }
        {
          name: 'event-grid-key'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'cosmos-connection-string'
          value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
      ]
    }
    template: {
      containers: [
        {
          image: containerApps.customerServiceAgent.image
          name: containerApps.customerServiceAgent.name
          resources: {
            cpu: json(containerApps.customerServiceAgent.cpu)
            memory: containerApps.customerServiceAgent.memory
          }
          env: [
            {
              name: 'AI_FOUNDRY_ENDPOINT'
              value: aiFoundryResource.properties.endpoint
            }
            {
              name: 'AI_FOUNDRY_KEY'
              secretRef: 'ai-foundry-key'
            }
            {
              name: 'EVENT_GRID_ENDPOINT'
              value: eventGridTopic.properties.endpoint
            }
            {
              name: 'EVENT_GRID_KEY'
              secretRef: 'event-grid-key'
            }
            {
              name: 'COSMOS_CONNECTION_STRING'
              secretRef: 'cosmos-connection-string'
            }
            {
              name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
              value: appInsights.properties.InstrumentationKey
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: containerApps.customerServiceAgent.port
                scheme: 'HTTP'
              }
              initialDelaySeconds: 30
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: containerApps.customerServiceAgent.minReplicas
        maxReplicas: containerApps.customerServiceAgent.maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '15'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    coordinatorAgent
  ]
}

resource apiGateway 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerApps.apiGateway.name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${containerAppsManagedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: containerWorkloadProfile
    configuration: {
      ingress: {
        external: containerApps.apiGateway.ingress == 'external'
        targetPort: containerApps.apiGateway.port
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: containerAppsManagedIdentity.id
        }
      ]
      secrets: [
        {
          name: 'event-grid-key'
          value: eventGridTopic.listKeys().key1
        }
      ]
    }
    template: {
      containers: [
        {
          image: containerApps.apiGateway.image
          name: containerApps.apiGateway.name
          resources: {
            cpu: json(containerApps.apiGateway.cpu)
            memory: containerApps.apiGateway.memory
          }
          env: [
            {
              name: 'COORDINATOR_ENDPOINT'
              value: 'https://${coordinatorAgent.properties.configuration.ingress.fqdn}'
            }
            {
              name: 'EVENT_GRID_ENDPOINT'
              value: eventGridTopic.properties.endpoint
            }
            {
              name: 'EVENT_GRID_KEY'
              secretRef: 'event-grid-key'
            }
            {
              name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
              value: appInsights.properties.InstrumentationKey
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: containerApps.apiGateway.port
                scheme: 'HTTP'
              }
              initialDelaySeconds: 30
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: containerApps.apiGateway.minReplicas
        maxReplicas: containerApps.apiGateway.maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '20'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    coordinatorAgent
  ]
}

// Event Grid Subscriptions
resource workflowOrchestrationSubscription 'Microsoft.EventGrid/eventSubscriptions@2024-06-01-preview' = {
  name: 'workflow-orchestration'
  scope: eventGridTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${coordinatorAgent.properties.configuration.ingress.fqdn}/api/orchestration'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Workflow.Started'
        'Agent.Completed'
        'Agent.Failed'
      ]
      subjectBeginsWith: 'multi-agent'
    }
    labels: []
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
    deadLetterDestination: {
      endpointType: 'StorageBlob'
      properties: {
        resourceId: storageAccount.id
        blobContainerName: 'deadletter-events'
      }
    }
  }
  dependsOn: [
    coordinatorAgent
    deadLetterContainer
  ]
}

resource documentAgentSubscription 'Microsoft.EventGrid/eventSubscriptions@2024-06-01-preview' = {
  name: 'document-agent-subscription'
  scope: eventGridTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${documentAgent.properties.configuration.ingress.fqdn}/api/events'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'DocumentProcessing.Requested'
      ]
    }
    labels: []
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
  }
  dependsOn: [
    documentAgent
  ]
}

resource dataAnalysisSubscription 'Microsoft.EventGrid/eventSubscriptions@2024-06-01-preview' = {
  name: 'data-analysis-subscription'
  scope: eventGridTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${dataAnalysisAgent.properties.configuration.ingress.fqdn}/api/events'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'DataAnalysis.Requested'
        'DataProcessing.Completed'
      ]
    }
    labels: []
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
  }
  dependsOn: [
    dataAnalysisAgent
  ]
}

resource customerServiceSubscription 'Microsoft.EventGrid/eventSubscriptions@2024-06-01-preview' = {
  name: 'customer-service-subscription'
  scope: eventGridTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${customerServiceAgent.properties.configuration.ingress.fqdn}/api/events'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'CustomerService.Requested'
        'CustomerInquiry.Received'
      ]
    }
    labels: []
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
  }
  dependsOn: [
    customerServiceAgent
  ]
}

resource agentHealthMonitoringSubscription 'Microsoft.EventGrid/eventSubscriptions@2024-06-01-preview' = {
  name: 'agent-health-monitoring'
  scope: eventGridTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${coordinatorAgent.properties.configuration.ingress.fqdn}/api/health'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Agent.HealthCheck'
        'Agent.Error'
      ]
    }
    labels: []
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 5
      eventTimeToLiveInMinutes: 1440
    }
  }
  dependsOn: [
    coordinatorAgent
  ]
}

// Monitor Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-09-01-preview' = {
  name: 'ag-multi-agent-alerts'
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'AgentAlert'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    azureFunction: []
    armRoleReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    voiceReceivers: []
  }
}

// Alert Rules
resource agentResponseTimeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'agent-response-time-alert'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when agent response time exceeds 5 seconds'
    severity: 2
    enabled: true
    scopes: [
      coordinatorAgent.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ResponseTime'
          metricName: 'RequestDuration'
          operator: 'GreaterThan'
          threshold: 5000
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Output values
output resourceGroupName string = resourceGroup().name
output aiFoundryEndpoint string = aiFoundryResource.properties.endpoint
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint
output containerAppsEnvironmentName string = containerAppsEnvironment.name
output apiGatewayUrl string = 'https://${apiGateway.properties.configuration.ingress.fqdn}'
output coordinatorAgentUrl string = 'https://${coordinatorAgent.properties.configuration.ingress.fqdn}'
output storageAccountName string = storageAccount.name
output cosmosAccountName string = cosmosAccount.name
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output managedIdentityPrincipalId string = containerAppsManagedIdentity.properties.principalId
output managedIdentityClientId string = containerAppsManagedIdentity.properties.clientId
output keyVaultName string = keyVault.name
output mlWorkspaceName string = mlWorkspace.name