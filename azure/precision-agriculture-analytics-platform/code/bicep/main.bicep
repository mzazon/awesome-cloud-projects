@description('Bicep template for Precision Agriculture Analytics with AI-Driven Insights')

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment tag value')
param environment string = 'demo'

@description('Industry tag value')
param industry string = 'agriculture'

@description('Workload tag value')
param workload string = 'analytics'

@description('Azure Data Manager for Agriculture SKU')
@allowed(['Standard'])
param admaInstanceSku string = 'Standard'

@description('IoT Hub SKU')
@allowed(['S1', 'S2', 'S3'])
param iotHubSku string = 'S1'

@description('IoT Hub partition count')
@minValue(2)
@maxValue(32)
param iotHubPartitionCount int = 4

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Azure AI Services SKU')
@allowed(['S0', 'S1', 'S2'])
param aiServicesSku string = 'S0'

@description('Azure Maps SKU')
@allowed(['S0', 'S1'])
param mapsSku string = 'S1'

@description('Stream Analytics SKU')
@allowed(['Standard'])
param streamAnalyticsSku string = 'Standard'

@description('Function App runtime')
@allowed(['python'])
param functionAppRuntime string = 'python'

@description('Function App runtime version')
param functionAppRuntimeVersion string = '3.9'

// Variables
var resourceNames = {
  admaInstance: 'adma-farm-${uniqueSuffix}'
  iotHub: 'iothub-farm-${uniqueSuffix}'
  streamAnalytics: 'stream-farm-${uniqueSuffix}'
  storageAccount: 'stfarm${uniqueSuffix}'
  aiServices: 'ai-farm-${uniqueSuffix}'
  mapsAccount: 'maps-farm-${uniqueSuffix}'
  functionApp: 'func-crop-analysis-${uniqueSuffix}'
  appServicePlan: 'asp-farm-${uniqueSuffix}'
  applicationInsights: 'ai-farm-${uniqueSuffix}'
  logAnalyticsWorkspace: 'law-farm-${uniqueSuffix}'
}

var commonTags = {
  purpose: 'precision-agriculture'
  environment: environment
  industry: industry
  workload: workload
  deployedBy: 'bicep'
}

var storageContainers = [
  'crop-imagery'
  'field-boundaries'
  'weather-data'
  'analytics-results'
]

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: commonTags
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

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
  }
}

// Storage Account for agricultural data
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: union(commonTags, {
    purpose: 'agricultural-data-storage'
  })
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
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
  }
}

// Storage containers for different data types
resource storageContainerResources 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for containerName in storageContainers: {
  name: '${storageAccount.name}/default/${containerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storageAccount
  ]
}]

// IoT Hub for sensor data ingestion
resource iotHub 'Microsoft.Devices/IotHubs@2023-06-30' = {
  name: resourceNames.iotHub
  location: location
  tags: union(commonTags, {
    purpose: 'farm-sensors'
    'data-type': 'telemetry'
  })
  sku: {
    name: iotHubSku
    capacity: 1
  }
  properties: {
    eventHubEndpoints: {
      events: {
        retentionTimeInDays: 1
        partitionCount: iotHubPartitionCount
      }
    }
    routing: {
      endpoints: {
        storageContainers: []
        serviceBusQueues: []
        serviceBusTopics: []
        eventHubs: []
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
  }
}

// Sample IoT device for demonstration
resource iotDevice 'Microsoft.Devices/IotHubs/devices@2023-06-30' = {
  parent: iotHub
  name: 'soil-sensor-field-01'
  properties: {
    deviceId: 'soil-sensor-field-01'
    status: 'enabled'
    capabilities: {
      iotEdge: false
    }
  }
}

// Azure AI Services for computer vision
resource aiServices 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: resourceNames.aiServices
  location: location
  tags: union(commonTags, {
    purpose: 'crop-analysis'
    service: 'computer-vision'
  })
  kind: 'CognitiveServices'
  sku: {
    name: aiServicesSku
  }
  properties: {
    customSubDomainName: resourceNames.aiServices
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Azure Maps for geospatial visualization
resource mapsAccount 'Microsoft.Maps/accounts@2023-06-01' = {
  name: resourceNames.mapsAccount
  location: 'global'
  tags: union(commonTags, {
    purpose: 'field-mapping'
    service: 'geospatial'
  })
  sku: {
    name: mapsSku
  }
  properties: {
    disableLocalAuth: false
  }
}

// Stream Analytics Job for real-time data processing
resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: resourceNames.streamAnalytics
  location: location
  tags: union(commonTags, {
    purpose: 'real-time-processing'
    'data-type': 'sensor-streams'
  })
  properties: {
    sku: {
      name: streamAnalyticsSku
    }
    outputErrorPolicy: 'Stop'
    eventsOutOfOrderPolicy: 'Adjust'
    eventsOutOfOrderMaxDelayInSeconds: 10
    eventsLateArrivalMaxDelayInSeconds: 5
    dataLocale: 'en-US'
    compatibilityLevel: '1.2'
    contentStoragePolicy: 'SystemAccount'
    jobType: 'Cloud'
  }
}

// Stream Analytics Input from IoT Hub
resource streamAnalyticsInput 'Microsoft.StreamAnalytics/streamingjobs/inputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'SensorInput'
  properties: {
    type: 'Stream'
    datasource: {
      type: 'Microsoft.Devices/IotHubs'
      properties: {
        iotHubNamespace: iotHub.name
        sharedAccessPolicyName: 'iothubowner'
        sharedAccessPolicyKey: iotHub.listKeys().value[0].primaryKey
        endpoint: 'messages/events'
        consumerGroupName: '$Default'
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

// Stream Analytics Output to Storage
resource streamAnalyticsOutput 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'StorageOutput'
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
        container: 'analytics-results'
        pathPattern: 'sensor-data/{date}/{time}'
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

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: resourceNames.appServicePlan
  location: location
  tags: commonTags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

// Function App for automated image processing
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: resourceNames.functionApp
  location: location
  tags: union(commonTags, {
    purpose: 'image-analysis'
    automation: 'crop-health'
  })
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: '${functionAppRuntime}|${functionAppRuntimeVersion}'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
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
          value: functionAppRuntime
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
          name: 'AI_SERVICES_ENDPOINT'
          value: aiServices.properties.endpoint
        }
        {
          name: 'AI_SERVICES_KEY'
          value: aiServices.listKeys().key1
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
}

// Note: Azure Data Manager for Agriculture requires special registration and is deployed separately
// This template includes a placeholder for reference but does not deploy the actual service

// Outputs
@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Location used for deployment')
output location string = location

@description('Unique suffix used for resource names')
output uniqueSuffix string = uniqueSuffix

@description('Storage account name for agricultural data')
output storageAccountName string = storageAccount.name

@description('Storage account connection string')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('IoT Hub name for sensor data ingestion')
output iotHubName string = iotHub.name

@description('IoT Hub connection string')
output iotHubConnectionString string = 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=iothubowner;SharedAccessKey=${iotHub.listKeys().value[0].primaryKey}'

@description('Azure AI Services endpoint')
output aiServicesEndpoint string = aiServices.properties.endpoint

@description('Azure AI Services key')
output aiServicesKey string = aiServices.listKeys().key1

@description('Azure Maps account name')
output mapsAccountName string = mapsAccount.name

@description('Azure Maps primary key')
output mapsPrimaryKey string = mapsAccount.listKeys().primaryKey

@description('Stream Analytics job name')
output streamAnalyticsJobName string = streamAnalyticsJob.name

@description('Function App name for image processing')
output functionAppName string = functionApp.name

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Sample IoT device ID')
output sampleIotDeviceId string = iotDevice.name

@description('Storage containers for different data types')
output storageContainers array = storageContainers

@description('Instructions for Azure Data Manager for Agriculture')
output admaInstructions string = 'Azure Data Manager for Agriculture requires manual registration at https://aka.ms/agridatamanager and separate deployment using Azure CLI extension.'