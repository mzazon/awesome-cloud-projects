@description('The name of the Azure Load Testing resource')
param loadTestName string = 'alt-perftest-demo'

@description('The name of the Application Insights resource')
param appInsightsName string = 'ai-perftest-demo'

@description('The name of the resource group')
param resourceGroupName string = resourceGroup().name

@description('The location where resources will be deployed')
param location string = resourceGroup().location

@description('Environment tag for resource categorization')
@allowed(['dev', 'test', 'staging', 'prod'])
param environment string = 'dev'

@description('Purpose tag for resource categorization')
param purpose string = 'performance-testing'

@description('Target application URL for load testing')
param targetAppUrl string = 'https://your-app.azurewebsites.net'

@description('Email address for performance alerts')
param alertEmailAddress string = 'devops@example.com'

@description('Pricing tier for Application Insights')
@allowed(['Basic', 'PerGB2018'])
param appInsightsPricingTier string = 'PerGB2018'

@description('Daily cap for Application Insights in GB')
param appInsightsDailyCap int = 1

@description('Response time threshold in milliseconds for alerts')
param responseTimeThreshold int = 1000

@description('Error rate threshold as percentage for alerts')
param errorRateThreshold int = 5

@description('Action group short name (max 12 characters)')
@maxLength(12)
param actionGroupShortName string = 'PerfAlerts'

// Common tags applied to all resources
var commonTags = {
  environment: environment
  purpose: purpose
  'deployed-by': 'bicep'
  'recipe-name': 'automating-performance-testing-with-azure-load-testing-and-azure-devops'
}

// Create Application Insights workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${appInsightsName}'
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Create Application Insights component
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: commonTags
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'IbizaAIExtension'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Configure Application Insights pricing and data cap
resource appInsightsBilling 'Microsoft.Insights/components/CurrentBillingFeatures@2015-05-01' = {
  parent: applicationInsights
  properties: {
    CurrentBillingFeatures: [appInsightsPricingTier]
    DataVolumeCap: {
      Cap: appInsightsDailyCap
      WarningThreshold: 90
      ResetTime: 0
    }
  }
}

// Create Azure Load Testing resource
resource loadTestingResource 'Microsoft.LoadTestService/loadtests@2022-12-01' = {
  name: loadTestName
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: 'Azure Load Testing resource for automated performance testing in CI/CD pipelines'
  }
}

// Create Action Group for performance alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-perftest-alerts'
  location: 'Global'
  tags: commonTags
  properties: {
    groupShortName: actionGroupShortName
    enabled: true
    emailReceivers: [
      {
        name: 'DevOpsTeam'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
    webhookReceivers: []
    eventHubReceivers: []
    smsReceivers: []
    voiceReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    azureFunctionReceivers: []
    logicAppReceivers: []
    automationRunbookReceivers: []
    azureAppPushReceivers: []
  }
}

// Create metric alert for high response time
resource responseTimeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-high-response-time'
  location: 'Global'
  tags: commonTags
  properties: {
    description: 'Alert when average response time exceeds threshold'
    severity: 2
    enabled: true
    scopes: [
      loadTestingResource.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighResponseTime'
          metricName: 'response_time_ms'
          metricNamespace: 'Microsoft.LoadTestService/loadtests'
          operator: 'GreaterThan'
          threshold: responseTimeThreshold
          timeAggregation: 'Average'
          skipMetricValidation: false
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// Create metric alert for high error rate
resource errorRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-high-error-rate'
  location: 'Global'
  tags: commonTags
  properties: {
    description: 'Alert when error rate exceeds threshold'
    severity: 1
    enabled: true
    scopes: [
      loadTestingResource.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighErrorRate'
          metricName: 'error_percentage'
          metricNamespace: 'Microsoft.LoadTestService/loadtests'
          operator: 'GreaterThan'
          threshold: errorRateThreshold
          timeAggregation: 'Average'
          skipMetricValidation: false
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// Create Log Analytics queries for performance monitoring
resource performanceQueries 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'PerformanceTestAnalysis'
  properties: {
    displayName: 'Performance Test Analysis'
    category: 'Load Testing'
    query: '''
requests
| where timestamp > ago(1h)
| summarize 
    avg_duration = avg(duration),
    p95_duration = percentile(duration, 95),
    p99_duration = percentile(duration, 99),
    request_count = count(),
    error_rate = countif(success == false) * 100.0 / count()
    by bin(timestamp, 5m)
| order by timestamp desc
'''
    version: 2
    tags: commonTags
  }
}

// Role assignment for Load Test service to access Application Insights
resource loadTestAppInsightsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(loadTestingResource.id, applicationInsights.id, 'Monitoring Reader')
  scope: applicationInsights
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05') // Monitoring Reader role
    principalId: loadTestingResource.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Output values for pipeline configuration and verification
@description('The resource ID of the Load Testing resource')
output loadTestResourceId string = loadTestingResource.id

@description('The name of the Load Testing resource')
output loadTestResourceName string = loadTestingResource.name

@description('The connection string for Application Insights')
output appInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The instrumentation key for Application Insights')
output appInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The resource ID of Application Insights')
output appInsightsResourceId string = applicationInsights.id

@description('The resource ID of the Action Group')
output actionGroupResourceId string = actionGroup.id

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The workspace ID for Log Analytics')
output logAnalyticsWorkspaceGuid string = logAnalyticsWorkspace.properties.customerId

@description('The principal ID of the Load Testing service identity')
output loadTestPrincipalId string = loadTestingResource.identity.principalId

@description('Configuration values for Azure DevOps pipeline')
output pipelineConfiguration object = {
  loadTestResource: loadTestingResource.name
  loadTestResourceGroup: resourceGroupName
  targetAppUrl: targetAppUrl
  appInsightsConnectionString: applicationInsights.properties.ConnectionString
  environment: environment
}

@description('Performance thresholds configured for alerts')
output performanceThresholds object = {
  responseTimeThreshold: responseTimeThreshold
  errorRateThreshold: errorRateThreshold
  actionGroupEmail: alertEmailAddress
}