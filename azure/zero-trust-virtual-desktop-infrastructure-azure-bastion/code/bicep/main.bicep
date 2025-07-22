// Main Bicep template for Azure Virtual Desktop with Azure Bastion
// This template deploys a complete multi-session virtual desktop infrastructure

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource naming')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Administrator username for session host VMs')
param adminUsername string = 'avdadmin'

@description('Administrator password for session host VMs')
@secure()
param adminPassword string

@description('Virtual network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('AVD subnet address prefix')
param avdSubnetPrefix string = '10.0.1.0/24'

@description('Azure Bastion subnet address prefix')
param bastionSubnetPrefix string = '10.0.2.0/27'

@description('Maximum session limit per session host')
param maxSessionLimit int = 10

@description('Session host VM size')
param sessionHostSize string = 'Standard_D4s_v3'

@description('Number of session hosts to deploy')
param sessionHostCount int = 2

@description('Load balancer type for the host pool')
@allowed(['BreadthFirst', 'DepthFirst'])
param loadBalancerType string = 'BreadthFirst'

@description('Host pool type')
@allowed(['Personal', 'Pooled'])
param hostPoolType string = 'Pooled'

@description('Preferred application group type')
@allowed(['Desktop', 'RailApplications'])
param preferredAppGroupType string = 'Desktop'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'virtual-desktop'
  environment: 'production'
  component: 'avd-infrastructure'
}

// Variables
var vnetName = 'vnet-avd-${resourceSuffix}'
var avdSubnetName = 'subnet-avd-hosts'
var bastionSubnetName = 'AzureBastionSubnet'
var nsgName = 'nsg-avd-hosts'
var bastionName = 'bastion-avd-${resourceSuffix}'
var bastionPublicIpName = 'pip-bastion-${resourceSuffix}'
var hostPoolName = 'hp-multi-session-${resourceSuffix}'
var workspaceName = 'ws-remote-desktop-${resourceSuffix}'
var appGroupName = 'ag-desktop-${resourceSuffix}'
var keyVaultName = 'kv-avd-${resourceSuffix}'
var sessionHostPrefix = 'vm-avd-host'

// Key Vault for certificate and secret management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: union(tags, { component: 'security' })
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Store admin password in Key Vault
resource adminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'avd-admin-password'
  properties: {
    value: adminPassword
    attributes: {
      enabled: true
    }
  }
}

// Virtual Network with subnets
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: union(tags, { component: 'networking' })
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: avdSubnetName
        properties: {
          addressPrefix: avdSubnetPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
      {
        name: bastionSubnetName
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
    ]
  }
}

// Network Security Group for AVD subnet
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  tags: union(tags, { component: 'security' })
  properties: {
    securityRules: [
      {
        name: 'AllowAVDServiceTraffic'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'WindowsVirtualDesktop'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowBastionInbound'
        properties: {
          priority: 1100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: ['3389', '22']
        }
      }
      {
        name: 'AllowAzureCloudOutbound'
        properties: {
          priority: 1200
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

// Public IP for Azure Bastion
resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: bastionPublicIpName
  location: location
  tags: union(tags, { component: 'networking' })
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// Azure Bastion for secure administrative access
resource bastion 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: bastionName
  location: location
  tags: union(tags, { component: 'security' })
  sku: {
    name: 'Basic'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, bastionSubnetName)
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

// Azure Virtual Desktop Host Pool
resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2023-09-05' = {
  name: hostPoolName
  location: location
  tags: union(tags, { component: 'virtual-desktop' })
  properties: {
    hostPoolType: hostPoolType
    maxSessionLimit: maxSessionLimit
    loadBalancerType: loadBalancerType
    preferredAppGroupType: preferredAppGroupType
    startVMOnConnect: false
    customRdpProperty: 'drivestoredirect:s:*;audiomode:i:0;videoplaybackmode:i:1;redirectclipboard:i:1;redirectprinters:i:1;devicestoredirect:s:*;redirectcomports:i:1;redirectsmartcards:i:1;usbdevicestoredirect:s:*;enablecredsspsupport:i:1;use multimon:i:1'
    validationEnvironment: false
    registrationInfo: {
      expirationTime: dateTimeAdd(utcNow(), 'P7D')
      registrationTokenOperation: 'Update'
    }
  }
}

// Application Group for desktop access
resource applicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2023-09-05' = {
  name: appGroupName
  location: location
  tags: union(tags, { component: 'virtual-desktop' })
  properties: {
    applicationGroupType: 'Desktop'
    hostPoolArmPath: hostPool.id
  }
}

// Workspace for user access
resource workspace 'Microsoft.DesktopVirtualization/workspaces@2023-09-05' = {
  name: workspaceName
  location: location
  tags: union(tags, { component: 'virtual-desktop' })
  properties: {
    applicationGroupReferences: [
      applicationGroup.id
    ]
  }
}

// Network interfaces for session hosts
resource sessionHostNics 'Microsoft.Network/networkInterfaces@2023-11-01' = [for i in range(0, sessionHostCount): {
  name: '${sessionHostPrefix}-${i + 1}-nic-${resourceSuffix}'
  location: location
  tags: union(tags, { component: 'session-host' })
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, avdSubnetName)
          }
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}]

// Session Host Virtual Machines
resource sessionHosts 'Microsoft.Compute/virtualMachines@2023-09-01' = [for i in range(0, sessionHostCount): {
  name: '${sessionHostPrefix}-${i + 1}-${resourceSuffix}'
  location: location
  tags: union(tags, { component: 'session-host' })
  properties: {
    hardwareProfile: {
      vmSize: sessionHostSize
    }
    osProfile: {
      computerName: '${sessionHostPrefix}-${i + 1}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'Windows-11'
        sku: 'win11-22h2-ent'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: sessionHostNics[i].id
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

// PowerShell DSC extension to install AVD agent
resource avdAgentExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for i in range(0, sessionHostCount): {
  name: 'Microsoft.PowerShell.DSC'
  parent: sessionHosts[i]
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.77'
    autoUpgradeMinorVersion: true
    settings: {
      modulesUrl: 'https://wvdportalstorageblob.blob.core.windows.net/galleryartifacts/Configuration_1.0.02507.240.zip'
      configurationFunction: 'Configuration.ps1\\Configuration'
      properties: {
        RegistrationInfoToken: hostPool.properties.registrationInfo.token
        aadJoin: false
      }
    }
  }
}]

// Outputs
output resourceGroupName string = resourceGroup().name
output location string = location
output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output virtualNetworkName string = virtualNetwork.name
output virtualNetworkId string = virtualNetwork.id
output bastionName string = bastion.name
output bastionFqdn string = bastionPublicIp.properties.dnsSettings.fqdn
output hostPoolName string = hostPool.name
output hostPoolId string = hostPool.id
output workspaceName string = workspace.name
output workspaceId string = workspace.id
output applicationGroupName string = applicationGroup.name
output applicationGroupId string = applicationGroup.id
output sessionHostNames array = [for i in range(0, sessionHostCount): sessionHosts[i].name]
output registrationToken string = hostPool.properties.registrationInfo.token