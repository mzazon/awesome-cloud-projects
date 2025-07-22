@description('The name prefix for all resources')
param namePrefix string = 'selfheal'

@description('The location for the primary resource group')
param location string = resourceGroup().location

@description('The locations for the web app deployments')
param appLocations array = [
  'East US'
  'West US'
  'West Europe'
]

@description('The App Service plan SKU for web applications')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
])
param appServicePlanSku string = 'B1'

@description('The runtime stack for the web applications')
@allowed([
  'NODE:18-lts'
  'NODE:20-lts'
  'DOTNETCORE:8.0'
  'PYTHON:3.9'
  'PYTHON:3.10'
])
param webAppRuntime string = 'NODE:18-lts'

@description('The DNS TTL for Traffic Manager profile')
@minValue(30)
@maxValue(86400)
param trafficManagerDnsTtl int = 30

@description('The monitoring interval for Traffic Manager endpoints')
@minValue(10)
@maxValue(30)
param monitoringInterval int = 30

@description('The monitoring timeout for Traffic Manager endpoints')
@minValue(5)
@maxValue(10)
param monitoringTimeout int = 10

@description('The number of failures before marking endpoint as degraded')
@minValue(1)
@maxValue(9)
param toleratedNumberOfFailures int = 3

@description('The Azure Functions runtime version')
@allowed([
  '3.9'
  '3.10'
  '3.11'
])
param functionsPythonVersion string = '3.9'

@description('Tags to be applied to all resources')
param tags object = {
  purpose: 'self-healing-demo'
  environment: 'test'
  recipe: 'implementing-self-healing-infrastructure'
}

// Generate unique suffix for resources
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)

// Resource names with unique suffix
var trafficManagerProfileName = '${namePrefix}-tm-${uniqueSuffix}'
var functionAppName = '${namePrefix}-func-${uniqueSuffix}'
var storageAccountName = '${namePrefix}st${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${namePrefix}-law-${uniqueSuffix}'
var applicationInsightsName = '${namePrefix}-ai-${uniqueSuffix}'
var loadTestResourceName = '${namePrefix}-alt-${uniqueSuffix}'

// Create Log Analytics workspace for centralized monitoring
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
  }
}

// Create Application Insights for application monitoring
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

// Create App Service plans in different regions
resource appServicePlans 'Microsoft.Web/serverfarms@2023-12-01' = [for (appLocation, index) in appLocations: {
  name: '${namePrefix}-asp-${toLower(replace(appLocation, ' ', ''))}-${uniqueSuffix}'
  location: appLocation
  tags: tags
  sku: {
    name: appServicePlanSku
    tier: contains(appServicePlanSku, 'B') ? 'Basic' : 'Standard'
  }
  properties: {
    reserved: true
  }
  kind: 'linux'
}]

// Create web applications in different regions
resource webApps 'Microsoft.Web/sites@2023-12-01' = [for (appLocation, index) in appLocations: {
  name: '${namePrefix}-webapp-${toLower(replace(appLocation, ' ', ''))}-${uniqueSuffix}'
  location: appLocation
  tags: tags
  properties: {
    serverFarmId: appServicePlans[index].id
    siteConfig: {
      linuxFxVersion: webAppRuntime
      alwaysOn: true
      httpLoggingEnabled: true
      detailedErrorLoggingEnabled: true
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}]

// Create Traffic Manager profile
resource trafficManagerProfile 'Microsoft.Network/trafficmanagerprofiles@2022-04-01' = {
  name: trafficManagerProfileName
  location: 'global'
  tags: tags
  properties: {
    profileStatus: 'Enabled'
    trafficRoutingMethod: 'Performance'
    dnsConfig: {
      relativeName: trafficManagerProfileName
      ttl: trafficManagerDnsTtl
    }
    monitorConfig: {
      protocol: 'HTTPS'
      port: 443
      path: '/'
      intervalInSeconds: monitoringInterval
      timeoutInSeconds: monitoringTimeout
      toleratedNumberOfFailures: toleratedNumberOfFailures
    }
    endpoints: [for (appLocation, index) in appLocations: {
      name: '${toLower(replace(appLocation, ' ', ''))}-endpoint'
      type: 'Microsoft.Network/trafficManagerProfiles/azureEndpoints'
      properties: {
        targetResourceId: webApps[index].id
        endpointStatus: 'Enabled'
        priority: index + 1
      }
    }]
  }
}

// Create storage account for Azure Functions
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Create Azure Function App for self-healing automation
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlans[0].id
    siteConfig: {
      linuxFxVersion: 'PYTHON|${functionsPythonVersion}'
      alwaysOn: false
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
          value: functionAppName
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
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'TRAFFIC_MANAGER_PROFILE'
          value: trafficManagerProfileName
        }
        {
          name: 'RESOURCE_GROUP'
          value: resourceGroup().name
        }
        {
          name: 'SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
        {
          name: 'LOAD_TEST_RESOURCE'
          value: loadTestResourceName
        }
      ]
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

// Create Azure Load Testing resource
resource loadTestResource 'Microsoft.LoadTestService/loadTests@2022-12-01' = {
  name: loadTestResourceName
  location: location
  tags: tags
  properties: {
    description: 'Load testing resource for self-healing infrastructure validation'
  }
}

// Create action group for alerting
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${namePrefix}-ag-${uniqueSuffix}'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'selfheal'
    enabled: true
    webhookReceivers: [
      {
        name: 'webhook-function'
        serviceUri: 'https://${functionApp.properties.defaultHostName}/api/self-healing'
        useCommonAlertSchema: true
      }
    ]
  }
}

// Create alert rule for response time degradation
resource responseTimeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${namePrefix}-alert-response-time-${uniqueSuffix}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when average response time exceeds 5 seconds'
    severity: 2
    enabled: true
    scopes: [
      webApps[0].id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ResponseTime'
          metricName: 'AverageResponseTime'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 5000
          timeAggregation: 'Average'
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

// Create alert rule for availability degradation
resource availabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${namePrefix}-alert-availability-${uniqueSuffix}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when request rate drops below threshold'
    severity: 1
    enabled: true
    scopes: [
      webApps[0].id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT3M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'RequestCount'
          metricName: 'Requests'
          dimensions: []
          operator: 'LessThan'
          threshold: 1
          timeAggregation: 'Average'
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

// Role assignments for Function App managed identity
resource trafficManagerContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'TrafficManagerContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '79e88a7d-0d39-4d8f-86a7-5e2f5b9ca6c6')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource monitoringReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'MonitoringReader')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource loadTestContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'LoadTestContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '749a398d-560b-491b-bb21-08924219302e')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('The Traffic Manager profile FQDN')
output trafficManagerFqdn string = trafficManagerProfile.properties.dnsConfig.fqdn

@description('The Traffic Manager profile name')
output trafficManagerProfileName string = trafficManagerProfile.name

@description('The Function App name')
output functionAppName string = functionApp.name

@description('The Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The Load Testing resource name')
output loadTestResourceName string = loadTestResource.name

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The web app URLs')
output webAppUrls array = [for (webApp, index) in webApps: {
  name: webApp.name
  url: 'https://${webApp.properties.defaultHostName}'
  location: appLocations[index]
}]

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('The unique suffix used for resource names')
output uniqueSuffix string = uniqueSuffix