@description('Module for creating Azure Batch account and pool')

// Parameters
@description('Location for the Batch account')
param location string

@description('Batch account name')
param batchAccountName string

@description('Storage account ID for Batch auto-storage')
param storageAccountId string

@description('Batch pool name')
param batchPoolName string = 'hpc-pool'

@description('VM size for Batch pool')
param batchVmSize string = 'Standard_HC44rs'

@description('Number of nodes in the Batch pool')
@minValue(0)
@maxValue(100)
param batchPoolNodeCount int = 2

@description('Subnet ID for Batch pool')
param subnetId string

@description('Tags to apply to resources')
param tags object = {}

@description('VM image reference')
param vmImageReference object = {
  publisher: 'Canonical'
  offer: '0001-com-ubuntu-server-focal'
  sku: '20_04-lts-gen2'
  version: 'latest'
}

@description('Node agent SKU ID')
param nodeAgentSkuId string = 'batch.node.ubuntu 20.04'

// Batch Account
resource batchAccount 'Microsoft.Batch/batchAccounts@2023-11-01' = {
  name: batchAccountName
  location: location
  tags: tags
  properties: {
    autoStorage: {
      storageAccountId: storageAccountId
    }
    poolAllocationMode: 'BatchService'
    publicNetworkAccess: 'Enabled'
    networkProfile: {
      nodeManagementAccess: {
        defaultAction: 'Allow'
      }
    }
    encryption: {
      keySource: 'Microsoft.Batch'
    }
  }
}

// Batch Pool
resource batchPool 'Microsoft.Batch/batchAccounts/pools@2023-11-01' = {
  name: batchPoolName
  parent: batchAccount
  properties: {
    vmSize: batchVmSize
    deploymentConfiguration: {
      virtualMachineConfiguration: {
        imageReference: vmImageReference
        nodeAgentSkuId: nodeAgentSkuId
      }
    }
    scaleSettings: {
      fixedScale: {
        targetDedicatedNodes: batchPoolNodeCount
        resizeTimeout: 'PT15M'
      }
    }
    networkConfiguration: {
      subnetId: subnetId
    }
    interNodeCommunication: 'Enabled'
    taskSlotsPerNode: 1
    taskSchedulingPolicy: {
      nodeFillType: 'Spread'
    }
  }
}

// Outputs
@description('Batch Account ID')
output batchAccountId string = batchAccount.id

@description('Batch Account Name')
output batchAccountName string = batchAccount.name

@description('Batch Account Endpoint')
output batchAccountEndpoint string = batchAccount.properties.accountEndpoint

@description('Batch Pool Name')
output batchPoolName string = batchPool.name

@description('Batch Pool VM Size')
output batchPoolVmSize string = batchPool.properties.vmSize

@description('Batch Pool Node Count')
output batchPoolNodeCount int = batchPool.properties.scaleSettings.fixedScale.targetDedicatedNodes

@description('Batch Pool State')
output batchPoolState string = batchPool.properties.allocationState