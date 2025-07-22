// Main Bicep template for Automating Proactive Infrastructure Health Monitoring
// with Azure Service Health and Azure Update Manager

@description('Location for all resources')
param location string = resourceGroup().location

@description('Prefix for all resource names')
param resourcePrefix string = 'health-monitor'

@description('Environment name (dev, staging, production)')
@allowed(['dev', 'staging', 'production'])
param environment string = 'production'

@description('Email address for Service Health alerts')
param alertEmail string

@description('Log Analytics workspace pricing tier')
@allowed(['Free', 'Standalone', 'PerNode', 'PerGB2018'])
param logAnalyticsSkuName string = 'PerGB2018'

@description('Maintenance schedule start date and time')
param maintenanceStartDateTime string = '2025-01-15T02:00:00Z'

@description('Maintenance window duration in hours')
param maintenanceDurationHours int = 4

@description('Maintenance recurrence frequency')
@allowed(['Daily', 'Weekly', 'Monthly'])
param maintenanceRecurrence string = 'Weekly'

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var workspaceName = '${resourcePrefix}-law-${uniqueSuffix}'
var actionGroupName = '${resourcePrefix}-ag-${uniqueSuffix}'
var logicAppName = '${resourcePrefix}-la-${uniqueSuffix}'
var automationAccountName = '${resourcePrefix}-aa-${uniqueSuffix}'
var maintenanceConfigName = '${resourcePrefix}-mc-${uniqueSuffix}'
var workbookName = '${resourcePrefix}-wb-${uniqueSuffix}'

// Common tags
var commonTags = {
  Environment: environment
  Purpose: 'health-monitoring'
  CreatedBy: 'bicep-template'
  Solution: 'proactive-infrastructure-monitoring'
}

// Logic App workflow definition
var logicAppDefinition = {
  '$schema': 'https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#'
  contentVersion: '1.0.0.0'
  parameters: {
    automationWebhookUrl: {
      type: 'string'
      defaultValue: ''
    }
    logAnalyticsWorkspaceName: {
      type: 'string'
      defaultValue: workspaceName
    }
  }
  triggers: {
    service_health_webhook: {
      type: 'Request'
      kind: 'Http'
      inputs: {
        schema: {
          type: 'object'
          properties: {
            schemaId: {
              type: 'string'
            }
            data: {
              type: 'object'
              properties: {
                status: {
                  type: 'string'
                }
                context: {
                  type: 'object'
                }
                properties: {
                  type: 'object'
                }
              }
            }
          }
        }
      }
    }
  }
  actions: {
    parse_service_health: {
      type: 'ParseJson'
      inputs: {
        content: '@triggerBody()'
        schema: {
          type: 'object'
          properties: {
            schemaId: {
              type: 'string'
            }
            data: {
              type: 'object'
              properties: {
                status: {
                  type: 'string'
                }
                context: {
                  type: 'object'
                }
                properties: {
                  type: 'object'
                }
              }
            }
          }
        }
      }
    }
    check_patch_compliance: {
      type: 'Http'
      inputs: {
        method: 'GET'
        uri: 'https://management.azure.com/subscriptions/@{subscription().subscriptionId}/providers/Microsoft.Maintenance/updates?api-version=2021-09-01-preview'
        authentication: {
          type: 'ManagedServiceIdentity'
        }
      }
      runAfter: {
        parse_service_health: [
          'Succeeded'
        ]
      }
    }
    evaluate_remediation_need: {
      type: 'Condition'
      expression: {
        and: [
          {
            greater: [
              '@length(body(\'check_patch_compliance\')?.value)'
              0
            ]
          }
          {
            equals: [
              '@body(\'parse_service_health\')?.data?.status'
              'Active'
            ]
          }
        ]
      }
      actions: {
        trigger_remediation: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '@parameters(\'automationWebhookUrl\')'
            body: {
              serviceHealthEvent: '@body(\'parse_service_health\')'
              patchCompliance: '@body(\'check_patch_compliance\')'
              correlationId: '@workflow().run.name'
              timestamp: '@utcnow()'
            }
          }
        }
        log_remediation_trigger: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://management.azure.com/subscriptions/@{subscription().subscriptionId}/resourceGroups/@{resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/@{parameters(\'logAnalyticsWorkspaceName\')}/api/logs?api-version=2020-08-01'
            authentication: {
              type: 'ManagedServiceIdentity'
            }
            body: [
              {
                TimeGenerated: '@utcnow()'
                CorrelationId: '@workflow().run.name'
                ServiceHealthEvent: '@body(\'parse_service_health\')'
                PatchComplianceStatus: '@body(\'check_patch_compliance\')'
                RemediationTriggered: true
                EventType: 'ProactiveRemediation'
              }
            ]
            headers: {
              'Log-Type': 'HealthMonitoring'
            }
          }
        }
      }
      else: {
        actions: {
          log_no_remediation_needed: {
            type: 'Http'
            inputs: {
              method: 'POST'
              uri: 'https://management.azure.com/subscriptions/@{subscription().subscriptionId}/resourceGroups/@{resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/@{parameters(\'logAnalyticsWorkspaceName\')}/api/logs?api-version=2020-08-01'
              authentication: {
                type: 'ManagedServiceIdentity'
              }
              body: [
                {
                  TimeGenerated: '@utcnow()'
                  CorrelationId: '@workflow().run.name'
                  ServiceHealthEvent: '@body(\'parse_service_health\')'
                  PatchComplianceStatus: '@body(\'check_patch_compliance\')'
                  RemediationTriggered: false
                  EventType: 'HealthMonitoring'
                }
              ]
              headers: {
                'Log-Type': 'HealthMonitoring'
              }
            }
          }
        }
      }
      runAfter: {
        check_patch_compliance: [
          'Succeeded'
        ]
      }
    }
  }
}

// Workbook template for health monitoring dashboard
var workbookTemplate = {
  version: 'Notebook/1.0'
  items: [
    {
      type: 1
      content: {
        json: '# Infrastructure Health Monitoring Dashboard\\n\\nThis dashboard provides comprehensive visibility into Service Health incidents and patch compliance status.'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'ServiceHealthResources | where type == "microsoft.resourcehealth/events" | summarize count() by tostring(properties.eventType)'
        size: 0
        title: 'Service Health Events Summary'
        timeContext: {
          durationMs: 2592000000
        }
        queryType: 1
        resourceType: 'microsoft.resourcegraph/resources'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'UpdateSummary | where Classification == "Critical Updates" | summarize count() by UpdateState'
        size: 0
        title: 'Critical Patch Compliance Status'
        timeContext: {
          durationMs: 86400000
        }
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'UpdateRunProgress | where InstallationStatus == "Failed" | summarize count() by Computer'
        size: 0
        title: 'Update Installation Failures by Computer'
        timeContext: {
          durationMs: 86400000
        }
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
      }
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'HealthMonitoring_CL | where EventType_s == "ProactiveRemediation" | summarize count() by bin(TimeGenerated, 1h)'
        size: 0
        title: 'Proactive Remediation Triggers Over Time'
        timeContext: {
          durationMs: 604800000
        }
        queryType: 0
        resourceType: 'microsoft.operationalinsights/workspaces'
      }
    }
  ]
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: logAnalyticsSkuName
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      immediatePurgeDataOn30Days: true
    }
  }
}

// Automation Account for remediation
resource automationAccount 'Microsoft.Automation/automationAccounts@2020-01-13-preview' = {
  name: automationAccountName
  location: location
  tags: commonTags
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

// Remediation Runbook
resource remediationRunbook 'Microsoft.Automation/automationAccounts/runbooks@2020-01-13-preview' = {
  parent: automationAccount
  name: 'Remediate-Critical-Patches'
  properties: {
    runbookType: 'PowerShell'
    description: 'Automated remediation for critical patch issues'
    draft: {
      inEdit: false
      contentHash: {
        algorithm: 'SHA256'
        value: 'sample-hash'
      }
    }
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/quickstarts/microsoft.automation/101-automation-runbook-getvms/Runbooks/Get-AzureVMTutorial.ps1'
      version: '1.0.0.0'
    }
  }
}

// Automation Webhook for remediation
resource automationAccountWebhook 'Microsoft.Automation/automationAccounts/webhooks@2020-01-13-preview' = {
  parent: automationAccount
  name: 'health-remediation-webhook'
  properties: {
    isEnabled: true
    runbook: {
      name: remediationRunbook.name
    }
    expiryTime: '2026-01-01T00:00:00Z'
  }
}

// Logic App for correlation workflow
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    definition: logicAppDefinition
    parameters: {
      automationWebhookUrl: {
        type: 'string'
        value: automationAccountWebhook.properties.uri
      }
      logAnalyticsWorkspaceName: {
        type: 'string'
        value: workspaceName
      }
    }
  }
}

// Action Group for Service Health alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: commonTags
  properties: {
    groupShortName: 'SvcHealth'
    enabled: true
    emailReceivers: [
      {
        name: 'admin'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
    webhookReceivers: [
      {
        name: 'health-webhook'
        serviceUri: logicApp.listCallbackUrl().value
        useCommonAlertSchema: true
      }
    ]
  }
}

// Service Health Alert Rule
resource serviceHealthAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'Service Health Issues'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'Alert for Azure Service Health incidents'
    enabled: true
    scopes: [
      subscription().id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ServiceHealth'
        }
        {
          field: 'properties.incidentType'
          equals: 'Incident'
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroup.id
        }
      ]
    }
  }
}

// Maintenance Configuration for patch management
resource maintenanceConfiguration 'Microsoft.Maintenance/maintenanceConfigurations@2021-09-01-preview' = {
  name: maintenanceConfigName
  location: location
  tags: commonTags
  properties: {
    maintenanceScope: 'InGuestPatch'
    maintenanceWindow: {
      startDateTime: maintenanceStartDateTime
      duration: '0${maintenanceDurationHours}:00'
      timeZone: 'UTC'
      recurEvery: maintenanceRecurrence == 'Weekly' ? '1Week' : maintenanceRecurrence == 'Daily' ? '1Day' : '1Month'
    }
    visibility: 'Custom'
    installPatches: {
      rebootSetting: 'IfRequired'
      windowsParameters: {
        classificationsToInclude: [
          'Critical'
          'Security'
          'UpdateRollup'
          'FeaturePack'
          'ServicePack'
          'Definition'
          'Tools'
          'Updates'
        ]
        excludeKbsRequiringReboot: false
      }
      linuxParameters: {
        classificationsToInclude: [
          'Critical'
          'Security'
          'Other'
        ]
      }
    }
  }
}

// Scheduled Query Alert for Critical Patch Compliance
resource criticalPatchAlert 'Microsoft.Insights/scheduledQueryRules@2021-08-01' = {
  name: 'Critical-Patch-Compliance-Alert'
  location: location
  tags: commonTags
  properties: {
    description: 'Alert when VMs have critical patches missing'
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    severity: 2
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: 'UpdateSummary | where Classification == "Critical Updates" and Computer != "" and UpdateState == "Needed" | distinct Computer'
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
  }
}

// Scheduled Query Alert for Update Installation Failures
resource updateFailureAlert 'Microsoft.Insights/scheduledQueryRules@2021-08-01' = {
  name: 'Update-Installation-Failures'
  location: location
  tags: commonTags
  properties: {
    description: 'Alert when update installations fail'
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    severity: 1
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: 'UpdateRunProgress | where InstallationStatus == "Failed" | distinct Computer'
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
  }
}

// Automation Effectiveness Metric Alert
resource automationEffectivenessAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Automation-Effectiveness-Metric'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'Alert when automation success rate drops below 90%'
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    severity: 3
    scopes: [
      automationAccount.id
    ]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'AutomationSuccessRate'
          metricName: 'TotalJob'
          operator: 'LessThan'
          threshold: 90
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

// Monitoring Workbook for Health Dashboard
resource monitoringWorkbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: workbookName
  location: location
  tags: commonTags
  kind: 'shared'
  properties: {
    displayName: 'Infrastructure Health Monitoring Dashboard'
    serializedData: string(workbookTemplate)
    category: 'health-monitoring'
    sourceId: logAnalyticsWorkspace.id
  }
}

// Role assignments for Logic App managed identity
resource logicAppReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logicApp.id, 'reader', resourceGroup().id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logicAppAutomationContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logicApp.id, 'automation-contributor', resourceGroup().id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f353d9bd-d4a6-484e-a77a-8050b599b867') // Automation Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logicAppLogAnalyticsContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logicApp.id, 'log-analytics-contributor', resourceGroup().id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293') // Log Analytics Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignments for Automation Account managed identity
resource automationAccountReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(automationAccount.id, 'reader', resourceGroup().id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource automationAccountUpdateManagementRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(automationAccount.id, 'update-management', resourceGroup().id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5fb5aef8-1081-4b8e-bb16-9d5d0385bab5') // Update Management Contributor
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output actionGroupId string = actionGroup.id
output logicAppId string = logicApp.id
output logicAppTriggerUrl string = logicApp.listCallbackUrl().value
output automationAccountId string = automationAccount.id
output automationAccountName string = automationAccount.name
output automationWebhookUrl string = automationAccountWebhook.properties.uri
output maintenanceConfigurationId string = maintenanceConfiguration.id
output workbookId string = monitoringWorkbook.id
output resourceGroupName string = resourceGroup().name
output deploymentLocation string = location