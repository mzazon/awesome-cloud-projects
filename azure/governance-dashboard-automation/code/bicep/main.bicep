// ======================================================================================
// Azure Governance Dashboard Infrastructure - Main Bicep Template
// ======================================================================================
// This template deploys a complete governance dashboard solution using:
// - Azure Monitor Workbooks for visualization
// - Log Analytics Workspace for data collection
// - Logic Apps for automation workflows
// - Action Groups for alert management
// - Alert Rules for governance monitoring
// ======================================================================================

@description('The Azure region where resources should be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Resource naming prefix')
@minLength(2)
@maxLength(10)
param namePrefix string = 'gov'

@description('Resource naming suffix for uniqueness')
@minLength(3)
@maxLength(6)
param nameSuffix string = uniqueString(resourceGroup().id)

@description('Log Analytics workspace pricing tier')
@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
])
param logAnalyticsSkuName string = 'PerGB2018'

@description('Log Analytics data retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Enable governance alerts')
param enableAlerts bool = true

@description('Alert evaluation frequency in minutes')
@allowed([
  1
  5
  15
  30
  60
])
param alertEvaluationFrequency int = 15

@description('Alert severity level')
@allowed([
  0
  1
  2
  3
  4
])
param alertSeverity int = 2

@description('Notification email address for governance alerts')
param notificationEmail string

@description('Slack webhook URL for notifications (optional)')
param slackWebhookUrl string = ''

@description('Tags to apply to all resources')
param resourceTags object = {
  Purpose: 'Governance Dashboard'
  Environment: environment
  ManagedBy: 'Bicep'
  Project: 'Azure Governance'
}

// ======================================================================================
// Variables and Resource Naming
// ======================================================================================

var resourceNames = {
  logAnalyticsWorkspace: '${namePrefix}-law-${environment}-${nameSuffix}'
  workbook: '${namePrefix}-wb-${environment}-${nameSuffix}'
  logicApp: '${namePrefix}-la-${environment}-${nameSuffix}'
  actionGroup: '${namePrefix}-ag-${environment}-${nameSuffix}'
  alertRule: '${namePrefix}-alert-${environment}-${nameSuffix}'
  applicationInsights: '${namePrefix}-ai-${environment}-${nameSuffix}'
}

// ======================================================================================
// Log Analytics Workspace
// ======================================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: logAnalyticsSkuName
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ======================================================================================
// Application Insights for Workbook Dependencies
// ======================================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ======================================================================================
// Logic App Module Deployment
// ======================================================================================

module logicAppModule 'modules/logicapp.bicep' = {
  name: 'logicAppDeployment'
  params: {
    location: location
    logicAppName: resourceNames.logicApp
    resourceTags: resourceTags
    logAnalyticsWorkspaceId: logAnalyticsWorkspace.id
    logAnalyticsCustomerId: logAnalyticsWorkspace.properties.customerId
    logAnalyticsPrimaryKey: listKeys(logAnalyticsWorkspace.id, '2023-09-01').primarySharedKey
    slackWebhookUrl: slackWebhookUrl
    environment: environment
  }
}

// ======================================================================================
// Workbook Module Deployment
// ======================================================================================

module workbookModule 'modules/workbook.bicep' = {
  name: 'workbookDeployment'
  params: {
    location: location
    workbookDisplayName: 'Azure Governance Dashboard - ${environment}'
    workbookDescription: 'Comprehensive governance and compliance dashboard for Azure resources in ${environment} environment'
    workbookCategory: 'governance'
    resourceTags: resourceTags
    applicationInsightsResourceId: applicationInsights.id
  }
}

// ======================================================================================
// Monitoring Module Deployment
// ======================================================================================

module monitoringModule 'modules/monitoring.bicep' = if (enableAlerts) {
  name: 'monitoringDeployment'
  params: {
    location: location
    actionGroupName: resourceNames.actionGroup
    alertRuleName: resourceNames.alertRule
    resourceTags: resourceTags
    logAnalyticsWorkspaceId: logAnalyticsWorkspace.id
    notificationEmail: notificationEmail
    logicAppTriggerUrl: logicAppModule.outputs.logicAppTriggerUrl
    logicAppResourceId: logicAppModule.outputs.logicAppId
    enableAlerts: enableAlerts
    alertEvaluationFrequency: alertEvaluationFrequency
    alertSeverity: alertSeverity
    environment: environment
  }
}

// ======================================================================================
// RBAC Role Assignment for Logic App (Resource Graph Reader)
// ======================================================================================

// Get the built-in Resource Graph Reader role definition
resource resourceGraphReaderRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '4a9ae827-6dc8-4573-8ac7-8239d42aa03f' // Resource Graph Reader role ID
}

// Assign Resource Graph Reader role to Logic App managed identity
resource logicAppRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logicAppModule.outputs.logicAppId, resourceGraphReaderRole.id, subscription().id)
  scope: subscription()
  properties: {
    principalId: logicAppModule.outputs.logicAppPrincipalId
    roleDefinitionId: resourceGraphReaderRole.id
    principalType: 'ServicePrincipal'
  }
}

// Assign Log Analytics Contributor role to Logic App for writing logs
resource logAnalyticsContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Contributor role ID
}

resource logicAppLogAnalyticsRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logicAppModule.outputs.logicAppId, logAnalyticsContributorRole.id, logAnalyticsWorkspace.id)
  scope: logAnalyticsWorkspace
  properties: {
    principalId: logicAppModule.outputs.logicAppPrincipalId
    roleDefinitionId: logAnalyticsContributorRole.id
    principalType: 'ServicePrincipal'
  }
}

// ======================================================================================
// Outputs
// ======================================================================================

@description('Resource group name where resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace Customer ID')
output logAnalyticsCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('Governance Workbook ID')
output workbookId string = workbookModule.outputs.workbookId

@description('Governance Workbook URL')
output workbookUrl string = workbookModule.outputs.workbookUrl

@description('Logic App ID')
output logicAppId string = logicAppModule.outputs.logicAppId

@description('Logic App trigger URL for webhook integration')
output logicAppTriggerUrl string = logicAppModule.outputs.logicAppTriggerUrl

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Action Group ID (if alerts enabled)')
output actionGroupId string = enableAlerts ? monitoringModule.outputs.actionGroupId : ''

@description('Monitoring summary (if alerts enabled)')
output monitoringSummary object = enableAlerts ? monitoringModule.outputs.monitoringSummary : {}

@description('Resource tags applied to all resources')
output appliedTags object = resourceTags

@description('Sample Resource Graph queries for governance monitoring')
output sampleQueries object = {
  'Resources without required tags': 'resources | where tags !has "Environment" or tags !has "Owner" or tags !has "CostCenter" | project name, type, resourceGroup, subscriptionId, location, tags | limit 1000'
  'Non-compliant resource locations': 'resources | where location !in ("eastus", "westus", "centralus") | project name, type, resourceGroup, location, subscriptionId | limit 1000'
  'Policy compliance summary': 'policyresources | where type == "microsoft.policyinsights/policystates" | summarize count() by complianceState'
  'Security recommendations': 'securityresources | where type == "microsoft.security/assessments" | summarize count() by status.code'
  'Resource distribution': 'resources | summarize count() by type, location | order by count_ desc'
  'Recent resource deployments': 'resources | extend createdTime = properties.createdTime | where createdTime >= ago(7d) | project name, type, resourceGroup, location, createdTime | order by createdTime desc'
  'Resources without tags': 'resources | where tags == "{}" or isnull(tags) | project name, type, resourceGroup, location, subscriptionId'
  'Expensive resource types': 'resources | where type in ("microsoft.compute/virtualmachines", "microsoft.sql/servers/databases", "microsoft.storage/storageaccounts") | summarize count() by type, location'
}

@description('Deployment summary and next steps')
output deploymentSummary object = {
  status: 'Complete'
  message: 'Azure Governance Dashboard successfully deployed'
  environment: environment
  resourcesCreated: {
    logAnalyticsWorkspace: logAnalyticsWorkspace.name
    applicationInsights: applicationInsights.name
    workbook: workbookModule.outputs.workbookDisplayName
    logicApp: logicAppModule.outputs.logicAppName
    actionGroup: enableAlerts ? monitoringModule.outputs.actionGroupName : 'Not created (alerts disabled)'
    alertRules: enableAlerts ? monitoringModule.outputs.monitoringSummary.alertRulesCreated : 0
  }
  nextSteps: [
    'Access the workbook using the provided URL'
    'Configure additional Resource Graph queries for your governance requirements'
    'Test the Logic App by manually triggering a governance alert'
    'Review and customize alert thresholds based on your environment'
    'Set up additional notification channels in the action group'
    'Configure Azure Policy assignments to generate compliance data'
    'Review security assessments in Microsoft Defender for Cloud'
  ]
  documentation: [
    'https://docs.microsoft.com/en-us/azure/governance/resource-graph/'
    'https://docs.microsoft.com/en-us/azure/azure-monitor/platform/workbooks-overview'
    'https://docs.microsoft.com/en-us/azure/logic-apps/'
    'https://docs.microsoft.com/en-us/azure/governance/policy/'
  ]
  estimatedMonthlyCost: {
    logAnalytics: 'Variable based on data ingestion'
    applicationInsights: 'Variable based on telemetry volume'
    logicApp: '$0.000025 per action execution'
    workbook: 'No additional charge'
    alerts: '$0.10 per alert rule per month'
    actionGroup: 'No charge for email notifications'
  }
}