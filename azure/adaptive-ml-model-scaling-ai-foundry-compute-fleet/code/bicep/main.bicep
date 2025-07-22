@description('Main Bicep template for Adaptive ML Model Scaling with Azure AI Foundry and Compute Fleet')

// ================================================================================
// PARAMETERS
// ================================================================================

@description('The Azure region for resource deployment')
param location string = resourceGroup().location

@description('Unique suffix for resource naming')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment tag for resources')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Cost center tag for billing')
param costCenter string = 'ML-Engineering'

@description('Project name for resource grouping')
param projectName string = 'adaptive-ml-scaling'

@description('Azure AI Foundry hub configuration')
param aiFoundryConfig object = {
  name: 'aif-adaptive-${uniqueSuffix}'
  displayName: 'AI Foundry Hub for ML Adaptive Scaling'
  description: 'Central hub for orchestrating ML scaling agents'
  storageHnsEnabled: true
  publicNetworkAccess: 'Enabled'
}

@description('Machine Learning workspace configuration')
param mlWorkspaceConfig object = {
  name: 'mlw-scaling-${uniqueSuffix}'
  displayName: 'ML Workspace for Adaptive Scaling'
  description: 'Machine Learning workspace for model training and inference'
  hbiWorkspace: false
  publicNetworkAccess: 'Enabled'
}

@description('Compute Fleet configuration')
param computeFleetConfig object = {
  name: 'cf-ml-scaling-${uniqueSuffix}'
  spotPriorityProfile: {
    capacity: 20
    minCapacity: 5
    maxPricePerVM: json('0.10')
    evictionPolicy: 'Deallocate'
    allocationStrategy: 'PriceCapacityOptimized'
  }
  regularPriorityProfile: {
    capacity: 10
    minCapacity: 2
    allocationStrategy: 'LowestPrice'
  }
  vmSizesProfile: [
    {
      name: 'Standard_D4s_v3'
      rank: 1
    }
    {
      name: 'Standard_D8s_v3'
      rank: 2
    }
    {
      name: 'Standard_E4s_v3'
      rank: 3
    }
  ]
}

@description('Monitoring configuration')
param monitoringConfig object = {
  logAnalyticsName: 'law-ml-${uniqueSuffix}'
  applicationInsightsName: 'ai-ml-${uniqueSuffix}'
  workbookName: 'ML-Scaling-Dashboard'
  retentionInDays: 30
}

@description('Storage configuration')
param storageConfig object = {
  accountName: 'stmlscaling${uniqueSuffix}'
  skuName: 'Standard_LRS'
  accessTier: 'Hot'
  allowBlobPublicAccess: false
  allowSharedKeyAccess: true
  minimumTlsVersion: 'TLS1_2'
}

@description('Key Vault configuration')
param keyVaultConfig object = {
  name: 'kv-ml-${uniqueSuffix}'
  skuName: 'standard'
  enabledForDeployment: false
  enabledForTemplateDeployment: true
  enabledForDiskEncryption: false
  enableSoftDelete: true
  softDeleteRetentionInDays: 7
  enablePurgeProtection: false
}

@description('Container Registry configuration')
param containerRegistryConfig object = {
  name: 'crmlscaling${uniqueSuffix}'
  skuName: 'Basic'
  adminUserEnabled: true
  publicNetworkAccess: 'Enabled'
}

// ================================================================================
// VARIABLES
// ================================================================================

var resourceTags = {
  Environment: environment
  CostCenter: costCenter
  Project: projectName
  Purpose: 'ML-Adaptive-Scaling'
  DeployedBy: 'Bicep'
}

var tenantId = subscription().tenantId

// ================================================================================
// EXISTING RESOURCES
// ================================================================================

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: resourceGroup().name
}

// ================================================================================
// STORAGE RESOURCES
// ================================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageConfig.accountName
  location: location
  tags: resourceTags
  sku: {
    name: storageConfig.skuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: storageConfig.accessTier
    allowBlobPublicAccess: storageConfig.allowBlobPublicAccess
    allowSharedKeyAccess: storageConfig.allowSharedKeyAccess
    minimumTlsVersion: storageConfig.minimumTlsVersion
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
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

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource defaultContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'default'
  properties: {
    publicAccess: 'None'
  }
}

// ================================================================================
// KEY VAULT
// ================================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultConfig.name
  location: location
  tags: resourceTags
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: keyVaultConfig.skuName
    }
    enabledForDeployment: keyVaultConfig.enabledForDeployment
    enabledForTemplateDeployment: keyVaultConfig.enabledForTemplateDeployment
    enabledForDiskEncryption: keyVaultConfig.enabledForDiskEncryption
    enableSoftDelete: keyVaultConfig.enableSoftDelete
    softDeleteRetentionInDays: keyVaultConfig.softDeleteRetentionInDays
    enablePurgeProtection: keyVaultConfig.enablePurgeProtection
    accessPolicies: []
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ================================================================================
// CONTAINER REGISTRY
// ================================================================================

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryConfig.name
  location: location
  tags: resourceTags
  sku: {
    name: containerRegistryConfig.skuName
  }
  properties: {
    adminUserEnabled: containerRegistryConfig.adminUserEnabled
    publicNetworkAccess: containerRegistryConfig.publicNetworkAccess
    networkRuleBypassOptions: 'AzureServices'
  }
}

// ================================================================================
// MONITORING RESOURCES
// ================================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: monitoringConfig.logAnalyticsName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: monitoringConfig.retentionInDays
    features: {
      immediatePurgeDataOn30Days: true
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: monitoringConfig.applicationInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ================================================================================
// AI FOUNDRY HUB
// ================================================================================

resource aiFoundryHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: aiFoundryConfig.name
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: aiFoundryConfig.displayName
    description: aiFoundryConfig.description
    keyVault: keyVault.id
    storageAccount: storageAccount.id
    applicationInsights: applicationInsights.id
    containerRegistry: containerRegistry.id
    publicNetworkAccess: aiFoundryConfig.publicNetworkAccess
    hbiWorkspace: false
    workspaceHubConfig: {
      additionalWorkspaceStorageAccounts: []
      defaultWorkspaceResourceGroup: resourceGroup.id
    }
  }
  kind: 'Hub'
}

// ================================================================================
// ML WORKSPACE (PROJECT)
// ================================================================================

resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: mlWorkspaceConfig.name
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: mlWorkspaceConfig.displayName
    description: mlWorkspaceConfig.description
    keyVault: keyVault.id
    storageAccount: storageAccount.id
    applicationInsights: applicationInsights.id
    containerRegistry: containerRegistry.id
    publicNetworkAccess: mlWorkspaceConfig.publicNetworkAccess
    hbiWorkspace: mlWorkspaceConfig.hbiWorkspace
    workspaceHubConfig: {
      additionalWorkspaceStorageAccounts: []
      defaultWorkspaceResourceGroup: resourceGroup.id
    }
    hubResourceId: aiFoundryHub.id
  }
  kind: 'Project'
}

// ================================================================================
// COMPUTE FLEET
// ================================================================================

resource computeFleet 'Microsoft.AzureFleet/fleets@2024-05-01-preview' = {
  name: computeFleetConfig.name
  location: location
  tags: resourceTags
  properties: {
    spotPriorityProfile: {
      capacity: computeFleetConfig.spotPriorityProfile.capacity
      minCapacity: computeFleetConfig.spotPriorityProfile.minCapacity
      maxPricePerVM: computeFleetConfig.spotPriorityProfile.maxPricePerVM
      evictionPolicy: computeFleetConfig.spotPriorityProfile.evictionPolicy
      allocationStrategy: computeFleetConfig.spotPriorityProfile.allocationStrategy
      maintain: true
    }
    regularPriorityProfile: {
      capacity: computeFleetConfig.regularPriorityProfile.capacity
      minCapacity: computeFleetConfig.regularPriorityProfile.minCapacity
      allocationStrategy: computeFleetConfig.regularPriorityProfile.allocationStrategy
    }
    vmSizesProfile: computeFleetConfig.vmSizesProfile
    computeProfile: {
      baseVirtualMachineProfile: {
        osProfile: {
          computerNamePrefix: 'mlnode'
          adminUsername: 'azureuser'
          linuxConfiguration: {
            disablePasswordAuthentication: true
            ssh: {
              publicKeys: [
                {
                  path: '/home/azureuser/.ssh/authorized_keys'
                  keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC...' // Placeholder - should be provided via parameter
                }
              ]
            }
          }
        }
        storageProfile: {
          imageReference: {
            publisher: 'microsoft-dsvm'
            offer: 'ubuntu-2004'
            sku: '2004-gen2'
            version: 'latest'
          }
          osDisk: {
            createOption: 'FromImage'
            caching: 'ReadWrite'
            managedDisk: {
              storageAccountType: 'Premium_LRS'
            }
            diskSizeGB: 128
          }
        }
        networkProfile: {
          networkInterfaceConfigurations: [
            {
              name: 'ml-nic-config'
              properties: {
                primary: true
                ipConfigurations: [
                  {
                    name: 'internal'
                    properties: {
                      subnet: {
                        id: virtualNetwork.properties.subnets[0].id
                      }
                      primary: true
                      privateIPAddressVersion: 'IPv4'
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
              name: 'ml-setup'
              properties: {
                publisher: 'Microsoft.Azure.Extensions'
                type: 'CustomScript'
                typeHandlerVersion: '2.1'
                autoUpgradeMinorVersion: true
                settings: {
                  commandToExecute: 'sudo apt-get update && sudo apt-get install -y python3-pip && pip3 install azure-ml'
                }
              }
            }
          ]
        }
      }
      computeApiVersion: '2023-09-01'
      platformFaultDomainCount: 1
    }
  }
}

// ================================================================================
// NETWORKING
// ================================================================================

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: 'vnet-ml-scaling-${uniqueSuffix}'
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'compute-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
      {
        name: 'services-subnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.KeyVault'
            }
          ]
        }
      }
    ]
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-ml-compute-${uniqueSuffix}'
  location: location
  tags: resourceTags
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          description: 'Allow SSH access for ML compute nodes'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowMLServices'
        properties: {
          description: 'Allow ML service communication'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '8080'
            '8443'
            '5000'
          ]
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1100
          direction: 'Inbound'
        }
      }
    ]
  }
}

// ================================================================================
// RBAC ASSIGNMENTS
// ================================================================================

// AI Foundry Hub identity permissions
resource aiFoundryStorageContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundryHub.id, storageAccount.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: aiFoundryHub.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource aiFoundryKeyVaultContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundryHub.id, keyVault.id, 'Key Vault Contributor')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f25e0fa2-a7c8-4377-a976-54943a77a395') // Key Vault Contributor
    principalId: aiFoundryHub.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ML Workspace identity permissions
resource mlWorkspaceStorageContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(mlWorkspace.id, storageAccount.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: mlWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource mlWorkspaceContainerRegistryContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(mlWorkspace.id, containerRegistry.id, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: mlWorkspace.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ================================================================================
// MONITORING WORKBOOK
// ================================================================================

resource scalingWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup.id, 'ML-Scaling-Dashboard')
  location: location
  tags: resourceTags
  kind: 'shared'
  properties: {
    displayName: monitoringConfig.workbookName
    description: 'Comprehensive monitoring dashboard for ML adaptive scaling'
    category: 'workbook'
    serializedData: '''
    {
      "version": "Notebook/1.0",
      "items": [
        {
          "type": 1,
          "content": {
            "json": "# ML Adaptive Scaling Dashboard\\n\\nMonitor your AI Foundry agents and compute fleet performance in real-time."
          }
        },
        {
          "type": 9,
          "content": {
            "version": "KqlParameterItem/1.0",
            "parameters": [
              {
                "id": "timeRange",
                "version": "KqlParameterItem/1.0",
                "name": "TimeRange",
                "type": 4,
                "value": {
                  "durationMs": 3600000
                }
              }
            ]
          }
        },
        {
          "type": 3,
          "content": {
            "version": "KqlItem/1.0",
            "query": "AzureMetrics\\n| where ResourceProvider == \\"MICROSOFT.MACHINELEARNINGSERVICES\\"\\n| where MetricName in (\\"CpuUtilization\\", \\"MemoryUtilization\\")\\n| summarize avg(Average) by bin(TimeGenerated, 5m), MetricName\\n| render timechart",
            "size": 0,
            "title": "ML Compute Utilization",
            "timeContext": {
              "durationMs": 3600000
            }
          }
        },
        {
          "type": 3,
          "content": {
            "version": "KqlItem/1.0",
            "query": "AzureActivity\\n| where ResourceProvider == \\"MICROSOFT.AZUREFLEET\\"\\n| where OperationNameValue contains \\"fleet\\"\\n| summarize count() by bin(TimeGenerated, 15m), OperationNameValue\\n| render columnchart",
            "size": 0,
            "title": "Compute Fleet Operations",
            "timeContext": {
              "durationMs": 3600000
            }
          }
        }
      ]
    }
    '''
    sourceId: logAnalyticsWorkspace.id
  }
}

// ================================================================================
// ALERT RULES
// ================================================================================

resource scalingAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'ml-scaling-trigger-${uniqueSuffix}'
  location: 'global'
  tags: resourceTags
  properties: {
    description: 'Triggers agent scaling actions when compute utilization exceeds threshold'
    severity: 2
    enabled: true
    scopes: [
      mlWorkspace.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCpuUtilization'
          metricName: 'CpuUtilization'
          operator: 'GreaterThan'
          threshold: 75
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

// ================================================================================
// OUTPUTS
// ================================================================================

@description('The resource ID of the AI Foundry Hub')
output aiFoundryHubId string = aiFoundryHub.id

@description('The name of the AI Foundry Hub')
output aiFoundryHubName string = aiFoundryHub.name

@description('The resource ID of the ML Workspace')
output mlWorkspaceId string = mlWorkspace.id

@description('The name of the ML Workspace')
output mlWorkspaceName string = mlWorkspace.name

@description('The resource ID of the Compute Fleet')
output computeFleetId string = computeFleet.id

@description('The name of the Compute Fleet')
output computeFleetName string = computeFleet.name

@description('The resource ID of the Log Analytics Workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The name of the Log Analytics Workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The resource ID of the Application Insights')
output applicationInsightsId string = applicationInsights.id

@description('The name of the Application Insights')
output applicationInsightsName string = applicationInsights.name

@description('The resource ID of the Storage Account')
output storageAccountId string = storageAccount.id

@description('The name of the Storage Account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the Key Vault')
output keyVaultId string = keyVault.id

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The resource ID of the Container Registry')
output containerRegistryId string = containerRegistry.id

@description('The name of the Container Registry')
output containerRegistryName string = containerRegistry.name

@description('The login server for the Container Registry')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('The resource ID of the Virtual Network')
output virtualNetworkId string = virtualNetwork.id

@description('The name of the Virtual Network')
output virtualNetworkName string = virtualNetwork.name

@description('The resource tags applied to all resources')
output resourceTags object = resourceTags

@description('The unique suffix used for resource naming')
output uniqueSuffix string = uniqueSuffix

@description('Connection information for ML workspace')
output mlWorkspaceConnection object = {
  subscriptionId: subscription().subscriptionId
  resourceGroupName: resourceGroup().name
  workspaceName: mlWorkspace.name
  storageAccount: storageAccount.name
  keyVault: keyVault.name
  applicationInsights: applicationInsights.name
  containerRegistry: containerRegistry.name
}

@description('Monitoring and alerting endpoints')
output monitoringEndpoints object = {
  logAnalyticsWorkspaceId: logAnalyticsWorkspace.properties.customerId
  applicationInsightsInstrumentationKey: applicationInsights.properties.InstrumentationKey
  applicationInsightsConnectionString: applicationInsights.properties.ConnectionString
  workbookId: scalingWorkbook.id
}