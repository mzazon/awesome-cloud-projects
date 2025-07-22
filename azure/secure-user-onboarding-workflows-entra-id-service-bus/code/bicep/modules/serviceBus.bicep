// ==============================================================================
// Service Bus Module for Reliable Messaging
// ==============================================================================
// This module creates an Azure Service Bus namespace with queue and topic
// for reliable message processing in the user onboarding workflow
// ==============================================================================

@description('Service Bus namespace name')
param namespaceName string

@description('Location for Service Bus namespace')
param location string

@description('Service Bus SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param skuName string = 'Standard'

@description('Service Bus queue name')
param queueName string

@description('Service Bus topic name')
param topicName string

@description('Authorization rule name')
param authRuleName string = 'RootManageSharedAccessKey'

@description('Message retention in days')
@minValue(1)
@maxValue(14)
param messageRetentionDays int = 14

@description('Maximum delivery count')
@minValue(1)
@maxValue(10)
param maxDeliveryCount int = 5

@description('Enable duplicate detection')
param enableDuplicateDetection bool = true

@description('Tags to apply to Service Bus resources')
param tags object = {}

@description('Enable diagnostic logs')
param enableDiagnostics bool = true

@description('Log Analytics workspace ID for diagnostics')
param logAnalyticsWorkspaceId string = ''

@description('Zone redundancy enabled')
param zoneRedundant bool = false

// ==============================================================================
// VARIABLES
// ==============================================================================

var messageRetentionTimeSpan = 'P${messageRetentionDays}D'
var lockDuration = 'PT5M'
var duplicateDetectionHistoryTimeWindow = 'PT10M'
var defaultMessageTtl = 'P14D'

var serviceBusProperties = {
  serviceBusEndpoint: 'https://${namespaceName}.servicebus.windows.net:443/'
  status: 'Active'
  zoneRedundant: zoneRedundant
}

// ==============================================================================
// RESOURCES
// ==============================================================================

// Create Service Bus namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName
  }
  properties: serviceBusProperties
}

// Create Service Bus queue
resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: queueName
  properties: {
    lockDuration: lockDuration
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: enableDuplicateDetection
    requiresSession: false
    defaultMessageTimeToLive: defaultMessageTtl
    deadLetteringOnMessageExpiration: true
    duplicateDetectionHistoryTimeWindow: duplicateDetectionHistoryTimeWindow
    maxDeliveryCount: maxDeliveryCount
    status: 'Active'
    enableBatchedOperations: true
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    enablePartitioning: false
    enableExpress: false
  }
}

// Create Service Bus topic
resource serviceBusTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: topicName
  properties: {
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: enableDuplicateDetection
    defaultMessageTimeToLive: defaultMessageTtl
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    duplicateDetectionHistoryTimeWindow: duplicateDetectionHistoryTimeWindow
    enableBatchedOperations: true
    status: 'Active'
    supportOrdering: true
    enablePartitioning: false
    enableExpress: false
  }
}

// Create default subscription for the topic
resource serviceBusSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: serviceBusTopic
  name: 'default-subscription'
  properties: {
    lockDuration: lockDuration
    requiresSession: false
    defaultMessageTimeToLive: defaultMessageTtl
    deadLetteringOnMessageExpiration: true
    deadLetteringOnFilterEvaluationExceptions: true
    maxDeliveryCount: maxDeliveryCount
    status: 'Active'
    enableBatchedOperations: true
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
  }
}

// Create authorization rule for Logic Apps access
resource serviceBusAuthRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: authRuleName
  properties: {
    rights: [
      'Send'
      'Listen'
      'Manage'
    ]
  }
}

// Diagnostic settings for Service Bus namespace
resource serviceBusDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && !empty(logAnalyticsWorkspaceId)) {
  name: 'servicebus-diagnostics'
  scope: serviceBusNamespace
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'OperationalLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'VNetAndIPFilteringLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'RuntimeAuditLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('Service Bus namespace resource ID')
output serviceBusResourceId string = serviceBusNamespace.id

@description('Service Bus namespace resource reference')
output serviceBusResource resource = serviceBusNamespace

@description('Service Bus namespace name')
output namespaceName string = serviceBusNamespace.name

@description('Service Bus namespace endpoint')
output serviceBusEndpoint string = serviceBusNamespace.properties.serviceBusEndpoint

@description('Service Bus queue name')
output queueName string = serviceBusQueue.name

@description('Service Bus topic name')
output topicName string = serviceBusTopic.name

@description('Service Bus subscription name')
output subscriptionName string = serviceBusSubscription.name

@description('Service Bus connection string')
@secure()
output connectionString string = serviceBusAuthRule.listKeys().primaryConnectionString

@description('Service Bus primary key')
@secure()
output primaryKey string = serviceBusAuthRule.listKeys().primaryKey

@description('Service Bus secondary key')
@secure()
output secondaryKey string = serviceBusAuthRule.listKeys().secondaryKey

@description('Service Bus SKU')
output skuName string = serviceBusNamespace.sku.name

@description('Service Bus zone redundancy status')
output zoneRedundant bool = serviceBusNamespace.properties.zoneRedundant

@description('Service Bus namespace status')
output status string = serviceBusNamespace.properties.status