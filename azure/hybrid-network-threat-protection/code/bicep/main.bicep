// =============================================================================
// Azure Hybrid Network Security with Azure Firewall Premium and ExpressRoute
// =============================================================================
// This template deploys a comprehensive hybrid network security architecture
// with Azure Firewall Premium for advanced threat protection and ExpressRoute
// Gateway for private connectivity to on-premises networks.

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource naming')
param resourceSuffix string = uniqueString(resourceGroup().id, deployment().name)

@description('Environment tag for resource categorization')
@allowed(['dev', 'staging', 'production'])
param environment string = 'production'

@description('Hub virtual network address space')
param hubVNetAddressPrefix string = '10.0.0.0/16'

@description('Spoke virtual network address space')
param spokeVNetAddressPrefix string = '10.1.0.0/16'

@description('Azure Firewall subnet address space')
param azureFirewallSubnetPrefix string = '10.0.1.0/24'

@description('ExpressRoute Gateway subnet address space')
param gatewaySubnetPrefix string = '10.0.2.0/24'

@description('Workload subnet address space in spoke network')
param workloadSubnetPrefix string = '10.1.1.0/24'

@description('On-premises network address space for routing')
param onPremisesAddressPrefix string = '192.168.0.0/16'

@description('ExpressRoute Gateway SKU')
@allowed(['Standard', 'HighPerformance', 'UltraPerformance'])
param expressRouteGatewaySku string = 'Standard'

@description('Log Analytics workspace retention period in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Enable Azure Firewall Premium features')
param enableFirewallPremiumFeatures bool = true

@description('Threat intelligence mode for Azure Firewall')
@allowed(['Alert', 'Deny', 'Off'])
param threatIntelligenceMode string = 'Alert'

@description('IDPS mode for Azure Firewall Premium')
@allowed(['Alert', 'Deny', 'Off'])
param idpsMode string = 'Alert'

// =============================================================================
// Variables
// =============================================================================

var resourceNames = {
  hubVNet: 'vnet-hub-${resourceSuffix}'
  spokeVNet: 'vnet-spoke-${resourceSuffix}'
  azureFirewall: 'azfw-premium-${resourceSuffix}'
  firewallPolicy: 'azfw-policy-${resourceSuffix}'
  expressRouteGateway: 'ergw-${resourceSuffix}'
  logAnalyticsWorkspace: 'laws-firewall-${resourceSuffix}'
  firewallPublicIP: 'pip-azfw-${resourceSuffix}'
  gatewayPublicIP: 'pip-ergw-${resourceSuffix}'
  routeTable: 'rt-spoke-firewall-${resourceSuffix}'
}

var commonTags = {
  Environment: environment
  Purpose: 'hybrid-network-security'
  Solution: 'azure-firewall-premium-expressroute'
  CreatedBy: 'bicep-template'
  CreatedOn: utcNow('yyyy-MM-dd')
}

// =============================================================================
// Log Analytics Workspace
// =============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =============================================================================
// Hub Virtual Network
// =============================================================================

resource hubVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: resourceNames.hubVNet
  location: location
  tags: union(commonTags, {
    NetworkType: 'hub'
  })
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubVNetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: azureFirewallSubnetPrefix
          serviceEndpoints: []
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: gatewaySubnetPrefix
          serviceEndpoints: []
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
    enableDdosProtection: false
    enableVmProtection: false
  }
}

// =============================================================================
// Spoke Virtual Network
// =============================================================================

resource spokeVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: resourceNames.spokeVNet
  location: location
  tags: union(commonTags, {
    NetworkType: 'spoke'
  })
  properties: {
    addressSpace: {
      addressPrefixes: [
        spokeVNetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'WorkloadSubnet'
        properties: {
          addressPrefix: workloadSubnetPrefix
          serviceEndpoints: []
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
    enableDdosProtection: false
    enableVmProtection: false
  }
}

// =============================================================================
// Virtual Network Peering
// =============================================================================

resource hubToSpokeVNetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: hubVirtualNetwork
  name: 'hub-to-spoke'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: true
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spokeVirtualNetwork.id
    }
  }
}

resource spokeToHubVNetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: spokeVirtualNetwork
  name: 'spoke-to-hub'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: true
    remoteVirtualNetwork: {
      id: hubVirtualNetwork.id
    }
  }
  dependsOn: [
    expressRouteGateway // Ensure gateway exists before enabling useRemoteGateways
  ]
}

// =============================================================================
// Azure Firewall Public IP
// =============================================================================

resource firewallPublicIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: resourceNames.firewallPublicIP
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: toLower('azfw-${resourceSuffix}')
    }
    idleTimeoutInMinutes: 4
  }
}

// =============================================================================
// Azure Firewall Policy
// =============================================================================

resource firewallPolicy 'Microsoft.Network/firewallPolicies@2023-09-01' = {
  name: resourceNames.firewallPolicy
  location: location
  tags: commonTags
  properties: {
    sku: {
      tier: 'Premium'
    }
    threatIntelMode: threatIntelligenceMode
    threatIntelWhitelist: {
      fqdns: []
      ipAddresses: []
    }
    insights: {
      isEnabled: true
      retentionDays: logAnalyticsRetentionDays
      logAnalyticsResources: {
        defaultWorkspaceId: {
          id: logAnalyticsWorkspace.id
        }
      }
    }
    intrusionDetection: enableFirewallPremiumFeatures ? {
      mode: idpsMode
      configuration: {
        signatureOverrides: []
        bypassTrafficSettings: []
        privateRanges: [
          onPremisesAddressPrefix
          hubVNetAddressPrefix
          spokeVNetAddressPrefix
        ]
      }
    } : null
    dnsSettings: {
      servers: []
      enableProxy: true
    }
    explicitProxy: {
      enabled: false
    }
  }
}

// =============================================================================
// Azure Firewall Policy Rule Collection Groups
// =============================================================================

resource hybridNetworkRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-09-01' = {
  parent: firewallPolicy
  name: 'HybridNetworkRules'
  properties: {
    priority: 1000
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'OnPremToAzureNetworkRules'
        priority: 1100
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'AllowOnPremToSpoke'
            description: 'Allow on-premises traffic to spoke networks'
            ipProtocols: ['TCP', 'UDP']
            sourceAddresses: [onPremisesAddressPrefix]
            destinationAddresses: [spokeVNetAddressPrefix]
            destinationPorts: ['443', '80', '22', '3389']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowSpokeToOnPrem'
            description: 'Allow spoke network traffic to on-premises'
            ipProtocols: ['TCP', 'UDP']
            sourceAddresses: [spokeVNetAddressPrefix]
            destinationAddresses: [onPremisesAddressPrefix]
            destinationPorts: ['443', '80', '22', '3389', '53']
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'WebTrafficApplicationRules'
        priority: 1200
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'AllowWebTraffic'
            description: 'Allow web traffic with TLS inspection'
            sourceAddresses: [spokeVNetAddressPrefix, onPremisesAddressPrefix]
            targetFqdns: ['*.microsoft.com', '*.azure.com', '*.office.com', '*.windows.net']
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
              {
                protocolType: 'Http'
                port: 80
              }
            ]
            terminateTLS: enableFirewallPremiumFeatures
          }
          {
            ruleType: 'ApplicationRule'
            name: 'AllowAzureServices'
            description: 'Allow access to essential Azure services'
            sourceAddresses: [spokeVNetAddressPrefix, onPremisesAddressPrefix]
            targetFqdns: [
              '*.servicebus.windows.net'
              '*.vault.azure.net'
              '*.database.windows.net'
              '*.blob.core.windows.net'
              '*.table.core.windows.net'
              '*.queue.core.windows.net'
            ]
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            terminateTLS: enableFirewallPremiumFeatures
          }
        ]
      }
    ]
  }
}

// =============================================================================
// Azure Firewall
// =============================================================================

resource azureFirewall 'Microsoft.Network/azureFirewalls@2023-09-01' = {
  name: resourceNames.azureFirewall
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Premium'
    }
    ipConfigurations: [
      {
        name: 'firewallIPConfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', resourceNames.hubVNet, 'AzureFirewallSubnet')
          }
          publicIPAddress: {
            id: firewallPublicIP.id
          }
        }
      }
    ]
    networkRuleCollections: []
    applicationRuleCollections: []
    natRuleCollections: []
    threatIntelMode: threatIntelligenceMode
    firewallPolicy: {
      id: firewallPolicy.id
    }
    additionalProperties: {}
  }
  dependsOn: [
    hubVirtualNetwork
    hybridNetworkRuleCollectionGroup
  ]
}

// =============================================================================
// Azure Firewall Diagnostic Settings
// =============================================================================

resource firewallDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'firewall-diagnostics'
  scope: azureFirewall
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AzureFirewallApplicationRule'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
      {
        category: 'AzureFirewallNetworkRule'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
      {
        category: 'AzureFirewallDnsProxy'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
      {
        category: 'AZFWIdpsSignature'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
      {
        category: 'AZFWThreatIntel'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
  }
}

// =============================================================================
// ExpressRoute Gateway Public IP
// =============================================================================

resource gatewayPublicIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: resourceNames.gatewayPublicIP
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: toLower('ergw-${resourceSuffix}')
    }
    idleTimeoutInMinutes: 4
  }
}

// =============================================================================
// ExpressRoute Gateway
// =============================================================================

resource expressRouteGateway 'Microsoft.Network/virtualNetworkGateways@2023-09-01' = {
  name: resourceNames.expressRouteGateway
  location: location
  tags: commonTags
  properties: {
    ipConfigurations: [
      {
        name: 'gatewayIPConfig'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', resourceNames.hubVNet, 'GatewaySubnet')
          }
          publicIPAddress: {
            id: gatewayPublicIP.id
          }
        }
      }
    ]
    gatewayType: 'ExpressRoute'
    sku: {
      name: expressRouteGatewaySku
      tier: expressRouteGatewaySku
    }
    enableBgp: true
    activeActive: false
    enableDnsForwarding: false
  }
  dependsOn: [
    hubVirtualNetwork
  ]
}

// =============================================================================
// Route Table for Traffic Steering
// =============================================================================

resource spokeRouteTable 'Microsoft.Network/routeTables@2023-09-01' = {
  name: resourceNames.routeTable
  location: location
  tags: commonTags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'route-to-onprem'
        properties: {
          addressPrefix: onPremisesAddressPrefix
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: azureFirewall.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
      {
        name: 'route-default'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: azureFirewall.properties.ipConfigurations[0].properties.privateIPAddress
        }
      }
    ]
  }
}

// =============================================================================
// Route Table Association
// =============================================================================

resource workloadSubnetRouteTableAssociation 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: spokeVirtualNetwork
  name: 'WorkloadSubnet'
  properties: {
    addressPrefix: workloadSubnetPrefix
    serviceEndpoints: []
    delegations: []
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Disabled'
    routeTable: {
      id: spokeRouteTable.id
    }
  }
  dependsOn: [
    azureFirewall
  ]
}

// =============================================================================
// Outputs
// =============================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Location of deployed resources')
output location string = location

@description('Hub virtual network name')
output hubVirtualNetworkName string = hubVirtualNetwork.name

@description('Hub virtual network ID')
output hubVirtualNetworkId string = hubVirtualNetwork.id

@description('Spoke virtual network name')
output spokeVirtualNetworkName string = spokeVirtualNetwork.name

@description('Spoke virtual network ID')
output spokeVirtualNetworkId string = spokeVirtualNetwork.id

@description('Azure Firewall name')
output azureFirewallName string = azureFirewall.name

@description('Azure Firewall private IP address')
output azureFirewallPrivateIP string = azureFirewall.properties.ipConfigurations[0].properties.privateIPAddress

@description('Azure Firewall public IP address')
output azureFirewallPublicIP string = firewallPublicIP.properties.ipAddress

@description('Azure Firewall policy name')
output firewallPolicyName string = firewallPolicy.name

@description('ExpressRoute Gateway name')
output expressRouteGatewayName string = expressRouteGateway.name

@description('ExpressRoute Gateway ID')
output expressRouteGatewayId string = expressRouteGateway.id

@description('ExpressRoute Gateway public IP address')
output expressRouteGatewayPublicIP string = gatewayPublicIP.properties.ipAddress

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Route table name')
output routeTableName string = spokeRouteTable.name

@description('Route table ID')
output routeTableId string = spokeRouteTable.id

@description('Deployment summary')
output deploymentSummary object = {
  hubVNet: {
    name: hubVirtualNetwork.name
    addressSpace: hubVNetAddressPrefix
  }
  spokeVNet: {
    name: spokeVirtualNetwork.name
    addressSpace: spokeVNetAddressPrefix
  }
  azureFirewall: {
    name: azureFirewall.name
    privateIP: azureFirewall.properties.ipConfigurations[0].properties.privateIPAddress
    publicIP: firewallPublicIP.properties.ipAddress
    tier: 'Premium'
  }
  expressRouteGateway: {
    name: expressRouteGateway.name
    sku: expressRouteGatewaySku
    publicIP: gatewayPublicIP.properties.ipAddress
  }
  monitoring: {
    logAnalyticsWorkspace: logAnalyticsWorkspace.name
    retentionDays: logAnalyticsRetentionDays
  }
}

@description('Next steps for completing the deployment')
output nextSteps array = [
  'Connect your ExpressRoute circuit to the deployed gateway'
  'Configure custom DNS servers if required'
  'Deploy workload resources in the spoke virtual network'
  'Configure additional firewall rules as needed'
  'Set up Azure Monitor alerts for security events'
  'Review and tune IDPS signatures based on your environment'
]