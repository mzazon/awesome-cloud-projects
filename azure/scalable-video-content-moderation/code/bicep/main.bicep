// ====================================================================================================
// Azure Intelligent Video Content Moderation Infrastructure
// ====================================================================================================
// This Bicep template deploys a complete video content moderation solution using:
// - Azure AI Vision for content analysis
// - Azure Event Hubs for high-throughput event streaming
// - Azure Stream Analytics for real-time processing
// - Azure Logic Apps for response workflow automation
// - Azure Storage for processed data
// ====================================================================================================

@description('Specifies the Azure region for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Owner tag for all resources')
param owner string = 'video-moderation-team'

@description('Application name for resource naming')
param applicationName string = 'videomod'

// AI Vision Service Configuration
@description('Azure AI Vision service SKU')
@allowed(['F0', 'S1'])
param aiVisionSku string = 'S1'

// Event Hubs Configuration
@description('Event Hubs namespace SKU')
@allowed(['Basic', 'Standard'])
param eventHubsSku string = 'Standard'

@description('Event Hubs throughput units')
@minValue(1)
@maxValue(20)
param eventHubsThroughputUnits int = 2

@description('Event Hub partition count')
@minValue(2)
@maxValue(32)
param eventHubPartitionCount int = 4

@description('Event Hub message retention in days')
@minValue(1)
@maxValue(7)
param eventHubRetentionDays int = 1

// Stream Analytics Configuration
@description('Stream Analytics streaming units')
@minValue(1)
@maxValue(48)
param streamAnalyticsStreamingUnits int = 3

// Storage Configuration
@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Premium_LRS'])
param storageAccountSku string = 'Standard_LRS'

// ====================================================================================================
// Variables
// ====================================================================================================

var resourceNames = {
  aiVision: 'cv-${applicationName}-${uniqueSuffix}'
  eventHubNamespace: 'evhns-${applicationName}-${uniqueSuffix}'
  eventHub: 'video-frames'
  storageAccount: 'st${applicationName}${uniqueSuffix}'
  streamAnalytics: 'asa-${applicationName}-${uniqueSuffix}'
  logicApp: 'logic-${applicationName}-${uniqueSuffix}'
  logAnalytics: 'log-${applicationName}-${uniqueSuffix}'
}

var commonTags = {
  Environment: environment
  Application: applicationName
  Owner: owner
  Purpose: 'video-content-moderation'
  DeployedBy: 'bicep-template'
  'Cost-Center': 'ai-services'
}

// ====================================================================================================
// Log Analytics Workspace (for monitoring and diagnostics)
// ====================================================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalytics
  location: location
  tags: commonTags
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

// ====================================================================================================
// Azure AI Vision Service
// ====================================================================================================

resource aiVisionService 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: resourceNames.aiVision
  location: location
  tags: commonTags
  kind: 'ComputerVision'
  sku: {
    name: aiVisionSku
  }
  properties: {
    customSubDomainName: resourceNames.aiVision
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    apiProperties: {
      statisticsEnabled: false
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Diagnostic settings for AI Vision
resource aiVisionDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diagnostics'
  scope: aiVisionService
  properties: {
    workspaceId: logAnalyticsWorkspace.id
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

// ====================================================================================================
// Azure Storage Account
// ====================================================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: commonTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
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
    accessTier: 'Hot'
  }
}

// Blob services configuration
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    changeFeed: {
      enabled: false
    }
    restorePolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: true
      days: 7
    }
    isVersioningEnabled: false
  }
}

// Container for moderation results
resource moderationResultsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'moderation-results'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Container for video frames (if needed for temporary storage)
resource videoFramesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'video-frames'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Storage diagnostic settings
resource storageDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// ====================================================================================================
// Azure Event Hubs Namespace and Event Hub
// ====================================================================================================

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: resourceNames.eventHubNamespace
  location: location
  tags: commonTags
  sku: {
    name: eventHubsSku
    tier: eventHubsSku
    capacity: eventHubsThroughputUnits
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: true
    maximumThroughputUnits: 10
    kafkaEnabled: false
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Event Hub for video frames
resource videoFramesEventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubNamespace
  name: resourceNames.eventHub
  properties: {
    messageRetentionInDays: eventHubRetentionDays
    partitionCount: eventHubPartitionCount
    status: 'Active'
    captureDescription: {
      enabled: false
    }
  }
}

// Authorization rule for Stream Analytics
resource eventHubAuthRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: videoFramesEventHub
  name: 'StreamAnalyticsAccess'
  properties: {
    rights: ['Listen', 'Send']
  }
}

// Event Hub diagnostic settings
resource eventHubDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diagnostics'
  scope: eventHubNamespace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
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

// ====================================================================================================
// Azure Stream Analytics Job
// ====================================================================================================

resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: resourceNames.streamAnalytics
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'Standard'
    }
    outputErrorPolicy: 'Stop'
    eventsOutOfOrderPolicy: 'Adjust'
    eventsOutOfOrderMaxDelayInSeconds: 0
    eventsLateArrivalMaxDelayInSeconds: 5
    dataLocale: 'en-US'
    compatibilityLevel: '1.2'
    contentStoragePolicy: 'SystemAccount'
    jobType: 'Cloud'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Stream Analytics Input (Event Hub)
resource streamAnalyticsInput 'Microsoft.StreamAnalytics/streamingjobs/inputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'VideoFrameInput'
  properties: {
    type: 'Stream'
    datasource: {
      type: 'Microsoft.ServiceBus/EventHub'
      properties: {
        eventHubName: resourceNames.eventHub
        serviceBusNamespace: resourceNames.eventHubNamespace
        sharedAccessPolicyName: eventHubAuthRule.name
        sharedAccessPolicyKey: eventHubAuthRule.listKeys().primaryKey
        authenticationMode: 'ConnectionString'
      }
    }
    serialization: {
      type: 'Json'
      properties: {
        encoding: 'UTF8'
      }
    }
  }
}

// Stream Analytics Output (Storage Account)
resource streamAnalyticsOutput 'Microsoft.StreamAnalytics/streamingjobs/outputs@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'ModerationOutput'
  properties: {
    datasource: {
      type: 'Microsoft.Storage/Blob'
      properties: {
        storageAccounts: [
          {
            accountName: storageAccount.name
            accountKey: storageAccount.listKeys().keys[0].value
          }
        ]
        container: moderationResultsContainer.name
        pathPattern: 'year={datetime:yyyy}/month={datetime:MM}/day={datetime:dd}/hour={datetime:HH}'
        dateFormat: 'yyyy/MM/dd'
        timeFormat: 'HH'
        authenticationMode: 'ConnectionString'
      }
    }
    serialization: {
      type: 'Json'
      properties: {
        encoding: 'UTF8'
        format: 'LineSeparated'
      }
    }
  }
}

// Stream Analytics Transformation (Query)
resource streamAnalyticsTransformation 'Microsoft.StreamAnalytics/streamingjobs/transformations@2021-10-01-preview' = {
  parent: streamAnalyticsJob
  name: 'ModerationTransformation'
  properties: {
    streamingUnits: streamAnalyticsStreamingUnits
    query: '''
      WITH ProcessedFrames AS (
          SELECT 
              videoId,
              frameUrl,
              timestamp,
              userId,
              channelId,
              System.Timestamp() AS ProcessingTime
          FROM VideoFrameInput
          WHERE frameUrl IS NOT NULL
      ),
      ModerationResults AS (
          SELECT 
              videoId,
              frameUrl,
              timestamp,
              userId,
              channelId,
              ProcessingTime,
              -- Simulate AI Vision API call results (replace with actual AI Vision integration)
              CASE 
                  WHEN LEN(videoId) % 10 < 2 THEN 0.85  -- 20% flagged content
                  ELSE 0.15 
              END AS adultScore,
              CASE 
                  WHEN LEN(videoId) % 10 < 1 THEN 0.75  -- 10% racy content
                  ELSE 0.05 
              END AS racyScore
          FROM ProcessedFrames
      )
      SELECT 
          videoId,
          frameUrl,
          timestamp,
          userId,
          channelId,
          ProcessingTime,
          adultScore,
          racyScore,
          CASE 
              WHEN adultScore > 0.7 OR racyScore > 0.6 THEN 'BLOCKED'
              WHEN adultScore > 0.5 OR racyScore > 0.4 THEN 'REVIEW'
              ELSE 'APPROVED'
          END AS moderationDecision,
          CASE 
              WHEN adultScore > 0.7 OR racyScore > 0.6 THEN 1
              ELSE 0
          END AS requiresAction
      INTO ModerationOutput
      FROM ModerationResults
    '''
  }
}

// Stream Analytics diagnostic settings
resource streamAnalyticsDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diagnostics'
  scope: streamAnalyticsJob
  properties: {
    workspaceId: logAnalyticsWorkspace.id
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

// ====================================================================================================
// Azure Logic App (Workflow for Content Moderation Response)
// ====================================================================================================

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: resourceNames.logicApp
  location: location
  tags: commonTags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                videoId: {
                  type: 'string'
                }
                frameTimestamp: {
                  type: 'string'
                }
                moderationScore: {
                  type: 'number'
                }
                contentFlags: {
                  type: 'array'
                }
                moderationDecision: {
                  type: 'string'
                }
                userId: {
                  type: 'string'
                }
                channelId: {
                  type: 'string'
                }
              }
              required: [
                'videoId'
                'moderationDecision'
              ]
            }
          }
        }
      }
      actions: {
        'Check_Moderation_Decision': {
          type: 'Switch'
          expression: '@triggerBody()[\'moderationDecision\']'
          cases: {
            'BLOCKED': {
              case: 'BLOCKED'
              actions: {
                'Send_Critical_Alert': {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: 'https://httpbin.org/post'
                    headers: {
                      'Content-Type': 'application/json'
                    }
                    body: {
                      alertType: 'CRITICAL'
                      message: 'Inappropriate content detected and blocked'
                      videoId: '@{triggerBody()[\'videoId\']}'
                      userId: '@{triggerBody()[\'userId\']}'
                      channelId: '@{triggerBody()[\'channelId\']}'
                      moderationScore: '@{triggerBody()[\'moderationScore\']}'
                      timestamp: '@{utcNow()}'
                      action: 'Content automatically blocked'
                    }
                  }
                }
                'Log_Blocked_Content': {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: 'https://httpbin.org/post'
                    headers: {
                      'Content-Type': 'application/json'
                    }
                    body: {
                      logType: 'CONTENT_BLOCKED'
                      videoId: '@{triggerBody()[\'videoId\']}'
                      timestamp: '@{utcNow()}'
                      details: 'Content blocked by automated moderation system'
                    }
                  }
                  runAfter: {
                    'Send_Critical_Alert': [
                      'Succeeded'
                    ]
                  }
                }
              }
            }
            'REVIEW': {
              case: 'REVIEW'
              actions: {
                'Send_Review_Notification': {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: 'https://httpbin.org/post'
                    headers: {
                      'Content-Type': 'application/json'
                    }
                    body: {
                      alertType: 'REVIEW_REQUIRED'
                      message: 'Content requires human review'
                      videoId: '@{triggerBody()[\'videoId\']}'
                      userId: '@{triggerBody()[\'userId\']}'
                      channelId: '@{triggerBody()[\'channelId\']}'
                      moderationScore: '@{triggerBody()[\'moderationScore\']}'
                      timestamp: '@{utcNow()}'
                      action: 'Content flagged for manual review'
                    }
                  }
                }
                'Create_Review_Task': {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: 'https://httpbin.org/post'
                    headers: {
                      'Content-Type': 'application/json'
                    }
                    body: {
                      taskType: 'MANUAL_REVIEW'
                      videoId: '@{triggerBody()[\'videoId\']}'
                      priority: 'HIGH'
                      assignedTo: 'moderation-team'
                      timestamp: '@{utcNow()}'
                    }
                  }
                  runAfter: {
                    'Send_Review_Notification': [
                      'Succeeded'
                    ]
                  }
                }
              }
            }
          }
          default: {
            actions: {
              'Log_Approved_Content': {
                type: 'Http'
                inputs: {
                  method: 'POST'
                  uri: 'https://httpbin.org/post'
                  headers: {
                    'Content-Type': 'application/json'
                  }
                  body: {
                    logType: 'CONTENT_APPROVED'
                    videoId: '@{triggerBody()[\'videoId\']}'
                    timestamp: '@{utcNow()}'
                    details: 'Content approved by automated moderation system'
                  }
                }
              }
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {}
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Logic App diagnostic settings
resource logicAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diagnostics'
  scope: logicApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
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

// ====================================================================================================
// Role Assignments for Managed Identities
// ====================================================================================================

// Storage Blob Data Contributor role for Stream Analytics
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, streamAnalyticsJob.id, 'StorageBlobDataContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: streamAnalyticsJob.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Event Hubs Data Receiver role for Stream Analytics
resource eventHubRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: eventHubNamespace
  name: guid(eventHubNamespace.id, streamAnalyticsJob.id, 'EventHubsDataReceiver')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde') // Azure Event Hubs Data Receiver
    principalId: streamAnalyticsJob.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ====================================================================================================
// Outputs
// ====================================================================================================

@description('The resource ID of the Azure AI Vision service')
output aiVisionResourceId string = aiVisionService.id

@description('The endpoint URL of the Azure AI Vision service')
output aiVisionEndpoint string = aiVisionService.properties.endpoint

@description('The primary key of the Azure AI Vision service')
@secure()
output aiVisionPrimaryKey string = aiVisionService.listKeys().key1

@description('The resource ID of the Event Hubs namespace')
output eventHubNamespaceResourceId string = eventHubNamespace.id

@description('The connection string for the Event Hub')
@secure()
output eventHubConnectionString string = eventHubAuthRule.listKeys().primaryConnectionString

@description('The name of the Event Hub')
output eventHubName string = videoFramesEventHub.name

@description('The resource ID of the Stream Analytics job')
output streamAnalyticsJobResourceId string = streamAnalyticsJob.id

@description('The name of the Stream Analytics job')
output streamAnalyticsJobName string = streamAnalyticsJob.name

@description('The resource ID of the storage account')
output storageAccountResourceId string = storageAccount.id

@description('The primary connection string of the storage account')
@secure()
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'

@description('The name of the moderation results container')
output moderationResultsContainer string = moderationResultsContainer.name

@description('The resource ID of the Logic App')
output logicAppResourceId string = logicApp.id

@description('The trigger URL of the Logic App')
output logicAppTriggerUrl string = logicApp.listCallbackUrl().value

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceResourceId string = logAnalyticsWorkspace.id

@description('All resource names created by this template')
output resourceNames object = resourceNames

@description('Common tags applied to all resources')
output commonTags object = commonTags

@description('Summary of deployed resources')
output deploymentSummary object = {
  aiVisionService: {
    name: aiVisionService.name
    sku: aiVisionSku
    endpoint: aiVisionService.properties.endpoint
  }
  eventHub: {
    namespace: eventHubNamespace.name
    eventHub: videoFramesEventHub.name
    partitionCount: eventHubPartitionCount
    retentionDays: eventHubRetentionDays
  }
  streamAnalytics: {
    name: streamAnalyticsJob.name
    streamingUnits: streamAnalyticsStreamingUnits
  }
  storage: {
    name: storageAccount.name
    sku: storageAccountSku
    containers: [
      moderationResultsContainer.name
      videoFramesContainer.name
    ]
  }
  logicApp: {
    name: logicApp.name
    state: logicApp.properties.state
  }
  monitoring: {
    logAnalytics: logAnalyticsWorkspace.name
  }
}