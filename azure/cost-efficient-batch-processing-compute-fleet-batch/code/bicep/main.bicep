@description('Main Bicep template for cost-efficient batch processing with Azure Compute Fleet and Azure Batch')

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment type (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environmentType string = 'dev'

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Batch account name')
param batchAccountName string = 'batchacct${uniqueSuffix}'

@description('Storage account name for batch processing')
param storageAccountName string = 'stbatch${uniqueSuffix}'

@description('Compute fleet name')
param computeFleetName string = 'compute-fleet-${uniqueSuffix}'

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string = 'log-batch-${uniqueSuffix}'

@description('Batch pool configuration')
param batchPoolConfig object = {
  poolId: 'batch-pool-${uniqueSuffix}'
  vmSize: 'Standard_D2s_v3'
  targetDedicatedNodes: 0
  targetLowPriorityNodes: 10
  maxNodes: 20
  autoScaleEvaluationInterval: 'PT5M'
}

@description('Compute fleet configuration')
param computeFleetConfig object = {
  spotCapacityPercentage: 80
  regularCapacityPercentage: 20
  maxSpotPricePerVM: 0.05
  minCapacity: 0
  maxCapacity: 100
}

@description('VM configuration for compute fleet')
param vmConfiguration object = {
  publisher: 'MicrosoftWindowsServer'
  offer: 'WindowsServer'
  sku: '2022-datacenter-core'
  version: 'latest'
  adminUsername: 'batchadmin'
  computerNamePrefix: 'batch-vm'
}

@description('Budget configuration')
param budgetConfig object = {
  amount: 100
  alertThreshold: 80
  contactEmail: 'admin@example.com'
}

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'batch-processing'
  environment: environmentType
  solution: 'cost-efficient-batch'
  managedBy: 'bicep'
}

// Variables
var storageAccountSku = environmentType == 'prod' ? 'Standard_GRS' : 'Standard_LRS'
var logAnalyticsSku = environmentType == 'prod' ? 'PerGB2018' : 'PerGB2018'
var autoScaleFormula = '$TargetLowPriorityNodes = min(${batchPoolConfig.maxNodes}, $PendingTasks.GetSample(1 * TimeInterval_Minute, 0).GetAverage() * 2);'

// Storage Account for batch processing
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: storageAccountSku
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
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
  tags: tags
}

// Blob container for batch data
resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/batch-data'
  properties: {
    publicAccess: 'None'
  }
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: logAnalyticsSku
    }
    retentionInDays: environmentType == 'prod' ? 90 : 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
  tags: tags
}

// Application Insights for application monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-batch-${uniqueSuffix}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  tags: tags
}

// Managed Identity for batch operations
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-batch-${uniqueSuffix}'
  location: location
  tags: tags
}

// Role assignment for managed identity to access storage
resource storageContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Azure Batch Account
resource batchAccount 'Microsoft.Batch/batchAccounts@2024-02-01' = {
  name: batchAccountName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    autoStorage: {
      storageAccountId: storageAccount.id
    }
    poolAllocationMode: 'UserSubscription'
    keyVaultReference: {
      id: keyVault.id
      url: keyVault.properties.vaultUri
    }
    allowedAuthenticationModes: [
      'AAD'
      'SharedKey'
    ]
  }
  tags: tags
}

// Key Vault for batch account secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-batch-${uniqueSuffix}'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
  tags: tags
}

// Key Vault access policy for batch account
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        tenantId: tenant().tenantId
        objectId: managedIdentity.properties.principalId
        permissions: {
          secrets: [
            'get'
            'list'
            'set'
          ]
          certificates: [
            'get'
            'list'
          ]
        }
      }
    ]
  }
}

// Compute Fleet (using ARM template deployment as Bicep doesn't directly support Compute Fleet yet)
resource computeFleetDeployment 'Microsoft.Resources/deployments@2022-09-01' = {
  name: 'computeFleetDeployment'
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      variables: {}
      resources: [
        {
          type: 'Microsoft.Compute/fleets'
          apiVersion: '2023-09-01'
          name: computeFleetName
          location: location
          tags: tags
          properties: {
            computeProfile: {
              baseVirtualMachineProfile: {
                storageProfile: {
                  imageReference: {
                    publisher: vmConfiguration.publisher
                    offer: vmConfiguration.offer
                    sku: vmConfiguration.sku
                    version: vmConfiguration.version
                  }
                  osDisk: {
                    createOption: 'FromImage'
                    caching: 'ReadWrite'
                    managedDisk: {
                      storageAccountType: 'Standard_LRS'
                    }
                  }
                }
                osProfile: {
                  computerNamePrefix: vmConfiguration.computerNamePrefix
                  adminUsername: vmConfiguration.adminUsername
                  adminPassword: 'BatchP@ssw0rd123!'
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
                            }
                          }
                        ]
                      }
                    }
                  ]
                }
              }
              computeApiVersion: '2023-09-01'
            }
            spotPriorityProfile: {
              capacity: computeFleetConfig.spotCapacityPercentage
              minCapacity: computeFleetConfig.minCapacity
              maxPricePerVM: computeFleetConfig.maxSpotPricePerVM
              evictionPolicy: 'Delete'
              allocationStrategy: 'LowestPrice'
            }
            regularPriorityProfile: {
              capacity: computeFleetConfig.regularCapacityPercentage
              minCapacity: 5
              allocationStrategy: 'LowestPrice'
            }
          }
        }
      ]
    }
  }
  dependsOn: [
    virtualNetwork
  ]
}

// Virtual Network for compute fleet
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-batch-${uniqueSuffix}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-batch'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
  tags: tags
}

// Network Security Group
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-batch-${uniqueSuffix}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowBatchNodeManagement'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '29876-29877'
          protocol: 'Tcp'
          sourceAddressPrefix: 'BatchNodeManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowRDP'
        properties: {
          priority: 1001
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '3389'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
  tags: tags
}

// Diagnostic Settings for Batch Account
resource batchDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'batch-diagnostics'
  scope: batchAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ServiceLog'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Cost Management Budget
resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: 'budget-batch-${uniqueSuffix}'
  properties: {
    category: 'Cost'
    amount: budgetConfig.amount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: '${utcNow('yyyy-MM')}-01'
      endDate: '${dateTimeAdd(utcNow('yyyy-MM-01'), 'P1M')}'
    }
    filter: {
      dimensions: {
        name: 'ResourceGroupName'
        operator: 'In'
        values: [
          resourceGroup().name
        ]
      }
    }
    notifications: {
      'actual_GreaterThan_${budgetConfig.alertThreshold}_Percent': {
        enabled: true
        operator: 'GreaterThan'
        threshold: budgetConfig.alertThreshold
        contactEmails: [
          budgetConfig.contactEmail
        ]
        contactRoles: [
          'Owner'
          'Contributor'
        ]
      }
    }
  }
}

// Action Group for alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-batch-${uniqueSuffix}'
  location: 'Global'
  properties: {
    groupShortName: 'BatchAlert'
    enabled: true
    emailReceivers: [
      {
        name: 'EmailAdmin'
        emailAddress: budgetConfig.contactEmail
        useCommonAlertSchema: true
      }
    ]
  }
  tags: tags
}

// CPU utilization alert
resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'batch-cpu-alert'
  location: 'Global'
  properties: {
    description: 'Alert when batch processing CPU exceeds threshold'
    severity: 2
    enabled: true
    scopes: [
      batchAccount.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCPU'
          metricNamespace: 'Microsoft.Batch/batchAccounts'
          metricName: 'CoreCount'
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

// Outputs
@description('Batch account name')
output batchAccountName string = batchAccount.name

@description('Batch account resource ID')
output batchAccountId string = batchAccount.id

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account resource ID')
output storageAccountId string = storageAccount.id

@description('Storage account primary key')
output storageAccountKey string = storageAccount.listKeys().keys[0].value

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Managed identity client ID')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Managed identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Virtual network resource ID')
output virtualNetworkId string = virtualNetwork.id

@description('Subnet resource ID')
output subnetId string = virtualNetwork.properties.subnets[0].id

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Batch pool configuration')
output batchPoolConfig object = {
  poolId: batchPoolConfig.poolId
  vmSize: batchPoolConfig.vmSize
  autoScaleFormula: autoScaleFormula
  targetLowPriorityNodes: batchPoolConfig.targetLowPriorityNodes
  maxNodes: batchPoolConfig.maxNodes
}

@description('Compute fleet name')
output computeFleetName string = computeFleetName

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Deployment location')
output location string = location

@description('Environment type')
output environmentType string = environmentType

@description('Unique suffix used for resources')
output uniqueSuffix string = uniqueSuffix