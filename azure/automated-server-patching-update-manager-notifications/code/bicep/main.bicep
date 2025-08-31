// ==================================================
// Azure Automated Server Patching with Update Manager and Notifications
// ==================================================
// This Bicep template deploys a complete solution for automated server patching
// using Azure Update Manager with email notifications through Action Groups
// 
// Components:
// - Virtual Machine (Windows Server 2022) configured for automated patching
// - Maintenance Configuration for weekly patching schedule
// - Configuration Assignment linking VM to maintenance schedule
// - Action Group for email notifications
// - Activity Log Alerts for patch deployment monitoring
// ==================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Prefix for all resource names to ensure uniqueness')
param resourcePrefix string = 'patchdemo'

@description('Administrator username for the Virtual Machine')
param adminUsername string = 'azureuser'

@description('Administrator password for the Virtual Machine')
@secure()
param adminPassword string

@description('Email address for patch deployment notifications')
param notificationEmail string

@description('Virtual Machine size')
param vmSize string = 'Standard_B2s'

@description('Windows OS version for the VM')
@allowed([
  'Win2019Datacenter'
  'Win2022Datacenter'
  'Win2022DatacenterAzureEdition'
])
param windowsOSVersion string = 'Win2022Datacenter'

@description('Maintenance window start time (24-hour format, e.g., "02:00")')
param maintenanceStartTime string = '02:00'

@description('Maintenance window duration in hours (minimum 2 hours)')
@minValue(2)
@maxValue(8)
param maintenanceDurationHours int = 2

@description('Day of the week for maintenance (e.g., Saturday)')
@allowed([
  'Sunday'
  'Monday'
  'Tuesday'
  'Wednesday'
  'Thursday'
  'Friday'
  'Saturday'
])
param maintenanceDay string = 'Saturday'

@description('Time zone for maintenance schedule')
param maintenanceTimeZone string = 'Eastern Standard Time'

@description('Tags to apply to all resources')
param tags object = {
  Purpose: 'Recipe Demo'
  Environment: 'Demo'
  Solution: 'Automated Patching'
  CreatedBy: 'Bicep Template'
}

// Variables for resource names with uniqueness
var uniqueSuffix = uniqueString(resourceGroup().id)
var vmName = '${resourcePrefix}-vm-${uniqueSuffix}'
var maintenanceConfigName = '${resourcePrefix}-mc-${uniqueSuffix}'
var actionGroupName = '${resourcePrefix}-ag-${uniqueSuffix}'
var vnetName = '${resourcePrefix}-vnet-${uniqueSuffix}'
var subnetName = '${resourcePrefix}-subnet'
var nsgName = '${resourcePrefix}-nsg-${uniqueSuffix}'
var publicIpName = '${resourcePrefix}-pip-${uniqueSuffix}'
var nicName = '${resourcePrefix}-nic-${uniqueSuffix}'
var osDiskName = '${vmName}-osdisk'

// Calculate maintenance end time
var maintenanceEndTime = dateTimeAdd('1900-01-01T${maintenanceStartTime}:00', 'PT${maintenanceDurationHours}H', 'HH:mm')

// ==================================================
// NETWORKING RESOURCES
// ==================================================

// Network Security Group with RDP access
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowRDP'
        properties: {
          description: 'Allow RDP access for demonstration purposes'
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
    ]
  }
}

// Virtual Network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
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

// Public IP Address
resource publicIP 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: toLower('${resourcePrefix}-${uniqueSuffix}')
    }
  }
}

// Network Interface
resource networkInterface 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
          }
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}

// ==================================================
// VIRTUAL MACHINE
// ==================================================

// Virtual Machine configured for automated patching
resource virtualMachine 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: false // Disable automatic updates to use Update Manager
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
          automaticByPlatformSettings: {
            bypassPlatformSafetyChecksOnUserSchedule: true
          }
          assessmentMode: 'AutomaticByPlatform'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: windowsOSVersion
        version: 'latest'
      }
      osDisk: {
        name: osDiskName
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
          id: networkInterface.id
        }
      ]
    }
  }
}

// ==================================================
// MAINTENANCE CONFIGURATION
// ==================================================

// Maintenance Configuration for scheduled patching
resource maintenanceConfiguration 'Microsoft.Maintenance/maintenanceConfigurations@2023-10-01-preview' = {
  name: maintenanceConfigName
  location: location
  tags: tags
  properties: {
    maintenanceScope: 'InGuestPatch'
    visibility: 'Custom'
    installPatches: {
      windowsParameters: {
        classificationsToInclude: [
          'Critical'
          'Security'
          'UpdateRollup'
          'FeaturePack'
          'ServicePack'
          'Definition'
          'Tools'
          'Updates'
        ]
        kbNumbersToExclude: []
        kbNumbersToInclude: []
        excludeKbsRequiringReboot: false
      }
      rebootSetting: 'IfRequired'
    }
    maintenanceWindow: {
      startDateTime: '2025-08-02 ${maintenanceStartTime}:00'
      expirationDateTime: null
      duration: '0${maintenanceDurationHours}:00'
      timeZone: maintenanceTimeZone
      recurEvery: '1Week ${maintenanceDay}'
    }
  }
}

// Configuration Assignment to link VM with maintenance configuration
resource maintenanceAssignment 'Microsoft.Maintenance/configurationAssignments@2023-10-01-preview' = {
  name: 'MaintenanceAssignment-${uniqueSuffix}'
  scope: virtualMachine
  properties: {
    maintenanceConfigurationId: maintenanceConfiguration.id
    resourceId: virtualMachine.id
  }
}

// ==================================================
// MONITORING AND ALERTS
// ==================================================

// Action Group for email notifications
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'PatchAlert'
    enabled: true
    emailReceivers: [
      {
        name: 'EmailNotification'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// Activity Log Alert for Maintenance Configuration operations
resource maintenanceConfigAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'MaintenanceConfigAlert-${uniqueSuffix}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when maintenance configuration operations occur'
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Administrative'
        }
        {
          field: 'operationName'
          equals: 'Microsoft.Maintenance/maintenanceConfigurations/write'
        }
        {
          field: 'resourceGroup'
          equals: resourceGroup().name
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

// Activity Log Alert for Configuration Assignment operations
resource configAssignmentAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'ConfigAssignmentAlert-${uniqueSuffix}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when maintenance configuration assignments are created or updated'
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Administrative'
        }
        {
          field: 'operationName'
          equals: 'Microsoft.Maintenance/configurationAssignments/write'
        }
        {
          field: 'resourceGroup'
          equals: resourceGroup().name
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

// Activity Log Alert for Apply Updates operations
resource applyUpdatesAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'ApplyUpdatesAlert-${uniqueSuffix}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when update installation operations are performed'
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Administrative'
        }
        {
          field: 'operationName'
          equals: 'Microsoft.Maintenance/applyUpdates/write'
        }
        {
          field: 'resourceGroup'
          equals: resourceGroup().name
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

// ==================================================
// OUTPUTS
// ==================================================

@description('Resource group name where resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('Virtual Machine name')
output virtualMachineName string = virtualMachine.name

@description('Virtual Machine resource ID')
output virtualMachineId string = virtualMachine.id

@description('Public IP address of the VM')
output publicIPAddress string = publicIP.properties.ipAddress

@description('FQDN of the VM')
output vmFQDN string = publicIP.properties.dnsSettings.fqdn

@description('Maintenance Configuration name')
output maintenanceConfigurationName string = maintenanceConfiguration.name

@description('Maintenance Configuration resource ID')
output maintenanceConfigurationId string = maintenanceConfiguration.id

@description('Maintenance schedule details')
output maintenanceSchedule object = {
  startTime: maintenanceStartTime
  duration: '${maintenanceDurationHours} hours'
  dayOfWeek: maintenanceDay
  timeZone: maintenanceTimeZone
  nextMaintenance: '2025-08-02 ${maintenanceStartTime}:00 ${maintenanceTimeZone}'
}

@description('Action Group name for notifications')
output actionGroupName string = actionGroup.name

@description('Action Group resource ID')
output actionGroupId string = actionGroup.id

@description('Notification email address')
output notificationEmail string = notificationEmail

@description('Activity Log Alert names')
output activityLogAlerts array = [
  maintenanceConfigAlert.name
  configAssignmentAlert.name
  applyUpdatesAlert.name
]

@description('Connection information for the VM')
output connectionInfo object = {
  rdpConnection: 'mstsc /v:${publicIP.properties.dnsSettings.fqdn}'
  publicIP: publicIP.properties.ipAddress
  username: adminUsername
  note: 'Use the admin password you provided during deployment'
}

@description('Next steps for validating the deployment')
output nextSteps array = [
  'Connect to the VM using RDP with the provided connection information'
  'Check Windows Update settings to verify patch mode is set to AutomaticByPlatform'
  'Review the maintenance configuration in the Azure portal'
  'Monitor your email for activity log alerts related to maintenance operations'
  'Test the Action Group by triggering a test notification from the Azure portal'
]