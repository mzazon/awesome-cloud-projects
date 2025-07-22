// Azure Container Apps Jobs with Azure Service Bus Event-Driven Workflow
// This template creates a complete serverless event-driven architecture using Container Apps Jobs and Service Bus

targetScope = 'resourceGroup'

// ========== PARAMETERS ==========

@description('The name prefix for all resources')
param resourcePrefix string = 'containerworkflow'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('The environment name (dev, staging, prod)')
@allowed([
  'dev'
  'staging' 
  'prod'
])
param environment string = 'dev'

@description('Service Bus namespace SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param serviceBusSkuName string = 'Standard'

@description('Container Registry SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param containerRegistrySku string = 'Basic'

@description('Maximum number of concurrent job executions')
@minValue(1)
@maxValue(100)
param maxExecutions int = 10

@description('Minimum number of job executions (0 for scale to zero)')
@minValue(0)
@maxValue(10)
param minExecutions int = 0

@description('Job replica timeout in seconds')
@minValue(30)
@maxValue(1800)
param replicaTimeout int = 1800

@description('Maximum retry attempts for failed jobs')
@minValue(0)
@maxValue(10)
param maxRetryCount int = 3

@description('Service Bus queue message count threshold for scaling')
@minValue(1)
@maxValue(100)
param queueMessageCountThreshold int = 1

@description('KEDA polling interval in seconds')
@minValue(10)
@maxValue(600)
param pollingIntervalSeconds int = 30

@description('Container image for the message processor')
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Container CPU allocation')
@allowed([
  '0.25'
  '0.5'
  '0.75'
  '1.0'
  '1.25'
  '1.5'
  '1.75'
  '2.0'
])
param containerCpu string = '0.5'

@description('Container memory allocation')
@allowed([
  '0.5Gi'
  '1Gi'
  '1.5Gi'
  '2Gi'
  '3Gi'
  '4Gi'
])
param containerMemory string = '1Gi'

@description('Enable Container Apps job monitoring and logging')
param enableMonitoring bool = true

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: 'ContainerAppsWorkflow'
  ManagedBy: 'Bicep'
}

// ========== VARIABLES ==========

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 8)
var serviceBusNamespaceName = '${resourcePrefix}-sb-${uniqueSuffix}'
var queueName = 'message-processing-queue'
var containerRegistryName = '${resourcePrefix}acr${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-logs-${uniqueSuffix}'
var containerAppsEnvironmentName = '${resourcePrefix}-env-${uniqueSuffix}'
var containerJobName = '${resourcePrefix}-job-${uniqueSuffix}'
var appInsightsName = '${resourcePrefix}-insights-${uniqueSuffix}'

// Connection string secret names
var serviceBusConnectionSecretName = 'servicebus-connection-string'
var registryPasswordSecretName = 'registry-password'

// ========== LOG ANALYTICS WORKSPACE ==========

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableMonitoring) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
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

// ========== APPLICATION INSIGHTS ==========

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableMonitoring) {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: enableMonitoring ? logAnalyticsWorkspace.id : null
  }
}

// ========== AZURE CONTAINER REGISTRY ==========

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: containerRegistrySku
  }
  properties: {
    adminUserEnabled: true
    policies: {
      quotaPolicy: {
        status: 'enabled'
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

// ========== SERVICE BUS NAMESPACE ==========

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  tags: tags
  sku: {
    name: serviceBusSkuName
    tier: serviceBusSkuName
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
  }
}

// ========== SERVICE BUS QUEUE ==========

resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: queueName
  properties: {
    lockDuration: 'PT1M'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    requiresSession: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    maxDeliveryCount: 5
    enableBatchedOperations: true
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    enablePartitioning: false
    enableExpress: false
  }
}

// ========== SERVICE BUS AUTHORIZATION RULE ==========

resource serviceBusAuthRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'RootManageSharedAccessKey'
  properties: {
    rights: [
      'Listen'
      'Manage'
      'Send'
    ]
  }
}

// ========== CONTAINER APPS ENVIRONMENT ==========

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: tags
  properties: {
    vnetConfiguration: {}
    appLogsConfiguration: enableMonitoring ? {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    } : null
    zoneRedundant: false
    kedaConfiguration: {}
    daprConfiguration: {}
    customDomainConfiguration: {}
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// ========== CONTAINER APPS JOB ==========

resource containerAppsJob 'Microsoft.App/jobs@2024-03-01' = {
  name: containerJobName
  location: location
  tags: tags
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      secrets: [
        {
          name: serviceBusConnectionSecretName
          value: serviceBusAuthRule.listKeys().primaryConnectionString
        }
        {
          name: registryPasswordSecretName
          value: containerRegistry.listCredentials().passwords[0].value
        }
      ]
      triggerType: 'Event'
      replicaTimeout: replicaTimeout
      replicaRetryLimit: maxRetryCount
      eventTriggerConfig: {
        replicaCompletionCount: 1
        parallelism: 5
        scale: {
          minExecutions: minExecutions
          maxExecutions: maxExecutions
          pollingInterval: pollingIntervalSeconds
          rules: [
            {
              name: 'servicebus-queue-length'
              type: 'azure-servicebus'
              metadata: {
                queueName: queueName
                namespace: serviceBusNamespaceName
                messageCount: string(queueMessageCountThreshold)
              }
              auth: [
                {
                  secretRef: serviceBusConnectionSecretName
                  triggerParameter: 'connection'
                }
              ]
            }
          ]
        }
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistry.listCredentials().username
          passwordSecretRef: registryPasswordSecretName
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'message-processor'
          image: containerImage
          env: [
            {
              name: 'SERVICE_BUS_CONNECTION_STRING'
              secretRef: serviceBusConnectionSecretName
            }
            {
              name: 'QUEUE_NAME'
              value: queueName
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: enableMonitoring ? applicationInsights.properties.ConnectionString : ''
            }
          ]
          resources: {
            cpu: json(containerCpu)
            memory: containerMemory
          }
        }
      ]
    }
  }
  dependsOn: [
    serviceBusQueue
  ]
}

// ========== MONITORING ALERT RULES ==========

resource jobFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: '${containerJobName}-failure-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when Container Apps job executions fail'
    severity: 2
    enabled: true
    scopes: [
      containerAppsJob.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'JobExecutionsFailed'
          metricName: 'JobExecutionCount'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'Status'
              operator: 'Include'
              values: [
                'Failed'
              ]
            }
          ]
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.App/jobs'
    targetResourceRegion: location
  }
}

resource queueLengthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: '${serviceBusNamespaceName}-queue-length-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when Service Bus queue has high message count'
    severity: 3
    enabled: true
    scopes: [
      '${serviceBusNamespace.id}/queues/${queueName}'
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighQueueLength'
          metricName: 'ActiveMessages'
          operator: 'GreaterThan'
          threshold: 100
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.ServiceBus/namespaces'
    targetResourceRegion: location
  }
}

// ========== OUTPUTS ==========

@description('The name of the created Service Bus namespace')
output serviceBusNamespaceName string = serviceBusNamespace.name

@description('The name of the created Service Bus queue')
output serviceBusQueueName string = serviceBusQueue.name

@description('The Service Bus namespace connection string')
@secure()
output serviceBusConnectionString string = serviceBusAuthRule.listKeys().primaryConnectionString

@description('The name of the created Container Registry')
output containerRegistryName string = containerRegistry.name

@description('The login server URL for the Container Registry')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('The Container Registry admin username')
output containerRegistryUsername string = containerRegistry.listCredentials().username

@description('The name of the created Container Apps environment')
output containerAppsEnvironmentName string = containerAppsEnvironment.name

@description('The name of the created Container Apps job')
output containerAppsJobName string = containerAppsJob.name

@description('The resource ID of the Container Apps job')
output containerAppsJobId string = containerAppsJob.id

@description('The name of the created Log Analytics workspace')
output logAnalyticsWorkspaceName string = enableMonitoring ? logAnalyticsWorkspace.name : ''

@description('The workspace ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = enableMonitoring ? logAnalyticsWorkspace.properties.customerId : ''

@description('The name of the created Application Insights instance')
output applicationInsightsName string = enableMonitoring ? applicationInsights.name : ''

@description('The Application Insights connection string')
@secure()
output applicationInsightsConnectionString string = enableMonitoring ? applicationInsights.properties.ConnectionString : ''

@description('The resource group location')
output location string = location

@description('The unique suffix used for resource naming')
output uniqueSuffix string = uniqueSuffix

@description('Configuration summary for verification')
output deploymentSummary object = {
  serviceBusNamespace: serviceBusNamespace.name
  serviceBusQueue: queueName
  containerRegistry: containerRegistry.name
  containerEnvironment: containerAppsEnvironment.name
  containerJob: containerAppsJob.name
  monitoringEnabled: enableMonitoring
  maxExecutions: maxExecutions
  minExecutions: minExecutions
  scalingThreshold: queueMessageCountThreshold
  pollingInterval: pollingIntervalSeconds
}