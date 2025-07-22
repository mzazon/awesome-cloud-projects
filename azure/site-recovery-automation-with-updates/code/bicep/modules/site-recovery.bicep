@description('Site Recovery configuration module')

// Parameters
@description('Recovery Services Vault name')
param vaultName string

@description('Primary location')
param primaryLocation string

@description('Secondary location')
param secondaryLocation string

@description('Primary VM resource ID')
param primaryVmResourceId string

@description('Primary Virtual Network ID')
param primaryVnetId string

@description('Secondary Virtual Network ID')
param secondaryVnetId string

@description('Storage Account name for Site Recovery')
param storageAccountName string

@description('Resource tags')
param tags object

// Variables
var fabricName = 'ASR-Fabric-${primaryLocation}'
var protectionContainerName = 'ASR-Container-${primaryLocation}'
var networkMappingName = 'ASR-NetworkMapping-${primaryLocation}-to-${secondaryLocation}'
var replicationPolicyName = 'ASR-ReplicationPolicy'

// Reference existing Recovery Services Vault
resource recoveryServicesVault 'Microsoft.RecoveryServices/vaults@2023-06-01' existing = {
  name: vaultName
}

// Reference existing storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Site Recovery Fabric for primary location
resource primaryFabric 'Microsoft.RecoveryServices/vaults/replicationFabrics@2023-06-01' = {
  parent: recoveryServicesVault
  name: fabricName
  properties: {
    customDetails: {
      instanceType: 'Azure'
      location: primaryLocation
    }
  }
}

// Site Recovery Protection Container
resource protectionContainer 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationProtectionContainers@2023-06-01' = {
  parent: primaryFabric
  name: protectionContainerName
  properties: {
    providerSpecificInput: [
      {
        instanceType: 'A2A'
      }
    ]
  }
}

// Site Recovery Replication Policy
resource replicationPolicy 'Microsoft.RecoveryServices/vaults/replicationPolicies@2023-06-01' = {
  parent: recoveryServicesVault
  name: replicationPolicyName
  properties: {
    providerSpecificInput: {
      instanceType: 'A2A'
      recoveryPointRetentionInHours: 24
      appConsistentFrequencyInHours: 4
      crashConsistentFrequencyInHours: 4
      multiVmSyncStatus: 'Enable'
    }
  }
}

// Protection Container Mapping
resource protectionContainerMapping 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationProtectionContainers/replicationProtectionContainerMappings@2023-06-01' = {
  parent: protectionContainer
  name: 'ASR-ContainerMapping'
  properties: {
    targetProtectionContainerId: protectionContainer.id
    policyId: replicationPolicy.id
    providerSpecificInput: {
      instanceType: 'A2A'
    }
  }
}

// Network Mapping
resource networkMapping 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationNetworks/replicationNetworkMappings@2023-06-01' = {
  parent: primaryFabric
  name: 'network1/mapping1'
  properties: {
    recoveryFabricName: fabricName
    recoveryNetworkId: secondaryVnetId
    fabricSpecificDetails: {
      instanceType: 'AzureToAzure'
      primaryNetworkId: primaryVnetId
    }
  }
}

// Storage Account for cache
resource cacheStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'cache${uniqueString(resourceGroup().id)}'
  location: primaryLocation
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
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

// Replica Storage Account in secondary region
resource replicaStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'replica${uniqueString(resourceGroup().id)}'
  location: secondaryLocation
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
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

// Recovery Plan
resource recoveryPlan 'Microsoft.RecoveryServices/vaults/replicationRecoveryPlans@2023-06-01' = {
  parent: recoveryServicesVault
  name: 'DR-RecoveryPlan'
  properties: {
    primaryFabricId: primaryFabric.id
    recoveryFabricId: primaryFabric.id
    failoverDeploymentModel: 'ResourceManager'
    groups: [
      {
        groupType: 'Boot'
        replicationProtectedItems: []
        startGroupActions: []
        endGroupActions: []
      }
    ]
  }
}

// Outputs
@description('Primary Fabric ID')
output primaryFabricId string = primaryFabric.id

@description('Protection Container ID')
output protectionContainerId string = protectionContainer.id

@description('Replication Policy ID')
output replicationPolicyId string = replicationPolicy.id

@description('Protection Container Mapping ID')
output protectionContainerMappingId string = protectionContainerMapping.id

@description('Network Mapping ID')
output networkMappingId string = networkMapping.id

@description('Cache Storage Account ID')
output cacheStorageAccountId string = cacheStorageAccount.id

@description('Replica Storage Account ID')
output replicaStorageAccountId string = replicaStorageAccount.id

@description('Recovery Plan ID')
output recoveryPlanId string = recoveryPlan.id