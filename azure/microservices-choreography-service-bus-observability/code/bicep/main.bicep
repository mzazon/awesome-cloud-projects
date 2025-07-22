// ====================================================================================================
// Microservices Choreography with Service Bus and Observability
// ====================================================================================================
// This Bicep template deploys a complete microservices choreography solution using:
// - Azure Service Bus Premium for high-performance event-driven messaging
// - Azure Container Apps for scalable microservices hosting
// - Azure Functions for serverless event processing
// - Azure Monitor and Application Insights for comprehensive observability
// - Azure Monitor Workbooks for distributed tracing visualization
// ====================================================================================================

targetScope = 'resourceGroup'

// ====================================================================================================
// Parameters
// ====================================================================================================

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environmentName string = 'dev'

@description('Base name for all resources')
param baseName string = 'choreography'

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id, deployment().name)

@description('Service Bus Premium capacity (1-4 messaging units)')
@allowed([1, 2, 4])
param serviceBusCapacity int = 1

@description('Container Apps minimum replica count')
@minValue(0)
@maxValue(5)
param containerAppsMinReplicas int = 1

@description('Container Apps maximum replica count')
@minValue(1)
@maxValue(30)
param containerAppsMaxReplicas int = 10

@description('Function App consumption plan location')
param functionAppConsumptionPlanLocation string = location

@description('Container image for microservices')
param containerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Enable Azure Monitor Workbooks for distributed tracing')
param enableWorkbooks bool = true

@description('Enable zone redundancy for Service Bus Premium')
param enableZoneRedundancy bool = false

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logRetentionInDays int = 30

@description('Tags to be applied to all resources')
param tags object = {
  Environment: environmentName
  Application: 'microservices-choreography'
  Purpose: 'event-driven-architecture'
  CostCenter: 'IT'
  CreatedBy: 'bicep-deployment'
}

// ====================================================================================================
// Variables
// ====================================================================================================

var resourceNames = {
  serviceBusNamespace: 'sb-${baseName}-${environmentName}-${uniqueSuffix}'
  logAnalyticsWorkspace: 'log-${baseName}-${environmentName}-${uniqueSuffix}'
  applicationInsights: 'ai-${baseName}-${environmentName}-${uniqueSuffix}'
  containerAppsEnvironment: 'cae-${baseName}-${environmentName}-${uniqueSuffix}'
  storageAccount: 'st${baseName}${environmentName}${uniqueSuffix}'
  hostingPlan: 'plan-${baseName}-${environmentName}-${uniqueSuffix}'
  orderService: 'order-service-${environmentName}'
  inventoryService: 'inventory-service-${environmentName}'
  paymentService: 'payment-service-${environmentName}'
  shippingService: 'shipping-service-${environmentName}'
  workbookName: 'workbook-${baseName}-${environmentName}-${uniqueSuffix}'
}

var serviceBusTopics = [
  'order-events'
  'payment-events'
  'inventory-events'
  'shipping-events'
]

var serviceBusSubscriptions = [
  {
    topicName: 'order-events'
    subscriptionName: 'payment-service-sub'
  }
  {
    topicName: 'order-events'
    subscriptionName: 'inventory-service-sub'
  }
  {
    topicName: 'payment-events'
    subscriptionName: 'shipping-service-sub'
  }
  {
    topicName: 'payment-events'
    subscriptionName: 'order-service-payment-sub'
  }
  {
    topicName: 'inventory-events'
    subscriptionName: 'order-service-inventory-sub'
  }
  {
    topicName: 'inventory-events'
    subscriptionName: 'shipping-service-inventory-sub'
  }
  {
    topicName: 'shipping-events'
    subscriptionName: 'order-service-shipping-sub'
  }
  {
    topicName: 'order-events'
    subscriptionName: 'high-priority-orders'
  }
]

var containerApps = [
  {
    name: 'order-service'
    ingressType: 'external'
    targetPort: 80
    serviceName: 'order-service'
  }
  {
    name: 'inventory-service'
    ingressType: 'internal'
    targetPort: 80
    serviceName: 'inventory-service'
  }
]

var functionApps = [
  {
    name: 'payment-service'
    serviceName: 'payment-service'
  }
  {
    name: 'shipping-service'
    serviceName: 'shipping-service'
  }
]

// ====================================================================================================
// Log Analytics Workspace
// ====================================================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// ====================================================================================================
// Application Insights
// ====================================================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
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

// ====================================================================================================
// Service Bus Premium Namespace
// ====================================================================================================

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: resourceNames.serviceBusNamespace
  location: location
  tags: tags
  sku: {
    name: 'Premium'
    tier: 'Premium'
    capacity: serviceBusCapacity
  }
  properties: {
    premiumMessagingPartitions: 1
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: enableZoneRedundancy
  }
}

// ====================================================================================================
// Service Bus Topics
// ====================================================================================================

resource serviceBusTopicsRes 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = [for topic in serviceBusTopics: {
  name: topic
  parent: serviceBusNamespace
  properties: {
    maxMessageSizeInKilobytes: 1024
    defaultMessageTimeToLive: 'P14D'
    maxSizeInMegabytes: 5120
    requiresDuplicateDetection: false
    enableBatchedOperations: true
    supportOrdering: true
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    enablePartitioning: false
    enableExpress: false
  }
}]

// ====================================================================================================
// Service Bus Subscriptions
// ====================================================================================================

resource serviceBusSubscriptionsRes 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = [for subscription in serviceBusSubscriptions: {
  name: subscription.subscriptionName
  parent: serviceBusTopicsRes[indexOf(serviceBusTopics, subscription.topicName)]
  properties: {
    lockDuration: 'PT1M'
    requiresSession: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    deadLetteringOnFilterEvaluationExceptions: false
    maxDeliveryCount: 3
    enableBatchedOperations: true
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
  }
}]

// ====================================================================================================
// Service Bus Message Filtering Rules
// ====================================================================================================

resource highPriorityRule 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2022-10-01-preview' = {
  name: 'HighPriorityRule'
  parent: serviceBusSubscriptionsRes[length(serviceBusSubscriptions) - 1] // high-priority-orders subscription
  properties: {
    filterType: 'SqlFilter'
    sqlFilter: {
      sqlExpression: "Priority = 'High'"
    }
  }
}

// ====================================================================================================
// Service Bus Dead Letter Queue
// ====================================================================================================

resource serviceBusDeadLetterQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'failed-events-dlq'
  parent: serviceBusNamespace
  properties: {
    lockDuration: 'PT1M'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    requiresSession: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 3
    enableBatchedOperations: true
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    enablePartitioning: false
    enableExpress: false
  }
}

// ====================================================================================================
// Container Apps Environment
// ====================================================================================================

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: resourceNames.containerAppsEnvironment
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

// ====================================================================================================
// Order Service Container App
// ====================================================================================================

resource orderServiceContainerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: resourceNames.orderService
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      secrets: [
        {
          name: 'service-bus-connection'
          value: serviceBusNamespace.listKeys().primaryConnectionString
        }
        {
          name: 'appinsights-connection'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'order-service'
          image: containerImage
          env: [
            {
              name: 'SERVICE_BUS_CONNECTION'
              secretRef: 'service-bus-connection'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-connection'
            }
            {
              name: 'SERVICE_NAME'
              value: 'order-service'
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: containerAppsMinReplicas
        maxReplicas: containerAppsMaxReplicas
        rules: [
          {
            name: 'http-scale'
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

// ====================================================================================================
// Inventory Service Container App
// ====================================================================================================

resource inventoryServiceContainerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: resourceNames.inventoryService
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 80
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      secrets: [
        {
          name: 'service-bus-connection'
          value: serviceBusNamespace.listKeys().primaryConnectionString
        }
        {
          name: 'appinsights-connection'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'inventory-service'
          image: containerImage
          env: [
            {
              name: 'SERVICE_BUS_CONNECTION'
              secretRef: 'service-bus-connection'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-connection'
            }
            {
              name: 'SERVICE_NAME'
              value: 'inventory-service'
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: containerAppsMinReplicas
        maxReplicas: containerAppsMaxReplicas
        rules: [
          {
            name: 'service-bus-scale'
            custom: {
              type: 'azure-servicebus'
              metadata: {
                topicName: 'order-events'
                subscriptionName: 'inventory-service-sub'
                messageCount: '5'
              }
              auth: [
                {
                  secretRef: 'service-bus-connection'
                  triggerParameter: 'connection'
                }
              ]
            }
          }
        ]
      }
    }
  }
}

// ====================================================================================================
// Storage Account for Azure Functions
// ====================================================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: resourceNames.storageAccount
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
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    networkAcls: {
      defaultAction: 'Allow'
    }
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

// ====================================================================================================
// App Service Plan for Azure Functions
// ====================================================================================================

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: resourceNames.hostingPlan
  location: functionAppConsumptionPlanLocation
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    computeMode: 'Dynamic'
    reserved: false
  }
}

// ====================================================================================================
// Payment Service Function App
// ====================================================================================================

resource paymentServiceFunctionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: resourceNames.paymentService
  location: functionAppConsumptionPlanLocation
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlan.id
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
          value: toLower(resourceNames.paymentService)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'SERVICE_BUS_CONNECTION'
          value: serviceBusNamespace.listKeys().primaryConnectionString
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
        {
          name: 'SERVICE_NAME'
          value: 'payment-service'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      netFrameworkVersion: 'v6.0'
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
  }
}

// ====================================================================================================
// Shipping Service Function App
// ====================================================================================================

resource shippingServiceFunctionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: resourceNames.shippingService
  location: functionAppConsumptionPlanLocation
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlan.id
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
          value: toLower(resourceNames.shippingService)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'SERVICE_BUS_CONNECTION'
          value: serviceBusNamespace.listKeys().primaryConnectionString
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
        {
          name: 'SERVICE_NAME'
          value: 'shipping-service'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      netFrameworkVersion: 'v6.0'
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
  }
}

// ====================================================================================================
// Azure Monitor Workbook for Distributed Tracing
// ====================================================================================================

resource choreographyWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = if (enableWorkbooks && enableApplicationInsights) {
  name: guid(resourceGroup().id, 'choreography-workbook')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Microservices Choreography Dashboard'
    category: 'workbook'
    sourceId: applicationInsights.id
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        {
          type: 1
          content: {
            json: '# Microservices Choreography Dashboard\n\nThis workbook provides comprehensive observability for event-driven microservices choreography patterns using Azure Service Bus Premium and distributed tracing.'
          }
          name: 'title'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'requests\n| where cloud_RoleName in ("order-service", "inventory-service", "payment-service", "shipping-service")\n| summarize RequestCount = count() by bin(timestamp, 5m), cloud_RoleName\n| render timechart'
            size: 0
            title: 'Request Volume by Service'
          }
          name: 'requestVolume'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'dependencies\n| where type == "Azure Service Bus"\n| summarize MessageCount = count() by bin(timestamp, 5m), cloud_RoleName\n| render timechart'
            size: 0
            title: 'Service Bus Messages by Service'
          }
          name: 'serviceBusMessages'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'requests\n| where cloud_RoleName in ("order-service", "inventory-service", "payment-service", "shipping-service")\n| summarize AvgDuration = avg(duration) by cloud_RoleName\n| render barchart'
            size: 0
            title: 'Average Response Time by Service'
          }
          name: 'responseTime'
        }
      ]
    })
    version: '1.0'
    timeModified: utcNow()
  }
}

// ====================================================================================================
// High Priority Order Subscription with Message Filtering
// ====================================================================================================

resource highPriorityOrderSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  name: 'high-priority-orders'
  parent: serviceBusTopicsRes[indexOf(serviceBusTopics, 'order-events')]
  properties: {
    lockDuration: 'PT1M'
    requiresSession: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    deadLetteringOnFilterEvaluationExceptions: false
    maxDeliveryCount: 3
    enableBatchedOperations: true
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
  }
}

resource highPriorityOrderFilter 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2022-10-01-preview' = {
  name: 'HighPriorityRule'
  parent: highPriorityOrderSubscription
  properties: {
    filterType: 'SqlFilter'
    sqlFilter: {
      sqlExpression: "Priority = 'High'"
    }
  }
}

// ====================================================================================================
// Outputs
// ====================================================================================================

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Service Bus Namespace Name')
output serviceBusNamespaceName string = serviceBusNamespace.name

@description('Service Bus Connection String')
output serviceBusConnectionString string = serviceBusNamespace.listKeys().primaryConnectionString

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Application Insights Name')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Container Apps Environment Name')
output containerAppsEnvironmentName string = containerAppsEnvironment.name

@description('Order Service URL')
output orderServiceUrl string = 'https://${orderServiceContainerApp.properties.configuration.ingress.fqdn}'

@description('Inventory Service Name')
output inventoryServiceName string = inventoryServiceContainerApp.name

@description('Payment Service Function App Name')
output paymentServiceFunctionAppName string = paymentServiceFunctionApp.name

@description('Shipping Service Function App Name')
output shippingServiceFunctionAppName string = shippingServiceFunctionApp.name

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('Service Bus Topics')
output serviceBusTopics array = serviceBusTopics

@description('Dead Letter Queue Name')
output deadLetterQueueName string = serviceBusDeadLetterQueue.name

@description('Azure Monitor Workbook Name')
output workbookName string = enableWorkbooks && enableApplicationInsights ? choreographyWorkbook.name : ''

@description('Deployment Summary')
output deploymentSummary object = {
  serviceBusNamespace: serviceBusNamespace.name
  serviceBusTopics: length(serviceBusTopics)
  serviceBusSubscriptions: length(serviceBusSubscriptions)
  containerApps: 2
  functionApps: 2
  applicationInsights: enableApplicationInsights
  workbooks: enableWorkbooks && enableApplicationInsights
  environment: environmentName
  location: location
}