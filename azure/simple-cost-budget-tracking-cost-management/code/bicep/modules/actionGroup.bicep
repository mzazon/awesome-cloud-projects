// =====================================================================================
// Azure Monitor Action Group Module for Cost Budget Alerts
// =====================================================================================
// This module creates an Azure Monitor Action Group that handles email notifications
// for budget alerts. The action group serves as a reusable notification endpoint
// that can trigger multiple communication channels when cost thresholds are exceeded.
// =====================================================================================

@description('Name of the Azure Monitor Action Group')
param actionGroupName string

@description('Azure region for resource deployment')
param location string

@description('Email address for budget alert notifications')
param alertEmailAddress string

@description('Resource tags for consistent labeling')
param tags object = {}

// =====================================================================================
// VARIABLES
// =====================================================================================

var actionGroupShortName = 'CostAlert'
var emailReceiverName = 'budget-admin'

// =====================================================================================
// AZURE MONITOR ACTION GROUP
// =====================================================================================

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global' // Action Groups are global resources
  tags: tags
  properties: {
    groupShortName: actionGroupShortName
    enabled: true
    emailReceivers: [
      {
        name: emailReceiverName
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
    eventHubReceivers: []
  }
}

// =====================================================================================
// OUTPUTS
// =====================================================================================

@description('The name of the Azure Monitor Action Group')
output actionGroupName string = actionGroup.name

@description('The resource ID of the Azure Monitor Action Group')
output actionGroupId string = actionGroup.id

@description('The short name of the action group')
output actionGroupShortName string = actionGroupShortName

@description('The configured email address for notifications')
output notificationEmailAddress string = alertEmailAddress

@description('Action group enabled status')
output actionGroupEnabled bool = actionGroup.properties.enabled