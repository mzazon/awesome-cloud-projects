@description('Bicep template for Performance Regression Detection with Load Testing and Monitor Workbooks')

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = toLower(uniqueString(resourceGroup().id))

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Project name for resource naming')
param projectName string = 'perftest'

@description('Container image to deploy')
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Target port for the container app')
param targetPort int = 80

@description('CPU limit for the container app')
param cpuLimit string = '0.5'

@description('Memory limit for the container app')
param memoryLimit string = '1.0Gi'

@description('Minimum number of replicas')
param minReplicas int = 1

@description('Maximum number of replicas')
param maxReplicas int = 5

@description('Log Analytics workspace retention in days')
param logRetentionDays int = 30

@description('Alert evaluation frequency in minutes')
param alertEvaluationFrequency string = 'PT1M'

@description('Alert window size in minutes')
param alertWindowSize string = 'PT5M'

@description('Response time threshold in milliseconds')
param responseTimeThreshold int = 500

@description('Error rate threshold percentage')
param errorRateThreshold int = 5

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: projectName
  Purpose: 'performance-testing'
  CreatedBy: 'bicep-template'
}

// Variables
var resourceNames = {
  logAnalytics: 'law-${projectName}-${uniqueSuffix}'
  loadTesting: 'lt-${projectName}-${uniqueSuffix}'
  containerAppEnv: 'cae-${projectName}-${uniqueSuffix}'
  containerApp: 'ca-demo-${uniqueSuffix}'
  containerRegistry: 'acrperftest${uniqueSuffix}'
  applicationInsights: 'ai-${projectName}-${uniqueSuffix}'
  workbook: 'wb-${projectName}-${uniqueSuffix}'
  actionGroup: 'ag-${projectName}-${uniqueSuffix}'
  responseTimeAlert: 'alert-responsetime-${uniqueSuffix}'
  errorRateAlert: 'alert-errorrate-${uniqueSuffix}'
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalytics
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
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
  }
}

// Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: resourceNames.containerRegistry
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
  }
}

// Container Apps Environment
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: resourceNames.containerAppEnv
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: resourceNames.containerApp
  location: location
  tags: tags
  properties: {
    environmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: targetPort
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistry.name
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
        {
          name: 'appinsights-connection-string'
          value: applicationInsights.properties.ConnectionString
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'demo-app'
          image: containerImage
          resources: {
            cpu: json(cpuLimit)
            memory: memoryLimit
          }
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-connection-string'
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scale-rule'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

// Azure Load Testing Resource
resource loadTestingResource 'Microsoft.LoadTestService/loadTests@2022-12-01' = {
  name: resourceNames.loadTesting
  location: location
  tags: tags
  properties: {}
}

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: resourceNames.actionGroup
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'PerfAlert'
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

// Response Time Alert Rule
resource responseTimeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: resourceNames.responseTimeAlert
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when response time exceeds ${responseTimeThreshold}ms'
    severity: 2
    enabled: true
    scopes: [
      applicationInsights.id
    ]
    evaluationFrequency: alertEvaluationFrequency
    windowSize: alertWindowSize
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ResponseTime'
          metricName: 'performanceCounters/requestExecutionTime'
          operator: 'GreaterThan'
          threshold: responseTimeThreshold
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

// Error Rate Alert Rule
resource errorRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: resourceNames.errorRateAlert
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when error rate exceeds ${errorRateThreshold}%'
    severity: 2
    enabled: true
    scopes: [
      applicationInsights.id
    ]
    evaluationFrequency: alertEvaluationFrequency
    windowSize: alertWindowSize
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ErrorRate'
          metricName: 'requests/failed'
          operator: 'GreaterThan'
          threshold: errorRateThreshold
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

// Azure Monitor Workbook
resource performanceWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: resourceNames.workbook
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Performance Regression Detection Dashboard'
    description: 'Monitor application performance trends and detect regressions automatically'
    category: 'performance'
    sourceId: logAnalyticsWorkspace.id
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        {
          type: 1
          content: {
            json: '# Performance Regression Detection Dashboard\\n\\nMonitor application performance trends and detect regressions automatically.'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'requests\\n| where timestamp > ago(1h)\\n| summarize ResponseTime = avg(duration) by bin(timestamp, 5m)\\n| render timechart'
            size: 0
            title: 'Average Response Time Trend'
            timeContext: {
              durationMs: 3600000
            }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'requests\\n| where timestamp > ago(1h)\\n| summarize ErrorRate = countif(success == false) * 100.0 / count() by bin(timestamp, 5m)\\n| render timechart'
            size: 0
            title: 'Error Rate %'
            timeContext: {
              durationMs: 3600000
            }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'requests\\n| where timestamp > ago(24h)\\n| summarize TotalRequests = count(), AvgDuration = avg(duration), P95Duration = percentile(duration, 95) by bin(timestamp, 1h)\\n| render columnchart'
            size: 0
            title: 'Request Volume and Performance'
            timeContext: {
              durationMs: 86400000
            }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'exceptions\\n| where timestamp > ago(1h)\\n| summarize ExceptionCount = count() by bin(timestamp, 5m), type\\n| render timechart'
            size: 0
            title: 'Exception Trends'
            timeContext: {
              durationMs: 3600000
            }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
          }
        }
      ]
    })
  }
}

// Outputs
@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Load Testing resource name')
output loadTestingResourceName string = loadTestingResource.name

@description('Load Testing resource ID')
output loadTestingResourceId string = loadTestingResource.id

@description('Container App URL')
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'

@description('Container App name')
output containerAppName string = containerApp.name

@description('Container Registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('Container Registry name')
output containerRegistryName string = containerRegistry.name

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Container Apps environment name')
output containerAppEnvironmentName string = containerAppEnvironment.name

@description('Performance workbook name')
output performanceWorkbookName string = performanceWorkbook.name

@description('Action group name')
output actionGroupName string = actionGroup.name

@description('Response time alert name')
output responseTimeAlertName string = responseTimeAlert.name

@description('Error rate alert name')  
output errorRateAlertName string = errorRateAlert.name

@description('Deployment summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  environment: environment
  projectName: projectName
  containerAppUrl: 'https://${containerApp.properties.configuration.ingress.fqdn}'
  loadTestingResource: loadTestingResource.name
  workspaceName: logAnalyticsWorkspace.name
  alertsConfigured: {
    responseTimeThreshold: '${responseTimeThreshold}ms'
    errorRateThreshold: '${errorRateThreshold}%'
  }
}