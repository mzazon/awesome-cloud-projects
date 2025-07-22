// ============================================================================
// Azure Cost Optimization Infrastructure with Azure Copilot and Azure Monitor
// ============================================================================
// This template deploys a comprehensive cost optimization solution that leverages
// Azure Copilot's AI capabilities with Azure Monitor for automated infrastructure
// cost optimization and resource right-sizing.

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Budget amount for cost alerts (in USD)')
@minValue(100)
@maxValue(100000)
param budgetAmount int = 5000

@description('Budget alert threshold percentage')
@minValue(50)
@maxValue(100)
param budgetThreshold int = 80

@description('Email addresses for budget notifications')
param notificationEmails array = []

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('Enable diagnostic settings for subscription-level logging')
param enableSubscriptionDiagnostics bool = true

@description('Tags to apply to all resources')
param resourceTags object = {
  Environment: environment
  Purpose: 'cost-optimization'
  DeployedBy: 'bicep-template'
  ManagedBy: 'azure-automation'
}

// ============================================================================
// Variables
// ============================================================================

var resourcePrefix = 'costopt'
var logAnalyticsWorkspaceName = 'law-${resourcePrefix}-${uniqueSuffix}'
var automationAccountName = 'aa-${resourcePrefix}-${uniqueSuffix}'
var actionGroupName = 'ag-${resourcePrefix}-${uniqueSuffix}'
var budgetName = 'budget-${resourcePrefix}-${environment}'
var logicAppName = 'la-${resourcePrefix}-${uniqueSuffix}'
var applicationInsightsName = 'ai-${resourcePrefix}-${uniqueSuffix}'

// ============================================================================
// Log Analytics Workspace
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 10
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// Application Insights for enhanced monitoring
// ============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
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

// ============================================================================
// Azure Automation Account
// ============================================================================

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'Basic'
    }
    encryption: {
      keySource: 'Microsoft.Automation'
    }
    publicNetworkAccess: true
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ============================================================================
// PowerShell Runbooks for Cost Optimization
// ============================================================================

resource vmOptimizationRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'Optimize-VMSize'
  properties: {
    runbookType: 'PowerShell'
    logVerbose: true
    logProgress: true
    description: 'Automated VM right-sizing based on utilization metrics'
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/quickstarts/microsoft.automation/automation-runbook-vmrightsize/VMRightSizeRunbook.ps1'
      version: '1.0.0.0'
    }
  }
}

resource storageOptimizationRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'Optimize-StorageTier'
  properties: {
    runbookType: 'PowerShell'
    logVerbose: true
    logProgress: true
    description: 'Automated storage tier optimization based on access patterns'
    draft: {
      inEdit: false
    }
  }
}

resource sqlOptimizationRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'Optimize-SQLDatabase'
  properties: {
    runbookType: 'PowerShell'
    logVerbose: true
    logProgress: true
    description: 'Automated SQL Database DTU/vCore optimization based on performance metrics'
    draft: {
      inEdit: false
    }
  }
}

// ============================================================================
// Automation Schedules for Regular Optimization
// ============================================================================

resource weeklyOptimizationSchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'WeeklyOptimization'
  properties: {
    description: 'Weekly cost optimization analysis and implementation'
    startTime: dateTimeAdd(utcNow(), 'PT1H')
    frequency: 'Week'
    interval: 1
    timeZone: 'UTC'
  }
}

resource dailyReportSchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'DailyCostReport'
  properties: {
    description: 'Daily cost analysis and reporting'
    startTime: dateTimeAdd(utcNow(), 'PT2H')
    frequency: 'Day'
    interval: 1
    timeZone: 'UTC'
  }
}

// ============================================================================
// Action Group for Alerts
// ============================================================================

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: resourceTags
  properties: {
    groupShortName: 'CostOptim'
    enabled: true
    emailReceivers: [for email in notificationEmails: {
      name: 'EmailAlert-${indexOf(notificationEmails, email)}'
      emailAddress: email
      useCommonAlertSchema: true
    }]
    automationRunbookReceivers: [
      {
        automationAccountId: automationAccount.id
        runbookName: vmOptimizationRunbook.name
        webhookResourceId: ''
        isGlobalRunbook: false
        name: 'VMOptimization'
        serviceUri: ''
        useCommonAlertSchema: true
      }
    ]
  }
}

// ============================================================================
// Budget Configuration
// ============================================================================

resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: budgetName
  properties: {
    timePeriod: {
      startDate: '${utcNow('yyyy-MM')}-01'
      endDate: '${dateTimeAdd(utcNow(), 'P1Y', 'yyyy-MM')}-01'
    }
    timeGrain: 'Monthly'
    amount: budgetAmount
    category: 'Cost'
    notifications: {
      'Actual_GreaterThan_${budgetThreshold}_Percent': {
        enabled: true
        operator: 'GreaterThan'
        threshold: budgetThreshold
        contactEmails: notificationEmails
        contactRoles: [
          'Owner'
          'Contributor'
        ]
        thresholdType: 'Actual'
      }
      'Forecasted_GreaterThan_90_Percent': {
        enabled: true
        operator: 'GreaterThan'
        threshold: 90
        contactEmails: notificationEmails
        contactRoles: [
          'Owner'
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

// ============================================================================
// Metric Alerts for Cost Anomaly Detection
// ============================================================================

resource highCostAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'HighCostAlert-${uniqueSuffix}'
  location: 'Global'
  tags: resourceTags
  properties: {
    description: 'Alert when daily costs exceed threshold indicating potential cost anomaly'
    severity: 2
    enabled: true
    scopes: [
      subscription().id
    ]
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'DailyCostThreshold'
          metricName: 'UsageQuantity'
          metricNamespace: 'Microsoft.Consumption/usageDetails'
          operator: 'GreaterThan'
          threshold: budgetAmount / 30 // Daily threshold based on monthly budget
          timeAggregation: 'Total'
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

// ============================================================================
// Logic App for Orchestrating Cost Optimization Workflows
// ============================================================================

resource costOptimizationLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: resourceTags
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        automationAccountName: {
          type: 'string'
          defaultValue: automationAccountName
        }
        resourceGroupName: {
          type: 'string'
          defaultValue: resourceGroup().name
        }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                alertType: {
                  type: 'string'
                }
                resourceId: {
                  type: 'string'
                }
                recommendationType: {
                  type: 'string'
                }
              }
            }
          }
        }
      }
      actions: {
        'Switch_on_alert_type': {
          type: 'Switch'
          expression: '@triggerBody()?[\'alertType\']'
          cases: {
            VM_Optimization: {
              case: 'vm-rightsizing'
              actions: {
                'Start_VM_Optimization_Runbook': {
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'azureautomation\'][\'connectionId\']'
                      }
                    }
                    method: 'put'
                    path: '/subscriptions/${subscription().subscriptionId}/resourceGroups/@{parameters(\'resourceGroupName\')}/providers/Microsoft.Automation/automationAccounts/@{parameters(\'automationAccountName\')}/jobs'
                    queries: {
                      runbookName: 'Optimize-VMSize'
                      'api-version': '2015-10-31'
                    }
                    body: {
                      properties: {
                        runbook: {
                          name: 'Optimize-VMSize'
                        }
                        parameters: {
                          ResourceId: '@triggerBody()?[\'resourceId\']'
                        }
                      }
                    }
                  }
                }
              }
            }
            Storage_Optimization: {
              case: 'storage-tiering'
              actions: {
                'Start_Storage_Optimization_Runbook': {
                  type: 'ApiConnection'
                  inputs: {
                    host: {
                      connection: {
                        name: '@parameters(\'$connections\')[\'azureautomation\'][\'connectionId\']'
                      }
                    }
                    method: 'put'
                    path: '/subscriptions/${subscription().subscriptionId}/resourceGroups/@{parameters(\'resourceGroupName\')}/providers/Microsoft.Automation/automationAccounts/@{parameters(\'automationAccountName\')}/jobs'
                    queries: {
                      runbookName: 'Optimize-StorageTier'
                      'api-version': '2015-10-31'
                    }
                  }
                }
              }
            }
          }
          default: {
            actions: {
              'Log_Unknown_Alert_Type': {
                type: 'Compose'
                inputs: 'Unknown alert type: @{triggerBody()?[\'alertType\']}'
              }
            }
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          azureautomation: {
            connectionId: ''
            connectionName: 'azureautomation'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azureautomation'
          }
        }
      }
    }
  }
}

// ============================================================================
// Diagnostic Settings for Subscription-level Logging
// ============================================================================

resource subscriptionDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableSubscriptionDiagnostics) {
  name: 'CostOptimizationDiagnostics'
  scope: subscription()
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'Administrative'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'ServiceHealth'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'ResourceHealth'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'Alert'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'Policy'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// ============================================================================
// Role Assignments for Automation Account
// ============================================================================

// Virtual Machine Contributor role for VM optimization
resource vmContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, automationAccount.id, 'VM-Contributor')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9980e02c-c2be-4d73-94e8-173b1dc7cf3c') // Virtual Machine Contributor
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Data Contributor role for storage optimization
resource storageContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, automationAccount.id, 'Storage-Contributor')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// SQL DB Contributor role for database optimization
resource sqlContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, automationAccount.id, 'SQL-Contributor')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9b7fa17d-e63e-47b0-bb0a-15c516ac86ec') // SQL DB Contributor
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Cost Management Reader role for cost analysis
resource costManagementReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, automationAccount.id, 'Cost-Reader')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '72fafb9e-0641-4937-9268-a91bfd8191a3') // Cost Management Reader
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Automation Account ID')
output automationAccountId string = automationAccount.id

@description('Automation Account Name')
output automationAccountName string = automationAccount.name

@description('Automation Account Principal ID')
output automationAccountPrincipalId string = automationAccount.identity.principalId

@description('Action Group ID')
output actionGroupId string = actionGroup.id

@description('Budget Name')
output budgetName string = budget.name

@description('Logic App ID')
output logicAppId string = costOptimizationLogicApp.id

@description('Logic App Trigger URL')
output logicAppTriggerUrl string = costOptimizationLogicApp.listCallbackUrl().value

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Deployment Summary')
output deploymentSummary object = {
  logAnalyticsWorkspace: logAnalyticsWorkspace.name
  automationAccount: automationAccount.name
  budgetAmount: budgetAmount
  budgetThreshold: budgetThreshold
  location: location
  environment: environment
  runbooks: [
    vmOptimizationRunbook.name
    storageOptimizationRunbook.name
    sqlOptimizationRunbook.name
  ]
  schedules: [
    weeklyOptimizationSchedule.name
    dailyReportSchedule.name
  ]
}