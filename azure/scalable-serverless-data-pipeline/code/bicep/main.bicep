// ============================================================================
// Azure Bicep Template for Serverless Data Pipeline
// Recipe: Scalable Serverless Data Pipeline with Synapse and Data Factory
// ============================================================================

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Project name prefix for resource naming')
@minLength(3)
@maxLength(10)
param projectName string = 'pipeline'

@description('Unique suffix for resource naming (auto-generated if not provided)')
param uniqueSuffix string = uniqueString(resourceGroup().id, deployment().name)

@description('Storage account replication type')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS', 'Premium_LRS'])
param storageAccountSku string = 'Standard_LRS'

@description('SQL Administrator login username')
@minLength(4)
param sqlAdminLogin string = 'sqladmin'

@description('SQL Administrator login password')
@minLength(12)
@secure()
param sqlAdminPassword string

@description('Key Vault soft delete retention days')
@minValue(7)
@maxValue(90)
param keyVaultRetentionDays int = 7

@description('Enable purge protection for Key Vault')
param keyVaultPurgeProtectionEnabled bool = false

@description('Client IP address for firewall rules (auto-detected if not provided)')
param clientIpAddress string = ''

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: projectName
  Purpose: 'data-pipeline'
  Recipe: 'serverless-data-pipeline'
}

// ============================================================================
// Variables
// ============================================================================

var resourceNames = {
  storageAccount: '${projectName}st${uniqueSuffix}'
  synapseWorkspace: '${projectName}-syn-${uniqueSuffix}'
  dataFactory: '${projectName}-adf-${uniqueSuffix}'
  keyVault: '${projectName}-kv-${uniqueSuffix}'
  managedResourceGroup: '${projectName}-syn-mrg-${uniqueSuffix}'
  storageFileSystem: 'synapsefs'
}

var dataLakeContainers = [
  'raw'
  'curated'
  'refined'
]

var dataLakeDirectories = [
  'streaming-data'
  'batch-data'
  'processed-data'
  'archived-data'
]

// ============================================================================
// Azure Data Lake Storage Gen2 Account
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true // Enable hierarchical namespace for Data Lake Gen2
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    accessTier: 'Hot'
    networkRules: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
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

// Blob service for storage account
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    versioning: {
      enabled: true
    }
    changeFeed: {
      enabled: true
    }
    restorePolicy: {
      enabled: false
    }
  }
}

// Create containers for medallion architecture
resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for container in dataLakeContainers: {
  parent: blobService
  name: container
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'data-lake-${container}'
      layer: container == 'raw' ? 'bronze' : container == 'curated' ? 'silver' : 'gold'
    }
  }
}]

// Synapse file system container
resource synapseFileSystem 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: resourceNames.storageFileSystem
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'synapse-workspace'
    }
  }
}

// ============================================================================
// Azure Key Vault
// ============================================================================

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
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enabledForDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: keyVaultRetentionDays
    enablePurgeProtection: keyVaultPurgeProtectionEnabled
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    accessPolicies: []
  }
}

// Store storage account connection string in Key Vault
resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-connection-string'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// ============================================================================
// Azure Synapse Analytics Workspace
// ============================================================================

resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: resourceNames.synapseWorkspace
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: storageAccount.properties.primaryEndpoints.dfs
      filesystem: resourceNames.storageFileSystem
      resourceId: storageAccount.id
    }
    sqlAdministratorLogin: sqlAdminLogin
    sqlAdministratorLoginPassword: sqlAdminPassword
    managedResourceGroupName: resourceNames.managedResourceGroup
    publicNetworkAccess: 'Enabled'
    trustedServiceBypassEnabled: true
    cspWorkspaceAdminProperties: {
      initialWorkspaceAdminObjectId: ''
    }
  }
}

// Synapse firewall rule for client IP (if provided)
resource synapseFirewallRule 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = if (!empty(clientIpAddress)) {
  parent: synapseWorkspace
  name: 'AllowClientIP'
  properties: {
    startIpAddress: clientIpAddress
    endIpAddress: clientIpAddress
  }
}

// Synapse firewall rule for Azure services
resource synapseFirewallRuleAzure 'Microsoft.Synapse/workspaces/firewallRules@2021-06-01' = {
  parent: synapseWorkspace
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Grant Synapse workspace access to storage account
resource synapseStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, synapseWorkspace.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: synapseWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Azure Data Factory
// ============================================================================

resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: resourceNames.dataFactory
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    encryption: {
      identity: {
        userAssignedIdentity: ''
      }
    }
  }
}

// Grant Data Factory access to Key Vault
resource dataFactoryKeyVaultAccess 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: dataFactory.identity.principalId
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

// Grant Data Factory access to storage account
resource dataFactoryStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, dataFactory.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: dataFactory.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Data Factory Linked Services
// ============================================================================

// Key Vault linked service
resource keyVaultLinkedService 'Microsoft.DataFactory/factories/linkedServices@2018-06-01' = {
  parent: dataFactory
  name: 'ls_keyvault'
  properties: {
    type: 'AzureKeyVault'
    typeProperties: {
      baseUrl: keyVault.properties.vaultUri
    }
  }
}

// Storage linked service using Key Vault for credentials
resource storageLinkedService 'Microsoft.DataFactory/factories/linkedServices@2018-06-01' = {
  parent: dataFactory
  name: 'ls_storage'
  dependsOn: [
    keyVaultLinkedService
    storageConnectionStringSecret
  ]
  properties: {
    type: 'AzureBlobFS'
    typeProperties: {
      url: storageAccount.properties.primaryEndpoints.dfs
      accountKey: {
        type: 'AzureKeyVaultSecret'
        store: {
          referenceName: 'ls_keyvault'
          type: 'LinkedServiceReference'
        }
        secretName: 'storage-connection-string'
      }
    }
  }
}

// Synapse linked service
resource synapseLinkedService 'Microsoft.DataFactory/factories/linkedServices@2018-06-01' = {
  parent: dataFactory
  name: 'ls_synapse'
  properties: {
    type: 'AzureSqlDW'
    typeProperties: {
      connectionString: 'Server=${synapseWorkspace.name}.sql.azuresynapse.net;Database=master;User ID=${sqlAdminLogin};Password=${sqlAdminPassword};Trusted_Connection=false;Encrypt=true;Connection Timeout=30'
    }
  }
}

// ============================================================================
// Data Factory Datasets
// ============================================================================

// Source dataset for streaming data (JSON)
resource streamingSourceDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'ds_streaming_source'
  dependsOn: [
    storageLinkedService
  ]
  properties: {
    type: 'Json'
    linkedServiceName: {
      referenceName: 'ls_storage'
      type: 'LinkedServiceReference'
    }
    typeProperties: {
      location: {
        type: 'AzureBlobFSLocation'
        fileSystem: 'raw'
        folderPath: 'streaming-data'
      }
    }
  }
}

// Sink dataset for curated data (Parquet)
resource curatedSinkDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'ds_curated_sink'
  dependsOn: [
    storageLinkedService
  ]
  properties: {
    type: 'Parquet'
    linkedServiceName: {
      referenceName: 'ls_storage'
      type: 'LinkedServiceReference'
    }
    typeProperties: {
      location: {
        type: 'AzureBlobFSLocation'
        fileSystem: 'curated'
        folderPath: 'processed-data'
      }
    }
  }
}

// ============================================================================
// Monitoring and Diagnostics
// ============================================================================

// Log Analytics workspace for centralized logging
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${projectName}-logs-${uniqueSuffix}'
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
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Diagnostic settings for Data Factory
resource dataFactoryDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'adf-diagnostics'
  scope: dataFactory
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'PipelineRuns'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'TriggerRuns'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'ActivityRuns'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Diagnostic settings for Synapse workspace
resource synapseDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'synapse-diagnostics'
  scope: synapseWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'SynapseRbacOperations'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'GatewayApiRequests'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// ============================================================================
// Alert Rules
// ============================================================================

// Alert for Data Factory pipeline failures
resource pipelineFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'pipeline-failure-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when Data Factory pipeline fails'
    severity: 2
    enabled: true
    scopes: [
      dataFactory.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'PipelineFailures'
          metricName: 'PipelineFailedRuns'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Total'
        }
      ]
    }
    actions: []
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account primary endpoint')
output storageAccountEndpoint string = storageAccount.properties.primaryEndpoints.dfs

@description('Synapse workspace name')
output synapseWorkspaceName string = synapseWorkspace.name

@description('Synapse workspace SQL endpoint')
output synapseSqlEndpoint string = '${synapseWorkspace.name}.sql.azuresynapse.net'

@description('Synapse workspace development endpoint')
output synapseDevEndpoint string = '${synapseWorkspace.name}.dev.azuresynapse.net'

@description('Data Factory name')
output dataFactoryName string = dataFactory.name

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Deployment summary')
output deploymentSummary object = {
  resourcesCreated: {
    storageAccount: storageAccount.name
    synapseWorkspace: synapseWorkspace.name
    dataFactory: dataFactory.name
    keyVault: keyVault.name
    logAnalyticsWorkspace: logAnalyticsWorkspace.name
  }
  endpoints: {
    storageAccount: storageAccount.properties.primaryEndpoints.dfs
    synapseSql: '${synapseWorkspace.name}.sql.azuresynapse.net'
    synapseStudio: '${synapseWorkspace.name}.dev.azuresynapse.net'
    keyVault: keyVault.properties.vaultUri
  }
  nextSteps: [
    'Configure external tables in Synapse serverless SQL pool'
    'Create data transformation pipelines in Data Factory'
    'Set up monitoring dashboards in Azure Monitor'
    'Configure data quality validation rules'
  ]
}