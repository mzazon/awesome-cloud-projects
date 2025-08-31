@description('The name of the Service Bus namespace')
param serviceBusNamespaceName string = 'sbns-demo-${uniqueString(resourceGroup().id)}'

@description('The name of the Service Bus queue')
param queueName string = 'orders'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Service Bus SKU tier')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param serviceBusSku string = 'Standard'

@description('The maximum size of the queue in megabytes')
@minValue(1024)
@maxValue(5120)
param maxSizeInMegabytes int = 1024

@description('Default message time to live as an ISO 8601 duration')
param defaultMessageTimeToLive string = 'P14D'

@description('Enable dead lettering on message expiration')
param enableDeadLetteringOnMessageExpiration bool = true

@description('Tags to apply to all resources')
param tags object = {
  environment: 'demo'
  purpose: 'recipe'
  'created-by': 'bicep-template'
}

// Service Bus Namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  tags: tags
  sku: {
    name: serviceBusSku
    tier: serviceBusSku
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
  }
}

// Service Bus Queue
resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: queueName
  parent: serviceBusNamespace
  properties: {
    maxSizeInMegabytes: maxSizeInMegabytes
    defaultMessageTimeToLive: defaultMessageTimeToLive
    deadLetteringOnMessageExpiration: enableDeadLetteringOnMessageExpiration
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enableBatchedOperations: true
    enableExpress: false
    enablePartitioning: false
    lockDuration: 'PT1M'
    maxDeliveryCount: 10
    requiresDuplicateDetection: false
    requiresSession: false
    status: 'Active'
  }
}

// Authorization rule for accessing the Service Bus namespace
resource serviceBusAuthRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  name: 'RootManageSharedAccessKey'
  parent: serviceBusNamespace
  properties: {
    rights: [
      'Listen'
      'Manage'
      'Send'
    ]
  }
}

// Diagnostic settings for monitoring (optional but recommended)
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: serviceBusNamespace
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
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

@description('The name of the created Service Bus namespace')
output serviceBusNamespaceName string = serviceBusNamespace.name

@description('The resource ID of the Service Bus namespace')
output serviceBusNamespaceId string = serviceBusNamespace.id

@description('The name of the created Service Bus queue')
output queueName string = serviceBusQueue.name

@description('The primary connection string for the Service Bus namespace')
output connectionString string = serviceBusAuthRule.listKeys().primaryConnectionString

@description('The primary key for the Service Bus namespace')
output primaryKey string = serviceBusAuthRule.listKeys().primaryKey

@description('The Service Bus namespace hostname')
output serviceBusEndpoint string = serviceBusNamespace.properties.serviceBusEndpoint

@description('The status of the Service Bus namespace')
output namespaceStatus string = serviceBusNamespace.properties.status

@description('The SKU tier of the Service Bus namespace')
output skuTier string = serviceBusNamespace.sku.tier

@description('Queue properties for verification')
output queueProperties object = {
  maxSizeInMegabytes: serviceBusQueue.properties.maxSizeInMegabytes
  defaultMessageTimeToLive: serviceBusQueue.properties.defaultMessageTimeToLive
  deadLetteringOnMessageExpiration: serviceBusQueue.properties.deadLetteringOnMessageExpiration
  maxDeliveryCount: serviceBusQueue.properties.maxDeliveryCount
  lockDuration: serviceBusQueue.properties.lockDuration
}