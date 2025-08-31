// =====================================================================================
// Simple Cost Budget Tracking with Cost Management - Main Bicep Template
// =====================================================================================
// This template deploys a comprehensive cost management solution with automated 
// budget tracking and email notifications using Azure Cost Management and Monitor.
// 
// Resources Created:
// - Resource Group for monitoring resources
// - Azure Monitor Action Group for email notifications
// - Subscription-level budget with multi-threshold alerts (50%, 80%, 100%)
// - Resource group-level budget with filtering capabilities
// =====================================================================================

targetScope = 'subscription'

// =====================================================================================
// PARAMETERS
// =====================================================================================

@description('Unique suffix for resource names (e.g., 6-character random string)')
@minLength(3)
@maxLength(8)
param uniqueSuffix string = uniqueString(subscription().subscriptionId, utcNow())

@description('Azure region for resource deployment')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'centralus'
  'northcentralus'
  'southcentralus'
  'westcentralus'
  'canadacentral'
  'canadaeast'
  'brazilsouth'
  'northeurope'
  'westeurope'
  'uksouth'
  'ukwest'
  'francecentral'
  'germanywestcentral'
  'norwayeast'
  'switzerlandnorth'
  'australiaeast'
  'australiasoutheast'
  'southeastasia'
  'eastasia'
  'japaneast'
  'japanwest'
  'koreacentral'
  'koreasouth'
  'southafricanorth'
  'uaenorth'
  'centralindia'
  'southindia'
  'westindia'
])
param location string = 'eastus'

@description('Email address for budget alert notifications')
@metadata({
  example: 'admin@company.com'
})
param alertEmailAddress string

@description('Monthly budget amount in USD for subscription-level monitoring')
@minValue(1)
@maxValue(100000)
param subscriptionBudgetAmount int = 100

@description('Monthly budget amount in USD for resource group-level monitoring')
@minValue(1)
@maxValue(100000)
param resourceGroupBudgetAmount int = 50

@description('Budget start date (YYYY-MM-DD format). Defaults to first day of current month')
param budgetStartDate string = dateTimeFromEpoch(dateTimeToEpoch(utcNow()), 'yyyy-MM-01')

@description('Budget end date (YYYY-MM-DD format). Defaults to 1 year from start date')
param budgetEndDate string = dateTimeAdd(budgetStartDate, 'P1Y', 'yyyy-MM-dd')

@description('Environment tag for resource categorization')
@allowed([
  'dev'
  'test'
  'stage'
  'prod'
  'demo'
])
param environment string = 'demo'

@description('Cost center or department for resource attribution')
param costCenter string = 'IT'

@description('Project name for resource grouping')
param projectName string = 'CostManagement'

// =====================================================================================
// VARIABLES
// =====================================================================================

var resourceGroupName = 'rg-cost-tracking-${uniqueSuffix}'
var actionGroupName = 'cost-alert-group-${uniqueSuffix}'
var subscriptionBudgetName = 'monthly-cost-budget-${uniqueSuffix}'
var resourceGroupBudgetName = 'rg-budget-${uniqueSuffix}'

// Common resource tags following Azure Well-Architected Framework
var commonTags = {
  Purpose: 'cost-monitoring'
  Environment: environment
  CostCenter: costCenter
  Project: projectName
  CreatedBy: 'bicep-template'
  CreatedDate: utcNow('yyyy-MM-dd')
  Recipe: 'simple-cost-budget-tracking'
}

// Budget notification thresholds with progressive escalation
var budgetNotifications = {
  fiftyPercent: {
    enabled: true
    operator: 'GreaterThan'
    threshold: 50
    contactEmails: [
      alertEmailAddress
    ]
    contactRoles: []
    thresholdType: 'Actual'
    locale: 'en-us'
  }
  eightyPercent: {
    enabled: true
    operator: 'GreaterThan'
    threshold: 80
    contactEmails: [
      alertEmailAddress
    ]
    contactRoles: []
    thresholdType: 'Actual'
    locale: 'en-us'
  }
  hundredPercent: {
    enabled: true
    operator: 'GreaterThan'
    threshold: 100
    contactEmails: [
      alertEmailAddress
    ]
    contactRoles: []
    thresholdType: 'Forecasted'
    locale: 'en-us'
  }
}

// =====================================================================================
// RESOURCE GROUP
// =====================================================================================

resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: commonTags
  properties: {}
}

// =====================================================================================
// AZURE MONITOR ACTION GROUP MODULE
// =====================================================================================

module actionGroup 'modules/actionGroup.bicep' = {
  name: 'actionGroupDeployment'
  scope: resourceGroup
  params: {
    actionGroupName: actionGroupName
    location: location
    alertEmailAddress: alertEmailAddress
    tags: commonTags
  }
}

// =====================================================================================
// SUBSCRIPTION-LEVEL BUDGET
// =====================================================================================

resource subscriptionBudget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: subscriptionBudgetName
  properties: {
    displayName: 'Monthly Subscription Budget - ${subscriptionBudgetName}'
    category: 'Cost'
    amount: subscriptionBudgetAmount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate
      endDate: budgetEndDate
    }
    filter: {}
    notifications: {
      'Actual_GreaterThan_50_Percent': {
        enabled: budgetNotifications.fiftyPercent.enabled
        operator: budgetNotifications.fiftyPercent.operator
        threshold: budgetNotifications.fiftyPercent.threshold
        contactEmails: budgetNotifications.fiftyPercent.contactEmails
        contactRoles: budgetNotifications.fiftyPercent.contactRoles
        contactGroups: [
          actionGroup.outputs.actionGroupId
        ]
        thresholdType: budgetNotifications.fiftyPercent.thresholdType
        locale: budgetNotifications.fiftyPercent.locale
      }
      'Actual_GreaterThan_80_Percent': {
        enabled: budgetNotifications.eightyPercent.enabled
        operator: budgetNotifications.eightyPercent.operator
        threshold: budgetNotifications.eightyPercent.threshold
        contactEmails: budgetNotifications.eightyPercent.contactEmails
        contactRoles: budgetNotifications.eightyPercent.contactRoles
        contactGroups: [
          actionGroup.outputs.actionGroupId
        ]
        thresholdType: budgetNotifications.eightyPercent.thresholdType
        locale: budgetNotifications.eightyPercent.locale
      }
      'Forecasted_GreaterThan_100_Percent': {
        enabled: budgetNotifications.hundredPercent.enabled
        operator: budgetNotifications.hundredPercent.operator
        threshold: budgetNotifications.hundredPercent.threshold
        contactEmails: budgetNotifications.hundredPercent.contactEmails
        contactRoles: budgetNotifications.hundredPercent.contactRoles
        contactGroups: [
          actionGroup.outputs.actionGroupId
        ]
        thresholdType: budgetNotifications.hundredPercent.thresholdType
        locale: budgetNotifications.hundredPercent.locale
      }
    }
  }
}

// =====================================================================================
// RESOURCE GROUP-LEVEL BUDGET WITH FILTERING
// =====================================================================================

resource resourceGroupBudget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: resourceGroupBudgetName
  properties: {
    displayName: 'Monthly Resource Group Budget - ${resourceGroupBudgetName}'
    category: 'Cost'
    amount: resourceGroupBudgetAmount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate
      endDate: budgetEndDate
    }
    filter: {
      dimensions: {
        name: 'ResourceGroupName'
        operator: 'In'
        values: [
          resourceGroupName
        ]
      }
    }
    notifications: {
      'Actual_GreaterThan_50_Percent': {
        enabled: budgetNotifications.fiftyPercent.enabled
        operator: budgetNotifications.fiftyPercent.operator
        threshold: budgetNotifications.fiftyPercent.threshold
        contactEmails: budgetNotifications.fiftyPercent.contactEmails
        contactRoles: budgetNotifications.fiftyPercent.contactRoles
        contactGroups: [
          actionGroup.outputs.actionGroupId
        ]
        thresholdType: budgetNotifications.fiftyPercent.thresholdType
        locale: budgetNotifications.fiftyPercent.locale
      }
      'Actual_GreaterThan_80_Percent': {
        enabled: budgetNotifications.eightyPercent.enabled
        operator: budgetNotifications.eightyPercent.operator
        threshold: budgetNotifications.eightyPercent.threshold
        contactEmails: budgetNotifications.eightyPercent.contactEmails
        contactRoles: budgetNotifications.eightyPercent.contactRoles
        contactGroups: [
          actionGroup.outputs.actionGroupId
        ]
        thresholdType: budgetNotifications.eightyPercent.thresholdType
        locale: budgetNotifications.eightyPercent.locale
      }
      'Forecasted_GreaterThan_100_Percent': {
        enabled: budgetNotifications.hundredPercent.enabled
        operator: budgetNotifications.hundredPercent.operator
        threshold: budgetNotifications.hundredPercent.threshold
        contactEmails: budgetNotifications.hundredPercent.contactEmails
        contactRoles: budgetNotifications.hundredPercent.contactRoles
        contactGroups: [
          actionGroup.outputs.actionGroupId
        ]
        thresholdType: budgetNotifications.hundredPercent.thresholdType
        locale: budgetNotifications.hundredPercent.locale
      }
    }
  }
}

// =====================================================================================
// OUTPUTS
// =====================================================================================

@description('The name of the created resource group')
output resourceGroupName string = resourceGroup.name

@description('The resource ID of the created resource group')
output resourceGroupId string = resourceGroup.id

@description('The name of the Azure Monitor Action Group')
output actionGroupName string = actionGroup.outputs.actionGroupName

@description('The resource ID of the Azure Monitor Action Group')
output actionGroupId string = actionGroup.outputs.actionGroupId

@description('The name of the subscription-level budget')
output subscriptionBudgetName string = subscriptionBudget.name

@description('The resource ID of the subscription-level budget')
output subscriptionBudgetId string = subscriptionBudget.id

@description('The configured budget amount for subscription monitoring')
output subscriptionBudgetAmount int = subscriptionBudgetAmount

@description('The name of the resource group-level budget')
output resourceGroupBudgetName string = resourceGroupBudget.name

@description('The resource ID of the resource group-level budget')
output resourceGroupBudgetId string = resourceGroupBudget.id

@description('The configured budget amount for resource group monitoring')
output resourceGroupBudgetAmount int = resourceGroupBudgetAmount

@description('Email address configured for budget alerts')
output alertEmailAddress string = alertEmailAddress

@description('Azure Cost Management portal URL for monitoring')
output costManagementUrl string = 'https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview'

@description('Budget monitoring period')
output budgetPeriod object = {
  startDate: budgetStartDate
  endDate: budgetEndDate
  timeGrain: 'Monthly'
}

@description('Configured alert thresholds')
output alertThresholds array = [
  {
    threshold: 50
    type: 'Actual'
    description: 'Early warning at 50% of budget'
  }
  {
    threshold: 80
    type: 'Actual'
    description: 'Critical warning at 80% of budget'
  }
  {
    threshold: 100
    type: 'Forecasted'
    description: 'Forecasted overage warning'
  }
]