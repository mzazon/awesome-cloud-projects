// ========================================================================
// Main Bicep template for Intelligent Document Processing
// ========================================================================
// This template deploys a complete intelligent document processing solution
// using Azure AI Document Intelligence and Logic Apps with supporting services

@description('The location where all resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
param environmentName string = 'dev'

@description('Base name for all resources')
param baseName string = 'docprocessing'

@description('Unique suffix for globally unique resources')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Storage account tier (Standard_LRS, Standard_GRS, etc.)')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Premium_LRS'
])
param storageAccountTier string = 'Standard_LRS'

@description('Document Intelligence service tier')
@allowed([
  'F0'
  'S0'
])
param documentIntelligenceTier string = 'S0'

@description('Service Bus namespace tier')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param serviceBusTier string = 'Standard'

@description('Key Vault access policies object ID (typically your user or service principal)')
param keyVaultAccessPolicyObjectId string

@description('Tags to apply to all resources')
param tags object = {
  Environment: environmentName
  Project: 'DocumentProcessing'
  DeployedBy: 'Bicep'
}

// ========================================================================
// Variables
// ========================================================================

var storageAccountName = 'st${baseName}${uniqueSuffix}'
var keyVaultName = 'kv-${baseName}-${uniqueSuffix}'
var documentIntelligenceName = 'docintell-${baseName}-${uniqueSuffix}'
var logicAppName = 'logic-${baseName}-${uniqueSuffix}'
var serviceBusNamespaceName = 'sb-${baseName}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'log-${baseName}-${uniqueSuffix}'

// ========================================================================
// Storage Account for Document Storage
// ========================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountTier
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Blob service configuration
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Input documents container
resource inputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'input-documents'
  parent: blobService
  properties: {
    publicAccess: 'None'
  }
}

// Processed documents container
resource processedContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'processed-documents'
  parent: blobService
  properties: {
    publicAccess: 'None'
  }
}

// ========================================================================
// Azure AI Document Intelligence
// ========================================================================

resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: documentIntelligenceName
  location: location
  tags: tags
  kind: 'FormRecognizer'
  sku: {
    name: documentIntelligenceTier
  }
  properties: {
    customSubDomainName: documentIntelligenceName
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
  }
}

// ========================================================================
// Service Bus Namespace and Queue
// ========================================================================

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  tags: tags
  sku: {
    name: serviceBusTier
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

resource serviceBusQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  name: 'processed-docs-queue'
  parent: serviceBusNamespace
  properties: {
    maxSizeInMegabytes: 1024
    defaultMessageTimeToLive: 'P7D'
    deadLetteringOnMessageExpiration: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    maxDeliveryCount: 10
    requiresDuplicateDetection: false
    requiresSession: false
    enableBatchedOperations: true
  }
}

// ========================================================================
// Key Vault for Secure Credential Storage
// ========================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableRbacAuthorization: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    publicNetworkAccess: 'Enabled'
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: keyVaultAccessPolicyObjectId
        permissions: {
          keys: [
            'get'
            'list'
            'create'
            'update'
          ]
          secrets: [
            'get'
            'list'
            'set'
            'delete'
          ]
          certificates: [
            'get'
            'list'
            'create'
            'update'
          ]
        }
      }
    ]
  }
}

// Store storage account key in Key Vault
resource storageAccountKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'storage-account-key'
  parent: keyVault
  properties: {
    value: storageAccount.listKeys().keys[0].value
    contentType: 'text/plain'
  }
}

// Store Document Intelligence key in Key Vault
resource documentIntelligenceKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'doc-intelligence-key'
  parent: keyVault
  properties: {
    value: documentIntelligence.listKeys().key1
    contentType: 'text/plain'
  }
}

// Store Document Intelligence endpoint in Key Vault
resource documentIntelligenceEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'doc-intelligence-endpoint'
  parent: keyVault
  properties: {
    value: documentIntelligence.properties.endpoint
    contentType: 'text/plain'
  }
}

// Store Service Bus connection string in Key Vault
resource serviceBusConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'servicebus-connection'
  parent: keyVault
  properties: {
    value: listKeys(resourceId('Microsoft.ServiceBus/namespaces/AuthorizationRules', serviceBusNamespaceName, 'RootManageSharedAccessKey'), '2022-10-01-preview').primaryConnectionString
    contentType: 'text/plain'
  }
}

// ========================================================================
// Log Analytics Workspace for Monitoring
// ========================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ========================================================================
// Logic App with System-Assigned Managed Identity
// ========================================================================

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
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
        'When_a_blob_is_added_or_modified': {
          type: 'ApiConnection'
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/v2/datasets/@{encodeURIComponent(\'${storageAccountName}\')}/triggers/batch/onupdatedfile'
            queries: {
              folderId: '/input-documents'
              maxFileCount: 10
            }
          }
        }
      }
      actions: {
        'Get_Storage_Key': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'keyvault\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/secrets/@{encodeURIComponent(\'storage-account-key\')}/value'
          }
        }
        'Get_Document_Intelligence_Key': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'keyvault\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/secrets/@{encodeURIComponent(\'doc-intelligence-key\')}/value'
          }
          runAfter: {
            'Get_Storage_Key': [
              'Succeeded'
            ]
          }
        }
        'Get_Document_Intelligence_Endpoint': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'keyvault\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/secrets/@{encodeURIComponent(\'doc-intelligence-endpoint\')}/value'
          }
          runAfter: {
            'Get_Document_Intelligence_Key': [
              'Succeeded'
            ]
          }
        }
        'Process_Document': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '@{body(\'Get_Document_Intelligence_Endpoint\')?[\'value\']}/formrecognizer/v2.1/prebuilt/invoice/analyze'
            headers: {
              'Ocp-Apim-Subscription-Key': '@{body(\'Get_Document_Intelligence_Key\')?[\'value\']}'
              'Content-Type': 'application/json'
            }
            body: {
              source: '@{body(\'When_a_blob_is_added_or_modified\')?[\'Path\']}'
            }
          }
          runAfter: {
            'Get_Document_Intelligence_Endpoint': [
              'Succeeded'
            ]
          }
        }
        'Send_to_Service_Bus': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              ContentData: '@{base64(body(\'Process_Document\'))}'
              ContentType: 'application/json'
            }
            path: '/@{encodeURIComponent(\'processed-docs-queue\')}/messages'
          }
          runAfter: {
            'Process_Document': [
              'Succeeded'
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
          keyvault: {
            connectionId: keyVaultConnection.id
            connectionName: 'keyvault'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/keyvault'
          }
          servicebus: {
            connectionId: serviceBusConnection.id
            connectionName: 'servicebus'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/servicebus'
          }
        }
      }
    }
  }
}

// ========================================================================
// API Connections for Logic App
// ========================================================================

// Blob Storage API Connection
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

// Key Vault API Connection
resource keyVaultConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'keyvault-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'Azure Key Vault Connection'
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/keyvault'
    }
    parameterValueType: 'Alternative'
    alternativeParameterValues: {
      vaultName: keyVault.name
    }
  }
}

// Service Bus API Connection
resource serviceBusConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'servicebus-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'Azure Service Bus Connection'
    customParameterValues: {}
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/servicebus'
    }
    parameterValues: {
      connectionString: listKeys(resourceId('Microsoft.ServiceBus/namespaces/AuthorizationRules', serviceBusNamespaceName, 'RootManageSharedAccessKey'), '2022-10-01-preview').primaryConnectionString
    }
  }
}

// ========================================================================
// Key Vault Access Policy for Logic App Managed Identity
// ========================================================================

resource keyVaultAccessPolicyForLogicApp 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: logicApp.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
  }
}

// ========================================================================
// Diagnostic Settings for Monitoring
// ========================================================================

resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'storage-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
      }
    ]
  }
}

resource logicAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'logicapp-diagnostics'
  scope: logicApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'WorkflowRuntime'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ========================================================================
// Outputs
// ========================================================================

@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The primary endpoint of the storage account')
output storageAccountEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The URI of the Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The name of the Document Intelligence service')
output documentIntelligenceName string = documentIntelligence.name

@description('The endpoint of the Document Intelligence service')
output documentIntelligenceEndpoint string = documentIntelligence.properties.endpoint

@description('The name of the Logic App')
output logicAppName string = logicApp.name

@description('The Logic App trigger URL (for manual triggering)')
output logicAppTriggerUrl string = listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicAppName, 'When_a_blob_is_added_or_modified'), '2019-05-01').value

@description('The name of the Service Bus namespace')
output serviceBusNamespaceName string = serviceBusNamespace.name

@description('The name of the Service Bus queue')
output serviceBusQueueName string = serviceBusQueue.name

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The workspace ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Instructions for testing the solution')
output testingInstructions string = 'Upload a document to the "${inputContainer.name}" container in storage account "${storageAccount.name}" to trigger the workflow. Monitor the Logic App execution in the Azure portal.'