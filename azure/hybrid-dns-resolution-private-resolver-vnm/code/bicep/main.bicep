// ============================================================================
// Azure Hybrid DNS Resolution with DNS Private Resolver and Virtual Network Manager
// This template deploys a complete hybrid DNS solution including:
// - Azure DNS Private Resolver with inbound/outbound endpoints
// - Azure Virtual Network Manager with hub-spoke connectivity
// - Private DNS zones and sample private endpoints
// - Storage account with private endpoint for testing
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names (auto-generated if not provided)')
param uniqueSuffix string = take(uniqueString(resourceGroup().id), 6)

@description('Environment prefix for resource naming')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Hub virtual network address space')
param hubVNetAddressSpace string = '10.10.0.0/16'

@description('Spoke 1 virtual network address space')
param spoke1VNetAddressSpace string = '10.20.0.0/16'

@description('Spoke 2 virtual network address space')
param spoke2VNetAddressSpace string = '10.30.0.0/16'

@description('On-premises DNS server IP address for forwarding rules')
param onPremisesDnsServerIp string = '10.100.0.2'

@description('On-premises domain name for DNS forwarding')
param onPremisesDomainName string = 'contoso.com'

@description('Private DNS zone name for Azure resources')
param privateDnsZoneName string = 'azure.contoso.com'

@description('Create storage account with private endpoint for demonstration')
param createStorageDemo bool = true

@description('Tags to apply to all resources')
param resourceTags object = {
  Environment: environment
  Solution: 'HybridDNS'
  Purpose: 'DNSPrivateResolver'
  CreatedBy: 'Bicep'
}

// ============================================================================
// VARIABLES
// ============================================================================

var resourceNames = {
  hubVNet: 'vnet-hub-${environment}-${uniqueSuffix}'
  spoke1VNet: 'vnet-spoke1-${environment}-${uniqueSuffix}'
  spoke2VNet: 'vnet-spoke2-${environment}-${uniqueSuffix}'
  dnsResolver: 'dns-resolver-${environment}-${uniqueSuffix}'
  networkManager: 'avnm-${environment}-${uniqueSuffix}'
  storageAccount: 'st${environment}${uniqueSuffix}'
  privateEndpoint: 'pe-storage-${environment}-${uniqueSuffix}'
  networkGroup: 'hub-spoke-group'
  connectivityConfig: 'hub-spoke-connectivity'
  forwardingRuleset: 'onprem-forwarding-ruleset'
  forwardingRule: 'contoso-com-rule'
}

var subnetNames = {
  dnsInbound: 'dns-inbound-subnet'
  dnsOutbound: 'dns-outbound-subnet'
  default: 'default'
}

// Hub VNet subnets configuration
var hubSubnets = [
  {
    name: subnetNames.dnsInbound
    properties: {
      addressPrefix: '10.10.0.0/24'
      delegations: [
        {
          name: 'Microsoft.Network.dnsResolvers'
          properties: {
            serviceName: 'Microsoft.Network/dnsResolvers'
          }
        }
      ]
    }
  }
  {
    name: subnetNames.dnsOutbound
    properties: {
      addressPrefix: '10.10.1.0/24'
      delegations: [
        {
          name: 'Microsoft.Network.dnsResolvers'
          properties: {
            serviceName: 'Microsoft.Network/dnsResolvers'
          }
        }
      ]
    }
  }
]

// Spoke VNet subnets configuration
var spokeSubnets = [
  {
    name: subnetNames.default
    properties: {
      addressPrefix: '${split(spoke1VNetAddressSpace, '/')[0]}/24'
      privateEndpointNetworkPolicies: 'Disabled'
      privateLinkServiceNetworkPolicies: 'Disabled'
    }
  }
]

// ============================================================================
// RESOURCES
// ============================================================================

// Hub Virtual Network with DNS resolver subnets
resource hubVNet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: resourceNames.hubVNet
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [hubVNetAddressSpace]
    }
    subnets: hubSubnets
  }
}

// Spoke 1 Virtual Network
resource spoke1VNet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: resourceNames.spoke1VNet
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [spoke1VNetAddressSpace]
    }
    subnets: [
      {
        name: subnetNames.default
        properties: {
          addressPrefix: '10.20.0.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Spoke 2 Virtual Network
resource spoke2VNet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: resourceNames.spoke2VNet
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [spoke2VNetAddressSpace]
    }
    subnets: [
      {
        name: subnetNames.default
        properties: {
          addressPrefix: '10.30.0.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Azure Virtual Network Manager
resource networkManager 'Microsoft.Network/networkManagers@2023-09-01' = {
  name: resourceNames.networkManager
  location: location
  tags: resourceTags
  properties: {
    description: 'Centralized network management for hybrid DNS'
    networkManagerScopes: {
      subscriptions: [subscription().subscriptionId]
    }
    networkManagerScopeAccesses: ['Connectivity']
  }
}

// Network Group for hub-spoke topology
resource networkGroup 'Microsoft.Network/networkManagers/networkGroups@2023-09-01' = {
  parent: networkManager
  name: resourceNames.networkGroup
  properties: {
    description: 'Network group for hub-spoke DNS topology'
  }
}

// Static members for network group
resource hubStaticMember 'Microsoft.Network/networkManagers/networkGroups/staticMembers@2023-09-01' = {
  parent: networkGroup
  name: 'hub-member'
  properties: {
    resourceId: hubVNet.id
  }
}

resource spoke1StaticMember 'Microsoft.Network/networkManagers/networkGroups/staticMembers@2023-09-01' = {
  parent: networkGroup
  name: 'spoke1-member'
  properties: {
    resourceId: spoke1VNet.id
  }
}

resource spoke2StaticMember 'Microsoft.Network/networkManagers/networkGroups/staticMembers@2023-09-01' = {
  parent: networkGroup
  name: 'spoke2-member'
  properties: {
    resourceId: spoke2VNet.id
  }
}

// Connectivity Configuration
resource connectivityConfig 'Microsoft.Network/networkManagers/connectivityConfigurations@2023-09-01' = {
  parent: networkManager
  name: resourceNames.connectivityConfig
  properties: {
    description: 'Hub-spoke connectivity for DNS resolution'
    connectivityTopology: 'HubAndSpoke'
    hubs: [
      {
        resourceId: hubVNet.id
        resourceType: 'Microsoft.Network/virtualNetworks'
      }
    ]
    appliesToGroups: [
      {
        networkGroupId: networkGroup.id
        useHubGateway: 'False'
        isGlobal: 'False'
        groupConnectivity: 'None'
      }
    ]
  }
}

// Private DNS Zone for Azure resources
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: resourceTags
  properties: {}
}

// Virtual network links for private DNS zone
resource hubVNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'hub-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVNet.id
    }
  }
}

resource spoke1VNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'spoke1-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: spoke1VNet.id
    }
  }
}

resource spoke2VNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'spoke2-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: spoke2VNet.id
    }
  }
}

// Test DNS records in private zone
resource testVmRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateDnsZone
  name: 'test-vm'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: '10.20.0.100'
      }
    ]
  }
}

resource appServerRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateDnsZone
  name: 'app-server'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: '10.30.0.50'
      }
    ]
  }
}

// DNS Private Resolver
resource dnsPrivateResolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: resourceNames.dnsResolver
  location: location
  tags: resourceTags
  properties: {
    virtualNetwork: {
      id: hubVNet.id
    }
  }
}

// Inbound endpoint for on-premises to Azure DNS queries
resource inboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  parent: dnsPrivateResolver
  name: 'inbound-endpoint'
  location: location
  properties: {
    ipConfigurations: [
      {
        subnet: {
          id: '${hubVNet.id}/subnets/${subnetNames.dnsInbound}'
        }
      }
    ]
  }
}

// Outbound endpoint for Azure to on-premises DNS queries
resource outboundEndpoint 'Microsoft.Network/dnsResolvers/outboundEndpoints@2022-07-01' = {
  parent: dnsPrivateResolver
  name: 'outbound-endpoint'
  location: location
  properties: {
    subnet: {
      id: '${hubVNet.id}/subnets/${subnetNames.dnsOutbound}'
    }
  }
}

// DNS Forwarding Ruleset for on-premises resolution
resource dnsForwardingRuleset 'Microsoft.Network/dnsForwardingRulesets@2022-07-01' = {
  name: resourceNames.forwardingRuleset
  location: location
  tags: resourceTags
  properties: {
    dnsResolverOutboundEndpoints: [
      {
        id: outboundEndpoint.id
      }
    ]
  }
}

// Forwarding rule for on-premises domain
resource forwardingRule 'Microsoft.Network/dnsForwardingRulesets/forwardingRules@2022-07-01' = {
  parent: dnsForwardingRuleset
  name: resourceNames.forwardingRule
  properties: {
    domainName: '${onPremisesDomainName}.'
    forwardingRuleState: 'Enabled'
    targetDnsServers: [
      {
        ipAddress: onPremisesDnsServerIp
        port: 53
      }
    ]
  }
}

// Virtual network links for DNS forwarding ruleset
resource hubForwardingRulesetLink 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2022-07-01' = {
  parent: dnsForwardingRuleset
  name: 'hub-vnet-link'
  properties: {
    virtualNetwork: {
      id: hubVNet.id
    }
  }
}

resource spoke1ForwardingRulesetLink 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2022-07-01' = {
  parent: dnsForwardingRuleset
  name: 'spoke1-vnet-link'
  properties: {
    virtualNetwork: {
      id: spoke1VNet.id
    }
  }
}

resource spoke2ForwardingRulesetLink 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2022-07-01' = {
  parent: dnsForwardingRuleset
  name: 'spoke2-vnet-link'
  properties: {
    virtualNetwork: {
      id: spoke2VNet.id
    }
  }
}

// Storage account for private endpoint demonstration
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = if (createStorageDemo) {
  name: resourceNames.storageAccount
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Disabled'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
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
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// Private DNS zone for storage blob private endpoint
resource storageBlobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (createStorageDemo) {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
  tags: resourceTags
  properties: {}
}

// Virtual network links for storage private DNS zone
resource storageBlobHubVNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (createStorageDemo) {
  parent: storageBlobPrivateDnsZone
  name: 'hub-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVNet.id
    }
  }
}

resource storageBlobSpoke1VNetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (createStorageDemo) {
  parent: storageBlobPrivateDnsZone
  name: 'spoke1-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: spoke1VNet.id
    }
  }
}

// Private endpoint for storage account
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = if (createStorageDemo) {
  name: resourceNames.privateEndpoint
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: '${spoke1VNet.id}/subnets/${subnetNames.default}'
    }
    privateLinkServiceConnections: [
      {
        name: 'storage-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: ['blob']
        }
      }
    ]
  }
}

// Private DNS zone group for automatic DNS registration
resource storagePrivateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = if (createStorageDemo) {
  parent: storagePrivateEndpoint
  name: 'storage-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: storageBlobPrivateDnsZone.id
        }
      }
    ]
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Hub virtual network resource ID')
output hubVNetId string = hubVNet.id

@description('Hub virtual network name')
output hubVNetName string = hubVNet.name

@description('Spoke 1 virtual network resource ID')
output spoke1VNetId string = spoke1VNet.id

@description('Spoke 1 virtual network name')
output spoke1VNetName string = spoke1VNet.name

@description('Spoke 2 virtual network resource ID')
output spoke2VNetId string = spoke2VNet.id

@description('Spoke 2 virtual network name')
output spoke2VNetName string = spoke2VNet.name

@description('DNS Private Resolver resource ID')
output dnsPrivateResolverId string = dnsPrivateResolver.id

@description('DNS Private Resolver name')
output dnsPrivateResolverName string = dnsPrivateResolver.name

@description('Inbound endpoint IP address for on-premises DNS configuration')
output inboundEndpointIp string = inboundEndpoint.properties.ipConfigurations[0].privateIpAddress

@description('Outbound endpoint IP address')
output outboundEndpointIp string = outboundEndpoint.properties.ipConfigurations[0].privateIpAddress

@description('Virtual Network Manager resource ID')
output networkManagerId string = networkManager.id

@description('Virtual Network Manager name')
output networkManagerName string = networkManager.name

@description('Private DNS zone name for Azure resources')
output privateDnsZoneName string = privateDnsZone.name

@description('DNS forwarding ruleset resource ID')
output dnsForwardingRulesetId string = dnsForwardingRuleset.id

@description('DNS forwarding ruleset name')
output dnsForwardingRulesetName string = dnsForwardingRuleset.name

@description('Storage account name (if created)')
output storageAccountName string = createStorageDemo ? storageAccount.name : ''

@description('Storage account resource ID (if created)')
output storageAccountId string = createStorageDemo ? storageAccount.id : ''

@description('Private endpoint resource ID (if created)')
output privateEndpointId string = createStorageDemo ? storagePrivateEndpoint.id : ''

@description('Connectivity configuration deployment command')
output connectivityDeploymentCommand string = 'az network manager post-commit --resource-group ${resourceGroup().name} --network-manager-name ${networkManager.name} --commit-type "Connectivity" --configuration-ids ${connectivityConfig.id} --target-locations ${location}'

@description('Next steps for completing the setup')
output nextSteps array = [
  'Deploy the connectivity configuration using the provided Azure CLI command'
  'Configure your on-premises DNS server to forward ${privateDnsZoneName} queries to ${inboundEndpoint.properties.ipConfigurations[0].privateIpAddress}'
  'Test DNS resolution from Azure VMs to on-premises resources'
  'Test DNS resolution from on-premises to Azure private resources'
  'Monitor DNS query patterns using Azure Monitor'
]