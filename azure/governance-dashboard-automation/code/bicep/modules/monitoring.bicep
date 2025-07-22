// ======================================================================================
// Monitoring Module for Governance Alerts
// ======================================================================================
// This module creates Azure Monitor components including action groups and alert rules
// for governance monitoring and automated responses to policy violations.
// ======================================================================================

@description('The Azure region where monitoring resources should be deployed')
param location string = resourceGroup().location

@description('Action group name')
param actionGroupName string

@description('Alert rule name')
param alertRuleName string

@description('Tags to apply to monitoring resources')
param resourceTags object = {}

@description('Log Analytics workspace resource ID for alert scoping')
param logAnalyticsWorkspaceId string

@description('Notification email address')
param notificationEmail string

@description('Logic App trigger URL for webhook notifications')
param logicAppTriggerUrl string

@description('Logic App resource ID for direct integration')
param logicAppResourceId string

@description('Enable or disable alerts')
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

@description('Alert severity level (0=Critical, 1=Error, 2=Warning, 3=Informational, 4=Verbose)')
@allowed([
  0
  1
  2
  3
  4
])
param alertSeverity int = 2

@description('Environment name for alert context')
param environment string = 'dev'

// ======================================================================================
// Action Group for Governance Alerts
// ======================================================================================

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (enableAlerts) {
  name: actionGroupName
  location: 'global' // Action groups are global resources
  tags: resourceTags
  properties: {
    groupShortName: 'GovAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'GovernanceTeamEmail'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ]
    webhookReceivers: [
      {
        name: 'GovernanceLogicAppWebhook'
        serviceUri: logicAppTriggerUrl
        useCommonAlertSchema: true
      }
    ]
    logicAppReceivers: [
      {
        name: 'GovernanceAutomationWorkflow'
        resourceId: logicAppResourceId
        callbackUrl: logicAppTriggerUrl
        useCommonAlertSchema: true
      }
    ]
    azureFunctionReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    armRoleReceivers: [
      {
        name: 'GovernanceOwners'
        roleId: '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' // Owner role
        useCommonAlertSchema: true
      }
      {
        name: 'GovernanceContributors'
        roleId: 'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor role
        useCommonAlertSchema: true
      }
    ]
    eventHubReceivers: []
  }
}

// ======================================================================================
// Alert Rules for Different Governance Scenarios
// ======================================================================================

// Policy Violations Alert Rule
resource policyViolationAlertRule 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (enableAlerts) {
  name: '${alertRuleName}-policy-violations'
  location: location
  tags: union(resourceTags, {
    AlertType: 'PolicyViolation'
    Purpose: 'Governance'
  })
  properties: {
    displayName: 'Policy Violation Detection'
    description: 'Monitors for Azure Policy violations and non-compliant resources'
    severity: alertSeverity
    enabled: true
    evaluationFrequency: 'PT${alertEvaluationFrequency}M'
    windowSize: 'PT${alertEvaluationFrequency}M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            // Policy violation detection query
            AzureActivity
            | where TimeGenerated >= ago(${alertEvaluationFrequency}m)
            | where CategoryValue == "Policy"
            | where ActivityStatusValue in ("Failed", "Error")
            | where OperationNameValue contains "policy"
            | extend PolicyName = tostring(Properties.policies[0].policyDefinitionName)
            | extend ResourceId = tostring(Properties.resource)
            | extend ComplianceState = "NonCompliant"
            | summarize 
                ViolationCount = count(),
                LastViolation = max(TimeGenerated),
                PolicyNames = make_set(PolicyName),
                Resources = make_set(ResourceId)
                by bin(TimeGenerated, 5m)
            | where ViolationCount > 0
          '''
          timeAggregation: 'Count'
          dimensions: [
            {
              name: 'PolicyNames'
              operator: 'Include'
              values: ['*']
            }
          ]
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
      actionGroups: enableAlerts ? [actionGroup.id] : []
      customProperties: {
        AlertType: 'PolicyViolation'
        Environment: environment
        AutomationEnabled: 'true'
        Severity: string(alertSeverity)
      }
    }
    autoMitigate: true
    checkWorkspaceAlertsStorageConfigured: false
  }
}

// Resource Compliance Alert Rule
resource resourceComplianceAlertRule 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (enableAlerts) {
  name: '${alertRuleName}-resource-compliance'
  location: location
  tags: union(resourceTags, {
    AlertType: 'ResourceCompliance'
    Purpose: 'Governance'
  })
  properties: {
    displayName: 'Resource Compliance Monitoring'
    description: 'Monitors for resources missing required tags or deployed in non-approved locations'
    severity: alertSeverity
    enabled: true
    evaluationFrequency: 'PT${alertEvaluationFrequency}M'
    windowSize: 'PT${alertEvaluationFrequency}M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            // Resource compliance monitoring query
            AzureActivity
            | where TimeGenerated >= ago(${alertEvaluationFrequency}m)
            | where CategoryValue == "Administrative"
            | where OperationNameValue in (
                "Microsoft.Resources/deployments/write",
                "Microsoft.Resources/subscriptions/resourceGroups/deployments/write"
            )
            | where ActivityStatusValue == "Succeeded"
            | extend ResourceId = tostring(Properties.resource)
            | extend ResourceType = tostring(Properties.resourceType)
            | extend Location = tostring(Properties.location)
            | where Location !in ("eastus", "westus", "centralus", "eastus2", "westus2")
                or Properties !has "Environment"
                or Properties !has "Owner"
                or Properties !has "CostCenter"
            | summarize 
                NonCompliantCount = count(),
                LastDeployment = max(TimeGenerated),
                Resources = make_set(ResourceId),
                Locations = make_set(Location)
                by bin(TimeGenerated, 5m)
            | where NonCompliantCount > 0
          '''
          timeAggregation: 'Count'
          dimensions: [
            {
              name: 'Locations'
              operator: 'Include'
              values: ['*']
            }
          ]
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
      actionGroups: enableAlerts ? [actionGroup.id] : []
      customProperties: {
        AlertType: 'ResourceCompliance'
        Environment: environment
        AutomationEnabled: 'true'
        Severity: string(alertSeverity)
      }
    }
    autoMitigate: true
    checkWorkspaceAlertsStorageConfigured: false
  }
}

// Security Assessment Alert Rule
resource securityAssessmentAlertRule 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (enableAlerts) {
  name: '${alertRuleName}-security-assessment'
  location: location
  tags: union(resourceTags, {
    AlertType: 'SecurityAssessment'
    Purpose: 'Governance'
  })
  properties: {
    displayName: 'Security Assessment Monitoring'
    description: 'Monitors for new security recommendations and unhealthy security assessments'
    severity: alertSeverity
    enabled: true
    evaluationFrequency: 'PT${alertEvaluationFrequency}M'
    windowSize: 'PT${alertEvaluationFrequency}M'
    scopes: [
      logAnalyticsWorkspaceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            // Security assessment monitoring query
            SecurityEvent
            | where TimeGenerated >= ago(${alertEvaluationFrequency}m)
            | where EventID in (4625, 4648, 4719, 4720, 4722, 4724, 4732, 4733, 4756)
            | extend SecurityEventType = case(
                EventID == 4625, "Failed Logon",
                EventID == 4648, "Explicit Credential Logon",
                EventID == 4719, "System Audit Policy Changed",
                EventID == 4720, "User Account Created",
                EventID == 4722, "User Account Enabled",
                EventID == 4724, "Password Reset Attempt",
                EventID == 4732, "Member Added to Security Group",
                EventID == 4733, "Member Removed from Security Group",
                EventID == 4756, "Universal Group Created",
                "Other Security Event"
            )
            | summarize 
                SecurityEventCount = count(),
                LastEvent = max(TimeGenerated),
                EventTypes = make_set(SecurityEventType),
                Accounts = make_set(Account)
                by bin(TimeGenerated, 5m)
            | where SecurityEventCount >= 5  // Alert when 5 or more security events occur
          '''
          timeAggregation: 'Count'
          dimensions: [
            {
              name: 'EventTypes'
              operator: 'Include'
              values: ['*']
            }
          ]
          operator: 'GreaterThanOrEqual'
          threshold: 5
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: enableAlerts ? [actionGroup.id] : []
      customProperties: {
        AlertType: 'SecurityAssessment'
        Environment: environment
        AutomationEnabled: 'true'
        Severity: string(alertSeverity)
      }
    }
    autoMitigate: true
    checkWorkspaceAlertsStorageConfigured: false
  }
}

// ======================================================================================
// Outputs
// ======================================================================================

@description('Action Group resource ID')
output actionGroupId string = enableAlerts ? actionGroup.id : ''

@description('Action Group name')
output actionGroupName string = enableAlerts ? actionGroup.name : ''

@description('Policy Violation Alert Rule ID')
output policyViolationAlertRuleId string = enableAlerts ? policyViolationAlertRule.id : ''

@description('Resource Compliance Alert Rule ID')
output resourceComplianceAlertRuleId string = enableAlerts ? resourceComplianceAlertRule.id : ''

@description('Security Assessment Alert Rule ID')
output securityAssessmentAlertRuleId string = enableAlerts ? securityAssessmentAlertRule.id : ''

@description('Summary of created monitoring resources')
output monitoringSummary object = {
  actionGroupCreated: enableAlerts
  alertRulesCreated: enableAlerts ? 3 : 0
  alertTypes: enableAlerts ? [
    'PolicyViolation'
    'ResourceCompliance'
    'SecurityAssessment'
  ] : []
  evaluationFrequency: '${alertEvaluationFrequency} minutes'
  severity: alertSeverity
}