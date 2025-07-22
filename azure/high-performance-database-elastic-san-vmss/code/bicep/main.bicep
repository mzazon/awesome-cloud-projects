//==============================================================================
// Azure Elastic SAN and VMSS High-Performance Database Infrastructure
// This template deploys a complete high-performance database infrastructure
// using Azure Elastic SAN for storage and Virtual Machine Scale Sets for compute
//==============================================================================

targetScope = 'resourceGroup'

//==============================================================================
// PARAMETERS
//==============================================================================

@description('The deployment location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param resourceSuffix string = take(uniqueString(resourceGroup().id), 6)

@description('Environment name for resource tagging')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Administrator username for virtual machines')
param adminUsername string = 'azureuser'

@description('Administrator password for virtual machines')
@secure()
param adminPassword string

@description('PostgreSQL administrator username')
param postgresAdminUsername string = 'pgadmin'

@description('PostgreSQL administrator password')
@secure()
param postgresAdminPassword string

@description('Virtual network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet address prefix')
param subnetAddressPrefix string = '10.0.1.0/24'

@description('VM SKU for the Virtual Machine Scale Set')
@allowed([
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
  'Standard_D16s_v3'
])
param vmSku string = 'Standard_D4s_v3'

@description('Initial instance count for the Virtual Machine Scale Set')
@minValue(1)
@maxValue(10)
param vmssInitialInstanceCount int = 2

@description('Minimum instance count for auto-scaling')
@minValue(1)
@maxValue(5)
param vmssMinInstanceCount int = 2

@description('Maximum instance count for auto-scaling')
@minValue(5)
@maxValue(100)
param vmssMaxInstanceCount int = 10

@description('Elastic SAN base size in TiB')
@minValue(1)
@maxValue(100)
param elasticSanBaseSizeTiB int = 1

@description('Elastic SAN extended capacity size in TiB')
@minValue(1)
@maxValue(100)
param elasticSanExtendedCapacityTiB int = 2

@description('PostgreSQL Flexible Server storage size in GB')
@minValue(32)
@maxValue(65536)
param postgresStorageSizeGB int = 128

@description('PostgreSQL Flexible Server SKU')
@allowed([
  'Standard_B1ms'
  'Standard_B2s'
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
])
param postgresSku string = 'Standard_D2s_v3'

@description('Enable PostgreSQL high availability')
param postgresHighAvailability bool = true

@description('Data volume size in GB')
@minValue(100)
@maxValue(2048)
param dataVolumeSizeGB int = 500

@description('Log volume size in GB')
@minValue(50)
@maxValue(1024)
param logVolumeSizeGB int = 200

//==============================================================================
// VARIABLES
//==============================================================================

var resourceNames = {
  elasticSan: 'esan-db-${resourceSuffix}'
  vmss: 'vmss-db-${resourceSuffix}'
  vnet: 'vnet-db-${resourceSuffix}'
  subnet: 'subnet-db-${resourceSuffix}'
  loadBalancer: 'lb-db-${resourceSuffix}'
  publicIP: 'pip-db-${resourceSuffix}'
  postgresServer: 'pg-db-${resourceSuffix}'
  logAnalytics: 'law-db-${resourceSuffix}'
  actionGroup: 'ag-db-${resourceSuffix}'
  autoscaleProfile: 'vmss-autoscale-${resourceSuffix}'
  nsg: 'nsg-db-${resourceSuffix}'
}

var commonTags = {
  Environment: environment
  Purpose: 'high-performance-database'
  CreatedBy: 'bicep-template'
  CostCenter: 'database-infrastructure'
}

var postgresZones = postgresHighAvailability ? ['1', '2'] : ['1']

//==============================================================================
// NETWORKING RESOURCES
//==============================================================================

// Network Security Group
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: resourceNames.nsg
  location: location
  tags: commonTags
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 1000
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
        name: 'AllowPostgreSQL'
        properties: {
          priority: 1001
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5432'
        }
      }
      {
        name: 'AllowISCSI'
        properties: {
          priority: 1002
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3260'
        }
      }
      {
        name: 'AllowLoadBalancer'
        properties: {
          priority: 1003
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5432'
        }
      }
    ]
  }
}

// Virtual Network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: resourceNames.vnet
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: resourceNames.subnet
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          delegations: [
            {
              name: 'Microsoft.DBforPostgreSQL/flexibleServers'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
    ]
  }
}

// Public IP for Load Balancer
resource publicIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: resourceNames.publicIP
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${resourceNames.loadBalancer}-${resourceSuffix}'
    }
  }
}

// Load Balancer
resource loadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: resourceNames.loadBalancer
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
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
        name: 'db-backend-pool'
      }
    ]
    probes: [
      {
        name: 'postgresql-health-probe'
        properties: {
          protocol: 'Tcp'
          port: 5432
          intervalInSeconds: 15
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'postgresql-rule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', resourceNames.loadBalancer, 'LoadBalancerFrontEnd')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', resourceNames.loadBalancer, 'db-backend-pool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', resourceNames.loadBalancer, 'postgresql-health-probe')
          }
          protocol: 'Tcp'
          frontendPort: 5432
          backendPort: 5432
          enableFloatingIP: false
          idleTimeoutInMinutes: 4
          loadDistribution: 'Default'
        }
      }
    ]
  }
}

//==============================================================================
// ELASTIC SAN RESOURCES
//==============================================================================

// Azure Elastic SAN
resource elasticSan 'Microsoft.ElasticSan/elasticSans@2023-01-01' = {
  name: resourceNames.elasticSan
  location: location
  tags: commonTags
  properties: {
    baseSizeTiB: elasticSanBaseSizeTiB
    extendedCapacitySizeTiB: elasticSanExtendedCapacityTiB
    sku: {
      name: 'Premium_LRS'
    }
  }
}

// Volume Group for Database Storage
resource volumeGroup 'Microsoft.ElasticSan/elasticSans/volumeGroups@2023-01-01' = {
  parent: elasticSan
  name: 'vg-database-storage'
  properties: {
    protocolType: 'Iscsi'
    networkAcls: {
      virtualNetworkRules: [
        {
          id: '${virtualNetwork.id}/subnets/${resourceNames.subnet}'
          action: 'Allow'
        }
      ]
    }
  }
}

// Data Volume
resource dataVolume 'Microsoft.ElasticSan/elasticSans/volumeGroups/volumes@2023-01-01' = {
  parent: volumeGroup
  name: 'vol-pg-data'
  properties: {
    sizeGiB: dataVolumeSizeGB
    creationData: {
      sourceType: 'None'
    }
  }
}

// Log Volume
resource logVolume 'Microsoft.ElasticSan/elasticSans/volumeGroups/volumes@2023-01-01' = {
  parent: volumeGroup
  name: 'vol-pg-logs'
  properties: {
    sizeGiB: logVolumeSizeGB
    creationData: {
      sourceType: 'None'
    }
  }
}

//==============================================================================
// VIRTUAL MACHINE SCALE SET
//==============================================================================

// Virtual Machine Scale Set
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name: resourceNames.vmss
  location: location
  tags: commonTags
  sku: {
    name: vmSku
    tier: 'Standard'
    capacity: vmssInitialInstanceCount
  }
  properties: {
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {
      storageProfile: {
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2'
          version: 'latest'
        }
      }
      osProfile: {
        computerNamePrefix: 'vmdb'
        adminUsername: adminUsername
        adminPassword: adminPassword
        linuxConfiguration: {
          disablePasswordAuthentication: false
          provisionVMAgent: true
        }
        customData: base64(loadTextContent('setup-postgres.sh'))
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nic-vmss-db'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: '${virtualNetwork.id}/subnets/${resourceNames.subnet}'
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: '${loadBalancer.id}/backendAddressPools/db-backend-pool'
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
            name: 'PostgreSQLSetup'
            properties: {
              publisher: 'Microsoft.Azure.Extensions'
              type: 'CustomScript'
              typeHandlerVersion: '2.1'
              autoUpgradeMinorVersion: true
              settings: {
                fileUris: []
                commandToExecute: 'bash setup-postgres.sh'
              }
            }
          }
        ]
      }
    }
  }
}

//==============================================================================
// POSTGRESQL FLEXIBLE SERVER
//==============================================================================

// PostgreSQL Flexible Server
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: resourceNames.postgresServer
  location: location
  tags: commonTags
  sku: {
    name: postgresSku
    tier: 'GeneralPurpose'
  }
  properties: {
    administratorLogin: postgresAdminUsername
    administratorLoginPassword: postgresAdminPassword
    version: '14'
    storage: {
      storageSizeGB: postgresStorageSizeGB
      storageType: 'Premium_LRS'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Enabled'
    }
    highAvailability: postgresHighAvailability ? {
      mode: 'ZoneRedundant'
      standbyAvailabilityZone: '2'
    } : null
    availabilityZone: '1'
    network: {
      delegatedSubnetResourceId: '${virtualNetwork.id}/subnets/${resourceNames.subnet}'
    }
  }
}

//==============================================================================
// MONITORING RESOURCES
//==============================================================================

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: resourceNames.logAnalytics
  location: location
  tags: commonTags
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

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: resourceNames.actionGroup
  location: 'global'
  tags: commonTags
  properties: {
    groupShortName: 'DBAlerts'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
    eventHubReceivers: []
  }
}

//==============================================================================
// AUTO-SCALING CONFIGURATION
//==============================================================================

// Auto-scale Settings
resource autoscaleSettings 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: resourceNames.autoscaleProfile
  location: location
  tags: commonTags
  properties: {
    enabled: true
    targetResourceUri: vmss.id
    profiles: [
      {
        name: 'DefaultProfile'
        capacity: {
          minimum: string(vmssMinInstanceCount)
          maximum: string(vmssMaxInstanceCount)
          default: string(vmssInitialInstanceCount)
        }
        rules: [
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
              threshold: 70
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
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 30
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
    notifications: [
      {
        operation: 'Scale'
        email: {
          sendToSubscriptionAdministrator: false
          sendToSubscriptionCoAdministrators: false
          customEmails: []
        }
        webhooks: []
      }
    ]
  }
}

// CPU Usage Alert
resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'high-cpu-usage'
  location: 'global'
  tags: commonTags
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
          name: 'HighCPUUsage'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
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

//==============================================================================
// OUTPUTS
//==============================================================================

@description('The resource ID of the Elastic SAN')
output elasticSanId string = elasticSan.id

@description('The resource ID of the Virtual Machine Scale Set')
output vmssId string = vmss.id

@description('The resource ID of the PostgreSQL Flexible Server')
output postgresServerId string = postgresServer.id

@description('The resource ID of the Virtual Network')
output vnetId string = virtualNetwork.id

@description('The resource ID of the Load Balancer')
output loadBalancerId string = loadBalancer.id

@description('The public IP address of the Load Balancer')
output loadBalancerPublicIP string = publicIP.properties.ipAddress

@description('The FQDN of the Load Balancer')
output loadBalancerFqdn string = publicIP.properties.dnsSettings.fqdn

@description('The resource ID of the Log Analytics Workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The resource ID of the Action Group')
output actionGroupId string = actionGroup.id

@description('The resource ID of the Elastic SAN Volume Group')
output volumeGroupId string = volumeGroup.id

@description('The resource ID of the Data Volume')
output dataVolumeId string = dataVolume.id

@description('The resource ID of the Log Volume')
output logVolumeId string = logVolume.id

@description('PostgreSQL connection string')
output postgresConnectionString string = 'postgresql://${postgresAdminUsername}@${postgresServer.properties.fullyQualifiedDomainName}:5432/postgres'

@description('Load balancer connection string')
output loadBalancerConnectionString string = 'postgresql://${postgresAdminUsername}@${publicIP.properties.dnsSettings.fqdn}:5432/postgres'

@description('Deployment summary')
output deploymentSummary object = {
  elasticSanName: elasticSan.name
  vmssName: vmss.name
  postgresServerName: postgresServer.name
  loadBalancerName: loadBalancer.name
  publicIPAddress: publicIP.properties.ipAddress
  vnetName: virtualNetwork.name
  resourceGroupName: resourceGroup().name
  location: location
  environment: environment
}