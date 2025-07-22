@description('Automation Account module for Update Management')

// Parameters
@description('Location for Automation Account')
param location string

@description('Automation Account name')
param automationAccountName string

@description('Log Analytics Workspace name')
param logAnalyticsWorkspaceName string

@description('Resource tags')
param tags object

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
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Automation Account
resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: tags
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

// Link Log Analytics Workspace to Automation Account
resource automationAccountLinkedService 'Microsoft.OperationalInsights/workspaces/linkedServices@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'Automation'
  properties: {
    resourceId: automationAccount.id
  }
}

// Update Management Solution
resource updateManagementSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'Updates(${logAnalyticsWorkspaceName})'
  location: location
  tags: tags
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: 'Updates(${logAnalyticsWorkspaceName})'
    publisher: 'Microsoft'
    product: 'OMSGallery/Updates'
    promotionCode: ''
  }
}

// Change Tracking Solution
resource changeTrackingSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'ChangeTracking(${logAnalyticsWorkspaceName})'
  location: location
  tags: tags
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: 'ChangeTracking(${logAnalyticsWorkspaceName})'
    publisher: 'Microsoft'
    product: 'OMSGallery/ChangeTracking'
    promotionCode: ''
  }
}

// Disaster Recovery Orchestration Runbook
resource drOrchestrationRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: 'DrRecoveryOrchestration'
  properties: {
    runbookType: 'PowerShell'
    logVerbose: false
    logProgress: false
    description: 'Orchestrates disaster recovery failover process'
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/quickstarts/microsoft.automation/101-automation-runbook-getvms/Runbooks/Get-AzureVMTutorial.ps1'
    }
  }
}

// Update Configuration Schedule
resource updateSchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: 'WeeklyUpdateSchedule'
  properties: {
    description: 'Weekly update schedule for disaster recovery VMs'
    startTime: '2024-01-01T02:00:00+00:00'
    frequency: 'Week'
    interval: 1
    advancedSchedule: {
      weekDays: [
        'Sunday'
      ]
    }
  }
}

// Outputs
@description('Automation Account ID')
output automationAccountId string = automationAccount.id

@description('Automation Account name')
output automationAccountName string = automationAccount.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace customer ID')
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('Log Analytics Workspace primary shared key')
output logAnalyticsWorkspacePrimarySharedKey string = logAnalyticsWorkspace.listKeys().primarySharedKey