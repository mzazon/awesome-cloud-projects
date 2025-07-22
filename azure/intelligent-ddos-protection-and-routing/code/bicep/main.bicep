// Azure Adaptive Network Security with DDoS Protection and Route Server
// This template deploys a comprehensive network security solution with:
// - Azure DDoS Protection Standard
// - Azure Route Server for dynamic BGP routing
// - Hub-and-spoke VNet architecture
// - Azure Firewall for traffic inspection
// - Comprehensive monitoring and alerting

@description('The location where all resources will be deployed')
param location string = resourceGroup().location

@description('A unique suffix to ensure resource names are globally unique')
param uniqueSuffix string = take(uniqueString(resourceGroup().id), 6)

@description('The address prefix for the hub virtual network')
param hubVNetAddressPrefix string = '10.0.0.0/16'

@description('The address prefix for the spoke virtual network')
param spokeVNetAddressPrefix string = '10.1.0.0/16'

@description('Enable DDoS Protection Standard (incurs monthly cost)')
param enableDdosProtection bool = true

@description('Enable Azure Firewall deployment')
param enableFirewall bool = true

@description('Log Analytics workspace retention in days')
param logRetentionDays int = 30

@description('Enable Network Watcher flow logs')
param enableFlowLogs bool = true

@description('Tags to be applied to all resources')
param tags object = {
  purpose: 'adaptive-network-security'
  environment: 'production'
  recipe: 'implementing-adaptive-network-security-with-azure-ddos-protection-and-azure-route-server'
}

// Variables for resource naming
var ddosProtectionPlanName = 'ddos-plan-${uniqueSuffix}'
var hubVNetName = 'vnet-hub-${uniqueSuffix}'
var spokeVNetName = 'vnet-spoke-${uniqueSuffix}'
var routeServerName = 'rs-adaptive-${uniqueSuffix}'
var firewallName = 'fw-adaptive-${uniqueSuffix}'
var logAnalyticsName = 'law-adaptive-${uniqueSuffix}'
var storageAccountName = 'stflowlogs${uniqueSuffix}'
var actionGroupName = 'ddos-alerts-${uniqueSuffix}'
var networkWatcherName = 'NetworkWatcher_${location}'

// DDoS Protection Plan
resource ddosProtectionPlan 'Microsoft.Network/ddosProtectionPlans@2023-09-01' = if (enableDdosProtection) {
  name: ddosProtectionPlanName
  location: location
  tags: union(tags, {
    tier: 'standard'
  })
  properties: {}
}

// Hub Virtual Network with DDoS Protection
resource hubVNet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: hubVNetName
  location: location
  tags: union(tags, {
    tier: 'production'
    networkType: 'hub'
  })
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubVNetAddressPrefix
      ]
    }
    ddosProtectionPlan: enableDdosProtection ? {
      id: ddosProtectionPlan.id
    } : null
    enableDdosProtection: enableDdosProtection
    subnets: [
      {
        name: 'RouteServerSubnet'
        properties: {
          addressPrefix: '10.0.1.0/27'
          delegations: []
          serviceEndpoints: []
        }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: '10.0.2.0/26'
          delegations: []
          serviceEndpoints: []
        }
      }
      {
        name: 'ManagementSubnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
          delegations: []
          serviceEndpoints: []
        }
      }
    ]
  }
}

// Spoke Virtual Network
resource spokeVNet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: spokeVNetName
  location: location
  tags: union(tags, {
    tier: 'application'
    networkType: 'spoke'
  })
  properties: {
    addressSpace: {
      addressPrefixes: [
        spokeVNetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'ApplicationSubnet'
        properties: {
          addressPrefix: '10.1.1.0/24'
          delegations: []
          serviceEndpoints: []
        }
      }
      {
        name: 'DatabaseSubnet'
        properties: {
          addressPrefix: '10.1.2.0/24'
          delegations: []
          serviceEndpoints: []
        }
      }
    ]
  }
}

// VNet Peering: Hub to Spoke
resource hubToSpokeVNetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: hubVNet
  name: 'hub-to-spoke'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spokeVNet.id
    }
  }
}

// VNet Peering: Spoke to Hub
resource spokeToHubVNetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: spokeVNet
  name: 'spoke-to-hub'
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

// Public IP for Route Server
resource routeServerPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'pip-${routeServerName}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// Azure Route Server
resource routeServer 'Microsoft.Network/virtualHubs@2023-09-01' = {
  name: routeServerName
  location: location
  tags: union(tags, {
    tier: 'production'
    purpose: 'dynamic-routing'
  })
  properties: {
    sku: 'Standard'
    allowBranchToBranchTraffic: true
    hubRoutingPreference: 'ExpressRoute'
    virtualNetworkConnections: []
  }
}

// Route Server IP Configuration
resource routeServerIpConfig 'Microsoft.Network/virtualHubs/ipConfigurations@2023-09-01' = {
  parent: routeServer
  name: 'ipconfig1'
  properties: {
    privateIPAllocationMethod: 'Dynamic'
    subnet: {
      id: '${hubVNet.id}/subnets/RouteServerSubnet'
    }
    publicIPAddress: {
      id: routeServerPublicIp.id
    }
  }
}

// Public IP for Azure Firewall
resource firewallPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = if (enableFirewall) {
  name: 'pip-${firewallName}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// Azure Firewall
resource firewall 'Microsoft.Network/azureFirewalls@2023-09-01' = if (enableFirewall) {
  name: firewallName
  location: location
  tags: union(tags, {
    tier: 'production'
    purpose: 'network-security'
  })
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    threatIntelMode: 'Alert'
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
    networkRuleCollections: [
      {
        name: 'adaptive-security-rules'
        properties: {
          priority: 100
          action: {
            type: 'Allow'
          }
          rules: [
            {
              name: 'allow-web-traffic'
              protocols: [
                'TCP'
              ]
              sourceAddresses: [
                spokeVNetAddressPrefix
              ]
              destinationAddresses: [
                '*'
              ]
              destinationPorts: [
                '80'
                '443'
              ]
            }
          ]
        }
      }
    ]
  }
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: union(tags, {
    tier: 'production'
    purpose: 'security-monitoring'
  })
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

// Storage Account for Flow Logs
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = if (enableFlowLogs) {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    accessTier: 'Cool'
    encryption: {
      services: {
        blob: {
          keyType: 'Account'
          enabled: true
        }
        file: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Network Watcher (if not already exists)
resource networkWatcher 'Microsoft.Network/networkWatchers@2023-09-01' = {
  name: networkWatcherName
  location: location
  tags: tags
  properties: {}
}

// Network Security Group for Spoke VNet
resource spokeNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-${spokeVNetName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowHTTPSInbound'
        properties: {
          description: 'Allow HTTPS inbound traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHTTPInbound'
        properties: {
          description: 'Allow HTTP inbound traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Flow Logs Configuration
resource flowLogs 'Microsoft.Network/networkWatchers/flowLogs@2023-09-01' = if (enableFlowLogs) {
  parent: networkWatcher
  name: 'flowlog-${uniqueSuffix}'
  location: location
  tags: tags
  properties: {
    targetResourceId: spokeNsg.id
    storageId: storageAccount.id
    enabled: true
    format: {
      type: 'JSON'
      version: 2
    }
    flowAnalyticsConfiguration: {
      networkWatcherFlowAnalyticsConfiguration: {
        enabled: true
        workspaceResourceId: logAnalyticsWorkspace.id
        trafficAnalyticsInterval: 10
      }
    }
    retentionPolicy: {
      days: 7
      enabled: true
    }
  }
}

// Action Group for DDoS Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'ddos-ag'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    armRoleReceivers: []
    azureFunctionReceivers: []
    logicAppReceivers: []
  }
}

// DDoS Attack Detection Alert
resource ddosAttackAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableDdosProtection) {
  name: 'DDoS-Attack-Alert'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when DDoS attack is detected'
    severity: 1
    enabled: true
    scopes: [
      ddosProtectionPlan.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'DDoSAttackCriteria'
          metricName: 'DDoSAttack'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// High Traffic Volume Alert
resource highTrafficAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableDdosProtection) {
  name: 'High-Traffic-Volume-Alert'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when traffic volume exceeds threshold'
    severity: 2
    enabled: true
    scopes: [
      ddosProtectionPlan.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighTrafficCriteria'
          metricName: 'PacketsInboundTotal'
          operator: 'GreaterThan'
          threshold: 100000
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Outputs
@description('The resource ID of the DDoS Protection Plan')
output ddosProtectionPlanId string = enableDdosProtection ? ddosProtectionPlan.id : ''

@description('The resource ID of the hub virtual network')
output hubVNetId string = hubVNet.id

@description('The resource ID of the spoke virtual network')
output spokeVNetId string = spokeVNet.id

@description('The resource ID of the Azure Route Server')
output routeServerId string = routeServer.id

@description('The private IP address of the Azure Route Server')
output routeServerPrivateIp string = routeServerIpConfig.properties.privateIPAddress

@description('The resource ID of the Azure Firewall')
output firewallId string = enableFirewall ? firewall.id : ''

@description('The private IP address of the Azure Firewall')
output firewallPrivateIp string = enableFirewall ? firewall.properties.ipConfigurations[0].properties.privateIPAddress : ''

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The workspace ID of the Log Analytics workspace')
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('The resource ID of the storage account for flow logs')
output storageAccountId string = enableFlowLogs ? storageAccount.id : ''

@description('The resource ID of the action group for alerts')
output actionGroupId string = actionGroup.id

@description('The resource ID of the Network Security Group')
output spokeNsgId string = spokeNsg.id

@description('The hub virtual network address space')
output hubVNetAddressSpace string = hubVNetAddressPrefix

@description('The spoke virtual network address space')
output spokeVNetAddressSpace string = spokeVNetAddressPrefix