@description('Main Bicep template for Fleet Tracking with Geospatial Analytics')

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment suffix for resource naming (e.g., dev, test, prod)')
@maxLength(10)
param environmentSuffix string = 'demo'

@description('Random suffix for unique resource names')
@maxLength(6)
param randomSuffix string = uniqueString(resourceGroup().id, deployment().name)

@description('Event Hub namespace SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param eventHubSku string = 'Standard'

@description('Event Hub namespace capacity (throughput units)')
@minValue(1)
@maxValue(20)
param eventHubCapacity int = 2

@description('Number of partitions for the Event Hub')
@minValue(1)
@maxValue(32)
param eventHubPartitionCount int = 4

@description('Event Hub message retention in hours')
@minValue(1)
@maxValue(168)
param eventHubRetentionHours int = 24

@description('Cosmos DB consistency level')
@allowed([
  'Eventual'
  'Session'
  'BoundedStaleness'
  'Strong'
  'ConsistentPrefix'
])
param cosmosConsistencyLevel string = 'Session'

@description('Cosmos DB container throughput (RU/s)')
@minValue(400)
@maxValue(100000)
param cosmosThroughput int = 400

@description('Azure Maps SKU')
@allowed([
  'S0'
  'S1'
  'G2'
])
param mapsSku string = 'G2'

@description('Stream Analytics SKU')
@allowed([
  'Standard'
  'Premium'
])
param streamAnalyticsSku string = 'Standard'

@description('Stream Analytics streaming units')
@minValue(1)
@maxValue(192)
param streamAnalyticsStreamingUnits int = 1

// Variables
var resourcePrefix = 'geospatial-${environmentSuffix}'
var uniqueResourceSuffix = '${environmentSuffix}-${randomSuffix}'

var eventHubNamespaceName = 'ehns-${uniqueResourceSuffix}'
var eventHubName = 'vehicle-locations'
var storageAccountName = 'st${replace(uniqueResourceSuffix, '-', '')}'
var streamAnalyticsJobName = 'asa-${uniqueResourceSuffix}'
var cosmosAccountName = 'cosmos-${uniqueResourceSuffix}'
var cosmosDatabaseName = 'FleetAnalytics'
var cosmosContainerName = 'LocationEvents'
var mapsAccountName = 'maps-${uniqueResourceSuffix}'
var actionGroupName = 'ag-fleet-alerts-${uniqueResourceSuffix}'

// Common tags
var commonTags = {
  Environment: environmentSuffix
  Project: 'GeospatialAnalytics'
  CostCenter: 'Operations'
  Owner: 'FleetManagement'
  CreatedBy: 'Bicep'
  CreatedDate: utcNow('yyyy-MM-dd')
}

// Storage Account for Stream Analytics and archival
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
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

// Blob containers for data archival and geofences
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
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

resource telemetryArchiveContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'telemetry-archive'
  properties: {
    publicAccess: 'None'
  }
}

resource geofencesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'geofences'
  properties: {
    publicAccess: 'None'
  }
}

// Event Hub Namespace
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2023-01-01-preview' = {
  name: eventHubNamespaceName
  location: location
  tags: commonTags
  sku: {
    name: eventHubSku
    capacity: eventHubCapacity
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
  }
}

// Authorization rule for Event Hub namespace
resource eventHubNamespaceAuthRule 'Microsoft.EventHub/namespaces/authorizationRules@2023-01-01-preview' = {
  parent: eventHubNamespace
  name: 'RootManageSharedAccessKey'
  properties: {
    rights: [
      'Listen'
      'Manage'
      'Send'
    ]
  }
}

// Event Hub for vehicle locations
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2023-01-01-preview' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    partitionCount: eventHubPartitionCount
    messageRetentionInDays: eventHubRetentionHours / 24
    status: 'Active'
    captureDescription: {
      enabled: false
    }
  }
}

// Consumer group for Stream Analytics
resource eventHubConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2023-01-01-preview' = {
  parent: eventHub
  name: 'stream-analytics-consumer-group'
  properties: {
    userMetadata: 'Consumer group for Stream Analytics job'
  }
}

// Cosmos DB Account
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: cosmosAccountName
  location: location
  tags: commonTags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: cosmosConsistencyLevel
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
    apiProperties: {
      serverVersion: '4.2'
    }
  }
}

// Cosmos DB Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-11-15' = {
  parent: cosmosAccount
  name: cosmosDatabaseName
  properties: {
    resource: {
      id: cosmosDatabaseName
    }
  }
}

// Cosmos DB Container for location events
resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = {
  parent: cosmosDatabase
  name: cosmosContainerName
  properties: {
    resource: {
      id: cosmosContainerName
      partitionKey: {
        paths: [
          '/vehicleId'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        automatic: true
        indexingMode: 'consistent'
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
        spatialIndexes: [
          {
            path: '/location/*'
            types: [
              'Point'
              'Polygon'
              'LineString'
            ]
          }
        ]
      }
    }
    options: {
      throughput: cosmosThroughput
    }
  }
}

// Azure Maps Account
resource mapsAccount 'Microsoft.Maps/accounts@2023-06-01' = {
  name: mapsAccountName
  location: 'global'
  tags: commonTags
  sku: {
    name: mapsSku
  }
  kind: 'Gen2'
  properties: {
    disableLocalAuth: false
    cors: {
      corsRules: [
        {
          allowedOrigins: [
            '*'
          ]
          allowedMethods: [
            'GET'
            'POST'
          ]
          allowedHeaders: [
            '*'
          ]
          maxAgeInSeconds: 86400
        }
      ]
    }
  }
}

// Stream Analytics Job
resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: streamAnalyticsJobName
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: streamAnalyticsSku
      capacity: streamAnalyticsStreamingUnits
    }
    outputErrorPolicy: 'Stop'
    eventsOutOfOrderPolicy: 'Adjust'
    eventsOutOfOrderMaxDelayInSeconds: 5
    eventsLateArrivalMaxDelayInSeconds: 16
    dataLocale: 'en-US'
    compatibilityLevel: '1.2'
    contentStoragePolicy: 'SystemAccount'
    jobType: 'Cloud'
  }
}

// Stream Analytics Input from Event Hub
resource streamAnalyticsInput 'Microsoft.StreamAnalytics/streamingjobs/inputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'VehicleInput'
  properties: {
    type: 'Stream'
    datasource: {
      type: 'Microsoft.EventHub/EventHub'
      properties: {
        eventHubName: eventHubName
        serviceBusNamespace: eventHubNamespaceName
        sharedAccessPolicyName: 'RootManageSharedAccessKey'
        sharedAccessPolicyKey: eventHubNamespaceAuthRule.listKeys().primaryKey
        consumerGroupName: eventHubConsumerGroup.name
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

// Stream Analytics Output to Cosmos DB
resource streamAnalyticsOutputCosmos 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'VehicleOutput'
  properties: {
    datasource: {
      type: 'Microsoft.Storage/DocumentDB'
      properties: {
        accountId: cosmosAccount.name
        accountKey: cosmosAccount.listKeys().primaryMasterKey
        database: cosmosDatabaseName
        collectionNamePattern: cosmosContainerName
        documentId: 'vehicleId'
        upsert: true
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

// Stream Analytics Output to Blob Storage for archival
resource streamAnalyticsOutputBlob 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'ArchiveOutput'
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
        container: telemetryArchiveContainer.name
        pathPattern: 'vehicles/{date}/{time}'
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

// Stream Analytics Transformation (Query)
resource streamAnalyticsTransformation 'Microsoft.StreamAnalytics/streamingjobs/transformations@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'GeospatialTransformation'
  properties: {
    streamingUnits: streamAnalyticsStreamingUnits
    query: '''
WITH GeofencedData AS (
    SELECT
        vehicleId,
        location,
        speed,
        System.Timestamp() AS timestamp,
        ST_WITHIN(
            CreatePoint(CAST(location.longitude AS float), 
                       CAST(location.latitude AS float)),
            CreatePolygon(
                CreatePoint(-122.135, 47.642),
                CreatePoint(-122.135, 47.658),
                CreatePoint(-122.112, 47.658),
                CreatePoint(-122.112, 47.642),
                CreatePoint(-122.135, 47.642)
            )
        ) AS isInZone,
        ST_DISTANCE(
            CreatePoint(CAST(location.longitude AS float), 
                       CAST(location.latitude AS float)),
            CreatePoint(-122.123, 47.650)
        ) AS distanceFromDepot
    FROM VehicleInput
)
SELECT
    vehicleId,
    location,
    speed,
    timestamp,
    isInZone,
    distanceFromDepot,
    CASE 
        WHEN speed > 80 THEN 'Speeding Alert'
        WHEN isInZone = 0 THEN 'Outside Geofence'
        ELSE 'Normal'
    END AS alertType
INTO VehicleOutput
FROM GeofencedData

SELECT
    vehicleId,
    location,
    speed,
    timestamp,
    isInZone,
    distanceFromDepot,
    alertType
INTO ArchiveOutput
FROM GeofencedData
'''
  }
}

// Action Group for monitoring alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: commonTags
  properties: {
    groupShortName: 'FleetOps'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    azureFunction: []
    logicAppReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    armRoleReceivers: []
    azureFunctionReceivers: []
    eventHubReceivers: []
  }
}

// Metric alert for Stream Analytics high latency
resource streamAnalyticsLatencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'high-processing-latency'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'Alert when Stream Analytics processing latency exceeds 10 seconds'
    severity: 2
    enabled: true
    scopes: [
      streamAnalyticsJob.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighLatency'
          metricName: 'OutputWatermarkDelaySeconds'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 10
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
  }
}

// Diagnostic settings for Stream Analytics
resource streamAnalyticsDiagnostics 'Microsoft.Insights/diagnosticsettings@2021-05-01-preview' = {
  name: 'asa-diagnostics'
  scope: streamAnalyticsJob
  properties: {
    storageAccountId: storageAccount.id
    logs: [
      {
        category: 'Execution'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'Authoring'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Outputs
@description('The name of the Event Hub namespace')
output eventHubNamespaceName string = eventHubNamespace.name

@description('The name of the Event Hub')
output eventHubName string = eventHub.name

@description('Event Hub connection string')
output eventHubConnectionString string = eventHubNamespaceAuthRule.listKeys().primaryConnectionString

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account primary key')
output storageAccountKey string = storageAccount.listKeys().keys[0].value

@description('Cosmos DB account name')
output cosmosAccountName string = cosmosAccount.name

@description('Cosmos DB primary key')
output cosmosAccountKey string = cosmosAccount.listKeys().primaryMasterKey

@description('Cosmos DB endpoint')
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint

@description('Azure Maps account name')
output mapsAccountName string = mapsAccount.name

@description('Azure Maps primary key')
output mapsAccountKey string = mapsAccount.listKeys().primaryKey

@description('Stream Analytics job name')
output streamAnalyticsJobName string = streamAnalyticsJob.name

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Primary location')
output location string = location

@description('Generated unique suffix')
output uniqueSuffix string = randomSuffix