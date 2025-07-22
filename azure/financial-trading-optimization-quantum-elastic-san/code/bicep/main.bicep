// Azure Quantum Financial Trading Algorithms with Elastic SAN
// This Bicep template deploys a comprehensive quantum-enhanced financial trading system
// combining Azure Quantum, Elastic SAN, Machine Learning, and monitoring services

targetScope = 'resourceGroup'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Base name for all resources')
@minLength(3)
@maxLength(10)
param baseName string = 'qtrade'

@description('Admin username for compute resources')
param adminUsername string = 'azureuser'

@description('Admin password for compute resources')
@secure()
param adminPassword string

@description('Object ID of the Azure AD user or group for key vault access')
param keyVaultAccessObjectId string

@description('Azure Elastic SAN base size in TiB')
@minValue(1)
@maxValue(100)
param elasticSanBaseSizeTib int = 10

@description('Azure Elastic SAN extended capacity size in TiB')
@minValue(0)
@maxValue(500)
param elasticSanExtendedCapacityTib int = 5

@description('Enable quantum workspace (requires preview access)')
param enableQuantumWorkspace bool = true

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Workload: 'quantum-trading'
  CostCenter: 'finance'
  Owner: 'trading-team'
}

// Variables for resource naming
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var resourcePrefix = '${baseName}-${environment}'

// Storage account names (must be globally unique and lowercase)
var storageAccountName = '${toLower(baseName)}${toLower(environment)}${uniqueSuffix}'
var elasticSanName = '${resourcePrefix}-esan-${uniqueSuffix}'

// Resource names
var keyVaultName = '${resourcePrefix}-kv-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-log-${uniqueSuffix}'
var applicationInsightsName = '${resourcePrefix}-ai-${uniqueSuffix}'
var mlWorkspaceName = '${resourcePrefix}-ml-${uniqueSuffix}'
var quantumWorkspaceName = '${resourcePrefix}-quantum-${uniqueSuffix}'
var eventHubNamespaceName = '${resourcePrefix}-eh-${uniqueSuffix}'
var dataFactoryName = '${resourcePrefix}-df-${uniqueSuffix}'
var streamAnalyticsJobName = '${resourcePrefix}-sa-${uniqueSuffix}'
var containerRegistryName = '${toLower(resourcePrefix)}cr${uniqueSuffix}'

// Key Vault for secrets management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'premium'
    }
    tenantId: tenant().tenantId
    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    accessPolicies: [
      {
        tenantId: tenant().tenantId
        objectId: keyVaultAccessObjectId
        permissions: {
          keys: ['all']
          secrets: ['all']
          certificates: ['all']
        }
      }
    ]
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Store admin password in Key Vault
resource adminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'admin-password'
  properties: {
    value: adminPassword
    attributes: {
      enabled: true
    }
  }
}

// Storage account for general purpose storage
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
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
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Blob containers for different data types
resource marketDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/market-data'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Market data storage for quantum algorithms'
    }
  }
}

resource quantumResultsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/quantum-results'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Quantum optimization results storage'
    }
  }
}

// Azure Elastic SAN for ultra-high performance storage
resource elasticSan 'Microsoft.ElasticSan/elasticSans@2023-01-01' = {
  name: elasticSanName
  location: location
  tags: tags
  properties: {
    baseSizeTiB: elasticSanBaseSizeTib
    extendedCapacitySizeTiB: elasticSanExtendedCapacityTib
    sku: {
      name: 'Premium_LRS'
      tier: 'Premium'
    }
  }
}

// Volume group for market data
resource marketDataVolumeGroup 'Microsoft.ElasticSan/elasticSans/volumeGroups@2023-01-01' = {
  parent: elasticSan
  name: 'vg-market-data'
  properties: {
    protocolType: 'iSCSI'
    networkAcls: {
      virtualNetworkRules: []
    }
  }
}

// Volume for real-time market data
resource realtimeDataVolume 'Microsoft.ElasticSan/elasticSans/volumeGroups/volumes@2023-01-01' = {
  parent: marketDataVolumeGroup
  name: 'vol-realtime-data'
  properties: {
    sizeGiB: 1000
    creationData: {
      createOption: 'None'
    }
  }
}

// Log Analytics workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    features: {
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

// Container Registry for ML models and algorithms
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    encryption: {
      status: 'enabled'
    }
    networkRuleBypassOptions: 'AzureServices'
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
  }
}

// Azure Machine Learning workspace
resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: mlWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: applicationInsights.id
    containerRegistry: containerRegistry.id
    encryption: {
      status: 'Enabled'
      keyVaultProperties: {
        keyVaultArmId: keyVault.id
        keyIdentifier: '${keyVault.properties.vaultUri}keys/ml-workspace-key'
      }
    }
    hbiWorkspace: false
    publicNetworkAccess: 'Enabled'
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
  }
}

// Compute cluster for ML training
resource mlComputeCluster 'Microsoft.MachineLearningServices/workspaces/computes@2024-04-01' = {
  parent: mlWorkspace
  name: 'quantum-compute-cluster'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    computeType: 'AmlCompute'
    properties: {
      vmSize: 'Standard_DS3_v2'
      vmPriority: 'Dedicated'
      scaleSettings: {
        minNodeCount: 0
        maxNodeCount: 10
        nodeIdleTimeBeforeScaleDown: 'PT120S'
      }
      enableNodePublicIp: false
      isolatedNetwork: false
      osType: 'Linux'
    }
  }
}

// Azure Quantum workspace (conditional deployment)
resource quantumWorkspace 'Microsoft.Quantum/workspaces@2023-11-13-preview' = if (enableQuantumWorkspace) {
  name: quantumWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    providers: [
      {
        providerId: 'microsoft'
        providerSku: 'DZI'
      }
      {
        providerId: 'ionq'
        providerSku: 'pay-as-you-go-cred'
      }
    ]
    storageAccount: storageAccount.id
  }
}

// Event Hub namespace for real-time data streaming
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2023-01-01-preview' = {
  name: eventHubNamespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: true
    maximumThroughputUnits: 5
    kafkaEnabled: true
  }
}

// Event Hub for market data streaming
resource marketDataEventHub 'Microsoft.EventHub/namespaces/eventhubs@2023-01-01-preview' = {
  parent: eventHubNamespace
  name: 'market-data-stream'
  properties: {
    messageRetentionInDays: 1
    partitionCount: 4
    status: 'Active'
  }
}

// Consumer group for market data processing
resource marketDataConsumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2023-01-01-preview' = {
  parent: marketDataEventHub
  name: 'quantum-processor'
  properties: {
    userMetadata: 'Consumer group for quantum trading algorithm processing'
  }
}

// Data Factory for data orchestration
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    encryption: {
      identity: {
        userAssignedIdentity: null
      }
    }
  }
}

// Stream Analytics job for real-time processing
resource streamAnalyticsJob 'Microsoft.StreamAnalytics/streamingjobs@2021-10-01-preview' = {
  name: streamAnalyticsJobName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Standard'
    }
    outputErrorPolicy: 'Stop'
    eventsOutOfOrderPolicy: 'Adjust'
    eventsOutOfOrderMaxDelayInSeconds: 0
    eventsLateArrivalMaxDelayInSeconds: 5
    dataLocale: 'en-US'
    compatibilityLevel: '1.2'
    contentStoragePolicy: 'SystemAccount'
    jobType: 'Cloud'
  }
}

// Monitoring alert for quantum job duration
resource quantumJobDurationAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableQuantumWorkspace) {
  name: 'quantum-job-duration-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when quantum job duration exceeds threshold'
    severity: 2
    enabled: true
    scopes: [
      quantumWorkspace.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'QuantumJobDuration'
          metricNamespace: 'Microsoft.Quantum/workspaces'
          metricName: 'JobDuration'
          operator: 'GreaterThan'
          threshold: 300
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

// Storage performance alert
resource storagePerformanceAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'elastic-san-performance-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when Elastic SAN IOPS drops below threshold'
    severity: 1
    enabled: true
    scopes: [
      elasticSan.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ElasticSanIOPS'
          metricNamespace: 'Microsoft.ElasticSan/elasticSans'
          metricName: 'VolumeIOPS'
          operator: 'LessThan'
          threshold: 50000
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

// RBAC assignments for ML workspace managed identity
resource mlWorkspaceStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, mlWorkspace.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: mlWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource mlWorkspaceKeyVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, mlWorkspace.id, 'KeyVaultContributor')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f25e0fa2-a7c8-4377-a976-54943a77a395') // Key Vault Contributor
    principalId: mlWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC assignment for Data Factory to access Event Hub
resource dataFactoryEventHubRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventHubNamespace.id, dataFactory.id, 'EventHubDataReceiver')
  scope: eventHubNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde') // Azure Event Hubs Data Receiver
    principalId: dataFactory.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC assignment for Stream Analytics to access Event Hub
resource streamAnalyticsEventHubRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventHubNamespace.id, streamAnalyticsJob.id, 'EventHubDataReceiver')
  scope: eventHubNamespace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde') // Azure Event Hubs Data Receiver
    principalId: streamAnalyticsJob.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs for reference and validation
output resourceGroupName string = resourceGroup().name
output location string = location
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output elasticSanName string = elasticSan.name
output elasticSanId string = elasticSan.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output mlWorkspaceName string = mlWorkspace.name
output mlWorkspaceId string = mlWorkspace.id
output quantumWorkspaceName string = enableQuantumWorkspace ? quantumWorkspace.name : 'Not deployed'
output quantumWorkspaceId string = enableQuantumWorkspace ? quantumWorkspace.id : 'Not deployed'
output applicationInsightsName string = applicationInsights.name
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output eventHubNamespaceName string = eventHubNamespace.name
output eventHubConnectionString string = eventHubNamespace.listKeys().primaryConnectionString
output dataFactoryName string = dataFactory.name
output streamAnalyticsJobName string = streamAnalyticsJob.name
output containerRegistryName string = containerRegistry.name
output containerRegistryLoginServer string = containerRegistry.properties.loginServer