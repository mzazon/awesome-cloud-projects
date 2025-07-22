@description('Service Bus module for health monitoring system')

// Parameters
@description('Name of the Service Bus namespace')
param namespaceName string

@description('Azure region for deployment')
param location string

@description('Resource tags')
param tags object

@description('Service Bus SKU tier')
@allowed(['Basic', 'Standard', 'Premium'])
param skuTier string = 'Standard'

@description('Name of the health events queue')
param healthQueueName string

@description('Name of the remediation actions topic')
param remediationTopicName string

@description('Enable duplicate detection')
param enableDuplicateDetection bool = true

@description('Maximum message size in megabytes')
@allowed([1, 2, 3, 4, 5])
param maxMessageSizeInMegabytes int = 1

// Service Bus Namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2021-11-01' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: skuTier
    tier: skuTier
  }
  properties: {
    disableLocalAuth: false
    zoneRedundant: skuTier == 'Premium' ? true : false
  }
}

// Health Events Queue
resource healthEventsQueue 'Microsoft.ServiceBus/namespaces/queues@2021-11-01' = {
  parent: serviceBusNamespace
  name: healthQueueName
  properties: {
    lockDuration: 'PT5M'
    maxSizeInMegabytes: 2048
    requiresDuplicateDetection: enableDuplicateDetection
    requiresSession: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    duplicateDetectionHistoryTimeWindow: enableDuplicateDetection ? 'PT10M' : null
    maxDeliveryCount: 3
    enableBatchedOperations: true
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    enablePartitioning: skuTier != 'Premium'
    enableExpress: false
  }
}

// Remediation Actions Topic
resource remediationTopic 'Microsoft.ServiceBus/namespaces/topics@2021-11-01' = {
  parent: serviceBusNamespace
  name: remediationTopicName
  properties: {
    maxSizeInMegabytes: 2048
    requiresDuplicateDetection: enableDuplicateDetection
    defaultMessageTimeToLive: 'P14D'
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    duplicateDetectionHistoryTimeWindow: enableDuplicateDetection ? 'PT10M' : null
    enableBatchedOperations: true
    enablePartitioning: skuTier != 'Premium'
    enableExpress: false
    supportOrdering: false
  }
}

// Auto-Scale Handler Subscription
resource autoScaleSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2021-11-01' = {
  parent: remediationTopic
  name: 'auto-scale-handler'
  properties: {
    lockDuration: 'PT5M'
    requiresSession: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    deadLetteringOnFilterEvaluationExceptions: false
    maxDeliveryCount: 3
    enableBatchedOperations: true
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
  }
}

// Auto-Scale Handler Subscription Rule
resource autoScaleSubscriptionRule 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2021-11-01' = {
  parent: autoScaleSubscription
  name: 'ScaleActionFilter'
  properties: {
    filterType: 'CorrelationFilter'
    correlationFilter: {
      properties: {
        ActionType: 'scale'
      }
    }
  }
}

// Restart Handler Subscription
resource restartSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2021-11-01' = {
  parent: remediationTopic
  name: 'restart-handler'
  properties: {
    lockDuration: 'PT5M'
    requiresSession: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    deadLetteringOnFilterEvaluationExceptions: false
    maxDeliveryCount: 3
    enableBatchedOperations: true
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
  }
}

// Restart Handler Subscription Rule
resource restartSubscriptionRule 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2021-11-01' = {
  parent: restartSubscription
  name: 'RestartActionFilter'
  properties: {
    filterType: 'CorrelationFilter'
    correlationFilter: {
      properties: {
        ActionType: 'restart'
      }
    }
  }
}

// All Actions Subscription (for logging/monitoring)
resource allActionsSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2021-11-01' = {
  parent: remediationTopic
  name: 'all-actions-logger'
  properties: {
    lockDuration: 'PT1M'
    requiresSession: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: false
    deadLetteringOnFilterEvaluationExceptions: false
    maxDeliveryCount: 1
    enableBatchedOperations: true
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
  }
}

// Service Bus Authorization Rules
resource serviceBusAuthRule 'Microsoft.ServiceBus/namespaces/authorizationrules@2021-11-01' = {
  parent: serviceBusNamespace
  name: 'HealthMonitoringRule'
  properties: {
    rights: [
      'Listen'
      'Send'
      'Manage'
    ]
  }
}

// Outputs
@description('Service Bus namespace name')
output namespaceName string = serviceBusNamespace.name

@description('Service Bus namespace resource ID')
output namespaceId string = serviceBusNamespace.id

@description('Service Bus connection string')
@secure()
output connectionString string = listKeys(serviceBusAuthRule.id, serviceBusAuthRule.apiVersion).primaryConnectionString

@description('Service Bus namespace endpoint')
output serviceBusEndpoint string = serviceBusNamespace.properties.serviceBusEndpoint

@description('Health events queue name')
output healthQueueName string = healthEventsQueue.name

@description('Remediation topic name')
output remediationTopicName string = remediationTopic.name