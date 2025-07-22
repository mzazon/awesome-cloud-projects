@description('Main Bicep template for Secure IoT Edge Analytics with Azure Percept and Sphere')

// ========== PARAMETERS ==========
@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Administrator email for alert notifications')
param adminEmail string

@description('IoT Hub SKU and capacity')
@allowed(['S1', 'S2', 'S3'])
param iotHubSku string = 'S1'

@description('IoT Hub capacity (number of units)')
@minValue(1)
@maxValue(200)
param iotHubCapacity int = 1

@description('Stream Analytics streaming units')
@minValue(1)
@maxValue(48)
param streamAnalyticsStreamingUnits int = 1

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Enable diagnostic logging')
param enableDiagnostics bool = true

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Solution: 'IoT Edge Analytics'
  Purpose: 'Secure IoT Analytics with Azure Percept and Sphere'
}

// ========== VARIABLES ==========
var resourcePrefix = 'iot-edge-${environment}-${uniqueSuffix}'
var iotHubName = '${resourcePrefix}-hub'
var streamAnalyticsJobName = '${resourcePrefix}-stream'
var storageAccountName = replace('${resourcePrefix}storage', '-', '')
var logAnalyticsWorkspaceName = '${resourcePrefix}-logs'
var applicationInsightsName = '${resourcePrefix}-insights'
var actionGroupName = '${resourcePrefix}-alerts'
var keyVaultName = '${resourcePrefix}-kv'
var containerName = 'processed-telemetry'

// Device configuration
var perceptDeviceId = 'percept-device-01'
var sphereDeviceId = 'sphere-device-01'

// ========== RESOURCES ==========

// Log Analytics Workspace for centralized logging
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for application monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Key Vault for secure storage of connection strings and certificates
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
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Storage Account with Data Lake Gen2 capabilities
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    isHnsEnabled: true // Enable hierarchical namespace for Data Lake Gen2
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
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

// Blob Services for storage account
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

// Container for processed telemetry data
resource telemetryContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: containerName
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'IoT telemetry data storage'
    }
  }
}

// Container for raw telemetry data
resource rawTelemetryContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'raw-telemetry'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Raw IoT telemetry data storage'
    }
  }
}

// IoT Hub for device management and messaging
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
        storageContainers: [
          {
            name: 'rawTelemetryEndpoint'
            resourceGroup: resourceGroup().name
            subscriptionId: subscription().subscriptionId
            connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
            containerName: 'raw-telemetry'
            fileNameFormat: '{iothub}/{partition}/{YYYY}/{MM}/{DD}/{HH}/{mm}'
            batchFrequencyInSeconds: 100
            maxChunkSizeInBytes: 104857600
            encoding: 'JSON'
          }
        ]
        serviceBusQueues: []
        serviceBusTopics: []
        eventHubs: []
      }
      routes: [
        {
          name: 'DeviceToStorageRoute'
          source: 'DeviceMessages'
          condition: 'true'
          endpointNames: [
            'rawTelemetryEndpoint'
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
    publicNetworkAccess: 'Enabled'
  }
}

// Consumer group for Stream Analytics
resource streamAnalyticsConsumerGroup 'Microsoft.Devices/IotHubs/eventHubEndpoints/ConsumerGroups@2023-06-30' = {
  parent: iotHub
  name: 'events/streamanalytics'
  properties: {
    name: 'streamanalytics'
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
    eventsOutOfOrderMaxDelayInSeconds: 0
    eventsLateArrivalMaxDelayInSeconds: 5
    dataLocale: 'en-US'
    compatibilityLevel: '1.2'
    jobType: 'Cloud'
  }
}

// Stream Analytics Input (IoT Hub)
resource streamAnalyticsInput 'Microsoft.StreamAnalytics/streamingjobs/inputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'IoTHubInput'
  properties: {
    type: 'Stream'
    datasource: {
      type: 'Microsoft.Devices/IotHubs'
      properties: {
        iotHubNamespace: iotHub.name
        sharedAccessPolicyName: 'iothubowner'
        sharedAccessPolicyKey: iotHub.listKeys().value[0].primaryKey
        endpoint: 'messages/events'
        consumerGroupName: streamAnalyticsConsumerGroup.name
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

// Stream Analytics Output (Storage)
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
        container: containerName
        pathPattern: 'year={datetime:yyyy}/month={datetime:MM}/day={datetime:dd}/hour={datetime:HH}'
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

// Stream Analytics Transformation
resource streamAnalyticsTransformation 'Microsoft.StreamAnalytics/streamingjobs/transformations@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'ProcessTelemetry'
  properties: {
    streamingUnits: streamAnalyticsStreamingUnits
    query: '''
      WITH AnomalyDetection AS (
        SELECT
          deviceId,
          EventEnqueuedUtcTime as timestamp,
          temperature,
          humidity,
          vibration,
          AnomalyDetection_SpikeAndDip(temperature, 95, 120, 'spikesanddips')
            OVER(LIMIT DURATION(minute, 2)) AS temperatureAnomaly,
          AnomalyDetection_SpikeAndDip(vibration, 95, 120, 'spikesanddips')
            OVER(LIMIT DURATION(minute, 2)) AS vibrationAnomaly
        FROM IoTHubInput
        WHERE deviceId IN ('${perceptDeviceId}', '${sphereDeviceId}')
      ),
      AggregatedData AS (
        SELECT
          deviceId,
          System.Timestamp() AS windowEnd,
          AVG(temperature) AS avgTemperature,
          MAX(temperature) AS maxTemperature,
          MIN(temperature) AS minTemperature,
          AVG(humidity) AS avgHumidity,
          MAX(humidity) AS maxHumidity,
          MIN(humidity) AS minHumidity,
          AVG(vibration) AS avgVibration,
          MAX(vibration) AS maxVibration,
          MIN(vibration) AS minVibration,
          COUNT(*) AS messageCount
        FROM IoTHubInput
        WHERE deviceId IN ('${perceptDeviceId}', '${sphereDeviceId}')
        GROUP BY deviceId, TumblingWindow(minute, 5)
      )
      SELECT
        ad.deviceId,
        ad.timestamp,
        ad.temperature,
        ad.humidity,
        ad.vibration,
        ad.temperatureAnomaly.IsAnomaly as isTemperatureAnomaly,
        ad.temperatureAnomaly.Score as temperatureAnomalyScore,
        ad.vibrationAnomaly.IsAnomaly as isVibrationAnomaly,
        ad.vibrationAnomaly.Score as vibrationAnomalyScore,
        ag.avgTemperature,
        ag.maxTemperature,
        ag.minTemperature,
        ag.avgHumidity,
        ag.maxHumidity,
        ag.minHumidity,
        ag.avgVibration,
        ag.maxVibration,
        ag.minVibration,
        ag.messageCount,
        ag.windowEnd
      INTO StorageOutput
      FROM AnomalyDetection ad
      JOIN AggregatedData ag ON ad.deviceId = ag.deviceId
      WHERE ad.temperatureAnomaly.IsAnomaly = 1 OR ad.vibrationAnomaly.IsAnomaly = 1
    '''
  }
}

// Action Group for alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'IoTAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'AdminEmail'
        emailAddress: adminEmail
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    azureFunctionReceivers: []
    logicAppReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    armRoleReceivers: []
    eventHubReceivers: []
  }
}

// Alert Rule for Stream Analytics failures
resource streamAnalyticsFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${streamAnalyticsJobName}-failures'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when Stream Analytics job encounters runtime errors'
    enabled: true
    severity: 2
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'RuntimeErrors'
          metricName: 'Errors'
          metricNamespace: 'Microsoft.StreamAnalytics/streamingjobs'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
    scopes: [
      streamAnalyticsJob.id
    ]
  }
}

// Alert Rule for device connectivity
resource deviceConnectivityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${iotHubName}-connectivity'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when device count drops below expected threshold'
    enabled: true
    severity: 3
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ConnectedDevices'
          metricName: 'devices.connectedDevices.allProtocols'
          metricNamespace: 'Microsoft.Devices/IotHubs'
          operator: 'LessThan'
          threshold: 2
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
    scopes: [
      iotHub.id
    ]
  }
}

// Diagnostic Settings for IoT Hub
resource iotHubDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: '${iotHubName}-diagnostics'
  scope: iotHub
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// Diagnostic Settings for Stream Analytics
resource streamAnalyticsDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: '${streamAnalyticsJobName}-diagnostics'
  scope: streamAnalyticsJob
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// Diagnostic Settings for Storage Account
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: '${storageAccountName}-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// Store connection strings in Key Vault
resource iotHubConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'iot-hub-connection-string'
  properties: {
    value: 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=iothubowner;SharedAccessKey=${iotHub.listKeys().value[0].primaryKey}'
    contentType: 'IoT Hub Connection String'
  }
}

resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-connection-string'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    contentType: 'Storage Account Connection String'
  }
}

// ========== OUTPUTS ==========

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('IoT Hub name')
output iotHubName string = iotHub.name

@description('IoT Hub hostname')
output iotHubHostname string = iotHub.properties.hostName

@description('IoT Hub connection string')
output iotHubConnectionString string = 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=iothubowner;SharedAccessKey=${iotHub.listKeys().value[0].primaryKey}'

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Storage Account connection string')
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Stream Analytics Job name')
output streamAnalyticsJobName string = streamAnalyticsJob.name

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Percept device ID')
output perceptDeviceId string = perceptDeviceId

@description('Sphere device ID')
output sphereDeviceId string = sphereDeviceId

@description('Telemetry container name')
output telemetryContainerName string = containerName

@description('Action Group name')
output actionGroupName string = actionGroup.name

@description('Deployment completed successfully')
output deploymentStatus string = 'SUCCESS: IoT Edge Analytics infrastructure deployed'