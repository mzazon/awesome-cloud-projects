// Chaos Engineering for Application Resilience Testing
// This Bicep template deploys all necessary infrastructure for chaos engineering testing

@minLength(1)
@maxLength(16)
@description('Prefix for all resource names to ensure uniqueness')
param namePrefix string = 'chaos'

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Administrator username for virtual machine')
param vmAdminUsername string = 'azureuser'

@description('SSH public key for virtual machine authentication')
@secure()
param vmSshPublicKey string

@description('VM size for the target virtual machine')
@allowed(['Standard_B2s', 'Standard_D2s_v3', 'Standard_D2as_v4'])
param vmSize string = 'Standard_B2s'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'chaos-testing'
  environment: 'demo'
  recipe: 'implementing-resilience-testing-with-azure-chaos-studio-and-application-insights'
}

@description('Chaos experiment duration in ISO 8601 format')
param chaosExperimentDuration string = 'PT5M'

@description('Enable abrupt shutdown for VM chaos experiment')
param abruptShutdown bool = true

@description('Email address for alert notifications')
param alertEmailAddress string = 'admin@example.com'

// Generate unique suffix for resource names
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)

// Resource names
var logAnalyticsWorkspaceName = '${namePrefix}-log-${uniqueSuffix}'
var applicationInsightsName = '${namePrefix}-appi-${uniqueSuffix}'
var virtualNetworkName = '${namePrefix}-vnet-${uniqueSuffix}'
var networkSecurityGroupName = '${namePrefix}-nsg-${uniqueSuffix}'
var publicIpName = '${namePrefix}-pip-${uniqueSuffix}'
var networkInterfaceName = '${namePrefix}-nic-${uniqueSuffix}'
var virtualMachineName = '${namePrefix}-vm-${uniqueSuffix}'
var managedIdentityName = '${namePrefix}-id-${uniqueSuffix}'
var chaosExperimentName = '${namePrefix}-exp-vm-shutdown-${uniqueSuffix}'
var actionGroupName = '${namePrefix}-ag-${uniqueSuffix}'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
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

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Virtual Network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: virtualNetworkName
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
        name: 'default'
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

// Network Security Group
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: networkSecurityGroupName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          description: 'Allow SSH'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1001
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Public IP
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${namePrefix}-vm-${uniqueSuffix}'
    }
  }
}

// Network Interface
resource networkInterface 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: networkInterfaceName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
  }
}

// User Assigned Managed Identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Virtual Machine
resource virtualMachine 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: virtualMachineName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: virtualMachineName
      adminUsername: vmAdminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${vmAdminUsername}/.ssh/authorized_keys'
              keyData: vmSshPublicKey
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
        name: '${virtualMachineName}-osdisk'
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
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// Enable Chaos Studio Target on Virtual Machine
resource chaosTarget 'Microsoft.Chaos/targets@2024-01-01' = {
  name: 'Microsoft-VirtualMachine'
  scope: virtualMachine
  properties: {}
}

// Enable Chaos Agent capability for agent-based faults
resource chaosCapability 'Microsoft.Chaos/targets/capabilities@2024-01-01' = {
  name: 'Shutdown-1.0'
  parent: chaosTarget
  properties: {}
}

// Chaos Agent VM Extension
resource chaosAgentExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  name: 'ChaosAgent'
  parent: virtualMachine
  properties: {
    publisher: 'Microsoft.Azure.Chaos'
    type: 'ChaosAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    settings: {
      profile: 'Node'
      auth: {
        msi: {
          clientId: managedIdentity.properties.clientId
        }
      }
      appInsightsSettings: {
        isEnabled: true
        instrumentationKey: applicationInsights.properties.InstrumentationKey
        logLevel: 'Information'
      }
    }
  }
}

// Role Assignment: Virtual Machine Contributor for Managed Identity
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: virtualMachine
  name: guid(virtualMachine.id, managedIdentity.id, 'Virtual Machine Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9980e02c-c2be-4d73-94e8-173b1dc7cf3c')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Chaos Experiment
resource chaosExperiment 'Microsoft.Chaos/experiments@2024-01-01' = {
  name: chaosExperimentName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    steps: [
      {
        name: 'Step 1'
        branches: [
          {
            name: 'Branch 1'
            actions: [
              {
                type: 'continuous'
                name: 'VM Shutdown'
                selectorId: 'Selector1'
                duration: chaosExperimentDuration
                parameters: [
                  {
                    key: 'abruptShutdown'
                    value: string(abruptShutdown)
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
    selectors: [
      {
        id: 'Selector1'
        type: 'List'
        targets: [
          {
            type: 'ChaosTarget'
            id: chaosTarget.id
          }
        ]
      }
    ]
  }
  dependsOn: [
    roleAssignment
  ]
}

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'ChaosAlert'
    enabled: true
    emailReceivers: [
      {
        name: 'admin-email'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// Metric Alert for High CPU Usage
resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Chaos Experiment High CPU Alert'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when chaos experiment affects VM performance'
    severity: 2
    enabled: true
    scopes: [
      virtualMachine.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 80
          name: 'Metric1'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          metricName: 'Percentage CPU'
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
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

// Outputs
output resourceGroupName string = resourceGroup().name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output applicationInsightsName string = applicationInsights.name
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output virtualMachineName string = virtualMachine.name
output virtualMachineResourceId string = virtualMachine.id
output publicIpAddress string = publicIp.properties.ipAddress
output sshConnectionString string = 'ssh ${vmAdminUsername}@${publicIp.properties.ipAddress}'
output managedIdentityName string = managedIdentity.name
output managedIdentityClientId string = managedIdentity.properties.clientId
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output chaosExperimentName string = chaosExperiment.name
output chaosTargetId string = chaosTarget.id
output actionGroupName string = actionGroup.name
output deploymentInstructions object = {
  step1: 'Register Microsoft.Chaos provider if not already registered'
  step2: 'Deploy this Bicep template using Azure CLI or Azure PowerShell'
  step3: 'Wait for all resources to be provisioned'
  step4: 'Use the chaos experiment outputs to start testing'
  step5: 'Monitor Application Insights for fault events during experiments'
}