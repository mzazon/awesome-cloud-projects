// ================================================================================
// Bicep template for Edge-Based Healthcare Analytics with Azure SQL Edge 
// and Azure Health Data Services
// ================================================================================

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource naming')
@minLength(3)
@maxLength(8)
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('IoT Hub SKU and capacity')
@allowed(['S1', 'S2', 'S3'])
param iotHubSku string = 'S1'

@description('IoT Hub partition count')
@minValue(2)
@maxValue(32)
param iotHubPartitionCount int = 2

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('Function App hosting plan SKU')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppSku string = 'Y1'

@description('Storage account SKU for Function App')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Azure Health Data Services workspace name')
param healthDataWorkspaceName string = 'ahds-workspace-${resourceSuffix}'

@description('FHIR service name')
param fhirServiceName string = 'fhir-service-${resourceSuffix}'

@description('Enable diagnostic settings')
param enableDiagnostics bool = true

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'healthcare-edge-analytics'
  Solution: 'edge-healthcare'
  CostCenter: 'healthcare-it'
}

// ================================================================================
// Variables
// ================================================================================

var resourceNames = {
  iotHub: 'iot-healthcare-${resourceSuffix}'
  logAnalyticsWorkspace: 'law-health-${resourceSuffix}'
  storageAccount: 'sthealthdata${resourceSuffix}'
  functionApp: 'func-health-alerts-${resourceSuffix}'
  applicationInsights: 'ai-health-${resourceSuffix}'
  healthDataWorkspace: healthDataWorkspaceName
  fhirService: fhirServiceName
}

// ================================================================================
// Storage Account for Function App
// ================================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
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
  }
}

// ================================================================================
// Log Analytics Workspace
// ================================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
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
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ================================================================================
// Application Insights
// ================================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ================================================================================
// IoT Hub
// ================================================================================

resource iotHub 'Microsoft.Devices/IotHubs@2023-06-30' = {
  name: resourceNames.iotHub
  location: location
  tags: tags
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
        eventHubs: []
        serviceBusQueues: []
        serviceBusTopics: []
        storageContainers: []
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
    features: 'None'
    minTlsVersion: '1.2'
  }
}

// ================================================================================
// IoT Hub Diagnostic Settings
// ================================================================================

resource iotHubDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
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

// ================================================================================
// Azure Health Data Services Workspace
// ================================================================================

resource healthDataWorkspace 'Microsoft.HealthcareApis/workspaces@2024-03-31' = {
  name: resourceNames.healthDataWorkspace
  location: location
  tags: tags
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// ================================================================================
// FHIR Service
// ================================================================================

resource fhirService 'Microsoft.HealthcareApis/workspaces/fhirservices@2024-03-31' = {
  name: resourceNames.fhirService
  parent: healthDataWorkspace
  location: location
  tags: tags
  kind: 'fhir-R4'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    authenticationConfiguration: {
      authority: '${environment().authentication.loginEndpoint}${tenant().tenantId}'
      audience: 'https://${resourceNames.healthDataWorkspace}-${resourceNames.fhirService}.fhir.azurehealthcareapis.com'
      smartProxyEnabled: false
    }
    corsConfiguration: {
      allowCredentials: false
      headers: ['*']
      maxAge: 1440
      methods: ['DELETE', 'GET', 'OPTIONS', 'PATCH', 'POST', 'PUT']
      origins: ['https://localhost:6001']
    }
    exportConfiguration: {
      storageAccountName: storageAccount.name
    }
    importConfiguration: {
      enabled: false
      initialImportMode: false
      integrationDataStore: storageAccount.name
    }
    publicNetworkAccess: 'Enabled'
  }
}

// ================================================================================
// Function App (Consumption Plan)
// ================================================================================

resource functionAppPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${resourceNames.functionApp}-plan'
  location: location
  tags: tags
  sku: {
    name: functionAppSku
  }
  kind: 'functionapp'
  properties: {
    reserved: false
  }
}

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: resourceNames.functionApp
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
          value: toLower(resourceNames.functionApp)
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
          name: 'FHIR_URL'
          value: 'https://${resourceNames.healthDataWorkspace}-${resourceNames.fhirService}.fhir.azurehealthcareapis.com'
        }
        {
          name: 'IOT_HUB_CONNECTION'
          value: 'Endpoint=${iotHub.properties.eventHubEndpoints.events.endpoint};SharedAccessKeyName=iothubowner;SharedAccessKey=${iotHub.listKeys().value[0].primaryKey};EntityPath=${iotHub.properties.eventHubEndpoints.events.path}'
        }
        {
          name: 'LOG_ANALYTICS_WORKSPACE_ID'
          value: logAnalyticsWorkspace.properties.customerId
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      netFrameworkVersion: 'v6.0'
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

// ================================================================================
// Role Assignments for Function App
// ================================================================================

// FHIR Data Contributor role for Function App
resource fhirDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(fhirService.id, functionApp.id, 'fhir-data-contributor')
  scope: fhirService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5a1fc7df-4bf1-4951-a576-89034ee01acd') // FHIR Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// IoT Hub Data Contributor role for Function App
resource iotHubDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(iotHub.id, functionApp.id, 'iot-hub-data-contributor')
  scope: iotHub
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4fc6c259-987e-4a07-842e-c321cc9d413f') // IoT Hub Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ================================================================================
// Outputs
// ================================================================================

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('IoT Hub name')
output iotHubName string = iotHub.name

@description('IoT Hub hostname')
output iotHubHostname string = iotHub.properties.hostName

@description('IoT Hub Event Hub endpoint')
output iotHubEventHubEndpoint string = iotHub.properties.eventHubEndpoints.events.endpoint

@description('Azure Health Data Services workspace name')
output healthDataWorkspaceName string = healthDataWorkspace.name

@description('FHIR service name')
output fhirServiceName string = fhirService.name

@description('FHIR service URL')
output fhirServiceUrl string = 'https://${resourceNames.healthDataWorkspace}-${resourceNames.fhirService}.fhir.azurehealthcareapis.com'

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Resource suffix used for naming')
output resourceSuffix string = resourceSuffix

@description('All resource names created')
output resourceNames object = {
  iotHub: iotHub.name
  healthDataWorkspace: healthDataWorkspace.name
  fhirService: fhirService.name
  functionApp: functionApp.name
  storageAccount: storageAccount.name
  logAnalyticsWorkspace: logAnalyticsWorkspace.name
  applicationInsights: applicationInsights.name
}