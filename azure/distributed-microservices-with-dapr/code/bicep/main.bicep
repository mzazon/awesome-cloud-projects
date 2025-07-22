@description('Main Bicep template for Distributed Microservices Architecture with Container Apps and Dapr')

// Parameters
@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment name for resource naming')
@minLength(3)
@maxLength(20)
param environmentName string = 'dapr-demo'

@description('Enable Application Insights for monitoring')
param enableAppInsights bool = true

@description('Container Apps environment name')
param containerAppsEnvironmentName string = 'aca-env-${environmentName}'

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string = 'law-${environmentName}'

@description('Service Bus namespace name')
param serviceBusNamespaceName string = 'sb-${environmentName}-${uniqueString(resourceGroup().id)}'

@description('Cosmos DB account name')
param cosmosDbAccountName string = 'cosmos-${environmentName}-${uniqueString(resourceGroup().id)}'

@description('Key Vault name')
param keyVaultName string = 'kv-${environmentName}-${uniqueString(resourceGroup().id)}'

@description('Application Insights name')
param appInsightsName string = 'ai-${environmentName}'

@description('Service Bus topic name')
param serviceBusTopicName string = 'orders'

@description('Cosmos DB database name')
param cosmosDbDatabaseName string = 'daprstate'

@description('Cosmos DB container name')
param cosmosDbContainerName string = 'statestore'

@description('Order service container image')
param orderServiceImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Inventory service container image')
param inventoryServiceImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Minimum replicas for container apps')
@minValue(0)
@maxValue(25)
param minReplicas int = 1

@description('Maximum replicas for container apps')
@minValue(1)
@maxValue(25)
param maxReplicas int = 10

@description('CPU allocation for container apps')
param cpuAllocation string = '0.5'

@description('Memory allocation for container apps')
param memoryAllocation string = '1.0Gi'

@description('Tags to apply to all resources')
param tags object = {
  environment: 'development'
  purpose: 'microservices-demo'
  solution: 'dapr-container-apps'
}

// Variables
var serviceBusConnectionStringSecretName = 'servicebus-connectionstring'
var cosmosDbUrlSecretName = 'cosmosdb-url'
var cosmosDbKeySecretName = 'cosmosdb-key'

// Log Analytics Workspace
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
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (enableAppInsights) {
  name: appInsightsName
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

// Service Bus Namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
  }
}

// Service Bus Topic
resource serviceBusTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: serviceBusTopicName
  properties: {
    maxSizeInMegabytes: 1024
    defaultMessageTimeToLive: 'P14D'
    enableBatchedOperations: true
    enablePartitioning: false
    requiresDuplicateDetection: false
    supportOrdering: false
  }
}

// Service Bus Authorization Rule
resource serviceBusAuthRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'RootManageSharedAccessKey'
  properties: {
    rights: [
      'Listen'
      'Manage'
      'Send'
    ]
  }
}

// Cosmos DB Account
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosDbAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
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
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    publicNetworkAccess: 'Enabled'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    isVirtualNetworkFilterEnabled: false
    virtualNetworkRules: []
    ipRules: []
    dependsOn: []
    enableFreeTier: false
    enableAnalyticalStorage: false
    analyticalStorageConfiguration: {
      schemaType: 'WellDefined'
    }
    createMode: 'Default'
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Local'
      }
    }
    networkAclBypass: 'None'
    disableKeyBasedMetadataWriteAccess: false
    enablePartitionMerge: false
    enableBurstCapacity: false
    minimalTlsVersion: 'Tls12'
  }
}

// Cosmos DB Database
resource cosmosDbDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosDbAccount
  name: cosmosDbDatabaseName
  properties: {
    resource: {
      id: cosmosDbDatabaseName
    }
  }
}

// Cosmos DB Container
resource cosmosDbContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDbDatabase
  name: cosmosDbContainerName
  properties: {
    resource: {
      id: cosmosDbContainerName
      partitionKey: {
        paths: [
          '/partitionKey'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
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
      defaultTtl: -1
    }
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
    tenantId: tenant().tenantId
    accessPolicies: []
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: false
    vaultUri: 'https://${keyVaultName}.vault.azure.net/'
    provisioningState: 'Succeeded'
    publicNetworkAccess: 'Enabled'
  }
}

// Key Vault Secrets
resource serviceBusConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: serviceBusConnectionStringSecretName
  properties: {
    value: listKeys(serviceBusAuthRule.id, serviceBusAuthRule.apiVersion).primaryConnectionString
    attributes: {
      enabled: true
    }
  }
}

resource cosmosDbUrlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: cosmosDbUrlSecretName
  properties: {
    value: cosmosDbAccount.properties.documentEndpoint
    attributes: {
      enabled: true
    }
  }
}

resource cosmosDbKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: cosmosDbKeySecretName
  properties: {
    value: cosmosDbAccount.listKeys().primaryMasterKey
    attributes: {
      enabled: true
    }
  }
}

// Container Apps Environment
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppsEnvironmentName
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
    daprConfiguration: {
      version: '1.12'
    }
    vnetConfiguration: {}
    infrastructureResourceGroup: '${resourceGroup().name}-infrastructure'
  }
}

// Dapr Component: Service Bus Pub/Sub
resource daprServiceBusPubSub 'Microsoft.App/managedEnvironments/daprComponents@2023-05-01' = {
  parent: containerAppsEnvironment
  name: 'pubsub'
  properties: {
    componentType: 'pubsub.azure.servicebus'
    version: 'v1'
    secrets: [
      {
        name: serviceBusConnectionStringSecretName
        value: listKeys(serviceBusAuthRule.id, serviceBusAuthRule.apiVersion).primaryConnectionString
      }
    ]
    metadata: [
      {
        name: 'connectionString'
        secretRef: serviceBusConnectionStringSecretName
      }
    ]
    scopes: [
      'order-service'
      'inventory-service'
    ]
  }
}

// Dapr Component: Cosmos DB State Store
resource daprCosmosDbStateStore 'Microsoft.App/managedEnvironments/daprComponents@2023-05-01' = {
  parent: containerAppsEnvironment
  name: 'statestore'
  properties: {
    componentType: 'state.azure.cosmosdb'
    version: 'v1'
    secrets: [
      {
        name: cosmosDbKeySecretName
        value: cosmosDbAccount.listKeys().primaryMasterKey
      }
    ]
    metadata: [
      {
        name: 'url'
        value: cosmosDbAccount.properties.documentEndpoint
      }
      {
        name: 'masterKey'
        secretRef: cosmosDbKeySecretName
      }
      {
        name: 'database'
        value: cosmosDbDatabaseName
      }
      {
        name: 'collection'
        value: cosmosDbContainerName
      }
    ]
    scopes: [
      'order-service'
      'inventory-service'
    ]
  }
}

// Order Service Container App
resource orderServiceContainerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'order-service'
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      dapr: {
        enabled: true
        appId: 'order-service'
        appProtocol: 'http'
        appPort: 80
        logLevel: 'info'
        enableApiLogging: true
      }
      secrets: enableAppInsights ? [
        {
          name: 'appinsights-connection-string'
          value: appInsights.properties.ConnectionString
        }
      ] : []
    }
    template: {
      containers: [
        {
          name: 'order-service'
          image: orderServiceImage
          resources: {
            cpu: json(cpuAllocation)
            memory: memoryAllocation
          }
          env: concat([
            {
              name: 'DAPR_HTTP_PORT'
              value: '3500'
            }
            {
              name: 'PUBSUB_NAME'
              value: 'pubsub'
            }
            {
              name: 'TOPIC_NAME'
              value: serviceBusTopicName
            }
            {
              name: 'STATE_STORE_NAME'
              value: 'statestore'
            }
          ], enableAppInsights ? [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-connection-string'
            }
          ] : [])
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scale-rule'
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
}

// Inventory Service Container App
resource inventoryServiceContainerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'inventory-service'
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: false
        targetPort: 80
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      dapr: {
        enabled: true
        appId: 'inventory-service'
        appProtocol: 'http'
        appPort: 80
        logLevel: 'info'
        enableApiLogging: true
      }
      secrets: enableAppInsights ? [
        {
          name: 'appinsights-connection-string'
          value: appInsights.properties.ConnectionString
        }
      ] : []
    }
    template: {
      containers: [
        {
          name: 'inventory-service'
          image: inventoryServiceImage
          resources: {
            cpu: json(cpuAllocation)
            memory: memoryAllocation
          }
          env: concat([
            {
              name: 'DAPR_HTTP_PORT'
              value: '3500'
            }
            {
              name: 'PUBSUB_NAME'
              value: 'pubsub'
            }
            {
              name: 'TOPIC_NAME'
              value: serviceBusTopicName
            }
            {
              name: 'STATE_STORE_NAME'
              value: 'statestore'
            }
          ], enableAppInsights ? [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-connection-string'
            }
          ] : [])
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scale-rule'
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
}

// Outputs
@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Container Apps environment name')
output containerAppsEnvironmentName string = containerAppsEnvironment.name

@description('Container Apps environment ID')
output containerAppsEnvironmentId string = containerAppsEnvironment.id

@description('Order service URL')
output orderServiceUrl string = 'https://${orderServiceContainerApp.properties.configuration.ingress.fqdn}'

@description('Order service FQDN')
output orderServiceFqdn string = orderServiceContainerApp.properties.configuration.ingress.fqdn

@description('Inventory service name')
output inventoryServiceName string = inventoryServiceContainerApp.name

@description('Service Bus namespace name')
output serviceBusNamespaceName string = serviceBusNamespace.name

@description('Service Bus topic name')
output serviceBusTopicName string = serviceBusTopic.name

@description('Cosmos DB account name')
output cosmosDbAccountName string = cosmosDbAccount.name

@description('Cosmos DB database name')
output cosmosDbDatabaseName string = cosmosDbDatabase.name

@description('Cosmos DB container name')
output cosmosDbContainerName string = cosmosDbContainer.name

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Application Insights name')
output appInsightsName string = enableAppInsights ? appInsights.name : ''

@description('Application Insights instrumentation key')
output appInsightsInstrumentationKey string = enableAppInsights ? appInsights.properties.InstrumentationKey : ''

@description('Application Insights connection string')
output appInsightsConnectionString string = enableAppInsights ? appInsights.properties.ConnectionString : ''

@description('Dapr components deployed')
output daprComponents array = [
  {
    name: daprServiceBusPubSub.name
    type: 'pubsub.azure.servicebus'
  }
  {
    name: daprCosmosDbStateStore.name
    type: 'state.azure.cosmosdb'
  }
]