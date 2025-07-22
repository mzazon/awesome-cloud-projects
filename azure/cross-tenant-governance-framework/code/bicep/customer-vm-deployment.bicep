// ==============================================================================
// Customer Virtual Machine Deployment with Automanage
// ==============================================================================
// This template deploys virtual machines in customer tenants with Azure
// Automanage integration for automated governance.
// ==============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Virtual network name')
param vnetName string

@description('Virtual network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet name')
param subnetName string = 'default'

@description('Subnet address prefix')
param subnetAddressPrefix string = '10.0.1.0/24'

@description('Virtual machine name prefix')
param vmNamePrefix string

@description('Number of virtual machines to deploy')
param vmCount int = 2

@description('Virtual machine size')
param vmSize string = 'Standard_B2s'

@description('OS image reference')
param osImageReference object = {
  publisher: 'MicrosoftWindowsServer'
  offer: 'WindowsServer'
  sku: '2019-datacenter-gensecond'
  version: 'latest'
}

@description('Administrator username')
param adminUsername string = 'azureuser'

@description('Administrator password')
@secure()
param adminPassword string

@description('MSP Automanage configuration profile resource ID')
param automanageProfileResourceId string

@description('MSP Log Analytics workspace resource ID')
param logAnalyticsWorkspaceResourceId string

@description('Enable automatic OS updates')
param enableAutomaticUpdates bool = true

@description('Time zone for the virtual machines')
param timeZone string = 'UTC'

@description('Tags to apply to all resources')
param tags object = {
  environment: 'production'
  managedBy: 'msp'
  automanage: 'enabled'
}

// ==============================================================================
// Variables
// ==============================================================================

var networkSecurityGroupName = '${vnetName}-nsg'
var publicIPPrefix = '${vmNamePrefix}-pip'
var nicPrefix = '${vmNamePrefix}-nic'

// ==============================================================================
// Network Security Group
// ==============================================================================

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: networkSecurityGroupName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowRDP'
        properties: {
          description: 'Allow RDP access'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowWinRM'
        properties: {
          description: 'Allow WinRM access'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5985'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1001
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ==============================================================================
// Virtual Network
// ==============================================================================

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
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
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
}

// ==============================================================================
// Public IP Addresses
// ==============================================================================

resource publicIPAddresses 'Microsoft.Network/publicIPAddresses@2023-09-01' = [for i in range(0, vmCount): {
  name: '${publicIPPrefix}-${i + 1}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${vmNamePrefix}-${i + 1}-${uniqueString(resourceGroup().id)}'
    }
  }
}]

// ==============================================================================
// Network Interfaces
// ==============================================================================

resource networkInterfaces 'Microsoft.Network/networkInterfaces@2023-09-01' = [for i in range(0, vmCount): {
  name: '${nicPrefix}-${i + 1}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddresses[i].id
          }
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
        }
      }
    ]
  }
}]

// ==============================================================================
// Virtual Machines
// ==============================================================================

resource virtualMachines 'Microsoft.Compute/virtualMachines@2023-09-01' = [for i in range(0, vmCount): {
  name: '${vmNamePrefix}-${i + 1}'
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: '${vmNamePrefix}-${i + 1}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: enableAutomaticUpdates
        timeZone: timeZone
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: osImageReference
      osDisk: {
        name: '${vmNamePrefix}-${i + 1}-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterfaces[i].id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}]

// ==============================================================================
// VM Extensions for Monitoring
// ==============================================================================

resource logAnalyticsExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for i in range(0, vmCount): {
  name: 'MicrosoftMonitoringAgent'
  parent: virtualMachines[i]
  location: location
  properties: {
    publisher: 'Microsoft.EnterpriseCloud.Monitoring'
    type: 'MicrosoftMonitoringAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    settings: {
      workspaceId: reference(logAnalyticsWorkspaceResourceId, '2023-09-01').customerId
    }
    protectedSettings: {
      workspaceKey: listKeys(logAnalyticsWorkspaceResourceId, '2023-09-01').primarySharedKey
    }
  }
}]

resource dependencyAgentExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for i in range(0, vmCount): {
  name: 'DependencyAgentWindows'
  parent: virtualMachines[i]
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitoring.DependencyAgent'
    type: 'DependencyAgentWindows'
    typeHandlerVersion: '9.5'
    autoUpgradeMinorVersion: true
  }
  dependsOn: [
    logAnalyticsExtension[i]
  ]
}]

// ==============================================================================
// Automanage Profile Assignments
// ==============================================================================

resource automanageAssignments 'Microsoft.Automanage/configurationProfileAssignments@2022-05-04' = [for i in range(0, vmCount): {
  name: 'default'
  scope: virtualMachines[i]
  properties: {
    configurationProfile: automanageProfileResourceId
  }
}]

// ==============================================================================
// Outputs
// ==============================================================================

@description('Array of virtual machine resource IDs')
output virtualMachineIds array = [for i in range(0, vmCount): virtualMachines[i].id]

@description('Array of virtual machine names')
output virtualMachineNames array = [for i in range(0, vmCount): virtualMachines[i].name]

@description('Array of public IP addresses')
output publicIPAddresses array = [for i in range(0, vmCount): publicIPAddresses[i].properties.ipAddress]

@description('Array of FQDN values')
output fqdns array = [for i in range(0, vmCount): publicIPAddresses[i].properties.dnsSettings.fqdn]

@description('Virtual network resource ID')
output virtualNetworkId string = virtualNetwork.id

@description('Subnet resource ID')
output subnetId string = virtualNetwork.properties.subnets[0].id

@description('Network security group resource ID')
output networkSecurityGroupId string = networkSecurityGroup.id

@description('Deployment summary')
output deploymentSummary object = {
  vmCount: vmCount
  vmNamePrefix: vmNamePrefix
  virtualNetworkName: virtualNetwork.name
  subnetName: subnetName
  automanageEnabled: true
  monitoringEnabled: true
  status: 'Deployed Successfully'
}