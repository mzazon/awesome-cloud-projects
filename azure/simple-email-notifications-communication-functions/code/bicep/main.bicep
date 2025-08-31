// Infrastructure as Code for Simple Email Notifications with Communication Services
// This template creates a complete serverless email notification system using Azure Communication Services and Azure Functions

targetScope = 'resourceGroup'

// =====================================
// PARAMETERS
// =====================================

@description('The Azure region where all resources will be deployed')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'westeurope'
  'northeurope'
  'southeastasia'
  'eastasia'
])
param location string = 'eastus'

@description('A unique suffix to append to resource names to avoid naming conflicts')
@minLength(3)
@maxLength(6)
param resourceSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Environment name for resource tagging and naming')
@allowed([
  'dev'
  'test'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Project name for resource tagging and naming')
@minLength(3)
@maxLength(15)
param projectName string = 'email-notify'

@description('The name of the sender for outgoing emails')
@minLength(3)
@maxLength(50)
param senderName string = 'Azure Notification System'

@description('The sender email address display name')
@minLength(3)
@maxLength(100)
param senderDisplayName string = 'Azure Email Notifications'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: projectName
  Purpose: 'email-notifications'
  IaC: 'bicep'
  Recipe: 'simple-email-notifications-communication-functions'
}

@description('Azure Functions runtime version')
@allowed([
  '~4'
  '~3'
])
param functionsExtensionVersion string = '~4'

@description('Node.js runtime version for Azure Functions')
@allowed([
  '18'
  '16'
])
param nodeVersion string = '18'

// =====================================
// VARIABLES
// =====================================

var resourcePrefix = '${projectName}-${environment}'
var communicationServiceName = 'cs-${resourcePrefix}-${resourceSuffix}'
var emailServiceName = 'email-${resourcePrefix}-${resourceSuffix}'
var functionAppName = 'func-${resourcePrefix}-${resourceSuffix}'
var storageAccountName = 'st${replace(resourcePrefix, '-', '')}${resourceSuffix}'
var appServicePlanName = 'plan-${resourcePrefix}-${resourceSuffix}'
var applicationInsightsName = 'ai-${resourcePrefix}-${resourceSuffix}'
var logAnalyticsWorkspaceName = 'law-${resourcePrefix}-${resourceSuffix}'

// =====================================
// RESOURCES
// =====================================

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
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

// Application Insights for monitoring Function App
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 30
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for Azure Functions runtime
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
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

// Communication Services resource for email sending
resource communicationService 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: communicationServiceName
  location: 'global'
  tags: tags
  properties: {
    dataLocation: 'United States'
    linkedDomains: []
  }
}

// Email Communication Service
resource emailService 'Microsoft.Communication/emailServices@2023-04-01' = {
  name: emailServiceName
  location: 'global'
  tags: tags
  properties: {
    dataLocation: 'United States'
  }
}

// Azure Managed Domain for email sending
resource emailDomain 'Microsoft.Communication/emailServices/domains@2023-04-01' = {
  parent: emailService
  name: 'AzureManagedDomain'
  location: 'global'
  tags: tags
  properties: {
    domainManagement: 'AzureManaged'
    userEngagementTracking: 'Disabled'
  }
}

// Link the email service to communication services
resource communicationServiceEmailLink 'Microsoft.Communication/communicationServices/linkedDomains@2023-04-01' = {
  parent: communicationService
  name: emailDomain.properties.fromSenderDomain
  properties: {
    domainId: emailDomain.id
  }
}

// App Service Plan for Azure Functions (Consumption plan)
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
    reserved: true // Required for Linux consumption plan
  }
}

// Azure Function App
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
    reserved: true // Required for Linux
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'NODE|${nodeVersion}'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      netFrameworkVersion: 'v6.0'
      powerShellVersion: '~7'
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
        supportCredentials: false
      }
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

// Function App Configuration Settings
resource functionAppSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'appsettings'
  properties: {
    // Azure Functions runtime settings
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    WEBSITE_CONTENTSHARE: toLower(functionAppName)
    FUNCTIONS_EXTENSION_VERSION: functionsExtensionVersion
    WEBSITE_NODE_DEFAULT_VERSION: '~${nodeVersion}'
    FUNCTIONS_WORKER_RUNTIME: 'node'
    
    // Application Insights settings
    APPINSIGHTS_INSTRUMENTATIONKEY: applicationInsights.properties.InstrumentationKey
    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
    
    // Communication Services settings
    COMMUNICATION_SERVICES_CONNECTION_STRING: communicationService.listKeys().primaryConnectionString
    SENDER_ADDRESS: 'DoNotReply@${emailDomain.properties.fromSenderDomain}'
    SENDER_NAME: senderName
    SENDER_DISPLAY_NAME: senderDisplayName
    
    // Function App settings
    WEBSITE_RUN_FROM_PACKAGE: '1'
    WEBSITE_ENABLE_SYNC_UPDATE_SITE: 'true'
    SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    
    // Security settings
    WEBSITE_HTTPLOGGING_RETENTION_DAYS: '3'
    WEBSITE_DISABLE_SCM_SEPARATION: 'false'
  }
}

// Function App host configuration
resource functionAppHostConfig 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: functionApp
  name: 'host'
  properties: {
    version: '2.0'
    functionTimeout: '00:05:00'
    logging: {
      applicationInsights: {
        samplingSettings: {
          isEnabled: true
          maxTelemetryItemsPerSecond: 20
          excludedTypes: 'Request'
        }
      }
    }
    extensionBundle: {
      id: 'Microsoft.Azure.Functions.ExtensionBundle'
      version: '[3.*, 4.0.0)'
    }
    functionAppScaleLimit: 200
    healthMonitor: {
      enabled: true
      healthCheckInterval: '00:00:10'
      healthCheckWindow: '00:02:00'
      healthCheckThreshold: 6
      counterThreshold: 0.80
    }
  }
}

// =====================================
// OUTPUTS
// =====================================

@description('The name of the Communication Services resource')
output communicationServiceName string = communicationService.name

@description('The name of the Email Service resource')
output emailServiceName string = emailService.name

@description('The sender domain for outgoing emails')
output senderDomain string = emailDomain.properties.fromSenderDomain

@description('The complete sender email address')
output senderEmailAddress string = 'DoNotReply@${emailDomain.properties.fromSenderDomain}'

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The URL of the Function App')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The Function App default hostname')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The name of the Storage Account')
output storageAccountName string = storageAccount.name

@description('The name of the Application Insights instance')
output applicationInsightsName string = applicationInsights.name

@description('The Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The Connection String for Communication Services')
output communicationServicesConnectionString string = communicationService.listKeys().primaryConnectionString

@description('The Resource Group name where all resources are deployed')
output resourceGroupName string = resourceGroup().name

@description('The Azure region where resources are deployed')
output deploymentLocation string = location

@description('Tags applied to all resources')
output resourceTags object = tags

@description('Function App System Assigned Managed Identity Principal ID')
output functionAppManagedIdentityPrincipalId string = functionApp.identity.principalId

@description('Function App System Assigned Managed Identity Tenant ID')
output functionAppManagedIdentityTenantId string = functionApp.identity.tenantId

@description('Log Analytics Workspace ID for monitoring')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Resource IDs for all created resources')
output resourceIds object = {
  communicationService: communicationService.id
  emailService: emailService.id
  emailDomain: emailDomain.id
  functionApp: functionApp.id
  storageAccount: storageAccount.id
  appServicePlan: appServicePlan.id
  applicationInsights: applicationInsights.id
  logAnalyticsWorkspace: logAnalyticsWorkspace.id
}