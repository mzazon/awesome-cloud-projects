@description('Name of the resource group. Will be created if it does not exist.')
param resourceGroupName string = 'rg-lifecycle-demo'

@description('Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment tag for resources')
@allowed(['development', 'testing', 'production'])
param environment string = 'development'

@description('Base name for storage account (will be appended with random suffix)')
param storageAccountBaseName string = 'stlifecycle'

@description('Name for the Logic App')
param logicAppName string = 'logic-storage-alerts'

@description('Name for the Log Analytics workspace')
param workspaceName string = 'law-storage-monitoring'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Hot tier lifecycle policy - days after modification to move to cool tier')
param documentsCoolTierDays int = 30

@description('Hot tier lifecycle policy - days after modification to move to archive tier')
param documentsArchiveTierDays int = 90

@description('Hot tier lifecycle policy - days after modification to delete')
param documentsDeleteDays int = 365

@description('Log lifecycle policy - days after modification to move to cool tier')
param logsCoolTierDays int = 7

@description('Log lifecycle policy - days after modification to move to archive tier')
param logsArchiveTierDays int = 30

@description('Log lifecycle policy - days after modification to delete')
param logsDeleteDays int = 180

@description('Storage capacity alert threshold in bytes')
param storageCapacityThreshold int = 1000000000

@description('Transaction count alert threshold')
param transactionCountThreshold int = 1000

@description('Email address for alert notifications')
param alertEmailAddress string = ''

@description('Log Analytics workspace retention in days')
param logAnalyticsRetentionDays int = 30

// Generate unique suffix for storage account name
var uniqueSuffix = uniqueString(resourceGroup().id, deployment().name)
var storageAccountName = '${storageAccountBaseName}${uniqueSuffix}'

// Common tags for all resources
var commonTags = {
  purpose: 'lifecycle-demo'
  environment: environment
  deployedBy: 'bicep'
  createdDate: utcNow('yyyy-MM-dd')
}

// Storage Account with lifecycle management capabilities
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    isHnsEnabled: false
    networkAcls: {
      defaultAction: 'Allow'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Blob Services configuration with versioning and soft delete
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    versioning: {
      enabled: true
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: []
    }
  }
}

// Lifecycle Management Policy
resource lifecycleManagementPolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          enabled: true
          name: 'DocumentLifecycle'
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: [
                'blockBlob'
              ]
              prefixMatch: [
                'documents/'
              ]
            }
            actions: {
              baseBlob: {
                tierToCool: {
                  daysAfterModificationGreaterThan: documentsCoolTierDays
                }
                tierToArchive: {
                  daysAfterModificationGreaterThan: documentsArchiveTierDays
                }
                delete: {
                  daysAfterModificationGreaterThan: documentsDeleteDays
                }
              }
              version: {
                tierToCool: {
                  daysAfterCreationGreaterThan: documentsCoolTierDays
                }
                tierToArchive: {
                  daysAfterCreationGreaterThan: documentsArchiveTierDays
                }
                delete: {
                  daysAfterCreationGreaterThan: documentsDeleteDays
                }
              }
            }
          }
        }
        {
          enabled: true
          name: 'LogLifecycle'
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: [
                'blockBlob'
              ]
              prefixMatch: [
                'logs/'
              ]
            }
            actions: {
              baseBlob: {
                tierToCool: {
                  daysAfterModificationGreaterThan: logsCoolTierDays
                }
                tierToArchive: {
                  daysAfterModificationGreaterThan: logsArchiveTierDays
                }
                delete: {
                  daysAfterModificationGreaterThan: logsDeleteDays
                }
              }
              version: {
                tierToCool: {
                  daysAfterCreationGreaterThan: logsCoolTierDays
                }
                tierToArchive: {
                  daysAfterCreationGreaterThan: logsArchiveTierDays
                }
                delete: {
                  daysAfterCreationGreaterThan: logsDeleteDays
                }
              }
            }
          }
        }
      ]
    }
  }
}

// Create sample containers for testing
resource documentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'documents'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'document-storage'
      lifecyclePolicy: 'DocumentLifecycle'
    }
  }
}

resource logsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'logs'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'log-storage'
      lifecyclePolicy: 'LogLifecycle'
    }
  }
}

// Log Analytics Workspace for storage monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'pergb2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Diagnostic Settings for Storage Account
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'StorageAccountMonitoring'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'Capacity'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Diagnostic Settings for Blob Services
resource blobServicesDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'BlobStorageMonitoring'
  scope: blobServices
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'StorageRead'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'StorageWrite'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'StorageDelete'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'Capacity'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Action Group for alert notifications
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'StorageAlertsGroup'
  location: 'global'
  tags: commonTags
  properties: {
    groupShortName: 'StorageAlerts'
    enabled: true
    emailReceivers: empty(alertEmailAddress) ? [] : [
      {
        name: 'StorageAdmin'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// Logic App for automated alerting and workflows
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
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
                alertType: {
                  type: 'string'
                }
                message: {
                  type: 'string'
                }
                timestamp: {
                  type: 'string'
                }
              }
            }
          }
        }
      }
      actions: {
        'Initialize_Response': {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'response'
                type: 'string'
                value: 'Alert received and processed'
              }
            ]
          }
        }
        'Response': {
          type: 'Response'
          inputs: {
            statusCode: 200
            body: '@variables(\'response\')'
          }
          runAfter: {
            'Initialize_Response': [
              'Succeeded'
            ]
          }
        }
      }
      outputs: {}
    }
  }
}

// Storage Capacity Alert
resource storageCapacityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'HighStorageCapacity'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'Alert when storage capacity exceeds threshold'
    severity: 2
    enabled: true
    scopes: [
      storageAccount.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'StorageCapacityCondition'
          metricName: 'UsedCapacity'
          metricNamespace: 'Microsoft.Storage/storageAccounts'
          operator: 'GreaterThan'
          threshold: storageCapacityThreshold
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
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

// Transaction Count Alert
resource transactionCountAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'HighTransactionCount'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'Alert when transaction count is high'
    severity: 3
    enabled: true
    scopes: [
      storageAccount.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'TransactionCountCondition'
          metricName: 'Transactions'
          metricNamespace: 'Microsoft.Storage/storageAccounts'
          operator: 'GreaterThan'
          threshold: transactionCountThreshold
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
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

// Outputs for verification and integration
@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('Storage Account ID')
output storageAccountId string = storageAccount.id

@description('Storage Account Primary Endpoint')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Logic App Name')
output logicAppName string = logicApp.name

@description('Logic App ID')
output logicAppId string = logicApp.id

@description('Logic App Trigger URL')
output logicAppTriggerUrl string = listCallbackURL(resourceId('Microsoft.Logic/workflows/triggers', logicApp.name, 'manual'), '2019-05-01').value

@description('Action Group Name')
output actionGroupName string = actionGroup.name

@description('Action Group ID')
output actionGroupId string = actionGroup.id

@description('Storage Account Connection String')
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Documents Container Name')
output documentsContainerName string = documentsContainer.name

@description('Logs Container Name')
output logsContainerName string = logsContainer.name

@description('Lifecycle Management Policy Status')
output lifecyclePolicyEnabled bool = lifecycleManagementPolicy.properties.policy.rules[0].enabled

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Deployment Location')
output deploymentLocation string = location

@description('Common Tags Applied')
output commonTags object = commonTags