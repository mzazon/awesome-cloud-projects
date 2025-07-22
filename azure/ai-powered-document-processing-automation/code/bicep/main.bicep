@description('Main Bicep template for Intelligent Business Process Automation with Azure OpenAI Assistants and Container Apps Jobs')

// Parameters
@description('The location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Environment name for resource naming')
param environment string = 'demo'

@description('OpenAI model name to deploy')
param openAiModelName string = 'gpt-4'

@description('OpenAI model version')
param openAiModelVersion string = '0613'

@description('Service Bus SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param serviceBusSkuName string = 'Standard'

@description('Container Registry SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param containerRegistrySkuName string = 'Basic'

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Maximum replicas for Container Apps Jobs')
@minValue(1)
@maxValue(10)
param maxReplicas int = 3

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'intelligent-automation'
  environment: environment
  solution: 'openai-container-apps'
}

// Variables
var resourcePrefix = 'ia-${environment}-${uniqueSuffix}'
var openAiAccountName = '${resourcePrefix}-openai'
var serviceBusNamespaceName = '${resourcePrefix}-sb'
var containerRegistryName = replace('${resourcePrefix}acr', '-', '')
var containerEnvName = '${resourcePrefix}-aca-env'
var logAnalyticsWorkspaceName = '${resourcePrefix}-law'
var appInsightsName = '${resourcePrefix}-ai'
var managedIdentityName = '${resourcePrefix}-mi'

// Resources

// Managed Identity for Container Apps
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 10
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
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
    Flow_Type: 'Redfield'
    Request_Source: 'IbizaAIExtension'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Azure OpenAI Service
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: openAiAccountName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: openAiAccountName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// OpenAI Model Deployment
resource openAiModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openAiAccount
  name: openAiModelName
  sku: {
    name: 'Standard'
    capacity: 10
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiModelName
      version: openAiModelVersion
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.Default'
  }
}

// Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: containerRegistrySkuName
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
      exportPolicy: {
        status: 'enabled'
      }
      azureADAuthenticationAsArmPolicy: {
        status: 'enabled'
      }
      softDeletePolicy: {
        retentionDays: 7
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

// Service Bus Namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2023-01-01-preview' = {
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

// Service Bus Queue for Processing Tasks
resource processingQueue 'Microsoft.ServiceBus/namespaces/queues@2023-01-01-preview' = {
  parent: serviceBusNamespace
  name: 'processing-queue'
  properties: {
    lockDuration: 'PT1M'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    requiresSession: false
    defaultMessageTimeToLive: 'PT10M'
    deadLetteringOnMessageExpiration: false
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    maxDeliveryCount: 10
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    enablePartitioning: false
    enableExpress: false
  }
}

// Service Bus Topic for Results Broadcasting
resource processingResultsTopic 'Microsoft.ServiceBus/namespaces/topics@2023-01-01-preview' = {
  parent: serviceBusNamespace
  name: 'processing-results'
  properties: {
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    defaultMessageTimeToLive: 'P14D'
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enablePartitioning: false
    enableExpress: false
    supportOrdering: false
  }
}

// Service Bus Topic Subscription for Notifications
resource notificationSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2023-01-01-preview' = {
  parent: processingResultsTopic
  name: 'notification-sub'
  properties: {
    lockDuration: 'PT1M'
    requiresSession: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: false
    deadLetteringOnFilterEvaluationExceptions: true
    maxDeliveryCount: 10
    autoDeleteOnIdle: 'P14D'
    enablePartitioning: false
  }
}

// Service Bus Authorization Rules
resource serviceBusAuthRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2023-01-01-preview' = {
  parent: serviceBusNamespace
  name: 'ContainerAppsAccess'
  properties: {
    rights: [
      'Listen'
      'Send'
      'Manage'
    ]
  }
}

// Container Apps Environment
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-11-02-preview' = {
  name: containerEnvName
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
    openTelemetryConfiguration: {
      tracesConfiguration: {
        destinations: ['appInsights']
      }
      logsConfiguration: {
        destinations: ['appInsights']
      }
      destinationsConfiguration: {
        appInsights: {
          connectionString: applicationInsights.properties.ConnectionString
        }
      }
    }
    zoneRedundant: false
    kedaConfiguration: {}
    daprConfiguration: {}
    customDomainConfiguration: {
      dnsSuffix: ''
      certificatePassword: ''
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// Role Assignments for Managed Identity
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, managedIdentity.id, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource serviceBusDataOwnerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBusNamespace.id, managedIdentity.id, 'ServiceBusDataOwner')
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '090c5cfd-751d-490a-894a-3ce6f1109419') // Azure Service Bus Data Owner
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource cognitiveServicesUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, managedIdentity.id, 'CognitiveServicesUser')
  scope: openAiAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908') // Cognitive Services User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Container Apps Job for Document Processing
resource documentProcessorJob 'Microsoft.App/jobs@2023-11-02-preview' = {
  name: '${resourcePrefix}-doc-processor'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      scheduleTriggerConfig: null
      eventTriggerConfig: {
        replicaCompletionCount: 1
        parallelism: maxReplicas
        scale: {
          minExecutions: 0
          maxExecutions: 10
          pollingInterval: 30
          rules: [
            {
              name: 'servicebus-scale'
              type: 'azure-servicebus'
              metadata: {
                queueName: processingQueue.name
                messageCount: '1'
                connectionFromEnv: 'SERVICEBUS_CONNECTION'
                activationMessageCount: '0'
              }
            }
          ]
        }
      }
      replicaTimeout: 300
      replicaRetryLimit: 2
      manualTriggerConfig: null
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: managedIdentity.id
        }
      ]
      secrets: [
        {
          name: 'servicebus-connection'
          value: serviceBusAuthRule.listKeys().primaryConnectionString
        }
        {
          name: 'openai-endpoint'
          value: openAiAccount.properties.endpoint
        }
        {
          name: 'openai-key'
          value: openAiAccount.listKeys().key1
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'document-processor'
          image: '${containerRegistry.properties.loginServer}/processing-job:latest'
          env: [
            {
              name: 'SERVICEBUS_CONNECTION'
              secretRef: 'servicebus-connection'
            }
            {
              name: 'OPENAI_ENDPOINT'
              secretRef: 'openai-endpoint'
            }
            {
              name: 'OPENAI_KEY'
              secretRef: 'openai-key'
            }
            {
              name: 'QUEUE_NAME'
              value: processingQueue.name
            }
            {
              name: 'TOPIC_NAME'
              value: processingResultsTopic.name
            }
          ]
          resources: {
            cpu: '0.5'
            memory: '1Gi'
          }
        }
      ]
    }
  }
  dependsOn: [
    acrPullRole
    serviceBusDataOwnerRole
  ]
}

// Container Apps Job for Notification Service
resource notificationServiceJob 'Microsoft.App/jobs@2023-11-02-preview' = {
  name: '${resourcePrefix}-notification'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      scheduleTriggerConfig: null
      eventTriggerConfig: {
        replicaCompletionCount: 1
        parallelism: 2
        scale: {
          minExecutions: 0
          maxExecutions: 5
          pollingInterval: 30
          rules: [
            {
              name: 'servicebus-topic-scale'
              type: 'azure-servicebus'
              metadata: {
                topicName: processingResultsTopic.name
                subscriptionName: notificationSubscription.name
                messageCount: '1'
                connectionFromEnv: 'SERVICEBUS_CONNECTION'
                activationMessageCount: '0'
              }
            }
          ]
        }
      }
      replicaTimeout: 120
      replicaRetryLimit: 2
      manualTriggerConfig: null
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: managedIdentity.id
        }
      ]
      secrets: [
        {
          name: 'servicebus-connection'
          value: serviceBusAuthRule.listKeys().primaryConnectionString
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'notification-service'
          image: '${containerRegistry.properties.loginServer}/notification-job:latest'
          env: [
            {
              name: 'SERVICEBUS_CONNECTION'
              secretRef: 'servicebus-connection'
            }
            {
              name: 'TOPIC_NAME'
              value: processingResultsTopic.name
            }
            {
              name: 'SUBSCRIPTION_NAME'
              value: notificationSubscription.name
            }
          ]
          resources: {
            cpu: '0.25'
            memory: '0.5Gi'
          }
        }
      ]
    }
  }
  dependsOn: [
    acrPullRole
    serviceBusDataOwnerRole
  ]
}

// Monitoring Alert Rules
resource highOpenAiUsageAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${resourcePrefix}-high-openai-usage'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when OpenAI API usage is high'
    severity: 2
    enabled: true
    scopes: [
      openAiAccount.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'TokenUsage'
          metricName: 'ProcessedTokens'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 10000
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.CognitiveServices/accounts'
    targetResourceRegion: location
    actions: []
  }
}

resource containerJobFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${resourcePrefix}-job-failure-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when Container Apps Jobs fail frequently'
    severity: 1
    enabled: true
    scopes: [
      documentProcessorJob.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'JobExecutionCount'
          metricName: 'JobExecutionCount'
          dimensions: [
            {
              name: 'ExecutionStatus'
              operator: 'Include'
              values: [
                'Failed'
              ]
            }
          ]
          operator: 'GreaterThan'
          threshold: 3
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.App/jobs'
    targetResourceRegion: location
    actions: []
  }
}

// Outputs
@description('Azure OpenAI Service endpoint')
output openAiEndpoint string = openAiAccount.properties.endpoint

@description('Azure OpenAI Service name')
output openAiAccountName string = openAiAccount.name

@description('Service Bus namespace name')
output serviceBusNamespaceName string = serviceBusNamespace.name

@description('Service Bus connection string')
output serviceBusConnectionString string = serviceBusAuthRule.listKeys().primaryConnectionString

@description('Container Registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('Container Apps Environment name')
output containerAppsEnvironmentName string = containerAppsEnvironment.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Managed Identity Principal ID')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Managed Identity Client ID')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Document Processor Job Name')
output documentProcessorJobName string = documentProcessorJob.name

@description('Notification Service Job Name')
output notificationServiceJobName string = notificationServiceJob.name

@description('Processing Queue Name')
output processingQueueName string = processingQueue.name

@description('Processing Results Topic Name')
output processingResultsTopicName string = processingResultsTopic.name

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Deployment Location')
output deploymentLocation string = location