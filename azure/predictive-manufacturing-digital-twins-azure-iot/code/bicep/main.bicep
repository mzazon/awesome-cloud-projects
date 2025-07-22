// =============================================================================
// Smart Manufacturing Digital Twins Infrastructure
// =============================================================================
// This Bicep template deploys a comprehensive smart manufacturing solution
// using Azure IoT Hub, Digital Twins, Time Series Insights, and Machine Learning
// for predictive maintenance and operational intelligence.

@description('Environment prefix for all resources (e.g., dev, staging, prod)')
@minLength(2)
@maxLength(10)
param environmentPrefix string = 'dev'

@description('Primary Azure region for resource deployment')
param location string = resourceGroup().location

@description('Unique suffix for resource naming (auto-generated if not provided)')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('IoT Hub SKU and capacity configuration')
@allowed(['B1', 'B2', 'B3', 'S1', 'S2', 'S3'])
param iotHubSku string = 'S1'

@description('Number of IoT Hub units')
@minValue(1)
@maxValue(200)
param iotHubUnits int = 1

@description('Time Series Insights SKU configuration')
@allowed(['L1'])
param tsiSku string = 'L1'

@description('Time Series Insights capacity (number of units)')
@minValue(1)
@maxValue(10)
param tsiCapacity int = 1

@description('Warm store data retention period in ISO 8601 format')
param warmStoreRetention string = 'P7D'

@description('Machine Learning workspace SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param mlWorkspaceSku string = 'Basic'

@description('Enable system-assigned managed identity for resources')
param enableManagedIdentity bool = true

@description('Resource tags for cost management and organization')
param resourceTags object = {
  Environment: environmentPrefix
  Solution: 'SmartManufacturing'
  Purpose: 'DigitalTwins'
  CostCenter: 'Manufacturing'
}

// =============================================================================
// Variables
// =============================================================================

var namePrefix = '${environmentPrefix}-manufacturing'
var resourceNames = {
  storageAccount: 'st${replace(namePrefix, '-', '')}${uniqueSuffix}'
  iotHub: '${namePrefix}-iothub-${uniqueSuffix}'
  digitalTwins: '${namePrefix}-dt-${uniqueSuffix}'
  timeSeriesInsights: '${namePrefix}-tsi-${uniqueSuffix}'
  mlWorkspace: '${namePrefix}-mlws-${uniqueSuffix}'
  applicationInsights: '${namePrefix}-ai-${uniqueSuffix}'
  keyVault: '${namePrefix}-kv-${uniqueSuffix}'
  eventHub: '${namePrefix}-eh-${uniqueSuffix}'
  eventHubNamespace: '${namePrefix}-ehns-${uniqueSuffix}'
}

// =============================================================================
// Storage Account for Time Series Insights
// =============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    isHnsEnabled: true // Hierarchical namespace for Time Series Insights
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
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

// =============================================================================
// Key Vault for Secrets Management
// =============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: resourceTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// =============================================================================
// Event Hub Namespace and Hub for IoT Data Routing
// =============================================================================

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: resourceNames.eventHubNamespace
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubNamespace
  name: 'manufacturing-telemetry'
  properties: {
    messageRetentionInDays: 1
    partitionCount: 4
    status: 'Active'
  }
}

resource eventHubConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = {
  parent: eventHub
  name: 'tsi-consumer-group'
  properties: {}
}

// =============================================================================
// IoT Hub for Device Connectivity
// =============================================================================

resource iotHub 'Microsoft.Devices/IotHubs@2023-06-30' = {
  name: resourceNames.iotHub
  location: location
  tags: resourceTags
  sku: {
    name: iotHubSku
    capacity: iotHubUnits
  }
  identity: enableManagedIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    eventHubEndpoints: {
      events: {
        retentionTimeInDays: 1
        partitionCount: 4
      }
    }
    routing: {
      endpoints: {
        eventHubs: [
          {
            name: 'manufacturing-telemetry-endpoint'
            connectionString: listKeys(eventHub.id, eventHub.apiVersion).primaryConnectionString
            subscriptionId: subscription().subscriptionId
            resourceGroup: resourceGroup().name
          }
        ]
      }
      routes: [
        {
          name: 'manufacturing-telemetry-route'
          source: 'DeviceMessages'
          condition: 'true'
          endpointNames: [
            'manufacturing-telemetry-endpoint'
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
    enableDataResidency: false
    minTlsVersion: '1.2'
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

// =============================================================================
// Azure Digital Twins Instance
// =============================================================================

resource digitalTwins 'Microsoft.DigitalTwins/digitalTwinsInstances@2023-01-31' = {
  name: resourceNames.digitalTwins
  location: location
  tags: resourceTags
  identity: enableManagedIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// =============================================================================
// Time Series Insights Environment
// =============================================================================

resource timeSeriesInsights 'Microsoft.TimeSeriesInsights/environments@2020-05-15' = {
  name: resourceNames.timeSeriesInsights
  location: location
  tags: resourceTags
  sku: {
    name: tsiSku
    capacity: tsiCapacity
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
      managementKey: listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value
    }
  }
}

resource tsiEventSource 'Microsoft.TimeSeriesInsights/environments/eventSources@2020-05-15' = {
  parent: timeSeriesInsights
  name: 'manufacturing-event-source'
  location: location
  kind: 'Microsoft.EventHub'
  properties: {
    eventSourceResourceId: eventHub.id
    eventHubName: eventHub.name
    serviceBusNamespace: eventHubNamespace.name
    keyName: 'RootManageSharedAccessKey'
    sharedAccessKey: listKeys(resourceId('Microsoft.EventHub/namespaces/authorizationRules', eventHubNamespace.name, 'RootManageSharedAccessKey'), eventHubNamespace.apiVersion).primaryKey
    consumerGroupName: eventHubConsumerGroup.name
    timestampPropertyName: 'timestamp'
  }
}

// =============================================================================
// Application Insights for Monitoring
// =============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 90
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =============================================================================
// Azure Machine Learning Workspace
// =============================================================================

resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: resourceNames.mlWorkspace
  location: location
  tags: resourceTags
  identity: enableManagedIdentity ? {
    type: 'SystemAssigned'
  } : null
  sku: {
    name: mlWorkspaceSku
    tier: mlWorkspaceSku
  }
  properties: {
    friendlyName: 'Smart Manufacturing ML Workspace'
    description: 'Machine Learning workspace for predictive maintenance and manufacturing analytics'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: applicationInsights.id
    publicNetworkAccess: 'Enabled'
    imageBuildCompute: 'DefaultCompute'
    allowPublicAccessWhenBehindVnet: false
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
  }
}

// =============================================================================
// RBAC Assignments for Managed Identities
// =============================================================================

// Digital Twins Data Owner role for IoT Hub (for data ingestion)
resource iotHubToDigitalTwinsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableManagedIdentity) {
  name: guid(iotHub.id, digitalTwins.id, 'b3ba6cc8-2c45-4c52-832b-6de9c95b8bc6')
  scope: digitalTwins
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b3ba6cc8-2c45-4c52-832b-6de9c95b8bc6') // Azure Digital Twins Data Owner
    principalId: enableManagedIdentity ? iotHub.identity.principalId : ''
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Data Contributor role for ML Workspace
resource mlWorkspaceToStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableManagedIdentity) {
  name: guid(mlWorkspace.id, storageAccount.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: enableManagedIdentity ? mlWorkspace.identity.principalId : ''
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Resource group name where resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('IoT Hub name for device registration')
output iotHubName string = iotHub.name

@description('IoT Hub hostname for device connections')
output iotHubHostname string = iotHub.properties.hostName

@description('Digital Twins instance hostname')
output digitalTwinsHostname string = digitalTwins.properties.hostName

@description('Digital Twins instance name')
output digitalTwinsName string = digitalTwins.name

@description('Time Series Insights environment name')
output timeSeriesInsightsName string = timeSeriesInsights.name

@description('Time Series Insights data access FQDN')
output timeSeriesInsightsDataAccessFqdn string = timeSeriesInsights.properties.dataAccessFqdn

@description('Machine Learning workspace name')
output mlWorkspaceName string = mlWorkspace.name

@description('Storage account name for Time Series Insights')
output storageAccountName string = storageAccount.name

@description('Key Vault name for secrets management')
output keyVaultName string = keyVault.name

@description('Event Hub namespace name')
output eventHubNamespaceName string = eventHubNamespace.name

@description('Event Hub name for telemetry routing')
output eventHubName string = eventHub.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('IoT Hub connection string for device management')
output iotHubConnectionString string = 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=iothubowner;SharedAccessKey=${listKeys(iotHub.id, iotHub.apiVersion).value[0].primaryKey}'

@description('Deployment summary with key resource information')
output deploymentSummary object = {
  environment: environmentPrefix
  location: location
  resourceCount: 9
  iotHub: {
    name: iotHub.name
    sku: iotHubSku
    units: iotHubUnits
  }
  digitalTwins: {
    name: digitalTwins.name
    hostname: digitalTwins.properties.hostName
  }
  timeSeriesInsights: {
    name: timeSeriesInsights.name
    sku: tsiSku
    capacity: tsiCapacity
  }
  machineLearning: {
    name: mlWorkspace.name
    sku: mlWorkspaceSku
  }
  managedIdentityEnabled: enableManagedIdentity
}