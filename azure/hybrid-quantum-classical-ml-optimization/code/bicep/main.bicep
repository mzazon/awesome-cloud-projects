// ===================================================================================================
// Bicep Template: Quantum-Enhanced Machine Learning Workflows
// Description: Orchestrates Azure Quantum and Azure Machine Learning for hybrid quantum-classical ML
// Version: 1.0
// ===================================================================================================

targetScope = 'resourceGroup'

// ===================================================================================================
// Parameters
// ===================================================================================================

@description('The base name for all resources')
@minLength(3)
@maxLength(10)
param baseName string = 'quantml'

@description('The Azure region where resources will be deployed')
@allowed([
  'eastus'
  'westus2'
  'westeurope'
  'eastus2'
  'australiaeast'
])
param location string = 'eastus'

@description('Environment tag for resources')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('The SKU for the Azure Machine Learning workspace')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param mlWorkspaceSku string = 'Basic'

@description('The size of the Azure ML compute instance')
@allowed([
  'Standard_DS3_v2'
  'Standard_DS4_v2'
  'Standard_DS5_v2'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
])
param computeInstanceSize string = 'Standard_DS3_v2'

@description('The minimum number of nodes for the ML compute cluster')
@minValue(0)
@maxValue(10)
param minComputeNodes int = 0

@description('The maximum number of nodes for the ML compute cluster')
@minValue(1)
@maxValue(20)
param maxComputeNodes int = 4

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Enable Azure Batch for quantum job orchestration')
param enableBatch bool = true

@description('Admin username for Batch pool VMs (only used if enableBatch is true)')
param batchAdminUsername string = 'quantumuser'

@description('The SKU for the storage account')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: 'quantum-ml'
  Purpose: 'hybrid-quantum-classical-computing'
  CostCenter: 'research-development'
}

// ===================================================================================================
// Variables
// ===================================================================================================

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var resourceNames = {
  quantumWorkspace: '${baseName}-quantum-${uniqueSuffix}'
  mlWorkspace: '${baseName}-aml-${uniqueSuffix}'
  storageAccount: '${baseName}st${uniqueSuffix}'
  keyVault: '${baseName}-kv-${uniqueSuffix}'
  applicationInsights: '${baseName}-ai-${uniqueSuffix}'
  batchAccount: '${baseName}batch${uniqueSuffix}'
  containerRegistry: '${baseName}acr${uniqueSuffix}'
  logAnalytics: '${baseName}-law-${uniqueSuffix}'
  computeInstance: '${baseName}-compute-instance'
  computeCluster: '${baseName}-compute-cluster'
}

var quantumProviders = [
  {
    providerId: 'microsoft'
    skus: [
      {
        name: 'microsoft.simulator'
        tier: 'free'
      }
    ]
  }
  {
    providerId: 'ionq'
    skus: [
      {
        name: 'ionq.simulator'
        tier: 'free'
      }
    ]
  }
  {
    providerId: 'quantinuum'
    skus: [
      {
        name: 'quantinuum.sim.h1-1sc'
        tier: 'free'
      }
    ]
  }
]

// ===================================================================================================
// Resources
// ===================================================================================================

// Log Analytics Workspace for centralized logging
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalytics
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
    }
  }
}

// Application Insights for application monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: resourceNames.applicationInsights
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

// Storage Account with Data Lake Gen2 capabilities
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    largeFileSharesState: 'Disabled'
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
    isHnsEnabled: true // Enable Data Lake Gen2
  }
}

// Key Vault for secrets management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    vaultUri: 'https://${resourceNames.keyVault}.vault.azure.net/'
    provisioningState: 'Succeeded'
    publicNetworkAccess: 'Enabled'
  }
}

// Container Registry for ML model images
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: resourceNames.containerRegistry
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
      exportPolicy: {
        status: 'enabled'
      }
      azureADAuthenticationAsArmPolicy: {
        status: 'enabled'
      }
      softDeletePolicy: {
        retentionDays: 7
        status: 'disabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
    anonymousPullEnabled: false
  }
}

// Azure Machine Learning Workspace
resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: resourceNames.mlWorkspace
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'Quantum-Enhanced ML Workspace'
    description: 'Azure ML workspace for hybrid quantum-classical machine learning workflows'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: enableApplicationInsights ? applicationInsights.id : null
    containerRegistry: containerRegistry.id
    hbiWorkspace: false
    imageBuildCompute: resourceNames.computeCluster
    allowPublicAccessWhenBehindVnet: false
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
    publicNetworkAccess: 'Enabled'
    managedNetwork: {
      isolationMode: 'Disabled'
    }
    workspaceHubConfig: {
      defaultWorkspaceResourceGroup: resourceGroup().name
    }
  }
  
  // ML Compute Instance for development
  resource computeInstance 'computes@2024-04-01' = {
    name: resourceNames.computeInstance
    location: location
    tags: tags
    properties: {
      computeType: 'ComputeInstance'
      properties: {
        vmSize: computeInstanceSize
        subnet: null
        applicationSharingPolicy: 'Personal'
        sshSettings: {
          sshPublicAccess: 'Disabled'
        }
        connectivityEndpoints: {
          publicIpAddress: ''
          privateIpAddress: ''
        }
        schedules: {
          computeStartStop: [
            {
              action: 'Stop'
              cron: {
                startTime: '2024-01-01T18:00:00'
                timeZone: 'UTC'
                expression: '0 18 * * *'
              }
              status: 'Enabled'
              triggerType: 'Cron'
            }
          ]
        }
        enableNodePublicIp: true
        idleTimeBeforeShutdown: 'PT30M'
      }
    }
  }

  // ML Compute Cluster for training
  resource computeCluster 'computes@2024-04-01' = {
    name: resourceNames.computeCluster
    location: location
    tags: tags
    properties: {
      computeType: 'AmlCompute'
      properties: {
        osType: 'Linux'
        vmSize: computeInstanceSize
        vmPriority: 'Dedicated'
        scaleSettings: {
          minNodeCount: minComputeNodes
          maxNodeCount: maxComputeNodes
          nodeIdleTimeBeforeScaleDown: 'PT2M'
        }
        enableNodePublicIp: true
        isolatedNetwork: false
        remoteLoginPortPublicAccess: 'NotSpecified'
      }
    }
  }
}

// Azure Quantum Workspace
resource quantumWorkspace 'Microsoft.Quantum/workspaces@2023-11-13-preview' = {
  name: resourceNames.quantumWorkspace
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    providers: quantumProviders
    usable: 'Yes'
    storageAccount: storageAccount.id
    provisioningState: 'Succeeded'
    endpointUri: 'https://${resourceNames.quantumWorkspace}.quantum.azure.com'
  }
}

// Azure Batch Account for quantum job orchestration
resource batchAccount 'Microsoft.Batch/batchAccounts@2024-02-01' = if (enableBatch) {
  name: resourceNames.batchAccount
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    autoStorage: {
      storageAccountId: storageAccount.id
    }
    poolAllocationMode: 'BatchService'
    publicNetworkAccess: 'Enabled'
    networkProfile: {
      accountAccess: {
        defaultAction: 'Allow'
      }
    }
    encryption: {
      keySource: 'Microsoft.Batch'
    }
  }
}

// Batch Pool for quantum computing workloads
resource batchPool 'Microsoft.Batch/batchAccounts/pools@2024-02-01' = if (enableBatch) {
  parent: batchAccount
  name: 'quantum-compute-pool'
  properties: {
    vmSize: 'Standard_D2s_v3'
    deploymentConfiguration: {
      virtualMachineConfiguration: {
        imageReference: {
          publisher: 'canonical'
          offer: '0001-com-ubuntu-server-focal'
          sku: '20_04-lts-gen2'
        }
        nodeAgentSkuId: 'batch.node.ubuntu 20.04'
      }
    }
    scaleSettings: {
      autoScale: {
        formula: '$TargetDedicatedNodes=0; $TargetLowPriorityNodes=0;'
        evaluationInterval: 'PT5M'
      }
    }
    startTask: {
      commandLine: '/bin/bash -c "apt-get update && apt-get install -y python3 python3-pip && pip3 install azure-quantum azure-quantum[qiskit] qsharp"'
      userIdentity: {
        autoUser: {
          scope: 'pool'
          elevationLevel: 'admin'
        }
      }
      waitForSuccess: true
    }
    maxTasksPerNode: 1
    taskSlotsPerNode: 1
    interNodeCommunication: 'Disabled'
    networkConfiguration: {
      subnetId: null
      publicIPAddressConfiguration: {
        provision: 'BatchManaged'
      }
    }
  }
}

// ===================================================================================================
// Role Assignments
// ===================================================================================================

// ML Workspace access to Storage Account
resource mlWorkspaceStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(mlWorkspace.id, storageAccount.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: mlWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ML Workspace access to Key Vault
resource mlWorkspaceKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(mlWorkspace.id, keyVault.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: mlWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Quantum Workspace access to Storage Account
resource quantumWorkspaceStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(quantumWorkspace.id, storageAccount.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: quantumWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Batch Account access to Storage Account (if enabled)
resource batchAccountStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableBatch) {
  name: guid(batchAccount.id, storageAccount.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: batchAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ===================================================================================================
// Diagnostic Settings
// ===================================================================================================

// ML Workspace diagnostics
resource mlWorkspaceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'mlWorkspaceDiagnostics'
  scope: mlWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Quantum Workspace diagnostics
resource quantumWorkspaceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'quantumWorkspaceDiagnostics'
  scope: quantumWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Storage Account diagnostics
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'storageAccountDiagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'Capacity'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// ===================================================================================================
// Outputs
// ===================================================================================================

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('The location where resources are deployed')
output location string = location

@description('The name of the Azure Quantum workspace')
output quantumWorkspaceName string = quantumWorkspace.name

@description('The resource ID of the Azure Quantum workspace')
output quantumWorkspaceId string = quantumWorkspace.id

@description('The endpoint URI for the Azure Quantum workspace')
output quantumWorkspaceEndpoint string = quantumWorkspace.properties.endpointUri

@description('The name of the Azure Machine Learning workspace')
output mlWorkspaceName string = mlWorkspace.name

@description('The resource ID of the Azure Machine Learning workspace')
output mlWorkspaceId string = mlWorkspace.id

@description('The discovery URL for the Azure Machine Learning workspace')
output mlWorkspaceDiscoveryUrl string = mlWorkspace.properties.discoveryUrl

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The primary endpoint of the storage account')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The URI of the Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The name of the container registry')
output containerRegistryName string = containerRegistry.name

@description('The login server of the container registry')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('The name of the Azure Batch account (if enabled)')
output batchAccountName string = enableBatch ? batchAccount.name : ''

@description('The account endpoint of the Azure Batch account (if enabled)')
output batchAccountEndpoint string = enableBatch ? batchAccount.properties.accountEndpoint : ''

@description('The name of the Application Insights instance (if enabled)')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''

@description('The instrumentation key for Application Insights (if enabled)')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('The connection string for Application Insights (if enabled)')
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('The workspace ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The compute instance name for Azure ML')
output mlComputeInstanceName string = resourceNames.computeInstance

@description('The compute cluster name for Azure ML')
output mlComputeClusterName string = resourceNames.computeCluster

@description('Available quantum providers and their SKUs')
output quantumProviders array = quantumProviders

@description('Resource naming convention used')
output resourceNamingConvention object = resourceNames

@description('Environment and project tags applied to resources')
output appliedTags object = tags