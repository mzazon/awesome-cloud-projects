@description('Main Bicep template for Edge-Based Predictive Maintenance with Azure IoT Edge and Azure Monitor')

// Parameters
@description('Prefix for resource names')
@minLength(2)
@maxLength(10)
param resourcePrefix string = 'pm'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Environment tag for resources')
@allowed(['dev', 'test', 'staging', 'prod'])
param environment string = 'dev'

@description('IoT Hub SKU name')
@allowed(['F1', 'S1', 'S2', 'S3'])
param iotHubSku string = 'S1'

@description('IoT Hub capacity units')
@minValue(1)
@maxValue(10)
param iotHubCapacity int = 1

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS', 'Premium_LRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Stream Analytics job SKU')
@allowed(['Standard'])
param streamAnalyticsJobSku string = 'Standard'

@description('Stream Analytics streaming units')
@minValue(1)
@maxValue(192)
param streamAnalyticsStreamingUnits int = 1

@description('IoT Edge device ID')
param edgeDeviceId string = 'edge-device-01'

@description('Temperature alert threshold (average)')
@minValue(50)
@maxValue(100)
param temperatureAlertThreshold int = 75

@description('Temperature critical threshold (maximum)')
@minValue(70)
@maxValue(120)
param temperatureCriticalThreshold int = 85

@description('Alert window size in seconds')
@minValue(10)
@maxValue(300)
param alertWindowSize int = 30

@description('Notification email address for alerts')
param notificationEmail string

@description('Notification phone number for SMS alerts (format: +1234567890)')
param notificationPhone string

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'predictive-maintenance'
  environment: environment
  solution: 'iot-edge-monitoring'
}

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id)
var iotHubName = '${resourcePrefix}-hub-${uniqueSuffix}'
var storageAccountName = '${resourcePrefix}st${uniqueSuffix}'
var streamAnalyticsJobName = '${resourcePrefix}-sa-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-law-${uniqueSuffix}'
var actionGroupName = '${resourcePrefix}-ag-${uniqueSuffix}'
var alertRuleName = '${resourcePrefix}-alert-${uniqueSuffix}'

// Resources

// Storage Account for Stream Analytics and telemetry archival
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: storageAccountSku
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
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

// Blob containers for Stream Analytics and telemetry
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
  }
}

resource streamAnalyticsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'streamanalytics'
  properties: {
    publicAccess: 'None'
  }
}

resource telemetryArchiveContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'telemetry-archive'
  properties: {
    publicAccess: 'None'
  }
}

// IoT Hub
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
        retentionTimeInDays: 1
        partitionCount: 2
      }
    }
    routing: {
      endpoints: {
        storageContainers: [
          {
            name: 'telemetry-storage'
            connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
            containerName: 'telemetry-archive'
            fileNameFormat: '{iothub}/{partition}/{YYYY}/{MM}/{DD}/{HH}/{mm}'
            batchFrequencyInSeconds: 100
            maxChunkSizeInBytes: 104857600
            encoding: 'JSON'
          }
        ]
      }
      routes: [
        {
          name: 'telemetry-to-storage'
          source: 'DeviceMessages'
          condition: 'true'
          endpointNames: [
            'telemetry-storage'
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
  }
}

// IoT Edge Device Identity
resource edgeDevice 'Microsoft.Devices/IotHubs/devices@2023-06-30' = {
  parent: iotHub
  name: edgeDeviceId
  properties: {
    deviceId: edgeDeviceId
    capabilities: {
      iotEdge: true
    }
    authentication: {
      symmetricKey: {
        primaryKey: null
        secondaryKey: null
      }
      x509Thumbprint: {
        primaryThumbprint: null
        secondaryThumbprint: null
      }
      type: 'sas'
    }
    status: 'enabled'
  }
}

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
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Stream Analytics Job
resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: streamAnalyticsJobName
  location: location
  tags: tags
  properties: {
    sku: {
      name: streamAnalyticsJobSku
    }
    outputErrorPolicy: 'Stop'
    eventsOutOfOrderPolicy: 'Adjust'
    eventsOutOfOrderMaxDelayInSeconds: 0
    eventsLateArrivalMaxDelayInSeconds: 5
    dataLocale: 'en-US'
    compatibilityLevel: '1.2'
    contentStoragePolicy: 'SystemAccount'
    jobType: 'Edge'
    jobStorageAccount: {
      accountName: storageAccount.name
      accountKey: storageAccount.listKeys().keys[0].value
    }
  }
}

// Stream Analytics Job Input
resource streamAnalyticsInput 'Microsoft.StreamAnalytics/streamingjobs/inputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'temperature-input'
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

// Stream Analytics Job Output
resource streamAnalyticsOutput 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'anomaly-output'
  properties: {
    datasource: {
      type: 'Microsoft.Devices/IotHubs'
      properties: {
        iotHubNamespace: iotHub.name
        sharedAccessPolicyName: 'iothubowner'
        sharedAccessPolicyKey: iotHub.listKeys().value[0].primaryKey
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

// Stream Analytics Job Transformation
resource streamAnalyticsTransformation 'Microsoft.StreamAnalytics/streamingjobs/transformations@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'Transformation'
  properties: {
    streamingUnits: streamAnalyticsStreamingUnits
    query: '''
      SELECT
          'maintenance_required' AS alertType,
          System.Timestamp() AS alertTime,
          AVG(temperature) AS avgTemperature,
          MAX(temperature) AS maxTemperature,
          COUNT(*) AS readingCount,
          '${edgeDeviceId}' AS deviceId
      INTO
          [anomaly-output]
      FROM
          [temperature-input] TIMESTAMP BY timeCreated
      GROUP BY
          TumblingWindow(second, ${alertWindowSize})
      HAVING
          AVG(temperature) > ${temperatureAlertThreshold} OR MAX(temperature) > ${temperatureCriticalThreshold}
    '''
  }
}

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'MaintTeam'
    enabled: true
    emailReceivers: [
      {
        name: 'Maintenance'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: [
      {
        name: 'OnCall'
        countryCode: '1'
        phoneNumber: replace(notificationPhone, '+1', '')
      }
    ]
    azureFunctionReceivers: []
    logicAppReceivers: []
    webhookReceivers: []
    eventHubReceivers: []
    itsmReceivers: []
    voiceReceivers: []
    armRoleReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
  }
}

// Metric Alert Rule for High Temperature
resource metricAlertRule 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: alertRuleName
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when high message volume indicates temperature anomalies'
    severity: 2
    enabled: true
    scopes: [
      iotHub.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighTelemetryVolume'
          metricName: 'c2d.telemetry.ingress.allProtocol'
          metricNamespace: 'Microsoft.Devices/IotHubs'
          operator: 'GreaterThan'
          threshold: 100
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// Outputs
@description('IoT Hub name')
output iotHubName string = iotHub.name

@description('IoT Hub connection string')
output iotHubConnectionString string = 'HostName=${iotHub.name}.azure-devices.net;SharedAccessKeyName=iothubowner;SharedAccessKey=${iotHub.listKeys().value[0].primaryKey}'

@description('Edge device connection string')
output edgeDeviceConnectionString string = 'HostName=${iotHub.name}.azure-devices.net;DeviceId=${edgeDeviceId};SharedAccessKey=${iotHub.listKeys().value[0].primaryKey}'

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Stream Analytics job name')
output streamAnalyticsJobName string = streamAnalyticsJob.name

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Action group name')
output actionGroupName string = actionGroup.name

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Deployed resource information')
output deployedResources object = {
  iotHub: {
    name: iotHub.name
    resourceId: iotHub.id
    endpoint: 'https://${iotHub.name}.azure-devices.net'
  }
  storageAccount: {
    name: storageAccount.name
    resourceId: storageAccount.id
    endpoint: storageAccount.properties.primaryEndpoints.blob
  }
  streamAnalyticsJob: {
    name: streamAnalyticsJob.name
    resourceId: streamAnalyticsJob.id
    jobType: streamAnalyticsJob.properties.jobType
  }
  logAnalyticsWorkspace: {
    name: logAnalyticsWorkspace.name
    resourceId: logAnalyticsWorkspace.id
    workspaceId: logAnalyticsWorkspace.properties.customerId
  }
}