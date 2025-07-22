@description('Module for creating virtual network and subnet for HPC Cache')

// Parameters
@description('Location for the virtual network')
param location string

@description('Virtual network name')
param virtualNetworkName string

@description('Subnet name for HPC Cache')
param subnetName string

@description('Virtual network address space')
param addressPrefix string = '10.0.0.0/16'

@description('Subnet address prefix')
param subnetAddressPrefix string = '10.0.1.0/24'

@description('Tags to apply to resources')
param tags object = {}

// Virtual Network for HPC Cache
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          delegations: [
            {
              name: 'Microsoft.StorageCache/caches'
              properties: {
                serviceName: 'Microsoft.StorageCache/caches'
              }
            }
          ]
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
        }
      }
    ]
  }
}

// Outputs
@description('Virtual Network ID')
output virtualNetworkId string = virtualNetwork.id

@description('Virtual Network Name')
output virtualNetworkName string = virtualNetwork.name

@description('Subnet ID')
output subnetId string = '${virtualNetwork.id}/subnets/${subnetName}'

@description('Subnet Name')
output subnetName string = subnetName

@description('Address Space')
output addressSpace string = addressPrefix