@description('Main Bicep template for auto-scaling web application with Azure Virtual Machine Scale Sets and Load Balancer')

// ==============================================================================
// PARAMETERS
// ==============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Application name for resource naming')
@minLength(3)
@maxLength(15)
param applicationName string = 'webapp'

@description('Virtual Network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet address prefix for VMSS')
param subnetAddressPrefix string = '10.0.1.0/24'

@description('VM SKU size for scale set instances')
@allowed(['Standard_B1s', 'Standard_B2s', 'Standard_D2s_v3', 'Standard_D4s_v3'])
param vmSkuSize string = 'Standard_B2s'

@description('Initial number of VM instances in scale set')
@minValue(2)
@maxValue(100)
param initialInstanceCount int = 2

@description('Minimum number of VM instances for auto-scaling')
@minValue(1)
@maxValue(10)
param minInstanceCount int = 2

@description('Maximum number of VM instances for auto-scaling')
@minValue(2)
@maxValue(100)
param maxInstanceCount int = 10

@description('Admin username for VM instances')
param adminUsername string = 'azureuser'

@description('SSH public key for VM access')
param sshPublicKey string

@description('Enable Application Insights monitoring')
param enableApplicationInsights bool = true

@description('Auto-scale CPU threshold for scale-out (percentage)')
@minValue(50)
@maxValue(90)
param scaleOutCpuThreshold int = 70

@description('Auto-scale CPU threshold for scale-in (percentage)')
@minValue(10)
@maxValue(50)
param scaleInCpuThreshold int = 30

@description('Tags to apply to all resources')
param resourceTags object = {
  Environment: environment
  Application: applicationName
  ManagedBy: 'Bicep'
  Purpose: 'AutoScalingWebApp'
}

// ==============================================================================
// VARIABLES
// ==============================================================================

var resourceNamePrefix = '${applicationName}-${environment}'
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)

// Resource names
var vnetName = '${resourceNamePrefix}-vnet-${uniqueSuffix}'
var subnetName = '${resourceNamePrefix}-subnet'
var nsgName = '${resourceNamePrefix}-nsg-${uniqueSuffix}'
var publicIpName = '${resourceNamePrefix}-pip-${uniqueSuffix}'
var loadBalancerName = '${resourceNamePrefix}-lb-${uniqueSuffix}'
var vmssName = '${resourceNamePrefix}-vmss-${uniqueSuffix}'
var appInsightsName = '${resourceNamePrefix}-insights-${uniqueSuffix}'
var logAnalyticsName = '${resourceNamePrefix}-logs-${uniqueSuffix}'
var autoScaleName = '${resourceNamePrefix}-autoscale-${uniqueSuffix}'

// Cloud-init script for web server setup
var cloudInitData = base64('''#cloud-config
package_upgrade: true
packages:
  - nginx
runcmd:
  - systemctl start nginx
  - systemctl enable nginx
  - echo "<h1>Web Server $(hostname)</h1><p>Server Time: $(date)</p><p>Environment: ${environment}</p>" > /var/www/html/index.html
  - systemctl restart nginx
''')

// ==============================================================================
// RESOURCES
// ==============================================================================

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableApplicationInsights) {
  name: logAnalyticsName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'IbizaAIExtension'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
  }
}

// Public IP for Load Balancer
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: '${resourceNamePrefix}-${uniqueSuffix}'
    }
  }
}

// Network Security Group with web traffic rules
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  tags: resourceTags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP'
        properties: {
          description: 'Allow HTTP traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-HTTPS'
        properties: {
          description: 'Allow HTTPS traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SSH'
        properties: {
          description: 'Allow SSH access for management'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Virtual Network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: resourceTags
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

// Load Balancer
resource loadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: loadBalancerName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'frontend-ip'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'backend-pool'
      }
    ]
    probes: [
      {
        name: 'http-probe'
        properties: {
          protocol: 'Http'
          port: 80
          requestPath: '/'
          intervalInSeconds: 15
          numberOfProbes: 3
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'http-rule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, 'frontend-ip')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, 'backend-pool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, 'http-probe')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          loadDistribution: 'Default'
        }
      }
    ]
  }
}

// Virtual Machine Scale Set
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name: vmssName
  location: location
  tags: resourceTags
  sku: {
    name: vmSkuSize
    tier: 'Standard'
    capacity: initialInstanceCount
  }
  properties: {
    upgradePolicy: {
      mode: 'Automatic'
      automaticOSUpgradePolicy: {
        enableAutomaticOSUpgrade: true
        disableAutomaticRollback: false
      }
    }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: '${applicationName}vm'
        adminUsername: adminUsername
        customData: cloudInitData
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUsername}/.ssh/authorized_keys'
                keyData: sshPublicKey
              }
            ]
          }
        }
      }
      storageProfile: {
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
          diskSizeGB: 30
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nic-config'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ip-config'
                  properties: {
                    subnet: {
                      id: '${virtualNetwork.id}/subnets/${subnetName}'
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: '${loadBalancer.id}/backendAddressPools/backend-pool'
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
      extensionProfile: enableApplicationInsights ? {
        extensions: [
          {
            name: 'ApplicationInsightsAgent'
            properties: {
              publisher: 'Microsoft.Azure.Diagnostics'
              type: 'LinuxDiagnostic'
              typeHandlerVersion: '3.0'
              autoUpgradeMinorVersion: true
              settings: {
                StorageAccount: 'mystorageaccount'
                ladCfg: {
                  diagnosticMonitorConfiguration: {
                    eventVolume: 'Medium'
                    metrics: {
                      resourceId: vmss.id
                      metricAggregation: [
                        {
                          scheduledTransferPeriod: 'PT1H'
                          unit: 'Count'
                        }
                      ]
                    }
                  }
                }
              }
            }
          }
        ]
      } : null
    }
    scaleInPolicy: {
      rules: [
        'OldestVM'
      ]
    }
  }
  dependsOn: [
    loadBalancer
  ]
}

// Auto-scale settings
resource autoScaleSettings 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: autoScaleName
  location: location
  tags: resourceTags
  properties: {
    name: autoScaleName
    targetResourceUri: vmss.id
    enabled: true
    profiles: [
      {
        name: 'default-profile'
        capacity: {
          minimum: string(minInstanceCount)
          maximum: string(maxInstanceCount)
          default: string(initialInstanceCount)
        }
        rules: [
          // Scale-out rule
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: scaleOutCpuThreshold
              dimensions: []
              dividePerInstance: false
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '2'
              cooldown: 'PT5M'
            }
          }
          // Scale-in rule
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: scaleInCpuThreshold
              dimensions: []
              dividePerInstance: false
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
    notifications: []
  }
}

// High CPU Alert
resource highCpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableApplicationInsights) {
  name: '${resourceNamePrefix}-high-cpu-alert'
  location: 'global'
  tags: resourceTags
  properties: {
    description: 'Alert when CPU usage exceeds 80%'
    severity: 2
    enabled: true
    scopes: [
      vmss.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCPU'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('Public IP address of the Load Balancer')
output loadBalancerPublicIp string = publicIp.properties.ipAddress

@description('FQDN of the Load Balancer')
output loadBalancerFqdn string = publicIp.properties.dnsSettings.fqdn

@description('Resource ID of the Virtual Machine Scale Set')
output vmssResourceId string = vmss.id

@description('Resource ID of the Load Balancer')
output loadBalancerResourceId string = loadBalancer.id

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Application Insights App ID')
output applicationInsightsAppId string = enableApplicationInsights ? applicationInsights.properties.AppId : ''

@description('Virtual Network Resource ID')
output virtualNetworkId string = virtualNetwork.id

@description('Subnet Resource ID')
output subnetId string = '${virtualNetwork.id}/subnets/${subnetName}'

@description('Network Security Group Resource ID')
output networkSecurityGroupId string = networkSecurityGroup.id

@description('Auto-scale Settings Resource ID')
output autoScaleSettingsId string = autoScaleSettings.id

@description('Current instance count')
output currentInstanceCount int = vmss.sku.capacity

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Deployment Environment')
output environment string = environment

@description('Application Name')
output applicationName string = applicationName