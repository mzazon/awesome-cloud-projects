// Azure Carbon-Aware Cost Optimization Infrastructure
// This Bicep template deploys the complete infrastructure for automated carbon optimization
// using Azure Carbon Optimization, Azure Automation, and Azure Logic Apps

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Carbon emissions threshold in kg CO2e per month')
param carbonThresholdKg int = 100

@description('Cost threshold in USD per month for optimization actions')
param costThresholdUsd int = 500

@description('Minimum carbon reduction percentage to trigger actions')
param minCarbonReductionPercent int = 10

@description('CPU utilization threshold for rightsizing recommendations')
param cpuUtilizationThreshold int = 20

@description('Tags to apply to all resources')
param resourceTags object = {
  purpose: 'sustainability'
  environment: environment
  project: 'carbon-optimization'
  deployedBy: 'bicep'
}

// Variables for resource naming
var resourcePrefix = 'carbon-opt'
var automationAccountName = 'aa-${resourcePrefix}-${uniqueSuffix}'
var keyVaultName = 'kv-${resourcePrefix}-${uniqueSuffix}'
var logicAppName = 'la-${resourcePrefix}-${uniqueSuffix}'
var logAnalyticsName = 'law-${resourcePrefix}-${uniqueSuffix}'
var storageAccountName = 'st${resourcePrefix}${uniqueSuffix}'
var runbookName = 'CarbonOptimizationRunbook'

// Log Analytics Workspace for centralized monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: resourceTags
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

// Storage Account for Logic Apps and automation workflows
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
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

// Key Vault for secure configuration storage
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: resourceTags
  properties: {
    enabledForDeployment: false
    enabledForTemplateDeployment: false
    enabledForDiskEncryption: false
    enableRbacAuthorization: true
    tenantId: tenant().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Azure Automation Account with managed identity
resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    encryption: {
      keySource: 'Microsoft.Automation'
    }
  }
}

// PowerShell runbook for carbon optimization logic
resource carbonOptimizationRunbook 'Microsoft.Automation/automationAccounts/runbooks@2020-01-13-preview' = {
  parent: automationAccount
  name: runbookName
  properties: {
    runbookType: 'PowerShell'
    description: 'Automated carbon-aware cost optimization based on emissions data'
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/Azure/azure-docs-powershell-samples/master/automation/empty-runbook.ps1'
      version: '1.0.0.0'
    }
  }
}

// Daily carbon optimization schedule
resource dailyOptimizationSchedule 'Microsoft.Automation/automationAccounts/schedules@2020-01-13-preview' = {
  parent: automationAccount
  name: 'DailyCarbonOptimization'
  properties: {
    description: 'Daily carbon optimization analysis and actions'
    frequency: 'Day'
    interval: 1
    startTime: '2025-01-01T02:00:00Z'
    timeZone: 'UTC'
  }
}

// Peak carbon optimization schedule
resource peakOptimizationSchedule 'Microsoft.Automation/automationAccounts/schedules@2020-01-13-preview' = {
  parent: automationAccount
  name: 'PeakCarbonOptimization'
  properties: {
    description: 'Optimization during peak carbon intensity periods'
    frequency: 'Day'
    interval: 1
    startTime: '2025-01-01T18:00:00Z'
    timeZone: 'UTC'
  }
}

// Logic App for carbon optimization orchestration
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
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
            startTime: '2025-01-01T02:00:00Z'
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Get_Carbon_Intensity_Data: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: 'https://api.carbonintensity.org.uk/intensity'
          }
        }
        Parse_Carbon_Intensity: {
          type: 'ParseJson'
          inputs: {
            content: '@body(\'Get_Carbon_Intensity_Data\')'
            schema: {
              type: 'object'
              properties: {
                data: {
                  type: 'array'
                  items: {
                    type: 'object'
                    properties: {
                      intensity: {
                        type: 'object'
                        properties: {
                          actual: {
                            type: 'integer'
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          runAfter: {
            Get_Carbon_Intensity_Data: ['Succeeded']
          }
        }
        Check_Carbon_Intensity_Threshold: {
          type: 'If'
          expression: {
            and: [
              {
                less: [
                  '@body(\'Parse_Carbon_Intensity\')?[\'data\']?[0]?[\'intensity\']?[\'actual\']'
                  200
                ]
              }
            ]
          }
          actions: {
            Start_Carbon_Optimization_Runbook: {
              type: 'Http'
              inputs: {
                method: 'POST'
                uri: 'https://management.azure.com/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Automation/automationAccounts/${automationAccountName}/runbooks/${runbookName}/start?api-version=2020-01-13-preview'
                headers: {
                  'Content-Type': 'application/json'
                }
                body: {
                  properties: {
                    parameters: {
                      SubscriptionId: subscription().subscriptionId
                      ResourceGroupName: resourceGroup().name
                      KeyVaultName: keyVaultName
                    }
                  }
                }
                authentication: {
                  type: 'ManagedServiceIdentity'
                }
              }
            }
            Log_Optimization_Trigger: {
              type: 'Http'
              inputs: {
                method: 'POST'
                uri: 'https://${logAnalyticsName}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01'
                headers: {
                  'Content-Type': 'application/json'
                  'Log-Type': 'CarbonOptimization'
                }
                body: {
                  timestamp: '@utcnow()'
                  carbonIntensity: '@body(\'Parse_Carbon_Intensity\')?[\'data\']?[0]?[\'intensity\']?[\'actual\']'
                  action: 'optimization_triggered'
                  reason: 'low_carbon_intensity'
                }
                authentication: {
                  type: 'ManagedServiceIdentity'
                }
              }
              runAfter: {
                Start_Carbon_Optimization_Runbook: ['Succeeded']
              }
            }
          }
        }
      }
    }
  }
}

// Key Vault secrets for configuration thresholds
resource carbonThresholdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'carbon-threshold-kg'
  properties: {
    value: string(carbonThresholdKg)
    attributes: {
      enabled: true
    }
  }
}

resource costThresholdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'cost-threshold-usd'
  properties: {
    value: string(costThresholdUsd)
    attributes: {
      enabled: true
    }
  }
}

resource minCarbonReductionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'min-carbon-reduction-percent'
  properties: {
    value: string(minCarbonReductionPercent)
    attributes: {
      enabled: true
    }
  }
}

resource cpuUtilizationSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'cpu-utilization-threshold'
  properties: {
    value: string(cpuUtilizationThreshold)
    attributes: {
      enabled: true
    }
  }
}

// Role assignments for Automation Account managed identity
resource automationCostManagementReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, automationAccount.id, 'CostManagementReader')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '72fafb9e-0641-4937-9268-a91bfd8191a3') // Cost Management Reader
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource automationVMContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, automationAccount.id, 'VirtualMachineContributor')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9980e02c-c2be-4d73-94e8-173b1dc7cf3c') // Virtual Machine Contributor
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource automationKeyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, automationAccount.id, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignments for Logic App managed identity
resource logicAppAutomationContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(automationAccount.id, logicApp.id, 'AutomationContributor')
  scope: automationAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f353d9bd-d4a6-484e-a77a-8050b599b867') // Automation Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logicAppLogAnalyticsContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalyticsWorkspace.id, logicApp.id, 'LogAnalyticsContributor')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293') // Log Analytics Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logicAppReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, logicApp.id, 'Reader')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs for verification and integration
@description('Resource Group name where resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('Automation Account name for carbon optimization')
output automationAccountName string = automationAccount.name

@description('Key Vault name for secure configuration storage')
output keyVaultName string = keyVault.name

@description('Logic App name for orchestration workflows')
output logicAppName string = logicApp.name

@description('Log Analytics workspace name for monitoring')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Storage account name for Logic Apps')
output storageAccountName string = storageAccount.name

@description('Automation Account managed identity principal ID')
output automationAccountPrincipalId string = automationAccount.identity.principalId

@description('Logic App managed identity principal ID')
output logicAppPrincipalId string = logicApp.identity.principalId

@description('Key Vault URI for programmatic access')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Log Analytics workspace ID for integration')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Carbon optimization runbook name')
output runbookName string = runbookName

@description('Daily optimization schedule name')
output dailyScheduleName string = dailyOptimizationSchedule.name

@description('Peak optimization schedule name')
output peakScheduleName string = peakOptimizationSchedule.name