// ==============================================================================
// Azure Bicep Template for Financial Fraud Detection Solution
// ==============================================================================
// This template deploys a comprehensive fraud detection solution using:
// - Azure AI Metrics Advisor for anomaly detection
// - Azure AI Immersive Reader for accessible fraud alerts
// - Azure Logic Apps for workflow orchestration
// - Azure Storage for data and processing
// - Azure Monitor for comprehensive monitoring
// ==============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, test, prod)')
param environment string = 'dev'

@description('Unique suffix for resource names')
param resourceSuffix string = uniqueString(resourceGroup().id, deployment().name)

@description('Azure AI Metrics Advisor SKU')
@allowed(['F0', 'S0'])
param metricsAdvisorSku string = 'F0'

@description('Azure AI Immersive Reader SKU')
@allowed(['F0', 'S0'])
param immersiveReaderSku string = 'F0'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Log Analytics workspace retention in days')
param logAnalyticsRetentionInDays int = 30

@description('Email address for fraud alerts')
param alertEmailAddress string = 'compliance@company.com'

@description('Enable monitoring and alerting')
param enableMonitoring bool = true

@description('Resource tags')
param tags object = {
  Environment: environment
  Project: 'FraudDetection'
  CostCenter: 'Security'
  Owner: 'ComplianceTeam'
}

// ==============================================================================
// VARIABLES
// ==============================================================================

var resourceNames = {
  metricsAdvisor: 'ma-fraud-${resourceSuffix}'
  immersiveReader: 'ir-fraud-${resourceSuffix}'
  logicApp: 'la-fraud-workflow-${resourceSuffix}'
  storageAccount: 'stfraud${resourceSuffix}'
  logAnalytics: 'law-fraud-monitoring-${resourceSuffix}'
  appInsights: 'ai-fraud-insights-${resourceSuffix}'
  keyVault: 'kv-fraud-${resourceSuffix}'
  actionGroup: 'ag-fraud-alerts-${resourceSuffix}'
}

// ==============================================================================
// AZURE STORAGE ACCOUNT
// ==============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    encryption: {
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
  }

  resource blobService 'blobServices' = {
    name: 'default'
    properties: {
      cors: {
        corsRules: []
      }
      deleteRetentionPolicy: {
        enabled: true
        days: 7
      }
    }
  }
}

// Storage containers for transaction data and fraud alerts
resource transactionDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: storageAccount::blobService
  name: 'transaction-data'
  properties: {
    publicAccess: 'None'
  }
}

resource fraudAlertsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: storageAccount::blobService
  name: 'fraud-alerts'
  properties: {
    publicAccess: 'None'
  }
}

resource processingContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: storageAccount::blobService
  name: 'processing'
  properties: {
    publicAccess: 'None'
  }
}

// ==============================================================================
// AZURE KEY VAULT
// ==============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: []
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// ==============================================================================
// AZURE AI METRICS ADVISOR
// ==============================================================================

resource metricsAdvisor 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: resourceNames.metricsAdvisor
  location: location
  tags: tags
  sku: {
    name: metricsAdvisorSku
  }
  kind: 'MetricsAdvisor'
  properties: {
    apiProperties: {}
    customSubDomainName: resourceNames.metricsAdvisor
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    disableLocalAuth: false
    restore: false
    restrictOutboundNetworkAccess: false
  }
}

// Store Metrics Advisor key in Key Vault
resource metricsAdvisorKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'metrics-advisor-key'
  properties: {
    value: metricsAdvisor.listKeys().key1
    attributes: {
      enabled: true
    }
  }
}

// ==============================================================================
// AZURE AI IMMERSIVE READER
// ==============================================================================

resource immersiveReader 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: resourceNames.immersiveReader
  location: location
  tags: tags
  sku: {
    name: immersiveReaderSku
  }
  kind: 'ImmersiveReader'
  properties: {
    apiProperties: {}
    customSubDomainName: resourceNames.immersiveReader
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    disableLocalAuth: false
    restore: false
    restrictOutboundNetworkAccess: false
  }
}

// Store Immersive Reader key in Key Vault
resource immersiveReaderKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'immersive-reader-key'
  properties: {
    value: immersiveReader.listKeys().key1
    attributes: {
      enabled: true
    }
  }
}

// ==============================================================================
// LOG ANALYTICS WORKSPACE
// ==============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableMonitoring) {
  name: resourceNames.logAnalytics
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ==============================================================================
// APPLICATION INSIGHTS
// ==============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableMonitoring) {
  name: resourceNames.appInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableMonitoring ? logAnalyticsWorkspace.id : null
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ==============================================================================
// ACTION GROUP FOR ALERTS
// ==============================================================================

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (enableMonitoring) {
  name: resourceNames.actionGroup
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'FraudAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'ComplianceTeam'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    azureFunction: []
    logicAppReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    armRoleReceivers: []
  }
}

// ==============================================================================
// AZURE LOGIC APPS
// ==============================================================================

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: resourceNames.logicApp
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        metricsAdvisorEndpoint: {
          type: 'string'
          defaultValue: metricsAdvisor.properties.endpoint
        }
        immersiveReaderEndpoint: {
          type: 'string'
          defaultValue: immersiveReader.properties.endpoint
        }
        storageAccountName: {
          type: 'string'
          defaultValue: storageAccount.name
        }
        keyVaultName: {
          type: 'string'
          defaultValue: keyVault.name
        }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                alertId: {
                  type: 'string'
                }
                severity: {
                  type: 'string'
                }
                anomalyData: {
                  type: 'object'
                  properties: {
                    description: {
                      type: 'string'
                    }
                    affectedMetrics: {
                      type: 'array'
                      items: {
                        type: 'string'
                      }
                    }
                    confidenceScore: {
                      type: 'number'
                    }
                    timestamp: {
                      type: 'string'
                    }
                  }
                }
              }
            }
          }
        }
      }
      actions: {
        'Initialize_Alert_Processing': {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'AlertSummary'
                type: 'object'
                value: {
                  alert_id: '@{triggerBody()[\'alertId\']}'
                  severity: '@{triggerBody()[\'severity\']}'
                  detected_at: '@{utcNow()}'
                  description: '@{triggerBody()[\'anomalyData\'][\'description\']}'
                  confidence_score: '@{triggerBody()[\'anomalyData\'][\'confidenceScore\']}'
                  recommendation: 'Immediate review required for potential fraud investigation'
                }
              }
            ]
          }
        }
        'Create_Accessible_Text': {
          type: 'Compose'
          inputs: 'FRAUD ALERT SUMMARY\n\nAlert ID: @{variables(\'AlertSummary\')[\'alert_id\']}\nSeverity: @{toUpper(variables(\'AlertSummary\')[\'severity\'])}\nTime Detected: @{variables(\'AlertSummary\')[\'detected_at\']}\n\nDescription: @{variables(\'AlertSummary\')[\'description\']}\n\nRecommendation: @{variables(\'AlertSummary\')[\'recommendation\']}\n\nConfidence Score: @{variables(\'AlertSummary\')[\'confidence_score\']}\n\nPlease review the attached details and take appropriate action.'
          runAfter: {
            'Initialize_Alert_Processing': [
              'Succeeded'
            ]
          }
        }
        'Store_Alert_Data': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: '@variables(\'AlertSummary\')'
            path: '/v2/datasets/@{encodeURIComponent(parameters(\'storageAccountName\'))}/files'
            queries: {
              folderPath: '/fraud-alerts'
              name: 'alert-@{variables(\'AlertSummary\')[\'alert_id\']}-@{formatDateTime(utcNow(), \'yyyyMMddHHmmss\')}.json'
              queryParametersSingleEncoded: true
            }
          }
          runAfter: {
            'Create_Accessible_Text': [
              'Succeeded'
            ]
          }
        }
        'Send_Email_Notification': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              To: alertEmailAddress
              Subject: 'Fraud Alert - @{variables(\'AlertSummary\')[\'alert_id\']}'
              Body: '@{outputs(\'Create_Accessible_Text\')}'
              Importance: 'High'
            }
            path: '/v2/Mail'
          }
          runAfter: {
            'Store_Alert_Data': [
              'Succeeded'
            ]
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          azureblob: {
            connectionId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/connections/azureblob-connection'
            connectionName: 'azureblob-connection'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azureblob'
          }
          office365: {
            connectionId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/connections/office365-connection'
            connectionName: 'office365-connection'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/office365'
          }
        }
      }
    }
  }
}

// ==============================================================================
// MONITORING ALERTS
// ==============================================================================

resource metricsAdvisorFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: 'fraud-detection-failures'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when fraud detection service experiences failures'
    severity: 2
    enabled: true
    scopes: [
      metricsAdvisor.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ErrorRateCondition'
          metricName: 'Errors'
          metricNamespace: 'Microsoft.CognitiveServices/accounts'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Count'
          dimensions: []
          skipMetricValidation: false
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: enableMonitoring ? actionGroup.id : ''
        webHookProperties: {}
      }
    ]
  }
}

resource logicAppFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: 'logic-app-failures'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when Logic App workflow experiences failures'
    severity: 2
    enabled: true
    scopes: [
      logicApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'RunsFailedCondition'
          metricName: 'RunsFailed'
          metricNamespace: 'Microsoft.Logic/workflows'
          operator: 'GreaterThan'
          threshold: 2
          timeAggregation: 'Count'
          dimensions: []
          skipMetricValidation: false
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: enableMonitoring ? actionGroup.id : ''
        webHookProperties: {}
      }
    ]
  }
}

// ==============================================================================
// DIAGNOSTIC SETTINGS
// ==============================================================================

resource metricsAdvisorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: 'metrics-advisor-diagnostics'
  scope: metricsAdvisor
  properties: {
    workspaceId: enableMonitoring ? logAnalyticsWorkspace.id : null
    logs: [
      {
        category: 'Audit'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionInDays
        }
      }
      {
        category: 'RequestResponse'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionInDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionInDays
        }
      }
    ]
  }
}

resource logicAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: 'logic-app-diagnostics'
  scope: logicApp
  properties: {
    workspaceId: enableMonitoring ? logAnalyticsWorkspace.id : null
    logs: [
      {
        category: 'WorkflowRuntime'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionInDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionInDays
        }
      }
    ]
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Azure AI Metrics Advisor endpoint')
output metricsAdvisorEndpoint string = metricsAdvisor.properties.endpoint

@description('Azure AI Metrics Advisor resource name')
output metricsAdvisorName string = metricsAdvisor.name

@description('Azure AI Immersive Reader endpoint')
output immersiveReaderEndpoint string = immersiveReader.properties.endpoint

@description('Azure AI Immersive Reader resource name')
output immersiveReaderName string = immersiveReader.name

@description('Logic App resource name')
output logicAppName string = logicApp.name

@description('Logic App trigger URL')
output logicAppTriggerUrl string = logicApp.listCallbackUrl().value

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Storage Account primary endpoint')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = enableMonitoring ? logAnalyticsWorkspace.name : ''

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = enableMonitoring ? logAnalyticsWorkspace.properties.customerId : ''

@description('Application Insights name')
output applicationInsightsName string = enableMonitoring ? applicationInsights.name : ''

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = enableMonitoring ? applicationInsights.properties.InstrumentationKey : ''

@description('Action Group name')
output actionGroupName string = enableMonitoring ? actionGroup.name : ''

@description('Resource naming suffix used')
output resourceSuffix string = resourceSuffix

@description('All resource names created')
output resourceNames object = resourceNames

@description('Connection information for external integrations')
output connectionInfo object = {
  metricsAdvisor: {
    endpoint: metricsAdvisor.properties.endpoint
    keyVaultSecretName: 'metrics-advisor-key'
  }
  immersiveReader: {
    endpoint: immersiveReader.properties.endpoint
    keyVaultSecretName: 'immersive-reader-key'
  }
  storage: {
    accountName: storageAccount.name
    blobEndpoint: storageAccount.properties.primaryEndpoints.blob
    containers: [
      'transaction-data'
      'fraud-alerts'
      'processing'
    ]
  }
  logicApp: {
    name: logicApp.name
    triggerUrl: logicApp.listCallbackUrl().value
  }
  keyVault: {
    name: keyVault.name
    uri: keyVault.properties.vaultUri
  }
  monitoring: enableMonitoring ? {
    logAnalyticsWorkspaceId: logAnalyticsWorkspace.properties.customerId
    applicationInsightsInstrumentationKey: applicationInsights.properties.InstrumentationKey
  } : {}
}