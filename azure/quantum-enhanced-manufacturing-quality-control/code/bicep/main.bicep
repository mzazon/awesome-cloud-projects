@description('Main Bicep template for Quantum-Enhanced Manufacturing Quality Control')
@minLength(3)
@maxLength(10)
param environmentName string = 'dev'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Unique suffix for resource naming')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('IoT Hub SKU and capacity')
param iotHubSku string = 'S1'
param iotHubCapacity int = 2

@description('Machine Learning compute instance VM size')
param mlComputeInstanceSize string = 'Standard_DS3_v2'

@description('Machine Learning compute cluster configuration')
param mlComputeClusterMinInstances int = 0
param mlComputeClusterMaxInstances int = 4

@description('Stream Analytics streaming units')
param streamAnalyticsStreamingUnits int = 1

@description('Cosmos DB throughput (RU/s)')
param cosmosThroughput int = 400

@description('Storage account replication type')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
])
param storageReplicationType string = 'Standard_LRS'

@description('Enable hierarchical namespace for Data Lake')
param enableHierarchicalNamespace bool = true

@description('Application Insights sampling percentage')
param applicationInsightsSamplingPercentage int = 100

@description('Tags to apply to all resources')
param tags object = {
  Environment: environmentName
  Application: 'Quantum-Manufacturing-QC'
  Owner: 'Manufacturing-Team'
  CostCenter: 'Manufacturing'
}

// Variables for resource naming
var resourcePrefix = 'qmc-${environmentName}-${uniqueSuffix}'
var storageAccountName = 'st${replace(resourcePrefix, '-', '')}'
var iotHubName = 'iothub-${resourcePrefix}'
var mlWorkspaceName = 'mlws-${resourcePrefix}'
var quantumWorkspaceName = 'qws-${resourcePrefix}'
var streamAnalyticsJobName = 'sa-${resourcePrefix}'
var cosmosAccountName = 'cosmos-${resourcePrefix}'
var functionAppName = 'func-${resourcePrefix}'
var appInsightsName = 'ai-${resourcePrefix}'
var keyVaultName = 'kv-${resourcePrefix}'
var logAnalyticsName = 'log-${resourcePrefix}'

// Storage Account with Data Lake capabilities
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageReplicationType
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    isHnsEnabled: enableHierarchicalNamespace
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    encryption: {
      requireInfrastructureEncryption: true
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
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Storage containers for manufacturing data
resource mlInferenceContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/ml-inference'
  properties: {
    publicAccess: 'None'
  }
}

resource qualityDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/quality-data'
  properties: {
    publicAccess: 'None'
  }
}

resource quantumResultsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/quantum-results'
  properties: {
    publicAccess: 'None'
  }
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
    }
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    SamplingPercentage: applicationInsightsSamplingPercentage
  }
}

// Key Vault for secrets management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: []
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// IoT Hub for manufacturing sensor data
resource iotHub 'Microsoft.Devices/IotHubs@2023-06-30' = {
  name: iotHubName
  location: location
  tags: tags
  sku: {
    name: iotHubSku
    capacity: iotHubCapacity
  }
  properties: {
    eventHubEndpoints: {
      events: {
        retentionTimeInDays: 7
        partitionCount: 4
      }
    }
    routing: {
      endpoints: {
        serviceBusQueues: []
        serviceBusTopics: []
        eventHubs: []
        storageContainers: []
      }
      routes: [
        {
          name: 'QualityControlRoute'
          source: 'DeviceMessages'
          condition: 'messageType = "qualityControl"'
          endpointNames: [
            'events'
          ]
          isEnabled: true
        }
      ]
      fallbackRoute: {
        name: '$fallback'
        source: 'DeviceMessages'
        condition: 'true'
        endpointNames: [
          'events'
        ]
        isEnabled: true
      }
    }
    messagingEndpoints: {
      fileNotifications: {
        lockDurationAsIso8601: 'PT1M'
        ttlAsIso8601: 'PT1H'
        maxDeliveryCount: 10
      }
    }
    enableFileUploadNotifications: false
    cloudToDevice: {
      maxDeliveryCount: 10
      defaultTtlAsIso8601: 'PT1H'
      feedback: {
        lockDurationAsIso8601: 'PT1M'
        ttlAsIso8601: 'PT1H'
        maxDeliveryCount: 10
      }
    }
    features: 'None'
  }
}

// Machine Learning Workspace
resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: mlWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'Quantum Manufacturing ML Workspace'
    description: 'Machine Learning workspace for quantum-enhanced manufacturing quality control'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: applicationInsights.id
    publicNetworkAccess: 'Enabled'
    allowPublicAccessWhenBehindVnet: true
    encryption: {
      status: 'Enabled'
      keyVaultProperties: {
        keyVaultArmId: keyVault.id
        keyIdentifier: ''
      }
    }
    hbiWorkspace: false
    v1LegacyMode: false
  }
}

// ML Compute Instance for development
resource mlComputeInstance 'Microsoft.MachineLearningServices/workspaces/computes@2024-04-01' = {
  name: 'quantum-dev-instance'
  parent: mlWorkspace
  location: location
  properties: {
    computeType: 'ComputeInstance'
    properties: {
      vmSize: mlComputeInstanceSize
      enableSSH: true
      sshSettings: {
        sshPublicAccess: 'Enabled'
      }
      applicationSharingPolicy: 'Personal'
      computeInstanceAuthorizationType: 'personal'
    }
  }
}

// ML Compute Cluster for training
resource mlComputeCluster 'Microsoft.MachineLearningServices/workspaces/computes@2024-04-01' = {
  name: 'quantum-ml-cluster'
  parent: mlWorkspace
  location: location
  properties: {
    computeType: 'AmlCompute'
    properties: {
      vmSize: mlComputeInstanceSize
      scaleSettings: {
        minNodeCount: mlComputeClusterMinInstances
        maxNodeCount: mlComputeClusterMaxInstances
        nodeIdleTimeBeforeScaleDown: 'PT5M'
      }
      userAccountCredentials: {
        adminUserName: 'azureuser'
        adminUserPassword: null
      }
      remoteLoginPortPublicAccess: 'Enabled'
    }
  }
}

// Azure Quantum Workspace
resource quantumWorkspace 'Microsoft.Quantum/Workspaces@2023-11-13-preview' = {
  name: quantumWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    providers: [
      {
        providerId: 'microsoft'
        providerSku: 'DZZ-Free'
      }
    ]
    storageAccount: storageAccount.id
  }
}

// Stream Analytics Job for real-time processing
resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: streamAnalyticsJobName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'Standard'
      capacity: streamAnalyticsStreamingUnits
    }
    outputErrorPolicy: 'Stop'
    eventsOutOfOrderPolicy: 'Adjust'
    eventsOutOfOrderMaxDelayInSeconds: 10
    eventsLateArrivalMaxDelayInSeconds: 60
    dataLocale: 'en-US'
    compatibilityLevel: '1.2'
    jobType: 'Cloud'
    inputs: [
      {
        name: 'ManufacturingInput'
        properties: {
          type: 'Stream'
          datasource: {
            type: 'Microsoft.ServiceBus/EventHub'
            properties: {
              serviceBusNamespace: ''
              eventHubName: 'events'
              sharedAccessPolicyName: 'iothubowner'
              sharedAccessPolicyKey: listKeys(resourceId('Microsoft.Devices/IotHubs/IotHubKeys', iotHub.name, 'iothubowner'), '2023-06-30').primaryKey
            }
          }
          serialization: {
            type: 'Json'
            properties: {
              encoding: 'UTF8'
            }
          }
        }
      }
    ]
    outputs: [
      {
        name: 'MLOutput'
        properties: {
          datasource: {
            type: 'Microsoft.Storage/Blob'
            properties: {
              storageAccounts: [
                {
                  accountName: storageAccount.name
                  accountKey: storageAccount.listKeys().keys[0].value
                }
              ]
              container: 'ml-inference'
              pathPattern: 'quality-control/{date}/{time}'
              dateFormat: 'yyyy/MM/dd'
              timeFormat: 'HH'
            }
          }
          serialization: {
            type: 'Json'
            properties: {
              encoding: 'UTF8'
              format: 'LineSeparated'
            }
          }
        }
      }
    ]
    transformation: {
      name: 'Transformation'
      properties: {
        streamingUnits: streamAnalyticsStreamingUnits
        query: '''
          SELECT
              System.Timestamp() as EventTime,
              IoTHub.ConnectionDeviceId as DeviceId,
              temperature,
              pressure,
              speed,
              quality_score,
              CASE 
                  WHEN quality_score < 95 THEN 'LOW'
                  WHEN quality_score < 98 THEN 'MEDIUM'
                  ELSE 'HIGH'
              END as QualityLevel
          INTO MLOutput
          FROM ManufacturingInput
          WHERE quality_score IS NOT NULL
        '''
      }
    }
  }
}

// Cosmos DB for real-time dashboard data
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-09-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
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
    defaultConsistencyLevel: 'Session'
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
        backupRetentionIntervalInHours: 720
        backupStorageRedundancy: 'Local'
      }
    }
    networkAclBypass: 'AzureServices'
    networkAclBypassResourceIds: []
  }
}

// Cosmos DB SQL Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-09-15' = {
  name: 'QualityControlDB'
  parent: cosmosAccount
  properties: {
    resource: {
      id: 'QualityControlDB'
    }
  }
}

// Cosmos DB Container for quality metrics
resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-09-15' = {
  name: 'QualityMetrics'
  parent: cosmosDatabase
  properties: {
    resource: {
      id: 'QualityMetrics'
      partitionKey: {
        paths: [
          '/productionLineId'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'Consistent'
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
      defaultTtl: 86400
    }
    options: {
      throughput: cosmosThroughput
    }
  }
}

// Function App for dashboard API
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enabled: true
    serverFarmId: hostingPlan.id
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
          value: 'python'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'COSMOS_CONNECTION_STRING'
          value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
        {
          name: 'IOT_HUB_CONNECTION_STRING'
          value: 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=iothubowner;SharedAccessKey=${listKeys(resourceId('Microsoft.Devices/IotHubs/IotHubKeys', iotHub.name, 'iothubowner'), '2023-06-30').primaryKey}'
        }
        {
          name: 'QUANTUM_WORKSPACE_CONNECTION_STRING'
          value: 'subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Quantum/Workspaces/${quantumWorkspace.name}'
        }
      ]
      pythonVersion: '3.9'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// App Service Plan for Function App
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'plan-${functionAppName}'
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
    reserved: true
  }
}

// RBAC assignments for managed identities
resource mlWorkspaceStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(mlWorkspace.id, storageAccount.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: mlWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource quantumWorkspaceStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(quantumWorkspace.id, storageAccount.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: quantumWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppCosmosRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, cosmosAccount.id, '00000000-0000-0000-0000-000000000002')
  scope: cosmosAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00000000-0000-0000-0000-000000000002')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output resourceGroupName string = resourceGroup().name
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output iotHubName string = iotHub.name
output iotHubHostName string = iotHub.properties.hostName
output mlWorkspaceName string = mlWorkspace.name
output mlWorkspaceId string = mlWorkspace.id
output quantumWorkspaceName string = quantumWorkspace.name
output quantumWorkspaceId string = quantumWorkspace.id
output streamAnalyticsJobName string = streamAnalyticsJob.name
output cosmosAccountName string = cosmosAccount.name
output cosmosAccountEndpoint string = cosmosAccount.properties.documentEndpoint
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output applicationInsightsName string = applicationInsights.name
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId