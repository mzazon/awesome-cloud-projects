// ==========================================================================
// Bicep Template: Simple Contact Form with Functions and Table Storage
// ==========================================================================
// This template deploys a serverless contact form solution using:
// - Azure Functions (Consumption Plan) for HTTP request processing
// - Azure Storage Account with Table Storage for contact data persistence
// - Application Insights for monitoring and logging
// ==========================================================================

targetScope = 'resourceGroup'

// ==========================================================================
// PARAMETERS
// ==========================================================================

@description('Base name for all resources (will be used to generate unique names)')
@minLength(3)
@maxLength(10)
param baseName string = 'contact'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Environment suffix (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  project: 'SimpleContactForm'
  environment: environment
  managedBy: 'Bicep'
}

@description('Function App runtime stack')
@allowed(['node', 'python', 'dotnet', 'java'])
param functionRuntime string = 'node'

@description('Function App runtime version')
param functionRuntimeVersion string = '20'

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Function App consumption plan name override (optional)')
param consumptionPlanName string = ''

@description('CORS allowed origins for the Function App')
param corsAllowedOrigins array = ['*']

// ==========================================================================
// VARIABLES
// ==========================================================================

var uniqueSuffix = uniqueString(resourceGroup().id, baseName)
var resourceNames = {
  storageAccount: 'st${baseName}${uniqueSuffix}'
  functionApp: 'func-${baseName}-${uniqueSuffix}'
  hostingPlan: !empty(consumptionPlanName) ? consumptionPlanName : 'plan-${baseName}-${uniqueSuffix}'
  applicationInsights: 'ai-${baseName}-${uniqueSuffix}'
  logAnalyticsWorkspace: 'law-${baseName}-${uniqueSuffix}'
}

var functionAppSettings = [
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
    value: toLower(resourceNames.functionApp)
  }
  {
    name: 'FUNCTIONS_EXTENSION_VERSION'
    value: '~4'
  }
  {
    name: 'FUNCTIONS_WORKER_RUNTIME'
    value: functionRuntime
  }
  {
    name: 'WEBSITE_NODE_DEFAULT_VERSION'
    value: functionRuntime == 'node' ? '~${functionRuntimeVersion}' : ''
  }
  {
    name: 'WEBSITE_RUN_FROM_PACKAGE'
    value: '1'
  }
]

var applicationInsightsSettings = enableApplicationInsights ? [
  {
    name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
    value: applicationInsights.properties.InstrumentationKey
  }
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: applicationInsights.properties.ConnectionString
  }
] : []

// ==========================================================================
// RESOURCES
// ==========================================================================

// Log Analytics Workspace (required for Application Insights)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableApplicationInsights) {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for monitoring and logging
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for Function App and Table Storage
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
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
        table: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

// Table Service for contact form data storage
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

// Contacts table for storing form submissions
resource contactsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  parent: tableService
  name: 'contacts'
  properties: {}
}

// App Service Plan (Consumption Plan for serverless)
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: resourceNames.hostingPlan
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  kind: 'functionapp'
  properties: {
    computeMode: 'Dynamic'
    reserved: false
  }
}

// Function App for processing contact form submissions
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: resourceNames.functionApp
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    reserved: false
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      appSettings: concat(functionAppSettings, applicationInsightsSettings)
      cors: {
        allowedOrigins: corsAllowedOrigins
        supportCredentials: false
      }
      use32BitWorkerProcess: true
      ftpsState: 'FtpsOnly'
      netFrameworkVersion: 'v6.0'
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    containerSize: 1536
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Function App Configuration (additional settings)
resource functionAppConfig 'Microsoft.Web/sites/config@2023-01-01' = {
  parent: functionApp
  name: 'web'
  properties: {
    numberOfWorkers: 1
    defaultDocuments: [
      'Default.htm'
      'Default.html'
      'index.html'
    ]
    netFrameworkVersion: 'v6.0'
    requestTracingEnabled: false
    remoteDebuggingEnabled: false
    httpLoggingEnabled: false
    acrUseManagedIdentityCreds: false
    logsDirectorySizeLimit: 35
    detailedErrorLoggingEnabled: false
    publishingUsername: '$${resourceNames.functionApp}'
    scmType: 'None'
    use32BitWorkerProcess: true
    webSocketsEnabled: false
    alwaysOn: false
    managedPipelineMode: 'Integrated'
    virtualApplications: [
      {
        virtualPath: '/'
        physicalPath: 'site\\wwwroot'
        preloadEnabled: false
      }
    ]
    loadBalancing: 'LeastRequests'
    experiments: {
      rampUpRules: []
    }
    autoHealEnabled: false
    vnetRouteAllEnabled: false
    vnetPrivatePortsCount: 0
    cors: {
      allowedOrigins: corsAllowedOrigins
      supportCredentials: false
    }
    localMySqlEnabled: false
    managedServiceIdentityId: functionApp.identity.principalId
    ipSecurityRestrictions: [
      {
        ipAddress: 'Any'
        action: 'Allow'
        priority: 2147483647
        name: 'Allow all'
        description: 'Allow all access'
      }
    ]
    scmIpSecurityRestrictions: [
      {
        ipAddress: 'Any'
        action: 'Allow'
        priority: 2147483647
        name: 'Allow all'
        description: 'Allow all access'
      }
    ]
    scmIpSecurityRestrictionsUseMain: false
    http20Enabled: false
    minTlsVersion: '1.2'
    scmMinTlsVersion: '1.2'
    ftpsState: 'FtpsOnly'
    preWarmedInstanceCount: 0
    functionAppScaleLimit: 200
    functionsRuntimeScaleMonitoringEnabled: false
    minimumElasticInstanceCount: 0
    azureStorageAccounts: {}
  }
}

// ==========================================================================
// ROLE ASSIGNMENTS
// ==========================================================================

// Built-in role definition for Storage Account Contributor
var storageAccountContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')

// Role assignment for Function App to access Storage Account
resource functionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageAccountContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageAccountContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ==========================================================================
// OUTPUTS
// ==========================================================================

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('Storage Account Connection String')
@secure()
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('Function App Name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Function App Principal ID (for additional role assignments)')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('Hosting Plan Name')
output hostingPlanName string = hostingPlan.name

@description('Contacts Table Name')
output contactsTableName string = contactsTable.name

@description('Application Insights Name (if enabled)')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''

@description('Application Insights Instrumentation Key (if enabled)')
@secure()
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Application Insights Connection String (if enabled)')
@secure()
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('Log Analytics Workspace Name (if enabled)')
output logAnalyticsWorkspaceName string = enableApplicationInsights ? logAnalyticsWorkspace.name : ''

@description('Resource names for reference')
output resourceNames object = {
  storageAccount: storageAccount.name
  functionApp: functionApp.name
  hostingPlan: hostingPlan.name
  applicationInsights: enableApplicationInsights ? applicationInsights.name : ''
  logAnalyticsWorkspace: enableApplicationInsights ? logAnalyticsWorkspace.name : ''
  contactsTable: contactsTable.name
}

@description('Function App Settings (for validation)')
output functionAppSettings array = functionApp.properties.siteConfig.appSettings

@description('API Endpoint URL for contact form submissions')
output contactFormApiUrl string = 'https://${functionApp.properties.defaultHostName}/api/contact'

@description('Deployment summary')
output deploymentSummary object = {
  resourceGroupName: resourceGroup().name
  location: location
  environment: environment
  totalResourcesDeployed: enableApplicationInsights ? 7 : 5
  contactFormEndpoint: 'https://${functionApp.properties.defaultHostName}/api/contact'
  monitoringEnabled: enableApplicationInsights
  storageType: storageAccountSku
  functionRuntime: '${functionRuntime} ${functionRuntimeVersion}'
}