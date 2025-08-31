// Event-Driven AI Agent Workflows with AI Foundry and Logic Apps
// This template deploys the complete infrastructure for intelligent event processing

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Service Bus namespace pricing tier')
@allowed(['Basic', 'Standard', 'Premium'])
param serviceBusSku string = 'Standard'

@description('Logic App plan type')
@allowed(['Consumption', 'Standard'])
param logicAppPlanType string = 'Consumption'

@description('AI Foundry workspace kind')
@allowed(['Hub', 'Project'])
param aiFoundryWorkspaceKind string = 'Hub'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'recipe'
  environment: environment
  solution: 'ai-agent-workflows'
}

@description('Maximum message size in MB for Service Bus')
@minValue(1)
@maxValue(256)
param maxMessageSizeMB int = 1

@description('Message time to live in days')
@minValue(1)
@maxValue(14)
param messageTimeToLiveDays int = 14

@description('Maximum delivery count for Service Bus messages')
@minValue(1)
@maxValue(100)
param maxDeliveryCount int = 10

// ============================================================================
// VARIABLES
// ============================================================================

var namingConvention = {
  aiFoundryHub: 'aihub-workflows-${uniqueSuffix}'
  aiFoundryProject: 'aiproject-workflows-${uniqueSuffix}'
  serviceBusNamespace: 'sb-workflows-${uniqueSuffix}'
  logicAppName: 'la-ai-workflows-${uniqueSuffix}'
  storageAccount: 'sawf${uniqueSuffix}'
  applicationInsights: 'ai-workflows-${uniqueSuffix}'
  logAnalyticsWorkspace: 'law-workflows-${uniqueSuffix}'
  keyVault: 'kv-workflows-${uniqueSuffix}'
}

var serviceBusConfig = {
  queueName: 'event-processing-queue'
  topicName: 'business-events-topic'
  subscriptionName: 'ai-agent-subscription'
  maxSizeInMegabytes: maxMessageSizeMB * 1024
  defaultMessageTimeToLive: 'P${messageTimeToLiveDays}D'
}

// ============================================================================
// EXISTING RESOURCES (if needed)
// ============================================================================

// Reference to the resource group for tagging and metadata
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: resourceGroup().name
}

// ============================================================================
// MONITORING AND OBSERVABILITY
// ============================================================================

// Log Analytics Workspace for centralized logging
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: namingConvention.logAnalyticsWorkspace
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for application monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: namingConvention.applicationInsights
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

// ============================================================================
// SECURITY AND KEY MANAGEMENT
// ============================================================================

// Key Vault for secure storage of connection strings and secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: namingConvention.keyVault
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ============================================================================
// STORAGE
// ============================================================================

// Storage Account for Logic Apps and AI Foundry (if needed)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: namingConvention.storageAccount
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
}

// ============================================================================
// SERVICE BUS MESSAGING
// ============================================================================

// Service Bus Namespace for event messaging
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namingConvention.serviceBusNamespace
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
  
  // Authorization rule for accessing Service Bus
  resource authRule 'AuthorizationRules@2022-10-01-preview' = {
    name: 'RootManageSharedAccessKey'
    properties: {
      rights: [
        'Listen'
        'Manage'
        'Send'
      ]
    }
  }
}

// Service Bus Queue for direct event processing
resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: serviceBusConfig.queueName
  properties: {
    maxSizeInMegabytes: serviceBusConfig.maxSizeInMegabytes
    defaultMessageTimeToLive: serviceBusConfig.defaultMessageTimeToLive
    deadLetteringOnMessageExpiration: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enableBatchedOperations: true
    enableExpress: false
    enablePartitioning: false
    lockDuration: 'PT5M'
    maxDeliveryCount: maxDeliveryCount
    requiresDuplicateDetection: false
    requiresSession: false
  }
}

// Service Bus Topic for event distribution
resource serviceBusTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: serviceBusConfig.topicName
  properties: {
    maxSizeInMegabytes: serviceBusConfig.maxSizeInMegabytes
    defaultMessageTimeToLive: serviceBusConfig.defaultMessageTimeToLive
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enableBatchedOperations: true
    enableExpress: false
    enablePartitioning: false
    requiresDuplicateDetection: false
    supportOrdering: false
  }
}

// Service Bus Topic Subscription for AI agent processing
resource serviceBusSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: serviceBusTopic
  name: serviceBusConfig.subscriptionName
  properties: {
    maxDeliveryCount: maxDeliveryCount
    defaultMessageTimeToLive: serviceBusConfig.defaultMessageTimeToLive
    deadLetteringOnFilterEvaluationExceptions: true
    deadLetteringOnMessageExpiration: true
    enableBatchedOperations: true
    lockDuration: 'PT5M'
    requiresSession: false
  }
}

// ============================================================================
// AI FOUNDRY RESOURCES
// ============================================================================

// AI Foundry Hub workspace
resource aiFoundryHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: namingConvention.aiFoundryHub
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  kind: 'Hub'
  properties: {
    friendlyName: 'AI Workflows Hub'
    description: 'AI Foundry Hub for event-driven AI agent workflows'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: applicationInsights.id
    publicNetworkAccess: 'Enabled'
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
  }
}

// AI Foundry Project workspace (depends on Hub)
resource aiFoundryProject 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: namingConvention.aiFoundryProject
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  kind: 'Project'
  properties: {
    friendlyName: 'AI Workflows Project'
    description: 'AI Foundry Project for business event processing agents'
    hubResourceId: aiFoundryHub.id
    publicNetworkAccess: 'Enabled'
  }
  dependsOn: [
    aiFoundryHub
  ]
}

// ============================================================================
// LOGIC APPS
// ============================================================================

// Logic App for Consumption plan (serverless)
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = if (logicAppPlanType == 'Consumption') {
  name: namingConvention.logicAppName
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'When_a_message_is_received_in_a_queue': {
          type: 'ServiceBus'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/@{encodeURIComponent(encodeURIComponent(\'${serviceBusConfig.queueName}\'))}/messages/head'
            queries: {
              queueType: 'Main'
            }
          }
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
        }
      }
      actions: {
        'Parse_Event_Content': {
          type: 'ParseJson'
          inputs: {
            content: '@base64ToString(triggerBody()?[\'ContentData\'])'
            schema: {
              type: 'object'
              properties: {
                eventType: {
                  type: 'string'
                }
                content: {
                  type: 'string'
                }
                metadata: {
                  type: 'object'
                }
              }
            }
          }
        }
        'Initialize_Response_Variable': {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'AIResponse'
                type: 'string'
                value: ''
              }
            ]
          }
          runAfter: {
            'Parse_Event_Content': [
              'Succeeded'
            ]
          }
        }
        'Process_Event_with_AI_Agent': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://${location}.api.azureml.ms/v1.0/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.MachineLearningServices/workspaces/${namingConvention.aiFoundryProject}/chat/completions'
            headers: {
              'Content-Type': 'application/json'
              'Authorization': 'Bearer @{variables(\'AIResponse\')}'
            }
            body: {
              eventData: '@body(\'Parse_Event_Content\')'
              timestamp: '@utcNow()'
              instructions: 'Process this business event and determine appropriate automated actions based on the event type and content.'
            }
          }
          runAfter: {
            'Initialize_Response_Variable': [
              'Succeeded'
            ]
          }
        }
        'Log_Processing_Results': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://${applicationInsights.properties.ConnectionString}'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              eventProcessed: '@body(\'Parse_Event_Content\')'
              aiResponse: '@body(\'Process_Event_with_AI_Agent\')'
              timestamp: '@utcNow()'
              workflowRunId: '@workflow().run.name'
            }
          }
          runAfter: {
            'Process_Event_with_AI_Agent': [
              'Succeeded'
              'Failed'
            ]
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          servicebus: {
            connectionId: serviceBusConnection.id
            connectionName: 'servicebus'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/servicebus'
          }
        }
      }
    }
  }
  dependsOn: [
    serviceBusNamespace
    serviceBusQueue
    aiFoundryProject
  ]
}

// Service Bus API Connection for Logic Apps
resource serviceBusConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'servicebus-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'Service Bus Connection'
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/servicebus'
    }
    parameterValues: {
      connectionString: serviceBusNamespace::authRule.listKeys().primaryConnectionString
    }
  }
}

// ============================================================================
// RBAC ASSIGNMENTS
// ============================================================================

// Role assignments for AI Foundry to access resources
var contributorRoleDefinitionId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var serviceBusDataOwnerRoleId = '090c5cfd-751d-490a-894a-3ce6f1109419'

// AI Foundry Hub access to Storage Account
resource aiHubStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundryHub.id, storageAccount.id, contributorRoleDefinitionId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleDefinitionId)
    principalId: aiFoundryHub.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// AI Foundry Project access to Service Bus
resource aiProjectServiceBusRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundryProject.id, serviceBusNamespace.id, serviceBusDataOwnerRoleId)
  scope: serviceBusNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataOwnerRoleId)
    principalId: aiFoundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// KEY VAULT SECRETS
// ============================================================================

// Store Service Bus connection string in Key Vault
resource serviceBusConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ServiceBusConnectionString'
  properties: {
    value: serviceBusNamespace::authRule.listKeys().primaryConnectionString
    attributes: {
      enabled: true
    }
    contentType: 'Service Bus Primary Connection String'
  }
}

// Store Application Insights connection string in Key Vault
resource appInsightsConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ApplicationInsightsConnectionString'
  properties: {
    value: applicationInsights.properties.ConnectionString
    attributes: {
      enabled: true
    }
    contentType: 'Application Insights Connection String'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('The name of the deployed resource group')
output resourceGroupName string = resourceGroup().name

@description('The location where resources were deployed')
output location string = location

@description('The unique suffix used for resource naming')
output uniqueSuffix string = uniqueSuffix

@description('AI Foundry Hub resource ID')
output aiFoundryHubId string = aiFoundryHub.id

@description('AI Foundry Hub name')
output aiFoundryHubName string = aiFoundryHub.name

@description('AI Foundry Project resource ID')
output aiFoundryProjectId string = aiFoundryProject.id

@description('AI Foundry Project name')
output aiFoundryProjectName string = aiFoundryProject.name

@description('AI Foundry Project endpoint URL')
output aiFoundryProjectEndpoint string = aiFoundryProject.properties.discoveryUrl

@description('Service Bus namespace name')
output serviceBusNamespaceName string = serviceBusNamespace.name

@description('Service Bus namespace hostname')
output serviceBusNamespaceHostname string = '${serviceBusNamespace.name}.servicebus.windows.net'

@description('Service Bus queue name')
output serviceBusQueueName string = serviceBusQueue.name

@description('Service Bus topic name')
output serviceBusTopicName string = serviceBusTopic.name

@description('Service Bus subscription name')
output serviceBusSubscriptionName string = serviceBusSubscription.name

@description('Logic App name')
output logicAppName string = logicAppPlanType == 'Consumption' ? logicApp.name : 'Not deployed (Standard plan selected)'

@description('Logic App resource ID')
output logicAppId string = logicAppPlanType == 'Consumption' ? logicApp.id : ''

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Service Bus connection string (for testing purposes only)')
output serviceBusConnectionString string = serviceBusNamespace::authRule.listKeys().primaryConnectionString

@description('Deployment summary with key information')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  aiFoundryHub: aiFoundryHub.name
  aiFoundryProject: aiFoundryProject.name
  serviceBusNamespace: serviceBusNamespace.name
  logicApp: logicAppPlanType == 'Consumption' ? logicApp.name : 'Not deployed'
  keyVault: keyVault.name
  storageAccount: storageAccount.name
  environment: environment
  tags: tags
}