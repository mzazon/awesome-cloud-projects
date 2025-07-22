// ============================================================================
// Main Bicep template for IoT Digital Twins Predictive Maintenance Solution
// ============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Base name for all resources')
param baseName string = 'iot-dt-${uniqueString(resourceGroup().id)}'

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Solution: 'IoT Digital Twins Predictive Maintenance'
  CreatedBy: 'Bicep Template'
  CreatedDate: utcNow('yyyy-MM-dd')
}

@description('Azure Digital Twins service name')
param digitalTwinsName string = 'adt-${baseName}'

@description('Azure Data Explorer cluster name')
param adxClusterName string = 'adx${replace(baseName, '-', '')}'

@description('Azure Data Explorer database name')
param adxDatabaseName string = 'iottelemetry'

@description('IoT Central application name')
param iotCentralAppName string = 'iotc-${baseName}'

@description('Function App name')
param functionAppName string = 'func-${baseName}'

@description('Storage account name')
param storageAccountName string = 'st${replace(baseName, '-', '')}'

@description('Event Hub namespace name')
param eventHubNamespaceName string = 'ehns-${baseName}'

@description('Event Hub name')
param eventHubName string = 'telemetry-hub'

@description('Time Series Insights environment name')
param tsiEnvironmentName string = 'tsi-${baseName}'

@description('Data Explorer cluster SKU')
@allowed(['Dev(No SLA)_Standard_E2a_v4', 'Standard_E2a_v4', 'Standard_E4a_v4'])
param adxClusterSku string = 'Dev(No SLA)_Standard_E2a_v4'

@description('Data Explorer cluster tier')
@allowed(['Basic', 'Standard'])
param adxClusterTier string = 'Basic'

@description('Data Explorer cluster capacity')
@minValue(1)
@maxValue(1000)
param adxClusterCapacity int = 1

@description('Event Hub SKU')
@allowed(['Basic', 'Standard'])
param eventHubSku string = 'Standard'

@description('Event Hub capacity')
@minValue(1)
@maxValue(20)
param eventHubCapacity int = 1

@description('Function App hosting plan SKU')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppSku string = 'Y1'

@description('Time Series Insights SKU')
@allowed(['L1'])
param tsiSku string = 'L1'

@description('IoT Central SKU')
@allowed(['ST0', 'ST1', 'ST2'])
param iotCentralSku string = 'ST2'

@description('IoT Central subdomain')
param iotCentralSubdomain string = iotCentralAppName

@description('IoT Central template')
param iotCentralTemplate string = 'iotc-pnp-preview'

// ============================================================================
// Variables
// ============================================================================

var eventHubAuthRuleName = 'RootManageSharedAccessKey'
var functionAppPlanName = 'asp-${baseName}'
var applicationInsightsName = 'ai-${baseName}'
var keyVaultName = 'kv-${replace(baseName, '-', '')}'
var logAnalyticsName = 'law-${baseName}'

// ============================================================================
// Resources
// ============================================================================

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
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
    }
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// Storage Account
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
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
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

// Key Vault
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
    enabledForDeployment: false
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Event Hub Namespace
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2023-01-01-preview' = {
  name: eventHubNamespaceName
  location: location
  tags: tags
  sku: {
    name: eventHubSku
    tier: eventHubSku
    capacity: eventHubCapacity
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: false
    maximumThroughputUnits: 0
    kafkaEnabled: false
  }
}

// Event Hub
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2023-01-01-preview' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: 1
    partitionCount: 4
    status: 'Active'
  }
}

// Event Hub Authorization Rule
resource eventHubAuthRule 'Microsoft.EventHub/namespaces/AuthorizationRules@2023-01-01-preview' = {
  parent: eventHubNamespace
  name: eventHubAuthRuleName
  properties: {
    rights: [
      'Listen'
      'Manage'
      'Send'
    ]
  }
}

// Azure Digital Twins
resource digitalTwins 'Microsoft.DigitalTwins/digitalTwinsInstances@2023-01-31' = {
  name: digitalTwinsName
  location: location
  tags: tags
  properties: {
    publicNetworkAccess: 'Enabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Digital Twins Event Hub Endpoint
resource digitalTwinsEndpoint 'Microsoft.DigitalTwins/digitalTwinsInstances/endpoints@2023-01-31' = {
  parent: digitalTwins
  name: 'telemetry-endpoint'
  properties: {
    endpointType: 'EventHub'
    connectionStringPrimaryKey: eventHubAuthRule.listKeys().primaryConnectionString
    connectionStringSecondaryKey: eventHubAuthRule.listKeys().secondaryConnectionString
  }
}

// Digital Twins Event Route
resource digitalTwinsRoute 'Microsoft.DigitalTwins/digitalTwinsInstances/eventRoutes@2023-01-31' = {
  parent: digitalTwins
  name: 'telemetry-route'
  properties: {
    endpointName: digitalTwinsEndpoint.name
    filter: 'type = \'Microsoft.DigitalTwins.Twin.Update\''
  }
}

// Function App Hosting Plan
resource functionAppPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: functionAppPlanName
  location: location
  tags: tags
  sku: {
    name: functionAppSku
    tier: functionAppSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  kind: 'functionapp'
  properties: {
    reserved: false
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionAppPlan.id
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
          value: 'dotnet'
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
          name: 'ADT_SERVICE_URL'
          value: 'https://${digitalTwins.properties.hostName}'
        }
        {
          name: 'EventHubConnection'
          value: eventHubAuthRule.listKeys().primaryConnectionString
        }
      ]
      netFrameworkVersion: 'v6.0'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      httpsOnly: true
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

// Azure Data Explorer Cluster
resource adxCluster 'Microsoft.Kusto/clusters@2023-08-15' = {
  name: adxClusterName
  location: location
  tags: tags
  sku: {
    name: adxClusterSku
    tier: adxClusterTier
    capacity: adxClusterCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    optimizedAutoscale: {
      version: 1
      isEnabled: false
    }
    enableDiskEncryption: false
    enableStreamingIngest: true
    enablePurge: true
    enableDoubleEncryption: false
    engineType: 'V3'
    acceptedAudiences: []
    enableAutoStop: true
    restrictOutboundNetworkAccess: 'Disabled'
    allowedFqdnList: []
    publicNetworkAccess: 'Enabled'
    publicIPType: 'IPv4'
    virtualNetworkConfiguration: {
      subnetId: ''
      enginePublicIpId: ''
      dataManagementPublicIpId: ''
    }
  }
}

// Azure Data Explorer Database
resource adxDatabase 'Microsoft.Kusto/clusters/databases@2023-08-15' = {
  parent: adxCluster
  name: adxDatabaseName
  location: location
  kind: 'ReadWrite'
  properties: {
    softDeletePeriod: 'P30D'
    hotCachePeriod: 'P7D'
  }
}

// Azure Data Explorer Data Connection
resource adxDataConnection 'Microsoft.Kusto/clusters/databases/dataConnections@2023-08-15' = {
  parent: adxDatabase
  name: 'iot-telemetry-connection'
  location: location
  kind: 'EventHub'
  properties: {
    eventHubResourceId: eventHub.id
    consumerGroup: '$Default'
    tableName: 'TelemetryData'
    mappingRuleName: 'TelemetryMapping'
    dataFormat: 'JSON'
    eventSystemProperties: []
    compression: 'None'
  }
}

// Time Series Insights Environment
resource tsiEnvironment 'Microsoft.TimeSeriesInsights/environments@2020-05-15' = {
  name: tsiEnvironmentName
  location: location
  tags: tags
  sku: {
    name: tsiSku
    capacity: 1
  }
  kind: 'Gen2'
  properties: {
    storageConfiguration: {
      accountName: storageAccount.name
      managementKey: storageAccount.listKeys().keys[0].value
    }
    timeSeriesIdProperties: [
      {
        name: 'deviceId'
        type: 'String'
      }
    ]
    warmStoreConfiguration: {
      dataRetention: 'P7D'
    }
  }
}

// IoT Central Application
resource iotCentralApp 'Microsoft.IoTCentral/iotApps@2021-11-01-preview' = {
  name: iotCentralAppName
  location: location
  tags: tags
  sku: {
    name: iotCentralSku
  }
  properties: {
    displayName: iotCentralAppName
    subdomain: iotCentralSubdomain
    template: iotCentralTemplate
    state: 'created'
    publicNetworkAccess: 'Enabled'
  }
}

// ============================================================================
// RBAC Assignments
// ============================================================================

// Digital Twins Data Owner role for Function App
resource digitalTwinsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: digitalTwins
  name: guid(digitalTwins.id, functionApp.id, 'bcd981a7-7f74-457b-83e1-cceb9e632ffe')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'bcd981a7-7f74-457b-83e1-cceb9e632ffe') // Azure Digital Twins Data Owner
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Event Hub Data Receiver role for ADX
resource eventHubRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: eventHub
  name: guid(eventHub.id, adxCluster.id, 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde') // Azure Event Hubs Data Receiver
    principalId: adxCluster.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Data Contributor role for Function App
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The location of the deployed resources')
output location string = location

@description('The name of the Azure Digital Twins instance')
output digitalTwinsName string = digitalTwins.name

@description('The hostname of the Azure Digital Twins instance')
output digitalTwinsHostName string = digitalTwins.properties.hostName

@description('The service URL of the Azure Digital Twins instance')
output digitalTwinsServiceUrl string = 'https://${digitalTwins.properties.hostName}'

@description('The name of the Azure Data Explorer cluster')
output adxClusterName string = adxCluster.name

@description('The URI of the Azure Data Explorer cluster')
output adxClusterUri string = adxCluster.properties.uri

@description('The name of the Azure Data Explorer database')
output adxDatabaseName string = adxDatabase.name

@description('The name of the IoT Central application')
output iotCentralAppName string = iotCentralApp.name

@description('The URL of the IoT Central application')
output iotCentralAppUrl string = 'https://${iotCentralApp.properties.subdomain}.azureiotcentral.com'

@description('The application ID of the IoT Central application')
output iotCentralAppId string = iotCentralApp.properties.applicationId

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The URL of the Function App')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the Event Hub namespace')
output eventHubNamespaceName string = eventHubNamespace.name

@description('The name of the Event Hub')
output eventHubName string = eventHub.name

@description('The primary connection string for the Event Hub')
output eventHubConnectionString string = eventHubAuthRule.listKeys().primaryConnectionString

@description('The name of the Time Series Insights environment')
output tsiEnvironmentName string = tsiEnvironment.name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The name of the Application Insights instance')
output applicationInsightsName string = applicationInsights.name

@description('The instrumentation key for Application Insights')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The URI of the Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalytics.name

@description('Summary of all deployed resources')
output deploymentSummary object = {
  digitalTwins: {
    name: digitalTwins.name
    serviceUrl: 'https://${digitalTwins.properties.hostName}'
  }
  dataExplorer: {
    name: adxCluster.name
    uri: adxCluster.properties.uri
    database: adxDatabase.name
  }
  iotCentral: {
    name: iotCentralApp.name
    url: 'https://${iotCentralApp.properties.subdomain}.azureiotcentral.com'
    appId: iotCentralApp.properties.applicationId
  }
  functionApp: {
    name: functionApp.name
    url: 'https://${functionApp.properties.defaultHostName}'
  }
  eventHub: {
    namespace: eventHubNamespace.name
    hubName: eventHub.name
  }
  timeSeriesInsights: {
    name: tsiEnvironment.name
  }
  monitoring: {
    applicationInsights: applicationInsights.name
    logAnalytics: logAnalytics.name
  }
}