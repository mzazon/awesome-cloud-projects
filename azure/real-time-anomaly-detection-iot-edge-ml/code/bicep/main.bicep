@description('The name of the resource group')
param resourceGroupName string = 'rg-anomaly-detection'

@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('The name of the IoT Hub')
param iotHubName string = 'iot-hub-anomaly-${uniqueString(resourceGroup().id)}'

@description('The name of the storage account')
param storageAccountName string = 'stanomalydata${uniqueString(resourceGroup().id)}'

@description('The name of the Machine Learning workspace')
param mlWorkspaceName string = 'ml-anomaly-detection'

@description('The name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string = 'log-anomaly-detection'

@description('The name of the Stream Analytics job')
param streamAnalyticsJobName string = 'asa-edge-anomaly-job'

@description('The name of the Application Insights instance')
param applicationInsightsName string = 'ai-anomaly-detection'

@description('The name of the Key Vault')
param keyVaultName string = 'kv-anomaly-${uniqueString(resourceGroup().id)}'

@description('The Edge Device ID')
param edgeDeviceId string = 'factory-edge-device-01'

@description('The IoT Hub SKU')
@allowed([
  'F1'
  'S1'
  'S2'
  'S3'
])
param iotHubSku string = 'S1'

@description('The number of IoT Hub units')
@minValue(1)
@maxValue(200)
param iotHubUnits int = 1

@description('The storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Tags to apply to all resources')
param resourceTags object = {
  purpose: 'anomaly-detection'
  environment: 'demo'
  project: 'iot-edge-ml'
}

// Variables
var iotHubKeyName = 'iothubowner'
var storageAccountType = 'StorageV2'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      immediatePurgeDataOn30Days: true
    }
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: resourceTags
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
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Storage Account with Data Lake Gen2 capabilities
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageAccountSku
  }
  kind: storageAccountType
  properties: {
    isHnsEnabled: true // Enable hierarchical namespace for Data Lake Gen2
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
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
      bypass: 'AzureServices'
    }
  }
}

// Storage Account Blob Services
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

// Storage Containers
resource mlModelsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'ml-models'
  properties: {
    publicAccess: 'None'
  }
}

resource anomalyDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'anomaly-data'
  properties: {
    publicAccess: 'None'
  }
}

// IoT Hub
resource iotHub 'Microsoft.Devices/IotHubs@2023-06-30' = {
  name: iotHubName
  location: location
  tags: resourceTags
  sku: {
    name: iotHubSku
    capacity: iotHubUnits
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
            name: 'anomaly-storage'
            resourceGroup: resourceGroup().name
            subscriptionId: subscription().subscriptionId
            containerName: anomalyDataContainer.name
            fileNameFormat: '{iothub}/{partition}/{YYYY}/{MM}/{DD}/{HH}/{mm}.json'
            batchFrequencyInSeconds: 60
            maxChunkSizeInBytes: 10485760
            encoding: 'JSON'
            connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
          }
        ]
      }
      routes: [
        {
          name: 'AnomalyDataRoute'
          source: 'DeviceMessages'
          condition: 'true'
          endpointNames: [
            'anomaly-storage'
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
    features: 'None'
  }
}

// Machine Learning Workspace
resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2023-10-01' = {
  name: mlWorkspaceName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: mlWorkspaceName
    description: 'Machine Learning workspace for anomaly detection'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: applicationInsights.id
    hbiWorkspace: false
    v1LegacyMode: false
    publicNetworkAccess: 'Enabled'
  }
}

// ML Compute Instance
resource mlComputeInstance 'Microsoft.MachineLearningServices/workspaces/computes@2023-10-01' = {
  parent: mlWorkspace
  name: 'cpu-cluster'
  location: location
  tags: resourceTags
  properties: {
    computeType: 'AmlCompute'
    properties: {
      vmSize: 'Standard_DS3_v2'
      vmPriority: 'Dedicated'
      scaleSettings: {
        minNodeCount: 0
        maxNodeCount: 4
        nodeIdleTimeBeforeScaleDown: 'PT120S'
      }
      enableNodePublicIp: true
    }
  }
}

// Stream Analytics Job
resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: streamAnalyticsJobName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'Standard'
    }
    outputErrorPolicy: 'Stop'
    eventsOutOfOrderPolicy: 'Adjust'
    eventsOutOfOrderMaxDelayInSeconds: 0
    eventsLateArrivalMaxDelayInSeconds: 5
    dataLocale: 'en-US'
    compatibilityLevel: '1.2'
    jobType: 'Edge'
  }
}

// Stream Analytics Input
resource streamAnalyticsInput 'Microsoft.StreamAnalytics/streamingjobs/inputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'sensorInput'
  properties: {
    type: 'Stream'
    datasource: {
      type: 'Microsoft.Devices/IotHubs'
      properties: {
        iotHubNamespace: iotHub.name
        sharedAccessPolicyName: iotHubKeyName
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

// Stream Analytics Output
resource streamAnalyticsOutput 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'output'
  properties: {
    datasource: {
      type: 'Microsoft.Devices/IotHubs'
      properties: {
        iotHubNamespace: iotHub.name
        sharedAccessPolicyName: iotHubKeyName
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

// Stream Analytics Transformation (Anomaly Detection Query)
resource streamAnalyticsTransformation 'Microsoft.StreamAnalytics/streamingjobs/transformations@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'anomalyQuery'
  properties: {
    streamingUnits: 1
    query: '''
      WITH AnomalyDetectionStep AS
      (
          SELECT
              deviceId,
              temperature,
              pressure,
              vibration,
              ANOMALYDETECTION(temperature) OVER (PARTITION BY deviceId LIMIT DURATION(minute, 5)) AS temp_scores,
              ANOMALYDETECTION(pressure) OVER (PARTITION BY deviceId LIMIT DURATION(minute, 5)) AS pressure_scores,
              System.Timestamp() AS eventTime
          FROM sensorInput
      )
      SELECT
          deviceId,
          temperature,
          pressure,
          vibration,
          temp_scores,
          pressure_scores,
          eventTime
      INTO output
      FROM AnomalyDetectionStep
      WHERE
          CAST(GetRecordPropertyValue(temp_scores, "BiLevelChangeScore") AS FLOAT) > 3.5
          OR CAST(GetRecordPropertyValue(pressure_scores, "BiLevelChangeScore") AS FLOAT) > 3.5
    '''
  }
}

// Diagnostic Settings for IoT Hub
resource iotHubDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'iot-diagnostics'
  scope: iotHub
  properties: {
    workspaceId: logAnalyticsWorkspace.id
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

// Diagnostic Settings for ML Workspace
resource mlWorkspaceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'ml-diagnostics'
  scope: mlWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
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

// Role Assignment for ML Workspace to access Storage Account
resource mlWorkspaceStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, mlWorkspace.id, 'StorageBlobDataContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: mlWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for ML Workspace to access Key Vault
resource mlWorkspaceKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, mlWorkspace.id, 'KeyVaultContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f25e0fa2-a7c8-4377-a976-54943a77a395') // Key Vault Contributor
    principalId: mlWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('The name of the IoT Hub')
output iotHubName string = iotHub.name

@description('The IoT Hub hostname')
output iotHubHostname string = iotHub.properties.hostName

@description('The IoT Hub connection string')
output iotHubConnectionString string = 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=${iotHubKeyName};SharedAccessKey=${iotHub.listKeys().value[0].primaryKey}'

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The storage account connection string')
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('The name of the ML workspace')
output mlWorkspaceName string = mlWorkspace.name

@description('The ML workspace ID')
output mlWorkspaceId string = mlWorkspace.id

@description('The name of the Stream Analytics job')
output streamAnalyticsJobName string = streamAnalyticsJob.name

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The edge device ID')
output edgeDeviceId string = edgeDeviceId

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Location of all resources')
output location string = location