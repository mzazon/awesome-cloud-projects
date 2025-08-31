// ========================================
// Business Intelligence Query Assistant with Azure OpenAI and SQL Database
// ========================================
// This Bicep template deploys a complete business intelligence query assistant solution
// that converts natural language questions into SQL queries using Azure OpenAI Service
// and executes them against Azure SQL Database through serverless Azure Functions.

@description('The Azure region where all resources will be deployed')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'westeurope'
  'northeurope'
  'southeastasia'
  'japaneast'
  'australiaeast'
  'uksouth'
  'canadacentral'
  'francecentral'
])
param location string = resourceGroup().location

@description('Environment type for resource naming and configuration')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environmentType string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
@minLength(3)
@maxLength(6)
param resourceSuffix string

@description('Administrator username for the SQL Server')
@minLength(4)
@maxLength(20)
param sqlAdminUsername string = 'sqladmin'

@description('Administrator password for the SQL Server')
@minLength(12)
@maxLength(128)
@secure()
param sqlAdminPassword string

@description('SKU for the SQL Database')
@allowed([
  'Basic'
  'S0'
  'S1'
  'S2'
  'S3'
])
param sqlDatabaseSku string = 'Basic'

@description('Runtime for the Function App')
@allowed([
  'node'
  'dotnet'
  'python'
])
param functionAppRuntime string = 'node'

@description('Runtime version for the Function App')
param functionAppRuntimeVersion string = '18'

@description('OpenAI model deployment name')
param openAiModelDeploymentName string = 'gpt-4o'

@description('OpenAI model version')
param openAiModelVersion string = '2024-11-20'

@description('OpenAI deployment capacity (TPM in thousands)')
@minValue(1)
@maxValue(50)
param openAiDeploymentCapacity int = 10

@description('Tags to be applied to all resources')
param tags object = {
  Environment: environmentType
  Project: 'BI-Query-Assistant'
  ManagedBy: 'Bicep'
  Purpose: 'BusinessIntelligence'
}

// ========================================
// Variables
// ========================================

var naming = {
  openAiService: 'openai-bi-${resourceSuffix}'
  sqlServer: 'sql-bi-server-${resourceSuffix}'
  sqlDatabase: 'BiAnalyticsDB'
  functionApp: 'func-bi-assistant-${resourceSuffix}'
  storageAccount: 'stbi${resourceSuffix}'
  appInsights: 'ai-bi-${resourceSuffix}'
  logAnalytics: 'law-bi-${resourceSuffix}'
  hostingPlan: 'plan-bi-${resourceSuffix}'
  managedIdentity: 'id-bi-${resourceSuffix}'
  keyVault: 'kv-bi-${resourceSuffix}'
}

// Built-in role definition IDs for Azure RBAC
var roleDefinitions = {
  contributor: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  sqlDbContributor: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9b7fa17d-e63e-47b0-bb0a-15c516ac86ec')
  cognitiveServicesUser: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
  keyVaultSecretsUser: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
}

// ========================================
// User-Assigned Managed Identity
// ========================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: naming.managedIdentity
  location: location
  tags: tags
}

// ========================================
// Azure OpenAI Service
// ========================================

resource openAiService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: naming.openAiService
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: naming.openAiService
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Deploy GPT-4o model for natural language to SQL conversion
resource openAiModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAiService
  name: openAiModelDeploymentName
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: openAiModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'Standard'
    capacity: openAiDeploymentCapacity
  }
}

// ========================================
// Azure SQL Server and Database
// ========================================

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: naming.sqlServer
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Allow Azure services to access the SQL Server
resource sqlFirewallRule 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Create the business intelligence database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: naming.sqlDatabase
  location: location
  tags: tags
  sku: {
    name: sqlDatabaseSku
    tier: sqlDatabaseSku == 'Basic' ? 'Basic' : 'Standard'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 1073741824 // 1GB
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    requestedBackupStorageRedundancy: 'Local'
  }
}

// ========================================
// Storage Account for Function App
// ========================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: naming.storageAccount
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// ========================================
// Log Analytics Workspace and Application Insights
// ========================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: naming.logAnalytics
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
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: naming.appInsights
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

// ========================================
// Key Vault for Secrets Management
// ========================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: naming.keyVault
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    accessPolicies: []
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Store OpenAI key in Key Vault
resource openAiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'OpenAI-API-Key'
  properties: {
    value: openAiService.listKeys().key1
    attributes: {
      enabled: true
    }
  }
}

// Store SQL connection string in Key Vault
resource sqlConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'SQL-Connection-String'
  properties: {
    value: 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${naming.sqlDatabase};User ID=${sqlAdminUsername};Password=${sqlAdminPassword};Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;'
    attributes: {
      enabled: true
    }
  }
}

// ========================================
// App Service Plan for Function App
// ========================================

resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: naming.hostingPlan
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
    reserved: false
  }
}

// ========================================
// Function App
// ========================================

resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: naming.functionApp
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(naming.functionApp)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~${functionAppRuntimeVersion}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionAppRuntime
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
          name: 'AZURE_OPENAI_ENDPOINT'
          value: openAiService.properties.endpoint
        }
        {
          name: 'AZURE_OPENAI_KEY'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=OpenAI-API-Key)'
        }
        {
          name: 'AZURE_OPENAI_DEPLOYMENT'
          value: openAiModelDeploymentName
        }
        {
          name: 'SQL_CONNECTION_STRING'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=SQL-Connection-String)'
        }
      ]
      functionAppScaleLimit: 10
      minimumElasticInstanceCount: 0
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      netFrameworkVersion: 'v6.0'
    }
    httpsOnly: true
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  dependsOn: [
    openAiKeySecret
    sqlConnectionStringSecret
  ]
}

// ========================================
// Role Assignments for Managed Identity
// ========================================

// Grant the managed identity access to OpenAI Service
resource openAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiService.id, managedIdentity.id, roleDefinitions.cognitiveServicesUser)
  scope: openAiService
  properties: {
    roleDefinitionId: roleDefinitions.cognitiveServicesUser
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant the managed identity access to SQL Database
resource sqlRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sqlServer.id, managedIdentity.id, roleDefinitions.sqlDbContributor)
  scope: sqlServer
  properties: {
    roleDefinitionId: roleDefinitions.sqlDbContributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant the managed identity access to Key Vault secrets
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentity.id, roleDefinitions.keyVaultSecretsUser)
  scope: keyVault
  properties: {
    roleDefinitionId: roleDefinitions.keyVaultSecretsUser
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Enable system-assigned managed identity for the Function App and grant Key Vault access
resource functionAppSystemIdentity 'Microsoft.Web/sites@2023-01-01' existing = {
  name: naming.functionApp
}

resource functionAppKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.identity.principalId, roleDefinitions.keyVaultSecretsUser)
  scope: keyVault
  properties: {
    roleDefinitionId: roleDefinitions.keyVaultSecretsUser
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ========================================
// Outputs
// ========================================

@description('The resource group name where all resources are deployed')
output resourceGroupName string = resourceGroup().name

@description('The Azure region where resources are deployed')
output location string = location

@description('The name of the Azure OpenAI Service')
output openAiServiceName string = openAiService.name

@description('The endpoint URL for the Azure OpenAI Service')
output openAiEndpoint string = openAiService.properties.endpoint

@description('The name of the deployed OpenAI model')
output openAiModelDeploymentName string = openAiModelDeployment.name

@description('The name of the SQL Server')
output sqlServerName string = sqlServer.name

@description('The fully qualified domain name of the SQL Server')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('The name of the SQL Database')
output sqlDatabaseName string = sqlDatabase.name

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The Function App URL for testing the query processor')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}/api/QueryProcessor'

@description('The name of the storage account used by the Function App')
output storageAccountName string = storageAccount.name

@description('The name of the Application Insights instance')
output applicationInsightsName string = applicationInsights.name

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The name of the Key Vault containing secrets')
output keyVaultName string = keyVault.name

@description('The URI of the Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The name of the user-assigned managed identity')
output managedIdentityName string = managedIdentity.name

@description('The principal ID of the user-assigned managed identity')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Sample natural language queries to test the system')
output sampleQueries array = [
  'Show me total revenue by country for all customers'
  'Which customers have the highest order values?'
  'What is the average order amount by customer?'
  'List all completed orders from the last month'
  'Show me customers with revenue above $200,000'
]

@description('SQL connection string for manual database setup (for development use only)')
output sqlConnectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${naming.sqlDatabase};User ID=${sqlAdminUsername};Password=***;Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;'

@description('Estimated monthly cost breakdown in USD (based on basic tier usage)')
output estimatedMonthlyCost object = {
  openAiService: '$${(openAiDeploymentCapacity * 0.002 * 30 * 24)}'
  sqlDatabase: sqlDatabaseSku == 'Basic' ? '$5' : '$15+'  
  functionApp: '$0 (consumption tier free tier)'
  storage: '$1-2'
  applicationInsights: '$2-5'
  keyVault: '$1'
  total: '$10-30 per month'
  note: 'Actual costs depend on usage patterns and query volume'
}