// ==============================================================================
// Azure Advanced Network Segmentation with Service Mesh and DNS Private Zones
// ==============================================================================
// This template deploys a comprehensive network segmentation solution using:
// - Azure Kubernetes Service (AKS) with Istio service mesh
// - Azure DNS Private Zones for secure service discovery
// - Azure Application Gateway with WAF for secure ingress
// - Azure Monitor for comprehensive observability
// ==============================================================================

targetScope = 'resourceGroup'

// ==============================================================================
// PARAMETERS
// ==============================================================================

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name prefix for all resources')
param namePrefix string = 'advnet'

@description('AKS cluster name')
param aksClusterName string = '${namePrefix}-aks-${environment}'

@description('AKS node count')
@minValue(2)
@maxValue(100)
param aksNodeCount int = 3

@description('AKS node VM size')
@allowed([
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
  'Standard_D16s_v3'
])
param aksNodeVmSize string = 'Standard_D4s_v3'

@description('Kubernetes version')
param kubernetesVersion string = '1.28.0'

@description('Enable AKS cluster autoscaler')
param enableAutoscaler bool = true

@description('Minimum node count for autoscaler')
@minValue(1)
@maxValue(10)
param autoscalerMinCount int = 2

@description('Maximum node count for autoscaler')
@minValue(3)
@maxValue(100)
param autoscalerMaxCount int = 10

@description('DNS zone name for private DNS')
param dnsZoneName string = 'company.internal'

@description('Application Gateway name')
param applicationGatewayName string = '${namePrefix}-agw-${environment}'

@description('Application Gateway SKU')
@allowed(['Standard_v2', 'WAF_v2'])
param applicationGatewaySku string = 'WAF_v2'

@description('Application Gateway capacity')
@minValue(1)
@maxValue(10)
param applicationGatewayCapacity int = 2

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string = '${namePrefix}-law-${environment}'

@description('Log Analytics workspace SKU')
@allowed(['PerGB2018', 'PerNode', 'Premium', 'Standard', 'Standalone'])
param logAnalyticsWorkspaceSku string = 'PerGB2018'

@description('Virtual network name')
param virtualNetworkName string = '${namePrefix}-vnet-${environment}'

@description('Virtual network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('AKS subnet address prefix')
param aksSubnetAddressPrefix string = '10.0.1.0/24'

@description('Application Gateway subnet address prefix')
param appGatewaySubnetAddressPrefix string = '10.0.2.0/24'

@description('Private endpoints subnet address prefix')
param privateEndpointsSubnetAddressPrefix string = '10.0.3.0/24'

@description('Enable Azure Monitor for containers')
param enableContainerInsights bool = true

@description('Enable Istio service mesh')
param enableIstioServiceMesh bool = true

@description('Enable WAF on Application Gateway')
param enableWaf bool = true

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: 'AdvancedNetworkSegmentation'
  ManagedBy: 'Bicep'
}

// ==============================================================================
// VARIABLES
// ==============================================================================

var uniqueSuffix = uniqueString(resourceGroup().id)
var storageAccountName = '${namePrefix}st${uniqueSuffix}'
var publicIpName = '${applicationGatewayName}-pip'
var nsgAksName = '${aksClusterName}-nsg'
var nsgAppGatewayName = '${applicationGatewayName}-nsg'
var nsgPrivateEndpointsName = '${namePrefix}-pe-nsg-${environment}'

// Subnet names
var aksSubnetName = 'aks-subnet'
var appGatewaySubnetName = 'appgw-subnet'
var privateEndpointsSubnetName = 'private-endpoints-subnet'

// ==============================================================================
// RESOURCES
// ==============================================================================

// Network Security Groups
resource nsgAks 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: nsgAksName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowAKSInbound'
        properties: {
          description: 'Allow AKS control plane communication'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'AzureCloud'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowServiceMeshInbound'
        properties: {
          description: 'Allow Istio service mesh communication'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '15000-15999'
            '8080'
            '9090'
            '9091'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1100
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource nsgAppGateway 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: nsgAppGatewayName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowHttpInbound'
        properties: {
          description: 'Allow HTTP traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHttpsInbound'
        properties: {
          description: 'Allow HTTPS traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowGatewayManagerInbound'
        properties: {
          description: 'Allow Gateway Manager'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1200
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource nsgPrivateEndpoints 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: nsgPrivateEndpointsName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowVnetInbound'
        properties: {
          description: 'Allow VNet traffic to private endpoints'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Virtual Network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: aksSubnetName
        properties: {
          addressPrefix: aksSubnetAddressPrefix
          networkSecurityGroup: {
            id: nsgAks.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.ContainerRegistry'
            }
            {
              service: 'Microsoft.KeyVault'
            }
            {
              service: 'Microsoft.Storage'
            }
          ]
        }
      }
      {
        name: appGatewaySubnetName
        properties: {
          addressPrefix: appGatewaySubnetAddressPrefix
          networkSecurityGroup: {
            id: nsgAppGateway.id
          }
        }
      }
      {
        name: privateEndpointsSubnetName
        properties: {
          addressPrefix: privateEndpointsSubnetAddressPrefix
          networkSecurityGroup: {
            id: nsgPrivateEndpoints.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsWorkspaceSku
    }
    retentionInDays: 30
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

// Storage Account for diagnostics
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
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
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
  }
}

// Managed Identity for AKS
resource aksManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${aksClusterName}-identity'
  location: location
  tags: tags
}

// Role assignment for AKS managed identity
resource aksRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: virtualNetwork
  name: guid(virtualNetwork.id, aksManagedIdentity.id, 'Network Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7')
    principalId: aksManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// AKS Cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-10-01' = {
  name: aksClusterName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksManagedIdentity.id}': {}
    }
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    dnsPrefix: aksClusterName
    agentPoolProfiles: [
      {
        name: 'default'
        count: aksNodeCount
        vmSize: aksNodeVmSize
        osDiskSizeGB: 128
        osDiskType: 'Managed'
        vnetSubnetID: '${virtualNetwork.id}/subnets/${aksSubnetName}'
        maxPods: 30
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: enableAutoscaler
        minCount: enableAutoscaler ? autoscalerMinCount : null
        maxCount: enableAutoscaler ? autoscalerMaxCount : null
        enableNodePublicIP: false
        mode: 'System'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        enableEncryptionAtHost: false
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '10.100.0.0/16'
      dnsServiceIP: '10.100.0.10'
      loadBalancerSku: 'Standard'
      outboundType: 'loadBalancer'
    }
    addonProfiles: enableContainerInsights ? {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspace.id
        }
      }
    } : {}
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
    }
    disableLocalAccounts: false
    apiServerAccessProfile: {
      enablePrivateCluster: false
    }
    serviceMeshProfile: enableIstioServiceMesh ? {
      mode: 'Istio'
      istio: {
        components: {
          ingressGateways: [
            {
              mode: 'External'
              enabled: true
            }
          ]
        }
      }
    } : null
  }
  dependsOn: [
    aksRoleAssignment
  ]
}

// Public IP for Application Gateway
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
  }
}

// Application Gateway
resource applicationGateway 'Microsoft.Network/applicationGateways@2023-05-01' = {
  name: applicationGatewayName
  location: location
  tags: tags
  properties: {
    sku: {
      name: applicationGatewaySku
      tier: applicationGatewaySku
      capacity: applicationGatewayCapacity
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: '${virtualNetwork.id}/subnets/${appGatewaySubnetName}'
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIP'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'appGatewayFrontendPort80'
        properties: {
          port: 80
        }
      }
      {
        name: 'appGatewayFrontendPort443'
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'istio-backend-pool'
        properties: {
          backendAddresses: []
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'appGatewayBackendHttpSettings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: false
          requestTimeout: 20
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', applicationGatewayName, 'healthProbe')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'appGatewayHttpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', applicationGatewayName, 'appGatewayFrontendIP')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', applicationGatewayName, 'appGatewayFrontendPort80')
          }
          protocol: 'Http'
          requireServerNameIndication: false
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'appGatewayRoutingRule'
        properties: {
          ruleType: 'Basic'
          priority: 1000
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', applicationGatewayName, 'appGatewayHttpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', applicationGatewayName, 'istio-backend-pool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', applicationGatewayName, 'appGatewayBackendHttpSettings')
          }
        }
      }
    ]
    probes: [
      {
        name: 'healthProbe'
        properties: {
          protocol: 'Http'
          path: '/health'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: false
          minServers: 0
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
    webApplicationFirewallConfiguration: enableWaf ? {
      enabled: true
      firewallMode: 'Detection'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
      disabledRuleGroups: []
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    } : null
    enableHttp2: true
    autoscaleConfiguration: {
      minCapacity: 1
      maxCapacity: 10
    }
  }
}

// Private DNS Zone
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: dnsZoneName
  location: 'global'
  tags: tags
  properties: {}
}

// Link private DNS zone to virtual network
resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

// DNS A Records for services
resource frontendServiceRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateDnsZone
  name: 'frontend-service'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: '10.100.1.10'
      }
    ]
  }
}

resource backendServiceRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateDnsZone
  name: 'backend-service'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: '10.100.1.20'
      }
    ]
  }
}

resource databaseServiceRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: privateDnsZone
  name: 'database-service'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: '10.100.1.30'
      }
    ]
  }
}

// Diagnostic settings for AKS
resource aksDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableContainerInsights) {
  scope: aksCluster
  name: 'aks-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'kube-apiserver'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'kube-audit'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'kube-audit-admin'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'kube-controller-manager'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'kube-scheduler'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'cluster-autoscaler'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'guard'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Application Gateway diagnostic settings
resource appGatewayDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: applicationGateway
  name: 'appgw-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ApplicationGatewayAccessLog'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'ApplicationGatewayPerformanceLog'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'ApplicationGatewayFirewallLog'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('The resource ID of the AKS cluster')
output aksClusterResourceId string = aksCluster.id

@description('The name of the AKS cluster')
output aksClusterName string = aksCluster.name

@description('The FQDN of the AKS cluster')
output aksClusterFqdn string = aksCluster.properties.fqdn

@description('The API server address of the AKS cluster')
output aksClusterApiServerAddress string = aksCluster.properties.fqdn

@description('The resource ID of the virtual network')
output virtualNetworkResourceId string = virtualNetwork.id

@description('The name of the virtual network')
output virtualNetworkName string = virtualNetwork.name

@description('The resource ID of the Application Gateway')
output applicationGatewayResourceId string = applicationGateway.id

@description('The name of the Application Gateway')
output applicationGatewayName string = applicationGateway.name

@description('The public IP address of the Application Gateway')
output applicationGatewayPublicIpAddress string = publicIp.properties.ipAddress

@description('The resource ID of the private DNS zone')
output privateDnsZoneResourceId string = privateDnsZone.id

@description('The name of the private DNS zone')
output privateDnsZoneName string = privateDnsZone.name

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceResourceId string = logAnalyticsWorkspace.id

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The workspace ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('The resource ID of the storage account')
output storageAccountResourceId string = storageAccount.id

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the AKS managed identity')
output aksManagedIdentityResourceId string = aksManagedIdentity.id

@description('The client ID of the AKS managed identity')
output aksManagedIdentityClientId string = aksManagedIdentity.properties.clientId

@description('The principal ID of the AKS managed identity')
output aksManagedIdentityPrincipalId string = aksManagedIdentity.properties.principalId

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Resource group location')
output resourceGroupLocation string = resourceGroup().location

@description('Deployment environment')
output environment string = environment

@description('DNS zone name for service discovery')
output dnsZoneName string = dnsZoneName

@description('AKS subnet resource ID')
output aksSubnetResourceId string = '${virtualNetwork.id}/subnets/${aksSubnetName}'

@description('Application Gateway subnet resource ID')
output appGatewaySubnetResourceId string = '${virtualNetwork.id}/subnets/${appGatewaySubnetName}'

@description('Private endpoints subnet resource ID')
output privateEndpointsSubnetResourceId string = '${virtualNetwork.id}/subnets/${privateEndpointsSubnetName}'

@description('Service mesh configuration status')
output serviceMeshEnabled bool = enableIstioServiceMesh

@description('Container insights configuration status')
output containerInsightsEnabled bool = enableContainerInsights

@description('WAF configuration status')
output wafEnabled bool = enableWaf

@description('Tags applied to resources')
output appliedTags object = tags