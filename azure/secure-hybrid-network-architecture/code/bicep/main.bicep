// ================================================================================================
// Azure Hybrid Network Security with VPN Gateway and Private Link
// ================================================================================================
// This template deploys a complete hybrid network security solution with Azure VPN Gateway
// and Private Link endpoints for secure connectivity between on-premises and Azure services.
// ================================================================================================

@description('The Azure region where all resources will be deployed')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Environment type for resource tagging')
@allowed(['dev', 'test', 'prod'])
param environment string = 'test'

@description('VPN Gateway SKU for the virtual network gateway')
@allowed(['Basic', 'VpnGw1', 'VpnGw2', 'VpnGw3'])
param vpnGatewaySku string = 'Basic'

@description('Hub virtual network address space')
param hubVnetAddressPrefix string = '10.0.0.0/16'

@description('Gateway subnet address prefix within hub VNet')
param gatewaySubnetPrefix string = '10.0.1.0/27'

@description('Spoke virtual network address space')
param spokeVnetAddressPrefix string = '10.1.0.0/16'

@description('Application subnet address prefix within spoke VNet')
param applicationSubnetPrefix string = '10.1.1.0/24'

@description('Private endpoint subnet address prefix within spoke VNet')
param privateEndpointSubnetPrefix string = '10.1.2.0/24'

@description('Administrator username for the test virtual machine')
param vmAdminUsername string

@description('SSH public key for the test virtual machine')
@secure()
param vmSshPublicKey string

@description('Virtual machine size for the test VM')
param vmSize string = 'Standard_B2s'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountSku string = 'Standard_LRS'

// ================================================================================================
// Variables
// ================================================================================================

var resourceNames = {
  hubVnet: 'vnet-hub-${resourceSuffix}'
  spokeVnet: 'vnet-spoke-${resourceSuffix}'
  vpnGateway: 'vpngw-${resourceSuffix}'
  vpnGatewayPip: 'pip-vpngw-${resourceSuffix}'
  keyVault: 'kv-${resourceSuffix}'
  storageAccount: 'st${replace(resourceSuffix, '-', '')}'
  testVm: 'vm-test-${resourceSuffix}'
  testVmNic: 'nic-test-${resourceSuffix}'
  keyVaultPrivateEndpoint: 'pe-kv-${resourceSuffix}'
  storagePrivateEndpoint: 'pe-st-${resourceSuffix}'
  keyVaultPrivateDnsZone: 'privatelink.vaultcore.azure.net'
  storagePrivateDnsZone: 'privatelink.blob.core.windows.net'
}

var commonTags = {
  Environment: environment
  Purpose: 'hybrid-network-security'
  Recipe: 'vpn-gateway-private-link'
  CreatedBy: 'bicep-template'
}

// ================================================================================================
// Hub Virtual Network and VPN Gateway
// ================================================================================================

// Public IP for VPN Gateway
resource vpnGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: resourceNames.vpnGatewayPip
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
  }
}

// Hub Virtual Network
resource hubVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: resourceNames.hubVnet
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubVnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: gatewaySubnetPrefix
          serviceEndpoints: []
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
    enableDdosProtection: false
    enableVmProtection: false
  }
}

// VPN Gateway
resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2023-09-01' = {
  name: resourceNames.vpnGateway
  location: location
  tags: commonTags
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    sku: {
      name: vpnGatewaySku
      tier: vpnGatewaySku
    }
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          publicIPAddress: {
            id: vpnGatewayPublicIp.id
          }
          subnet: {
            id: '${hubVnet.id}/subnets/GatewaySubnet'
          }
        }
      }
    ]
    enableBgp: false
    activeActive: false
    vpnGatewayGeneration: 'Generation1'
  }
}

// ================================================================================================
// Spoke Virtual Network and Subnets
// ================================================================================================

// Spoke Virtual Network
resource spokeVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: resourceNames.spokeVnet
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        spokeVnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'ApplicationSubnet'
        properties: {
          addressPrefix: applicationSubnetPrefix
          serviceEndpoints: []
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'PrivateEndpointSubnet'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          serviceEndpoints: []
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
    enableDdosProtection: false
    enableVmProtection: false
  }
}

// VNet Peering: Hub to Spoke
resource hubToSpokeVnetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: hubVnet
  name: 'HubToSpoke'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: true
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spokeVnet.id
    }
  }
  dependsOn: [
    vpnGateway
  ]
}

// VNet Peering: Spoke to Hub
resource spokeToHubVnetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: spokeVnet
  name: 'SpokeToHub'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: true
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
  }
  dependsOn: [
    vpnGateway
  ]
}

// ================================================================================================
// Azure Services (Key Vault and Storage Account)
// ================================================================================================

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: commonTags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: commonTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    allowCrossTenantReplication: false
    defaultToOAuthAuthentication: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// ================================================================================================
// Private DNS Zones
// ================================================================================================

// Private DNS Zone for Key Vault
resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: resourceNames.keyVaultPrivateDnsZone
  location: 'global'
  tags: commonTags
}

// Private DNS Zone for Storage Account
resource storagePrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: resourceNames.storagePrivateDnsZone
  location: 'global'
  tags: commonTags
}

// Link Key Vault DNS Zone to Hub VNet
resource keyVaultDnsZoneHubVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultPrivateDnsZone
  name: 'hub-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVnet.id
    }
  }
}

// Link Key Vault DNS Zone to Spoke VNet
resource keyVaultDnsZoneSpokeVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultPrivateDnsZone
  name: 'spoke-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: spokeVnet.id
    }
  }
}

// Link Storage DNS Zone to Hub VNet
resource storageDnsZoneHubVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: storagePrivateDnsZone
  name: 'hub-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVnet.id
    }
  }
}

// Link Storage DNS Zone to Spoke VNet
resource storageDnsZoneSpokeVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: storagePrivateDnsZone
  name: 'spoke-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: spokeVnet.id
    }
  }
}

// ================================================================================================
// Private Endpoints
// ================================================================================================

// Private Endpoint for Key Vault
resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: resourceNames.keyVaultPrivateEndpoint
  location: location
  tags: commonTags
  properties: {
    subnet: {
      id: '${spokeVnet.id}/subnets/PrivateEndpointSubnet'
    }
    privateLinkServiceConnections: [
      {
        name: 'keyvault-connection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

// Private Endpoint for Storage Account
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: resourceNames.storagePrivateEndpoint
  location: location
  tags: commonTags
  properties: {
    subnet: {
      id: '${spokeVnet.id}/subnets/PrivateEndpointSubnet'
    }
    privateLinkServiceConnections: [
      {
        name: 'storage-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone Group for Key Vault Private Endpoint
resource keyVaultPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: keyVaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'keyvault-config'
        properties: {
          privateDnsZoneId: keyVaultPrivateDnsZone.id
        }
      }
    ]
  }
}

// Private DNS Zone Group for Storage Private Endpoint
resource storagePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: storagePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'storage-config'
        properties: {
          privateDnsZoneId: storagePrivateDnsZone.id
        }
      }
    ]
  }
}

// ================================================================================================
// Test Virtual Machine
// ================================================================================================

// Network Interface for Test VM
resource testVmNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: resourceNames.testVmNic
  location: location
  tags: commonTags
  properties: {
    ipConfigurations: [
      {
        name: 'internal'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${spokeVnet.id}/subnets/ApplicationSubnet'
          }
        }
      }
    ]
  }
}

// Test Virtual Machine
resource testVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: resourceNames.testVm
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: '${resourceNames.testVm}-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    osProfile: {
      computerName: resourceNames.testVm
      adminUsername: vmAdminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${vmAdminUsername}/.ssh/authorized_keys'
              keyData: vmSshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: testVmNic.id
        }
      ]
    }
  }
}

// ================================================================================================
// Role Assignments
// ================================================================================================

// Key Vault Secrets User role assignment for VM managed identity
resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, testVm.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: testVm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Data Reader role assignment for VM managed identity
resource storageBlobDataReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, testVm.id, 'Storage Blob Data Reader')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1') // Storage Blob Data Reader
    principalId: testVm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ================================================================================================
// Outputs
// ================================================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Hub virtual network resource ID')
output hubVnetId string = hubVnet.id

@description('Spoke virtual network resource ID')
output spokeVnetId string = spokeVnet.id

@description('VPN Gateway public IP address for on-premises configuration')
output vpnGatewayPublicIp string = vpnGatewayPublicIp.properties.ipAddress

@description('VPN Gateway resource ID')
output vpnGatewayId string = vpnGateway.id

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account blob endpoint')
output storageAccountBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Test VM name')
output testVmName string = testVm.name

@description('Test VM resource ID')
output testVmId string = testVm.id

@description('Test VM managed identity principal ID')
output testVmManagedIdentityPrincipalId string = testVm.identity.principalId

@description('Key Vault private endpoint IP address')
output keyVaultPrivateEndpointIp string = keyVaultPrivateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]

@description('Storage account private endpoint IP address')
output storagePrivateEndpointIp string = storagePrivateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]

@description('Private DNS zone names')
output privateDnsZones object = {
  keyVault: keyVaultPrivateDnsZone.name
  storage: storagePrivateDnsZone.name
}

@description('Deployment summary')
output deploymentSummary object = {
  hubVnetAddressSpace: hubVnetAddressPrefix
  spokeVnetAddressSpace: spokeVnetAddressPrefix
  vpnGatewaySku: vpnGatewaySku
  location: location
  environment: environment
  resourceSuffix: resourceSuffix
}