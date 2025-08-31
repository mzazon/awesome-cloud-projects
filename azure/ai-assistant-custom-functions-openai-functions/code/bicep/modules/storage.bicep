@description('Bicep module for Azure Storage Account with containers for AI Assistant data')

// Parameters
@description('The location/region where resources will be deployed')
param location string

@description('Storage Account name (must be globally unique)')
param storageAccountName string

@description('Storage replication type')
@allowed(['LRS', 'GRS', 'ZRS', 'GZRS'])
param replicationType string = 'LRS'

@description('Tags to apply to resources')
param tags object = {}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_${replicationType}'
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

// Blob Service
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

// Conversations Container
resource conversationsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'conversations'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Sessions Container
resource sessionsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'sessions'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Assistant Data Container
resource assistantDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'assistant-data'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Lifecycle Management Policy
resource lifecyclePolicy 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: '${storageAccountName}-lifecycle-policy'
  location: location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.40.0'
    timeout: 'PT10M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'STORAGE_ACCOUNT_NAME'
        value: storageAccount.name
      }
      {
        name: 'RESOURCE_GROUP_NAME'
        value: resourceGroup().name
      }
    ]
    scriptContent: '''
      # Configure lifecycle management policy for cost optimization
      az storage account management-policy create \
        --account-name $STORAGE_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP_NAME \
        --policy '{
          "rules": [
            {
              "name": "ConversationDataLifecycle",
              "enabled": true,
              "type": "Lifecycle",
              "definition": {
                "filters": {
                  "blobTypes": ["blockBlob"],
                  "prefixMatch": ["conversations/"]
                },
                "actions": {
                  "baseBlob": {
                    "tierToCool": {
                      "daysAfterModificationGreaterThan": 30
                    },
                    "tierToArchive": {
                      "daysAfterModificationGreaterThan": 90
                    },
                    "delete": {
                      "daysAfterModificationGreaterThan": 365
                    }
                  }
                }
              }
            },
            {
              "name": "SessionDataLifecycle",
              "enabled": true,
              "type": "Lifecycle",
              "definition": {
                "filters": {
                  "blobTypes": ["blockBlob"],
                  "prefixMatch": ["sessions/"]
                },
                "actions": {
                  "baseBlob": {
                    "delete": {
                      "daysAfterModificationGreaterThan": 7
                    }
                  }
                }
              }
            }
          ]
        }'
    '''
  }
  dependsOn: [
    storageAccount
    conversationsContainer
    sessionsContainer
  ]
}

// Outputs
@description('Storage Account ID')
output storageAccountId string = storageAccount.id

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Storage Account primary endpoint')
output primaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Storage Account connection string')
@secure()
output connectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Storage Account primary access key')
@secure()
output primaryAccessKey string = storageAccount.listKeys().keys[0].value

@description('Container names')
output containers object = {
  conversations: conversationsContainer.name
  sessions: sessionsContainer.name
  assistantData: assistantDataContainer.name
}