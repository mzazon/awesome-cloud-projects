// Main Bicep template for Quantum-Enhanced Financial Risk Analytics
// Deploys Azure Quantum, Synapse Analytics, Machine Learning, and supporting services

@description('Prefix for all resource names')
param resourcePrefix string = 'quantum-finance'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Environment designation (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('SQL Administrator username for Synapse workspace')
param sqlAdministratorLogin string = 'synapseadmin'

@description('SQL Administrator password for Synapse workspace')
@secure()
param sqlAdministratorLoginPassword string

@description('Spark pool node count for Synapse')
@minValue(3)
@maxValue(10)
param sparkPoolNodeCount int = 3

@description('Spark pool node size')
@allowed(['Small', 'Medium', 'Large'])
param sparkPoolNodeSize string = 'Medium'

@description('Enable auto-scale for Spark pool')
param enableSparkAutoScale bool = true

@description('Maximum node count for Spark pool auto-scaling')
@minValue(3)
@maxValue(20)
param sparkPoolMaxNodeCount int = 10

@description('Machine Learning compute instance size')
@allowed(['Standard_DS3_v2', 'Standard_DS4_v2', 'Standard_DS5_v2'])
param mlComputeInstanceSize string = 'Standard_DS3_v2'

@description('Maximum instances for ML compute cluster')
@minValue(0)
@maxValue(10)
param mlComputeMaxInstances int = 4

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'quantum-financial-analytics'
  Owner: 'finance-team'
  CostCenter: 'research-development'
}

// Generate unique suffix for resource names
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var keyVaultName = '${resourcePrefix}-kv-${uniqueSuffix}'
var dataLakeName = '${resourcePrefix}dl${uniqueSuffix}'
var synapseWorkspaceName = '${resourcePrefix}-synapse-${uniqueSuffix}'
var quantumWorkspaceName = '${resourcePrefix}-quantum-${uniqueSuffix}'
var mlWorkspaceName = '${resourcePrefix}-ml-${uniqueSuffix}'
var applicationInsightsName = '${resourcePrefix}-ai-${uniqueSuffix}'
var logAnalyticsName = '${resourcePrefix}-logs-${uniqueSuffix}'

// Key Vault for secure credential management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    accessPolicies: []
  }
}

// Store SQL admin password in Key Vault
resource sqlPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'synapse-sql-admin-password'
  properties: {
    value: sqlAdministratorLoginPassword
    attributes: {
      enabled: true
    }
  }
}

// Data Lake Storage Gen2 for financial data repository
resource dataLakeStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: dataLakeName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    isHnsEnabled: true // Enable hierarchical namespace for Data Lake Gen2
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
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
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Data Lake containers for organized financial data
resource marketDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${dataLakeStorage.name}/default/market-data'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'market-data-storage'
      environment: environment
    }
  }
}

resource portfolioDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${dataLakeStorage.name}/default/portfolio-data'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'portfolio-data-storage'
      environment: environment
    }
  }
}

resource riskModelsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${dataLakeStorage.name}/default/risk-models'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'risk-models-storage'
      environment: environment
    }
  }
}

resource synapseFileSystemContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${dataLakeStorage.name}/default/synapse-filesystem'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'synapse-workspace-filesystem'
      environment: environment
    }
  }
}

// Log Analytics workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for application monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Azure Synapse Analytics workspace
resource synapseWorkspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: synapseWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      accountUrl: 'https://${dataLakeStorage.name}.dfs.core.windows.net'
      filesystem: 'synapse-filesystem'
      createManagedPrivateEndpoint: false
    }
    sqlAdministratorLogin: sqlAdministratorLogin
    sqlAdministratorLoginPassword: sqlAdministratorLoginPassword
    managedVirtualNetwork: 'default'
    managedVirtualNetworkSettings: {
      preventDataExfiltration: false
      linkedAccessCheckOnTargetResource: false
      allowedAadTenantIdsForLinking: []
    }
    publicNetworkAccess: 'Enabled'
    connectivityEndpoints: {
      web: 'https://${synapseWorkspaceName}.dev.azuresynapse.net'
      dev: 'https://${synapseWorkspaceName}.dev.azuresynapse.net'
      sqlOnDemand: '${synapseWorkspaceName}-ondemand.sql.azuresynapse.net'
      sql: '${synapseWorkspaceName}.sql.azuresynapse.net'
    }
  }

  // Synapse firewall rules
  resource allowAllWindowsAzureIps 'firewallRules@2021-06-01' = {
    name: 'AllowAllWindowsAzureIps'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '0.0.0.0'
    }
  }

  resource allowAllIps 'firewallRules@2021-06-01' = {
    name: 'AllowAllIps'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '255.255.255.255'
    }
  }
}

// Synapse Spark pool for quantum algorithm integration
resource synapseSparkPool 'Microsoft.Synapse/workspaces/bigDataPools@2021-06-01' = {
  parent: synapseWorkspace
  name: 'sparkpool01'
  location: location
  tags: tags
  properties: {
    sparkVersion: '3.3'
    nodeCount: sparkPoolNodeCount
    nodeSizeFamily: 'MemoryOptimized'
    nodeSize: sparkPoolNodeSize
    autoScale: {
      enabled: enableSparkAutoScale
      minNodeCount: sparkPoolNodeCount
      maxNodeCount: sparkPoolMaxNodeCount
    }
    autoPause: {
      enabled: true
      delayInMinutes: 15
    }
    dynamicExecutorAllocation: {
      enabled: true
      minExecutors: 1
      maxExecutors: sparkPoolMaxNodeCount
    }
    sessionLevelPackagesEnabled: true
    libraryRequirements: {
      content: '''
numpy==1.24.3
pandas==2.0.3
scipy==1.11.1
scikit-learn==1.3.0
azure-quantum==0.28.263226
azure-storage-blob==12.17.0
azure-identity==1.13.0
matplotlib==3.7.2
seaborn==0.12.2
      '''
      filename: 'requirements.txt'
    }
  }
}

// Azure Quantum workspace for optimization algorithms
resource quantumWorkspace 'Microsoft.Quantum/Workspaces@2022-01-11-preview' = {
  name: quantumWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    providers: [
      {
        providerId: 'Microsoft'
        providerSku: 'DZI-Standard'
      }
    ]
    storageAccount: dataLakeStorage.id
    usable: 'Yes'
  }
}

// Azure Machine Learning workspace
resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2023-10-01' = {
  name: mlWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: '${mlWorkspaceName} Workspace'
    description: 'Machine Learning workspace for quantum-enhanced financial risk analytics'
    storageAccount: dataLakeStorage.id
    keyVault: keyVault.id
    applicationInsights: applicationInsights.id
    containerRegistry: null
    publicNetworkAccess: 'Enabled'
    allowPublicAccessWhenBehindVnet: false
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
  }

  // ML compute cluster for model training
  resource mlComputeCluster 'computes@2023-10-01' = {
    name: 'ml-cluster'
    location: location
    properties: {
      computeType: 'AmlCompute'
      description: 'ML compute cluster for quantum-enhanced risk modeling'
      properties: {
        vmSize: mlComputeInstanceSize
        vmPriority: 'Dedicated'
        scaleSettings: {
          minNodeCount: 0
          maxNodeCount: mlComputeMaxInstances
          nodeIdleTimeBeforeScaleDown: 'PT120S'
        }
        enableNodePublicIp: false
        osType: 'Linux'
        isolatedNetwork: false
      }
    }
  }
}

// Role assignments for service integrations

// Storage Blob Data Contributor for Synapse managed identity
resource synapseStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataLakeStorage.id, synapseWorkspace.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: dataLakeStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: synapseWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Data Contributor for ML workspace managed identity
resource mlStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataLakeStorage.id, mlWorkspace.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: dataLakeStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: mlWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Secrets User for Synapse managed identity
resource synapseKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, synapseWorkspace.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: synapseWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Quantum workspace contributor for Synapse managed identity
resource synapseQuantumRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(quantumWorkspace.id, synapseWorkspace.id, 'b1a2b304-7be3-4b7e-8c61-d0a5b9c8c8f0')
  scope: quantumWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b1a2b304-7be3-4b7e-8c61-d0a5b9c8c8f0') // Contributor
    principalId: synapseWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs for reference and validation
output resourceGroupName string = resourceGroup().name
output location string = location
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output dataLakeStorageName string = dataLakeStorage.name
output dataLakeStorageUrl string = 'https://${dataLakeStorage.name}.dfs.core.windows.net'
output synapseWorkspaceName string = synapseWorkspace.name
output synapseWorkspaceUrl string = 'https://${synapseWorkspaceName}.dev.azuresynapse.net'
output synapseSqlServerlessEndpoint string = '${synapseWorkspaceName}-ondemand.sql.azuresynapse.net'
output quantumWorkspaceName string = quantumWorkspace.name
output quantumWorkspaceResourceId string = quantumWorkspace.id
output mlWorkspaceName string = mlWorkspace.name
output mlWorkspaceUrl string = 'https://ml.azure.com/?wsid=${mlWorkspace.id}'
output applicationInsightsName string = applicationInsights.name
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output sparkPoolName string = synapseSparkPool.name
output mlComputeClusterName string = mlWorkspace::mlComputeCluster.name

// Security and compliance outputs
output synapseWorkspaceManagedIdentity string = synapseWorkspace.identity.principalId
output mlWorkspaceManagedIdentity string = mlWorkspace.identity.principalId
output quantumWorkspaceManagedIdentity string = quantumWorkspace.identity.principalId