@description('Main Bicep template for Voice-Enabled Business Process Automation with Azure Speech Services and Power Platform')

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Project name prefix for resource naming')
@minLength(3)
@maxLength(10)
param projectName string = 'voiceauto'

@description('Speech Services pricing tier')
@allowed(['F0', 'S0'])
param speechServiceSku string = 'S0'

@description('Logic App Standard plan SKU')
@allowed(['WS1', 'WS2', 'WS3'])
param logicAppPlanSku string = 'WS1'

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Tags to be applied to all resources')
param tags object = {
  Environment: environment
  Project: 'VoiceAutomation'
  'Created-By': 'Bicep'
}

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id, deployment().name)
var speechServiceName = '${projectName}-speech-${environment}-${uniqueSuffix}'
var logicAppName = '${projectName}-logic-${environment}-${uniqueSuffix}'
var storageAccountName = '${projectName}st${environment}${uniqueSuffix}'
var appServicePlanName = '${projectName}-plan-${environment}-${uniqueSuffix}'
var appInsightsName = '${projectName}-ai-${environment}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${projectName}-law-${environment}-${uniqueSuffix}'

// Storage Account for Logic Apps
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: take(replace(storageAccountName, '-', ''), 24)
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
    allowSharedKeyAccess: true
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
      bypass: 'AzureServices'
    }
  }
}

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableApplicationInsights) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
  }
}

// Azure AI Speech Service
resource speechService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: speechServiceName
  location: location
  tags: tags
  sku: {
    name: speechServiceSku
  }
  kind: 'SpeechServices'
  properties: {
    customSubDomainName: speechServiceName
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// App Service Plan for Logic Apps Standard
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
    targetWorkerCount: 1
    maximumElasticWorkerCount: 20
    elasticScaleEnabled: true
    isSpot: false
    zoneRedundant: false
  }
}

// Logic App Standard for speech processing
resource logicApp 'Microsoft.Web/sites@2022-09-01' = {
  name: logicAppName
  location: location
  tags: tags
  kind: 'functionapp,workflowapp'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      functionsRuntimeScaleMonitoringEnabled: true
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
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
          name: 'AzureFunctionsJobHost__extensionBundle__id'
          value: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__version'
          value: '[1.*, 2.0.0)'
        }
        {
          name: 'APP_KIND'
          value: 'workflowApp'
        }
        {
          name: 'SPEECH_SERVICE_ENDPOINT'
          value: speechService.properties.endpoint
        }
        {
          name: 'SPEECH_SERVICE_KEY'
          value: speechService.listKeys().key1
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
          'https://ms.portal.azure.com'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
    clientAffinityEnabled: false
  }
}

// Role Assignment for Logic App to access Speech Service
resource speechServiceContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68' // Cognitive Services Contributor
}

resource logicAppSpeechServiceRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(speechService.id, logicApp.id, speechServiceContributorRole.id)
  scope: speechService
  properties: {
    roleDefinitionId: speechServiceContributorRole.id
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Enable system-assigned managed identity for Logic App
resource logicAppIdentity 'Microsoft.Web/sites/config@2022-09-01' = {
  name: 'web'
  parent: logicApp
  properties: {
    managedServiceIdentityId: logicApp.identity.principalId
  }
}

// Outputs
@description('The name of the Speech Service')
output speechServiceName string = speechService.name

@description('The endpoint of the Speech Service')
output speechServiceEndpoint string = speechService.properties.endpoint

@description('The name of the Logic App')
output logicAppName string = logicApp.name

@description('The default hostname of the Logic App')
output logicAppDefaultHostname string = logicApp.properties.defaultHostName

@description('The resource ID of the Logic App')
output logicAppResourceId string = logicApp.id

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('The location where resources were deployed')
output deploymentLocation string = location

@description('Application Insights connection string')
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Speech Service key for client applications')
@secure()
output speechServiceKey string = speechService.listKeys().key1

@description('Storage account connection string')
@secure()
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'