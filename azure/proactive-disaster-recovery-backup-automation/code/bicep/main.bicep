@description('Main Bicep template for Proactive Disaster Recovery with Backup Center Automation')

// Parameters
@description('Primary Azure region for resource deployment')
param primaryLocation string = resourceGroup().location

@description('Secondary Azure region for disaster recovery')
param secondaryLocation string

@description('Environment suffix for resource naming')
param environmentSuffix string = 'prod'

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = take(uniqueString(resourceGroup().id), 6)

@description('Resource tags to apply to all resources')
param resourceTags object = {
  environment: environmentSuffix
  purpose: 'disaster-recovery'
  managedBy: 'bicep'
  costCenter: 'operations'
}

@description('Admin email address for notifications')
param adminEmail string

@description('Admin phone number for SMS notifications (format: +1234567890)')
param adminPhoneNumber string

@description('Microsoft Teams webhook URL for notifications')
param teamsWebhookUrl string = ''

@description('Backup policies configuration')
param backupPolicies object = {
  vmPolicy: {
    name: 'DRVMPolicy'
    scheduleRunTimes: ['02:00:00']
    dailyRetentionDurationCount: 30
    weeklyRetentionDurationCount: 12
    weeklyRetentionDaysOfTheWeek: ['Sunday']
  }
  sqlPolicy: {
    name: 'DRSQLPolicy'
    scheduleRunTimes: ['22:00:00']
    dailyRetentionDurationCount: 30
  }
}

@description('Log Analytics workspace configuration')
param logAnalyticsConfig object = {
  sku: 'PerGB2018'
  retentionInDays: 30
  dailyQuotaGb: 10
}

@description('Alert rules configuration')
param alertConfig object = {
  evaluationFrequency: 'PT5M'
  windowSize: 'PT15M'
  autoMitigate: true
  enabled: true
}

// Variables
var namingPrefix = 'dr-${environmentSuffix}-${uniqueSuffix}'
var primaryRsvName = 'rsv-${namingPrefix}-primary'
var secondaryRsvName = 'rsv-${namingPrefix}-secondary'
var logAnalyticsWorkspaceName = 'law-${namingPrefix}-monitoring'
var storageAccountName = 'st${replace(namingPrefix, '-', '')}backup'
var actionGroupName = 'ag-${namingPrefix}-alerts'
var logicAppName = 'la-${namingPrefix}-orchestration'

// Resource Group for backup resources (created separately if needed)
var backupResourceGroupName = 'rg-${namingPrefix}-backup'

// Primary Recovery Services Vault
resource primaryRecoveryServicesVault 'Microsoft.RecoveryServices/vaults@2023-08-01' = {
  name: primaryRsvName
  location: primaryLocation
  tags: resourceTags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    restoreSettings: {
      crossSubscriptionRestoreSettings: {
        crossSubscriptionRestoreState: 'Enabled'
      }
    }
    securitySettings: {
      immutabilitySettings: {
        state: 'Unlocked'
      }
      softDeleteSettings: {
        softDeleteState: 'Enabled'
        softDeleteRetentionPeriodInDays: 14
      }
    }
    upgradeDetails: {
      startTimeUtc: ''
      lastUpdatedTimeUtc: ''
      status: 'NotStarted'
      triggerType: 'UserTriggered'
    }
  }

  // Backup Storage Configuration
  resource backupStorageConfig 'backupstorageconfig@2023-08-01' = {
    name: 'vaultstorageconfig'
    properties: {
      storageModelType: 'GeoRedundant'
      crossRegionRestoreFlag: true
    }
  }

  // VM Backup Policy
  resource vmBackupPolicy 'backupPolicies@2023-08-01' = {
    name: backupPolicies.vmPolicy.name
    properties: {
      backupManagementType: 'AzureIaasVM'
      instantRpRetentionRangeInDays: 2
      policyType: 'V2'
      schedulePolicy: {
        schedulePolicyType: 'SimpleSchedulePolicy'
        scheduleRunFrequency: 'Daily'
        scheduleRunTimes: backupPolicies.vmPolicy.scheduleRunTimes
        scheduleWeeklyFrequency: 0
      }
      retentionPolicy: {
        retentionPolicyType: 'LongTermRetentionPolicy'
        dailySchedule: {
          retentionTimes: backupPolicies.vmPolicy.scheduleRunTimes
          retentionDuration: {
            count: backupPolicies.vmPolicy.dailyRetentionDurationCount
            durationType: 'Days'
          }
        }
        weeklySchedule: {
          daysOfTheWeek: backupPolicies.vmPolicy.weeklyRetentionDaysOfTheWeek
          retentionTimes: backupPolicies.vmPolicy.scheduleRunTimes
          retentionDuration: {
            count: backupPolicies.vmPolicy.weeklyRetentionDurationCount
            durationType: 'Weeks'
          }
        }
      }
      instantRPDetails: {
        azureBackupRGNamePrefix: 'AzureBackupRG'
        azureBackupRGNameSuffix: 'snapshots'
      }
      timeZone: 'UTC'
    }
  }

  // SQL Backup Policy
  resource sqlBackupPolicy 'backupPolicies@2023-08-01' = {
    name: backupPolicies.sqlPolicy.name
    properties: {
      backupManagementType: 'AzureWorkload'
      workLoadType: 'SQLDataBase'
      schedulePolicy: {
        schedulePolicyType: 'SimpleSchedulePolicy'
        scheduleRunFrequency: 'Daily'
        scheduleRunTimes: backupPolicies.sqlPolicy.scheduleRunTimes
      }
      retentionPolicy: {
        retentionPolicyType: 'LongTermRetentionPolicy'
        dailySchedule: {
          retentionTimes: backupPolicies.sqlPolicy.scheduleRunTimes
          retentionDuration: {
            count: backupPolicies.sqlPolicy.dailyRetentionDurationCount
            durationType: 'Days'
          }
        }
      }
    }
  }
}

// Secondary Recovery Services Vault (for disaster recovery)
resource secondaryRecoveryServicesVault 'Microsoft.RecoveryServices/vaults@2023-08-01' = {
  name: secondaryRsvName
  location: secondaryLocation
  tags: union(resourceTags, { region: 'secondary' })
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    restoreSettings: {
      crossSubscriptionRestoreSettings: {
        crossSubscriptionRestoreState: 'Enabled'
      }
    }
    securitySettings: {
      immutabilitySettings: {
        state: 'Unlocked'
      }
      softDeleteSettings: {
        softDeleteState: 'Enabled'
        softDeleteRetentionPeriodInDays: 14
      }
    }
  }

  // Secondary Vault Backup Storage Configuration
  resource secondaryBackupStorageConfig 'backupstorageconfig@2023-08-01' = {
    name: 'vaultstorageconfig'
    properties: {
      storageModelType: 'GeoRedundant'
      crossRegionRestoreFlag: true
    }
  }
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: primaryLocation
  tags: resourceTags
  properties: {
    sku: {
      name: logAnalyticsConfig.sku
    }
    retentionInDays: logAnalyticsConfig.retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    workspaceCapping: {
      dailyQuotaGb: logAnalyticsConfig.dailyQuotaGb
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for Logic Apps and orchestration
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: primaryLocation
  tags: resourceTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: false
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

// Action Group for notifications
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: resourceTags
  properties: {
    groupShortName: 'DRAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'admin-email'
        emailAddress: adminEmail
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: [
      {
        name: 'admin-sms'
        countryCode: take(adminPhoneNumber, 2)
        phoneNumber: skip(adminPhoneNumber, 2)
      }
    ]
    webhookReceivers: !empty(teamsWebhookUrl) ? [
      {
        name: 'teams-webhook'
        serviceUri: teamsWebhookUrl
        useCommonAlertSchema: true
      }
    ] : []
    azureFunctionReceivers: []
    armRoleReceivers: []
    logicAppReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
  }
}

// Diagnostic Settings for Primary Recovery Services Vault
resource primaryVaultDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'DiagnosticSettings-${primaryRsvName}'
  scope: primaryRecoveryServicesVault
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'Health'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Diagnostic Settings for Secondary Recovery Services Vault
resource secondaryVaultDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'DiagnosticSettings-${secondaryRsvName}'
  scope: secondaryRecoveryServicesVault
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'Health'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Alert Rule for Backup Job Failures
resource backupJobFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'BackupJobFailureAlert-${uniqueSuffix}'
  location: 'Global'
  tags: resourceTags
  properties: {
    description: 'Alert when backup jobs fail'
    severity: 2
    enabled: alertConfig.enabled
    scopes: [
      primaryRecoveryServicesVault.id
    ]
    evaluationFrequency: alertConfig.evaluationFrequency
    windowSize: alertConfig.windowSize
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'BackupJobFailure'
          metricName: 'BackupHealthEvent'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: alertConfig.autoMitigate
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// Alert Rule for Recovery Vault Health
resource recoveryVaultHealthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'RecoveryVaultHealthAlert-${uniqueSuffix}'
  location: 'Global'
  tags: resourceTags
  properties: {
    description: 'Alert when Recovery Services Vault becomes unhealthy'
    severity: 1
    enabled: alertConfig.enabled
    scopes: [
      primaryRecoveryServicesVault.id
    ]
    evaluationFrequency: alertConfig.evaluationFrequency
    windowSize: alertConfig.windowSize
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'VaultHealth'
          metricName: 'Health'
          operator: 'LessThan'
          threshold: 1
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: alertConfig.autoMitigate
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// Scheduled Query Rule for Backup Storage Consumption
resource backupStorageAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'BackupStorageConsumptionAlert-${uniqueSuffix}'
  location: primaryLocation
  tags: resourceTags
  properties: {
    displayName: 'Backup Storage Consumption Alert'
    description: 'Alert when backup storage consumption exceeds threshold'
    severity: 3
    enabled: alertConfig.enabled
    evaluationFrequency: 'PT60M'
    windowSize: 'PT60M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: 'AzureBackupReport | where TimeGenerated > ago(1h) | where StorageConsumedInMBs > 100000'
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
    autoMitigate: alertConfig.autoMitigate
    actions: {
      actionGroups: [
        actionGroup.id
      ]
      customProperties: {}
    }
  }
}

// Logic App for disaster recovery orchestration
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: primaryLocation
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        subscriptionId: {
          defaultValue: subscription().subscriptionId
          type: 'String'
        }
        resourceGroupName: {
          defaultValue: resourceGroup().name
          type: 'String'
        }
        primaryVaultName: {
          defaultValue: primaryRsvName
          type: 'String'
        }
        secondaryVaultName: {
          defaultValue: secondaryRsvName
          type: 'String'
        }
        teamsWebhookUrl: {
          defaultValue: teamsWebhookUrl
          type: 'String'
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
                data: {
                  type: 'object'
                  properties: {
                    context: {
                      type: 'object'
                      properties: {
                        subscriptionId: {
                          type: 'string'
                        }
                        resourceGroupName: {
                          type: 'string'
                        }
                        resourceName: {
                          type: 'string'
                        }
                        alertType: {
                          type: 'string'
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      actions: {
        Initialize_Variables: {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'alertContext'
                type: 'object'
                value: '@triggerBody()?[\'data\']?[\'context\']'
              }
              {
                name: 'isDisasterRecoveryNeeded'
                type: 'boolean'
                value: false
              }
            ]
          }
          runAfter: {}
        }
        Evaluate_Alert_Severity: {
          type: 'Switch'
          expression: '@variables(\'alertContext\')?[\'alertType\']'
          cases: {
            BackupFailure: {
              case: 'BackupJobFailure'
              actions: {
                Set_DR_Flag: {
                  type: 'SetVariable'
                  inputs: {
                    name: 'isDisasterRecoveryNeeded'
                    value: true
                  }
                }
              }
            }
            VaultHealth: {
              case: 'VaultHealthFailure'
              actions: {
                Set_Critical_DR_Flag: {
                  type: 'SetVariable'
                  inputs: {
                    name: 'isDisasterRecoveryNeeded'
                    value: true
                  }
                }
              }
            }
          }
          default: {
            actions: {
              Log_Unknown_Alert: {
                type: 'Compose'
                inputs: {
                  message: 'Unknown alert type received'
                  alertType: '@variables(\'alertContext\')?[\'alertType\']'
                }
              }
            }
          }
          runAfter: {
            Initialize_Variables: [
              'Succeeded'
            ]
          }
        }
        Check_If_DR_Needed: {
          type: 'If'
          expression: {
            and: [
              {
                equals: [
                  '@variables(\'isDisasterRecoveryNeeded\')'
                  true
                ]
              }
            ]
          }
          actions: {
            Send_Teams_Notification: {
              type: 'Http'
              inputs: {
                method: 'POST'
                uri: '@parameters(\'teamsWebhookUrl\')'
                headers: {
                  'Content-Type': 'application/json'
                }
                body: {
                  '@type': 'MessageCard'
                  '@context': 'http://schema.org/extensions'
                  themeColor: 'FF5733'
                  summary: 'Disaster Recovery Alert'
                  sections: [
                    {
                      activityTitle: '🚨 Disaster Recovery Alert'
                      activitySubtitle: 'Backup failure detected - Initiating automated recovery procedures'
                      facts: [
                        {
                          name: 'Alert Type'
                          value: '@variables(\'alertContext\')?[\'alertType\']'
                        }
                        {
                          name: 'Resource'
                          value: '@variables(\'alertContext\')?[\'resourceName\']'
                        }
                        {
                          name: 'Timestamp'
                          value: '@utcNow()'
                        }
                      ]
                      markdown: true
                    }
                  ]
                  potentialAction: [
                    {
                      '@type': 'OpenUri'
                      name: 'View Azure Portal'
                      targets: [
                        {
                          os: 'default'
                          uri: 'https://portal.azure.com'
                        }
                      ]
                    }
                  ]
                }
              }
              runAfter: {}
            }
            Check_Backup_Status: {
              type: 'Http'
              inputs: {
                method: 'GET'
                uri: 'https://management.azure.com/subscriptions/@{parameters(\'subscriptionId\')}/resourceGroups/@{parameters(\'resourceGroupName\')}/providers/Microsoft.RecoveryServices/vaults/@{parameters(\'primaryVaultName\')}/backupJobs?api-version=2023-08-01'
                authentication: {
                  type: 'ManagedServiceIdentity'
                }
              }
              runAfter: {
                Send_Teams_Notification: [
                  'Succeeded'
                ]
              }
            }
            Evaluate_Cross_Region_Restore: {
              type: 'Compose'
              inputs: {
                message: 'Evaluating need for cross-region restore'
                primaryVault: '@parameters(\'primaryVaultName\')'
                secondaryVault: '@parameters(\'secondaryVaultName\')'
                restoreAction: 'Consider cross-region restore if primary region is unavailable'
              }
              runAfter: {
                Check_Backup_Status: [
                  'Succeeded'
                  'Failed'
                ]
              }
            }
          }
          else: {
            actions: {
              Log_No_Action_Needed: {
                type: 'Compose'
                inputs: {
                  message: 'Alert received but no disaster recovery action needed'
                  alertType: '@variables(\'alertContext\')?[\'alertType\']'
                }
              }
            }
          }
          runAfter: {
            Evaluate_Alert_Severity: [
              'Succeeded'
            ]
          }
        }
      }
      outputs: {}
    }
    parameters: {}
  }
}

// Role Assignment for Logic App to access Recovery Services
resource logicAppRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(primaryRecoveryServicesVault.id, logicApp.id, 'Backup Contributor')
  scope: primaryRecoveryServicesVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e467623-bb1f-42f4-a55d-6e525e11384b') // Backup Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for Logic App to access secondary vault
resource logicAppSecondaryRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(secondaryRecoveryServicesVault.id, logicApp.id, 'Backup Contributor')
  scope: secondaryRecoveryServicesVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e467623-bb1f-42f4-a55d-6e525e11384b') // Backup Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Monitoring Workbook for disaster recovery dashboard
resource monitoringWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'disaster-recovery-dashboard')
  location: primaryLocation
  tags: resourceTags
  kind: 'shared'
  properties: {
    displayName: 'Disaster Recovery Dashboard'
    description: 'Comprehensive visibility into backup operations, recovery readiness, and disaster recovery metrics'
    serializedData: '''
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# Disaster Recovery Dashboard\\n\\nThis dashboard provides comprehensive visibility into backup operations, recovery readiness, and disaster recovery metrics across all protected resources."
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AddonAzureBackupJobs\\n| where TimeGenerated > ago(24h)\\n| summarize BackupJobs = count() by JobOperation, JobStatus\\n| render piechart",
        "size": 0,
        "title": "Backup Job Status by Operation Type (Last 24 Hours)",
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces",
        "crossComponentResources": []
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AddonAzureBackupStorage\\n| where TimeGenerated > ago(7d)\\n| summarize TotalStorageGB = sum(StorageConsumedInMBs)/1024 by bin(TimeGenerated, 1d)\\n| render timechart",
        "size": 0,
        "title": "Storage Consumption Trend (Last 7 Days)",
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AddonAzureBackupAlerts\\n| where TimeGenerated > ago(24h)\\n| summarize AlertCount = count() by AlertStatus, bin(TimeGenerated, 1h)\\n| render columnchart",
        "size": 0,
        "title": "Backup Alerts Over Time (Last 24 Hours)",
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AddonAzureBackupProtectedInstance\\n| where TimeGenerated > ago(1d)\\n| summarize ProtectedInstances = dcount(BackupItemUniqueId) by ResourceType\\n| render barchart",
        "size": 0,
        "title": "Protected Instances by Resource Type",
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      }
    }
  ]
}
'''
    category: 'workbook'
    sourceId: logAnalyticsWorkspace.id
    revision: '1'
  }
}

// Outputs
@description('Primary Recovery Services Vault resource ID')
output primaryRecoveryServicesVaultId string = primaryRecoveryServicesVault.id

@description('Primary Recovery Services Vault name')
output primaryRecoveryServicesVaultName string = primaryRecoveryServicesVault.name

@description('Secondary Recovery Services Vault resource ID')
output secondaryRecoveryServicesVaultId string = secondaryRecoveryServicesVault.id

@description('Secondary Recovery Services Vault name')
output secondaryRecoveryServicesVaultName string = secondaryRecoveryServicesVault.name

@description('Log Analytics Workspace resource ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Storage Account resource ID')
output storageAccountId string = storageAccount.id

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Action Group resource ID')
output actionGroupId string = actionGroup.id

@description('Action Group name')
output actionGroupName string = actionGroup.name

@description('Logic App resource ID')
output logicAppId string = logicApp.id

@description('Logic App name')
output logicAppName string = logicApp.name

@description('Logic App callback URL for webhook integration')
output logicAppCallbackUrl string = listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicAppName, 'manual'), '2019-05-01').value

@description('Monitoring Workbook resource ID')
output monitoringWorkbookId string = monitoringWorkbook.id

@description('VM Backup Policy name')
output vmBackupPolicyName string = primaryRecoveryServicesVault::vmBackupPolicy.name

@description('SQL Backup Policy name')
output sqlBackupPolicyName string = primaryRecoveryServicesVault::sqlBackupPolicy.name

@description('Backup Center URL for centralized management')
output backupCenterUrl string = 'https://portal.azure.com/#view/Microsoft_Azure_RecoveryServices/BackupCenterMenuBlade/~/overview'

@description('Azure Monitor Workbooks URL for dashboard access')
output workbookUrl string = 'https://portal.azure.com/#view/Microsoft_Azure_Monitoring_Logs/WorkbookTemplateBlade/~/resourceId/${uri(environment().portal, monitoringWorkbook.id)}'