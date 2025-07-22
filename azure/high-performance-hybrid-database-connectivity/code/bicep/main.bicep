// ===================================================================================================
// Azure Bicep Template: Secure Hybrid Database Connectivity
// Description: Establishes secure hybrid database connectivity using Azure ExpressRoute and Application Gateway
// Author: Generated from Azure Recipe
// Version: 1.0
// ===================================================================================================

targetScope = 'resourceGroup'

// ===================================================================================================
// PARAMETERS
// ===================================================================================================

@description('The primary location for resources')
param location string = resourceGroup().location

@description('Environment name for resource naming (dev, test, prod)')
@maxLength(8)
param environmentName string = 'prod'

@description('Project name prefix for resource naming')
@maxLength(10)
param projectName string = 'hybriddb'

@description('The address space for the hub virtual network')
param hubVnetAddressSpace string = '10.1.0.0/16'

@description('The address space for the Gateway subnet (must be /27 or larger)')
param gatewaySubnetAddressSpace string = '10.1.1.0/27'

@description('The address space for the Application Gateway subnet')
param applicationGatewaySubnetAddressSpace string = '10.1.2.0/24'

@description('The address space for the Database subnet')
param databaseSubnetAddressSpace string = '10.1.3.0/24'

@description('The address space for the Management subnet')
param managementSubnetAddressSpace string = '10.1.4.0/24'

@description('Administrator username for PostgreSQL server')
param postgresAdminUsername string = 'dbadmin'

@description('Administrator password for PostgreSQL server')
@secure()
param postgresAdminPassword string

@description('PostgreSQL server SKU name')
@allowed([
  'Standard_B1ms'
  'Standard_B2s'
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
])
param postgresSku string = 'Standard_D2s_v3'

@description('PostgreSQL server storage size in GB')
@minValue(32)
@maxValue(16384)
param postgresStorageSize int = 128

@description('Application Gateway SKU name')
@allowed([
  'Standard_v2'
  'WAF_v2'
])
param applicationGatewaySku string = 'WAF_v2'

@description('Application Gateway capacity (number of instances)')
@minValue(1)
@maxValue(10)
param applicationGatewayCapacity int = 2

@description('ExpressRoute Gateway SKU')
@allowed([
  'Standard'
  'HighPerformance'
  'UltraPerformance'
])
param expressRouteGatewaySku string = 'Standard'

@description('ExpressRoute Circuit Resource ID (existing circuit)')
param expressRouteCircuitId string = ''

@description('Enable Application Gateway autoscaling')
param enableAutoscaling bool = true

@description('Minimum autoscale capacity for Application Gateway')
@minValue(1)
@maxValue(10)
param minCapacity int = 1

@description('Maximum autoscale capacity for Application Gateway')
@minValue(2)
@maxValue(100)
param maxCapacity int = 10

@description('Resource tags to apply to all resources')
param resourceTags object = {
  Environment: environmentName
  Project: projectName
  Purpose: 'Hybrid Database Connectivity'
  Architecture: 'ExpressRoute + Application Gateway + PostgreSQL'
}

// ===================================================================================================
// VARIABLES
// ===================================================================================================

var namingPrefix = '${projectName}-${environmentName}'
var hubVnetName = '${namingPrefix}-vnet-hub'
var applicationGatewayName = '${namingPrefix}-appgw'
var postgresServerName = '${namingPrefix}-postgres-${uniqueString(resourceGroup().id)}'
var expressRouteGatewayName = '${namingPrefix}-ergw'
var privateDnsZoneName = '${postgresServerName}.private.postgres.database.azure.com'

// NSG Names
var gatewayNsgName = '${namingPrefix}-nsg-gateway'
var applicationGatewayNsgName = '${namingPrefix}-nsg-appgw'
var databaseNsgName = '${namingPrefix}-nsg-database'
var managementNsgName = '${namingPrefix}-nsg-management'

// Route Table Names
var databaseRouteTableName = '${namingPrefix}-rt-database'

// Public IP Names
var expressRouteGatewayPipName = '${namingPrefix}-pip-ergw'
var applicationGatewayPipName = '${namingPrefix}-pip-appgw'

// WAF Policy Name
var wafPolicyName = '${namingPrefix}-waf-policy'

// ===================================================================================================
// NETWORK SECURITY GROUPS
// ===================================================================================================

// Gateway Subnet NSG
resource gatewayNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: gatewayNsgName
  location: location
  tags: resourceTags
  properties: {
    securityRules: [
      {
        name: 'AllowGatewayManager'
        properties: {
          description: 'Allow Azure Gateway Manager'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          description: 'Allow Azure Load Balancer'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Application Gateway Subnet NSG
resource applicationGatewayNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: applicationGatewayNsgName
  location: location
  tags: resourceTags
  properties: {
    securityRules: [
      {
        name: 'AllowHTTPS'
        properties: {
          description: 'Allow HTTPS traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHTTP'
        properties: {
          description: 'Allow HTTP traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowGatewayManager'
        properties: {
          description: 'Allow Azure Gateway Manager'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          description: 'Allow Azure Load Balancer'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 130
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Database Subnet NSG
resource databaseNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: databaseNsgName
  location: location
  tags: resourceTags
  properties: {
    securityRules: [
      {
        name: 'AllowApplicationGatewayToPostgreSQL'
        properties: {
          description: 'Allow Application Gateway to PostgreSQL'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5432'
          sourceAddressPrefix: applicationGatewaySubnetAddressSpace
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowExpressRouteToPostgreSQL'
        properties: {
          description: 'Allow ExpressRoute traffic to PostgreSQL'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5432'
          sourceAddressPrefix: '10.0.0.0/8'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowManagementSubnet'
        properties: {
          description: 'Allow management subnet access'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5432'
          sourceAddressPrefix: managementSubnetAddressSpace
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllOther'
        properties: {
          description: 'Deny all other traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4000
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Management Subnet NSG
resource managementNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: managementNsgName
  location: location
  tags: resourceTags
  properties: {
    securityRules: [
      {
        name: 'AllowBastionCommunication'
        properties: {
          description: 'Allow Bastion communication'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          description: 'Allow Azure Load Balancer'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ===================================================================================================
// ROUTE TABLES
// ===================================================================================================

// Route table for Database subnet
resource databaseRouteTable 'Microsoft.Network/routeTables@2023-09-01' = {
  name: databaseRouteTableName
  location: location
  tags: resourceTags
  properties: {
    routes: [
      {
        name: 'RouteToOnPremises'
        properties: {
          addressPrefix: '10.0.0.0/8'
          nextHopType: 'VnetLocal'
        }
      }
    ]
  }
}

// ===================================================================================================
// PUBLIC IP ADDRESSES
// ===================================================================================================

// Public IP for ExpressRoute Gateway
resource expressRouteGatewayPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: expressRouteGatewayPipName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
  }
}

// Public IP for Application Gateway
resource applicationGatewayPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: applicationGatewayPipName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    publicIPAddressVersion: 'IPv4'
  }
}

// ===================================================================================================
// VIRTUAL NETWORK AND SUBNETS
// ===================================================================================================

// Hub Virtual Network
resource hubVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: hubVnetName
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubVnetAddressSpace
      ]
    }
    subnets: [
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: gatewaySubnetAddressSpace
          networkSecurityGroup: {
            id: gatewayNsg.id
          }
        }
      }
      {
        name: 'ApplicationGatewaySubnet'
        properties: {
          addressPrefix: applicationGatewaySubnetAddressSpace
          networkSecurityGroup: {
            id: applicationGatewayNsg.id
          }
        }
      }
      {
        name: 'DatabaseSubnet'
        properties: {
          addressPrefix: databaseSubnetAddressSpace
          networkSecurityGroup: {
            id: databaseNsg.id
          }
          routeTable: {
            id: databaseRouteTable.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
          delegations: [
            {
              name: 'dlg-PostgreSQL'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
      {
        name: 'ManagementSubnet'
        properties: {
          addressPrefix: managementSubnetAddressSpace
          networkSecurityGroup: {
            id: managementNsg.id
          }
        }
      }
    ]
  }
}

// ===================================================================================================
// PRIVATE DNS ZONE
// ===================================================================================================

// Private DNS Zone for PostgreSQL
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: resourceTags
}

// Link Private DNS Zone to Virtual Network
resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${hubVnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: hubVnet.id
    }
  }
}

// ===================================================================================================
// POSTGRESQL FLEXIBLE SERVER
// ===================================================================================================

// PostgreSQL Flexible Server
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: postgresServerName
  location: location
  tags: resourceTags
  sku: {
    name: postgresSku
    tier: 'GeneralPurpose'
  }
  properties: {
    administratorLogin: postgresAdminUsername
    administratorLoginPassword: postgresAdminPassword
    version: '14'
    storage: {
      storageSizeGB: postgresStorageSize
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Enabled'
    }
    highAvailability: {
      mode: 'ZoneRedundant'
    }
    network: {
      delegatedSubnetResourceId: '${hubVnet.id}/subnets/DatabaseSubnet'
      privateDnsZoneResourceId: privateDnsZone.id
    }
  }
  dependsOn: [
    privateDnsZoneLink
  ]
}

// Configure PostgreSQL parameters for optimal performance
resource postgresConfiguration1 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-06-01-preview' = {
  parent: postgresServer
  name: 'max_connections'
  properties: {
    value: '200'
    source: 'user-override'
  }
}

resource postgresConfiguration2 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-06-01-preview' = {
  parent: postgresServer
  name: 'shared_preload_libraries'
  properties: {
    value: 'pg_stat_statements'
    source: 'user-override'
  }
}

// ===================================================================================================
// WEB APPLICATION FIREWALL POLICY
// ===================================================================================================

// WAF Policy for Application Gateway
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-09-01' = {
  name: wafPolicyName
  location: location
  tags: resourceTags
  properties: {
    policySettings: {
      mode: 'Prevention'
      state: 'Enabled'
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
      ]
    }
  }
}

// ===================================================================================================
// APPLICATION GATEWAY
// ===================================================================================================

// Application Gateway
resource applicationGateway 'Microsoft.Network/applicationGateways@2023-09-01' = {
  name: applicationGatewayName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: applicationGatewaySku
      tier: applicationGatewaySku == 'WAF_v2' ? 'WAF_v2' : 'Standard_v2'
      capacity: enableAutoscaling ? null : applicationGatewayCapacity
    }
    autoscaleConfiguration: enableAutoscaling ? {
      minCapacity: minCapacity
      maxCapacity: maxCapacity
    } : null
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: '${hubVnet.id}/subnets/ApplicationGatewaySubnet'
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          publicIPAddress: {
            id: applicationGatewayPip.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
      {
        name: 'port_443'
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'PostgreSQLBackendPool'
        properties: {
          backendAddresses: [
            {
              fqdn: postgresServer.properties.fullyQualifiedDomainName
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'PostgreSQLHttpSettings'
        properties: {
          port: 5432
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 20
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', applicationGatewayName, 'PostgreSQLHealthProbe')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'PostgreSQLListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', applicationGatewayName, 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', applicationGatewayName, 'port_80')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'PostgreSQLRoutingRule'
        properties: {
          ruleType: 'Basic'
          priority: 1000
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', applicationGatewayName, 'PostgreSQLListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', applicationGatewayName, 'PostgreSQLBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', applicationGatewayName, 'PostgreSQLHttpSettings')
          }
        }
      }
    ]
    probes: [
      {
        name: 'PostgreSQLHealthProbe'
        properties: {
          protocol: 'Http'
          path: '/'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
        }
      }
    ]
    firewallPolicy: applicationGatewaySku == 'WAF_v2' ? {
      id: wafPolicy.id
    } : null
    sslPolicy: {
      policyType: 'Custom'
      cipherSuites: [
        'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384'
        'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256'
      ]
      minProtocolVersion: 'TLSv1_2'
    }
  }
}

// ===================================================================================================
// EXPRESSROUTE GATEWAY
// ===================================================================================================

// ExpressRoute Gateway
resource expressRouteGateway 'Microsoft.Network/virtualNetworkGateways@2023-09-01' = {
  name: expressRouteGatewayName
  location: location
  tags: resourceTags
  properties: {
    ipConfigurations: [
      {
        name: 'vnetGatewayConfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${hubVnet.id}/subnets/GatewaySubnet'
          }
          publicIPAddress: {
            id: expressRouteGatewayPip.id
          }
        }
      }
    ]
    gatewayType: 'ExpressRoute'
    sku: {
      name: expressRouteGatewaySku
      tier: expressRouteGatewaySku
    }
    vpnType: 'RouteBased'
    enableBgp: true
  }
}

// ExpressRoute Connection (conditional - only if circuit ID is provided)
resource expressRouteConnection 'Microsoft.Network/connections@2023-09-01' = if (!empty(expressRouteCircuitId)) {
  name: '${expressRouteGatewayName}-connection'
  location: location
  tags: resourceTags
  properties: {
    virtualNetworkGateway1: {
      id: expressRouteGateway.id
    }
    connectionType: 'ExpressRoute'
    peer: {
      id: expressRouteCircuitId
    }
  }
}

// ===================================================================================================
// OUTPUTS
// ===================================================================================================

@description('The resource ID of the hub virtual network')
output hubVirtualNetworkId string = hubVnet.id

@description('The resource ID of the ExpressRoute Gateway')
output expressRouteGatewayId string = expressRouteGateway.id

@description('The resource ID of the Application Gateway')
output applicationGatewayId string = applicationGateway.id

@description('The resource ID of the PostgreSQL server')
output postgresServerId string = postgresServer.id

@description('The fully qualified domain name of the PostgreSQL server')
output postgresServerFqdn string = postgresServer.properties.fullyQualifiedDomainName

@description('The public IP address of the Application Gateway')
output applicationGatewayPublicIp string = applicationGatewayPip.properties.ipAddress

@description('The public IP address of the ExpressRoute Gateway')
output expressRouteGatewayPublicIp string = expressRouteGatewayPip.properties.ipAddress

@description('The resource ID of the private DNS zone')
output privateDnsZoneId string = privateDnsZone.id

@description('Connection string for PostgreSQL (without password)')
output postgresConnectionString string = 'Server=${postgresServer.properties.fullyQualifiedDomainName};Database=postgres;Port=5432;User Id=${postgresAdminUsername};Ssl Mode=Require;'

@description('Resource group name where resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('Tags applied to all resources')
output resourceTags object = resourceTags