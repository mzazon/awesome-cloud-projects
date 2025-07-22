@description('Name of the Azure Confidential Ledger')
param ledgerName string = 'acl-${uniqueString(resourceGroup().id)}'

@description('Name of the Key Vault')
param keyVaultName string = 'kv-audit-${uniqueString(resourceGroup().id)}'

@description('Name of the Logic App')
param logicAppName string = 'la-audit-${uniqueString(resourceGroup().id)}'

@description('Name of the Event Hub Namespace')
param eventHubNamespaceName string = 'eh-audit-${uniqueString(resourceGroup().id)}'

@description('Name of the Storage Account')
param storageAccountName string = 'staudit${uniqueString(resourceGroup().id)}'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Event Hub SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param eventHubSku string = 'Standard'

@description('Event Hub capacity')
@minValue(1)
@maxValue(20)
param eventHubCapacity int = 1

@description('Number of Event Hub partitions')
@minValue(2)
@maxValue(32)
param eventHubPartitionCount int = 4

@description('Event Hub message retention in days')
@minValue(1)
@maxValue(7)
param eventHubRetentionDays int = 1

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Premium_LRS'
  'Premium_ZRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Key Vault SKU')
@allowed([
  'standard'
  'premium'
])
param keyVaultSku string = 'standard'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'audit-trail'
  environment: 'demo'
  solution: 'confidential-ledger-audit'
}

@description('Principal ID of the user or service principal to grant Key Vault access')
param principalId string = ''

// Variables
var containerName = 'audit-archive'
var eventHubName = 'audit-events'
var consumerGroupName = 'logic-apps-consumer'

// Storage Account with hierarchical namespace and versioning
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    isHnsEnabled: true // Hierarchical namespace for Data Lake Storage
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        blob: {
          keyType: 'Account'
          enabled: true
        }
        file: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
  }
}

// Blob service configuration for versioning
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    isVersioningEnabled: true
    changeFeed: {
      enabled: true
      retentionInDays: 7
    }
  }
}

// Container for audit archives
resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'audit-trail-archive'
    }
  }
}

// Key Vault with advanced security features
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    tenantId: subscription().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: false
    accessPolicies: principalId != '' ? [
      {
        tenantId: subscription().tenantId
        objectId: principalId
        permissions: {
          secrets: [
            'get'
            'list'
            'set'
          ]
          certificates: [
            'get'
            'list'
          ]
          keys: [
            'get'
            'list'
          ]
        }
      }
    ] : []
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Event Hub Namespace
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2023-01-01-preview' = {
  name: eventHubNamespaceName
  location: location
  tags: tags
  sku: {
    name: eventHubSku
    tier: eventHubSku
    capacity: eventHubCapacity
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: false
    kafkaEnabled: false
  }
}

// Event Hub
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2023-01-01-preview' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: eventHubRetentionDays
    partitionCount: eventHubPartitionCount
    status: 'Active'
    captureDescription: {
      enabled: false
    }
  }
}

// Event Hub Consumer Group
resource consumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2023-01-01-preview' = {
  parent: eventHub
  name: consumerGroupName
  properties: {
    userMetadata: 'Consumer group for Logic Apps audit processing'
  }
}

// Event Hub authorization rule for Logic Apps
resource eventHubAuthRule 'Microsoft.EventHub/namespaces/authorizationRules@2023-01-01-preview' = {
  parent: eventHubNamespace
  name: 'LogicAppsAccess'
  properties: {
    rights: [
      'Listen'
      'Send'
    ]
  }
}

// Azure Confidential Ledger
resource confidentialLedger 'Microsoft.ConfidentialLedger/ledgers@2023-01-26-preview' = {
  name: ledgerName
  location: location
  tags: tags
  properties: {
    ledgerType: 'Public'
    aadBasedSecurityPrincipals: principalId != '' ? [
      {
        principalId: principalId
        ledgerRoleName: 'Administrator'
      }
    ] : []
    runningState: 'Active'
  }
}

// Logic App with system-assigned managed identity
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
        keyVaultName: {
          defaultValue: keyVaultName
          type: 'String'
        }
        ledgerName: {
          defaultValue: ledgerName
          type: 'String'
        }
      }
      triggers: {
        'When_events_are_available_in_Event_Hub': {
          type: 'EventHub'
          inputs: {
            connection: {
              name: '@parameters(\'$connections\')[\'eventhubs\'][\'connectionId\']'
            }
            eventHubName: eventHubName
            consumerGroupName: consumerGroupName
          }
          recurrence: {
            frequency: 'Second'
            interval: 30
          }
        }
      }
      actions: {
        'Initialize_audit_entry': {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'auditEntry'
                type: 'object'
                value: {
                  eventType: '@{triggerBody()?[\'eventType\']}'
                  timestamp: '@{utcNow()}'
                  actor: '@{triggerBody()?[\'actor\']}'
                  action: '@{triggerBody()?[\'action\']}'
                  resource: '@{triggerBody()?[\'resource\']}'
                  result: '@{triggerBody()?[\'result\']}'
                  details: '@{triggerBody()?[\'details\']}'
                  correlationId: '@{triggerBody()?[\'correlationId\']}'
                }
              }
            ]
          }
          runAfter: {}
        }
        'Get_ledger_endpoint_from_Key_Vault': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'keyvault\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/secrets/@{encodeURIComponent(\'ledger-endpoint\')}/value'
          }
          runAfter: {
            'Initialize_audit_entry': [
              'Succeeded'
            ]
          }
        }
        'Submit_to_Confidential_Ledger': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '@{body(\'Get_ledger_endpoint_from_Key_Vault\')?[\'value\']}/app/transactions'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              contents: '@{string(variables(\'auditEntry\'))}'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
            }
          }
          runAfter: {
            'Get_ledger_endpoint_from_Key_Vault': [
              'Succeeded'
            ]
          }
        }
        'Archive_to_Storage': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccountName}\'))}/files'
            queries: {
              folderPath: '/${containerName}/audit-logs/@{formatDateTime(utcNow(), \'yyyy/MM/dd\')}'
              name: 'audit-@{formatDateTime(utcNow(), \'yyyyMMdd-HHmmss\')}-@{guid()}.json'
              queryParametersSingleEncoded: true
            }
            body: '@variables(\'auditEntry\')'
          }
          runAfter: {
            'Submit_to_Confidential_Ledger': [
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
          eventhubs: {
            connectionId: resourceId('Microsoft.Web/connections', 'eventhubs-connection')
            connectionName: 'eventhubs-connection'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'eventhubs')
          }
          keyvault: {
            connectionId: resourceId('Microsoft.Web/connections', 'keyvault-connection')
            connectionName: 'keyvault-connection'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'keyvault')
          }
          azureblob: {
            connectionId: resourceId('Microsoft.Web/connections', 'azureblob-connection')
            connectionName: 'azureblob-connection'
            id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
          }
        }
      }
    }
  }
}

// API Connections for Logic App
resource eventHubConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'eventhubs-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'Event Hub Connection'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'eventhubs')
    }
    parameterValues: {
      connectionString: eventHubAuthRule.listKeys().primaryConnectionString
    }
  }
}

resource keyVaultConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'keyvault-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'Key Vault Connection'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'keyvault')
    }
    parameterValueType: 'Alternative'
    alternativeParameterValues: {
      vaultName: keyVault.name
    }
  }
}

resource blobConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'azureblob-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'Azure Blob Storage Connection'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')
    }
    parameterValues: {
      accountName: storageAccount.name
      accessKey: storageAccount.listKeys().keys[0].value
    }
  }
}

// RBAC role assignments for Logic App managed identity
resource logicAppKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, logicApp.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logicAppEventHubRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventHubNamespace.id, logicApp.id, 'Azure Event Hubs Data Receiver')
  scope: eventHubNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde') // Azure Event Hubs Data Receiver
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logicAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, logicApp.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logicAppLedgerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(confidentialLedger.id, logicApp.id, 'Confidential Ledger Contributor')
  scope: confidentialLedger
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7cc8b3b8-1f88-4c7c-8f0b-b45d2e07f561') // Confidential Ledger Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Store connection information in Key Vault
resource ledgerEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ledger-endpoint'
  properties: {
    value: confidentialLedger.properties.ledgerUri
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource eventHubConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'eventhub-connection'
  properties: {
    value: eventHubAuthRule.listKeys().primaryConnectionString
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource storageConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-connection'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Outputs
@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Azure Confidential Ledger Name')
output confidentialLedgerName string = confidentialLedger.name

@description('Azure Confidential Ledger Endpoint')
output confidentialLedgerEndpoint string = confidentialLedger.properties.ledgerUri

@description('Key Vault Name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Logic App Name')
output logicAppName string = logicApp.name

@description('Logic App Trigger URL')
output logicAppTriggerUrl string = logicApp.listCallbackUrl().value

@description('Event Hub Namespace Name')
output eventHubNamespaceName string = eventHubNamespace.name

@description('Event Hub Name')
output eventHubName string = eventHub.name

@description('Event Hub Connection String')
output eventHubConnectionString string = eventHubAuthRule.listKeys().primaryConnectionString

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('Storage Account Primary Endpoint')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Archive Container Name')
output archiveContainerName string = containerName

@description('Logic App Principal ID')
output logicAppPrincipalId string = logicApp.identity.principalId

@description('Deployment Status')
output deploymentStatus string = 'Audit trail infrastructure deployed successfully'