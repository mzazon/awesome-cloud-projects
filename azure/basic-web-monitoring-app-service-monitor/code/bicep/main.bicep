@description('Name of the App Service web application')
param appName string = 'app-${uniqueString(resourceGroup().id)}'

@description('Name of the App Service plan')
param appServicePlanName string = 'plan-${uniqueString(resourceGroup().id)}'

@description('Name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string = 'logs-${uniqueString(resourceGroup().id)}'

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('SKU for the App Service plan')
@allowed([
  'F1'
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1'
  'P2'
  'P3'
])
param appServicePlanSku string = 'F1'

@description('Operating system for the App Service plan')
@allowed([
  'Linux'
  'Windows'
])
param operatingSystem string = 'Linux'

@description('Container image for the web app (Linux only)')
param containerImage string = 'mcr.microsoft.com/appsvc/node:18-lts'

@description('Email address for alert notifications')
param alertEmail string

@description('Response time threshold in seconds for performance alerts')
param responseTimeThresholdSeconds int = 5

@description('HTTP 5xx error threshold for error alerts')
param httpErrorThreshold int = 10

@description('Tags to apply to resources')
param tags object = {
  purpose: 'recipe-demo'
  environment: 'development'
}

// Variables
var isLinux = operatingSystem == 'Linux'
var actionGroupName = 'ag-web-alerts-${uniqueString(resourceGroup().id)}'

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
      dailyQuotaGb: 1
    }
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
  }
  kind: isLinux ? 'linux' : 'app'
  properties: {
    reserved: isLinux
  }
}

// App Service Web App  
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  tags: tags
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: isLinux ? {
      linuxFxVersion: 'DOCKER|${containerImage}'
      appSettings: [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
      ]
    } : {
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY' 
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
      ]
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${appName}-insights'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'IbizaWebAppExtensionCreate'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Web App Logging Configuration
resource webAppLogs 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: webApp
  name: 'logs'
  properties: {
    applicationLogs: {
      fileSystem: {
        level: 'Information'
      }
    }
    httpLogs: {
      fileSystem: {
        retentionInMb: 35
        retentionInDays: 3
        enabled: true
      }
    }
    failedRequestsTracing: {
      enabled: true
    }
    detailedErrorMessages: {
      enabled: true
    }
  }
}

// Diagnostic Settings for Web App
resource webAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'AppServiceDiagnostics'
  scope: webApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'AppServicePlatformLogs'
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

// Action Group for Alert Notifications
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'WebAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'Admin'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// Metric Alert Rule for High Response Time
resource responseTimeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'HighResponseTime-${appName}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when average response time exceeds ${responseTimeThresholdSeconds} seconds'
    enabled: true
    severity: 2
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    targetResourceType: 'Microsoft.Web/sites'
    targetResourceRegion: location
    scopes: [
      webApp.id
    ]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'AverageResponseTime'
          metricName: 'AverageResponseTime'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          threshold: responseTimeThresholdSeconds
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

// Metric Alert Rule for HTTP 5xx Errors
resource httpErrorAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'HTTP5xxErrors-${appName}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when HTTP 5xx errors exceed ${httpErrorThreshold} in 5 minutes'
    enabled: true
    severity: 1
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    targetResourceType: 'Microsoft.Web/sites'
    targetResourceRegion: location
    scopes: [
      webApp.id
    ]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Http5xx'
          metricName: 'Http5xx'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          threshold: httpErrorThreshold
          timeAggregation: 'Total'
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

// CPU Usage Alert Rule
resource cpuUsageAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'HighCPUUsage-${appName}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when CPU usage exceeds 80% for 10 minutes'
    enabled: true
    severity: 2
    evaluationFrequency: 'PT1M'
    windowSize: 'PT10M'
    targetResourceType: 'Microsoft.Web/sites'
    targetResourceRegion: location
    scopes: [
      webApp.id
    ]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CpuPercentage'
          metricName: 'CpuPercentage'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          threshold: 80
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

// Memory Usage Alert Rule  
resource memoryUsageAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'HighMemoryUsage-${appName}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when memory usage exceeds 85% for 10 minutes'
    enabled: true
    severity: 2
    evaluationFrequency: 'PT1M'
    windowSize: 'PT10M'
    targetResourceType: 'Microsoft.Web/sites'
    targetResourceRegion: location
    scopes: [
      webApp.id
    ]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'MemoryPercentage'
          metricName: 'MemoryPercentage'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          threshold: 85
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

// Outputs
output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output actionGroupId string = actionGroup.id
output resourceGroupName string = resourceGroup().name