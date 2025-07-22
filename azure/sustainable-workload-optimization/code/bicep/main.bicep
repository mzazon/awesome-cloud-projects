@description('The location where resources will be deployed')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment type (dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'sustainability'
  environment: environment
  project: 'carbon-optimization'
}

@description('Email address for alert notifications')
param alertEmail string

@description('Webhook URL for notifications (optional)')
param webhookUrl string = ''

@description('Log Analytics workspace pricing tier')
@allowed([
  'pergb2018'
  'Free'
  'Standalone'
  'PerNode'
  'Standard'
  'Premium'
])
param logAnalyticsWorkspaceSku string = 'pergb2018'

@description('Carbon optimization alert threshold')
param carbonOptimizationThreshold int = 100

@description('Enable automatic remediation')
param enableAutomaticRemediation bool = true

// Variables for resource names
var resourceNames = {
  logAnalyticsWorkspace: 'law-carbon-opt-${uniqueSuffix}'
  automationAccount: 'aa-carbon-opt-${uniqueSuffix}'
  workbook: 'carbon-optimization-dashboard-${uniqueSuffix}'
  actionGroup: 'CarbonOptimizationAlerts-${uniqueSuffix}'
  alertRule: 'HighCarbonImpactAlert-${uniqueSuffix}'
  storageAccount: 'stcarbonopt${uniqueSuffix}'
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsWorkspaceSku
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for Automation Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: false
    allowCrossTenantReplication: true
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

// Automation Account
resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: resourceNames.automationAccount
  location: location
  tags: tags
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
    publicNetworkAccess: true
  }
}

// Role Assignment for Automation Account - Carbon Optimization Reader
resource carbonOptimizationReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, 'Carbon Optimization Reader', automationAccount.id)
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'fa0d39e6-28e5-40cf-8521-1eb320653a4c') // Carbon Optimization Reader
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for Automation Account - Contributor
resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, 'Contributor', automationAccount.id)
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// PowerShell Runbook for Carbon Monitoring
resource carbonMonitoringRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'CarbonOptimizationMonitoring'
  properties: {
    runbookType: 'PowerShell'
    logVerbose: false
    logProgress: false
    description: 'Monitor carbon emissions and generate optimization recommendations'
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/quickstarts/microsoft.automation/101-automation-runbook-getvms/Runbooks/Get-AzureVMTutorial.ps1'
      version: '1.0.0.0'
    }
  }
}

// PowerShell Runbook for Automated Remediation
resource automatedRemediationRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'AutomatedCarbonRemediation'
  properties: {
    runbookType: 'PowerShell'
    logVerbose: false
    logProgress: false
    description: 'Automated remediation for carbon optimization recommendations'
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/quickstarts/microsoft.automation/101-automation-runbook-getvms/Runbooks/Get-AzureVMTutorial.ps1'
      version: '1.0.0.0'
    }
  }
}

// Schedule for Daily Carbon Monitoring
resource dailyMonitoringSchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'DailyCarbonMonitoring'
  properties: {
    description: 'Daily carbon optimization monitoring'
    startTime: dateTimeAdd(utcNow(), 'P1D', 'yyyy-MM-ddTHH:mm:ss')
    interval: 1
    frequency: 'Day'
    timeZone: 'UTC'
  }
}

// Job Schedule linking runbook to schedule
resource carbonMonitoringJobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: automationAccount
  name: guid(carbonMonitoringRunbook.id, dailyMonitoringSchedule.id)
  properties: {
    schedule: {
      name: dailyMonitoringSchedule.name
    }
    runbook: {
      name: carbonMonitoringRunbook.name
    }
    parameters: {
      SubscriptionId: subscription().subscriptionId
      WorkspaceId: logAnalyticsWorkspace.properties.customerId
    }
  }
}

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: resourceNames.actionGroup
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'CarbonOpt'
    enabled: true
    emailReceivers: [
      {
        name: 'CarbonOptimizationAdmin'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
    webhookReceivers: webhookUrl != '' ? [
      {
        name: 'CarbonOptimizationWebhook'
        serviceUri: webhookUrl
        useCommonAlertSchema: true
      }
    ] : []
  }
}

// Scheduled Query Rule for Carbon Optimization Alerts
resource carbonOptimizationAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: resourceNames.alertRule
  location: location
  tags: tags
  properties: {
    description: 'Alert when carbon optimization opportunities are detected'
    severity: 2
    enabled: true
    scopes: [
      logAnalyticsWorkspace.id
    ]
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    targetResourceTypes: [
      'Microsoft.OperationalInsights/workspaces'
    ]
    criteria: {
      allOf: [
        {
          query: 'CarbonOptimization_CL | where CarbonSavingsEstimate_d > ${carbonOptimizationThreshold} | count'
          timeAggregation: 'Count'
          dimensions: []
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

// Azure Monitor Workbook for Carbon Optimization
resource carbonOptimizationWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'carbon-optimization-workbook')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Carbon Optimization Dashboard'
    description: 'Comprehensive carbon optimization monitoring and insights'
    category: 'workbook'
    serializedData: '''
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# Carbon Optimization Dashboard\\n\\nThis workbook provides comprehensive insights into your Azure carbon footprint and optimization opportunities."
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "CarbonOptimization_CL\\n| where TimeGenerated >= ago(30d)\\n| summarize TotalCarbonSavings = sum(CarbonSavingsEstimate_d) by bin(TimeGenerated, 1d)\\n| render timechart",
        "size": 0,
        "title": "Carbon Savings Trend (30 Days)",
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "CarbonOptimization_CL\\n| where TimeGenerated >= ago(7d)\\n| summarize Count = count() by Category_s\\n| render piechart",
        "size": 0,
        "title": "Optimization Opportunities by Category",
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "CarbonOptimization_CL\\n| where TimeGenerated >= ago(1d)\\n| summarize TotalSavings = sum(CarbonSavingsEstimate_d), Count = count() by OptimizationAction_s\\n| order by TotalSavings desc",
        "size": 0,
        "title": "Top Optimization Actions (Last 24 Hours)",
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces"
      }
    }
  ]
}
'''
    sourceId: logAnalyticsWorkspace.id
  }
}

// Data Collection Rule for Carbon Optimization
resource carbonOptimizationDataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-carbon-optimization-${uniqueSuffix}'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataSources: {
      logFiles: [
        {
          name: 'CarbonOptimizationLogs'
          streams: [
            'Microsoft-Table-CarbonOptimization'
          ]
          filePatterns: [
            '/var/log/carbon-optimization/*.log'
          ]
          format: 'text'
          settings: {
            text: {
              recordStartTimestamp: {
                timestamp: '%Y-%m-%d %H:%M:%S'
                timezone: 'UTC'
              }
            }
          }
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: 'carbonOptimizationWorkspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Table-CarbonOptimization'
        ]
        destinations: [
          'carbonOptimizationWorkspace'
        ]
        transformKql: 'source | extend CarbonSavingsEstimate_d = todouble(CarbonSavingsEstimate_s), TimeGenerated = now()'
        outputStream: 'Custom-CarbonOptimization_CL'
      }
    ]
  }
}

// Outputs
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId
output automationAccountId string = automationAccount.id
output automationAccountIdentityPrincipalId string = automationAccount.identity.principalId
output workbookId string = carbonOptimizationWorkbook.id
output actionGroupId string = actionGroup.id
output alertRuleId string = carbonOptimizationAlert.id
output storageAccountId string = storageAccount.id
output carbonMonitoringRunbookName string = carbonMonitoringRunbook.name
output automatedRemediationRunbookName string = automatedRemediationRunbook.name
output dailyMonitoringScheduleName string = dailyMonitoringSchedule.name
output resourceGroupName string = resourceGroup().name
output subscriptionId string = subscription().subscriptionId