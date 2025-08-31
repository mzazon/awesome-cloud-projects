// =====================================================================================
// Azure Virtual Network with Three-Tier Subnet Architecture
// =====================================================================================
// This template creates a Virtual Network with frontend, backend, and database subnets,
// along with Network Security Groups configured for a secure three-tier application architecture.
// 
// Resources created:
// - Virtual Network with three subnets
// - Network Security Groups for each tier
// - NSG associations with subnets
// =====================================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment designation for resource naming')
@allowed([
  'dev'
  'test'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Project name for resource naming')
@minLength(2)
@maxLength(10)
param projectName string

@description('Virtual Network address space in CIDR notation')
param vnetAddressSpace string = '10.0.0.0/16'

@description('Frontend subnet address prefix')
param frontendSubnetPrefix string = '10.0.1.0/24'

@description('Backend subnet address prefix')
param backendSubnetPrefix string = '10.0.2.0/24'

@description('Database subnet address prefix')
param databaseSubnetPrefix string = '10.0.3.0/24'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: projectName
  Purpose: 'basic-network-recipe'
  CostCenter: 'IT'
  Owner: 'Network-Team'
}

// =====================================================================================
// Variables
// =====================================================================================

var uniqueSuffix = uniqueString(resourceGroup().id, deployment().name)
var vnetName = 'vnet-${projectName}-${environment}-${uniqueSuffix}'
var frontendSubnetName = 'subnet-frontend'
var backendSubnetName = 'subnet-backend'
var databaseSubnetName = 'subnet-database'

// Network Security Group names
var frontendNsgName = 'nsg-${frontendSubnetName}-${environment}'
var backendNsgName = 'nsg-${backendSubnetName}-${environment}'
var databaseNsgName = 'nsg-${databaseSubnetName}-${environment}'

// =====================================================================================
// Network Security Groups
// =====================================================================================

// Frontend NSG - Allows HTTP traffic from internet
resource frontendNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: frontendNsgName
  location: location
  tags: union(tags, {
    Tier: 'Frontend'
    Purpose: 'Web-facing security rules'
  })
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-Inbound'
        properties: {
          description: 'Allow HTTP traffic from internet to frontend tier'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-HTTPS-Inbound'
        properties: {
          description: 'Allow HTTPS traffic from internet to frontend tier'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1001
          direction: 'Inbound'
        }
      }
      {
        name: 'Deny-All-Other-Inbound'
        properties: {
          description: 'Deny all other inbound traffic'
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

// Backend NSG - Allows traffic only from frontend subnet
resource backendNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: backendNsgName
  location: location
  tags: union(tags, {
    Tier: 'Backend'
    Purpose: 'Application tier security rules'
  })
  properties: {
    securityRules: [
      {
        name: 'Allow-From-Frontend-Subnet'
        properties: {
          description: 'Allow application traffic from frontend subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8080'
          sourceAddressPrefix: frontendSubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-Management-SSH'
        properties: {
          description: 'Allow SSH for management (restrict source as needed)'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: frontendSubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1100
          direction: 'Inbound'
        }
      }
      {
        name: 'Deny-All-Other-Inbound'
        properties: {
          description: 'Deny all other inbound traffic'
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

// Database NSG - Allows traffic only from backend subnet
resource databaseNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: databaseNsgName
  location: location
  tags: union(tags, {
    Tier: 'Database'
    Purpose: 'Data tier security rules'
  })
  properties: {
    securityRules: [
      {
        name: 'Allow-PostgreSQL-From-Backend'
        properties: {
          description: 'Allow PostgreSQL traffic from backend subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5432'
          sourceAddressPrefix: backendSubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-MySQL-From-Backend'
        properties: {
          description: 'Allow MySQL traffic from backend subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3306'
          sourceAddressPrefix: backendSubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1001
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-MSSQL-From-Backend'
        properties: {
          description: 'Allow SQL Server traffic from backend subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: backendSubnetPrefix
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1002
          direction: 'Inbound'
        }
      }
      {
        name: 'Deny-All-Other-Inbound'
        properties: {
          description: 'Deny all other inbound traffic'
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

// =====================================================================================
// Virtual Network with Subnets
// =====================================================================================

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: union(tags, {
    Purpose: 'Three-tier network architecture'
  })
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: frontendSubnetName
        properties: {
          addressPrefix: frontendSubnetPrefix
          networkSecurityGroup: {
            id: frontendNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: backendSubnetName
        properties: {
          addressPrefix: backendSubnetPrefix
          networkSecurityGroup: {
            id: backendNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: databaseSubnetName
        properties: {
          addressPrefix: databaseSubnetPrefix
          networkSecurityGroup: {
            id: databaseNsg.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
    enableDdosProtection: false
    enableVmProtection: false
  }
}

// =====================================================================================
// Outputs
// =====================================================================================

@description('Virtual Network resource ID')
output vnetId string = virtualNetwork.id

@description('Virtual Network name')
output vnetName string = virtualNetwork.name

@description('Virtual Network address space')
output vnetAddressSpace string = vnetAddressSpace

@description('Frontend subnet resource ID')
output frontendSubnetId string = virtualNetwork.properties.subnets[0].id

@description('Frontend subnet name')
output frontendSubnetName string = frontendSubnetName

@description('Frontend subnet address prefix')
output frontendSubnetPrefix string = frontendSubnetPrefix

@description('Backend subnet resource ID')
output backendSubnetId string = virtualNetwork.properties.subnets[1].id

@description('Backend subnet name')
output backendSubnetName string = backendSubnetName

@description('Backend subnet address prefix')
output backendSubnetPrefix string = backendSubnetPrefix

@description('Database subnet resource ID')
output databaseSubnetId string = virtualNetwork.properties.subnets[2].id

@description('Database subnet name')
output databaseSubnetName string = databaseSubnetName

@description('Database subnet address prefix')
output databaseSubnetPrefix string = databaseSubnetPrefix

@description('Frontend NSG resource ID')
output frontendNsgId string = frontendNsg.id

@description('Frontend NSG name')
output frontendNsgName string = frontendNsg.name

@description('Backend NSG resource ID')
output backendNsgId string = backendNsg.id

@description('Backend NSG name')
output backendNsgName string = backendNsg.name

@description('Database NSG resource ID')
output databaseNsgId string = databaseNsg.id

@description('Database NSG name')
output databaseNsgName string = databaseNsg.name

@description('Resource group location')
output location string = location

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Deployment summary')
output deploymentSummary object = {
  vnetName: virtualNetwork.name
  vnetAddressSpace: vnetAddressSpace
  subnets: [
    {
      name: frontendSubnetName
      addressPrefix: frontendSubnetPrefix
      nsgName: frontendNsg.name
    }
    {
      name: backendSubnetName
      addressPrefix: backendSubnetPrefix
      nsgName: backendNsg.name
    }
    {
      name: databaseSubnetName
      addressPrefix: databaseSubnetPrefix
      nsgName: databaseNsg.name
    }
  ]
  location: location
  environment: environment
  projectName: projectName
}