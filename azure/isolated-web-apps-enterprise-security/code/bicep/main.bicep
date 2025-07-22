@description('Deployment of enterprise-grade isolated web applications with Azure App Service Environment v3 and Azure Private DNS')

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Name prefix for all resources')
param namePrefix string = 'ase-enterprise'

@description('Random suffix for resource names')
param randomSuffix string = uniqueString(resourceGroup().id, deployment().name)

@description('Virtual network address space')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('ASE subnet address prefix')
param aseSubnetAddressPrefix string = '10.0.1.0/24'

@description('NAT Gateway subnet address prefix')
param natSubnetAddressPrefix string = '10.0.2.0/24'

@description('Support subnet address prefix')
param supportSubnetAddressPrefix string = '10.0.3.0/24'

@description('Bastion subnet address prefix')
param bastionSubnetAddressPrefix string = '10.0.4.0/26'

@description('Private DNS zone name')
param privateDnsZoneName string = 'enterprise.internal'

@description('App Service Environment zone redundancy')
param aseZoneRedundant bool = false

@description('App Service Plan SKU')
@allowed([
  'I1v2'
  'I2v2'
  'I3v2'
  'I4v2'
  'I5v2'
  'I6v2'
])
param appServicePlanSku string = 'I1v2'

@description('Web application runtime stack')
@allowed([
  'dotnet:8'
  'dotnet:6'
  'node:18'
  'node:20'
  'python:3.11'
  'java:11'
  'java:17'
])
param webAppRuntime string = 'dotnet:8'

@description('Management VM admin username')
param vmAdminUsername string = 'azureuser'

@description('Management VM admin password')
@secure()
param vmAdminPassword string

@description('Enable Azure Bastion deployment')
param enableBastion bool = true

@description('Enable management VM deployment')
param enableManagementVm bool = true

@description('Resource tags')
param tags object = {
  purpose: 'enterprise-isolation'
  environment: 'production'
  'recipe-id': 'a7f3c5d9'
}

// Variables
var vnetName = '${namePrefix}-vnet-${randomSuffix}'
var aseSubnetName = '${namePrefix}-ase-subnet-${randomSuffix}'
var natSubnetName = '${namePrefix}-nat-subnet-${randomSuffix}'
var supportSubnetName = '${namePrefix}-support-subnet-${randomSuffix}'
var bastionSubnetName = 'AzureBastionSubnet'
var aseName = '${namePrefix}-ase-${randomSuffix}'
var natGatewayName = '${namePrefix}-nat-gateway-${randomSuffix}'
var publicIpName = '${namePrefix}-pip-nat-${randomSuffix}'
var bastionName = '${namePrefix}-bastion-${randomSuffix}'
var bastionPipName = '${namePrefix}-pip-bastion-${randomSuffix}'
var appServicePlanName = '${namePrefix}-asp-${randomSuffix}'
var webAppName = '${namePrefix}-webapp-${randomSuffix}'
var managementVmName = '${namePrefix}-vm-mgmt-${randomSuffix}'
var managementVmNicName = '${namePrefix}-vm-mgmt-nic-${randomSuffix}'

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: union(tags, {
    tier: 'network'
  })
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: aseSubnetName
        properties: {
          addressPrefix: aseSubnetAddressPrefix
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.KeyVault'
            }
          ]
          delegations: [
            {
              name: 'Microsoft.Web.hostingEnvironments'
              properties: {
                serviceName: 'Microsoft.Web/hostingEnvironments'
              }
            }
          ]
          natGateway: {
            id: natGateway.id
          }
        }
      }
      {
        name: natSubnetName
        properties: {
          addressPrefix: natSubnetAddressPrefix
        }
      }
      {
        name: supportSubnetName
        properties: {
          addressPrefix: supportSubnetAddressPrefix
        }
      }
      {
        name: bastionSubnetName
        properties: {
          addressPrefix: bastionSubnetAddressPrefix
        }
      }
    ]
  }
}

// NAT Gateway Public IP
resource natPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  tags: union(tags, {
    tier: 'network'
    purpose: 'nat-gateway'
  })
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 10
  }
}

// NAT Gateway
resource natGateway 'Microsoft.Network/natGateways@2023-09-01' = {
  name: natGatewayName
  location: location
  tags: union(tags, {
    tier: 'network'
    purpose: 'outbound-connectivity'
  })
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natPublicIp.id
      }
    ]
    idleTimeoutInMinutes: 10
  }
}

// Private DNS Zone
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: union(tags, {
    tier: 'network'
    purpose: 'internal-dns'
  })
}

// Private DNS Zone Virtual Network Link
resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: 'link-${vnetName}'
  parent: privateDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// App Service Environment v3
resource ase 'Microsoft.Web/hostingEnvironments@2023-01-01' = {
  name: aseName
  location: location
  tags: union(tags, {
    tier: 'compute'
    purpose: 'enterprise-isolation'
  })
  kind: 'ASEV3'
  properties: {
    virtualNetwork: {
      id: vnet.properties.subnets[0].id
    }
    internalLoadBalancingMode: 'Web, Publishing'
    zoneRedundant: aseZoneRedundant
    dedicatedHostCount: 0
    frontEndScaleFactor: 15
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: union(tags, {
    tier: 'compute'
    purpose: 'enterprise-app'
  })
  sku: {
    name: appServicePlanSku
    tier: 'IsolatedV2'
  }
  properties: {
    hostingEnvironmentProfile: {
      id: ase.id
    }
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: false
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
  }
}

// Web Application
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  tags: union(tags, {
    tier: 'application'
    purpose: 'enterprise-app'
  })
  properties: {
    serverFarmId: appServicePlan.id
    hostingEnvironmentProfile: {
      id: ase.id
    }
    httpsOnly: true
    siteConfig: {
      metadata: [
        {
          name: 'CURRENT_STACK'
          value: split(webAppRuntime, ':')[0]
        }
      ]
      appSettings: [
        {
          name: 'WEBSITE_DNS_SERVER'
          value: '168.63.129.16'
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        }
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Production'
        }
      ]
      linuxFxVersion: contains(webAppRuntime, 'dotnet') ? '' : 'NODE|${split(webAppRuntime, ':')[1]}'
      netFrameworkVersion: contains(webAppRuntime, 'dotnet') ? 'v${split(webAppRuntime, ':')[1]}.0' : null
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      use32BitWorkerProcess: false
      webSocketsEnabled: false
      managedPipelineMode: 'Integrated'
      virtualApplications: [
        {
          virtualPath: '/'
          physicalPath: 'site\\wwwroot'
        }
      ]
      loadBalancing: 'LeastRequests'
      experiments: {
        rampUpRules: []
      }
      autoHealEnabled: false
      vnetRouteAllEnabled: true
      vnetPrivatePortsCount: 0
      localMySqlEnabled: false
      ipSecurityRestrictions: [
        {
          ipAddress: 'Any'
          action: 'Allow'
          priority: 2147483647
          name: 'Allow all'
          description: 'Allow all access'
        }
      ]
      scmIpSecurityRestrictions: [
        {
          ipAddress: 'Any'
          action: 'Allow'
          priority: 2147483647
          name: 'Allow all'
          description: 'Allow all access'
        }
      ]
      scmIpSecurityRestrictionsUseMain: false
      http20Enabled: false
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      preWarmedInstanceCount: 0
      functionAppScaleLimit: 0
      functionsRuntimeScaleMonitoringEnabled: false
      minimumElasticInstanceCount: 0
      azureStorageAccounts: {}
    }
  }
}

// Private DNS Records
resource webAppDnsRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: 'webapp'
  parent: privateDnsZone
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: ase.properties.internalInboundIpAddress
      }
    ]
  }
}

resource apiDnsRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: 'api'
  parent: privateDnsZone
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: ase.properties.internalInboundIpAddress
      }
    ]
  }
}

resource wildcardDnsRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: '*'
  parent: privateDnsZone
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: ase.properties.internalInboundIpAddress
      }
    ]
  }
}

// Azure Bastion (conditional deployment)
resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = if (enableBastion) {
  name: bastionPipName
  location: location
  tags: union(tags, {
    tier: 'management'
    purpose: 'bastion'
  })
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = if (enableBastion) {
  name: bastionName
  location: location
  tags: union(tags, {
    tier: 'management'
    purpose: 'secure-management'
  })
  sku: {
    name: 'Standard'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: vnet.properties.subnets[3].id
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
    enableTunneling: true
    enableIpConnect: true
    enableShareableLink: false
    enableSessionRecording: false
  }
}

// Management VM Network Interface
resource managementVmNic 'Microsoft.Network/networkInterfaces@2023-09-01' = if (enableManagementVm) {
  name: managementVmNicName
  location: location
  tags: union(tags, {
    tier: 'management'
    purpose: 'vm-interface'
  })
  properties: {
    ipConfigurations: [
      {
        name: 'internal'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: vnet.properties.subnets[2].id
          }
        }
      }
    ]
  }
}

// Management Virtual Machine
resource managementVm 'Microsoft.Compute/virtualMachines@2023-09-01' = if (enableManagementVm) {
  name: managementVmName
  location: location
  tags: union(tags, {
    tier: 'compute'
    purpose: 'management'
  })
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2s_v3'
    }
    osProfile: {
      computerName: managementVmName
      adminUsername: vmAdminUsername
      adminPassword: vmAdminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
          assessmentMode: 'ImageDefault'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        name: '${managementVmName}-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: managementVmNic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// VM Extension for IIS Installation
resource managementVmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (enableManagementVm) {
  name: 'InstallIIS'
  parent: managementVm
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: 'powershell.exe Install-WindowsFeature -Name Web-Server -IncludeManagementTools'
    }
  }
}

// Outputs
@description('App Service Environment name')
output aseEnvironmentName string = ase.name

@description('App Service Environment internal IP address')
output aseInternalIpAddress string = ase.properties.internalInboundIpAddress

@description('NAT Gateway public IP address')
output natGatewayPublicIp string = natPublicIp.properties.ipAddress

@description('Web application default hostname')
output webAppDefaultHostname string = webApp.properties.defaultHostName

@description('Web application resource ID')
output webAppResourceId string = webApp.id

@description('Private DNS zone name')
output privateDnsZoneName string = privateDnsZone.name

@description('Virtual network resource ID')
output virtualNetworkId string = vnet.id

@description('Virtual network name')
output virtualNetworkName string = vnet.name

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('NAT Gateway resource ID')
output natGatewayResourceId string = natGateway.id

@description('Azure Bastion hostname (if enabled)')
output bastionHostname string = enableBastion ? bastion.properties.dnsName : ''

@description('Management VM name (if enabled)')
output managementVmName string = enableManagementVm ? managementVm.name : ''

@description('App Service Plan resource ID')
output appServicePlanId string = appServicePlan.id

@description('Deployment summary')
output deploymentSummary object = {
  aseEnvironmentName: ase.name
  aseInternalIp: ase.properties.internalInboundIpAddress
  natGatewayPublicIp: natPublicIp.properties.ipAddress
  webAppHostname: webApp.properties.defaultHostName
  privateDnsZone: privateDnsZone.name
  bastionEnabled: enableBastion
  managementVmEnabled: enableManagementVm
  location: location
  resourceGroupName: resourceGroup().name
}