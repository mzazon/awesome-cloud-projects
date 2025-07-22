// main.bicep - Azure Resource Rightsizing Automation Solution
// This template deploys automated resource rightsizing infrastructure
// including monitoring, functions, logic apps, and cost management

@description('The location for all resources')
param location string = resourceGroup().location

@description('The environment name (e.g., dev, staging, prod)')
param environment string = 'dev'

@description('Unique suffix for resource names')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('The email address for cost alerts and notifications')
param alertEmail string

@description('The budget amount for cost monitoring in USD')
param budgetAmount int = 100

@description('The CPU utilization threshold for rightsizing (percentage)')
param cpuThreshold int = 80

@description('The low CPU utilization threshold for downsizing (percentage)')
param lowCpuThreshold int = 20

@description('Enable or disable the automated rightsizing function')
param enableAutomation bool = true

@description('The cron expression for the rightsizing function timer')
param functionSchedule string = '0 0 */1 * * *' // Every hour

@description('Tags to apply to all resources')
param tags object = {
  project: 'rightsizing-automation'
  environment: environment
  purpose: 'cost-optimization'
}

// Variables for resource naming
var storageAccountName = 'st${resourceSuffix}'
var functionAppName = 'func-rightsizing-${resourceSuffix}'
var logAnalyticsName = 'log-rightsizing-${resourceSuffix}'
var appInsightsName = 'ai-rightsizing-${resourceSuffix}'
var logicAppName = 'logic-rightsizing-${resourceSuffix}'
var hostingPlanName = 'plan-rightsizing-${resourceSuffix}'
var actionGroupName = 'ag-rightsizing-${resourceSuffix}'
var budgetName = 'budget-rightsizing-${resourceSuffix}'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
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
      dailyQuotaGb: 1
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Allow'
    }
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
  }
}

// Function App Hosting Plan (Consumption)
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: false
  }
}

// Function App for Rightsizing Logic
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
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
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
        {
          name: 'RESOURCE_GROUP'
          value: resourceGroup().name
        }
        {
          name: 'LOG_ANALYTICS_WORKSPACE_ID'
          value: logAnalyticsWorkspace.properties.customerId
        }
        {
          name: 'CPU_THRESHOLD'
          value: string(cpuThreshold)
        }
        {
          name: 'LOW_CPU_THRESHOLD'
          value: string(lowCpuThreshold)
        }
        {
          name: 'ENABLE_AUTOMATION'
          value: string(enableAutomation)
        }
        {
          name: 'FUNCTION_SCHEDULE'
          value: functionSchedule
        }
        {
          name: 'LOGIC_APP_CALLBACK_URL'
          value: logicApp.listCallbackUrl().value
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

// Logic App for Workflow Automation
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        functionAppName: {
          type: 'string'
          defaultValue: functionAppName
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
                recommendations: {
                  type: 'array'
                  items: {
                    type: 'object'
                    properties: {
                      resource: {
                        type: 'string'
                      }
                      action: {
                        type: 'string'
                      }
                      reason: {
                        type: 'string'
                      }
                      priority: {
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
      actions: {
        'Process-Recommendations': {
          type: 'Foreach'
          foreach: '@triggerBody()?[\'recommendations\']'
          actions: {
            'Check-Priority': {
              type: 'If'
              expression: {
                equals: [
                  '@items(\'Process-Recommendations\')?[\'priority\']'
                  'high'
                ]
              }
              actions: {
                'Send-Alert': {
                  type: 'Http'
                  inputs: {
                    method: 'POST'
                    uri: 'https://outlook.office.com/webhook/dummy-webhook-url'
                    body: {
                      text: 'High priority rightsizing recommendation: @{items(\'Process-Recommendations\')?[\'resource\']} - @{items(\'Process-Recommendations\')?[\'reason\']}'
                    }
                  }
                }
              }
            }
            'Log-Recommendation': {
              type: 'Http'
              inputs: {
                method: 'POST'
                uri: 'https://@{parameters(\'functionAppName\')}.azurewebsites.net/api/LogRecommendation'
                body: '@items(\'Process-Recommendations\')'
              }
            }
          }
        }
        'Response': {
          type: 'Response'
          inputs: {
            statusCode: 200
            body: {
              message: 'Recommendations processed successfully'
              processedCount: '@length(triggerBody()?[\'recommendations\'])'
            }
          }
        }
      }
    }
  }
}

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'rightsizing'
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
        name: 'logicapp'
        serviceUri: logicApp.listCallbackUrl().value
        useCommonAlertSchema: true
      }
    ]
  }
}

// Budget for Cost Monitoring
resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: budgetName
  properties: {
    timePeriod: {
      startDate: '2025-01-01'
      endDate: '2025-12-31'
    }
    timeGrain: 'Monthly'
    amount: budgetAmount
    category: 'Cost'
    notifications: {
      'budget-exceeded': {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: [
          alertEmail
        ]
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Actual'
      }
      'budget-forecasted': {
        enabled: true
        operator: 'GreaterThan'
        threshold: 90
        contactEmails: [
          alertEmail
        ]
        contactGroups: [
          actionGroup.id
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

// Metric Alert for Function App Errors
resource functionErrorAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'function-error-alert'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when rightsizing function fails to execute'
    severity: 2
    enabled: true
    scopes: [
      functionApp.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'FunctionExecutionCount'
          metricName: 'FunctionExecutionCount'
          dimensions: []
          operator: 'LessThan'
          threshold: 1
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

// Metric Alert for High Cost
resource costAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'high-cost-alert'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when resource group costs exceed threshold'
    severity: 1
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Cost'
          metricName: 'Cost'
          dimensions: []
          operator: 'GreaterThan'
          threshold: budgetAmount * 0.8
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

// RBAC Role Assignment for Function App (Contributor access)
resource functionAppRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, 'contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC Role Assignment for Logic App (Contributor access)
resource logicAppRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logicApp.id, 'contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC Role Assignment for Function App (Cost Management Reader)
resource functionAppCostRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, 'cost-reader')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '72fafb9e-0641-4937-9268-a91bfd8191a3') // Cost Management Reader
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC Role Assignment for Function App (Monitoring Reader)
resource functionAppMonitoringRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, 'monitoring-reader')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05') // Monitoring Reader
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Output values for verification and integration
output resourceGroupName string = resourceGroup().name
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output logicAppName string = logicApp.name
output logicAppCallbackUrl string = logicApp.listCallbackUrl().value
output storageAccountName string = storageAccount.name
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId
output appInsightsName string = appInsights.name
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output budgetName string = budget.name
output actionGroupName string = actionGroup.name
output functionAppPrincipalId string = functionApp.identity.principalId
output logicAppPrincipalId string = logicApp.identity.principalId