@description('Main Bicep template for Automated Cost Governance with Azure Resource Graph and Power BI')

// Parameters
@description('The location for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Project name prefix for resource naming')
@minLength(3)
@maxLength(10)
param projectPrefix string = 'costgov'

@description('Cost threshold for daily monitoring in USD')
@minValue(100)
@maxValue(100000)
param dailyCostThreshold int = 500

@description('Cost threshold for monthly monitoring in USD')
@minValue(1000)
@maxValue(1000000)
param monthlyCostThreshold int = 10000

@description('Email address for cost notifications')
param notificationEmail string

@description('Microsoft Teams webhook URL for notifications (optional)')
param teamsWebhookUrl string = ''

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'Cost Governance'
  Solution: 'Azure Resource Graph + Power BI'
}

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var storageAccountName = 'st${projectPrefix}${uniqueSuffix}'
var logicAppName = 'la-${projectPrefix}-${environment}-${uniqueSuffix}'
var keyVaultName = 'kv-${projectPrefix}-${environment}-${uniqueSuffix}'
var actionGroupName = 'ag-${projectPrefix}-alerts-${environment}'
var budgetName = 'budget-${projectPrefix}-${environment}'
var workspaceName = 'log-${projectPrefix}-${environment}-${uniqueSuffix}'

// Storage Account for data persistence
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
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
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
  tags: tags
}

// Storage containers for different data types
resource storageContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [
  for containerName in ['resource-graph-data', 'powerbi-datasets', 'cost-reports']: {
    name: '${storageAccount.name}/default/${containerName}'
    properties: {
      publicAccess: 'None'
    }
  }
]

// Key Vault for secure configuration storage
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
  tags: tags
}

// Key Vault secrets for cost thresholds
resource keyVaultSecrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [
  for secret in [
    {
      name: 'cost-threshold-daily'
      value: string(dailyCostThreshold)
    }
    {
      name: 'cost-threshold-monthly'
      value: string(monthlyCostThreshold)
    }
    {
      name: 'notification-email'
      value: notificationEmail
    }
    {
      name: 'teams-webhook-url'
      value: teamsWebhookUrl
    }
  ]: {
    name: '${keyVault.name}/${secret.name}'
    properties: {
      value: secret.value
      contentType: 'text/plain'
    }
  }
]

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
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
  tags: tags
}

// Logic App for cost monitoring automation
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        storageAccountName: {
          type: 'string'
          defaultValue: storageAccountName
        }
        keyVaultName: {
          type: 'string'
          defaultValue: keyVaultName
        }
        subscriptionId: {
          type: 'string'
          defaultValue: subscription().subscriptionId
        }
      }
      triggers: {
        Recurrence: {
          recurrence: {
            frequency: 'Hour'
            interval: 6
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Get_Cost_Threshold: {
          inputs: {
            authentication: {
              type: 'ManagedServiceIdentity'
            }
            method: 'GET'
            uri: 'https://@{parameters(\'keyVaultName\')}.vault.azure.net/secrets/cost-threshold-daily?api-version=2016-10-01'
          }
          runAfter: {}
          type: 'Http'
        }
        Execute_Resource_Graph_Query: {
          inputs: {
            authentication: {
              type: 'ManagedServiceIdentity'
            }
            body: {
              query: 'resources | where type in~ [\'microsoft.compute/virtualmachines\', \'microsoft.storage/storageaccounts\', \'microsoft.sql/servers\'] | extend costCenter = tostring(tags[\'CostCenter\']), environment = tostring(tags[\'Environment\']), owner = tostring(tags[\'Owner\']) | project name, type, resourceGroup, location, subscriptionId, costCenter, environment, owner | order by type, name'
            }
            method: 'POST'
            uri: 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01'
          }
          runAfter: {
            Get_Cost_Threshold: [
              'Succeeded'
            ]
          }
          type: 'Http'
        }
        Query_Cost_Management: {
          inputs: {
            authentication: {
              type: 'ManagedServiceIdentity'
            }
            body: {
              type: 'Usage'
              timeframe: 'MonthToDate'
              dataset: {
                granularity: 'Daily'
                aggregation: {
                  totalCost: {
                    name: 'PreTaxCost'
                    function: 'Sum'
                  }
                }
                grouping: [
                  {
                    type: 'Dimension'
                    name: 'ResourceGroupName'
                  }
                ]
              }
            }
            method: 'POST'
            uri: 'https://management.azure.com/subscriptions/@{parameters(\'subscriptionId\')}/providers/Microsoft.CostManagement/query?api-version=2021-10-01'
          }
          runAfter: {
            Execute_Resource_Graph_Query: [
              'Succeeded'
            ]
          }
          type: 'Http'
        }
        Store_Resource_Graph_Results: {
          inputs: {
            authentication: {
              type: 'ManagedServiceIdentity'
            }
            body: '@body(\'Execute_Resource_Graph_Query\')'
            headers: {
              'x-ms-blob-type': 'BlockBlob'
              'Content-Type': 'application/json'
            }
            method: 'PUT'
            uri: 'https://@{parameters(\'storageAccountName\')}.blob.core.windows.net/resource-graph-data/resource-inventory-@{utcnow()}.json'
          }
          runAfter: {
            Query_Cost_Management: [
              'Succeeded'
            ]
          }
          type: 'Http'
        }
        Store_Cost_Data: {
          inputs: {
            authentication: {
              type: 'ManagedServiceIdentity'
            }
            body: '@body(\'Query_Cost_Management\')'
            headers: {
              'x-ms-blob-type': 'BlockBlob'
              'Content-Type': 'application/json'
            }
            method: 'PUT'
            uri: 'https://@{parameters(\'storageAccountName\')}.blob.core.windows.net/cost-reports/cost-data-@{utcnow()}.json'
          }
          runAfter: {
            Store_Resource_Graph_Results: [
              'Succeeded'
            ]
          }
          type: 'Http'
        }
      }
      outputs: {}
    }
  }
  tags: tags
}

// Action Group for notifications
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  properties: {
    groupShortName: 'CostAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'CostAdmin'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ]
    webhookReceivers: teamsWebhookUrl != '' ? [
      {
        name: 'TeamsWebhook'
        serviceUri: teamsWebhookUrl
        useCommonAlertSchema: true
      }
    ] : []
  }
  tags: tags
}

// Budget for cost monitoring
resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: budgetName
  properties: {
    timePeriod: {
      startDate: '2025-01-01'
      endDate: '2025-12-31'
    }
    timeGrain: 'Monthly'
    amount: monthlyCostThreshold
    category: 'Cost'
    notifications: {
      'Actual_GreaterThan_80_Percent': {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: [
          notificationEmail
        ]
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Actual'
      }
      'Forecasted_GreaterThan_100_Percent': {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: [
          notificationEmail
        ]
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Forecasted'
      }
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
  }
}

// Role assignments for Logic App
resource logicAppKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, logicApp.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logicAppStorageContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, logicApp.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logicAppCostManagementReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, logicApp.id, 'Cost Management Reader')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '72fafb9e-0641-4937-9268-a91bfd8191a3') // Cost Management Reader
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logicAppResourceGraphReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, logicApp.id, 'Reader')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output logicAppName string = logicApp.name
output logicAppId string = logicApp.id
output actionGroupName string = actionGroup.name
output actionGroupId string = actionGroup.id
output budgetName string = budget.name
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

// Power BI connection information
output powerBiStorageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
output powerBiDatasetContainer string = 'powerbi-datasets'
output powerBiReportsContainer string = 'cost-reports'
output resourceGraphDataContainer string = 'resource-graph-data'