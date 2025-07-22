@description('Main Bicep template for Azure Intelligent Content Moderation Workflows')

// ============================================
// PARAMETERS
// ============================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Application name prefix')
param appNamePrefix string = 'content-moderation'

@description('Content Safety service tier')
@allowed(['S0'])
param contentSafetyTier string = 'S0'

@description('Service Bus namespace tier')
@allowed(['Basic', 'Standard', 'Premium'])
param serviceBusTier string = 'Standard'

@description('Storage account tier')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Premium_LRS'])
param storageAccountTier string = 'Standard_LRS'

@description('Container Apps Environment workload profiles enabled')
param enableWorkloadProfiles bool = true

@description('Container job CPU allocation')
@allowed(['0.25', '0.5', '0.75', '1.0', '1.25', '1.5', '1.75', '2.0'])
param containerCpu string = '0.5'

@description('Container job memory allocation')
@allowed(['0.5Gi', '1.0Gi', '1.5Gi', '2.0Gi', '3.0Gi', '4.0Gi'])
param containerMemory string = '1.0Gi'

@description('Container job parallelism')
@minValue(1)
@maxValue(10)
param containerParallelism int = 3

@description('Container job replica timeout in seconds')
@minValue(60)
@maxValue(3600)
param containerReplicaTimeout int = 300

@description('Container job retry limit')
@minValue(0)
@maxValue(10)
param containerRetryLimit int = 3

@description('Service Bus queue scaling trigger message count')
@minValue(1)
@maxValue(100)
param scalingMessageCount int = 5

@description('Service Bus queue max size in MB')
@allowed([1024, 2048, 3072, 4096, 5120])
param queueMaxSizeInMB int = 5120

@description('Service Bus message TTL in ISO 8601 format')
param messageTimeToLive string = 'PT24H'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Application: appNamePrefix
  Purpose: 'Content Moderation'
  ManagedBy: 'Bicep'
}

// ============================================
// VARIABLES
// ============================================

var contentSafetyName = '${appNamePrefix}-cs-${uniqueSuffix}'
var serviceBusNamespaceName = '${appNamePrefix}-sb-${uniqueSuffix}'
var storageAccountName = '${appNamePrefix}st${uniqueSuffix}'
var containerEnvironmentName = '${appNamePrefix}-cae-${uniqueSuffix}'
var containerJobName = '${appNamePrefix}-job-processor'
var logAnalyticsWorkspaceName = '${appNamePrefix}-law-${uniqueSuffix}'
var actionGroupName = '${appNamePrefix}-ag-${uniqueSuffix}'

// Service Bus specific variables
var contentQueueName = 'content-queue'
var serviceBusAuthRuleName = 'RootManageSharedAccessKey'

// Storage container names
var moderationResultsContainer = 'moderation-results'
var auditLogsContainer = 'audit-logs'

// Container image and command
var containerImage = 'mcr.microsoft.com/azure-cli:latest'
var containerCommand = [
  '/bin/bash'
  '-c'
  '''
  # Content processing script for Azure Container Apps Job
  set -e
  
  # Parse Service Bus message (simplified for demo)
  CONTENT_ID=${1:-"sample-content-$(date +%s)"}
  CONTENT_TEXT=${2:-"Sample content for moderation"}
  
  echo "Processing content ID: ${CONTENT_ID}"
  
  # Analyze content using Content Safety API
  ANALYSIS_RESULT=$(curl -s -X POST \
      "${CONTENT_SAFETY_ENDPOINT}/contentsafety/text:analyze?api-version=2023-10-01" \
      -H "Ocp-Apim-Subscription-Key: ${CONTENT_SAFETY_KEY}" \
      -H "Content-Type: application/json" \
      -d "{
          \"text\": \"${CONTENT_TEXT}\",
          \"categories\": [\"Hate\", \"SelfHarm\", \"Sexual\", \"Violence\"]
      }")
  
  # Store results in Azure Storage
  RESULT_FILE="/tmp/result-${CONTENT_ID}.json"
  echo "${ANALYSIS_RESULT}" > ${RESULT_FILE}
  
  # Upload to storage (using Azure CLI in container)
  az storage blob upload \
      --file ${RESULT_FILE} \
      --name "results/${CONTENT_ID}.json" \
      --container-name moderation-results \
      --connection-string "${STORAGE_CONNECTION}"
  
  # Create audit log entry
  AUDIT_ENTRY=$(cat << AUDIT_EOF
  {
      "contentId": "${CONTENT_ID}",
      "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
      "action": "content_moderation",
      "result": ${ANALYSIS_RESULT},
      "processor": "container-apps-job"
  }
  AUDIT_EOF
  )
  
  AUDIT_FILE="/tmp/audit-${CONTENT_ID}.json"
  echo "${AUDIT_ENTRY}" > ${AUDIT_FILE}
  
  # Upload audit log
  az storage blob upload \
      --file ${AUDIT_FILE} \
      --name "audit/$(date +%Y/%m/%d)/${CONTENT_ID}.json" \
      --container-name audit-logs \
      --connection-string "${STORAGE_CONNECTION}"
  
  echo "✅ Content ${CONTENT_ID} processed and results stored"
  '''
]

// ============================================
// RESOURCES
// ============================================

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
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
    }
  }
}

// Azure AI Content Safety Service
resource contentSafetyService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: contentSafetyName
  location: location
  tags: tags
  kind: 'ContentSafety'
  sku: {
    name: contentSafetyTier
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    apiProperties: {}
    customSubDomainName: contentSafetyName
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Service Bus Namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  tags: tags
  sku: {
    name: serviceBusTier
    tier: serviceBusTier
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// Service Bus Queue
resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: contentQueueName
  properties: {
    maxSizeInMegabytes: queueMaxSizeInMB
    defaultMessageTimeToLive: messageTimeToLive
    deadLetteringOnMessageExpiration: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    enableBatchedOperations: true
    enableExpress: false
    enablePartitioning: false
    maxDeliveryCount: 10
    requiresDuplicateDetection: false
    requiresSession: false
  }
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountTier
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
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
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

// Blob Services
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
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
      enabled: true
      days: 7
    }
    isVersioningEnabled: false
  }
}

// Moderation Results Container
resource moderationResultsContainerResource 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobServices
  name: moderationResultsContainer
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Audit Logs Container
resource auditLogsContainerResource 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobServices
  name: auditLogsContainer
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Container Apps Environment
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerEnvironmentName
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
    workloadProfiles: enableWorkloadProfiles ? [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ] : []
  }
}

// Container Apps Job
resource containerAppsJob 'Microsoft.App/jobs@2023-05-01' = {
  name: containerJobName
  location: location
  tags: tags
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      triggerType: 'Event'
      replicaTimeout: containerReplicaTimeout
      replicaRetryLimit: containerRetryLimit
      manualTriggerConfig: {
        parallelism: containerParallelism
        replicaCompletionCount: 1
      }
      eventTriggerConfig: {
        parallelism: containerParallelism
        replicaCompletionCount: 1
        scale: {
          minExecutions: 0
          maxExecutions: 10
          pollingInterval: 30
          rules: [
            {
              name: 'service-bus-rule'
              type: 'azure-servicebus'
              metadata: {
                queueName: contentQueueName
                messageCount: string(scalingMessageCount)
                namespace: serviceBusNamespaceName
              }
              auth: [
                {
                  secretRef: 'service-bus-connection'
                  triggerParameter: 'connection'
                }
              ]
            }
          ]
        }
      }
      secrets: [
        {
          name: 'content-safety-key'
          value: contentSafetyService.listKeys().key1
        }
        {
          name: 'service-bus-connection'
          value: serviceBusNamespace.listKeys().primaryConnectionString
        }
        {
          name: 'storage-connection'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
      ]
    }
    template: {
      containers: [
        {
          image: containerImage
          name: 'content-processor'
          command: containerCommand
          resources: {
            cpu: json(containerCpu)
            memory: containerMemory
          }
          env: [
            {
              name: 'CONTENT_SAFETY_ENDPOINT'
              value: contentSafetyService.properties.endpoint
            }
            {
              name: 'CONTENT_SAFETY_KEY'
              secretRef: 'content-safety-key'
            }
            {
              name: 'STORAGE_CONNECTION'
              secretRef: 'storage-connection'
            }
            {
              name: 'SERVICE_BUS_CONNECTION'
              secretRef: 'service-bus-connection'
            }
          ]
        }
      ]
    }
  }
}

// Action Group for monitoring alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'ContentMod'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    eventHubReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

// Alert Rule for High Queue Depth
resource queueDepthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'High Content Queue Depth'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when content queue has more than 50 messages'
    severity: 2
    enabled: true
    scopes: [
      serviceBusNamespace.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ActiveMessages'
          metricName: 'ActiveMessages'
          metricNamespace: 'Microsoft.ServiceBus/namespaces'
          operator: 'GreaterThan'
          threshold: 50
          timeAggregation: 'Average'
          dimensions: [
            {
              name: 'EntityName'
              operator: 'Include'
              values: [
                contentQueueName
              ]
            }
          ]
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

// Alert Rule for Processing Errors
resource processingErrorAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Content Processing Errors'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when container job execution fails'
    severity: 1
    enabled: true
    scopes: [
      containerAppsJob.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'FailedExecutions'
          metricName: 'JobExecutionCount'
          metricNamespace: 'Microsoft.App/jobs'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Total'
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
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ============================================
// OUTPUTS
// ============================================

@description('Content Safety service endpoint')
output contentSafetyEndpoint string = contentSafetyService.properties.endpoint

@description('Content Safety service resource ID')
output contentSafetyResourceId string = contentSafetyService.id

@description('Service Bus namespace name')
output serviceBusNamespace string = serviceBusNamespace.name

@description('Service Bus queue name')
output serviceBusQueueName string = contentQueueName

@description('Service Bus connection string')
output serviceBusConnectionString string = serviceBusNamespace.listKeys().primaryConnectionString

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account connection string')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Container Apps Environment name')
output containerEnvironmentName string = containerAppsEnvironment.name

@description('Container Apps Job name')
output containerJobName string = containerAppsJob.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Moderation results container URL')
output moderationResultsContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}${moderationResultsContainer}'

@description('Audit logs container URL')
output auditLogsContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}${auditLogsContainer}'

@description('Action Group resource ID')
output actionGroupResourceId string = actionGroup.id

@description('Deployment summary')
output deploymentSummary object = {
  resourceGroupName: resourceGroup().name
  location: location
  environment: environment
  contentSafetyName: contentSafetyService.name
  serviceBusNamespace: serviceBusNamespace.name
  storageAccountName: storageAccount.name
  containerEnvironmentName: containerAppsEnvironment.name
  containerJobName: containerAppsJob.name
  logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
  deploymentTimestamp: utcNow()
}