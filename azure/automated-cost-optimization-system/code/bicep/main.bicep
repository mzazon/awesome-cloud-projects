@description('Main Bicep template for Azure Cost Optimization with Advisor and Cost Management')

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
@minLength(3)
@maxLength(6)
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Log Analytics workspace SKU')
@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
])
param logAnalyticsWorkspaceSku string = 'PerGB2018'

@description('Budget amount in USD')
@minValue(100)
@maxValue(10000)
param budgetAmount int = 1000

@description('Budget alert thresholds as percentages')
param budgetThresholds array = [
  80
  100
]

@description('Email addresses for budget alerts')
param alertEmailAddresses array = []

@description('Microsoft Teams webhook URL for notifications')
param teamsWebhookUrl string = ''

@description('Logic Apps hosting plan SKU')
@allowed([
  'Standard'
  'Premium'
])
param logicAppsSku string = 'Standard'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'cost-optimization'
  environment: 'production'
  solution: 'azure-advisor-cost-management'
}

// Variables
var storageAccountName = 'stcostopt${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-cost-optimization-${uniqueSuffix}'
var logicAppName = 'la-cost-optimization-${uniqueSuffix}'
var budgetName = 'budget-optimization-${uniqueSuffix}'
var actionGroupName = 'cost-optimization-alerts-${uniqueSuffix}'
var servicePrincipalName = 'sp-cost-optimization-${uniqueSuffix}'
var costExportName = 'daily-cost-export-${uniqueSuffix}'
var costAnomalyAlertName = 'cost-anomaly-alert-${uniqueSuffix}'

// Storage Account for cost data exports
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Allow'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Blob container for cost exports
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
  }
}

resource costExportsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'cost-exports'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'cost-data-export'
    }
  }
}

// Log Analytics Workspace for cost monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsWorkspaceSku
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
    }
  }
}

// Application Insights for Logic Apps monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${logicAppName}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Logic Apps Standard resource for cost optimization automation
resource logicApp 'Microsoft.Web/sites@2023-01-01' = {
  name: logicAppName
  location: location
  tags: tags
  kind: 'functionapp,workflowapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: logicAppHostingPlan.id
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
          value: toLower(logicAppName)
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
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'AZURE_SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
        {
          name: 'AZURE_TENANT_ID'
          value: subscription().tenantId
        }
        {
          name: 'TEAMS_WEBHOOK_URL'
          value: teamsWebhookUrl
        }
        {
          name: 'COST_EXPORT_CONTAINER_URL'
          value: '${storageAccount.properties.primaryEndpoints.blob}cost-exports'
        }
      ]
      use32BitWorkerProcess: false
      netFrameworkVersion: 'v6.0'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Logic Apps hosting plan
resource logicAppHostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'asp-${logicAppName}'
  location: location
  tags: tags
  sku: {
    name: logicAppsSku == 'Standard' ? 'WS1' : 'WS2'
    tier: 'WorkflowStandard'
    size: logicAppsSku == 'Standard' ? 'WS1' : 'WS2'
    family: 'WS'
    capacity: 1
  }
  properties: {
    targetWorkerCount: 1
    targetWorkerSizeId: 0
    reserved: false
  }
}

// Action Group for budget alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'CostOpt'
    enabled: true
    emailReceivers: [for email in alertEmailAddresses: {
      name: 'EmailAlert-${indexOf(alertEmailAddresses, email)}'
      emailAddress: email
      useCommonAlertSchema: true
    }]
    logicAppReceivers: [
      {
        name: 'LogicAppAlert'
        resourceId: logicApp.id
        callbackUrl: 'https://${logicApp.properties.defaultHostName}/runtime/webhooks/workflow/api/management/workflows/cost-optimization-workflow/triggers/manual/listCallbackUrl?api-version=2020-05-01-preview&code=${listCallbackUrl(resourceId('Microsoft.Web/sites/hostruntime/webhooks/workflow/api/management/workflows/triggers', logicApp.name, 'cost-optimization-workflow', 'manual'), '2020-05-01-preview').value}'
        useCommonAlertSchema: true
      }
    ]
    webhookReceivers: !empty(teamsWebhookUrl) ? [
      {
        name: 'TeamsWebhook'
        serviceUri: teamsWebhookUrl
        useCommonAlertSchema: true
      }
    ] : []
  }
}

// Budget configuration with alerts
resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: budgetName
  properties: {
    timePeriod: {
      startDate: '${utcNow('yyyy-MM')}-01T00:00:00Z'
      endDate: '${utcNow('yyyy-MM')}-${dateTimeAdd(utcNow('yyyy-MM-01'), 'P1M', 'dd')}T00:00:00Z'
    }
    timeGrain: 'Monthly'
    amount: budgetAmount
    category: 'Cost'
    notifications: {
      'Alert-${budgetThresholds[0]}': {
        enabled: true
        operator: 'GreaterThan'
        threshold: budgetThresholds[0]
        contactEmails: alertEmailAddresses
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Actual'
        locale: 'en-us'
      }
      'Alert-${budgetThresholds[1]}': {
        enabled: true
        operator: 'GreaterThan'
        threshold: budgetThresholds[1]
        contactEmails: alertEmailAddresses
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Actual'
        locale: 'en-us'
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

// Cost anomaly detection alert
resource costAnomalyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: costAnomalyAlertName
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when cost exceeds 80% of monthly budget'
    severity: 2
    enabled: true
    scopes: [
      subscription().id
    ]
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    targetResourceType: 'Microsoft.Consumption/budgets'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'BudgetExceeded'
          metricName: 'ActualCost'
          metricNamespace: 'Microsoft.Consumption/budgets'
          operator: 'GreaterThan'
          threshold: budgetAmount * 0.8
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
  }
}

// Role assignments for Logic Apps managed identity
resource costManagementReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, logicApp.id, 'Cost Management Reader')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '72fafb9e-0641-4937-9268-a91bfd8191a3') // Cost Management Reader
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource advisorReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, logicApp.id, 'Advisor Reader')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ac7f3c68-9850-4f1b-b126-9b96c0ac4e9c') // Advisor Reader
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, logicApp.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Cost export configuration (requires deployment script as ARM doesn't support this directly)
resource costExportDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'deploy-cost-export-${uniqueSuffix}'
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.45.0'
    timeout: 'PT30M'
    retentionInterval: 'P1D'
    environmentVariables: [
      {
        name: 'EXPORT_NAME'
        value: costExportName
      }
      {
        name: 'STORAGE_ACCOUNT_ID'
        value: storageAccount.id
      }
      {
        name: 'SUBSCRIPTION_ID'
        value: subscription().subscriptionId
      }
    ]
    scriptContent: '''
      # Create cost export using Azure CLI
      az consumption export create \
        --export-name "$EXPORT_NAME" \
        --type ActualCost \
        --dataset-granularity Daily \
        --dataset-start-date "$(date -u -d '30 days ago' +%Y-%m-%d)" \
        --dataset-end-date "$(date -u +%Y-%m-%d)" \
        --storage-account-id "$STORAGE_ACCOUNT_ID" \
        --storage-container cost-exports \
        --storage-root-folder-path exports/daily \
        --recurrence-type Daily \
        --recurrence-start-date "$(date -u +%Y-%m-%d)" \
        --scope "/subscriptions/$SUBSCRIPTION_ID"
      
      echo "Cost export created successfully"
    '''
  }
}

// User-assigned managed identity for deployment script
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-cost-export-${uniqueSuffix}'
  location: location
  tags: tags
}

// Role assignment for deployment script identity
resource deploymentScriptCostManagementRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, userAssignedIdentity.id, 'Cost Management Contributor')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f20be4c6-5b5d-4f0e-9b56-a1f1e6c5f5ae') // Cost Management Contributor
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('Storage account name for cost exports')
output storageAccountName string = storageAccount.name

@description('Storage account connection string')
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics workspace customer ID')
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('Logic Apps name')
output logicAppName string = logicApp.name

@description('Logic Apps resource ID')
output logicAppResourceId string = logicApp.id

@description('Logic Apps default hostname')
output logicAppDefaultHostname string = logicApp.properties.defaultHostName

@description('Logic Apps managed identity principal ID')
output logicAppPrincipalId string = logicApp.identity.principalId

@description('Budget name')
output budgetName string = budgetName

@description('Budget amount')
output budgetAmount int = budgetAmount

@description('Action Group resource ID')
output actionGroupResourceId string = actionGroup.id

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Cost exports container URL')
output costExportsContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}cost-exports'

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Deployment timestamp')
output deploymentTimestamp string = utcNow()