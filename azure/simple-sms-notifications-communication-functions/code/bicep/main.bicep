@description('Main Bicep template for Simple SMS Notifications with Communication Services and Functions')

// Parameters for customization
@description('The name of the resource group where resources will be deployed')
param resourceGroupName string = resourceGroup().name

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names (leave empty for auto-generation)')
param uniqueSuffix string = ''

@description('Data location for Communication Services (default: United States)')
@allowed(['United States', 'Europe', 'Australia', 'United Kingdom', 'France', 'Germany', 'Switzerland'])
param dataLocation string = 'United States'

@description('Function App runtime stack')
@allowed(['node', 'dotnet', 'python'])
param functionRuntime string = 'node'

@description('Function App runtime version')
param functionRuntimeVersion string = '~20'

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'sms-notifications'
  environment: environment
  'created-by': 'bicep-template'
}

// Variables for resource naming
var suffix = !empty(uniqueSuffix) ? uniqueSuffix : substring(uniqueString(resourceGroup().id), 0, 6)
var resourceNames = {
  communicationService: 'acs-sms-${suffix}'
  functionApp: 'func-sms-${suffix}'
  storageAccount: 'stsms${suffix}'
  hostingPlan: 'plan-sms-${suffix}'
  applicationInsights: 'ai-sms-${suffix}'
  logAnalyticsWorkspace: 'log-sms-${suffix}'
}

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
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
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableApplicationInsights) {
  name: resourceNames.logAnalyticsWorkspace
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
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
  }
}

// Consumption Plan for Function App
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
    reserved: true // Required for Linux consumption plan
  }
}

// Communication Services Resource
resource communicationService 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: resourceNames.communicationService
  location: 'global'
  tags: tags
  properties: {
    dataLocation: dataLocation
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: resourceNames.functionApp
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: hostingPlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: '${upper(functionRuntime)}|${functionRuntimeVersion}'
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
          value: functionRuntime == 'node' ? '~20' : ''
        }
        {
          name: 'ACS_CONNECTION_STRING'
          value: communicationService.listKeys().primaryConnectionString
        }
        {
          name: 'SMS_FROM_PHONE'
          value: '' // Will be populated after phone number purchase
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: enableApplicationInsights ? '~3' : ''
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
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
    }
    httpsOnly: true
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Outputs for verification and integration
@description('Resource Group Name')
output resourceGroupName string = resourceGroupName

@description('Communication Services resource name')
output communicationServiceName string = communicationService.name

@description('Communication Services connection string')
@secure()
output communicationServiceConnectionString string = communicationService.listKeys().primaryConnectionString

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Function App default host key')
@secure()
output functionAppHostKey string = functionApp.listKeys().functionKeys.default

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Application Insights Instrumentation Key')
@secure()
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Application Insights Connection String')
@secure()
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('Next Steps')
output nextSteps object = {
  step1: 'Purchase a phone number through the Azure portal or CLI'
  step2: 'Update SMS_FROM_PHONE app setting with the purchased phone number'
  step3: 'Deploy your function code using Azure CLI or VS Code'
  step4: 'Test SMS functionality using the function endpoint'
  phoneNumberPurchaseCommand: 'az communication phonenumber list-available --resource-group ${resourceGroupName} --communication-service ${communicationService.name} --phone-number-type "tollFree" --assignment-type "application" --capabilities "sms"'
}

@description('Deployment summary')
output deploymentSummary object = {
  resourcesCreated: [
    'Communication Services'
    'Function App (Consumption Plan)'
    'Storage Account'
    'Hosting Plan'
    enableApplicationInsights ? 'Application Insights' : 'Application Insights (disabled)'
    enableApplicationInsights ? 'Log Analytics Workspace' : 'Log Analytics Workspace (disabled)'
  ]
  estimatedMonthlyCost: 'Function App: $0 (pay-per-use), Storage: ~$1-2, Phone Number: ~$2 (toll-free), SMS: $0.0075-0.01 per message'
  securityFeatures: [
    'HTTPS enforced'
    'System-assigned managed identity'
    'Storage account secure access'
    'Function authentication required'
    'TLS 1.2 minimum'
  ]
}