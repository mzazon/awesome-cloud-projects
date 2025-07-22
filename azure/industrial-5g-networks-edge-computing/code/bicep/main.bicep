// =============================================================================
// Azure Private 5G Networks with Operator Nexus Bicep Template
// =============================================================================
// This template deploys a complete private 5G network infrastructure using
// Azure Operator Nexus and Azure Private 5G Core services for manufacturing
// and enterprise environments.
// =============================================================================

targetScope = 'resourceGroup'

// =============================================================================
// PARAMETERS
// =============================================================================

@description('The name prefix for all resources. Keep under 8 characters for resource name limits.')
@minLength(2)
@maxLength(8)
param namePrefix string = 'p5g'

@description('The Azure region where resources will be deployed')
@allowed([
  'eastus'
  'westus2'
  'northeurope'
  'southeastasia'
])
param location string = 'eastus'

@description('The name of the mobile network')
@minLength(1)
@maxLength(64)
param mobileNetworkName string = '${namePrefix}-manufacturing'

@description('The name of the deployment site')
@minLength(1)
@maxLength(64)
param siteName string = '${namePrefix}-factory01'

@description('Public Land Mobile Network (PLMN) identifier - Mobile Country Code')
@minValue(100)
@maxValue(999)
param mobileCountryCode int = 310

@description('Public Land Mobile Network (PLMN) identifier - Mobile Network Code')
@minValue(0)
@maxValue(999)
param mobileNetworkCode int = 950

@description('The name of the Azure Stack Edge device for hosting the packet core')
@minLength(1)
@maxLength(64)
param azureStackEdgeDeviceName string = '${namePrefix}-ase-${uniqueString(resourceGroup().id)}'

@description('The subscription ID for cross-resource references')
param subscriptionId string = subscription().subscriptionId

@description('The resource group name for cross-resource references')
param resourceGroupName string = resourceGroup().name

@description('Configuration for the packet core access interface')
param accessInterface object = {
  name: 'N2'
  ipv4Address: '192.168.1.10'
  ipv4Subnet: '192.168.1.0/24'
  ipv4Gateway: '192.168.1.1'
}

@description('DNS server addresses for OT (Operational Technology) systems')
param otDnsAddresses array = [
  '10.1.0.10'
  '10.1.0.11'
]

@description('DNS server addresses for IT (Information Technology) systems')
param itDnsAddresses array = [
  '10.2.0.10'
  '10.2.0.11'
]

@description('User plane data interface IP address for OT systems')
param otUserPlaneIpAddress string = '10.1.0.100'

@description('User plane data interface IP address for IT systems')
param itUserPlaneIpAddress string = '10.2.0.100'

@description('Enable monitoring and analytics with Log Analytics workspace')
param enableMonitoring bool = true

@description('Enable IoT Hub integration for device management')
param enableIotIntegration bool = true

@description('IoT Hub SKU for device management')
@allowed([
  'S1'
  'S2'
  'S3'
])
param iotHubSku string = 'S1'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'private5g'
  environment: 'production'
  workload: 'manufacturing'
}

// =============================================================================
// VARIABLES
// =============================================================================

var uniqueSuffix = uniqueString(resourceGroup().id)
var customLocationName = '${namePrefix}-cl-${siteName}'
var logAnalyticsWorkspaceName = '${namePrefix}-law-${uniqueSuffix}'
var iotHubName = '${namePrefix}-iothub-${uniqueSuffix}'
var deviceProvisioningServiceName = '${namePrefix}-dps-${uniqueSuffix}'
var containerRegistryName = '${namePrefix}acr${uniqueSuffix}'

// Network slice configurations for different use cases
var networkSlices = [
  {
    name: 'slice-critical-iot'
    snssai: {
      sst: 1
      sd: '000001'
    }
    description: 'Ultra-reliable low latency communications for mission-critical IoT'
  }
  {
    name: 'slice-massive-iot'
    snssai: {
      sst: 2
      sd: '000002'
    }
    description: 'Massive machine-type communications for bulk IoT sensors'
  }
  {
    name: 'slice-video'
    snssai: {
      sst: 3
      sd: '000003'
    }
    description: 'Enhanced mobile broadband for video surveillance'
  }
]

// Data network configurations for traffic segmentation
var dataNetworks = [
  {
    name: 'dn-ot-systems'
    description: 'Data network for operational technology systems'
    dnsAddresses: otDnsAddresses
    userPlaneDataInterface: {
      name: 'N6'
      ipv4Address: otUserPlaneIpAddress
    }
  }
  {
    name: 'dn-it-systems'
    description: 'Data network for information technology systems'
    dnsAddresses: itDnsAddresses
    userPlaneDataInterface: {
      name: 'N6'
      ipv4Address: itUserPlaneIpAddress
    }
  }
]

// Service configurations for different traffic types
var services = [
  {
    name: 'svc-realtime-control'
    description: 'Service for real-time manufacturing control systems'
    serviceQoS: {
      fiveQi: 82
      allocationAndRetentionPriority: {
        priorityLevel: 1
        preemptionCapability: 'MayPreempt'
        preemptionVulnerability: 'NotPreemptable'
      }
    }
    pccRules: [
      {
        ruleName: 'rule-control'
        rulePrecedence: 100
        serviceDataFlowTemplates: [
          {
            templateName: 'control-traffic'
            direction: 'Bidirectional'
            protocol: [
              'TCP'
            ]
            remoteIpList: [
              '10.1.0.0/16'
            ]
          }
        ]
      }
    ]
  }
  {
    name: 'svc-video-surveillance'
    description: 'Service for video surveillance and monitoring'
    serviceQoS: {
      fiveQi: 4
      allocationAndRetentionPriority: {
        priorityLevel: 5
        preemptionCapability: 'MayPreempt'
        preemptionVulnerability: 'Preemptable'
      }
    }
    pccRules: [
      {
        ruleName: 'rule-video'
        rulePrecedence: 200
        serviceDataFlowTemplates: [
          {
            templateName: 'video-streams'
            direction: 'Uplink'
            protocol: [
              'UDP'
            ]
            remoteIpList: [
              '10.2.0.0/16'
            ]
            ports: [
              '554'
            ]
          }
        ]
      }
    ]
  }
]

// =============================================================================
// RESOURCES
// =============================================================================

// Mobile Network - Core network resource representing the private 5G network
resource mobileNetwork 'Microsoft.MobileNetwork/mobileNetworks@2023-09-01' = {
  name: mobileNetworkName
  location: location
  tags: tags
  properties: {
    publicLandMobileNetworkIdentifier: {
      mcc: string(mobileCountryCode)
      mnc: string(mobileNetworkCode)
    }
  }
}

// Network Slices - Virtual networks for different use cases
resource networkSlice 'Microsoft.MobileNetwork/mobileNetworks/slices@2023-09-01' = [for slice in networkSlices: {
  name: slice.name
  parent: mobileNetwork
  location: location
  tags: tags
  properties: {
    snssai: slice.snssai
    description: slice.description
  }
}]

// Data Networks - Define traffic routing and segmentation
resource dataNetwork 'Microsoft.MobileNetwork/mobileNetworks/dataNetworks@2023-09-01' = [for network in dataNetworks: {
  name: network.name
  parent: mobileNetwork
  location: location
  tags: tags
  properties: {
    description: network.description
  }
}]

// Attached Data Networks - Connect data networks to mobile network
resource attachedDataNetwork 'Microsoft.MobileNetwork/mobileNetworks/attachedDataNetworks@2023-09-01' = [for (network, index) in dataNetworks: {
  name: network.name
  parent: mobileNetwork
  location: location
  tags: tags
  properties: {
    dnsAddresses: network.dnsAddresses
    userPlaneDataInterface: network.userPlaneDataInterface
  }
  dependsOn: [
    dataNetwork[index]
  ]
}]

// Services - Define QoS policies for different traffic types
resource service 'Microsoft.MobileNetwork/mobileNetworks/services@2023-09-01' = [for svc in services: {
  name: svc.name
  parent: mobileNetwork
  location: location
  tags: tags
  properties: {
    serviceQosPolicy: svc.serviceQoS
    pccRules: svc.pccRules
  }
}]

// Mobile Network Site - Physical location for packet core deployment
resource site 'Microsoft.MobileNetwork/mobileNetworks/sites@2023-09-01' = {
  name: siteName
  parent: mobileNetwork
  location: location
  tags: tags
  properties: {
    description: 'Manufacturing facility site for private 5G deployment'
  }
}

// SIM Policy - Controls device access and service assignment
resource simPolicy 'Microsoft.MobileNetwork/mobileNetworks/simPolicies@2023-09-01' = {
  name: 'policy-industrial-iot'
  parent: mobileNetwork
  location: location
  tags: tags
  properties: {
    defaultSlice: {
      id: networkSlice[0].id // Critical IoT slice
    }
    ueAmbr: {
      uplink: '10 Mbps'
      downlink: '10 Mbps'
    }
    sliceConfigurations: [
      {
        slice: {
          id: networkSlice[0].id
        }
        defaultDataNetwork: {
          id: dataNetwork[0].id // OT systems network
        }
        dataNetworkConfigurations: [
          {
            dataNetwork: {
              id: dataNetwork[0].id
            }
            sessionAmbr: {
              uplink: '10 Mbps'
              downlink: '10 Mbps'
            }
            fiveQi: 82
            allocationAndRetentionPriority: {
              priorityLevel: 1
              preemptionCapability: 'MayPreempt'
              preemptionVulnerability: 'NotPreemptable'
            }
          }
        ]
      }
    ]
  }
}

// Log Analytics Workspace for monitoring (conditional deployment)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableMonitoring) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// IoT Hub for device management (conditional deployment)
resource iotHub 'Microsoft.Devices/IotHubs@2023-06-30' = if (enableIotIntegration) {
  name: iotHubName
  location: location
  tags: tags
  sku: {
    name: iotHubSku
    capacity: 1
  }
  properties: {
    eventHubEndpoints: {
      events: {
        retentionTimeInDays: 1
        partitionCount: 2
      }
    }
    routing: {
      endpoints: {
        serviceBusQueues: []
        serviceBusTopics: []
        eventHubs: []
        storageContainers: []
      }
      routes: []
      fallbackRoute: {
        name: '$fallback'
        source: 'DeviceMessages'
        condition: 'true'
        endpointNames: [
          'events'
        ]
        isEnabled: true
      }
    }
    messagingEndpoints: {
      fileNotifications: {
        lockDurationAsIso8601: 'PT1M'
        ttlAsIso8601: 'PT1H'
        maxDeliveryCount: 10
      }
    }
    enableFileUploadNotifications: false
    cloudToDevice: {
      maxDeliveryCount: 10
      defaultTtlAsIso8601: 'PT1H'
      feedback: {
        lockDurationAsIso8601: 'PT1M'
        ttlAsIso8601: 'PT1H'
        maxDeliveryCount: 10
      }
    }
    features: 'None'
  }
}

// Device Provisioning Service for automated device enrollment (conditional deployment)
resource deviceProvisioningService 'Microsoft.Devices/provisioningServices@2022-12-12' = if (enableIotIntegration) {
  name: deviceProvisioningServiceName
  location: location
  tags: tags
  sku: {
    name: 'S1'
    capacity: 1
  }
  properties: {
    state: 'Active'
    provisioningState: 'Succeeded'
    iotHubs: enableIotIntegration ? [
      {
        connectionString: 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=iothubowner;SharedAccessKey=${iotHub.listKeys().value[0].primaryKey}'
        location: location
      }
    ] : []
  }
}

// Container Registry for edge workloads (conditional deployment)
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = if (enableIotIntegration) {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: true
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('The resource ID of the mobile network')
output mobileNetworkId string = mobileNetwork.id

@description('The name of the mobile network')
output mobileNetworkName string = mobileNetwork.name

@description('The resource ID of the site')
output siteId string = site.id

@description('The name of the site')
output siteName string = site.name

@description('The resource IDs of the network slices')
output networkSliceIds array = [for i in range(0, length(networkSlices)): networkSlice[i].id]

@description('The resource IDs of the data networks')
output dataNetworkIds array = [for i in range(0, length(dataNetworks)): dataNetwork[i].id]

@description('The resource IDs of the services')
output serviceIds array = [for i in range(0, length(services)): service[i].id]

@description('The resource ID of the SIM policy')
output simPolicyId string = simPolicy.id

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = enableMonitoring ? logAnalyticsWorkspace.id : ''

@description('The connection string for the IoT Hub')
output iotHubConnectionString string = enableIotIntegration ? 'HostName=${iotHub.properties.hostName};SharedAccessKeyName=iothubowner;SharedAccessKey=${iotHub.listKeys().value[0].primaryKey}' : ''

@description('The resource ID of the IoT Hub')
output iotHubId string = enableIotIntegration ? iotHub.id : ''

@description('The resource ID of the Device Provisioning Service')
output deviceProvisioningServiceId string = enableIotIntegration ? deviceProvisioningService.id : ''

@description('The login server for the Container Registry')
output containerRegistryLoginServer string = enableIotIntegration ? containerRegistry.properties.loginServer : ''

@description('The resource ID of the Container Registry')
output containerRegistryId string = enableIotIntegration ? containerRegistry.id : ''

@description('Deployment summary with key information')
output deploymentSummary object = {
  mobileNetworkName: mobileNetwork.name
  siteName: site.name
  networkSliceCount: length(networkSlices)
  dataNetworkCount: length(dataNetworks)
  serviceCount: length(services)
  monitoringEnabled: enableMonitoring
  iotIntegrationEnabled: enableIotIntegration
  location: location
  tags: tags
}