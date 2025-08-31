@description('The name prefix for all resources. This will be combined with a unique suffix.')
param namePrefix string = 'contmod'

@description('The Azure region where all resources will be deployed.')
param location string = resourceGroup().location

@description('The environment designation (dev, test, prod, etc.)')
param environment string = 'demo'

@description('The pricing tier for the Content Safety service.')
@allowed([
  'S0'
  'F0'
])
param contentSafetyPricingTier string = 'S0'

@description('The pricing tier for the Storage Account.')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountPricingTier string = 'Standard_LRS'

@description('The name of the blob container for content uploads.')
param containerName string = 'content-uploads'

@description('Tags to apply to all resources.')
param resourceTags object = {
  purpose: 'content-moderation'
  environment: environment
  'deployed-by': 'bicep'
}

@description('The severity threshold for auto-approval (0-6, lower values are safer)')
@minValue(0)
@maxValue(6)
param autoApprovalThreshold int = 0

@description('The severity threshold for auto-rejection (0-6, higher values are more restrictive)')
@minValue(0)
@maxValue(6)
param autoRejectionThreshold int = 4

// Generate unique suffix for resource names
var uniqueSuffix = uniqueString(resourceGroup().id)
var contentSafetyName = '${namePrefix}-cs-${uniqueSuffix}'
var storageAccountName = '${namePrefix}st${uniqueSuffix}'
var logicAppName = '${namePrefix}-la-${uniqueSuffix}'
var connectionName = 'azureblob-connection'

// Create Azure AI Content Safety resource
resource contentSafety 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: contentSafetyName
  location: location
  tags: resourceTags
  kind: 'ContentSafety'
  sku: {
    name: contentSafetyPricingTier
  }
  properties: {
    customSubDomainName: contentSafetyName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Create Storage Account for content uploads
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  kind: 'StorageV2'
  sku: {
    name: storageAccountPricingTier
  }
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: true
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

// Create blob container for content uploads
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  name: 'default'
  parent: storageAccount
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

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: containerName
  parent: blobService
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Create Azure Blob Storage connection for Logic Apps
resource blobConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: connectionName
  location: location
  tags: resourceTags
  properties: {
    displayName: 'Azure Blob Storage Connection'
    customParameterValues: {}
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
    }
    parameterValues: {
      connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    }
  }
}

// Create Logic App for content moderation workflow
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: resourceTags
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
        When_a_blob_is_added_or_modified: {
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
          evaluatedRecurrence: {
            frequency: 'Minute'
            interval: 1
          }
          splitOn: '@triggerBody()'
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
              folderId: containerName
              maxFileCount: 10
            }
          }
        }
      }
      actions: {
        Get_blob_content: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/datasets/default/files/@{encodeURIComponent(encodeURIComponent(triggerBody()?[\'Path\']))}/content'
            queries: {
              inferContentType: true
            }
          }
        }
        Analyze_content_with_AI: {
          runAfter: {
            Get_blob_content: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            body: {
              text: '@{base64ToString(body(\'Get_blob_content\')?[\'$content\'])}'
              outputType: 'FourSeverityLevels'
            }
            headers: {
              'Content-Type': 'application/json'
              'Ocp-Apim-Subscription-Key': '@{listKeys(resourceId(\'Microsoft.CognitiveServices/accounts\', \'${contentSafetyName}\'), \'2023-05-01\').key1}'
            }
            method: 'POST'
            uri: '${contentSafety.properties.endpoint}contentsafety/text:analyze?api-version=2024-09-01'
          }
        }
        Process_moderation_results: {
          runAfter: {
            Analyze_content_with_AI: [
              'Succeeded'
            ]
          }
          cases: {
            Low_Risk_Auto_Approve: {
              case: autoApprovalThreshold
              actions: {
                Log_approval: {
                  type: 'Compose'
                  inputs: {
                    message: 'Content approved automatically'
                    file: '@triggerBody()?[\'Name\']'
                    timestamp: '@utcnow()'
                    moderationResult: '@body(\'Analyze_content_with_AI\')'
                    decision: 'approved'
                    maxSeverity: '@max(body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[0]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[1]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[2]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[3]?[\'severity\'])'
                  }
                }
                Send_approval_notification: {
                  runAfter: {
                    Log_approval: [
                      'Succeeded'
                    ]
                  }
                  type: 'Compose'
                  inputs: {
                    notificationType: 'approval'
                    content: '@outputs(\'Log_approval\')'
                  }
                }
              }
            }
            Medium_Risk_Needs_Review: {
              case: 2
              actions: {
                Flag_for_review: {
                  type: 'Compose'
                  inputs: {
                    message: 'Content flagged for human review'
                    file: '@triggerBody()?[\'Name\']'
                    timestamp: '@utcnow()'
                    moderationResult: '@body(\'Analyze_content_with_AI\')'
                    decision: 'review_needed'
                    maxSeverity: '@max(body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[0]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[1]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[2]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[3]?[\'severity\'])'
                  }
                }
                Send_review_notification: {
                  runAfter: {
                    Flag_for_review: [
                      'Succeeded'
                    ]
                  }
                  type: 'Compose'
                  inputs: {
                    notificationType: 'review_required'
                    content: '@outputs(\'Flag_for_review\')'
                  }
                }
              }
            }
            High_Risk_Auto_Reject: {
              case: autoRejectionThreshold
              actions: {
                Log_rejection: {
                  type: 'Compose'
                  inputs: {
                    message: 'Content rejected automatically'
                    file: '@triggerBody()?[\'Name\']'
                    timestamp: '@utcnow()'
                    moderationResult: '@body(\'Analyze_content_with_AI\')'
                    decision: 'rejected'
                    maxSeverity: '@max(body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[0]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[1]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[2]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[3]?[\'severity\'])'
                  }
                }
                Send_rejection_notification: {
                  runAfter: {
                    Log_rejection: [
                      'Succeeded'
                    ]
                  }
                  type: 'Compose'
                  inputs: {
                    notificationType: 'rejection'
                    content: '@outputs(\'Log_rejection\')'
                  }
                }
              }
            }
          }
          default: {
            actions: {
              Flag_for_urgent_review: {
                type: 'Compose'
                inputs: {
                  message: 'Content flagged for urgent human review'
                  file: '@triggerBody()?[\'Name\']'
                  timestamp: '@utcnow()'
                  moderationResult: '@body(\'Analyze_content_with_AI\')'
                  decision: 'urgent_review'
                  maxSeverity: '@max(body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[0]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[1]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[2]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[3]?[\'severity\'])'
                }
              }
              Send_urgent_notification: {
                runAfter: {
                  Flag_for_urgent_review: [
                    'Succeeded'
                  ]
                }
                type: 'Compose'
                inputs: {
                  notificationType: 'urgent_review'
                  content: '@outputs(\'Flag_for_urgent_review\')'
                }
              }
            }
          }
          expression: '@max(body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[0]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[1]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[2]?[\'severity\'], body(\'Analyze_content_with_AI\')?[\'categoriesAnalysis\']?[3]?[\'severity\'])'
          type: 'Switch'
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azureblob: {
            connectionId: blobConnection.id
            connectionName: connectionName
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
          }
        }
      }
    }
  }
}

// Outputs for reference and verification
@description('The name of the Content Safety resource.')
output contentSafetyName string = contentSafety.name

@description('The endpoint URL for the Content Safety service.')
output contentSafetyEndpoint string = contentSafety.properties.endpoint

@description('The name of the Storage Account.')
output storageAccountName string = storageAccount.name

@description('The name of the blob container.')
output containerName string = container.name

@description('The name of the Logic App workflow.')
output logicAppName string = logicApp.name

@description('The callback URL for the Logic App trigger.')
output logicAppTriggerUrl string = listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicApp.name, 'When_a_blob_is_added_or_modified'), '2019-05-01').value

@description('The resource group location.')
output resourceGroupLocation string = resourceGroup().location

@description('The unique suffix used for resource naming.')
output uniqueSuffix string = uniqueSuffix

@description('Connection string for the storage account (use with caution in production).')
@secure()
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'