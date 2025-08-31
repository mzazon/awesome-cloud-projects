@description('Main Bicep template for Simple Daily Quote Generator with Azure Functions and Table Storage')

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Application name prefix for resource naming')
@minLength(3)
@maxLength(10)
param appName string = 'quote'

@description('Unique suffix for resource names (3-6 characters)')
@minLength(3)
@maxLength(6)
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Function App runtime stack')
@allowed(['node'])
param functionAppRuntime string = 'node'

@description('Function App runtime version')
@allowed(['20'])
param functionAppRuntimeVersion string = '20'

@description('Function App plan SKU (Consumption plan)')
@allowed(['Y1'])
param functionAppPlanSku string = 'Y1'

@description('Enable Application Insights monitoring')
param enableApplicationInsights bool = true

@description('Sample quotes to populate Table Storage')
param sampleQuotes array = [
  {
    partitionKey: 'inspiration'
    rowKey: '001'
    quote: 'The only way to do great work is to love what you do.'
    author: 'Steve Jobs'
    category: 'motivation'
  }
  {
    partitionKey: 'inspiration'
    rowKey: '002'
    quote: 'Innovation distinguishes between a leader and a follower.'
    author: 'Steve Jobs'
    category: 'innovation'
  }
  {
    partitionKey: 'inspiration'
    rowKey: '003'
    quote: 'Success is not final, failure is not fatal.'
    author: 'Winston Churchill'
    category: 'perseverance'
  }
  {
    partitionKey: 'inspiration'
    rowKey: '004'
    quote: 'The future belongs to those who believe in the beauty of their dreams.'
    author: 'Eleanor Roosevelt'
    category: 'dreams'
  }
  {
    partitionKey: 'inspiration'
    rowKey: '005'
    quote: 'It is during our darkest moments that we must focus to see the light.'
    author: 'Aristotle'
    category: 'hope'
  }
]

// Variables
var resourcePrefix = '${appName}-${environment}'
var storageAccountName = 'st${appName}${uniqueSuffix}'
var functionAppName = 'func-${resourcePrefix}-${uniqueSuffix}'
var appServicePlanName = 'plan-${resourcePrefix}-${uniqueSuffix}'
var applicationInsightsName = 'appi-${resourcePrefix}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-${resourcePrefix}-${uniqueSuffix}'

// Common tags for all resources
var commonTags = {
  Environment: environment
  Application: 'QuoteGenerator'
  ManagedBy: 'Bicep'
  Purpose: 'Recipe'
  Recipe: 'simple-daily-quote-generator-functions-storage'
}

// Log Analytics Workspace (required for Application Insights)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableApplicationInsights) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: commonTags
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
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
  location: location
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for Function App and Table Storage
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
    encryption: {
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
  }
}

// Table Service for storing quotes
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

// Quotes Table
resource quotesTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'quotes'
  properties: {}
}

// App Service Plan (Consumption plan for serverless)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: commonTags
  sku: {
    name: functionAppPlanSku
    tier: 'Dynamic'
  }
  kind: 'functionapp'
  properties: {
    computeMode: 'Dynamic'
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: commonTags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: '${upper(functionAppRuntime)}|${functionAppRuntimeVersion}'
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
          value: functionAppRuntime
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
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
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
  }
  dependsOn: [
    quotesTable
  ]
}

// Application Insights configuration for Function App
resource functionAppInsights 'Microsoft.Web/sites/config@2023-12-01' = if (enableApplicationInsights) {
  parent: functionApp
  name: 'appsettings'
  properties: {
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    WEBSITE_CONTENTSHARE: toLower(functionAppName)
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: functionAppRuntime
    WEBSITE_RUN_FROM_PACKAGE: '1'
    APPINSIGHTS_INSTRUMENTATIONKEY: enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''
    APPLICATIONINSIGHTS_CONNECTION_STRING: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
    ApplicationInsightsAgent_EXTENSION_VERSION: '~3'
    XDT_MicrosoftApplicationInsights_Mode: 'Recommended'
  }
}

// Deployment script to populate Table Storage with sample quotes
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'populate-quotes-table'
  location: location
  tags: commonTags
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.55.0'
    timeout: 'PT10M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'STORAGE_ACCOUNT_NAME'
        value: storageAccount.name
      }
      {
        name: 'STORAGE_ACCOUNT_KEY'
        secureValue: storageAccount.listKeys().keys[0].value
      }
      {
        name: 'TABLE_NAME'
        value: 'quotes'
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e
      
      echo "Populating quotes table with sample data..."
      
      # Sample quotes data
      quotes='[
        {
          "PartitionKey": "inspiration",
          "RowKey": "001",
          "quote": "The only way to do great work is to love what you do.",
          "author": "Steve Jobs",
          "category": "motivation"
        },
        {
          "PartitionKey": "inspiration",
          "RowKey": "002",
          "quote": "Innovation distinguishes between a leader and a follower.",
          "author": "Steve Jobs",
          "category": "innovation"
        },
        {
          "PartitionKey": "inspiration",
          "RowKey": "003",
          "quote": "Success is not final, failure is not fatal.",
          "author": "Winston Churchill",
          "category": "perseverance"
        },
        {
          "PartitionKey": "inspiration",
          "RowKey": "004",
          "quote": "The future belongs to those who believe in the beauty of their dreams.",
          "author": "Eleanor Roosevelt",
          "category": "dreams"
        },
        {
          "PartitionKey": "inspiration",
          "RowKey": "005",
          "quote": "It is during our darkest moments that we must focus to see the light.",
          "author": "Aristotle",
          "category": "hope"
        }
      ]'
      
      # Insert each quote into the table
      echo "$quotes" | jq -c '.[]' | while read -r quote; do
        partitionKey=$(echo "$quote" | jq -r '.PartitionKey')
        rowKey=$(echo "$quote" | jq -r '.RowKey')
        quoteText=$(echo "$quote" | jq -r '.quote')
        author=$(echo "$quote" | jq -r '.author')
        category=$(echo "$quote" | jq -r '.category')
        
        echo "Inserting quote $rowKey..."
        az storage entity insert \
          --account-name "$STORAGE_ACCOUNT_NAME" \
          --account-key "$STORAGE_ACCOUNT_KEY" \
          --table-name "$TABLE_NAME" \
          --entity PartitionKey="$partitionKey" RowKey="$rowKey" quote="$quoteText" author="$author" category="$category"
      done
      
      echo "Successfully populated quotes table with sample data"
    '''
  }
  dependsOn: [
    quotesTable
  ]
}

// Outputs
@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Storage Account connection string')
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Function App default hostname')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('Quotes Table name')
output quotesTableName string = quotesTable.name

@description('App Service Plan name')
output appServicePlanName string = appServicePlan.name

@description('API endpoint for quote retrieval (example function name)')
output apiEndpointExample string = 'https://${functionApp.properties.defaultHostName}/api/quote-function'

@description('Resource tags applied to all resources')
output resourceTags object = commonTags

@description('Environment configuration summary')
output environmentSummary object = {
  environment: environment
  location: location
  appName: appName
  uniqueSuffix: uniqueSuffix
  storageAccountSku: storageAccountSku
  functionAppRuntime: functionAppRuntime
  functionAppRuntimeVersion: functionAppRuntimeVersion
  applicationInsightsEnabled: enableApplicationInsights
}