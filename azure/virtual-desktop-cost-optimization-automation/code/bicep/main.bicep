// ============================================================================
// Azure Virtual Desktop Cost Optimization with Reserved VM Instances
// ============================================================================
// This Bicep template deploys a cost-optimized Azure Virtual Desktop environment
// with auto-scaling capabilities and cost management integration.

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Prefix for all resource names')
@minLength(3)
@maxLength(10)
param resourcePrefix string

@description('Environment type (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Administrator username for VMs')
param adminUsername string

@description('Administrator password for VMs')
@secure()
param adminPassword string

@description('VM SKU for AVD session hosts')
@allowed(['Standard_D2s_v3', 'Standard_D4s_v3', 'Standard_D8s_v3', 'Standard_D16s_v3'])
param vmSku string = 'Standard_D2s_v3'

@description('Initial number of VMs in the scale set')
@minValue(1)
@maxValue(10)
param initialVmCount int = 2

@description('Minimum number of VMs in auto-scaling')
@minValue(1)
@maxValue(5)
param minVmCount int = 1

@description('Maximum number of VMs in auto-scaling')
@minValue(2)
@maxValue(20)
param maxVmCount int = 10

@description('Maximum sessions per VM')
@minValue(1)
@maxValue(50)
param maxSessionLimit int = 10

@description('Monthly budget amount in USD')
@minValue(100)
@maxValue(10000)
param budgetAmount int = 1000

@description('Department tags for cost attribution')
param departmentTags object = {
  finance: 'Finance Department'
  engineering: 'Engineering Department'
  marketing: 'Marketing Department'
}

// ============================================================================
// VARIABLES
// ============================================================================

var uniqueSuffix = take(uniqueString(resourceGroup().id), 6)
var commonTags = {
  Environment: environment
  Project: 'AVD-Cost-Optimization'
  CreatedBy: 'Bicep-Template'
  LastUpdated: utcNow('yyyy-MM-dd')
}

// Resource names
var avdWorkspaceName = '${resourcePrefix}-avd-workspace-${uniqueSuffix}'
var hostPoolName = '${resourcePrefix}-hp-cost-optimized-${uniqueSuffix}'
var applicationGroupName = '${resourcePrefix}-ag-desktop-${uniqueSuffix}'
var storageAccountName = '${resourcePrefix}costopt${uniqueSuffix}'
var logicAppName = '${resourcePrefix}-la-cost-optimizer-${uniqueSuffix}'
var functionAppName = '${resourcePrefix}-func-ri-analyzer-${uniqueSuffix}'
var budgetName = '${resourcePrefix}-budget-avd-${uniqueSuffix}'
var vnetName = '${resourcePrefix}-vnet-avd-${uniqueSuffix}'
var vmssName = '${resourcePrefix}-vmss-avd-${uniqueSuffix}'
var lawName = '${resourcePrefix}-law-avd-${uniqueSuffix}'
var appServicePlanName = '${resourcePrefix}-asp-${uniqueSuffix}'

// ============================================================================
// NETWORKING RESOURCES
// ============================================================================

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: union(commonTags, {
    ResourceType: 'Networking'
    Department: 'Shared'
  })
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'subnet-avd'
        properties: {
          addressPrefix: '10.0.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// ============================================================================
// STORAGE RESOURCES
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: union(commonTags, {
    ResourceType: 'Storage'
    Department: 'Shared'
    Purpose: 'Cost-Reporting'
  })
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
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
  }
}

resource costAnalysisContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storageAccount.name}/default/cost-analysis'
  properties: {
    publicAccess: 'None'
  }
}

// ============================================================================
// LOG ANALYTICS WORKSPACE
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: location
  tags: union(commonTags, {
    ResourceType: 'Monitoring'
    Department: 'Shared'
    Purpose: 'AVD-Monitoring'
  })
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

// ============================================================================
// AZURE VIRTUAL DESKTOP RESOURCES
// ============================================================================

resource avdWorkspace 'Microsoft.DesktopVirtualization/workspaces@2023-09-05' = {
  name: avdWorkspaceName
  location: location
  tags: union(commonTags, {
    ResourceType: 'Virtual-Desktop'
    Department: 'Shared'
    Purpose: 'Virtual-Desktop-Workspace'
  })
  properties: {
    description: 'Cost-optimized virtual desktop workspace'
    friendlyName: 'Cost Optimized AVD Workspace'
  }
}

resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2023-09-05' = {
  name: hostPoolName
  location: location
  tags: union(commonTags, {
    ResourceType: 'Virtual-Desktop'
    Department: 'Shared'
    WorkloadType: 'Pooled'
    CostCenter: '100'
  })
  properties: {
    hostPoolType: 'Pooled'
    loadBalancerType: 'BreadthFirst'
    maxSessionLimit: maxSessionLimit
    personalDesktopAssignmentType: 'Automatic'
    preferredAppGroupType: 'Desktop'
    startVMOnConnect: true
    validationEnvironment: false
    customRdpProperty: 'drivestoredirect:s:*;audiomode:i:0;videoplaybackmode:i:1;redirectclipboard:i:1;redirectprinters:i:1;devicestoredirect:s:*;redirectcomports:i:1;redirectsmartcards:i:1;usbdevicestoredirect:s:*;enablecredsspsupport:i:1;use multimon:i:1'
  }
}

resource applicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2023-09-05' = {
  name: applicationGroupName
  location: location
  tags: union(commonTags, {
    ResourceType: 'Virtual-Desktop'
    Department: 'Shared'
  })
  properties: {
    applicationGroupType: 'Desktop'
    hostPoolArmPath: hostPool.id
    friendlyName: 'Desktop Application Group'
  }
}

resource workspaceApplicationGroupAssociation 'Microsoft.DesktopVirtualization/workspaces/applicationGroupReferences@2023-09-05' = {
  parent: avdWorkspace
  name: guid(avdWorkspace.id, applicationGroup.id)
  properties: {
    applicationGroupReference: applicationGroup.id
  }
}

// ============================================================================
// VIRTUAL MACHINE SCALE SET
// ============================================================================

resource vmScaleSet 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name: vmssName
  location: location
  tags: union(commonTags, {
    ResourceType: 'Compute'
    Workload: 'AVD'
    Department: 'Shared'
    CostOptimization: 'Enabled'
    BillingCode: 'AVD-PROD'
    CostCenter: '100'
  })
  sku: {
    name: vmSku
    capacity: initialVmCount
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: take('${resourcePrefix}vm', 9)
        adminUsername: adminUsername
        adminPassword: adminPassword
        windowsConfiguration: {
          enableAutomaticUpdates: true
          provisionVMAgent: true
        }
      }
      storageProfile: {
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2022-datacenter-g2'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
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
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: virtualNetwork.properties.subnets[0].id
                    }
                    publicIPAddressConfiguration: {
                      name: 'pip-config'
                      properties: {
                        idleTimeoutInMinutes: 4
                      }
                    }
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
            name: 'Microsoft.Insights.VMDiagnosticsSettings'
            properties: {
              publisher: 'Microsoft.Azure.Diagnostics'
              type: 'IaaSDiagnostics'
              typeHandlerVersion: '1.9'
              autoUpgradeMinorVersion: true
              settings: {
                WadCfg: {
                  DiagnosticMonitorConfiguration: {
                    overallQuotaInMB: 4096
                    DiagnosticInfrastructureLogs: {
                      scheduledTransferLogLevelFilter: 'Error'
                    }
                    PerformanceCounters: {
                      scheduledTransferPeriod: 'PT1M'
                      PerformanceCounterConfiguration: [
                        {
                          counterSpecifier: '\\Processor(_Total)\\% Processor Time'
                          sampleRate: 'PT15S'
                          unit: 'Percent'
                        }
                        {
                          counterSpecifier: '\\Memory\\Available Bytes'
                          sampleRate: 'PT15S'
                          unit: 'Bytes'
                        }
                      ]
                    }
                  }
                }
              }
              protectedSettings: {
                storageAccountName: storageAccount.name
                storageAccountKey: storageAccount.listKeys().keys[0].value
              }
            }
          }
        ]
      }
    }
  }
}

// ============================================================================
// AUTO-SCALING CONFIGURATION
// ============================================================================

resource autoScaleSetting 'Microsoft.Insights/autoscaleSettings@2022-10-01' = {
  name: 'autoscale-${vmssName}'
  location: location
  tags: union(commonTags, {
    ResourceType: 'Monitoring'
    Purpose: 'Auto-Scaling'
  })
  properties: {
    enabled: true
    targetResourceUri: vmScaleSet.id
    profiles: [
      {
        name: 'Business Hours Profile'
        capacity: {
          minimum: string(minVmCount)
          maximum: string(maxVmCount)
          default: string(initialVmCount)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
              metricResourceUri: vmScaleSet.id
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
              metricResourceUri: vmScaleSet.id
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
        recurrence: {
          frequency: 'Week'
          schedule: {
            timeZone: 'UTC'
            days: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']
            hours: [8]
            minutes: [0]
          }
        }
      }
    ]
    notifications: [
      {
        operation: 'Scale'
        email: {
          sendToSubscriptionAdministrator: true
          sendToSubscriptionCoAdministrators: true
        }
      }
    ]
  }
}

// ============================================================================
// APP SERVICE PLAN AND FUNCTION APP
// ============================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: union(commonTags, {
    ResourceType: 'App-Service'
    Purpose: 'Cost-Analysis'
  })
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: false
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  tags: union(commonTags, {
    ResourceType: 'Function-App'
    Purpose: 'Cost-Analysis'
    Department: 'Shared'
  })
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
        {
          name: 'RESOURCE_GROUP'
          value: resourceGroup().name
        }
        {
          name: 'STORAGE_CONNECTION'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
      ]
      nodeVersion: '~18'
    }
    httpsOnly: true
  }
}

// ============================================================================
// LOGIC APP
// ============================================================================

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: union(commonTags, {
    ResourceType: 'Logic-App'
    Purpose: 'Cost-Automation'
    Department: 'Shared'
  })
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {
        Recurrence: {
          recurrence: {
            frequency: 'Day'
            interval: 1
            timeZone: 'UTC'
            startTime: '2024-01-01T08:00:00Z'
          }
          type: 'Recurrence'
        }
      }
      actions: {
        'Check-Cost-Threshold': {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: 'https://management.azure.com/subscriptions/${subscription().subscriptionId}/providers/Microsoft.CostManagement/query'
            headers: {
              'Content-Type': 'application/json'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
            }
          }
        }
      }
      outputs: {}
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ============================================================================
// COST MANAGEMENT BUDGET
// ============================================================================

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: budgetName
  properties: {
    displayName: 'AVD Cost Optimization Budget'
    amount: budgetAmount
    category: 'Cost'
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: utcNow('yyyy-MM-01')
      endDate: dateTimeAdd(utcNow('yyyy-MM-01'), 'P1Y')
    }
    filter: {
      dimensions: {
        name: 'ResourceGroupName'
        operator: 'In'
        values: [resourceGroup().name]
      }
    }
    notifications: {
      actual_80: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: []
        contactRoles: ['Owner', 'Contributor']
        thresholdType: 'Actual'
      }
      forecasted_100: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: []
        contactRoles: ['Owner', 'Contributor']
        thresholdType: 'Forecasted'
      }
    }
  }
}

// ============================================================================
// ROLE ASSIGNMENTS
// ============================================================================

// Cost Management Reader role for Logic App
var costManagementReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '72fafb9e-0641-4937-9268-a91bfd8191a3')

resource logicAppCostManagementRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logicApp.id, costManagementReaderRoleId, resourceGroup().id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: costManagementReaderRoleId
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('AVD Workspace Name')
output avdWorkspaceName string = avdWorkspace.name

@description('AVD Workspace Resource ID')
output avdWorkspaceId string = avdWorkspace.id

@description('Host Pool Name')
output hostPoolName string = hostPool.name

@description('Host Pool Resource ID')
output hostPoolId string = hostPool.id

@description('Application Group Name')
output applicationGroupName string = applicationGroup.name

@description('VM Scale Set Name')
output vmScaleSetName string = vmScaleSet.name

@description('VM Scale Set Resource ID')
output vmScaleSetId string = vmScaleSet.id

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('Function App Name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Logic App Name')
output logicAppName string = logicApp.name

@description('Logic App Resource ID')
output logicAppId string = logicApp.id

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Budget Name')
output budgetName string = budget.name

@description('Virtual Network Name')
output virtualNetworkName string = virtualNetwork.name

@description('Auto Scale Setting Name')
output autoScaleSettingName string = autoScaleSetting.name

@description('Deployment Summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  environment: environment
  vmSku: vmSku
  initialVmCount: initialVmCount
  maxSessionLimit: maxSessionLimit
  budgetAmount: budgetAmount
  deploymentTime: utcNow()
}