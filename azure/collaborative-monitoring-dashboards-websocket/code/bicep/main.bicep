@description('Name of the resource group')
param resourceGroupName string = 'rg-collab-dashboard'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment tag for resource organization')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Log Analytics workspace retention in days')
@minValue(7)
@maxValue(730)
param logRetentionDays int = 30

@description('Web PubSub service tier')
@allowed([
  'Free_F1'
  'Standard_S1'
  'Premium_P1'
])
param webPubSubSku string = 'Free_F1'

@description('Web PubSub unit count')
@minValue(1)
@maxValue(100)
param webPubSubUnits int = 1

@description('Function App runtime stack')
@allowed([
  'node'
  'dotnet'
  'python'
])
param functionAppRuntime string = 'node'

@description('Function App runtime version')
param functionAppRuntimeVersion string = '18'

@description('Static Web App SKU')
@allowed([
  'Free'
  'Standard'
])
param staticWebAppSku string = 'Free'

// Variables for resource naming
var webPubSubName = 'wps-dashboard-${uniqueSuffix}'
var staticAppName = 'swa-dashboard-${uniqueSuffix}'
var functionAppName = 'func-dashboard-${uniqueSuffix}'
var storageName = 'stdashboard${uniqueSuffix}'
var appInsightsName = 'appi-dashboard-${uniqueSuffix}'
var logAnalyticsName = 'log-dashboard-${uniqueSuffix}'
var appServicePlanName = 'asp-dashboard-${uniqueSuffix}'

// Common tags for all resources
var commonTags = {
  purpose: 'collab-dashboard'
  environment: environment
  'last-updated': '2025-07-12'
  'managed-by': 'bicep'
}

// Log Analytics Workspace - Foundation for centralized monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
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
      dailyQuotaGb: 5
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights - Deep application performance monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    DisableIpMasking: false
    DisableLocalAuth: false
  }
}

// Storage Account - Required for Function App and state management
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageName
  location: location
  tags: commonTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: false
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// CORS configuration for Storage Account to enable Static Web Apps integration
resource storageAccountBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: [
            '*'
          ]
          allowedMethods: [
            'GET'
            'POST'
            'PUT'
          ]
          allowedHeaders: [
            '*'
          ]
          exposedHeaders: [
            '*'
          ]
          maxAgeInSeconds: 86400
        }
      ]
    }
  }
}

// Azure Web PubSub - Serverless WebSocket connections at scale
resource webPubSubService 'Microsoft.SignalRService/webPubSub@2023-02-01' = {
  name: webPubSubName
  location: location
  tags: commonTags
  sku: {
    name: webPubSubSku
    capacity: webPubSubUnits
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    disableAadAuth: false
    disableLocalAuth: false
    liveTraceConfiguration: {
      enabled: true
      categories: [
        {
          name: 'ConnectivityLogs'
          enabled: true
        }
        {
          name: 'MessagingLogs'
          enabled: true
        }
      ]
    }
    networkACLs: {
      defaultAction: 'Allow'
      publicNetwork: {
        allow: [
          'ServerConnection'
          'ClientConnection'
          'RESTAPI'
          'Trace'
        ]
      }
    }
    publicNetworkAccess: 'Enabled'
    resourceLogConfiguration: {
      categories: [
        {
          name: 'ConnectivityLogs'
          enabled: true
        }
        {
          name: 'MessagingLogs'
          enabled: true
        }
      ]
    }
  }
}

// Web PubSub Hub Configuration for dashboard communication
resource webPubSubHub 'Microsoft.SignalRService/webPubSub/hubs@2023-02-01' = {
  parent: webPubSubService
  name: 'dashboard'
  properties: {
    eventHandlers: [
      {
        urlTemplate: 'https://${functionAppName}.azurewebsites.net/api/eventhandler'
        userEventPattern: '*'
        systemEvents: [
          'connect'
          'connected'
          'disconnected'
        ]
        auth: {
          type: 'None'
        }
      }
    ]
    anonymousConnectPolicy: 'allow'
  }
  dependsOn: [
    functionApp
  ]
}

// App Service Plan for Function App - Consumption plan for cost optimization
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: commonTags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    computeMode: 'Dynamic'
  }
}

// Function App - Serverless backend for WebSocket handling and metric processing
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: commonTags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
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
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~${functionAppRuntimeVersion}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionAppRuntime
        }
        {
          name: 'WEBPUBSUB_CONNECTION'
          value: webPubSubService.listKeys().primaryConnectionString
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
          name: 'AzureWebJobsFeatureFlags'
          value: 'EnableWorkerIndexing'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://${staticWebApp.properties.defaultHostname}'
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
    }
    httpsOnly: true
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Static Web App - Global CDN for dashboard frontend
resource staticWebApp 'Microsoft.Web/staticSites@2023-01-01' = {
  name: staticAppName
  location: location
  tags: commonTags
  sku: {
    name: staticWebAppSku
    tier: staticWebAppSku
  }
  properties: {
    repositoryUrl: null
    branch: null
    repositoryToken: null
    buildProperties: {
      skipGithubActionWorkflowGeneration: true
    }
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    enterpriseGradeCdnStatus: 'Disabled'
  }
}

// Link Function App as backend API for Static Web App
resource staticWebAppLinkedBackend 'Microsoft.Web/staticSites/linkedBackends@2023-01-01' = {
  parent: staticWebApp
  name: 'backend'
  properties: {
    backendResourceId: functionApp.id
    region: location
  }
}

// Diagnostic Settings for Web PubSub - Monitor service health and performance
resource webPubSubDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'webpubsub-diagnostics'
  scope: webPubSubService
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

// Diagnostic Settings for Function App - Monitor serverless backend performance
resource functionAppDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'functionapp-diagnostics'
  scope: functionApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'FunctionAppLogs'
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

// Metric Alert for High WebSocket Connections - Proactive monitoring
resource webSocketConnectionsAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'high-websocket-connections'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'Alert when WebSocket connections exceed 1000'
    severity: 2
    enabled: true
    scopes: [
      webPubSubService.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 1000
          name: 'Metric1'
          metricNamespace: 'Microsoft.SignalRService/webPubSub'
          metricName: 'ConnectionCount'
          operator: 'GreaterThan'
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.SignalRService/webPubSub'
    targetResourceRegion: location
    actions: []
  }
}

// RBAC: Grant Function App access to Web PubSub for connection management
resource webPubSubDataOwnerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(webPubSubService.id, functionApp.id, 'Web PubSub Service Owner')
  scope: webPubSubService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '12cf5a90-567b-43ae-8102-96cf46c7d9b4') // Web PubSub Service Owner
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC: Grant Function App access to Application Insights for telemetry
resource appInsightsComponentContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(applicationInsights.id, functionApp.id, 'Application Insights Component Contributor')
  scope: applicationInsights
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ae349356-3a1b-4a5e-921d-050484c6347e') // Application Insights Component Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC: Grant Function App access to Monitor Metrics for querying Azure Monitor
resource monitoringMetricsPublisherRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'Monitoring Metrics Publisher')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb') // Monitoring Metrics Publisher
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs for integration and verification
@description('The URL of the deployed Static Web App dashboard')
output dashboardUrl string = 'https://${staticWebApp.properties.defaultHostname}'

@description('The name of the Web PubSub service for connection configuration')
output webPubSubServiceName string = webPubSubService.name

@description('The hostname of the Function App for API integration')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The connection string for Web PubSub service (sensitive)')
@secure()
output webPubSubConnectionString string = webPubSubService.listKeys().primaryConnectionString

@description('The instrumentation key for Application Insights')
@secure()
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The connection string for Application Insights')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The customer ID of the Log Analytics workspace for queries')
output logAnalyticsCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('Resource group name containing all deployed resources')
output resourceGroupName string = resourceGroup().name

@description('Azure region where resources are deployed')
output deploymentLocation string = location

@description('Environment tag applied to all resources')
output environment string = environment

@description('Unique suffix used for resource naming')
output uniqueSuffix string = uniqueSuffix

@description('Summary of all deployed resources for verification')
output deployedResources object = {
  webPubSub: {
    name: webPubSubService.name
    sku: webPubSubService.sku.name
    units: webPubSubService.sku.capacity
  }
  staticWebApp: {
    name: staticWebApp.name
    url: 'https://${staticWebApp.properties.defaultHostname}'
    sku: staticWebApp.sku.name
  }
  functionApp: {
    name: functionApp.name
    hostname: functionApp.properties.defaultHostName
    runtime: functionAppRuntime
  }
  storage: {
    name: storageAccount.name
    tier: storageAccount.sku.name
  }
  monitoring: {
    logAnalytics: logAnalyticsWorkspace.name
    applicationInsights: applicationInsights.name
    retentionDays: logRetentionDays
  }
}