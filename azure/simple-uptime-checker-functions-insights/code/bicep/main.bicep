@description('Name of the Function App')
param functionAppName string = 'func-uptime-${uniqueString(resourceGroup().id)}'

@description('Name of the Application Insights instance')
param appInsightsName string = 'ai-uptime-${uniqueString(resourceGroup().id)}'

@description('Name of the Storage Account for Function App')
param storageAccountName string = 'stg${uniqueString(resourceGroup().id)}'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Node.js runtime version for Function App')
@allowed([
  '16'
  '18'
  '20'
])
param nodeVersion string = '18'

@description('Function App hosting plan SKU')
@allowed([
  'Y1'  // Consumption plan
  'EP1' // Elastic Premium
  'EP2'
  'EP3'
])
param hostingPlanSku string = 'Y1'

@description('Websites to monitor (comma-separated URLs)')
param websitesToMonitor string = 'https://www.microsoft.com,https://azure.microsoft.com,https://github.com'

@description('Monitoring interval in minutes (5-60)')
@minValue(5)
@maxValue(60)
param monitoringIntervalMinutes int = 5

@description('Function timeout in minutes (1-10)')
@minValue(1)
@maxValue(10)
param functionTimeoutMinutes int = 5

@description('Enable alert rules for uptime monitoring')
param enableAlerting bool = true

@description('Alert severity level (0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose)')
@minValue(0)
@maxValue(4)
param alertSeverity int = 2

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'uptime-monitoring'
  environment: 'demo'
  solution: 'simple-uptime-checker'
}

// Variables
var storageAccountNameClean = take(replace(storageAccountName, '-', ''), 24)
var cronExpression = '0 */${monitoringIntervalMinutes} * * * *'
var hostingPlanName = 'asp-${functionAppName}'
var actionGroupName = 'ag-uptime-alerts-${uniqueString(resourceGroup().id)}'
var alertRuleName = 'alert-website-down-${uniqueString(resourceGroup().id)}'

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountNameClean
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
    minimumTlsVersion: 'TLS1_2'
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
  }
}

// Application Insights for monitoring and telemetry
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 90
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Hosting Plan for Function App
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  sku: {
    name: hostingPlanSku
  }
  properties: {
    reserved: false // Windows plan
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    clientAffinityEnabled: false
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
          value: '~${nodeVersion}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'WEBSITES_TO_MONITOR'
          value: websitesToMonitor
        }
        {
          name: 'MONITORING_INTERVAL'
          value: string(monitoringIntervalMinutes)
        }
      ]
      nodeVersion: '~${nodeVersion}'
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
    }
  }
}

// Function configuration and code deployment
resource uptimeCheckerFunction 'Microsoft.Web/sites/functions@2023-01-01' = {
  parent: functionApp
  name: 'UptimeChecker'
  properties: {
    config: {
      bindings: [
        {
          name: 'timer'
          type: 'timerTrigger'
          direction: 'in'
          schedule: cronExpression
        }
      ]
      disabled: false
    }
    files: {
      'index.js': loadTextContent('function-code.js')
      'function.json': string({
        bindings: [
          {
            name: 'timer'
            type: 'timerTrigger'
            direction: 'in'
            schedule: cronExpression
          }
        ]
      })
    }
  }
}

// Action Group for alerts (if alerting is enabled)
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (enableAlerting) {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'uptimealert'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

// Scheduled Query Alert Rule (if alerting is enabled)
resource alertRule 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (enableAlerting) {
  name: alertRuleName
  location: location
  tags: tags
  properties: {
    displayName: 'Website Down Alert - ${functionAppName}'
    description: 'Alert when websites are detected as down by the uptime checker function'
    severity: alertSeverity
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [
      appInsights.id
    ]
    criteria: {
      allOf: [
        {
          query: 'traces | where timestamp > ago(10m) | where message contains "❌" | summarize count()'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: enableAlerting ? [actionGroup.id] : []
    }
  }
}

// Function App host configuration
resource hostConfig 'Microsoft.Web/sites/config@2023-01-01' = {
  parent: functionApp
  name: 'host'
  properties: {
    version: '2.0'
    functionTimeout: '00:0${functionTimeoutMinutes}:00'
    extensionBundle: {
      id: 'Microsoft.Azure.Functions.ExtensionBundle'
      version: '[3.*, 4.0.0)'
    }
    logging: {
      applicationInsights: {
        samplingSettings: {
          isEnabled: true
          maxTelemetryItemsPerSecond: 20
        }
      }
    }
  }
}

// Outputs
@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Application Insights name')
output appInsightsName string = appInsights.name

@description('Application Insights connection string')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Application Insights Instrumentation Key')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Websites being monitored')
output websitesMonitored array = split(websitesToMonitor, ',')

@description('Monitoring interval in minutes')
output monitoringInterval int = monitoringIntervalMinutes

@description('CRON expression for timer trigger')
output cronExpression string = cronExpression

@description('Alert rule name (if alerting enabled)')
output alertRuleName string = enableAlerting ? alertRule.name : ''

@description('Action group name (if alerting enabled)')
output actionGroupName string = enableAlerting ? actionGroup.name : ''