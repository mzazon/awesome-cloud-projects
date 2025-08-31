// Budget Alert Notifications with Cost Management and Logic Apps
// This template deploys the complete budget monitoring solution with automated email notifications

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Base name for all resources (will be combined with unique suffix)')
param baseName string = 'budget-alerts'

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Budget amount in USD')
@minValue(1)
@maxValue(1000000)
param budgetAmount int = 100

@description('Budget start date in YYYY-MM-DD format')
param budgetStartDate string = '2025-01-01'

@description('Budget end date in YYYY-MM-DD format')
param budgetEndDate string = '2025-12-31'

@description('Email addresses to receive budget alert notifications (comma-separated)')
param notificationEmails string = ''

@description('First alert threshold percentage (actual spending)')
@minValue(1)
@maxValue(100)
param firstThresholdPercentage int = 80

@description('Second alert threshold percentage (forecasted spending)')
@minValue(1)
@maxValue(200)
param secondThresholdPercentage int = 100

@description('Tags to apply to all resources')
param resourceTags object = {
  purpose: 'budget-monitoring'
  environment: 'demo'
  solution: 'cost-management-alerts'
}

// Variables for resource naming
var storageAccountName = 'st${uniqueSuffix}'
var logicAppName = '${baseName}-${uniqueSuffix}'
var actionGroupName = 'ag-${baseName}-${uniqueSuffix}'
var budgetName = 'budget-${baseName}-${uniqueSuffix}'

// Storage Account for Logic App runtime
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: union(resourceTags, {
    component: 'storage'
    purpose: 'logic-app'
  })
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
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
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// App Service Plan for Logic App
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${baseName}-plan-${uniqueSuffix}'
  location: location
  tags: union(resourceTags, {
    component: 'compute'
    purpose: 'logic-app-hosting'
  })
  sku: {
    name: 'WS1'
    tier: 'WorkflowStandard'
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: 20
    targetWorkerCount: 1
    targetWorkerSizeId: 0
  }
}

// Logic App for budget alert processing
resource logicApp 'Microsoft.Web/sites@2023-01-01' = {
  name: logicAppName
  location: location
  tags: union(resourceTags, {
    component: 'automation'
    purpose: 'budget-alerts'
  })
  kind: 'functionapp,workflowapp'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      functionsRuntimeScaleMonitoringEnabled: true
      appSettings: [
        {
          name: 'APP_KIND'
          value: 'workflowApp'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: '${logicAppName}-content'
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__id'
          value: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__version'
          value: '[1.*, 2.0.0)'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
      ]
    }
  }
}

// Action Group for budget notifications
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: union(resourceTags, {
    component: 'monitoring'
    purpose: 'budget-alerts'
  })
  properties: {
    groupShortName: 'BudgetAlert'
    enabled: true
    logicAppReceivers: [
      {
        name: 'BudgetLogicApp'
        resourceId: logicApp.id
        callbackUrl: 'https://${logicApp.properties.defaultHostName}/api/budgetalert/triggers/manual/invoke'
        useCommonAlertSchema: true
      }
    ]
    emailReceivers: empty(notificationEmails) ? [] : [
      {
        name: 'EmailNotification'
        emailAddress: split(notificationEmails, ',')[0]
        useCommonAlertSchema: true
      }
    ]
  }
}

// Budget with alert thresholds
resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: budgetName
  scope: subscription()
  properties: {
    timePeriod: {
      startDate: budgetStartDate
      endDate: budgetEndDate
    }
    timeGrain: 'Monthly'
    amount: budgetAmount
    category: 'Cost'
    notifications: {
      'actual-${firstThresholdPercentage}': {
        enabled: true
        operator: 'GreaterThan'
        threshold: firstThresholdPercentage
        contactEmails: empty(notificationEmails) ? [] : split(notificationEmails, ',')
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Actual'
      }
      'forecasted-${secondThresholdPercentage}': {
        enabled: true
        operator: 'GreaterThan'
        threshold: secondThresholdPercentage
        contactEmails: empty(notificationEmails) ? [] : split(notificationEmails, ',')
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Forecasted'
      }
    }
  }
}

// Outputs for verification and integration
@description('The resource group name where resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('The name of the created Logic App')
output logicAppName string = logicApp.name

@description('The resource ID of the Logic App')
output logicAppResourceId string = logicApp.id

@description('The default hostname of the Logic App')
output logicAppHostname string = logicApp.properties.defaultHostName

@description('The name of the created Action Group')
output actionGroupName string = actionGroup.name

@description('The resource ID of the Action Group')
output actionGroupResourceId string = actionGroup.id

@description('The name of the created budget')
output budgetName string = budget.name

@description('The storage account name used by the Logic App')
output storageAccountName string = storageAccount.name

@description('The App Service Plan name hosting the Logic App')
output appServicePlanName string = appServicePlan.name

@description('Budget configuration summary')
output budgetSummary object = {
  name: budget.name
  amount: budgetAmount
  currency: 'USD'
  timeGrain: 'Monthly'
  startDate: budgetStartDate
  endDate: budgetEndDate
  thresholds: {
    actual: firstThresholdPercentage
    forecasted: secondThresholdPercentage
  }
}

@description('Logic App workflow endpoint URL for manual triggers')
output workflowEndpointUrl string = 'https://${logicApp.properties.defaultHostName}/api/budgetalert/triggers/manual/invoke'

@description('Azure Portal URLs for easy access to resources')
output portalUrls object = {
  logicApp: 'https://portal.azure.com/#@/resource${logicApp.id}/overview'
  actionGroup: 'https://portal.azure.com/#@/resource${actionGroup.id}/overview'
  budget: 'https://portal.azure.com/#@/blade/Microsoft_Azure_CostManagement/BudgetsBlade'
  storageAccount: 'https://portal.azure.com/#@/resource${storageAccount.id}/overview'
}

@description('Next steps for completing the solution')
output nextSteps array = [
  'Navigate to the Logic App in Azure Portal to create the workflow'
  'Configure the HTTP trigger to accept POST requests from Action Groups'
  'Add Office 365 Outlook connector for email notifications'
  'Parse JSON action to extract budget alert data'
  'Test the workflow with sample budget alert data'
  'Enable the workflow and monitor for budget alerts'
]