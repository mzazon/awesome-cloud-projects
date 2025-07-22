// ==============================================================================
// Azure Secure User Onboarding Automation - Main Bicep Template
// ==============================================================================
// This template deploys a complete automated user onboarding solution using:
// - Azure Entra ID for identity management
// - Azure Service Bus for reliable messaging
// - Azure Logic Apps for workflow orchestration
// - Azure Key Vault for secure credential storage
// ==============================================================================

targetScope = 'resourceGroup'

// ==============================================================================
// PARAMETERS
// ==============================================================================

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Service Bus namespace SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param serviceBusSkuName string = 'Standard'

@description('Key Vault SKU')
@allowed(['standard', 'premium'])
param keyVaultSkuName string = 'standard'

@description('Logic Apps hosting plan SKU')
@allowed(['WS1', 'WS2', 'WS3'])
param logicAppPlanSku string = 'WS1'

@description('Application registration display name')
param appRegistrationDisplayName string = 'User Onboarding Automation'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'user-onboarding'
  environment: environment
  project: 'automation'
  solution: 'entra-servicebus-onboarding'
}

@description('Enable diagnostic logs')
param enableDiagnostics bool = true

@description('Log Analytics workspace ID for diagnostics (optional)')
param logAnalyticsWorkspaceId string = ''

@description('Storage account tier for Logic Apps')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountTier string = 'Standard_LRS'

@description('Service Bus message retention in days')
@minValue(1)
@maxValue(14)
param messageRetentionDays int = 14

@description('Service Bus maximum delivery count')
@minValue(1)
@maxValue(10)
param maxDeliveryCount int = 5

@description('Enable Service Bus duplicate detection')
param enableDuplicateDetection bool = true

@description('Key Vault soft delete retention days')
@minValue(7)
@maxValue(90)
param keyVaultRetentionDays int = 90

// ==============================================================================
// VARIABLES
// ==============================================================================

var resourcePrefix = 'onboarding-${environment}-${uniqueSuffix}'
var serviceBusNamespace = 'sb-${resourcePrefix}'
var keyVaultName = 'kv-${resourcePrefix}'
var logicAppName = 'la-${resourcePrefix}'
var storageAccountName = 'st${replace(resourcePrefix, '-', '')}'
var appServicePlanName = 'asp-${resourcePrefix}'
var applicationInsightsName = 'ai-${resourcePrefix}'

// Service Bus configuration
var serviceBusQueueName = 'user-onboarding-queue'
var serviceBusTopicName = 'user-onboarding-events'
var serviceBusAuthRuleName = 'LogicAppsAccess'

// Key Vault configuration
var keyVaultSecretNames = {
  serviceBusConnection: 'ServiceBusConnection'
  applicationInsightsKey: 'ApplicationInsightsInstrumentationKey'
  storageAccountConnection: 'StorageAccountConnection'
}

// ==============================================================================
// MODULES
// ==============================================================================

// Key Vault module for secure credential storage
module keyVault 'modules/keyVault.bicep' = {
  name: 'keyVault-deployment'
  params: {
    keyVaultName: keyVaultName
    location: location
    skuName: keyVaultSkuName
    retentionDays: keyVaultRetentionDays
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: true
    tags: tags
    enableDiagnostics: enableDiagnostics
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}

// Service Bus module for reliable messaging
module serviceBus 'modules/serviceBus.bicep' = {
  name: 'serviceBus-deployment'
  params: {
    namespaceName: serviceBusNamespace
    location: location
    skuName: serviceBusSkuName
    queueName: serviceBusQueueName
    topicName: serviceBusTopicName
    authRuleName: serviceBusAuthRuleName
    messageRetentionDays: messageRetentionDays
    maxDeliveryCount: maxDeliveryCount
    enableDuplicateDetection: enableDuplicateDetection
    tags: tags
    enableDiagnostics: enableDiagnostics
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}

// Storage Account for Logic Apps
module storageAccount 'modules/storageAccount.bicep' = {
  name: 'storageAccount-deployment'
  params: {
    storageAccountName: storageAccountName
    location: location
    skuName: storageAccountTier
    tags: tags
    enableDiagnostics: enableDiagnostics
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 90
    IngestionMode: 'ApplicationInsights'
    WorkspaceResourceId: !empty(logAnalyticsWorkspaceId) ? logAnalyticsWorkspaceId : null
  }
}

// App Service Plan for Logic Apps
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: logicAppPlanSku
    tier: 'WorkflowStandard'
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: 20
    isSpot: false
    reserved: false
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
  }
}

// ==============================================================================
// KEY VAULT SECRETS
// ==============================================================================

// Store Service Bus connection string
resource serviceBusConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault.outputs.keyVaultResource
  name: keyVaultSecretNames.serviceBusConnection
  properties: {
    value: serviceBus.outputs.connectionString
    contentType: 'application/x-connection-string'
    attributes: {
      enabled: true
    }
  }
}

// Store Application Insights instrumentation key
resource applicationInsightsKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault.outputs.keyVaultResource
  name: keyVaultSecretNames.applicationInsightsKey
  properties: {
    value: applicationInsights.properties.InstrumentationKey
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Store Storage Account connection string
resource storageAccountConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault.outputs.keyVaultResource
  name: keyVaultSecretNames.storageAccountConnection
  properties: {
    value: storageAccount.outputs.connectionString
    contentType: 'application/x-connection-string'
    attributes: {
      enabled: true
    }
  }
}

// ==============================================================================
// LOGIC APPS CONFIGURATION
// ==============================================================================

// Logic Apps configuration with Key Vault references
var logicAppSettings = [
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
    name: 'AzureWebJobsStorage'
    value: '@Microsoft.KeyVault(SecretUri=${keyVault.outputs.keyVaultUri}secrets/${keyVaultSecretNames.storageAccountConnection}/)'
  }
  {
    name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
    value: '@Microsoft.KeyVault(SecretUri=${keyVault.outputs.keyVaultUri}secrets/${keyVaultSecretNames.storageAccountConnection}/)'
  }
  {
    name: 'WEBSITE_CONTENTSHARE'
    value: '${logicAppName}-content'
  }
  {
    name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
    value: '@Microsoft.KeyVault(SecretUri=${keyVault.outputs.keyVaultUri}secrets/${keyVaultSecretNames.applicationInsightsKey}/)'
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: applicationInsights.properties.ConnectionString
  }
  {
    name: 'ServiceBusConnection'
    value: '@Microsoft.KeyVault(SecretUri=${keyVault.outputs.keyVaultUri}secrets/${keyVaultSecretNames.serviceBusConnection}/)'
  }
]

// Logic Apps for workflow orchestration
resource logicApp 'Microsoft.Web/sites@2022-09-01' = {
  name: logicAppName
  location: location
  tags: tags
  kind: 'functionapp,workflowapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 1
      appSettings: logicAppSettings
    }
    httpsOnly: true
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
  }
  dependsOn: [
    serviceBusConnectionSecret
    applicationInsightsKeySecret
    storageAccountConnectionSecret
  ]
}

// ==============================================================================
// RBAC ASSIGNMENTS
// ==============================================================================

// Logic Apps system-assigned identity needs access to Key Vault
resource logicAppKeyVaultAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.outputs.keyVaultResourceId, logicApp.id, 'Key Vault Secrets User')
  scope: keyVault.outputs.keyVaultResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Logic Apps needs access to Service Bus
resource logicAppServiceBusAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.outputs.serviceBusResourceId, logicApp.id, 'Azure Service Bus Data Owner')
  scope: serviceBus.outputs.serviceBusResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '090c5cfd-751d-490a-894a-3ce6f1109419') // Azure Service Bus Data Owner
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Logic Apps needs access to Storage Account
resource logicAppStorageAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.outputs.storageAccountResourceId, logicApp.id, 'Storage Blob Data Contributor')
  scope: storageAccount.outputs.storageAccountResource
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ==============================================================================
// DIAGNOSTIC SETTINGS
// ==============================================================================

// Logic Apps diagnostic settings
resource logicAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics && !empty(logAnalyticsWorkspaceId)) {
  name: 'logicapp-diagnostics'
  scope: logicApp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'WorkflowRuntime'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Resource Group location')
output location string = location

@description('Key Vault name')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('Key Vault URI')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('Service Bus namespace name')
output serviceBusNamespaceName string = serviceBus.outputs.namespaceName

@description('Service Bus queue name')
output serviceBusQueueName string = serviceBus.outputs.queueName

@description('Service Bus topic name')
output serviceBusTopicName string = serviceBus.outputs.topicName

@description('Logic Apps name')
output logicAppName string = logicApp.name

@description('Logic Apps default hostname')
output logicAppDefaultHostName string = logicApp.properties.defaultHostName

@description('Logic Apps system-assigned identity principal ID')
output logicAppPrincipalId string = logicApp.identity.principalId

@description('Storage Account name')
output storageAccountName string = storageAccount.outputs.storageAccountName

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights instrumentation key')
@secure()
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Deployment summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  environment: environment
  keyVault: keyVault.outputs.keyVaultName
  serviceBus: serviceBus.outputs.namespaceName
  logicApp: logicApp.name
  storageAccount: storageAccount.outputs.storageAccountName
  applicationInsights: applicationInsights.name
  deploymentTime: utcNow()
}

@description('Next steps for configuration')
output nextSteps array = [
  'Configure Azure Entra ID application registration with appropriate permissions'
  'Deploy Logic Apps workflow definition using Azure CLI or Portal'
  'Configure Service Bus queue and topic subscriptions'
  'Set up monitoring and alerts in Application Insights'
  'Test the user onboarding workflow with sample data'
  'Configure lifecycle workflows in Azure Entra ID'
]

@description('Key Vault secrets created')
output keyVaultSecrets array = [
  keyVaultSecretNames.serviceBusConnection
  keyVaultSecretNames.applicationInsightsKey
  keyVaultSecretNames.storageAccountConnection
]

@description('RBAC assignments created')
output rbacAssignments array = [
  'Logic Apps -> Key Vault Secrets User'
  'Logic Apps -> Azure Service Bus Data Owner'
  'Logic Apps -> Storage Blob Data Contributor'
]