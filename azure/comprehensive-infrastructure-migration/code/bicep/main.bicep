// ============================================================================
// Azure Infrastructure Migration Workflow with Resource Mover and Update Manager
// ============================================================================
// This Bicep template deploys the complete infrastructure for orchestrating
// migration workflows using Azure Resource Mover and Update Manager
// ============================================================================

@description('Prefix for all resource names to ensure uniqueness')
param resourcePrefix string = 'migration'

@description('Source region for migration')
param sourceRegion string = 'eastus'

@description('Target region for migration')
param targetRegion string = 'westus2'

@description('Environment tag for resources')
@allowed(['dev', 'test', 'staging', 'prod'])
param environment string = 'test'

@description('VM size for test infrastructure')
@allowed(['Standard_B1s', 'Standard_B2s', 'Standard_D2s_v3'])
param vmSize string = 'Standard_B2s'

@description('Admin username for virtual machines')
param adminUsername string = 'azureuser'

@description('SSH public key for VM authentication')
@secure()
param sshPublicKey string

@description('Maintenance window start time (24h format)')
param maintenanceWindowStartTime string = '03:00'

@description('Maintenance window duration in hours')
param maintenanceWindowDuration string = '02:00'

@description('Day of week for maintenance (0=Sunday, 6=Saturday)')
@minValue(0)
@maxValue(6)
param maintenanceWindowDayOfWeek int = 6

// Variables for resource naming
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var sourceResourceGroupName = '${resourcePrefix}-source-${uniqueSuffix}'
var targetResourceGroupName = '${resourcePrefix}-target-${uniqueSuffix}'
var moveCollectionName = '${resourcePrefix}-move-collection-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-law-${uniqueSuffix}'
var maintenanceConfigName = '${resourcePrefix}-maintenance-${uniqueSuffix}'
var workbookName = '${resourcePrefix}-workbook-${uniqueSuffix}'

// Common tags for all resources
var commonTags = {
  Environment: environment
  Purpose: 'migration-workflow'
  Solution: 'azure-resource-mover-update-manager'
  CreatedBy: 'bicep-template'
  LastModified: utcNow('yyyy-MM-dd')
}

// ============================================================================
// MONITORING AND LOGGING INFRASTRUCTURE
// ============================================================================

@description('Log Analytics Workspace for monitoring migration and update activities')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: sourceRegion
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
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

@description('Azure Workbook for migration monitoring dashboard')
resource migrationWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(workbookName)
  location: sourceRegion
  tags: commonTags
  kind: 'shared'
  properties: {
    displayName: 'Infrastructure Migration Monitoring'
    description: 'Comprehensive monitoring for Azure Resource Mover migration workflows and Update Manager compliance'
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        {
          type: 1
          content: {
            json: '# Infrastructure Migration Dashboard\n\nThis workbook provides comprehensive monitoring for Azure Resource Mover migration workflows and Update Manager compliance status.\n\n## Key Metrics\n- Migration operation status and progress\n- Resource dependency mapping\n- Update compliance across regions\n- Security patch status'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureActivity\n| where TimeGenerated > ago(24h)\n| where ResourceProvider == "Microsoft.Migrate"\n| summarize OperationCount = count() by OperationName, ResourceType\n| order by OperationCount desc'
            size: 0
            title: 'Migration Operations by Resource Type (Last 24h)'
            timeContext: {
              durationMs: 86400000
            }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [
              logAnalyticsWorkspace.id
            ]
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'Update\n| where TimeGenerated > ago(7d)\n| where Computer != ""\n| summarize ComplianceCount = count() by UpdateState\n| order by ComplianceCount desc'
            size: 0
            title: 'Update Compliance Status (Last 7 days)'
            timeContext: {
              durationMs: 604800000
            }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [
              logAnalyticsWorkspace.id
            ]
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureActivity\n| where TimeGenerated > ago(1d)\n| where ResourceProvider == "Microsoft.Migrate"\n| where ActivityStatus == "Failed"\n| project TimeGenerated, OperationName, ResourceGroup, ActivityStatus, Properties\n| order by TimeGenerated desc'
            size: 0
            title: 'Failed Migration Operations (Last 24h)'
            timeContext: {
              durationMs: 86400000
            }
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            crossComponentResources: [
              logAnalyticsWorkspace.id
            ]
          }
        }
      ]
    })
    category: 'workbook'
    sourceId: logAnalyticsWorkspace.id
  }
}

// ============================================================================
// SOURCE REGION INFRASTRUCTURE
// ============================================================================

@description('Virtual Network in source region for test infrastructure')
resource sourceVirtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${resourcePrefix}-vnet-source-${uniqueSuffix}'
  location: sourceRegion
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: sourceNetworkSecurityGroup.id
          }
        }
      }
    ]
    enableDdosProtection: false
  }
}

@description('Network Security Group for source region resources')
resource sourceNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${resourcePrefix}-nsg-source-${uniqueSuffix}'
  location: sourceRegion
  tags: commonTags
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
      {
        name: 'HTTP'
        properties: {
          priority: 1002
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      {
        name: 'HTTPS'
        properties: {
          priority: 1003
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

@description('Public IP for source region virtual machine')
resource sourcePublicIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${resourcePrefix}-pip-source-${uniqueSuffix}'
  location: sourceRegion
  tags: commonTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: '${resourcePrefix}-vm-source-${uniqueSuffix}'
    }
  }
}

@description('Network Interface for source region virtual machine')
resource sourceNetworkInterface 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${resourcePrefix}-nic-source-${uniqueSuffix}'
  location: sourceRegion
  tags: commonTags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${sourceVirtualNetwork.id}/subnets/default'
          }
          publicIPAddress: {
            id: sourcePublicIP.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: sourceNetworkSecurityGroup.id
    }
  }
}

@description('Virtual Machine in source region for migration testing')
resource sourceVirtualMachine 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${resourcePrefix}-vm-source-${uniqueSuffix}'
  location: sourceRegion
  tags: union(commonTags, {
    Role: 'migration-source'
    OS: 'Linux'
  })
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: '${resourcePrefix}-vm-source'
      adminUsername: adminUsername
      disablePasswordAuthentication: true
      linuxConfiguration: {
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
        disablePasswordAuthentication: true
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
        name: '${resourcePrefix}-disk-source-${uniqueSuffix}'
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
          id: sourceNetworkInterface.id
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

// ============================================================================
// AZURE RESOURCE MOVER CONFIGURATION
// ============================================================================

@description('Move Collection for orchestrating the migration workflow')
resource moveCollection 'Microsoft.Migrate/moveCollections@2023-08-01' = {
  name: moveCollectionName
  location: sourceRegion
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sourceRegion: sourceRegion
    targetRegion: targetRegion
    moveType: 'RegionToRegion'
    version: '2023-08-01'
  }
}

// ============================================================================
// TARGET REGION INFRASTRUCTURE PREPARATION
// ============================================================================

@description('Target Resource Group for migrated resources')
resource targetResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: targetResourceGroupName
  location: targetRegion
  tags: commonTags
  scope: subscription()
}

@description('Maintenance Configuration for Update Manager in target region')
resource maintenanceConfiguration 'Microsoft.Maintenance/maintenanceConfigurations@2023-10-01-preview' = {
  name: maintenanceConfigName
  location: targetRegion
  tags: commonTags
  properties: {
    maintenanceScope: 'InGuestPatch'
    maintenanceWindow: {
      startDateTime: '2024-01-15 ${maintenanceWindowStartTime}:00'
      duration: maintenanceWindowDuration
      timeZone: 'UTC'
      recurEvery: '1Week'
      expirationDateTime: null
    }
    visibility: 'Custom'
    installPatches: {
      rebootSetting: 'IfRequired'
      linuxParameters: {
        classificationsToInclude: [
          'Critical'
          'Security'
        ]
        packageNameMasksToExclude: []
        packageNameMasksToInclude: []
      }
    }
    extensionProperties: {
      InGuestPatchMode: 'User'
    }
  }
}

// ============================================================================
// RBAC AND PERMISSIONS
// ============================================================================

@description('Role assignment for Move Collection managed identity')
resource moveCollectionRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(moveCollection.id, 'contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor role
    principalId: moveCollection.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Role assignment for Update Manager on target resource group')
resource updateManagerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(targetResourceGroup.id, 'update-manager')
  scope: targetResourceGroup
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor role
    principalId: moveCollection.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// MONITORING EXTENSIONS
// ============================================================================

@description('Azure Monitor Agent extension for source VM')
resource azureMonitorAgentSource 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: sourceVirtualMachine
  name: 'AzureMonitorLinuxAgent'
  location: sourceRegion
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.25'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: {
      workspaceId: logAnalyticsWorkspace.properties.customerId
    }
    protectedSettings: {
      workspaceKey: logAnalyticsWorkspace.listKeys().primarySharedKey
    }
  }
}

@description('Data Collection Rule for VM monitoring')
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: '${resourcePrefix}-dcr-${uniqueSuffix}'
  location: sourceRegion
  tags: commonTags
  properties: {
    dataSources: {
      performanceCounters: [
        {
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\Memory\\Available MBytes'
            '\\Logical Disk(_Total)\\Disk Reads/sec'
            '\\Logical Disk(_Total)\\Disk Writes/sec'
            '\\Network Interface(*)\\Bytes Total/sec'
          ]
          name: 'perfCounterDataSource60'
        }
      ]
      syslog: [
        {
          streams: [
            'Microsoft-Syslog'
          ]
          facilityNames: [
            'auth'
            'authpriv'
            'cron'
            'daemon'
            'kern'
            'lpr'
            'mail'
            'mark'
            'news'
            'syslog'
            'user'
            'uucp'
          ]
          logLevels: [
            'Alert'
            'Critical'
            'Emergency'
            'Error'
            'Warning'
          ]
          name: 'syslogDataSource'
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'la-destination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Perf'
          'Microsoft-Syslog'
        ]
        destinations: [
          'la-destination'
        ]
      }
    ]
  }
}

@description('Data Collection Rule Association for source VM')
resource dataCollectionRuleAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: '${resourcePrefix}-dcra-${uniqueSuffix}'
  scope: sourceVirtualMachine
  properties: {
    dataCollectionRuleId: dataCollectionRule.id
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Resource ID of the Move Collection')
output moveCollectionId string = moveCollection.id

@description('Name of the Move Collection')
output moveCollectionName string = moveCollection.name

@description('Source region for the migration')
output sourceRegion string = sourceRegion

@description('Target region for the migration')
output targetRegion string = targetRegion

@description('Log Analytics Workspace ID for monitoring')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace Customer ID')
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('Maintenance Configuration ID for Update Manager')
output maintenanceConfigurationId string = maintenanceConfiguration.id

@description('Source VM Resource ID')
output sourceVmId string = sourceVirtualMachine.id

@description('Source VM Name')
output sourceVmName string = sourceVirtualMachine.name

@description('Source VM Public IP')
output sourceVmPublicIp string = sourcePublicIP.properties.ipAddress

@description('Source VM FQDN')
output sourceVmFqdn string = sourcePublicIP.properties.dnsSettings.fqdn

@description('Target Resource Group Name')
output targetResourceGroupName string = targetResourceGroupName

@description('Azure Workbook Name')
output workbookName string = migrationWorkbook.properties.displayName

@description('Network Security Group ID')
output networkSecurityGroupId string = sourceNetworkSecurityGroup.id

@description('Virtual Network ID')
output virtualNetworkId string = sourceVirtualNetwork.id

@description('Data Collection Rule ID')
output dataCollectionRuleId string = dataCollectionRule.id

@description('Deployment Summary')
output deploymentSummary object = {
  resourcePrefix: resourcePrefix
  uniqueSuffix: uniqueSuffix
  sourceRegion: sourceRegion
  targetRegion: targetRegion
  environment: environment
  vmSize: vmSize
  resourcesCreated: {
    moveCollection: moveCollectionName
    sourceVm: sourceVirtualMachine.name
    logAnalyticsWorkspace: logAnalyticsWorkspaceName
    maintenanceConfiguration: maintenanceConfigName
    workbook: migrationWorkbook.properties.displayName
  }
}