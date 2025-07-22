// ===================================================================
// Main Bicep template for Intelligent Energy Grid Analytics
// Orchestrates Azure Data Manager for Energy, Digital Twins, and AI Services
// ===================================================================

metadata description = 'Deploys intelligent energy grid analytics platform with Azure Data Manager for Energy, Digital Twins, AI Services, and Time Series Insights'

@description('The Azure region for deployment')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Project name for resource tagging')
param projectName string = 'energy-grid-analytics'

@description('SKU for Azure Data Manager for Energy')
@allowed(['S1', 'S2', 'S3'])
param energyDataManagerSku string = 'S1'

@description('Number of partitions for Energy Data Manager')
@minValue(1)
@maxValue(10)
param energyDataManagerPartitions int = 1

@description('SKU for Time Series Insights environment')
@allowed(['S1', 'S2'])
param timeSeriesInsightsSku string = 'S1'

@description('Capacity for Time Series Insights')
@minValue(1)
@maxValue(10)
param timeSeriesInsightsCapacity int = 1

@description('Data retention period for Time Series Insights warm store')
param warmStoreRetention string = 'P7D'

@description('SKU for Azure AI Services')
@allowed(['S0', 'S1', 'S2', 'S3', 'S4'])
param aiServicesSku string = 'S0'

@description('IoT Hub SKU')
@allowed(['S1', 'S2', 'S3'])
param iotHubSku string = 'S1'

@description('IoT Hub partition count')
@minValue(2)
@maxValue(32)
param iotHubPartitions int = 4

@description('Function App consumption plan location')
param functionAppLocation string = location

@description('Log Analytics workspace SKU')
@allowed(['PerGB2018', 'Free', 'Standalone', 'PerNode'])
param logAnalyticsSku string = 'PerGB2018'

// Variables for resource naming
var resourceNames = {
  energyDataManager: 'adm-energy-${uniqueSuffix}'
  digitalTwins: 'adt-grid-${uniqueSuffix}'
  timeSeriesInsights: 'tsi-energy-${uniqueSuffix}'
  aiServices: 'ai-energy-${uniqueSuffix}'
  storageAccount: 'stenergy${uniqueSuffix}'
  iotHub: 'iot-energy-${uniqueSuffix}'
  functionApp: 'func-energy-integration-${uniqueSuffix}'
  eventGridTopic: 'egt-energy-alerts-${uniqueSuffix}'
  logAnalytics: 'law-energy-${uniqueSuffix}'
  appServicePlan: 'asp-energy-${uniqueSuffix}'
}

// Common tags for all resources
var commonTags = {
  environment: environment
  project: projectName
  purpose: 'energy-grid-analytics'
  managedBy: 'bicep'
  costCenter: 'energy-operations'
}

// ===================================================================
// STORAGE ACCOUNT
// ===================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: union(commonTags, {
    resourceType: 'storage'
    purpose: 'ml-storage'
  })
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
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

// Storage containers for analytics and configuration
resource analyticsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/analytics-config'
  properties: {
    publicAccess: 'None'
  }
}

resource modelsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/ml-models'
  properties: {
    publicAccess: 'None'
  }
}

// ===================================================================
// AZURE DATA MANAGER FOR ENERGY
// ===================================================================

resource energyDataManager 'Microsoft.OpenEnergyPlatform/energyServices@2022-04-04-preview' = {
  name: resourceNames.energyDataManager
  location: location
  tags: union(commonTags, {
    resourceType: 'energy-data-manager'
    purpose: 'osdu-data-platform'
  })
  properties: {
    partitionCount: energyDataManagerPartitions
  }
  sku: {
    name: energyDataManagerSku
  }
}

// ===================================================================
// AZURE DIGITAL TWINS
// ===================================================================

resource digitalTwins 'Microsoft.DigitalTwins/digitalTwinsInstances@2023-01-31' = {
  name: resourceNames.digitalTwins
  location: location
  tags: union(commonTags, {
    resourceType: 'digital-twins'
    purpose: 'grid-modeling'
  })
  properties: {
    publicNetworkAccess: 'Enabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ===================================================================
// IOT HUB
// ===================================================================

resource iotHub 'Microsoft.Devices/IotHubs@2023-06-30' = {
  name: resourceNames.iotHub
  location: location
  tags: union(commonTags, {
    resourceType: 'iot-hub'
    purpose: 'iot-data-ingestion'
  })
  sku: {
    name: iotHubSku
    capacity: 1
  }
  properties: {
    eventHubEndpoints: {
      events: {
        retentionTimeInDays: 7
        partitionCount: iotHubPartitions
      }
    }
    messaging: {
      maxDeliveryCount: 10
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

// ===================================================================
// TIME SERIES INSIGHTS
// ===================================================================

resource timeSeriesInsights 'Microsoft.TimeSeriesInsights/environments@2020-05-15' = {
  name: resourceNames.timeSeriesInsights
  location: location
  tags: union(commonTags, {
    resourceType: 'time-series-insights'
    purpose: 'time-series-analytics'
  })
  sku: {
    name: timeSeriesInsightsSku
    capacity: timeSeriesInsightsCapacity
  }
  kind: 'Gen2'
  properties: {
    timeSeriesIdProperties: [
      {
        name: 'deviceId'
        type: 'String'
      }
    ]
    warmStoreConfiguration: {
      dataRetention: warmStoreRetention
    }
    storageConfiguration: {
      accountName: storageAccount.name
      managementKey: storageAccount.listKeys().keys[0].value
    }
  }
}

// Time Series Insights Event Source
resource tsiEventSource 'Microsoft.TimeSeriesInsights/environments/eventSources@2020-05-15' = {
  name: 'grid-data-source'
  parent: timeSeriesInsights
  location: location
  tags: union(commonTags, {
    resourceType: 'tsi-event-source'
  })
  kind: 'Microsoft.IoTHub'
  properties: {
    eventSourceResourceId: iotHub.id
    iotHubName: iotHub.name
    consumerGroupName: '$Default'
    keyName: 'iothubowner'
    sharedAccessKey: iotHub.listKeys().value[0].primaryKey
    timestampPropertyName: 'timestamp'
  }
}

// ===================================================================
// AZURE AI SERVICES
// ===================================================================

resource aiServices 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: resourceNames.aiServices
  location: location
  tags: union(commonTags, {
    resourceType: 'ai-services'
    purpose: 'ai-analytics'
  })
  sku: {
    name: aiServicesSku
  }
  kind: 'CognitiveServices'
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
    customSubDomainName: resourceNames.aiServices
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// ===================================================================
// LOG ANALYTICS WORKSPACE
// ===================================================================

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: resourceNames.logAnalytics
  location: location
  tags: union(commonTags, {
    resourceType: 'log-analytics'
    purpose: 'monitoring'
  })
  properties: {
    sku: {
      name: logAnalyticsSku
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ===================================================================
// APP SERVICE PLAN FOR FUNCTION APP
// ===================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: resourceNames.appServicePlan
  location: functionAppLocation
  tags: union(commonTags, {
    resourceType: 'app-service-plan'
    purpose: 'function-hosting'
  })
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
  }
  properties: {
    computeMode: 'Dynamic'
    reserved: false
  }
}

// ===================================================================
// FUNCTION APP FOR DATA INTEGRATION
// ===================================================================

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: resourceNames.functionApp
  location: functionAppLocation
  tags: union(commonTags, {
    resourceType: 'function-app'
    purpose: 'data-integration'
  })
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: resourceNames.functionApp
        }
        {
          name: 'DIGITAL_TWINS_ENDPOINT'
          value: 'https://${digitalTwins.properties.hostName}'
        }
        {
          name: 'AI_SERVICES_ENDPOINT'
          value: aiServices.properties.endpoint
        }
        {
          name: 'AI_SERVICES_KEY'
          value: aiServices.listKeys().key1
        }
        {
          name: 'ENERGY_DATA_MANAGER_ENDPOINT'
          value: energyDataManager.properties.endpoint
        }
        {
          name: 'IOT_HUB_CONNECTION_STRING'
          value: 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=iothubowner;SharedAccessKey=${iotHub.listKeys().value[0].primaryKey}'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      netFrameworkVersion: 'v6.0'
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ===================================================================
// EVENT GRID TOPIC
// ===================================================================

resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: resourceNames.eventGridTopic
  location: location
  tags: union(commonTags, {
    resourceType: 'event-grid-topic'
    purpose: 'alerting'
  })
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
  }
}

// ===================================================================
// DIAGNOSTIC SETTINGS
// ===================================================================

// Digital Twins diagnostics
resource digitalTwinsDiagnostics 'Microsoft.Insights/diagnosticsettings@2021-05-01-preview' = {
  name: 'dt-diagnostics'
  scope: digitalTwins
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// IoT Hub diagnostics
resource iotHubDiagnostics 'Microsoft.Insights/diagnosticsettings@2021-05-01-preview' = {
  name: 'iot-diagnostics'
  scope: iotHub
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Function App diagnostics
resource functionAppDiagnostics 'Microsoft.Insights/diagnosticsettings@2021-05-01-preview' = {
  name: 'function-diagnostics'
  scope: functionApp
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// ===================================================================
// RBAC ASSIGNMENTS
// ===================================================================

// Digital Twins Data Owner role for Function App
resource digitalTwinsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(digitalTwins.id, functionApp.id, 'bcd981a7-7f74-457b-83e1-cceb9e632ffe')
  scope: digitalTwins
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'bcd981a7-7f74-457b-83e1-cceb9e632ffe') // Azure Digital Twins Data Owner
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Data Contributor role for Function App
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Event Grid Data Sender role for Function App
resource eventGridRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, functionApp.id, 'd5a91429-5739-47e2-a06b-3470a27159e7')
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7') // EventGrid Data Sender
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ===================================================================
// OUTPUTS
// ===================================================================

@description('The name of the Energy Data Manager instance')
output energyDataManagerName string = energyDataManager.name

@description('The endpoint of the Energy Data Manager instance')
output energyDataManagerEndpoint string = energyDataManager.properties.endpoint

@description('The name of the Digital Twins instance')
output digitalTwinsName string = digitalTwins.name

@description('The hostname of the Digital Twins instance')
output digitalTwinsHostname string = digitalTwins.properties.hostName

@description('The endpoint URL of the Digital Twins instance')
output digitalTwinsEndpoint string = 'https://${digitalTwins.properties.hostName}'

@description('The name of the Time Series Insights environment')
output timeSeriesInsightsName string = timeSeriesInsights.name

@description('The name of the IoT Hub')
output iotHubName string = iotHub.name

@description('The hostname of the IoT Hub')
output iotHubHostname string = iotHub.properties.hostName

@description('The name of the AI Services account')
output aiServicesName string = aiServices.name

@description('The endpoint of the AI Services account')
output aiServicesEndpoint string = aiServices.properties.endpoint

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The name of the Event Grid topic')
output eventGridTopicName string = eventGridTopic.name

@description('The endpoint of the Event Grid topic')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The primary endpoint of the storage account')
output storageAccountEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The name of the Log Analytics workspace')
output logAnalyticsName string = logAnalytics.name

@description('The workspace ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalytics.properties.customerId

@description('Resource group name where all resources are deployed')
output resourceGroupName string = resourceGroup().name

@description('Common tags applied to all resources')
output commonTags object = commonTags

@description('All resource names used in the deployment')
output resourceNames object = resourceNames