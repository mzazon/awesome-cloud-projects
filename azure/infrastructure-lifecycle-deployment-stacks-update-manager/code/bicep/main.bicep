@description('Location for all resources')
param location string = resourceGroup().location

@description('Admin username for virtual machines')
param adminUsername string = 'azureuser'

@description('Admin password for virtual machines')
@secure()
param adminPassword string

@description('Size of virtual machines')
@allowed([
  'Standard_B2s'
  'Standard_B2ms'
  'Standard_D2s_v3'
  'Standard_D2s_v4'
  'Standard_D2s_v5'
])
param vmSize string = 'Standard_B2s'

@description('Number of VM instances in the scale set')
@minValue(1)
@maxValue(10)
param instanceCount int = 2

@description('Name prefix for resources')
param resourcePrefix string = 'infra-lifecycle'

@description('Environment tag for resources')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Log Analytics workspace SKU')
@allowed([
  'Free'
  'Standard'
  'Premium'
  'PerNode'
  'PerGB2018'
  'Standalone'
  'CapacityReservation'
])
param logAnalyticsWorkspaceSku string = 'PerGB2018'

@description('Maintenance configuration schedule settings')
param maintenanceSchedule object = {
  frequency: 'Week'
  interval: 1
  startTime: '2024-01-01T02:00:00'
  timeZone: 'UTC'
  duration: 'PT3H'
  daysOfWeek: [
    'Sunday'
  ]
}

@description('Enable monitoring and diagnostics')
param enableMonitoring bool = true

// Variables for consistent naming
var uniqueSuffix = uniqueString(resourceGroup().id)
var vnetName = '${resourcePrefix}-vnet-${uniqueSuffix}'
var nsgName = '${resourcePrefix}-nsg-${uniqueSuffix}'
var publicIpName = '${resourcePrefix}-pip-${uniqueSuffix}'
var loadBalancerName = '${resourcePrefix}-lb-${uniqueSuffix}'
var vmssName = '${resourcePrefix}-vmss-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-law-${uniqueSuffix}'
var maintenanceConfigName = '${resourcePrefix}-mc-${uniqueSuffix}'

// Common tags for all resources
var commonTags = {
  environment: environment
  project: 'infrastructure-lifecycle'
  managedBy: 'deployment-stack'
  createdDate: utcNow('yyyy-MM-dd')
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableMonitoring) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: logAnalyticsWorkspaceSku
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

// Virtual Network with subnet for web tier
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-web'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
}

// Network Security Group with secure default rules
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  tags: commonTags
  properties: {
    securityRules: [
      {
        name: 'AllowHTTPInbound'
        properties: {
          description: 'Allow HTTP traffic from internet'
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      {
        name: 'AllowHTTPSInbound'
        properties: {
          description: 'Allow HTTPS traffic from internet'
          priority: 1001
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'AllowSSHInbound'
        properties: {
          description: 'Allow SSH access for management'
          priority: 1002
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Deny all other inbound traffic'
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// Public IP for Load Balancer with Standard SKU
resource publicIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
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
      domainNameLabel: '${resourcePrefix}-${uniqueSuffix}'
    }
    idleTimeoutInMinutes: 4
  }
}

// Load Balancer with health probe and load balancing rules
resource loadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: loadBalancerName
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'LoadBalancerFrontEnd'
        properties: {
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'BackendPool'
      }
    ]
    loadBalancingRules: [
      {
        name: 'HTTPRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, 'LoadBalancerFrontEnd')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'BackendPool')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'HTTPHealthProbe')
          }
          loadDistribution: 'Default'
        }
      }
      {
        name: 'HTTPSRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, 'LoadBalancerFrontEnd')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'BackendPool')
          }
          protocol: 'Tcp'
          frontendPort: 443
          backendPort: 443
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'HTTPHealthProbe')
          }
          loadDistribution: 'Default'
        }
      }
    ]
    probes: [
      {
        name: 'HTTPHealthProbe'
        properties: {
          protocol: 'Http'
          port: 80
          requestPath: '/'
          intervalInSeconds: 15
          numberOfProbes: 2
        }
      }
    ]
  }
}

// Virtual Machine Scale Set with auto-scaling capabilities
resource virtualMachineScaleSet 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name: vmssName
  location: location
  tags: commonTags
  sku: {
    name: vmSize
    tier: 'Standard'
    capacity: instanceCount
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    orchestrationMode: 'Uniform'
    upgradePolicy: {
      mode: 'Manual'
    }
    automaticRepairsPolicy: {
      enabled: true
      gracePeriod: 'PT30M'
    }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'web'
        adminUsername: adminUsername
        adminPassword: adminPassword
        linuxConfiguration: {
          disablePasswordAuthentication: false
          provisionVMAgent: true
          patchSettings: {
            patchMode: 'AutomaticByPlatform'
            automaticByPlatformSettings: {
              rebootSetting: 'IfRequired'
            }
          }
        }
      }
      storageProfile: {
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
          diskSizeGB: 64
        }
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2'
          version: 'latest'
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nic-web'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'subnet-web')
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'BackendPool')
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
      extensionProfile: {
        extensions: [
          {
            name: 'customScript'
            properties: {
              publisher: 'Microsoft.Azure.Extensions'
              type: 'CustomScript'
              typeHandlerVersion: '2.1'
              autoUpgradeMinorVersion: true
              settings: {
                commandToExecute: 'apt-get update && apt-get install -y nginx && systemctl enable nginx && systemctl start nginx && echo "<h1>Infrastructure Lifecycle Demo - $(hostname)</h1>" > /var/www/html/index.html'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    virtualNetwork
    loadBalancer
  ]
}

// Auto-scaling settings for the VM Scale Set
resource autoScaleSettings 'Microsoft.Insights/autoscalesettings@2022-10-01' = if (enableMonitoring) {
  name: '${vmssName}-autoscale'
  location: location
  tags: commonTags
  properties: {
    name: '${vmssName}-autoscale'
    targetResourceUri: virtualMachineScaleSet.id
    enabled: true
    profiles: [
      {
        name: 'DefaultProfile'
        capacity: {
          minimum: '1'
          maximum: '10'
          default: string(instanceCount)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
              metricResourceUri: virtualMachineScaleSet.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 75
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
              metricResourceUri: virtualMachineScaleSet.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 25
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
        ]
      }
    ]
  }
}

// Maintenance Configuration for Update Manager
resource maintenanceConfiguration 'Microsoft.Maintenance/maintenanceConfigurations@2023-04-01' = {
  name: maintenanceConfigName
  location: location
  tags: commonTags
  properties: {
    maintenanceScope: 'InGuestPatch'
    installPatches: {
      rebootSetting: 'IfRequired'
      linuxParameters: {
        classificationsToInclude: [
          'Critical'
          'Security'
        ]
        packageNameMasksToInclude: [
          '*'
        ]
        packageNameMasksToExclude: []
      }
      windowsParameters: {
        classificationsToInclude: [
          'Critical'
          'Security'
        ]
        kbNumbersToInclude: []
        kbNumbersToExclude: []
      }
    }
    window: {
      startDateTime: maintenanceSchedule.startTime
      duration: maintenanceSchedule.duration
      timeZone: maintenanceSchedule.timeZone
      recurEvery: '${maintenanceSchedule.interval}${maintenanceSchedule.frequency}'
    }
  }
}

// Diagnostic Settings for VMSS (requires Log Analytics workspace)
resource vmsssDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: 'vmss-diagnostics'
  scope: virtualMachineScaleSet
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: []
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Diagnostic Settings for Load Balancer
resource loadBalancerDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: 'lb-diagnostics'
  scope: loadBalancer
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Outputs for verification and integration
@description('The public IP address of the load balancer')
output loadBalancerPublicIP string = publicIP.properties.ipAddress

@description('The FQDN of the load balancer')
output loadBalancerFQDN string = publicIP.properties.dnsSettings.fqdn

@description('The resource ID of the virtual machine scale set')
output vmssResourceId string = virtualMachineScaleSet.id

@description('The name of the virtual machine scale set')
output vmssName string = virtualMachineScaleSet.name

@description('The resource ID of the virtual network')
output vnetResourceId string = virtualNetwork.id

@description('The name of the virtual network')
output vnetName string = virtualNetwork.name

@description('The resource ID of the maintenance configuration')
output maintenanceConfigurationId string = maintenanceConfiguration.id

@description('The name of the maintenance configuration')
output maintenanceConfigurationName string = maintenanceConfiguration.name

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = enableMonitoring ? logAnalyticsWorkspace.id : ''

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = enableMonitoring ? logAnalyticsWorkspace.name : ''

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('The subscription ID')
output subscriptionId string = subscription().subscriptionId

@description('URL to access the deployed application')
output applicationUrl string = 'http://${publicIP.properties.ipAddress}'

@description('Common tags applied to all resources')
output commonTags object = commonTags