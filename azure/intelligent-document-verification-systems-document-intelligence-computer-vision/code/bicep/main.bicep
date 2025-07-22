// Azure Document Verification System - Main Bicep Template
// This template deploys a complete intelligent document verification system
// using Azure Document Intelligence and Computer Vision services

@description('The name of the environment (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Location for all resources')
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
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
@maxLength(6)
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: 'DocumentVerification'
  Owner: 'ITOps'
  CostCenter: 'AI-ML'
}

@description('Storage account configuration')
param storageConfig object = {
  sku: 'Standard_LRS'
  kind: 'StorageV2'
  accessTier: 'Hot'
  httpsOnly: true
  minimumTlsVersion: 'TLS1_2'
  supportsHttpsTrafficOnly: true
}

@description('Document Intelligence service configuration')
param documentIntelligenceConfig object = {
  sku: 'S0'
  kind: 'FormRecognizer'
  enableCustomDomain: true
  disableLocalAuth: false
}

@description('Computer Vision service configuration')
param computerVisionConfig object = {
  sku: 'S1'
  kind: 'ComputerVision'
  enableCustomDomain: true
  disableLocalAuth: false
}

@description('Function App configuration')
param functionAppConfig object = {
  alwaysOn: false
  use32BitWorkerProcess: false
  pythonVersion: '3.11'
  functionsVersion: '~4'
  enableApplicationInsights: true
}

@description('Cosmos DB configuration')
param cosmosDbConfig object = {
  consistencyLevel: 'Session'
  enableFreeTier: false
  enableAutomaticFailover: true
  databaseName: 'DocumentVerification'
  containerName: 'VerificationResults'
  partitionKey: '/documentId'
  throughput: 400
}

@description('API Management configuration')
param apiManagementConfig object = {
  sku: 'Developer'
  capacity: 1
  publisherName: 'Document Verification System'
  publisherEmail: 'admin@company.com'
}

@description('Logic App configuration')
param logicAppConfig object = {
  integrationServiceEnvironmentId: ''
  state: 'Enabled'
}

// Variables
var resourcePrefix = 'docverify'
var storageAccountName = '${resourcePrefix}st${resourceSuffix}'
var documentIntelligenceName = '${resourcePrefix}-docintel-${resourceSuffix}'
var computerVisionName = '${resourcePrefix}-vision-${resourceSuffix}'
var functionAppName = '${resourcePrefix}-func-${resourceSuffix}'
var appServicePlanName = '${resourcePrefix}-asp-${resourceSuffix}'
var cosmosAccountName = '${resourcePrefix}-cosmos-${resourceSuffix}'
var apiManagementName = '${resourcePrefix}-apim-${resourceSuffix}'
var logicAppName = '${resourcePrefix}-logic-${resourceSuffix}'
var applicationInsightsName = '${resourcePrefix}-appinsights-${resourceSuffix}'
var keyVaultName = '${resourcePrefix}-kv-${resourceSuffix}'
var logAnalyticsName = '${resourcePrefix}-logs-${resourceSuffix}'

// Storage Account for document processing
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageConfig.sku
  }
  kind: storageConfig.kind
  properties: {
    accessTier: storageConfig.accessTier
    supportsHttpsTrafficOnly: storageConfig.supportsHttpsTrafficOnly
    minimumTlsVersion: storageConfig.minimumTlsVersion
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
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

// Blob containers for document processing
resource incomingDocsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/incoming-docs'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Incoming documents for processing'
    }
  }
}

resource processedDocsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/processed-docs'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Processed documents with results'
    }
  }
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
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

// Key Vault for storing secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
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
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    accessPolicies: []
  }
}

// Document Intelligence Service
resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: documentIntelligenceName
  location: location
  tags: tags
  sku: {
    name: documentIntelligenceConfig.sku
  }
  kind: documentIntelligenceConfig.kind
  properties: {
    customSubDomainName: documentIntelligenceConfig.enableCustomDomain ? documentIntelligenceName : null
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: documentIntelligenceConfig.disableLocalAuth
    apiProperties: {
      statisticsEnabled: false
    }
  }
}

// Computer Vision Service
resource computerVision 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: computerVisionName
  location: location
  tags: tags
  sku: {
    name: computerVisionConfig.sku
  }
  kind: computerVisionConfig.kind
  properties: {
    customSubDomainName: computerVisionConfig.enableCustomDomain ? computerVisionName : null
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: computerVisionConfig.disableLocalAuth
    apiProperties: {
      statisticsEnabled: false
    }
  }
}

// Cosmos DB Account
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: cosmosDbConfig.enableFreeTier
    enableAutomaticFailover: cosmosDbConfig.enableAutomaticFailover
    consistencyPolicy: {
      defaultConsistencyLevel: cosmosDbConfig.consistencyLevel
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Local'
      }
    }
  }
}

// Cosmos DB Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-11-15' = {
  name: cosmosDbConfig.databaseName
  parent: cosmosAccount
  properties: {
    resource: {
      id: cosmosDbConfig.databaseName
    }
  }
}

// Cosmos DB Container
resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = {
  name: cosmosDbConfig.containerName
  parent: cosmosDatabase
  properties: {
    resource: {
      id: cosmosDbConfig.containerName
      partitionKey: {
        paths: [
          cosmosDbConfig.partitionKey
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
    }
  }
}

// App Service Plan for Functions
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
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
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'Python|${functionAppConfig.pythonVersion}'
      alwaysOn: functionAppConfig.alwaysOn
      use32BitWorkerProcess: functionAppConfig.use32BitWorkerProcess
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
          value: functionAppConfig.functionsVersion
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
          name: 'DOCUMENT_INTELLIGENCE_ENDPOINT'
          value: documentIntelligence.properties.endpoint
        }
        {
          name: 'DOCUMENT_INTELLIGENCE_KEY'
          value: documentIntelligence.listKeys().key1
        }
        {
          name: 'COMPUTER_VISION_ENDPOINT'
          value: computerVision.properties.endpoint
        }
        {
          name: 'COMPUTER_VISION_KEY'
          value: computerVision.listKeys().key1
        }
        {
          name: 'COSMOS_CONNECTION_STRING'
          value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
      ]
    }
    httpsOnly: true
  }
}

// Key Vault Secrets
resource documentIntelligenceKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'document-intelligence-key'
  parent: keyVault
  properties: {
    value: documentIntelligence.listKeys().key1
    contentType: 'text/plain'
  }
}

resource computerVisionKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'computer-vision-key'
  parent: keyVault
  properties: {
    value: computerVision.listKeys().key1
    contentType: 'text/plain'
  }
}

resource cosmosConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'cosmos-connection-string'
  parent: keyVault
  properties: {
    value: cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString
    contentType: 'text/plain'
  }
}

// API Management Service
resource apiManagement 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apiManagementName
  location: location
  tags: tags
  sku: {
    name: apiManagementConfig.sku
    capacity: apiManagementConfig.capacity
  }
  properties: {
    publisherName: apiManagementConfig.publisherName
    publisherEmail: apiManagementConfig.publisherEmail
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'False'
    }
    virtualNetworkType: 'None'
    apiVersionConstraint: {
      minApiVersion: '2019-12-01'
    }
  }
}

// Logic App
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: tags
  properties: {
    state: logicAppConfig.state
    integrationServiceEnvironment: empty(logicAppConfig.integrationServiceEnvironmentId) ? null : {
      id: logicAppConfig.integrationServiceEnvironmentId
    }
    definition: {
      '$schema': 'https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'When_a_blob_is_added_or_modified': {
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/triggers/batch/onupdatedfile'
            queries: {
              folderId: 'L2luY29taW5nLWRvY3M='
              maxFileCount: 10
            }
          }
        }
      }
      actions: {
        'Process_Document': {
          runAfter: {}
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://${functionApp.properties.defaultHostName}/api/DocumentVerificationFunction'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              document_url: '@triggerBody()?[\'Path\']'
            }
          }
        }
      }
      outputs: {}
    }
  }
}

// Outputs
output resourceGroupName string = resourceGroup().name
output storageAccountName string = storageAccount.name
output storageAccountEndpoint string = storageAccount.properties.primaryEndpoints.blob
output documentIntelligenceName string = documentIntelligence.name
output documentIntelligenceEndpoint string = documentIntelligence.properties.endpoint
output computerVisionName string = computerVision.name
output computerVisionEndpoint string = computerVision.properties.endpoint
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output cosmosAccountName string = cosmosAccount.name
output cosmosAccountEndpoint string = cosmosAccount.properties.documentEndpoint
output apiManagementName string = apiManagement.name
output apiManagementUrl string = 'https://${apiManagement.properties.gatewayUrl}'
output logicAppName string = logicApp.name
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output applicationInsightsName string = applicationInsights.name
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id