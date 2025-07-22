@description('Azure region for this deployment')
param location string

@description('Virtual network name')
param vnetName string

@description('Virtual network address space')
param vnetAddressSpace string

@description('Azure NetApp Files subnet prefix')
param anfSubnetPrefix string

@description('Private endpoint subnet prefix')
param privateEndpointSubnetPrefix string

@description('Azure NetApp Files account name')
param anfAccountName string

@description('Capacity pool name')
param capacityPoolName string

@description('Volume name')
param volumeName string

@description('NetApp Files service level')
param netAppServiceLevel string

@description('Capacity pool size in TiB')
param capacityPoolSize int

@description('Volume size in GiB')
param volumeSize int

@description('Load balancer name')
param loadBalancerName string

@description('Naming prefix for resources')
param namingPrefix string

@description('Tags to apply to resources')
param tags object

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: 'anf-subnet'
        properties: {
          addressPrefix: anfSubnetPrefix
          delegations: [
            {
              name: 'NetAppDelegation'
              properties: {
                serviceName: 'Microsoft.NetApp/volumes'
              }
            }
          ]
          serviceEndpoints: []
        }
      }
      {
        name: 'pe-subnet'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Azure NetApp Files Account
resource netAppAccount 'Microsoft.NetApp/netAppAccounts@2023-11-01' = {
  name: anfAccountName
  location: location
  tags: tags
  properties: {
    encryption: {
      keySource: 'Microsoft.NetApp'
    }
  }
}

// Capacity Pool
resource capacityPool 'Microsoft.NetApp/netAppAccounts/capacityPools@2023-11-01' = {
  parent: netAppAccount
  name: capacityPoolName
  location: location
  tags: tags
  properties: {
    serviceLevel: netAppServiceLevel
    size: capacityPoolSize * 1099511627776 // Convert TiB to bytes
    qosType: 'Auto'
    coolAccess: false
    encryptionType: 'Single'
  }
}

// NetApp Files Volume
resource volume 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes@2023-11-01' = {
  parent: capacityPool
  name: volumeName
  location: location
  tags: tags
  properties: {
    serviceLevel: netAppServiceLevel
    usageThreshold: volumeSize * 1073741824 // Convert GiB to bytes
    exportPolicy: {
      rules: [
        {
          ruleIndex: 1
          unixReadOnly: false
          unixReadWrite: true
          cifs: false
          nfsv3: true
          nfsv41: false
          allowedClients: '10.0.0.0/8'
          kerberos5ReadOnly: false
          kerberos5ReadWrite: false
          kerberos5iReadOnly: false
          kerberos5iReadWrite: false
          kerberos5pReadOnly: false
          kerberos5pReadWrite: false
          hasRootAccess: true
          chownMode: 'Restricted'
        }
      ]
    }
    protocolTypes: [
      'NFSv3'
    ]
    subnetId: '${vnet.id}/subnets/anf-subnet'
    creationToken: '${volumeName}-${uniqueString(resourceGroup().id)}'
    securityStyle: 'unix'
    smbEncryption: false
    smbContinuouslyAvailable: false
    throughputMibps: 64
    volumeType: ''
    dataProtection: {
      backup: {
        backupEnabled: false
      }
      replication: {
        replicationSchedule: '_10minutely'
        endpointType: 'dst'
      }
      snapshot: {
        snapshotPolicyId: ''
      }
    }
    isDefaultQuotaEnabled: false
    defaultUserQuotaInKiBs: 0
    defaultGroupQuotaInKiBs: 0
    networkFeatures: 'Standard'
    enableSubvolumes: 'Disabled'
    maximumNumberOfFiles: 100000000
    unixPermissions: '0755'
    avsDataStore: 'Disabled'
    isLargeVolume: false
    kerberosEnabled: false
    ldapEnabled: false
    zones: []
  }
}

// Load Balancer for Private Link Service
resource loadBalancer 'Microsoft.Network/loadBalancers@2023-11-01' = {
  name: loadBalancerName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'frontend-ip'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/anf-subnet'
          }
          privateIPAddress: split(anfSubnetPrefix, '/')[0] == '10.1.1.0' ? '10.1.1.10' : '10.2.1.10'
          privateIPAllocationMethod: 'Static'
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'backend-pool'
        properties: {}
      }
    ]
    probes: [
      {
        name: 'health-probe'
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 15
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'content-rule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, 'frontend-ip')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'backend-pool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'health-probe')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          loadDistribution: 'Default'
          enableTcpReset: false
          disableOutboundSnat: false
        }
      }
    ]
  }
}

// Private Link Service
resource privateLinkService 'Microsoft.Network/privateLinkServices@2023-11-01' = {
  name: '${namingPrefix}-pls-${location}'
  location: location
  tags: tags
  properties: {
    enableProxyProtocol: false
    loadBalancerFrontendIpConfigurations: [
      {
        id: '${loadBalancer.id}/frontendIPConfigurations/frontend-ip'
      }
    ]
    ipConfigurations: [
      {
        name: 'primary'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnet.id}/subnets/pe-subnet'
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
        }
      }
    ]
    visibility: {
      subscriptions: [
        '*'
      ]
    }
    autoApproval: {
      subscriptions: [
        '*'
      ]
    }
    fqdns: []
  }
}

// Network Security Group for Private Endpoint subnet
resource nsgPrivateEndpoint 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namingPrefix}-nsg-pe-${location}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowFrontDoorInbound'
        properties: {
          description: 'Allow inbound traffic from Front Door'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHttpsInbound'
        properties: {
          description: 'Allow HTTPS inbound traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Deny all other inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4096
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Associate NSG with Private Endpoint subnet
resource nsgAssociation 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = {
  parent: vnet
  name: 'pe-subnet'
  properties: {
    addressPrefix: privateEndpointSubnetPrefix
    networkSecurityGroup: {
      id: nsgPrivateEndpoint.id
    }
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Disabled'
  }
}

// Outputs
output vnetId string = vnet.id
output vnetName string = vnet.name
output anfSubnetId string = '${vnet.id}/subnets/anf-subnet'
output privateEndpointSubnetId string = '${vnet.id}/subnets/pe-subnet'
output netAppAccountId string = netAppAccount.id
output netAppAccountName string = netAppAccount.name
output capacityPoolId string = capacityPool.id
output capacityPoolName string = capacityPool.name
output volumeId string = volume.id
output volumeName string = volume.name
output volumeMountTargets array = volume.properties.mountTargets
output loadBalancerId string = loadBalancer.id
output loadBalancerName string = loadBalancer.name
output privateLinkServiceId string = privateLinkService.id
output privateLinkServiceName string = privateLinkService.name
output nsgPrivateEndpointId string = nsgPrivateEndpoint.id