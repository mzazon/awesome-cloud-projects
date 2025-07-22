// ==============================================================================
// Main Bicep template for Secure Code Execution Workflows
// Implements Azure Container Apps Dynamic Sessions with Event Grid integration
// ==============================================================================

@description('Primary Azure region for resource deployment')
param location string = resourceGroup().location

@description('Unique suffix for resource naming (3-6 characters)')
@minLength(3)
@maxLength(6)
param resourceSuffix string

@description('Environment name for resource tagging and naming')
@allowed(['dev', 'test', 'staging', 'prod'])
param environment string = 'dev'

@description('Maximum number of sessions in the session pool')
@minValue(5)
@maxValue(100)
param maxSessions int = 20

@description('Number of ready sessions to maintain in the pool')
@minValue(1)
@maxValue(20)
param readySessions int = 5

@description('Session cooldown period in seconds')
@minValue(60)
@maxValue(3600)
param cooldownPeriod int = 300

@description('Enable network isolation for session pool (recommended for security)')
param enableNetworkIsolation bool = true

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 90

@description('Application Insights sampling percentage')
@minValue(0)
@maxValue(100)
param samplingPercentage int = 100

@description('Storage account access tier')
@allowed(['Hot', 'Cool'])
param storageAccessTier string = 'Hot'

@description('Key Vault SKU')
@allowed(['standard', 'premium'])
param keyVaultSku string = 'standard'

// ==============================================================================
// Variables
// ==============================================================================

var namePrefix = 'sec-code-exec'
var tags = {
  environment: environment
  purpose: 'secure-code-execution'
  solution: 'container-apps-dynamic-sessions'
  managedBy: 'bicep'
}

// Resource names with suffix
var logAnalyticsWorkspaceName = '${namePrefix}-law-${resourceSuffix}'
var applicationInsightsName = '${namePrefix}-ai-${resourceSuffix}'
var keyVaultName = '${namePrefix}-kv-${resourceSuffix}'
var storageAccountName = '${namePrefix}st${resourceSuffix}'
var containerAppsEnvironmentName = '${namePrefix}-cae-${resourceSuffix}'
var sessionPoolName = '${namePrefix}-pool-${resourceSuffix}'
var eventGridTopicName = '${namePrefix}-egt-${resourceSuffix}'
var functionAppName = '${namePrefix}-func-${resourceSuffix}'
var appServicePlanName = '${namePrefix}-asp-${resourceSuffix}'

// ==============================================================================
// Log Analytics Workspace
// ==============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 10
    }
  }
}

// ==============================================================================
// Application Insights
// ==============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    SamplingPercentage: samplingPercentage
    RetentionInDays: logRetentionDays
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ==============================================================================
// Key Vault
// ==============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
  }
}

// ==============================================================================
// Storage Account
// ==============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: storageAccessTier
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
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
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Storage containers for execution results and logs
resource executionResultsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storageAccount.name}/default/execution-results'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'execution-results'
      environment: environment
    }
  }
}

resource executionLogsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storageAccount.name}/default/execution-logs'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'execution-logs'
      environment: environment
    }
  }
}

// ==============================================================================
// Container Apps Environment
// ==============================================================================

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    infrastructureResourceGroup: '${resourceGroup().name}-infrastructure'
  }
}

// ==============================================================================
// Container Apps Session Pool
// ==============================================================================

resource sessionPool 'Microsoft.App/sessionPools@2024-08-02-preview' = {
  name: sessionPoolName
  location: location
  tags: tags
  properties: {
    environmentId: containerAppsEnvironment.id
    poolManagementType: 'Dynamic'
    sessionPoolType: 'PythonLTS'
    dynamicPoolConfiguration: {
      cooldownPeriodInSeconds: cooldownPeriod
      executionType: 'Timed'
    }
    containerType: 'PythonLTS'
    sessionNetworkConfiguration: {
      status: enableNetworkIsolation ? 'EgressDisabled' : 'EgressEnabled'
    }
    scaleConfiguration: {
      maxConcurrentSessions: maxSessions
      readySessionInstances: readySessions
    }
  }
}

// ==============================================================================
// Event Grid Topic
// ==============================================================================

resource eventGridTopic 'Microsoft.EventGrid/topics@2024-06-01-preview' = {
  name: eventGridTopicName
  location: location
  tags: tags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    dataResidencyBoundary: 'WithinGeopair'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ==============================================================================
// App Service Plan for Function App
// ==============================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    computeMode: 'Dynamic'
    reserved: true // Linux
  }
}

// ==============================================================================
// Function App
// ==============================================================================

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'Python|3.11'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
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
          value: 'python'
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
          name: 'SESSION_POOL_ENDPOINT'
          value: 'https://${sessionPool.name}.${location}.azurecontainerapps.io'
        }
        {
          name: 'KEY_VAULT_URL'
          value: 'https://${keyVault.name}.vault.azure.net/'
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'EVENT_GRID_TOPIC_ENDPOINT'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      preWarmedInstanceCount: 0
      functionAppScaleLimit: 200
      healthCheckPath: '/api/health'
    }
    httpsOnly: true
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// ==============================================================================
// RBAC Role Assignments
// ==============================================================================

// Key Vault Secrets User role for Function App
resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Data Contributor role for Function App
resource storageBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Container Apps Session Executor role for Function App
resource sessionExecutorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sessionPool.id, functionApp.id, 'Container Apps Session Executor')
  scope: sessionPool
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0fb8eba5-a2bb-4abe-b1c1-49dfad359bb0') // Container Apps Session Executor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Event Grid Data Sender role for Function App
resource eventGridDataSenderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, functionApp.id, 'EventGrid Data Sender')
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7') // EventGrid Data Sender
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ==============================================================================
// Event Grid Subscription
// ==============================================================================

resource eventGridSubscription 'Microsoft.EventGrid/topics/eventSubscriptions@2024-06-01-preview' = {
  name: 'code-execution-subscription'
  parent: eventGridTopic
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/ProcessCodeExecution'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      subjectBeginsWith: 'code-execution'
      includedEventTypes: [
        'Microsoft.EventGrid.ExecuteCode'
      ]
      enableAdvancedFilteringOnArrays: true
    }
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
    deadLetterDestination: {
      endpointType: 'StorageBlob'
      properties: {
        resourceId: storageAccount.id
        blobContainerName: 'execution-logs'
      }
    }
  }
}

// ==============================================================================
// Diagnostic Settings
// ==============================================================================

resource sessionPoolDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sessionpool-diagnostics'
  scope: sessionPool
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

resource eventGridTopicDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'eventgrid-diagnostics'
  scope: eventGridTopic
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// ==============================================================================
// Outputs
// ==============================================================================

@description('Resource group name where resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('Azure region where resources were deployed')
output location string = location

@description('Environment name used for deployment')
output environment string = environment

@description('Log Analytics workspace ID for monitoring')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Key Vault resource ID')
output keyVaultId string = keyVault.id

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = 'https://${keyVault.name}.vault.azure.net/'

@description('Storage account resource ID')
output storageAccountId string = storageAccount.id

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account primary endpoint')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Container Apps Environment resource ID')
output containerAppsEnvironmentId string = containerAppsEnvironment.id

@description('Container Apps Environment name')
output containerAppsEnvironmentName string = containerAppsEnvironment.name

@description('Session pool resource ID')
output sessionPoolId string = sessionPool.id

@description('Session pool name')
output sessionPoolName string = sessionPool.name

@description('Session pool management endpoint')
output sessionPoolEndpoint string = 'https://${sessionPool.name}.${location}.azurecontainerapps.io'

@description('Event Grid topic resource ID')
output eventGridTopicId string = eventGridTopic.id

@description('Event Grid topic name')
output eventGridTopicName string = eventGridTopic.name

@description('Event Grid topic endpoint')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('Function App resource ID')
output functionAppId string = functionApp.id

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App default hostname')
output functionAppDefaultHostname string = functionApp.properties.defaultHostName

@description('Function App system-assigned managed identity principal ID')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('Event Grid subscription name')
output eventGridSubscriptionName string = eventGridSubscription.name

@description('Tags applied to all resources')
output resourceTags object = tags