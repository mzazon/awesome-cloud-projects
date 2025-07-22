// =======================================================================
// Azure Network Performance Monitoring Infrastructure
// =======================================================================
// This template deploys a comprehensive network performance monitoring
// solution using Azure Network Watcher and Application Insights
// =======================================================================

@description('Primary Azure region for resource deployment')
param location string = resourceGroup().location

@description('Environment name for resource naming (e.g., dev, staging, prod)')
param environmentName string

@description('Project or workload name for resource naming')
param projectName string

@description('Administrator username for virtual machines')
@secure()
param adminUsername string

@description('Administrator password for virtual machines')
@secure()
param adminPassword string

@description('SSH public key for Linux VM authentication')
param sshPublicKey string

@description('Virtual machine size for source and destination VMs')
param vmSize string = 'Standard_B2s'

@description('VM operating system type')
@allowed(['Ubuntu', 'Windows'])
param osType string = 'Ubuntu'

@description('Log Analytics workspace pricing tier')
@allowed(['PerGB2018', 'Free', 'Standalone', 'PerNode'])
param logAnalyticsSku string = 'PerGB2018'

@description('Log Analytics data retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 90

@description('Connection Monitor test frequency in seconds')
@minValue(30)
@maxValue(1800)
param connectionMonitorFrequency int = 60

@description('Network latency threshold in milliseconds for alerting')
@minValue(100)
@maxValue(5000)
param latencyThresholdMs int = 1000

@description('Connection failure threshold percentage for alerting')
@minValue(1)
@maxValue(100)
param failureThresholdPercent int = 20

@description('Enable NSG Flow Logs')
param enableFlowLogs bool = true

@description('Flow logs retention period in days')
@minValue(1)
@maxValue(365)
param flowLogsRetentionDays int = 30

@description('Alert notification email address')
param notificationEmail string

@description('Enable packet capture configuration')
param enablePacketCapture bool = true

@description('Resource tags for all created resources')
param tags object = {
  Environment: environmentName
  Project: projectName
  Purpose: 'NetworkMonitoring'
  ManagedBy: 'Bicep'
}

// =======================================================================
// Variables
// =======================================================================

var uniqueSuffix = substring(uniqueString(resourceGroup().id, deployment().name), 0, 6)
var namingPrefix = '${projectName}-${environmentName}'

var vnetName = '${namingPrefix}-vnet'
var subnetName = '${namingPrefix}-subnet'
var nsgName = '${namingPrefix}-nsg'
var sourceVmName = '${namingPrefix}-vm-source'
var destVmName = '${namingPrefix}-vm-dest'
var logAnalyticsWorkspaceName = '${namingPrefix}-law-${uniqueSuffix}'
var appInsightsName = '${namingPrefix}-ai-${uniqueSuffix}'
var storageAccountName = '${namingPrefix}st${uniqueSuffix}'
var connectionMonitorName = '${namingPrefix}-cm-${uniqueSuffix}'
var actionGroupName = '${namingPrefix}-ag-${uniqueSuffix}'

var vnetAddressPrefix = '10.0.0.0/16'
var subnetAddressPrefix = '10.0.1.0/24'

var vmImage = osType == 'Ubuntu' ? {
  publisher: 'Canonical'
  offer: '0001-com-ubuntu-server-jammy'
  sku: '22_04-lts-gen2'
  version: 'latest'
} : {
  publisher: 'MicrosoftWindowsServer'
  offer: 'WindowsServer'
  sku: '2022-datacenter-azure-edition'
  version: 'latest'
}

var networkWatcherName = 'NetworkWatcher_${location}'
var networkWatcherResourceGroup = 'NetworkWatcherRG'

// =======================================================================
// Storage Account for Flow Logs and Packet Capture
// =======================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Create blob container for packet captures
resource packetCaptureContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = if (enablePacketCapture) {
  name: '${storageAccount.name}/default/packet-captures'
  properties: {
    publicAccess: 'None'
  }
}

// =======================================================================
// Log Analytics Workspace
// =======================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsSku
    }
    retentionInDays: logAnalyticsRetentionDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// =======================================================================
// Application Insights
// =======================================================================

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =======================================================================
// Virtual Network and Network Security Group
// =======================================================================

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          description: 'Allow SSH traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHTTP'
        properties: {
          description: 'Allow HTTP traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1001
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHTTPS'
        properties: {
          description: 'Allow HTTPS traffic'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1002
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowICMP'
        properties: {
          description: 'Allow ICMP traffic for ping tests'
          protocol: 'Icmp'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1003
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowRDP'
        properties: {
          description: 'Allow RDP traffic for Windows VMs'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1004
          direction: 'Inbound'
        }
      }
    ]
  }
}

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

// =======================================================================
// NSG Flow Logs Configuration
// =======================================================================

resource nsgFlowLogs 'Microsoft.Network/networkWatchers/flowLogs@2023-09-01' = if (enableFlowLogs) {
  name: '${networkWatcherName}/fl-${nsgName}-${uniqueSuffix}'
  location: location
  tags: tags
  properties: {
    targetResourceId: networkSecurityGroup.id
    storageId: storageAccount.id
    enabled: true
    format: {
      type: 'JSON'
      version: 2
    }
    flowAnalyticsConfiguration: {
      networkWatcherFlowAnalyticsConfiguration: {
        enabled: true
        workspaceResourceId: logAnalyticsWorkspace.id
        trafficAnalyticsInterval: 10
      }
    }
    retentionPolicy: {
      days: flowLogsRetentionDays
      enabled: true
    }
  }
}

// =======================================================================
// Virtual Machine Network Interfaces
// =======================================================================

resource sourceVmPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${sourceVmName}-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${sourceVmName}-${uniqueSuffix}'
    }
  }
}

resource sourceVmNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${sourceVmName}-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: sourceVmPublicIp.id
          }
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
  }
}

resource destVmPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${destVmName}-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${destVmName}-${uniqueSuffix}'
    }
  }
}

resource destVmNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${destVmName}-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: destVmPublicIp.id
          }
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
  }
}

// =======================================================================
// Virtual Machines
// =======================================================================

resource sourceVm 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: sourceVmName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: sourceVmName
      adminUsername: adminUsername
      adminPassword: osType == 'Windows' ? adminPassword : null
      linuxConfiguration: osType == 'Ubuntu' ? {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      } : null
    }
    storageProfile: {
      imageReference: vmImage
      osDisk: {
        name: '${sourceVmName}-osdisk'
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
          id: sourceVmNic.id
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

resource destVm 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: destVmName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: destVmName
      adminUsername: adminUsername
      adminPassword: osType == 'Windows' ? adminPassword : null
      linuxConfiguration: osType == 'Ubuntu' ? {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      } : null
    }
    storageProfile: {
      imageReference: vmImage
      osDisk: {
        name: '${destVmName}-osdisk'
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
          id: destVmNic.id
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

// =======================================================================
// Network Watcher Extensions
// =======================================================================

resource sourceVmNetworkWatcherExtension 'Microsoft.Compute/virtualMachines/extensions@2023-07-01' = {
  parent: sourceVm
  name: osType == 'Ubuntu' ? 'NetworkWatcherAgentLinux' : 'NetworkWatcherAgentWindows'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.NetworkWatcher'
    type: osType == 'Ubuntu' ? 'NetworkWatcherAgentLinux' : 'NetworkWatcherAgentWindows'
    typeHandlerVersion: '1.4'
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {}
  }
}

resource destVmNetworkWatcherExtension 'Microsoft.Compute/virtualMachines/extensions@2023-07-01' = {
  parent: destVm
  name: osType == 'Ubuntu' ? 'NetworkWatcherAgentLinux' : 'NetworkWatcherAgentWindows'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.NetworkWatcher'
    type: osType == 'Ubuntu' ? 'NetworkWatcherAgentLinux' : 'NetworkWatcherAgentWindows'
    typeHandlerVersion: '1.4'
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {}
  }
}

// =======================================================================
// Connection Monitor
// =======================================================================

resource connectionMonitor 'Microsoft.Network/networkWatchers/connectionMonitors@2023-09-01' = {
  name: '${networkWatcherName}/${connectionMonitorName}'
  location: location
  tags: tags
  properties: {
    endpoints: [
      {
        name: 'source-endpoint'
        type: 'AzureVM'
        resourceId: sourceVm.id
      }
      {
        name: 'dest-endpoint'
        type: 'AzureVM'
        resourceId: destVm.id
      }
      {
        name: 'external-endpoint'
        type: 'ExternalAddress'
        address: 'www.microsoft.com'
      }
    ]
    testConfigurations: [
      {
        name: 'tcp-test'
        testFrequencySec: connectionMonitorFrequency
        protocol: 'TCP'
        tcpConfiguration: {
          port: 80
          disableTraceRoute: false
        }
        successThreshold: {
          checksFailedPercent: failureThresholdPercent
          roundTripTimeMs: latencyThresholdMs
        }
      }
      {
        name: 'icmp-test'
        testFrequencySec: connectionMonitorFrequency
        protocol: 'ICMP'
        icmpConfiguration: {
          disableTraceRoute: false
        }
        successThreshold: {
          checksFailedPercent: 10
          roundTripTimeMs: 500
        }
      }
    ]
    testGroups: [
      {
        name: 'vm-to-vm-tests'
        sources: ['source-endpoint']
        destinations: ['dest-endpoint']
        testConfigurations: ['tcp-test', 'icmp-test']
      }
      {
        name: 'vm-to-external-tests'
        sources: ['source-endpoint']
        destinations: ['external-endpoint']
        testConfigurations: ['tcp-test', 'icmp-test']
      }
    ]
    outputs: [
      {
        type: 'Workspace'
        workspaceSettings: {
          workspaceResourceId: logAnalyticsWorkspace.id
        }
      }
    ]
  }
  dependsOn: [
    sourceVmNetworkWatcherExtension
    destVmNetworkWatcherExtension
  ]
}

// =======================================================================
// Action Group for Alerts
// =======================================================================

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'NetAlert'
    enabled: true
    emailReceivers: [
      {
        name: 'Admin'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    armRoleReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    eventHubReceivers: []
  }
}

// =======================================================================
// Monitoring Alerts
// =======================================================================

resource networkLatencyAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'High Network Latency Alert'
  location: location
  tags: tags
  properties: {
    description: 'Alert when network latency exceeds threshold'
    displayName: 'High Network Latency Alert'
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    severity: 2
    criteria: {
      allOf: [
        {
          query: 'NetworkMonitoring | where TimeGenerated > ago(5m) | where TestResult == "Failed" and LatencyMs > ${latencyThresholdMs} | summarize count() by TestName'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
    scopes: [
      logAnalyticsWorkspace.id
    ]
  }
}

resource networkConnectivityAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'Network Connectivity Failure'
  location: location
  tags: tags
  properties: {
    description: 'Alert when network connectivity tests fail'
    displayName: 'Network Connectivity Failure'
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    severity: 1
    criteria: {
      allOf: [
        {
          query: 'NetworkMonitoring | where TimeGenerated > ago(5m) | where TestResult == "Failed" | summarize FailureCount = count() by TestName | where FailureCount > 2'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
    scopes: [
      logAnalyticsWorkspace.id
    ]
  }
}

// =======================================================================
// Outputs
// =======================================================================

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Storage Account name for flow logs and packet capture')
output storageAccountName string = storageAccount.name

@description('Source VM name')
output sourceVmName string = sourceVm.name

@description('Destination VM name')
output destVmName string = destVm.name

@description('Source VM public IP address')
output sourceVmPublicIp string = sourceVmPublicIp.properties.ipAddress

@description('Destination VM public IP address')
output destVmPublicIp string = destVmPublicIp.properties.ipAddress

@description('Connection Monitor name')
output connectionMonitorName string = connectionMonitorName

@description('Network Security Group name')
output networkSecurityGroupName string = networkSecurityGroup.name

@description('Virtual Network name')
output virtualNetworkName string = virtualNetwork.name

@description('Action Group name for alerts')
output actionGroupName string = actionGroup.name

@description('Flow logs enabled status')
output flowLogsEnabled bool = enableFlowLogs

@description('Packet capture enabled status')
output packetCaptureEnabled bool = enablePacketCapture

@description('Network Watcher resource group')
output networkWatcherResourceGroup string = networkWatcherResourceGroup

@description('Network Watcher name')
output networkWatcherName string = networkWatcherName