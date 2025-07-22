// ===================================================================================================
// Azure Zero-Trust Remote Access with Azure Bastion and Azure Firewall Manager
// ===================================================================================================
// This Bicep template deploys a comprehensive zero-trust remote access solution using:
// - Azure Bastion (Standard SKU) for secure remote access
// - Azure Firewall Premium with Firewall Manager policies
// - Hub-spoke network architecture with VNet peering
// - Network Security Groups for defense-in-depth
// - Azure Policy for compliance enforcement
// - Comprehensive monitoring and logging
// ===================================================================================================

@description('The Azure region where all resources will be deployed')
param location string = resourceGroup().location

@description('Environment prefix for resource naming (e.g., prod, dev, test)')
@minLength(2)
@maxLength(10)
param environmentPrefix string = 'zt'

@description('Random suffix for unique resource names')
@minLength(3)
@maxLength(8)
param randomSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Enable Azure Policy for compliance enforcement')
param enableAzurePolicy bool = true

@description('Enable monitoring and diagnostic settings')
param enableMonitoring bool = true

@description('Azure Bastion SKU (Standard recommended for enterprise features)')
@allowed(['Basic', 'Standard'])
param bastionSku string = 'Standard'

@description('Azure Bastion scale units (2-50, only for Standard SKU)')
@minValue(2)
@maxValue(50)
param bastionScaleUnits int = 2

@description('Azure Firewall SKU tier (Premium recommended for advanced threat protection)')
@allowed(['Standard', 'Premium'])
param firewallTier string = 'Premium'

@description('Enable Azure Firewall threat intelligence')
@allowed(['Alert', 'Deny', 'Off'])
param threatIntelMode string = 'Alert'

@description('Tags to apply to all resources')
param tags object = {
  environment: environmentPrefix
  purpose: 'zero-trust-demo'
  solution: 'bastion-firewall-manager'
  'cost-center': 'security'
}

// ===================================================================================================
// VARIABLES
// ===================================================================================================

var resourceNames = {
  hubVNet: 'vnet-hub-${environmentPrefix}-${randomSuffix}'
  spoke1VNet: 'vnet-spoke-prod-${environmentPrefix}-${randomSuffix}'
  spoke2VNet: 'vnet-spoke-dev-${environmentPrefix}-${randomSuffix}'
  bastion: 'bastion-${environmentPrefix}-${randomSuffix}'
  bastionPip: 'pip-bastion-${environmentPrefix}-${randomSuffix}'
  firewall: 'fw-${environmentPrefix}-${randomSuffix}'
  firewallPip: 'pip-firewall-${environmentPrefix}-${randomSuffix}'
  firewallPolicy: 'fwpolicy-zerotrust-${environmentPrefix}-${randomSuffix}'
  nsgProd: 'nsg-prod-workload-${environmentPrefix}-${randomSuffix}'
  nsgDev: 'nsg-dev-workload-${environmentPrefix}-${randomSuffix}'
  routeTable: 'rt-spoke-workloads-${environmentPrefix}-${randomSuffix}'
  logAnalytics: 'law-zerotrust-${environmentPrefix}-${randomSuffix}'
}

var addressSpaces = {
  hub: '10.0.0.0/16'
  spoke1: '10.1.0.0/16'
  spoke2: '10.2.0.0/16'
}

var subnets = {
  bastionSubnet: '10.0.1.0/26'
  firewallSubnet: '10.0.2.0/24'
  prodWorkload: '10.1.1.0/24'
  devWorkload: '10.2.1.0/24'
}

// ===================================================================================================
// LOG ANALYTICS WORKSPACE
// ===================================================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableMonitoring) {
  name: resourceNames.logAnalytics
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
    workspaceCapping: {
      dailyQuotaGb: 10
    }
  }
}

// ===================================================================================================
// HUB VIRTUAL NETWORK
// ===================================================================================================

resource hubVNet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: resourceNames.hubVNet
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpaces.hub
      ]
    }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: subnets.bastionSubnet
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: subnets.firewallSubnet
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// ===================================================================================================
// SPOKE VIRTUAL NETWORKS
// ===================================================================================================

resource spoke1VNet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: resourceNames.spoke1VNet
  location: location
  tags: union(tags, { workload: 'production' })
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpaces.spoke1
      ]
    }
    subnets: [
      {
        name: 'snet-prod-workload'
        properties: {
          addressPrefix: subnets.prodWorkload
          networkSecurityGroup: {
            id: nsgProd.id
          }
          routeTable: {
            id: routeTable.id
          }
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource spoke2VNet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: resourceNames.spoke2VNet
  location: location
  tags: union(tags, { workload: 'development' })
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpaces.spoke2
      ]
    }
    subnets: [
      {
        name: 'snet-dev-workload'
        properties: {
          addressPrefix: subnets.devWorkload
          networkSecurityGroup: {
            id: nsgDev.id
          }
          routeTable: {
            id: routeTable.id
          }
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// ===================================================================================================
// VNET PEERING
// ===================================================================================================

resource hubToSpoke1Peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  name: 'hub-to-spoke1'
  parent: hubVNet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spoke1VNet.id
    }
  }
}

resource spoke1ToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  name: 'spoke1-to-hub'
  parent: spoke1VNet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: hubVNet.id
    }
  }
}

resource hubToSpoke2Peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  name: 'hub-to-spoke2'
  parent: hubVNet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spoke2VNet.id
    }
  }
}

resource spoke2ToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-11-01' = {
  name: 'spoke2-to-hub'
  parent: spoke2VNet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: hubVNet.id
    }
  }
}

// ===================================================================================================
// NETWORK SECURITY GROUPS
// ===================================================================================================

resource nsgProd 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: resourceNames.nsgProd
  location: location
  tags: union(tags, { workload: 'production' })
  properties: {
    securityRules: [
      {
        name: 'AllowBastionRDP'
        properties: {
          description: 'Allow RDP access from Azure Bastion subnet only'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: subnets.bastionSubnet
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowBastionSSH'
        properties: {
          description: 'Allow SSH access from Azure Bastion subnet only'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: subnets.bastionSubnet
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHTTPSInbound'
        properties: {
          description: 'Allow HTTPS traffic for web applications'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 200
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

resource nsgDev 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: resourceNames.nsgDev
  location: location
  tags: union(tags, { workload: 'development' })
  properties: {
    securityRules: [
      {
        name: 'AllowBastionRDP'
        properties: {
          description: 'Allow RDP access from Azure Bastion subnet only'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: subnets.bastionSubnet
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowBastionSSH'
        properties: {
          description: 'Allow SSH access from Azure Bastion subnet only'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: subnets.bastionSubnet
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowDevPortsInbound'
        properties: {
          description: 'Allow common development ports'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['80', '443', '8080', '3000']
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 200
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

// ===================================================================================================
// AZURE FIREWALL POLICY
// ===================================================================================================

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2023-11-01' = {
  name: resourceNames.firewallPolicy
  location: location
  tags: tags
  properties: {
    sku: {
      tier: firewallTier
    }
    threatIntelMode: threatIntelMode
    threatIntelWhitelist: {
      fqdns: []
      ipAddresses: []
    }
    intrusionDetection: firewallTier == 'Premium' ? {
      mode: 'Alert'
      configuration: {
        signatureOverrides: []
        bypassTrafficSettings: []
      }
    } : null
    dnsSettings: {
      servers: []
      enableProxy: true
    }
  }
}

resource firewallPolicyRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-11-01' = {
  name: 'rcg-zerotrust'
  parent: firewallPolicy
  properties: {
    priority: 100
    ruleCollections: [
      {
        name: 'app-rules-windows'
        priority: 100
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: [
          {
            name: 'AllowWindowsUpdate'
            ruleType: 'ApplicationRule'
            sourceAddresses: [
              addressSpaces.spoke1
              addressSpaces.spoke2
            ]
            targetFqdns: [
              '*.update.microsoft.com'
              '*.windowsupdate.com'
              '*.delivery.mp.microsoft.com'
              '*.microsoft.com'
            ]
            protocols: [
              {
                port: 80
                protocolType: 'Http'
              }
              {
                port: 443
                protocolType: 'Https'
              }
            ]
          }
          {
            name: 'AllowAzureServices'
            ruleType: 'ApplicationRule'
            sourceAddresses: [
              addressSpaces.spoke1
              addressSpaces.spoke2
            ]
            targetFqdns: [
              '*.azure.com'
              '*.microsoft.com'
              '*.microsoftonline.com'
              '*.azure.net'
            ]
            protocols: [
              {
                port: 443
                protocolType: 'Https'
              }
            ]
          }
        ]
      }
      {
        name: 'net-rules-azure'
        priority: 200
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: [
          {
            name: 'AllowAzureCloud'
            ruleType: 'NetworkRule'
            sourceAddresses: [
              addressSpaces.spoke1
              addressSpaces.spoke2
            ]
            destinationAddresses: [
              'AzureCloud.${location}'
            ]
            destinationPorts: [
              '443'
              '80'
            ]
            ipProtocols: [
              'TCP'
            ]
          }
          {
            name: 'AllowDNS'
            ruleType: 'NetworkRule'
            sourceAddresses: [
              addressSpaces.spoke1
              addressSpaces.spoke2
            ]
            destinationAddresses: [
              '1.1.1.1'
              '8.8.8.8'
            ]
            destinationPorts: [
              '53'
            ]
            ipProtocols: [
              'UDP'
            ]
          }
        ]
      }
    ]
  }
}

// ===================================================================================================
// PUBLIC IP ADDRESSES
// ===================================================================================================

resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: resourceNames.bastionPip
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
    ddosSettings: {
      ddosProtectionPlan: {
        id: ''
      }
      protectionMode: 'VirtualNetworkInherited'
    }
  }
}

resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: resourceNames.firewallPip
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
    ddosSettings: {
      ddosProtectionPlan: {
        id: ''
      }
      protectionMode: 'VirtualNetworkInherited'
    }
  }
  zones: [
    '1'
    '2'
    '3'
  ]
}

// ===================================================================================================
// AZURE FIREWALL
// ===================================================================================================

resource firewall 'Microsoft.Network/azureFirewalls@2023-11-01' = {
  name: resourceNames.firewall
  location: location
  tags: tags
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: firewallTier
    }
    threatIntelMode: threatIntelMode
    ipConfigurations: [
      {
        name: 'fw-ipconfig'
        properties: {
          publicIPAddress: {
            id: firewallPublicIp.id
          }
          subnet: {
            id: '${hubVNet.id}/subnets/AzureFirewallSubnet'
          }
        }
      }
    ]
    firewallPolicy: {
      id: firewallPolicy.id
    }
  }
}

// ===================================================================================================
// ROUTE TABLE
// ===================================================================================================

resource routeTable 'Microsoft.Network/routeTables@2023-11-01' = {
  name: resourceNames.routeTable
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'route-to-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewall.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

// ===================================================================================================
// AZURE BASTION
// ===================================================================================================

resource bastion 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: resourceNames.bastion
  location: location
  tags: tags
  sku: {
    name: bastionSku
  }
  properties: {
    scaleUnits: bastionSku == 'Standard' ? bastionScaleUnits : 2
    ipConfigurations: [
      {
        name: 'bastion-ipconfig'
        properties: {
          publicIPAddress: {
            id: bastionPublicIp.id
          }
          subnet: {
            id: '${hubVNet.id}/subnets/AzureBastionSubnet'
          }
        }
      }
    ]
    enableTunneling: bastionSku == 'Standard'
    enableIpConnect: bastionSku == 'Standard'
    enableShareableLink: bastionSku == 'Standard'
    enableSessionRecording: bastionSku == 'Standard'
  }
}

// ===================================================================================================
// AZURE POLICY DEFINITIONS AND ASSIGNMENTS
// ===================================================================================================

resource nsgPolicyDefinition 'Microsoft.Authorization/policyDefinitions@2023-04-01' = if (enableAzurePolicy) {
  name: 'require-nsg-on-subnet-${randomSuffix}'
  properties: {
    displayName: 'Require NSG on Subnets (Zero Trust)'
    description: 'Require NSG on all subnets except Azure Bastion and Azure Firewall subnets'
    policyType: 'Custom'
    mode: 'All'
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.Network/virtualNetworks/subnets'
          }
          {
            field: 'Microsoft.Network/virtualNetworks/subnets/networkSecurityGroup.id'
            exists: false
          }
          {
            field: 'name'
            notIn: [
              'AzureBastionSubnet'
              'AzureFirewallSubnet'
            ]
          }
        ]
      }
      then: {
        effect: 'deny'
      }
    }
  }
}

resource nsgPolicyAssignment 'Microsoft.Authorization/policyAssignments@2023-04-01' = if (enableAzurePolicy) {
  name: 'nsg-enforcement-${randomSuffix}'
  scope: resourceGroup()
  properties: {
    displayName: 'Enforce NSG on Subnets'
    description: 'Ensures all subnets have network security groups attached for zero trust security'
    policyDefinitionId: nsgPolicyDefinition.id
    enforcementMode: 'Default'
  }
}

// ===================================================================================================
// DIAGNOSTIC SETTINGS
// ===================================================================================================

resource bastionDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: 'diag-bastion'
  scope: bastion
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
    ]
  }
}

resource firewallDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: 'diag-firewall'
  scope: firewall
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
    ]
  }
}

// ===================================================================================================
// OUTPUTS
// ===================================================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Hub virtual network name and resource ID')
output hubVNet object = {
  name: hubVNet.name
  id: hubVNet.id
  addressSpace: hubVNet.properties.addressSpace.addressPrefixes[0]
}

@description('Production spoke virtual network name and resource ID')
output spoke1VNet object = {
  name: spoke1VNet.name
  id: spoke1VNet.id
  addressSpace: spoke1VNet.properties.addressSpace.addressPrefixes[0]
}

@description('Development spoke virtual network name and resource ID')
output spoke2VNet object = {
  name: spoke2VNet.name
  id: spoke2VNet.id
  addressSpace: spoke2VNet.properties.addressSpace.addressPrefixes[0]
}

@description('Azure Bastion host information')
output bastion object = {
  name: bastion.name
  id: bastion.id
  publicIpAddress: bastionPublicIp.properties.ipAddress
  sku: bastion.sku.name
  scaleUnits: bastion.properties.scaleUnits
}

@description('Azure Firewall information')
output firewall object = {
  name: firewall.name
  id: firewall.id
  publicIpAddress: firewallPublicIp.properties.ipAddress
  privateIpAddress: firewall.properties.ipConfigurations[0].properties.privateIPAddress
  tier: firewall.properties.sku.tier
}

@description('Firewall policy information')
output firewallPolicy object = {
  name: firewallPolicy.name
  id: firewallPolicy.id
  tier: firewallPolicy.properties.sku.tier
}

@description('Network security groups information')
output networkSecurityGroups object = {
  production: {
    name: nsgProd.name
    id: nsgProd.id
  }
  development: {
    name: nsgDev.name
    id: nsgDev.id
  }
}

@description('Log Analytics workspace information')
output logAnalyticsWorkspace object = enableMonitoring ? {
  name: logAnalyticsWorkspace.name
  id: logAnalyticsWorkspace.id
  customerId: logAnalyticsWorkspace.properties.customerId
} : {}

@description('Azure Policy information')
output azurePolicy object = enableAzurePolicy ? {
  definition: {
    name: nsgPolicyDefinition.name
    id: nsgPolicyDefinition.id
  }
  assignment: {
    name: nsgPolicyAssignment.name
    id: nsgPolicyAssignment.id
  }
} : {}

@description('Deployment summary with key connection information')
output deploymentSummary object = {
  bastionUrl: 'https://portal.azure.com/#@/resource${bastion.id}/overview'
  firewallManagerUrl: 'https://portal.azure.com/#blade/Microsoft_Azure_Network/NetworkWatcherMenuBlade/firewallManager'
  logAnalyticsUrl: enableMonitoring ? 'https://portal.azure.com/#@/resource${logAnalyticsWorkspace.id}/overview' : ''
  bastionPublicIp: bastionPublicIp.properties.ipAddress
  firewallPublicIp: firewallPublicIp.properties.ipAddress
  firewallPrivateIp: firewall.properties.ipConfigurations[0].properties.privateIPAddress
}