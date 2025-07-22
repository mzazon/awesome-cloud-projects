@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Resource naming prefix')
param prefix string = 'cv-retrain'

@description('Environment name (dev, test, prod)')
param environment string = 'dev'

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Custom Vision service SKU')
@allowed([
  'F0'
  'S0'
])
param customVisionSku string = 'S0'

@description('Log Analytics workspace SKU')
@allowed([
  'PerGB2018'
  'Free'
  'Standalone'
  'PerNode'
])
param logAnalyticsSku string = 'PerGB2018'

@description('Tags to apply to all resources')
param tags object = {
  environment: environment
  purpose: 'ml-automation'
  recipe: 'intelligent-vision-model-retraining'
}

// Variables for resource naming
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var storageAccountName = '${prefix}st${uniqueSuffix}'
var customVisionName = '${prefix}-cv-${uniqueSuffix}'
var logicAppName = '${prefix}-logic-${uniqueSuffix}'
var logAnalyticsName = '${prefix}-log-${uniqueSuffix}'
var applicationInsightsName = '${prefix}-ai-${uniqueSuffix}'

// Storage containers to create
var storageContainers = [
  'training-images'
  'model-artifacts'
  'processed-images'
]

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsSku
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Storage Account for training data and model artifacts
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: false
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      keySource: 'Microsoft.Storage'
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
    }
    accessTier: 'Hot'
  }
}

// Blob Services for storage account
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
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
  }
}

// Storage containers for different data types
resource storageContainers_resource 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for containerName in storageContainers: {
  parent: blobServices
  name: containerName
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}]

// Custom Vision Service (Training)
resource customVisionService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: customVisionName
  location: location
  tags: tags
  sku: {
    name: customVisionSku
  }
  kind: 'CustomVision.Training'
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
    customSubDomainName: customVisionName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Logic App for workflow automation
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
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
        storageAccountName: {
          defaultValue: storageAccountName
          type: 'String'
        }
        customVisionEndpoint: {
          defaultValue: customVisionService.properties.endpoint
          type: 'String'
        }
        customVisionKey: {
          defaultValue: customVisionService.listKeys().key1
          type: 'String'
        }
      }
      triggers: {
        'When_a_blob_is_added_or_modified': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/datasets/default/triggers/batch/onupdatedfile'
            queries: {
              folderId: 'training-images'
              maxFileCount: 10
            }
          }
          recurrence: {
            frequency: 'Minute'
            interval: 5
          }
          metadata: {
            'training-images': 'training-images'
          }
        }
      }
      actions: {
        'Get_project_configuration': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/datasets/default/files/@{encodeURIComponent(\'model-artifacts/project-config.json\')}/content'
          }
        }
        'Parse_project_config': {
          type: 'ParseJson'
          inputs: {
            content: '@body(\'Get_project_configuration\')'
            schema: {
              properties: {
                projectId: {
                  type: 'string'
                }
                endpoint: {
                  type: 'string'
                }
                trainingKey: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
          runAfter: {
            'Get_project_configuration': [
              'Succeeded'
            ]
          }
        }
        'Start_training': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '@{body(\'Parse_project_config\')[\'endpoint\']}customvision/v3.0/Training/projects/@{body(\'Parse_project_config\')[\'projectId\']}/train'
            headers: {
              'Training-Key': '@{body(\'Parse_project_config\')[\'trainingKey\']}'
              'Content-Type': 'application/json'
            }
          }
          runAfter: {
            'Parse_project_config': [
              'Succeeded'
            ]
          }
        }
        'Log_training_started': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '@{concat(\'https://\', parameters(\'storageAccountName\'), \'.blob.core.windows.net/model-artifacts/training-log-\', utcnow(), \'.json\')}'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              message: 'Training started for project @{body(\'Parse_project_config\')[\'projectId\']}'
              timestamp: '@{utcnow()}'
              level: 'Info'
            }
          }
          runAfter: {
            'Start_training': [
              'Succeeded'
            ]
          }
        }
        'Handle_training_failure': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '@{concat(\'https://\', parameters(\'storageAccountName\'), \'.blob.core.windows.net/model-artifacts/training-error-\', utcnow(), \'.json\')}'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              message: 'Training failed for project @{body(\'Parse_project_config\')[\'projectId\']}'
              timestamp: '@{utcnow()}'
              level: 'Error'
              error: '@{body(\'Start_training\')}'
            }
          }
          runAfter: {
            'Start_training': [
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
          azureblob: {
            connectionId: blobConnection.id
            connectionName: 'azureblob'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azureblob'
          }
        }
      }
      storageAccountName: {
        value: storageAccountName
      }
      customVisionEndpoint: {
        value: customVisionService.properties.endpoint
      }
      customVisionKey: {
        value: customVisionService.listKeys().key1
      }
    }
  }
}

// API Connection for Blob Storage
resource blobConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'azureblob-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'Azure Blob Storage Connection'
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azureblob'
    }
    parameterValues: {
      accountName: storageAccount.name
      accessKey: storageAccount.listKeys().keys[0].value
    }
  }
}

// Metric Alerts for monitoring
resource customVisionAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'CustomVision-Training-Alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when Custom Vision training operations are detected'
    severity: 2
    enabled: true
    scopes: [
      customVisionService.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'TotalCalls'
          metricName: 'TotalCalls'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.CognitiveServices/accounts'
    targetResourceRegion: location
  }
}

// Logic App Failure Alert
resource logicAppAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'LogicApp-Failure-Alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when Logic App workflow fails'
    severity: 1
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
          name: 'RunsFailureRate'
          metricName: 'RunsFailureRate'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.Logic/workflows'
    targetResourceRegion: location
  }
}

// Outputs for integration and verification
@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('Storage Account Primary Key')
output storageAccountKey string = storageAccount.listKeys().keys[0].value

@description('Storage Account Connection String')
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Custom Vision Service Name')
output customVisionServiceName string = customVisionService.name

@description('Custom Vision Endpoint')
output customVisionEndpoint string = customVisionService.properties.endpoint

@description('Custom Vision Training Key')
output customVisionTrainingKey string = customVisionService.listKeys().key1

@description('Logic App Name')
output logicAppName string = logicApp.name

@description('Logic App Trigger URL')
output logicAppTriggerUrl string = logicApp.listCallbackURL('When_a_blob_is_added_or_modified').value

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Deployment Location')
output deploymentLocation string = location

@description('Storage Container Names')
output storageContainerNames array = storageContainers

@description('Blob Connection ID')
output blobConnectionId string = blobConnection.id