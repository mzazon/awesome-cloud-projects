// =============================================================================
// Azure Bicep Template: Intelligent Supply Chain Carbon Tracking
// Recipe: Supply Chain Carbon Tracking with AI Agents
// =============================================================================

targetScope = 'resourceGroup'

// =============================================================================
// PARAMETERS
// =============================================================================

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = take(uniqueString(resourceGroup().id), 6)

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Project name for resource naming and tagging')
param projectName string = 'carbon-tracking'

@description('The name of the AI Foundry project')
param aiFoundryProjectName string = 'aif-carbon-${uniqueSuffix}'

@description('The name of the Sustainability Manager environment')
param sustainabilityManagerName string = 'asm-carbon-${uniqueSuffix}'

@description('Service Bus namespace name')
param serviceBusNamespaceName string = 'sb-carbon-${uniqueSuffix}'

@description('Function App name')
param functionAppName string = 'func-carbon-${uniqueSuffix}'

@description('Storage account name for Function App')
param storageAccountName string = 'stcarbon${uniqueSuffix}'

@description('SKU for the Service Bus namespace')
@allowed(['Basic', 'Standard', 'Premium'])
param serviceBusSku string = 'Standard'

@description('Function App hosting plan')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppSku string = 'Y1'

@description('Python version for Function App')
@allowed(['3.8', '3.9', '3.10', '3.11'])
param pythonVersion string = '3.11'

@description('Tags to apply to all resources')
param tags object = {
  environment: environment
  project: projectName
  purpose: 'carbon-tracking'
  'cost-center': 'sustainability'
  'data-classification': 'internal'
}

// =============================================================================
// VARIABLES
// =============================================================================

var serviceBusQueues = [
  {
    name: 'carbon-data-queue'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
  }
  {
    name: 'analysis-results-queue'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
  }
  {
    name: 'optimization-recommendations-queue'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    defaultMessageTimeToLive: 'P14D'
    deadLetteringOnMessageExpiration: true
    maxDeliveryCount: 10
  }
]

var functionAppSettings = [
  {
    name: 'FUNCTIONS_EXTENSION_VERSION'
    value: '~4'
  }
  {
    name: 'FUNCTIONS_WORKER_RUNTIME'
    value: 'python'
  }
  {
    name: 'PYTHON_VERSION'
    value: pythonVersion
  }
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
    name: 'ServiceBusConnection'
    value: serviceBusNamespace.listKeys().primaryConnectionString
  }
  {
    name: 'AI_FOUNDRY_PROJECT_NAME'
    value: aiFoundryProjectName
  }
  {
    name: 'SUSTAINABILITY_MANAGER_NAME'
    value: sustainabilityManagerName
  }
  {
    name: 'CARBON_THRESHOLD_TONNES'
    value: '400'
  }
  {
    name: 'ALERT_WEBHOOK_URL'
    value: ''
  }
  {
    name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
    value: applicationInsights.properties.InstrumentationKey
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: applicationInsights.properties.ConnectionString
  }
]

// =============================================================================
// RESOURCES
// =============================================================================

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${projectName}-${uniqueSuffix}'
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
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${projectName}-${uniqueSuffix}'
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

// Service Bus Namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  tags: tags
  sku: {
    name: serviceBusSku
    tier: serviceBusSku
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
  }
}

// Service Bus Queues
resource serviceBusQueuesResource 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = [for queue in serviceBusQueues: {
  name: queue.name
  parent: serviceBusNamespace
  properties: {
    maxSizeInMegabytes: queue.maxSizeInMegabytes
    requiresDuplicateDetection: queue.requiresDuplicateDetection
    defaultMessageTimeToLive: queue.defaultMessageTimeToLive
    deadLetteringOnMessageExpiration: queue.deadLetteringOnMessageExpiration
    maxDeliveryCount: queue.maxDeliveryCount
    status: 'Active'
    enableBatchedOperations: true
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    enablePartitioning: false
    enableExpress: false
  }
}]

// Service Bus Authorization Rule
resource serviceBusAuthRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  name: 'RootManageSharedAccessKey'
  parent: serviceBusNamespace
  properties: {
    rights: [
      'Listen'
      'Manage'
      'Send'
    ]
  }
}

// AI Foundry Workspace (Machine Learning workspace)
resource aiFoundryWorkspace 'Microsoft.MachineLearningServices/workspaces@2023-10-01' = {
  name: aiFoundryProjectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'AI Foundry Project for Carbon Tracking'
    description: 'AI Foundry project for intelligent supply chain carbon tracking agents'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: applicationInsights.id
    containerRegistry: containerRegistry.id
    hbiWorkspace: false
    managedNetwork: {
      isolationMode: 'Disabled'
    }
    publicNetworkAccess: 'Enabled'
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
  }
}

// Key Vault for AI Foundry
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${projectName}-${uniqueSuffix}'
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Container Registry for AI Foundry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: 'cr${projectName}${uniqueSuffix}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        status: 'disabled'
        type: 'Notary'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    anonymousPullEnabled: false
  }
}

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: 'asp-${projectName}-${uniqueSuffix}'
  location: location
  tags: tags
  sku: {
    name: functionAppSku
    tier: functionAppSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  properties: {
    reserved: true
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: functionAppSettings
      linuxFxVersion: 'Python|${pythonVersion}'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      alwaysOn: functionAppSku != 'Y1'
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
  }
}

// Role Assignment for Function App to access Service Bus
resource functionAppServiceBusRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: serviceBusNamespace
  name: guid(functionApp.id, serviceBusNamespace.id, 'ServiceBusDataOwner')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '090c5cfd-751d-490a-894a-3ce6f1109419') // Service Bus Data Owner
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for Function App to access AI Foundry
resource functionAppAIFoundryRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aiFoundryWorkspace
  name: guid(functionApp.id, aiFoundryWorkspace.id, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for Function App to access Storage
resource functionAppStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(functionApp.id, storageAccount.id, 'StorageBlobDataOwner')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b') // Storage Blob Data Owner
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${projectName}-${uniqueSuffix}'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'CarbonAlert'
    enabled: true
    emailReceivers: [
      {
        name: 'sustainability-team'
        emailAddress: 'sustainability@company.com'
        useCommonAlertSchema: true
      }
    ]
    webhookReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
  }
}

// Metric Alert for Carbon Threshold
resource carbonThresholdAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'carbon-threshold-exceeded-${uniqueSuffix}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when carbon emissions exceed threshold'
    enabled: true
    scopes: [
      functionApp.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    severity: 2
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'FunctionExecutionCount'
          metricName: 'FunctionExecutionCount'
          dimensions: [
            {
              name: 'FunctionName'
              operator: 'Include'
              values: [
                'carbon-monitoring-function'
              ]
            }
          ]
          operator: 'GreaterThan'
          threshold: 10
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

// =============================================================================
// OUTPUTS
// =============================================================================

@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The location where resources were deployed')
output location string = location

@description('The name of the AI Foundry project')
output aiFoundryProjectName string = aiFoundryWorkspace.name

@description('The resource ID of the AI Foundry workspace')
output aiFoundryWorkspaceId string = aiFoundryWorkspace.id

@description('The name of the Service Bus namespace')
output serviceBusNamespaceName string = serviceBusNamespace.name

@description('The Service Bus connection string')
output serviceBusConnectionString string = serviceBusNamespace.listKeys().primaryConnectionString

@description('The names of the Service Bus queues')
output serviceBusQueueNames array = [for queue in serviceBusQueues: queue.name]

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The Key Vault name')
output keyVaultName string = keyVault.name

@description('The Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The Container Registry name')
output containerRegistryName string = containerRegistry.name

@description('The Container Registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('The Action Group resource ID')
output actionGroupId string = actionGroup.id

@description('The carbon threshold alert resource ID')
output carbonThresholdAlertId string = carbonThresholdAlert.id

@description('Resource tags applied to all resources')
output tags object = tags

@description('Deployment summary')
output deploymentSummary object = {
  aiFoundryProject: aiFoundryWorkspace.name
  serviceBusNamespace: serviceBusNamespace.name
  functionApp: functionApp.name
  storageAccount: storageAccount.name
  keyVault: keyVault.name
  containerRegistry: containerRegistry.name
  queuesCreated: length(serviceBusQueues)
  monitoringEnabled: true
  alertsConfigured: true
}