@description('Cost-Optimized Content Generation using Model Router and Azure Functions')
@description('This template deploys a complete serverless content generation pipeline with intelligent AI model selection')

// Parameters
@description('Base name for all resources. Must be globally unique for storage and function app.')
@minLength(3)
@maxLength(15)
param baseName string = 'contentgen${uniqueString(resourceGroup().id)}'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Environment designation for resource tagging')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Cost center for billing and management')
param costCenter string = 'marketing'

@description('AI Foundry SKU for cost optimization')
@allowed([
  'S0'
  'S1'
  'S2'
])
param aiFoundrySku string = 'S0'

@description('Model Router deployment capacity (1-10)')
@minValue(1)
@maxValue(10)
param modelRouterCapacity int = 10

@description('Storage account SKU for cost optimization')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Function App runtime stack')
@allowed([
  'node'
  'dotnet'
  'python'
])
param functionRuntime string = 'node'

@description('Function App runtime version')
param functionRuntimeVersion string = '18'

@description('Budget amount for cost monitoring (USD)')
@minValue(10)
@maxValue(1000)
param budgetAmount int = 100

@description('Budget alert threshold percentage')
@minValue(50)
@maxValue(100)
param budgetAlertThreshold int = 80

@description('Email address for budget alerts')
param alertEmail string = 'admin@company.com'

@description('Application Insights workspace retention days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

// Variables
var resourceTags = {
  environment: environment
  workload: 'content-generation'
  'cost-center': costCenter
  project: 'ai-model-router'
}

var storageAccountName = 'st${toLower(baseName)}'
var functionAppName = 'func-${baseName}'
var aiFoundryName = 'aif-${baseName}'
var logAnalyticsName = 'law-${baseName}'
var appInsightsName = 'ai-${baseName}'
var hostingPlanName = 'asp-${baseName}'
var eventGridTopicName = 'egt-${baseName}'
var budgetName = '${baseName}-budget'

// Log Analytics Workspace for centralized logging
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

// Application Insights for monitoring and telemetry
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'rest'
    RetentionInDays: logRetentionDays
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for content processing
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
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
      requireInfrastructureEncryption: false
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

// Blob Service Configuration
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    changeFeed: {
      enabled: false
    }
    restorePolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    isVersioningEnabled: false
  }
}

// Content Requests Container
resource contentRequestsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'content-requests'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Generated Content Container
resource generatedContentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'generated-content'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// Queue Service for function orchestration
resource queueServices 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

// Content Generation Queue
resource contentGenerationQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: queueServices
  name: 'content-generation-queue'
  properties: {
    metadata: {}
  }
}

// Azure AI Foundry Resource (Cognitive Services)
resource aiFoundry 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: aiFoundryName
  location: location
  tags: resourceTags
  sku: {
    name: aiFoundrySku
  }
  kind: 'AIServices'
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
    customSubDomainName: aiFoundryName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// Model Router Deployment
resource modelRouterDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiFoundry
  name: 'model-router-deployment'
  properties: {
    model: {
      format: 'OpenAI'
      name: 'model-router'
      version: '2025-01-25'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    currentCapacity: modelRouterCapacity
    raiPolicyName: 'Microsoft.DefaultV2'
  }
  sku: {
    name: 'Standard'
    capacity: modelRouterCapacity
  }
}

// Hosting Plan for Azure Functions (Consumption)
resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: hostingPlanName
  location: location
  tags: resourceTags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    computeMode: 'Dynamic'
    reserved: true
  }
}

// Function App for serverless content processing
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: resourceTags
  kind: 'functionapp,linux'
  properties: {
    enabled: true
    hostNameSslStates: [
      {
        name: '${functionAppName}.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Standard'
      }
      {
        name: '${functionAppName}.scm.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Repository'
      }
    ]
    serverFarmId: hostingPlan.id
    reserved: true
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: '${upper(functionRuntime)}|${functionRuntimeVersion}'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
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
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~${functionRuntimeVersion}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionRuntime
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
          name: 'AI_FOUNDRY_ENDPOINT'
          value: aiFoundry.properties.endpoint
        }
        {
          name: 'AI_FOUNDRY_KEY'
          value: aiFoundry.listKeys().key1
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'MODEL_DEPLOYMENT_NAME'
          value: modelRouterDeployment.name
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'WEBSITE_ENABLE_SYNC_UPDATE_SITE'
          value: 'true'
        }
      ]
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    customDomainVerificationId: '331F13F8B8C016F12D4D7F0EE85F4F949CF80F8F7075B7C9F7F3D6D8A9B4E5F6'
    containerSize: 1536
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Function App System-Assigned Managed Identity
resource functionAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${functionAppName}-identity'
  location: location
  tags: resourceTags
}

// Event Grid System Topic for Storage Events
resource eventGridSystemTopic 'Microsoft.EventGrid/systemTopics@2024-06-01-preview' = {
  name: '${storageAccountName}-topic'
  location: location
  tags: resourceTags
  properties: {
    source: storageAccount.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

// Event Grid Subscription for Blob Created Events
resource eventGridSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2024-06-01-preview' = {
  parent: eventGridSystemTopic
  name: 'content-processing-subscription'
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/ContentAnalyzer'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/content-requests/'
      enableAdvancedFilteringOnArrays: true
    }
    labels: [
      'content-generation'
    ]
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
    deadLetterDestination: {
      endpointType: 'StorageBlob'
      properties: {
        resourceId: storageAccount.id
        blobContainerName: 'deadletter'
      }
    }
  }
}

// Action Group for Budget Alerts
resource budgetActionGroup 'Microsoft.Insights/actionGroups@2023-09-01-preview' = {
  name: '${baseName}-budget-alerts'
  location: 'global'
  tags: resourceTags
  properties: {
    groupShortName: 'BudgetAlert'
    enabled: true
    emailReceivers: [
      {
        name: 'BudgetAlert'
        emailAddress: alertEmail
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

// Budget for Cost Management
resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: budgetName
  properties: {
    timePeriod: {
      startDate: '2025-01-01'
      endDate: '2026-12-31'
    }
    timeGrain: 'Monthly'
    amount: budgetAmount
    category: 'Cost'
    notifications: {
      'Actual_GreaterThan_${budgetAlertThreshold}_Percent': {
        enabled: true
        operator: 'GreaterThan'
        threshold: budgetAlertThreshold
        contactEmails: [
          alertEmail
        ]
        contactRoles: [
          'Owner'
          'Contributor'
        ]
        thresholdType: 'Actual'
      }
      'Forecasted_GreaterThan_${budgetAlertThreshold + 10}_Percent': {
        enabled: true
        operator: 'GreaterThan'
        threshold: budgetAlertThreshold + 10
        contactEmails: [
          alertEmail
        ]
        contactRoles: [
          'Owner'
          'Contributor'
        ]
        thresholdType: 'Forecasted'
      }
    }
  }
}

// Metric Alert for AI Foundry Cost Monitoring
resource aiFoundryCostAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'ai-foundry-cost-alert'
  location: 'global'
  tags: resourceTags
  properties: {
    description: 'Alert when AI Foundry costs exceed threshold'
    severity: 2
    enabled: true
    scopes: [
      aiFoundry.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 50
          name: 'Metric1'
          metricNamespace: 'Microsoft.CognitiveServices/accounts'
          metricName: 'TotalCalls'
          operator: 'GreaterThan'
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.CognitiveServices/accounts'
    targetResourceRegion: location
    actions: [
      {
        actionGroupId: budgetActionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// RBAC Assignments for Function App
resource storageContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, storageAccount.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource cognitiveServicesUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, aiFoundry.id, 'Cognitive Services User')
  scope: aiFoundry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908') // Cognitive Services User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The connection string for the storage account')
@secure()
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The URL of the Function App')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the AI Foundry resource')
output aiFoundryName string = aiFoundry.name

@description('The endpoint URL for the AI Foundry resource')
output aiFoundryEndpoint string = aiFoundry.properties.endpoint

@description('The primary key for the AI Foundry resource')
@secure()
output aiFoundryKey string = aiFoundry.listKeys().key1

@description('The name of the Model Router deployment')
output modelRouterDeploymentName string = modelRouterDeployment.name

@description('The name of the Application Insights resource')
output applicationInsightsName string = applicationInsights.name

@description('The instrumentation key for Application Insights')
@secure()
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The connection string for Application Insights')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalytics.name

@description('The workspace ID for Log Analytics')
output logAnalyticsWorkspaceId string = logAnalytics.id

@description('The name of the Event Grid system topic')
output eventGridSystemTopicName string = eventGridSystemTopic.name

@description('The name of the budget for cost monitoring')
output budgetName string = budget.name

@description('Deployment summary with key information')
output deploymentSummary object = {
  resourceGroupName: resourceGroup().name
  environment: environment
  location: location
  storageAccount: storageAccount.name
  functionApp: functionApp.name
  aiFoundry: aiFoundry.name
  modelRouterDeployment: modelRouterDeployment.name
  budgetAmount: budgetAmount
  estimatedMonthlyCost: '${budgetAmount * 0.3}-${budgetAmount * 0.7} USD'
  costOptimizationFeatures: [
    'Consumption Plan Functions (pay-per-execution)'
    'Standard LRS Storage (cost-effective redundancy)'
    'AI Model Router (intelligent model selection)'
    'Budget alerts and monitoring'
    'Log Analytics data retention limits'
  ]
}