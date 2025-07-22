@description('Scalable HPC Workload Processing with Elastic SAN and Azure Batch')
@description('This template deploys a complete HPC infrastructure with Azure Elastic SAN for high-performance shared storage and Azure Batch for managed parallel processing')

// ==============================================================================
// PARAMETERS
// ==============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Workload name prefix for resource naming')
@minLength(3)
@maxLength(8)
param workloadName string = 'hpc'

@description('Unique suffix for resource names (will be generated if not provided)')
param uniqueSuffix string = take(uniqueString(resourceGroup().id, deployment().name), 8)

@description('Azure Elastic SAN base size in TiB')
@minValue(1)
@maxValue(100)
param elasticSanBaseSizeTiB int = 1

@description('Azure Elastic SAN extended capacity size in TiB')
@minValue(0)
@maxValue(100)
param elasticSanExtendedCapacityTiB int = 2

@description('Data input volume size in GiB')
@minValue(100)
@maxValue(5000)
param dataInputVolumeSizeGiB int = 500

@description('Results output volume size in GiB')
@minValue(100)
@maxValue(5000)
param resultsOutputVolumeSizeGiB int = 1000

@description('Shared libraries volume size in GiB')
@minValue(50)
@maxValue(1000)
param sharedLibrariesVolumeSizeGiB int = 100

@description('VM size for Batch compute nodes')
@allowed(['Standard_HC44rs', 'Standard_HB60rs', 'Standard_HB120rs_v2', 'Standard_F72s_v2'])
param batchVmSize string = 'Standard_HC44rs'

@description('Target number of dedicated nodes in Batch pool')
@minValue(0)
@maxValue(50)
param targetDedicatedNodes int = 2

@description('Maximum number of nodes for auto-scaling')
@minValue(1)
@maxValue(100)
param maxNodes int = 20

@description('Enable inter-node communication for MPI workloads')
param enableInterNodeCommunication bool = true

@description('Enable diagnostics and monitoring')
param enableDiagnostics bool = true

@description('Log retention in days')
@minValue(30)
@maxValue(365)
param logRetentionDays int = 30

@description('Resource tags')
param tags object = {
  workload: 'hpc'
  environment: environment
  purpose: 'high-performance-computing'
  solution: 'elastic-san-batch'
}

// ==============================================================================
// VARIABLES
// ==============================================================================

var resourcePrefix = '${workloadName}-${environment}'
var resourceSuffix = uniqueSuffix

// Resource names
var virtualNetworkName = '${resourcePrefix}-vnet-${resourceSuffix}'
var networkSecurityGroupName = '${resourcePrefix}-nsg-${resourceSuffix}'
var batchSubnetName = 'batch-subnet'
var elasticSanName = '${resourcePrefix}-esan-${resourceSuffix}'
var batchAccountName = '${resourcePrefix}-batch-${resourceSuffix}'
var storageAccountName = '${resourcePrefix}st${resourceSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-law-${resourceSuffix}'
var applicationInsightsName = '${resourcePrefix}-ai-${resourceSuffix}'

// Batch pool configuration
var batchPoolId = 'hpc-compute-pool'
var batchPoolDisplayName = 'HPC Compute Pool for ${workloadName}'

// Virtual network configuration
var vnetAddressPrefix = '10.0.0.0/16'
var batchSubnetAddressPrefix = '10.0.1.0/24'

// Volume names
var dataInputVolumeName = 'data-input'
var resultsOutputVolumeName = 'results-output'
var sharedLibrariesVolumeName = 'shared-libraries'

// ==============================================================================
// EXISTING RESOURCES
// ==============================================================================

// Get current subscription for resource references
var subscriptionId = subscription().subscriptionId
var resourceGroupName = resourceGroup().name

// ==============================================================================
// NETWORKING RESOURCES
// ==============================================================================

@description('Network Security Group for HPC workloads')
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: networkSecurityGroupName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowHPCCommunication'
        properties: {
          description: 'Allow internal HPC communication between compute nodes'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1024-65535'
          sourceAddressPrefix: vnetAddressPrefix
          destinationAddressPrefix: vnetAddressPrefix
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowiSCSI'
        properties: {
          description: 'Allow iSCSI traffic for Elastic SAN connectivity'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3260'
          sourceAddressPrefix: vnetAddressPrefix
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowBatchManagement'
        properties: {
          description: 'Allow Azure Batch management traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '29876-29877'
          sourceAddressPrefix: 'BatchNodeManagement'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1200
          direction: 'Inbound'
        }
      }
    ]
  }
}

@description('Virtual Network for HPC infrastructure')
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: batchSubnetName
        properties: {
          addressPrefix: batchSubnetAddressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
              locations: [location]
            }
            {
              service: 'Microsoft.Batch'
              locations: [location]
            }
          ]
        }
      }
    ]
  }
}

// ==============================================================================
// STORAGE RESOURCES
// ==============================================================================

@description('Storage Account for Batch applications and logs')
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
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    allowCrossTenantReplication: false
    defaultToOAuthAuthentication: false
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: [
        {
          id: '${virtualNetwork.id}/subnets/${batchSubnetName}'
          action: 'Allow'
        }
      ]
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
      requireInfrastructureEncryption: true
    }
  }
}

@description('Blob container for scripts and applications')
resource scriptsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/scripts'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'hpc-scripts'
      workload: workloadName
    }
  }
}

@description('Blob container for results and outputs')
resource resultsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/results'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'hpc-results'
      workload: workloadName
    }
  }
}

// ==============================================================================
// AZURE ELASTIC SAN
// ==============================================================================

@description('Azure Elastic SAN for high-performance shared storage')
resource elasticSan 'Microsoft.ElasticSan/elasticSans@2023-01-01' = {
  name: elasticSanName
  location: location
  tags: tags
  properties: {
    baseSizeTiB: elasticSanBaseSizeTiB
    extendedCapacitySizeTiB: elasticSanExtendedCapacityTiB
    sku: {
      name: 'Premium_LRS'
      tier: 'Premium'
    }
    availabilityZones: [
      '1'
      '2'
      '3'
    ]
  }
}

@description('Volume Group for HPC storage organization')
resource elasticSanVolumeGroup 'Microsoft.ElasticSan/elasticSans/volumeGroups@2023-01-01' = {
  parent: elasticSan
  name: 'hpc-volumes'
  properties: {
    protocolType: 'iSCSI'
    networkAcls: {
      virtualNetworkRules: [
        {
          id: '${virtualNetwork.id}/subnets/${batchSubnetName}'
          action: 'Allow'
        }
      ]
    }
    encryption: 'EncryptionAtRestWithPlatformKey'
  }
}

@description('Data Input Volume for HPC datasets')
resource dataInputVolume 'Microsoft.ElasticSan/elasticSans/volumeGroups/volumes@2023-01-01' = {
  parent: elasticSanVolumeGroup
  name: dataInputVolumeName
  properties: {
    sizeGiB: dataInputVolumeSizeGiB
    creationData: {
      createSource: 'None'
    }
  }
  tags: union(tags, {
    purpose: 'input-data'
    volumeType: 'data'
  })
}

@description('Results Output Volume for HPC processing results')
resource resultsOutputVolume 'Microsoft.ElasticSan/elasticSans/volumeGroups/volumes@2023-01-01' = {
  parent: elasticSanVolumeGroup
  name: resultsOutputVolumeName
  properties: {
    sizeGiB: resultsOutputVolumeSizeGiB
    creationData: {
      createSource: 'None'
    }
  }
  tags: union(tags, {
    purpose: 'output-data'
    volumeType: 'results'
  })
}

@description('Shared Libraries Volume for HPC applications and libraries')
resource sharedLibrariesVolume 'Microsoft.ElasticSan/elasticSans/volumeGroups/volumes@2023-01-01' = {
  parent: elasticSanVolumeGroup
  name: sharedLibrariesVolumeName
  properties: {
    sizeGiB: sharedLibrariesVolumeSizeGiB
    creationData: {
      createSource: 'None'
    }
  }
  tags: union(tags, {
    purpose: 'shared-libraries'
    volumeType: 'applications'
  })
}

// ==============================================================================
// MONITORING AND LOGGING
// ==============================================================================

@description('Log Analytics Workspace for HPC monitoring')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableDiagnostics) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    workspaceCapping: {
      dailyQuotaGb: 100
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

@description('Application Insights for HPC application monitoring')
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableDiagnostics) {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableDiagnostics ? logAnalyticsWorkspace.id : null
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ==============================================================================
// AZURE BATCH
// ==============================================================================

@description('Azure Batch Account for HPC workload orchestration')
resource batchAccount 'Microsoft.Batch/batchAccounts@2023-05-01' = {
  name: batchAccountName
  location: location
  tags: tags
  properties: {
    autoStorage: {
      storageAccountId: storageAccount.id
    }
    poolAllocationMode: 'BatchService'
    publicNetworkAccess: 'Enabled'
    allowedAuthenticationModes: [
      'SharedKey'
      'AAD'
    ]
    encryption: {
      keySource: 'Microsoft.Batch'
    }
  }
}

@description('Diagnostic settings for Batch account')
resource batchDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'batch-diagnostics'
  scope: batchAccount
  properties: {
    workspaceId: enableDiagnostics ? logAnalyticsWorkspace.id : null
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// ==============================================================================
// MONITORING ALERTS
// ==============================================================================

@description('High CPU usage alert for HPC pool')
resource highCpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableDiagnostics) {
  name: 'hpc-high-cpu-usage'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when HPC pool CPU usage is above 80%'
    severity: 2
    enabled: true
    scopes: [
      batchAccount.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCpuUsage'
          metricName: 'CPUPercentage'
          metricNamespace: 'Microsoft.Batch/batchAccounts'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.Batch/batchAccounts'
    targetResourceRegion: location
  }
}

@description('High node count alert for cost monitoring')
resource highNodeCountAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableDiagnostics) {
  name: 'hpc-cost-threshold'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when HPC pool node count exceeds cost threshold'
    severity: 1
    enabled: true
    scopes: [
      batchAccount.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighNodeCount'
          metricName: 'RunningNodeCount'
          metricNamespace: 'Microsoft.Batch/batchAccounts'
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.Batch/batchAccounts'
    targetResourceRegion: location
  }
}

// ==============================================================================
// RBAC AND SECURITY
// ==============================================================================

@description('Role assignment for Batch to access storage')
resource batchStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(batchAccount.id, storageAccount.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: batchAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('Resource Group name')
output resourceGroupName string = resourceGroupName

@description('Azure Batch Account name')
output batchAccountName string = batchAccount.name

@description('Azure Batch Account ID')
output batchAccountId string = batchAccount.id

@description('Azure Batch Account endpoint')
output batchAccountEndpoint string = batchAccount.properties.accountEndpoint

@description('Azure Elastic SAN name')
output elasticSanName string = elasticSan.name

@description('Azure Elastic SAN ID')
output elasticSanId string = elasticSan.id

@description('Elastic SAN Volume Group name')
output volumeGroupName string = elasticSanVolumeGroup.name

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Storage Account ID')
output storageAccountId string = storageAccount.id

@description('Storage Account primary endpoints')
output storageAccountEndpoints object = storageAccount.properties.primaryEndpoints

@description('Virtual Network name')
output virtualNetworkName string = virtualNetwork.name

@description('Virtual Network ID')
output virtualNetworkId string = virtualNetwork.id

@description('Batch Subnet ID')
output batchSubnetId string = '${virtualNetwork.id}/subnets/${batchSubnetName}'

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = enableDiagnostics ? logAnalyticsWorkspace.id : ''

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = enableDiagnostics ? logAnalyticsWorkspace.name : ''

@description('Application Insights name')
output applicationInsightsName string = enableDiagnostics ? applicationInsights.name : ''

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = enableDiagnostics ? applicationInsights.properties.InstrumentationKey : ''

@description('Volume details for iSCSI connectivity')
output volumeDetails object = {
  dataInputVolume: {
    name: dataInputVolume.name
    sizeGiB: dataInputVolume.properties.sizeGiB
    targetIqn: dataInputVolume.properties.storageTarget.targetIqn
    targetPortalHostname: dataInputVolume.properties.storageTarget.targetPortalHostname
    targetPortalPort: dataInputVolume.properties.storageTarget.targetPortalPort
  }
  resultsOutputVolume: {
    name: resultsOutputVolume.name
    sizeGiB: resultsOutputVolume.properties.sizeGiB
    targetIqn: resultsOutputVolume.properties.storageTarget.targetIqn
    targetPortalHostname: resultsOutputVolume.properties.storageTarget.targetPortalHostname
    targetPortalPort: resultsOutputVolume.properties.storageTarget.targetPortalPort
  }
  sharedLibrariesVolume: {
    name: sharedLibrariesVolume.name
    sizeGiB: sharedLibrariesVolume.properties.sizeGiB
    targetIqn: sharedLibrariesVolume.properties.storageTarget.targetIqn
    targetPortalHostname: sharedLibrariesVolume.properties.storageTarget.targetPortalHostname
    targetPortalPort: sharedLibrariesVolume.properties.storageTarget.targetPortalPort
  }
}

@description('Deployment configuration summary')
output deploymentSummary object = {
  resourcePrefix: resourcePrefix
  uniqueSuffix: resourceSuffix
  location: location
  environment: environment
  elasticSanCapacity: {
    baseSizeTiB: elasticSanBaseSizeTiB
    extendedCapacityTiB: elasticSanExtendedCapacityTiB
    totalCapacityTiB: elasticSanBaseSizeTiB + elasticSanExtendedCapacityTiB
  }
  batchConfiguration: {
    vmSize: batchVmSize
    targetDedicatedNodes: targetDedicatedNodes
    maxNodes: maxNodes
    enableInterNodeCommunication: enableInterNodeCommunication
  }
  monitoringEnabled: enableDiagnostics
}

@description('Next steps for HPC workload deployment')
output nextSteps array = [
  'Configure Azure Batch pool using the provided subnet and storage account'
  'Upload HPC applications and scripts to the storage account'
  'Configure iSCSI connectivity on compute nodes to access Elastic SAN volumes'
  'Create and submit Batch jobs for parallel processing workloads'
  'Monitor performance through Azure Monitor and Application Insights'
  'Scale compute resources based on workload demands using auto-scaling features'
]