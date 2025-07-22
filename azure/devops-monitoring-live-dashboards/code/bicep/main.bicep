@description('Resource name prefix for all resources')
param resourcePrefix string = 'monitor'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment tag for resource categorization')
@allowed(['dev', 'test', 'staging', 'prod', 'demo'])
param environment string = 'demo'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'monitoring'
  environment: environment
  deployment: 'bicep'
  project: 'devops-monitoring-live-dashboards'
  'created-date': utcNow('yyyy-MM-dd')
}

@description('Enable diagnostic settings for resources')
param enableDiagnostics bool = true

@description('Enable network restrictions for enhanced security')
param enableNetworkRestrictions bool = false

@description('Allowed IP addresses for network restrictions (if enabled)')
param allowedIpAddresses array = []

@description('SignalR Service pricing tier')
@allowed(['Free_F1', 'Standard_S1'])
param signalrSku string = 'Standard_S1'

@description('Function App consumption plan')
@allowed(['Y1'])
param functionAppSku string = 'Y1'

@description('Web App pricing tier')
@allowed(['B1', 'B2', 'S1', 'S2'])
param webAppSku string = 'B1'

@description('Storage account type')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountType string = 'Standard_LRS'

@description('Log Analytics workspace pricing tier')
@allowed(['PerGB2018', 'Free', 'Standalone', 'PerNode'])
param logAnalyticsSku string = 'PerGB2018'

// Generate unique suffix for resource names
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)

// Resource names
var signalrName = '${resourcePrefix}-signalr-${uniqueSuffix}'
var functionAppName = '${resourcePrefix}-func-${uniqueSuffix}'
var storageAccountName = '${resourcePrefix}st${uniqueSuffix}'
var appServicePlanName = '${resourcePrefix}-asp-${uniqueSuffix}'
var webAppName = '${resourcePrefix}-webapp-${uniqueSuffix}'
var logAnalyticsName = '${resourcePrefix}-log-${uniqueSuffix}'
var appInsightsName = '${resourcePrefix}-ai-${uniqueSuffix}'
var actionGroupName = '${resourcePrefix}-ag-${uniqueSuffix}'

// Storage Account for Azure Functions
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    accessTier: 'Hot'
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

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsSku
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
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

// Azure SignalR Service
resource signalrService 'Microsoft.SignalRService/signalR@2023-02-01' = {
  name: signalrName
  location: location
  tags: tags
  sku: {
    name: signalrSku
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    tls: {
      clientCertEnabled: false
    }
    features: [
      {
        flag: 'ServiceMode'
        value: 'Default'
      }
      {
        flag: 'EnableConnectivityLogs'
        value: 'True'
      }
      {
        flag: 'EnableMessagingLogs'
        value: 'True'
      }
    ]
    cors: {
      allowedOrigins: [
        '*'
      ]
    }
    serverless: {
      connectionTimeoutInSeconds: 30
    }
    upstream: {
      templates: []
    }
  }
}

// App Service Plan for Function App (Consumption Plan)
resource functionAppServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: '${appServicePlanName}-func'
  location: location
  tags: tags
  sku: {
    name: functionAppSku
  }
  properties: {
    reserved: false
  }
}

// Azure Functions App
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionAppServicePlan.id
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
          value: '~18'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
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
          name: 'AzureSignalRConnectionString'
          value: signalrService.listKeys().primaryConnectionString
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
          'https://ms.portal.azure.com'
        ]
        supportCredentials: false
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
  dependsOn: [
    storageAccount
    applicationInsights
    signalrService
  ]
}

// App Service Plan for Web App
resource webAppServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: webAppSku
  }
  properties: {
    reserved: true
  }
}

// Web App for Dashboard
resource webApp 'Microsoft.Web/sites@2022-09-01' = {
  name: webAppName
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: webAppServicePlan.id
    siteConfig: {
      linuxFxVersion: 'NODE|18-lts'
      appSettings: [
        {
          name: 'FUNCTIONS_URL'
          value: 'https://${functionApp.properties.defaultHostName}'
        }
        {
          name: 'SIGNALR_CONNECTION_STRING'
          value: signalrService.listKeys().primaryConnectionString
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
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '18-lts'
        }
      ]
      alwaysOn: webAppSku != 'B1' ? true : false
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      cors: {
        allowedOrigins: [
          '*'
        ]
        supportCredentials: false
      }
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
  dependsOn: [
    webAppServicePlan
    functionApp
    signalrService
    applicationInsights
  ]
}

// Action Group for Azure Monitor Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'MonitorAG'
    enabled: true
    webhookReceivers: [
      {
        name: 'monitoring-webhook'
        serviceUri: 'https://${functionApp.properties.defaultHostName}/api/DevOpsWebhook'
        useCommonAlertSchema: true
      }
    ]
  }
  dependsOn: [
    functionApp
  ]
}

// Metric Alert for Function App Errors
resource functionAppErrorAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${functionAppName}-errors'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when Function App has high error rate'
    severity: 2
    enabled: true
    scopes: [
      functionApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'FunctionErrors'
          metricName: 'FunctionExecutionCount'
          dimensions: [
            {
              name: 'Status'
              operator: 'Include'
              values: [
                'Failed'
              ]
            }
          ]
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Count'
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
  dependsOn: [
    functionApp
    actionGroup
  ]
}

// Metric Alert for SignalR Connection Issues
resource signalrConnectionAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${signalrName}-connections'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when SignalR Service has low connection count'
    severity: 3
    enabled: true
    scopes: [
      signalrService.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ConnectionCount'
          metricName: 'ConnectionCount'
          operator: 'LessThan'
          threshold: 1
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
  dependsOn: [
    signalrService
    actionGroup
  ]
}

// RBAC: Grant SignalR Service Contributor role to Function App
resource signalrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(signalrService.id, functionApp.id, 'SignalR Service Contributor')
  scope: signalrService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '420fcaa2-552c-430f-98ca-3264be4806c7') // SignalR Service Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    signalrService
    functionApp
  ]
}

// RBAC: Grant Monitoring Metrics Publisher role to Function App for custom metrics
resource metricsPublisherRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'Monitoring Metrics Publisher')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb') // Monitoring Metrics Publisher
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    functionApp
  ]
}

// Output important values
output resourceGroupName string = resourceGroup().name
output signalrServiceName string = signalrService.name
output signalrServiceHostname string = signalrService.properties.hostName
output signalrConnectionString string = signalrService.listKeys().primaryConnectionString
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output storageAccountName string = storageAccount.name
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output applicationInsightsName string = applicationInsights.name
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output actionGroupName string = actionGroup.name
output webhookUrl string = 'https://${functionApp.properties.defaultHostName}/api/DevOpsWebhook'

// Output for Azure DevOps Service Hook configuration
output azureDevOpsServiceHookConfig object = {
  webhookUrl: 'https://${functionApp.properties.defaultHostName}/api/DevOpsWebhook'
  contentType: 'application/json'
  httpHeaders: {}
  basicAuthUsername: ''
  basicAuthPassword: ''
  resourceDetailsToSend: 'All'
  messagesToSend: 'All'
  detailedMessagesToSend: 'All'
}

// Diagnostic Settings for SignalR Service
resource signalrDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'signalr-diagnostics'
  scope: signalrService
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AllLogs'
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

// Diagnostic Settings for Function App
resource functionAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
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

// Diagnostic Settings for Web App
resource webAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'webapp-diagnostics'
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

// Network Access Restrictions for Function App (if enabled)
resource functionAppNetworkConfig 'Microsoft.Web/sites/config@2022-09-01' = if (enableNetworkRestrictions && length(allowedIpAddresses) > 0) {
  name: 'web'
  parent: functionApp
  properties: {
    ipSecurityRestrictions: [
      for ipAddress in allowedIpAddresses: {
        ipAddress: ipAddress
        action: 'Allow'
        priority: 100
        name: 'AllowedIP'
        description: 'Allowed IP address for Function App access'
      }
    ]
    scmIpSecurityRestrictions: [
      for ipAddress in allowedIpAddresses: {
        ipAddress: ipAddress
        action: 'Allow'
        priority: 100
        name: 'AllowedIP'
        description: 'Allowed IP address for SCM access'
      }
    ]
    scmIpSecurityRestrictionsUseMain: false
  }
}

// Network Access Restrictions for Web App (if enabled)
resource webAppNetworkConfig 'Microsoft.Web/sites/config@2022-09-01' = if (enableNetworkRestrictions && length(allowedIpAddresses) > 0) {
  name: 'web'
  parent: webApp
  properties: {
    ipSecurityRestrictions: [
      for ipAddress in allowedIpAddresses: {
        ipAddress: ipAddress
        action: 'Allow'
        priority: 100
        name: 'AllowedIP'
        description: 'Allowed IP address for Web App access'
      }
    ]
    scmIpSecurityRestrictions: [
      for ipAddress in allowedIpAddresses: {
        ipAddress: ipAddress
        action: 'Allow'
        priority: 100
        name: 'AllowedIP'
        description: 'Allowed IP address for SCM access'
      }
    ]
    scmIpSecurityRestrictionsUseMain: false
  }
}

// Output deployment validation commands
output validationCommands object = {
  signalrStatus: 'az signalr show --name ${signalrService.name} --resource-group ${resourceGroup().name} --query "provisioningState"'
  functionAppStatus: 'az functionapp show --name ${functionApp.name} --resource-group ${resourceGroup().name} --query "state"'
  webAppStatus: 'az webapp show --name ${webApp.name} --resource-group ${resourceGroup().name} --query "state"'
  testWebhook: 'curl -X POST "https://${functionApp.properties.defaultHostName}/api/DevOpsWebhook" -H "Content-Type: application/json" -d \'{"eventType":"test","resource":{"status":"success"}}\''
}

// Output for production deployment guidance
output productionGuidance object = {
  recommendations: [
    'Configure custom domain names for production workloads'
    'Enable Private Endpoints for SignalR Service in production'
    'Configure backup and disaster recovery for critical data'
    'Set up automated deployment pipelines using Azure DevOps'
    'Configure monitoring alerts for business-critical scenarios'
    'Review and adjust resource scaling limits based on usage patterns'
  ]
  securityConsiderations: [
    'Enable network restrictions for production environments'
    'Configure Azure Active Directory authentication for sensitive resources'
    'Use Azure Key Vault for secrets management'
    'Enable Azure Security Center recommendations'
    'Configure SSL/TLS certificates for custom domains'
  ]
  costOptimization: [
    'Monitor resource usage and scale down unused resources'
    'Consider reserved instances for predictable workloads'
    'Use Azure Cost Management for budget alerts'
    'Implement auto-scaling policies based on metrics'
    'Review and optimize Log Analytics data retention policies'
  ]
}

// Output for Azure DevOps integration
output azureDevOpsIntegration object = {
  serviceHookConfiguration: {
    webhookUrl: 'https://${functionApp.properties.defaultHostName}/api/DevOpsWebhook'
    events: [
      'Build completed'
      'Release deployment completed'
      'Work item created'
      'Git push'
    ]
    authentication: 'None (Function-level authentication recommended)'
  }
  sampleEvents: [
    {
      eventType: 'build.complete'
      description: 'Triggered when a build completes'
      samplePayload: {
        eventType: 'build.complete'
        resource: {
          status: 'succeeded'
          result: 'succeeded'
        }
      }
    }
    {
      eventType: 'ms.vss-release.deployment-completed-event'
      description: 'Triggered when a deployment completes'
      samplePayload: {
        eventType: 'ms.vss-release.deployment-completed-event'
        resource: {
          environment: {
            name: 'Production'
            status: 'succeeded'
          }
        }
      }
    }
  ]
}