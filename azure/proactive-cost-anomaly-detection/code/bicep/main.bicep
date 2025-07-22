// =============================================================================
// Azure Cost Anomaly Detection Solution
// Bicep Template for Automated Cost Monitoring with Azure Functions
// =============================================================================

targetScope = 'resourceGroup'

// =============================================================================
// Parameters
// =============================================================================

@description('The primary location for resource deployment')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'centralus'
  'northcentralus'
  'southcentralus'
  'westcentralus'
  'canadacentral'
  'canadaeast'
  'brazilsouth'
  'northeurope'
  'westeurope'
  'uksouth'
  'ukwest'
  'francecentral'
  'francesouth'
  'germanywestcentral'
  'switzerlandnorth'
  'norwayeast'
  'uaenorth'
  'southafricanorth'
  'australiaeast'
  'australiasoutheast'
  'southeastasia'
  'eastasia'
  'japaneast'
  'japanwest'
  'koreacentral'
  'koreasouth'
  'centralindia'
  'southindia'
  'westindia'
])
param location string = 'eastus'

@description('Environment name (dev, staging, prod)')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Application name used for resource naming')
@minLength(3)
@maxLength(12)
param appName string = 'costanomaly'

@description('Random suffix for unique resource names')
@minLength(3)
@maxLength(8)
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Subscription ID to monitor for cost anomalies')
param subscriptionId string = subscription().subscriptionId

@description('Anomaly detection threshold percentage')
@minValue(5)
@maxValue(100)
param anomalyThreshold int = 20

@description('Number of days to look back for baseline calculation')
@minValue(7)
@maxValue(90)
param lookbackDays int = 30

@description('Email address for anomaly notifications')
param notificationEmail string = 'admin@company.com'

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Enable Logic Apps for automated notifications')
param enableLogicApps bool = true

@description('Cosmos DB throughput provisioning (manual or autoscale)')
@allowed([
  'manual'
  'autoscale'
])
param cosmosDbThroughputType string = 'manual'

@description('Cosmos DB manual throughput RU/s')
@minValue(400)
@maxValue(4000)
param cosmosDbManualThroughput int = 400

@description('Cosmos DB autoscale max throughput RU/s')
@minValue(400)
@maxValue(40000)
param cosmosDbAutoscaleMaxThroughput int = 4000

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'cost-anomaly-detection'
  Owner: 'platform-team'
}

// =============================================================================
// Variables
// =============================================================================

var resourcePrefix = '${appName}-${environment}'
var storageAccountName = '${replace(resourcePrefix, '-', '')}sa${uniqueSuffix}'
var functionAppName = '${resourcePrefix}-func-${uniqueSuffix}'
var cosmosAccountName = '${resourcePrefix}-cosmos-${uniqueSuffix}'
var logicAppName = '${resourcePrefix}-logic-${uniqueSuffix}'
var appInsightsName = '${resourcePrefix}-ai-${uniqueSuffix}'
var hostingPlanName = '${resourcePrefix}-plan-${uniqueSuffix}'

// Cosmos DB configuration
var cosmosDbDatabaseName = 'CostAnalytics'
var cosmosDbContainers = [
  {
    name: 'DailyCosts'
    partitionKey: '/date'
  }
  {
    name: 'AnomalyResults'
    partitionKey: '/subscriptionId'
  }
]

// Function app configuration
var functionAppSettings = [
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
    value: 'python'
  }
  {
    name: 'COSMOS_ENDPOINT'
    value: cosmosAccount.properties.documentEndpoint
  }
  {
    name: 'COSMOS_CONNECTION'
    value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
  }
  {
    name: 'SUBSCRIPTION_ID'
    value: subscriptionId
  }
  {
    name: 'ANOMALY_THRESHOLD'
    value: string(anomalyThreshold)
  }
  {
    name: 'LOOKBACK_DAYS'
    value: string(lookbackDays)
  }
  {
    name: 'NOTIFICATION_EMAIL'
    value: notificationEmail
  }
  {
    name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
    value: enableApplicationInsights ? appInsights.properties.InstrumentationKey : ''
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: enableApplicationInsights ? appInsights.properties.ConnectionString : ''
  }
]

// =============================================================================
// Resources
// =============================================================================

// Storage Account for Azure Functions
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    accessTier: 'Hot'
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
  tags: tags
}

// Cosmos DB Account
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' = {
  name: cosmosAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
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
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Local'
      }
    }
    networkAclBypass: 'AzureServices'
    publicNetworkAccess: 'Enabled'
    enableFreeTier: false
    enableAnalyticalStorage: false
    analyticalStorageConfiguration: {
      schemaType: 'WellDefined'
    }
    minimalTlsVersion: 'Tls12'
    capacity: {
      totalThroughputLimit: 4000
    }
  }
  tags: tags
}

// Cosmos DB Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-12-01-preview' = {
  parent: cosmosAccount
  name: cosmosDbDatabaseName
  properties: {
    resource: {
      id: cosmosDbDatabaseName
    }
  }
}

// Cosmos DB Containers
resource cosmosContainers 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-12-01-preview' = [for container in cosmosDbContainers: {
  parent: cosmosDatabase
  name: container.name
  properties: {
    resource: {
      id: container.name
      partitionKey: {
        paths: [
          container.partitionKey
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
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
      }
      defaultTtl: -1
    }
  }
}]

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: tags
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableApplicationInsights) {
  name: '${resourcePrefix}-log-${uniqueSuffix}'
  location: location
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
  tags: tags
}

// App Service Plan for Functions
resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: hostingPlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
  tags: tags
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    reserved: true
    siteConfig: {
      appSettings: functionAppSettings
      linuxFxVersion: 'Python|3.11'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      functionAppScaleLimit: 10
      minimumElasticInstanceCount: 0
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
  tags: tags
  dependsOn: [
    storageAccount
    cosmosAccount
    appInsights
  ]
}

// Logic App for Notifications
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = if (enableLogicApps) {
  name: logicAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'When_a_HTTP_request_is_received': {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                subscriptionId: {
                  type: 'string'
                }
                serviceName: {
                  type: 'string'
                }
                resourceGroupName: {
                  type: 'string'
                }
                currentCost: {
                  type: 'number'
                }
                baselineCost: {
                  type: 'number'
                }
                percentageChange: {
                  type: 'number'
                }
                anomalyType: {
                  type: 'string'
                }
                severity: {
                  type: 'string'
                }
                date: {
                  type: 'string'
                }
              }
            }
          }
        }
      }
      actions: {
        'Send_an_email_(V2)': {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            body: {
              To: notificationEmail
              Subject: 'Cost Anomaly Alert - @{triggerBody()?[\'severity\']} Severity'
              Body: '<p><strong>Cost Anomaly Detected</strong></p><p><strong>Date:</strong> @{triggerBody()?[\'date\']}</p><p><strong>Subscription:</strong> @{triggerBody()?[\'subscriptionId\']}</p><p><strong>Service:</strong> @{triggerBody()?[\'serviceName\']}</p><p><strong>Resource Group:</strong> @{triggerBody()?[\'resourceGroupName\']}</p><p><strong>Current Cost:</strong> $@{triggerBody()?[\'currentCost\']}</p><p><strong>Baseline Cost:</strong> $@{triggerBody()?[\'baselineCost\']}</p><p><strong>Change:</strong> @{triggerBody()?[\'percentageChange\']}%</p><p><strong>Type:</strong> @{triggerBody()?[\'anomalyType\']}</p><p><strong>Severity:</strong> @{triggerBody()?[\'severity\']}</p><p>Please investigate this cost anomaly and take appropriate action.</p>'
              Importance: 'High'
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v2/Mail'
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          office365: {
            connectionId: office365Connection.id
            connectionName: 'office365'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
          }
        }
      }
    }
  }
  tags: tags
}

// Office 365 Connection for Logic Apps
resource office365Connection 'Microsoft.Web/connections@2016-06-01' = if (enableLogicApps) {
  name: '${resourcePrefix}-office365-${uniqueSuffix}'
  location: location
  properties: {
    displayName: 'Office 365 Outlook'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'office365')
    }
    parameterValues: {}
  }
  tags: tags
}

// =============================================================================
// Role Assignments
// =============================================================================

// Cosmos DB Data Contributor role for Function App
resource cosmosDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cosmosAccount
  name: guid(cosmosAccount.id, functionApp.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Cost Management Reader role for Function App
resource costManagementReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, functionApp.id, '72fafb9e-0641-4937-9268-a91bfd8191a3')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '72fafb9e-0641-4937-9268-a91bfd8191a3')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Reader role for Function App (for accessing subscription-level resources)
resource readerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, functionApp.id, 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The URL of the Function App')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the Cosmos DB account')
output cosmosDbAccountName string = cosmosAccount.name

@description('The endpoint of the Cosmos DB account')
output cosmosDbEndpoint string = cosmosAccount.properties.documentEndpoint

@description('The name of the Logic App')
output logicAppName string = enableLogicApps ? logicApp.name : ''

@description('The URL of the Logic App trigger')
output logicAppTriggerUrl string = enableLogicApps ? listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicApp.name, 'When_a_HTTP_request_is_received'), '2019-05-01').value : ''

@description('The name of the Storage Account')
output storageAccountName string = storageAccount.name

@description('The Application Insights Instrumentation Key')
output appInsightsInstrumentationKey string = enableApplicationInsights ? appInsights.properties.InstrumentationKey : ''

@description('The Application Insights Connection String')
output appInsightsConnectionString string = enableApplicationInsights ? appInsights.properties.ConnectionString : ''

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('The Function App principal ID for additional role assignments')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('Configuration summary')
output configurationSummary object = {
  subscriptionId: subscriptionId
  anomalyThreshold: anomalyThreshold
  lookbackDays: lookbackDays
  notificationEmail: notificationEmail
  enableApplicationInsights: enableApplicationInsights
  enableLogicApps: enableLogicApps
  cosmosDbThroughputType: cosmosDbThroughputType
  environment: environment
  location: location
}