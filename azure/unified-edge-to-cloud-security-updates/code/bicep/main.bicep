// Unified Edge-to-Cloud Security Updates with IoT Device Update and Update Manager
// This Bicep template deploys the complete infrastructure for coordinated security updates
// across IoT edge devices and cloud infrastructure using Azure native services.

targetScope = 'resourceGroup'

// ================================
// PARAMETERS
// ================================

@description('The primary location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = take(uniqueString(resourceGroup().id), 6)

@description('Environment tag for resources (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'iot-updates'
  environment: environment
  deployedBy: 'bicep'
  recipe: 'orchestrating-edge-to-cloud-security-updates'
}

@description('IoT Hub SKU settings')
param iotHubSku object = {
  name: 'S1'
  capacity: 1
}

@description('Storage account settings')
param storageAccountSku string = 'Standard_LRS'

@description('Virtual machine settings for Update Manager demonstration')
param vmConfig object = {
  size: 'Standard_B2s'
  adminUsername: 'azureuser'
  enableUpdateManager: true
  osDiskType: 'Standard_LRS'
}

@description('Log Analytics workspace retention in days')
param logAnalyticsRetentionDays int = 30

@description('Enable monitoring dashboard creation')
param enableMonitoringDashboard bool = true

@description('Device Update account location (must support Device Update service)')
param deviceUpdateLocation string = location

// ================================
// VARIABLES
// ================================

var resourceNames = {
  iotHub: 'iothub-${uniqueSuffix}'
  deviceUpdateAccount: 'deviceupdate-${uniqueSuffix}'
  deviceUpdateInstance: 'deviceupdate-instance-${uniqueSuffix}'
  storageAccount: 'stdevupdate${uniqueSuffix}'
  logAnalyticsWorkspace: 'law-iot-updates-${uniqueSuffix}'
  vmName: 'vm-update-test-${uniqueSuffix}'
  vmNetworkSecurityGroup: 'nsg-vm-${uniqueSuffix}'
  vmVirtualNetwork: 'vnet-vm-${uniqueSuffix}'
  vmSubnet: 'subnet-vm'
  vmPublicIp: 'pip-vm-${uniqueSuffix}'
  vmNetworkInterface: 'nic-vm-${uniqueSuffix}'
  logicAppWorkflow: 'update-orchestration-workflow-${uniqueSuffix}'
  dashboardName: 'IoT-Updates-Dashboard-${uniqueSuffix}'
}

var networkConfig = {
  vnetAddressPrefix: '10.0.0.0/16'
  subnetAddressPrefix: '10.0.1.0/24'
}

// ================================
// LOG ANALYTICS WORKSPACE
// ================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// ================================
// STORAGE ACCOUNT
// ================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Allow'
    }
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// ================================
// IOT HUB
// ================================

resource iotHub 'Microsoft.Devices/IotHubs@2023-06-30' = {
  name: resourceNames.iotHub
  location: location
  tags: tags
  sku: {
    name: iotHubSku.name
    capacity: iotHubSku.capacity
  }
  properties: {
    eventHubEndpoints: {
      events: {
        retentionTimeInDays: 1
        partitionCount: 2
      }
    }
    features: 'None'
    enableFileUploadNotifications: false
    messagingEndpoints: {
      fileNotifications: {
        lockDurationAsIso8601: 'PT1M'
        ttlAsIso8601: 'PT1H'
        maxDeliveryCount: 10
      }
    }
    cloudToDevice: {
      maxDeliveryCount: 10
      defaultTtlAsIso8601: 'PT1H'
      feedback: {
        lockDurationAsIso8601: 'PT1M'
        ttlAsIso8601: 'PT1H'
        maxDeliveryCount: 10
      }
    }
  }
}

// ================================
// DEVICE UPDATE ACCOUNT
// ================================

resource deviceUpdateAccount 'Microsoft.DeviceUpdate/accounts@2023-07-01' = {
  name: resourceNames.deviceUpdateAccount
  location: deviceUpdateLocation
  tags: tags
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// ================================
// DEVICE UPDATE INSTANCE
// ================================

resource deviceUpdateInstance 'Microsoft.DeviceUpdate/accounts/instances@2023-07-01' = {
  parent: deviceUpdateAccount
  name: resourceNames.deviceUpdateInstance
  location: deviceUpdateLocation
  tags: tags
  properties: {
    iotHubs: [
      {
        resourceId: iotHub.id
      }
    ]
    enableDiagnostics: true
  }
}

// ================================
// NETWORKING FOR VM
// ================================

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: resourceNames.vmVirtualNetwork
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        networkConfig.vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: resourceNames.vmSubnet
        properties: {
          addressPrefix: networkConfig.subnetAddressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: resourceNames.vmNetworkSecurityGroup
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          priority: 1001
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: resourceNames.vmPublicIp
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: resourceNames.vmNetworkInterface
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
          subnet: {
            id: '${virtualNetwork.id}/subnets/${resourceNames.vmSubnet}'
          }
        }
      }
    ]
  }
}

// ================================
// VIRTUAL MACHINE FOR UPDATE MANAGER
// ================================

resource virtualMachine 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: resourceNames.vmName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmConfig.size
    }
    osProfile: {
      computerName: resourceNames.vmName
      adminUsername: vmConfig.adminUsername
      disablePasswordAuthentication: true
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${vmConfig.adminUsername}/.ssh/authorized_keys'
              keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC...' // This should be replaced with actual public key
            }
          ]
        }
        patchSettings: {
          patchMode: vmConfig.enableUpdateManager ? 'AutomaticByPlatform' : 'ImageDefault'
          assessmentMode: 'AutomaticByPlatform'
          automaticByPlatformSettings: {
            rebootSetting: 'IfRequired'
          }
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
          storageAccountType: vmConfig.osDiskType
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: storageAccount.properties.primaryEndpoints.blob
      }
    }
  }
}

// ================================
// LOGIC APP FOR ORCHESTRATION
// ================================

resource logicAppWorkflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: resourceNames.logicAppWorkflow
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                updateType: {
                  type: 'string'
                  enum: ['infrastructure', 'devices', 'coordinated']
                }
                targetDevices: {
                  type: 'array'
                  items: {
                    type: 'string'
                  }
                }
              }
            }
          }
        }
      }
      actions: {
        checkInfrastructure: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: 'https://management.azure.com/subscriptions/@{subscription().subscriptionId}/resourceGroups/@{resourceGroup().name}/providers/Microsoft.Maintenance/updates'
            authentication: {
              type: 'ManagedServiceIdentity'
            }
          }
        }
        deployDeviceUpdates: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://management.azure.com/subscriptions/@{subscription().subscriptionId}/resourceGroups/@{resourceGroup().name}/providers/Microsoft.DeviceUpdate/accounts/${resourceNames.deviceUpdateAccount}/instances/${resourceNames.deviceUpdateInstance}/deployments'
            authentication: {
              type: 'ManagedServiceIdentity'
            }
            body: {
              deviceGroupType: 'DeviceGroupDefinitions'
              deviceGroupDefinition: [
                'deviceManufacturer'
              ]
              updateId: {
                provider: 'Contoso'
                name: 'SecurityPatch'
                version: '1.0.0'
              }
              startDateTime: '@{utcNow()}'
            }
          }
          runAfter: {
            checkInfrastructure: ['Succeeded']
          }
        }
        logDeploymentStatus: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://${logAnalyticsWorkspace.properties.customerId}.ods.opinsights.azure.com/api/logs'
            headers: {
              'Content-Type': 'application/json'
              'Log-Type': 'UpdateOrchestration'
            }
            body: {
              timestamp: '@{utcNow()}'
              updateType: '@{triggerBody()?[\'updateType\']}'
              status: 'Completed'
              resourceGroup: '@{resourceGroup().name}'
            }
          }
          runAfter: {
            deployDeviceUpdates: ['Succeeded', 'Failed']
          }
        }
      }
      outputs: {}
    }
  }
}

// ================================
// MONITORING ALERTS
// ================================

resource deviceUpdateFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'DeviceUpdateFailures'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when device updates fail'
    severity: 2
    enabled: true
    scopes: [
      deviceUpdateAccount.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'FailedUpdates'
          metricNamespace: 'Microsoft.DeviceUpdate/accounts'
          metricName: 'FailedUpdates'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Count'
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

resource actionGroup 'Microsoft.Insights/actionGroups@2022-06-01' = {
  name: 'UpdateFailureActionGroup'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'UpdateFail'
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

// ================================
// MONITORING DASHBOARD (Optional)
// ================================

resource dashboard 'Microsoft.Portal/dashboards@2020-09-01-preview' = if (enableMonitoringDashboard) {
  name: resourceNames.dashboardName
  location: location
  tags: union(tags, {
    'hidden-title': 'IoT Edge to Cloud Updates Dashboard'
  })
  properties: {
    lenses: [
      {
        order: 0
        parts: [
          {
            position: {
              x: 0
              y: 0
              rowSpan: 4
              colSpan: 6
            }
            metadata: {
              inputs: [
                {
                  name: 'resourceTypeMode'
                  isOptional: true
                }
                {
                  name: 'ComponentId'
                  value: {
                    Name: resourceNames.deviceUpdateAccount
                    SubscriptionId: subscription().subscriptionId
                    ResourceGroup: resourceGroup().name
                  }
                  isOptional: true
                }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              settings: {
                content: {
                  options: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: {
                            id: deviceUpdateAccount.id
                          }
                          name: 'TotalUpdates'
                          aggregationType: 7
                          namespace: 'microsoft.deviceupdate/accounts'
                          metricVisualization: {
                            displayName: 'Total Updates'
                          }
                        }
                      ]
                      title: 'Device Update Activity'
                      titleKind: 2
                      visualization: {
                        chartType: 2
                      }
                      openBladeOnClick: {
                        openBlade: true
                      }
                    }
                  }
                }
              }
            }
          }
        ]
      }
    ]
    metadata: {
      model: {
        timeRange: {
          value: {
            relative: {
              duration: 24
              timeUnit: 1
            }
          }
          type: 'MsPortalFx.Composition.Configuration.ValueTypes.TimeRange'
        }
        filterLocale: {
          value: 'en-us'
        }
        filters: {
          value: {
            MsPortalFx_TimeRange: {
              model: {
                format: 'utc'
                granularity: 'auto'
                relative: '24h'
              }
              displayCache: {
                name: 'UTC Time'
                value: 'Past 24 hours'
              }
              filteredPartIds: []
            }
          }
        }
      }
    }
  }
}

// ================================
// OUTPUTS
// ================================

@description('The resource ID of the IoT Hub')
output iotHubId string = iotHub.id

@description('The IoT Hub hostname for device connections')
output iotHubHostname string = iotHub.properties.hostName

@description('The resource ID of the Device Update account')
output deviceUpdateAccountId string = deviceUpdateAccount.id

@description('The name of the Device Update instance')
output deviceUpdateInstanceName string = deviceUpdateInstance.name

@description('The resource ID of the storage account')
output storageAccountId string = storageAccount.id

@description('The primary endpoint URL for the storage account')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The workspace ID for Log Analytics queries')
output logAnalyticsWorkspaceGuid string = logAnalyticsWorkspace.properties.customerId

@description('The resource ID of the virtual machine for Update Manager testing')
output virtualMachineId string = virtualMachine.id

@description('The public IP address of the virtual machine')
output virtualMachinePublicIp string = publicIp.properties.ipAddress

@description('The resource ID of the Logic App workflow for update orchestration')
output logicAppWorkflowId string = logicAppWorkflow.id

@description('The trigger URL for the Logic App workflow')
output logicAppTriggerUrl string = listCallbackUrl('${logicAppWorkflow.id}/triggers/manual', '2019-05-01').value

@description('The resource ID of the monitoring dashboard')
output dashboardId string = enableMonitoringDashboard ? dashboard.id : ''

@description('Connection information for validation and testing')
output connectionInfo object = {
  resourceGroup: resourceGroup().name
  subscription: subscription().subscriptionId
  iotHubName: resourceNames.iotHub
  deviceUpdateAccount: resourceNames.deviceUpdateAccount
  deviceUpdateInstance: resourceNames.deviceUpdateInstance
  storageAccountName: resourceNames.storageAccount
  vmName: resourceNames.vmName
  logAnalyticsWorkspaceName: resourceNames.logAnalyticsWorkspace
}