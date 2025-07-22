@description('Main Bicep template for Intelligent Document Analysis with Hybrid Search')
@description('Deploys Azure OpenAI Service, PostgreSQL, AI Search, and Functions for document analysis')

// Parameters
@description('Environment suffix for resource naming')
@minLength(3)
@maxLength(6)
param environmentSuffix string = 'dev'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Administrator username for PostgreSQL')
param postgresAdminUsername string = 'adminuser'

@description('Administrator password for PostgreSQL')
@minLength(8)
@maxLength(128)
@secure()
param postgresAdminPassword string

@description('SKU for Azure OpenAI Service')
@allowed(['S0'])
param openAiSku string = 'S0'

@description('SKU for Azure AI Search service')
@allowed(['basic', 'standard', 'standard2', 'standard3'])
param searchServiceSku string = 'standard'

@description('SKU for PostgreSQL server')
@allowed(['Standard_B1ms', 'Standard_D2s_v3', 'Standard_D4s_v3'])
param postgresServerSku string = 'Standard_D2s_v3'

@description('Storage size for PostgreSQL in GB')
@minValue(32)
@maxValue(16384)
param postgresStorageSize int = 128

@description('Azure Functions consumption plan location')
param functionAppLocation string = location

@description('Tags to apply to all resources')
param tags object = {
  environment: environmentSuffix
  solution: 'document-analysis'
  managedBy: 'bicep'
}

// Variables
var uniqueSuffix = take(uniqueString(resourceGroup().id), 6)
var namingPrefix = 'doc-analysis-${environmentSuffix}-${uniqueSuffix}'

var openAiAccountName = 'openai-${namingPrefix}'
var postgresServerName = 'postgres-${namingPrefix}'
var searchServiceName = 'search-${namingPrefix}'
var functionAppName = 'func-${namingPrefix}'
var storageAccountName = 'storage${replace(namingPrefix, '-', '')}'
var applicationInsightsName = 'ai-${namingPrefix}'
var logAnalyticsWorkspaceName = 'log-${namingPrefix}'

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
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
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

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Azure OpenAI Service
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAiAccountName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: openAiSku
  }
  properties: {
    customSubDomainName: openAiAccountName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Text Embedding Model Deployment
resource textEmbeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAiAccount
  name: 'text-embedding-ada-002'
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-ada-002'
      version: '2'
    }
    scaleSettings: {
      scaleType: 'Standard'
      capacity: 10
    }
  }
}

// PostgreSQL Flexible Server
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: postgresServerName
  location: location
  tags: tags
  sku: {
    name: postgresServerSku
    tier: 'GeneralPurpose'
  }
  properties: {
    administratorLogin: postgresAdminUsername
    administratorLoginPassword: postgresAdminPassword
    version: '14'
    storage: {
      storageSizeGB: postgresStorageSize
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      delegatedSubnetResourceId: null
      privateDnsZoneArmResourceId: null
    }
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
  }
}

// PostgreSQL Configuration for pgvector
resource postgresConfig 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-06-01-preview' = {
  parent: postgresServer
  name: 'shared_preload_libraries'
  properties: {
    value: 'vector'
    source: 'user-override'
  }
}

// PostgreSQL Firewall Rule - Allow Azure Services
resource postgresFirewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-06-01-preview' = {
  parent: postgresServer
  name: 'allow-azure-services'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Azure AI Search Service
resource searchService 'Microsoft.Search/searchServices@2023-11-01' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: {
    name: searchServiceSku
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'Default'
    publicNetworkAccess: 'Enabled'
    networkRuleSet: {
      ipRules: []
    }
    disableLocalAuth: false
    authOptions: {
      apiKeyOnly: {}
    }
  }
}

// Function App Service Plan (Consumption)
resource functionAppServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${functionAppName}-plan'
  location: functionAppLocation
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
  }
  properties: {
    reserved: true
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: functionAppLocation
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: functionAppServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
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
          name: 'OPENAI_ENDPOINT'
          value: openAiAccount.properties.endpoint
        }
        {
          name: 'OPENAI_KEY'
          value: openAiAccount.listKeys().key1
        }
        {
          name: 'POSTGRES_HOST'
          value: postgresServer.properties.fullyQualifiedDomainName
        }
        {
          name: 'POSTGRES_USER'
          value: postgresAdminUsername
        }
        {
          name: 'POSTGRES_PASSWORD'
          value: postgresAdminPassword
        }
        {
          name: 'POSTGRES_DATABASE'
          value: 'postgres'
        }
        {
          name: 'SEARCH_ENDPOINT'
          value: 'https://${searchService.name}.search.windows.net'
        }
        {
          name: 'SEARCH_KEY'
          value: searchService.listAdminKeys().primaryKey
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
      minTlsVersion: '1.2'
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

// Outputs
@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Azure OpenAI Service name')
output openAiAccountName string = openAiAccount.name

@description('Azure OpenAI Service endpoint')
output openAiEndpoint string = openAiAccount.properties.endpoint

@description('Azure OpenAI Service key')
@secure()
output openAiKey string = openAiAccount.listKeys().key1

@description('PostgreSQL server name')
output postgresServerName string = postgresServer.name

@description('PostgreSQL server FQDN')
output postgresServerFqdn string = postgresServer.properties.fullyQualifiedDomainName

@description('PostgreSQL connection string')
@secure()
output postgresConnectionString string = 'host=${postgresServer.properties.fullyQualifiedDomainName} port=5432 dbname=postgres user=${postgresAdminUsername} password=${postgresAdminPassword} sslmode=require'

@description('Azure AI Search service name')
output searchServiceName string = searchService.name

@description('Azure AI Search service endpoint')
output searchServiceEndpoint string = 'https://${searchService.name}.search.windows.net'

@description('Azure AI Search service key')
@secure()
output searchServiceKey string = searchService.listAdminKeys().primaryKey

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Deployment summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  environmentSuffix: environmentSuffix
  openAiService: openAiAccount.name
  postgresServer: postgresServer.name
  searchService: searchService.name
  functionApp: functionApp.name
  storageAccount: storageAccount.name
  estimatedMonthlyCost: 'Varies by usage - Monitor through Azure Cost Management'
}