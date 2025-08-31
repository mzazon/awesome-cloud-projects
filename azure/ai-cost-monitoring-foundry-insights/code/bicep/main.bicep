@description('Main Bicep template for AI Cost Monitoring with Azure AI Foundry and Application Insights')

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'ai-monitoring'
  environment: environment
  project: 'ai-cost-monitoring'
}

@description('Application Insights retention period in days')
@allowed([30, 60, 90, 120, 180, 270, 365, 550, 730])
param appInsightsRetentionDays int = 90

@description('Log Analytics workspace retention period in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Budget amount in USD')
@minValue(1)
param budgetAmount int = 100

@description('Email addresses for budget alerts (comma-separated)')
param budgetAlertEmails string = 'admin@company.com'

@description('Enable custom metrics with dimensions in Application Insights')
param enableCustomMetrics bool = true

@description('AI Hub display name')
param aiHubDisplayName string = 'AI Cost Monitoring Hub'

@description('AI Project display name')
param aiProjectDisplayName string = 'AI Cost Monitoring Project'

// Variables
var resourceNames = {
  aiHub: 'aihub-${uniqueSuffix}'
  aiProject: 'aiproject-${uniqueSuffix}'
  appInsights: 'appins-ai-${uniqueSuffix}'
  logAnalytics: 'logs-ai-${uniqueSuffix}'
  storageAccount: 'stor${uniqueSuffix}'
  keyVault: 'kv-ai-${uniqueSuffix}'
  actionGroup: 'ai-cost-alerts-${uniqueSuffix}'
  budget: 'ai-foundry-budget-${uniqueSuffix}'
  workbook: 'ai-monitoring-dashboard-${uniqueSuffix}'
}

var emailReceivers = [for email in split(budgetAlertEmails, ','): {
  name: 'admin-${indexOf(split(budgetAlertEmails, ','), email)}'
  emailAddress: trim(email)
  useCommonAlertSchema: true
}]

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalytics
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourceRbac: true
      disableLocalAuth: false
    }
    workspaceCapping: {
      dailyQuotaGb: 10
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.appInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    RetentionInDays: appInsightsRetentionDays
    CustomMetricsOptedInType: enableCustomMetrics ? 'WithDimensions' : 'WithoutDimensions'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Key Vault for secrets management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Store Application Insights instrumentation key in Key Vault
resource appInsightsKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'applicationinsights-instrumentationkey'
  parent: keyVault
  properties: {
    value: applicationInsights.properties.InstrumentationKey
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Store Application Insights connection string in Key Vault
resource appInsightsConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'applicationinsights-connectionstring'
  parent: keyVault
  properties: {
    value: applicationInsights.properties.ConnectionString
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Storage Account for AI Foundry
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
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
  }
}

// AI Foundry Hub (Azure Machine Learning Workspace with kind 'hub')
resource aiFoundryHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: resourceNames.aiHub
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
  }
  kind: 'hub'
  properties: {
    friendlyName: aiHubDisplayName
    description: 'AI Foundry Hub for cost monitoring and analytics'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: applicationInsights.id
    publicNetworkAccess: 'Enabled'
    managedNetwork: {
      isolationMode: 'Disabled'
    }
    v1LegacyMode: false
  }
}

// AI Foundry Project (Azure Machine Learning Workspace with kind 'project')
resource aiFoundryProject 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: resourceNames.aiProject
  location: location
  tags: union(tags, {
    'parent-hub': aiFoundryHub.name
  })
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Basic'
  }
  kind: 'project'
  properties: {
    friendlyName: aiProjectDisplayName
    description: 'AI Foundry Project for cost monitoring implementation'
    hubResourceId: aiFoundryHub.id
    publicNetworkAccess: 'Enabled'
    managedNetwork: {
      isolationMode: 'Disabled'
    }
    v1LegacyMode: false
  }
}

// Action Group for cost alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: resourceNames.actionGroup
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'AIAlerts'
    enabled: true
    emailReceivers: emailReceivers
    webhookReceivers: [
      {
        name: 'costWebhook'
        serviceUri: 'https://api.company.com/ai-cost-alert'
        useCommonAlertSchema: true
      }
    ]
  }
}

// Budget for AI resources
resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: resourceNames.budget
  properties: {
    displayName: 'AI Foundry Cost Budget'
    amount: budgetAmount
    category: 'Cost'
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: '${utcNow('yyyy-MM')}-01'
      endDate: '${dateTimeAdd(utcNow('yyyy-MM-01'), 'P1Y', 'yyyy-MM')}-01'
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
    notifications: {
      '80Percent': {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: split(budgetAlertEmails, ',')
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Actual'
      }
      '100Percent': {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: split(budgetAlertEmails, ',')
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Actual'
      }
      'Forecasted90Percent': {
        enabled: true
        operator: 'GreaterThan'
        threshold: 90
        contactEmails: split(budgetAlertEmails, ',')
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Forecasted'
      }
    }
  }
}

// Azure Monitor Workbook for AI cost analytics
resource aiMonitoringWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceNames.workbook)
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'AI Cost Monitoring Dashboard'
    description: 'Comprehensive view of AI token usage, costs, and performance metrics'
    category: 'workbook'
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        {
          type: 1
          content: {
            json: '# AI Cost Monitoring Dashboard\n\nComprehensive view of AI token usage, costs, and performance metrics.'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'customEvents\n| where name == "tokenUsage"\n| summarize TotalCost = sum(todouble(customMeasurements.estimatedCost)), TotalTokens = sum(todouble(customMeasurements.totalTokens)) by bin(timestamp, 1h)\n| render timechart'
            size: 0
            timeContext: {
              durationMs: 86400000
            }
            queryType: 0
            resourceType: 'microsoft.insights/components'
          }
        }
      ]
    })
    sourceId: applicationInsights.id
  }
}

// Alert rule for high token usage
resource tokenUsageAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'high-ai-token-usage'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when AI token usage exceeds threshold'
    enabled: true
    severity: 2
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'tokenUsageThreshold'
          metricName: 'customMetrics/tokenUsage'
          metricNamespace: 'Microsoft.Insights/components'
          operator: 'GreaterThan'
          threshold: 1000
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
    scopes: [
      applicationInsights.id
    ]
  }
}

// RBAC assignments for AI Foundry Hub identity
resource hubStorageContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, aiFoundryHub.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: aiFoundryHub.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource hubKeyVaultSecretsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, aiFoundryHub.id, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: aiFoundryHub.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC assignments for AI Foundry Project identity
resource projectStorageContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, aiFoundryProject.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: aiFoundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource projectKeyVaultSecretsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, aiFoundryProject.id, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: aiFoundryProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output aiFoundryHubId string = aiFoundryHub.id
output aiFoundryHubName string = aiFoundryHub.name
output aiFoundryProjectId string = aiFoundryProject.id
output aiFoundryProjectName string = aiFoundryProject.name
output applicationInsightsId string = applicationInsights.id
output applicationInsightsName string = applicationInsights.name
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output actionGroupId string = actionGroup.id
output actionGroupName string = actionGroup.name
output budgetId string = budget.id
output budgetName string = budget.name
output workbookId string = aiMonitoringWorkbook.id
output workbookName string = aiMonitoringWorkbook.name
output resourceGroupName string = resourceGroup().name
output resourceGroupLocation string = resourceGroup().location