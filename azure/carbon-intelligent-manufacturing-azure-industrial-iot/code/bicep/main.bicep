/*
  Azure Smart Factory Carbon Footprint Monitoring Infrastructure
  
  This Bicep template deploys a comprehensive carbon footprint monitoring solution
  that integrates Azure Industrial IoT with Azure Sustainability Manager for
  real-time environmental impact tracking in manufacturing facilities.
  
  Architecture Components:
  - Azure IoT Hub for device connectivity and telemetry ingestion
  - Azure Event Grid for event-driven processing
  - Azure Functions for carbon calculation logic
  - Azure Data Explorer for time-series analytics
  - Azure Event Hubs for high-throughput data streaming
  - Azure Storage for function app and data persistence
*/

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('IoT Hub SKU configuration')
@allowed(['F1', 'S1', 'S2', 'S3'])
param iotHubSku string = 'S1'

@description('IoT Hub capacity units')
@minValue(1)
@maxValue(200)
param iotHubCapacity int = 1

@description('Data Explorer cluster SKU')
@allowed(['Standard_D11_v2', 'Standard_D12_v2', 'Standard_D13_v2'])
param dataExplorerSku string = 'Standard_D11_v2'

@description('Data Explorer cluster capacity')
@minValue(2)
@maxValue(1000)
param dataExplorerCapacity int = 2

@description('Event Hub throughput units')
@minValue(1)
@maxValue(20)
param eventHubThroughputUnits int = 1

@description('Carbon calculation emission factor (kg CO2 per kWh)')
param carbonEmissionFactor string = '0.4'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'carbon-monitoring'
  Solution: 'smart-factory-sustainability'
}

// Variables for resource naming
var resourcePrefix = 'sf-carbon'
var iotHubName = '${resourcePrefix}-iothub-${uniqueSuffix}'
var eventGridTopicName = '${resourcePrefix}-evtgrid-${uniqueSuffix}'
var dataExplorerClusterName = '${resourcePrefix}-adx-${uniqueSuffix}'
var functionAppName = '${resourcePrefix}-func-${uniqueSuffix}'
var storageAccountName = '${resourcePrefix}st${uniqueSuffix}'
var eventHubNamespaceName = '${resourcePrefix}-ehns-${uniqueSuffix}'
var eventHubName = 'carbon-telemetry'
var applicationInsightsName = '${resourcePrefix}-ai-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-law-${uniqueSuffix}'

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
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
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
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
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
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

// Application Insights for Function App monitoring
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

// IoT Hub for device connectivity
resource iotHub 'Microsoft.Devices/IotHubs@2023-06-30' = {
  name: iotHubName
  location: location
  tags: tags
  sku: {
    name: iotHubSku
    capacity: iotHubCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    eventHubEndpoints: {
      events: {
        retentionTimeInDays: 1
        partitionCount: 4
      }
    }
    routing: {
      endpoints: {
        eventHubs: []
        serviceBusQueues: []
        serviceBusTopics: []
        storageContainers: []
      }
      routes: []
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
    minTlsVersion: '1.2'
    allowedFqdnList: []
  }
}

// Event Hub Namespace for high-throughput data ingestion
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2023-01-01-preview' = {
  name: eventHubNamespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: eventHubThroughputUnits
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: true
    maximumThroughputUnits: 20
    kafkaEnabled: true
  }
}

// Event Hub for carbon telemetry data
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2023-01-01-preview' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: 7
    partitionCount: 4
    status: 'Active'
    captureDescription: {
      enabled: false
    }
  }
}

// Event Hub authorization rule for Function App access
resource eventHubAuthRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2023-01-01-preview' = {
  parent: eventHub
  name: 'FunctionAppAccess'
  properties: {
    rights: [
      'Listen'
      'Send'
    ]
  }
}

// Event Grid Topic for event-driven architecture
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: tags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
    dataResidencyBoundary: 'WithinGeopair'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${functionAppName}-plan'
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
    reserved: false
  }
}

// Function App for carbon calculation logic
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    reserved: false
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
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
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'IoTHubConnectionString'
          value: 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=iothubowner;SharedAccessKey=${iotHub.listkeys().value[0].primaryKey}'
        }
        {
          name: 'EventGridEndpoint'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EventGridKey'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'EventHubConnectionString'
          value: eventHubAuthRule.listKeys().primaryConnectionString
        }
        {
          name: 'DataExplorerCluster'
          value: dataExplorerClusterName
        }
        {
          name: 'CarbonEmissionFactor'
          value: carbonEmissionFactor
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      pythonVersion: '3.9'
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
  }
  dependsOn: [
    storageAccount
    applicationInsights
  ]
}

// Data Explorer Cluster for time-series analytics
resource dataExplorerCluster 'Microsoft.Kusto/clusters@2023-08-15' = {
  name: dataExplorerClusterName
  location: location
  tags: tags
  sku: {
    name: dataExplorerSku
    tier: 'Standard'
    capacity: dataExplorerCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enableDiskEncryption: false
    enableStreamingIngest: true
    enablePurge: true
    enableDoubleEncryption: false
    enableAutoStop: true
    publicNetworkAccess: 'Enabled'
    allowedIpRangeList: []
    engineType: 'V3'
    acceptedAudiences: []
    enableZoneRedundant: false
    restrictOutboundNetworkAccess: 'Disabled'
  }
}

// Data Explorer Database for carbon monitoring data
resource dataExplorerDatabase 'Microsoft.Kusto/clusters/databases@2023-08-15' = {
  parent: dataExplorerCluster
  name: 'CarbonMonitoring'
  location: location
  kind: 'ReadWrite'
  properties: {
    softDeletePeriod: 'P365D'
    hotCachePeriod: 'P30D'
  }
}

// Event Grid Subscription for IoT Hub events
resource eventGridSubscription 'Microsoft.EventGrid/eventSubscriptions@2023-12-15-preview' = {
  name: 'carbon-monitoring-subscription'
  scope: iotHub
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${functionApp.properties.defaultHostName}/api/ProcessCarbonData'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Devices.DeviceTelemetry'
      ]
      enableAdvancedFilteringOnArrays: true
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
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

// Role assignment for Function App to access Event Grid
resource eventGridContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, functionApp.id, 'EventGrid Data Sender')
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7') // EventGrid Data Sender
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Function App to access IoT Hub
resource iotHubContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(iotHub.id, functionApp.id, 'IoT Hub Data Contributor')
  scope: iotHub
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4fc6c259-987e-4a07-842e-c321cc9d413f') // IoT Hub Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Function App to access Data Explorer
resource dataExplorerContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataExplorerCluster.id, functionApp.id, 'Azure Digital Twins Data Owner')
  scope: dataExplorerCluster
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'bcd981a7-7f74-457b-83e1-cceb9e632ffe') // Azure Digital Twins Data Owner
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs for integration and validation
@description('IoT Hub hostname for device connections')
output iotHubHostname string = iotHub.properties.hostName

@description('IoT Hub connection string for device management')
output iotHubConnectionString string = 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=iothubowner;SharedAccessKey=${iotHub.listkeys().value[0].primaryKey}'

@description('Event Grid topic endpoint for custom events')
output eventGridEndpoint string = eventGridTopic.properties.endpoint

@description('Event Grid topic access key')
output eventGridAccessKey string = eventGridTopic.listKeys().key1

@description('Function App hostname for API access')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('Function App name for deployment')
output functionAppName string = functionApp.name

@description('Data Explorer cluster URI for analytics queries')
output dataExplorerClusterUri string = dataExplorerCluster.properties.uri

@description('Data Explorer database name for carbon monitoring')
output dataExplorerDatabaseName string = dataExplorerDatabase.name

@description('Event Hub connection string for high-throughput ingestion')
output eventHubConnectionString string = eventHubAuthRule.listKeys().primaryConnectionString

@description('Event Hub namespace name')
output eventHubNamespaceName string = eventHubNamespace.name

@description('Event Hub name for telemetry data')
output eventHubName string = eventHub.name

@description('Storage account name for Function App')
output storageAccountName string = storageAccount.name

@description('Application Insights instrumentation key for monitoring')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Log Analytics workspace ID for monitoring')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Resource group name containing all resources')
output resourceGroupName string = resourceGroup().name

@description('Deployment environment')
output environment string = environment

@description('Unique suffix used for resource naming')
output uniqueSuffix string = uniqueSuffix