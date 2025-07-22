@description('Module for creating Azure HPC Cache')

// Parameters
@description('Location for the HPC Cache')
param location string

@description('HPC Cache name')
param hpcCacheName string

@description('HPC Cache size in GB')
@allowed([3072, 6144, 12288, 24576, 49152])
param hpcCacheSize int = 3072

@description('HPC Cache SKU')
@allowed(['Standard_2G', 'Standard_4G', 'Standard_8G'])
param hpcCacheSku string = 'Standard_2G'

@description('Subnet ID for HPC Cache')
param subnetId string

@description('Tags to apply to resources')
param tags object = {}

@description('Storage targets configuration')
param storageTargets array = []

@description('Cache security settings')
param securitySettings object = {
  accessPolicies: [
    {
      name: 'default'
      accessRules: [
        {
          scope: 'default'
          access: 'rw'
          suid: false
          submountAccess: true
          rootSquash: false
        }
      ]
    }
  ]
}

// HPC Cache
resource hpcCache 'Microsoft.StorageCache/caches@2023-05-01' = {
  name: hpcCacheName
  location: location
  tags: tags
  sku: {
    name: hpcCacheSku
  }
  properties: {
    cacheSizeGB: hpcCacheSize
    subnet: subnetId
    upgradeSettings: {
      upgradeScheduleEnabled: true
      scheduledTime: '22:00'
    }
    securitySettings: securitySettings
  }
}

// Storage targets (if provided)
resource storageTargetResources 'Microsoft.StorageCache/caches/storageTargets@2023-05-01' = [for storageTarget in storageTargets: {
  name: storageTarget.name
  parent: hpcCache
  properties: storageTarget.properties
}]

// Outputs
@description('HPC Cache ID')
output hpcCacheId string = hpcCache.id

@description('HPC Cache Name')
output hpcCacheName string = hpcCache.name

@description('HPC Cache Mount Addresses')
output hpcCacheMountAddresses array = hpcCache.properties.mountAddresses

@description('HPC Cache Health State')
output hpcCacheHealthState string = hpcCache.properties.health.state

@description('HPC Cache Provisioning State')
output hpcCacheProvisioningState string = hpcCache.properties.provisioningState

@description('HPC Cache Size')
output hpcCacheSize int = hpcCache.properties.cacheSizeGB

@description('HPC Cache SKU')
output hpcCacheSku string = hpcCache.sku.name