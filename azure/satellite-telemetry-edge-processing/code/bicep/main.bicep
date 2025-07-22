// =============================================================================
// Azure Orbital and Azure Local Edge-to-Orbit Data Processing
// =============================================================================
// This template deploys a comprehensive edge-to-orbit data processing pipeline
// using Azure Orbital Ground Station Service and Azure Local edge computing.
//
// Architecture Components:
// - Azure IoT Hub for satellite telemetry ingestion
// - Azure Event Grid for event-driven orchestration
// - Azure Storage for satellite data archival
// - Azure Orbital spacecraft and contact profiles
// - Azure Local (Azure Stack HCI) for edge processing
// - Azure Functions for serverless data processing
// - Azure Monitor for operational observability
// - Power BI for mission control dashboards
// =============================================================================

targetScope = 'resourceGroup'

// =============================================================================
// PARAMETERS
// =============================================================================

@description('The base name for all resources. This will be used to generate unique names.')
@minLength(3)
@maxLength(10)
param baseName string = 'orbital'

@description('The Azure region where resources will be deployed.')
param location string = resourceGroup().location

@description('Environment type for resource tagging and configuration.')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'prod'

@description('Mission type for satellite operations.')
@allowed(['earth-observation', 'communications', 'weather', 'research'])
param missionType string = 'earth-observation'

@description('Satellite NORAD ID for orbital tracking.')
param satelliteNoradId string = '12345'

@description('Satellite name for identification.')
param satelliteName string = 'earth-obs-sat'

@description('Two-Line Element (TLE) Line 1 for orbital parameters.')
param tleLine1 string = '1 25544U 98067A   08264.51782528 -.00002182  00000-0 -11606-4 0  2927'

@description('Two-Line Element (TLE) Line 2 for orbital parameters.')
param tleLine2 string = '2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.72125391563537'

@description('IoT Hub pricing tier and capacity.')
@allowed(['S1', 'S2', 'S3'])
param iotHubSku string = 'S2'

@description('Number of IoT Hub units.')
@minValue(1)
@maxValue(200)
param iotHubUnits int = 2

@description('Number of Event Hub partitions for high-throughput telemetry.')
@minValue(2)
@maxValue(32)
param eventHubPartitionCount int = 8

@description('Storage account performance tier.')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Premium_LRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Storage access tier for satellite data.')
@allowed(['Hot', 'Cool'])
param storageAccessTier string = 'Hot'

@description('Function App hosting plan SKU.')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppSku string = 'Y1'

@description('Log Analytics workspace retention in days.')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 90

@description('Enable Azure Local (Azure Stack HCI) resources.')
param enableAzureLocal bool = true

@description('Azure Local cluster node count.')
@minValue(2)
@maxValue(16)
param azureLocalNodeCount int = 3

@description('Satellite communication frequency in MHz.')
@minValue(1000)
@maxValue(30000)
param communicationFrequencyMhz int = 2250

@description('Satellite communication bandwidth in MHz.')
@minValue(1)
@maxValue(500)
param communicationBandwidthMhz int = 15

@description('Ground station minimum elevation angle in degrees.')
@minValue(0)
@maxValue(90)
param minimumElevationDegrees int = 5

@description('Minimum viable contact duration in minutes.')
@minValue(5)
@maxValue(120)
param minimumContactDurationMinutes int = 10

@description('Resource tags for organization and billing.')
param resourceTags object = {}

// =============================================================================
// VARIABLES
// =============================================================================

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var commonTags = union(resourceTags, {
  Environment: environment
  Mission: missionType
  Solution: 'orbital-edge-processing'
  DeployedBy: 'bicep-template'
  DeployedOn: utcNow('yyyy-MM-dd')
})

// Resource naming with unique suffix
var iotHubName = 'iot-${baseName}-${uniqueSuffix}'
var eventGridTopicName = 'orbital-events-${uniqueSuffix}'
var storageAccountName = 'stor${baseName}${uniqueSuffix}'
var functionAppName = 'func-${baseName}-${uniqueSuffix}'
var appServicePlanName = 'asp-${baseName}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-${baseName}-${uniqueSuffix}'
var applicationInsightsName = 'ai-${baseName}-${uniqueSuffix}'
var spacecraftName = '${satelliteName}-${uniqueSuffix}'
var contactProfileName = '${missionType}-profile-${uniqueSuffix}'
var azureLocalClusterName = 'azlocal-${baseName}-${uniqueSuffix}'
var arcK8sClusterName = '${azureLocalClusterName}-k8s'

// Configuration constants
var iotHubConsumerGroups = [
  'orbital-processing'
  'data-archive'
  'real-time-analytics'
  'mission-control'
]

var storageContainers = [
  'satellite-telemetry'
  'processed-imagery'
  'mission-logs'
  'backup-data'
]

var eventGridEventTypes = [
  'Microsoft.Devices.DeviceTelemetry'
  'Microsoft.Devices.DeviceConnected'
  'Microsoft.Devices.DeviceDisconnected'
  'Microsoft.Orbital.SatelliteContact'
]

// =============================================================================
// RESOURCES
// =============================================================================

// Log Analytics Workspace - Foundation for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    workspaceCapping: {
      dailyQuotaGb: 10
    }
  }
}

// Application Insights for Function App monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for satellite data archival
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: storageAccessTier
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    isHnsEnabled: true // Enable hierarchical namespace for Data Lake
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
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

// Storage containers for different data types
resource storageContainerResources 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for containerName in storageContainers: {
  name: '${storageAccount.name}/default/${containerName}'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'satellite-data'
      environment: environment
    }
  }
}]

// IoT Hub for satellite telemetry ingestion
resource iotHub 'Microsoft.Devices/IotHubs@2023-06-30' = {
  name: iotHubName
  location: location
  tags: commonTags
  sku: {
    name: iotHubSku
    capacity: iotHubUnits
  }
  properties: {
    eventHubEndpoints: {
      events: {
        retentionTimeInDays: 7
        partitionCount: eventHubPartitionCount
      }
    }
    routing: {
      endpoints: {
        storageContainers: [
          {
            name: 'satellite-telemetry-storage'
            resourceGroup: resourceGroup().name
            subscriptionId: subscription().subscriptionId
            containerName: 'satellite-telemetry'
            connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
            fileNameFormat: '{iothub}/{partition}/{YYYY}/{MM}/{DD}/{HH}/{mm}'
            batchFrequencyInSeconds: 300
            maxChunkSizeInBytes: 104857600
            encoding: 'JSON'
          }
        ]
      }
      routes: [
        {
          name: 'satellite-telemetry-route'
          source: 'DeviceMessages'
          condition: 'satellite = "active"'
          endpointNames: [
            'satellite-telemetry-storage'
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
    disableLocalAuth: false
    enableFileUploadNotifications: true
    messagingEndpoints: {
      fileNotifications: {
        lockDurationAsIso8601: 'PT1M'
        ttlAsIso8601: 'PT1H'
        maxDeliveryCount: 10
      }
    }
  }
}

// Consumer groups for IoT Hub
resource iotHubConsumerGroupResources 'Microsoft.Devices/IotHubs/eventHubEndpoints/ConsumerGroups@2023-06-30' = [for consumerGroup in iotHubConsumerGroups: {
  name: '${iotHub.name}/events/${consumerGroup}'
  properties: {
    name: consumerGroup
  }
}]

// Event Grid Topic for orbital event orchestration
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: commonTags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    dataResidencyBoundary: 'WithinGeopair'
  }
}

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: commonTags
  sku: {
    name: functionAppSku
    tier: functionAppSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  properties: {
    reserved: true // Linux hosting
  }
}

// Function App for serverless satellite data processing
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: commonTags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
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
          name: 'IOT_HUB_CONNECTION_STRING'
          value: 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=iothubowner;SharedAccessKey=${iotHub.listKeys().value[0].primaryKey}'
        }
        {
          name: 'EVENT_GRID_ENDPOINT'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EVENT_GRID_KEY'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'SATELLITE_NAME'
          value: spacecraftName
        }
        {
          name: 'MISSION_TYPE'
          value: missionType
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      httpLoggingEnabled: true
      logsDirectorySizeLimit: 35
      detailedErrorLoggingEnabled: true
      publishingUsername: '$${functionAppName}'
      scmType: 'None'
      netFrameworkVersion: 'v6.0'
      phpVersion: 'OFF'
      requestTracingEnabled: true
      remoteDebuggingEnabled: false
      httpLoggingEnabled: true
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      preWarmedInstanceCount: 0
      functionAppScaleLimit: 200
      functionsRuntimeScaleMonitoringEnabled: false
      minimumElasticInstanceCount: 0
      azureStorageAccounts: {}
    }
    httpsOnly: true
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Azure Orbital Spacecraft registration
resource spacecraft 'Microsoft.Orbital/spacecrafts@2023-04-01' = {
  name: spacecraftName
  location: location
  tags: commonTags
  properties: {
    noradId: satelliteNoradId
    titleLine: '${satelliteName} - ${missionType}'
    tleLine1: tleLine1
    tleLine2: tleLine2
    links: [
      {
        name: 'downlink'
        centerFrequencyMHz: communicationFrequencyMhz
        bandwidthMHz: communicationBandwidthMhz
        direction: 'Downlink'
        polarization: 'LHCP'
        authorizations: [
          {
            groundStation: 'Microsoft_Quincy'
            expirationDate: dateTimeAdd(utcNow(), 'P1Y')
          }
        ]
      }
    ]
  }
}

// Contact Profile for satellite communication
resource contactProfile 'Microsoft.Orbital/contactProfiles@2023-04-01' = {
  name: contactProfileName
  location: location
  tags: commonTags
  properties: {
    minimumViableContactDuration: 'PT${minimumContactDurationMinutes}M'
    minimumElevationDegrees: minimumElevationDegrees
    autoTrackingConfiguration: 'xBand'
    eventHubUri: '${iotHub.properties.eventHubEndpoints.events.endpoint}'
    networkConfiguration: {
      subnetId: ''
    }
    links: [
      {
        name: 'downlink'
        channels: [
          {
            name: 'telemetry-channel'
            centerFrequencyMHz: communicationFrequencyMhz
            bandwidthMHz: communicationBandwidthMhz
            endPoint: {
              endPointName: 'satellite-telemetry-endpoint'
              ipAddress: '10.0.0.4'
              port: '55555'
              protocol: 'TCP'
            }
            modulationConfiguration: {
              modulationType: 'QPSK'
              codingRate: '7/8'
            }
            demodulationConfiguration: {
              modulationType: 'QPSK'
              codingRate: '7/8'
            }
          }
        ]
        direction: 'Downlink'
        gainOverTemperature: 25.0
        eirpDbw: 45.0
        polarization: 'LHCP'
      }
    ]
  }
}

// Azure Local (Azure Stack HCI) cluster - conditional deployment
resource azureLocalCluster 'Microsoft.AzureStackHCI/clusters@2023-11-01-preview' = if (enableAzureLocal) {
  name: azureLocalClusterName
  location: location
  tags: commonTags
  properties: {
    aadClientId: '00000000-0000-0000-0000-000000000000'
    aadTenantId: subscription().tenantId
    cloudManagementEndpoint: 'https://management.azure.com/'
    desiredProperties: {
      windowsServerSubscription: 'Enabled'
      diagnosticLevel: 'Basic'
    }
  }
}

// Arc-enabled Kubernetes cluster for Azure Local
resource arcK8sCluster 'Microsoft.Kubernetes/connectedClusters@2024-01-01' = if (enableAzureLocal) {
  name: arcK8sClusterName
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    agentPublicKeyCertificate: ''
    kubernetesVersion: '1.28.0'
    totalNodeCount: azureLocalNodeCount
    totalCoreCount: azureLocalNodeCount * 4
    agentVersion: '1.18.0'
    distribution: 'AKS_HCI'
    infrastructure: 'azure_stack_hci'
    provisioningState: 'Succeeded'
    connectivityStatus: 'Connected'
    lastConnectivityTime: utcNow()
    managedIdentityCertificateExpirationTime: dateTimeAdd(utcNow(), 'P1Y')
  }
}

// Event Grid subscription for IoT Hub integration
resource eventGridSubscription 'Microsoft.EventGrid/eventSubscriptions@2023-12-15-preview' = {
  name: 'iot-orbital-subscription'
  scope: iotHub
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: eventGridTopic.properties.endpoint
        deliveryAttributeMappings: [
          {
            name: 'source'
            type: 'Static'
            properties: {
              value: 'iot-hub'
            }
          }
        ]
      }
    }
    filter: {
      includedEventTypes: eventGridEventTypes
      subjectBeginsWith: 'satellite/'
      isSubjectCaseSensitive: false
    }
    labels: [
      'orbital'
      'telemetry-routing'
    ]
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
    deadLetterDestination: {
      endpointType: 'StorageBlob'
      properties: {
        resourceId: storageAccount.id
        blobContainerName: 'satellite-telemetry'
      }
    }
  }
}

// Diagnostic settings for IoT Hub
resource iotHubDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'orbital-diagnostics'
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

// Alert rule for satellite communication failures
resource satelliteConnectionAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'satellite-connection-failure'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'Alert when satellite connection failures exceed threshold'
    severity: 2
    enabled: true
    scopes: [
      iotHub.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ConnectionFailures'
          metricName: 'c2d.commands.egress.abandon.success'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Count'
          skipMetricValidation: false
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.Devices/IotHubs'
    targetResourceRegion: location
    actions: []
  }
}

// Power BI workspace for mission control dashboard
resource powerBIWorkspace 'Microsoft.PowerBI/workspaceCollections@2016-01-29' = {
  name: 'orbital-dashboard-${uniqueSuffix}'
  location: location
  tags: commonTags
  sku: {
    name: 'S1'
    tier: 'Standard'
  }
  properties: {}
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('The name of the created resource group.')
output resourceGroupName string = resourceGroup().name

@description('The name of the IoT Hub.')
output iotHubName string = iotHub.name

@description('The IoT Hub hostname.')
output iotHubHostname string = iotHub.properties.hostName

@description('The IoT Hub connection string.')
@secure()
output iotHubConnectionString string = 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=iothubowner;SharedAccessKey=${iotHub.listKeys().value[0].primaryKey}'

@description('The Event Grid topic name.')
output eventGridTopicName string = eventGridTopic.name

@description('The Event Grid topic endpoint.')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('The Event Grid topic access key.')
@secure()
output eventGridTopicKey string = eventGridTopic.listKeys().key1

@description('The storage account name.')
output storageAccountName string = storageAccount.name

@description('The storage account primary endpoint.')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The storage account connection string.')
@secure()
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('The Function App name.')
output functionAppName string = functionApp.name

@description('The Function App default hostname.')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The spacecraft name.')
output spacecraftName string = spacecraft.name

@description('The contact profile name.')
output contactProfileName string = contactProfile.name

@description('The Azure Local cluster name.')
output azureLocalClusterName string = enableAzureLocal ? azureLocalCluster.name : ''

@description('The Arc-enabled Kubernetes cluster name.')
output arcK8sClusterName string = enableAzureLocal ? arcK8sCluster.name : ''

@description('The Log Analytics workspace name.')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The Log Analytics workspace ID.')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The Application Insights name.')
output applicationInsightsName string = applicationInsights.name

@description('The Application Insights instrumentation key.')
@secure()
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The Application Insights connection string.')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The Power BI workspace name.')
output powerBIWorkspaceName string = powerBIWorkspace.name

@description('Deployment summary with key information.')
output deploymentSummary object = {
  resourceGroupName: resourceGroup().name
  location: location
  environment: environment
  missionType: missionType
  satelliteName: spacecraftName
  iotHubName: iotHub.name
  storageAccountName: storageAccount.name
  functionAppName: functionApp.name
  eventGridTopicName: eventGridTopic.name
  azureLocalEnabled: enableAzureLocal
  deploymentTimestamp: utcNow()
  estimatedMonthlyCost: 'Contact Microsoft for pricing estimates'
  nextSteps: [
    'Configure satellite TLE data with actual orbital parameters'
    'Deploy satellite processing workload to Azure Local'
    'Schedule satellite contacts using Azure Orbital'
    'Configure Power BI dashboard with mission control metrics'
    'Set up automated satellite contact scheduling'
  ]
}