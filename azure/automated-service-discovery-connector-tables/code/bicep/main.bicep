// ================================================================================
// Azure Bicep Template for Dynamic Service Discovery with Service Connector and Azure Tables
// ================================================================================
// This template deploys a complete service discovery solution using:
// - Azure Service Connector for automated connection management
// - Azure Tables for service registry storage
// - Azure Functions for health monitoring and service registration
// - Target services (SQL Database, Redis Cache) for demonstration
// ================================================================================

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Primary region for resource deployment')
param location string = resourceGroup().location

@description('Unique suffix for resource naming')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Admin username for SQL Server')
param sqlAdminUsername string = 'sqladmin'

@description('Admin password for SQL Server')
@secure()
param sqlAdminPassword string

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Solution: 'ServiceDiscovery'
  ManagedBy: 'Bicep'
}

// ================================================================================
// Variables for consistent resource naming
// ================================================================================

var namingPrefix = 'svc-disc-${environment}'
var storageAccountName = 'stdiscovery${resourceSuffix}'
var functionAppName = '${namingPrefix}-func-${resourceSuffix}'
var appServicePlanName = '${namingPrefix}-plan-${resourceSuffix}'
var webAppName = '${namingPrefix}-app-${resourceSuffix}'
var sqlServerName = '${namingPrefix}-sql-${resourceSuffix}'
var sqlDatabaseName = 'ServiceRegistry'
var redisCacheName = '${namingPrefix}-redis-${resourceSuffix}'
var applicationInsightsName = '${namingPrefix}-ai-${resourceSuffix}'
var logAnalyticsWorkspaceName = '${namingPrefix}-law-${resourceSuffix}'

// ================================================================================
// Log Analytics Workspace for Application Insights
// ================================================================================

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

// ================================================================================
// Application Insights for monitoring and telemetry
// ================================================================================

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

// ================================================================================
// Storage Account for Azure Tables (Service Registry) and Function Apps
// ================================================================================

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

// ================================================================================
// Table Services for Service Registry
// ================================================================================

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

// Service Registry Table for storing service metadata
resource serviceRegistryTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'ServiceRegistry'
  properties: {}
}

// Health Status Table for storing service health information
resource healthStatusTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'HealthStatus'
  properties: {}
}

// ================================================================================
// App Service Plan for hosting Function App and Web App
// ================================================================================

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
  kind: 'functionapp'
}

// ================================================================================
// Function App for Service Discovery, Registration, and Health Monitoring
// ================================================================================

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
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
      linuxFxVersion: 'NODE|18'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
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
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
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
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
      ]
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
  identity: {
    type: 'SystemAssigned'
  }
}

// ================================================================================
// Web Application for Service Discovery Demo
// ================================================================================

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    isXenon: false
    hyperV: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'NODE|18-lts'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      appSettings: [
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
      ]
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: true
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ================================================================================
// Azure SQL Server and Database for demonstration
// ================================================================================

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Firewall rule to allow Azure services access
resource sqlServerFirewallRuleAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// SQL Database for service registry demonstration
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 104857600 // 100 MB
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'
    isLedgerOn: false
  }
}

// ================================================================================
// Azure Cache for Redis for demonstration
// ================================================================================

resource redisCache 'Microsoft.Cache/redis@2024-03-01' = {
  name: redisCacheName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'Basic'
      family: 'C'
      capacity: 0
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    redisConfiguration: {
      'maxmemory-reserved': '2'
      'maxfragmentationmemory-reserved': '12'
      'maxmemory-delta': '2'
    }
  }
}

// ================================================================================
// Service Connector Resources
// ================================================================================

// Service Connector: Function App to Storage Tables
resource serviceConnectorFunctionStorage 'Microsoft.ServiceLinker/linkers@2024-04-01' = {
  scope: functionApp
  name: 'StorageConnection'
  properties: {
    targetService: {
      type: 'AzureResource'
      id: storageAccount.id
    }
    authInfo: {
      authType: 'accessKey'
    }
    clientType: 'nodejs'
    configurationInfo: {
      additionalConfigurations: {
        AZURE_STORAGE_ACCOUNT_NAME: storageAccount.name
        AZURE_STORAGE_TABLE_ENDPOINT: storageAccount.properties.primaryEndpoints.table
      }
    }
  }
}

// Service Connector: Web App to Storage Tables
resource serviceConnectorWebAppStorage 'Microsoft.ServiceLinker/linkers@2024-04-01' = {
  scope: webApp
  name: 'ServiceRegistryConnection'
  properties: {
    targetService: {
      type: 'AzureResource'
      id: storageAccount.id
    }
    authInfo: {
      authType: 'accessKey'
    }
    clientType: 'nodejs'
    configurationInfo: {
      additionalConfigurations: {
        AZURE_STORAGE_ACCOUNT_NAME: storageAccount.name
        AZURE_STORAGE_TABLE_ENDPOINT: storageAccount.properties.primaryEndpoints.table
      }
    }
  }
}

// Service Connector: Web App to SQL Database
resource serviceConnectorWebAppSQL 'Microsoft.ServiceLinker/linkers@2024-04-01' = {
  scope: webApp
  name: 'DatabaseConnection'
  properties: {
    targetService: {
      type: 'AzureResource'
      id: sqlDatabase.id
    }
    authInfo: {
      authType: 'sqlAuth'
      userName: sqlAdminUsername
      password: sqlAdminPassword
    }
    clientType: 'nodejs'
    configurationInfo: {
      additionalConfigurations: {
        AZURE_SQL_SERVER: sqlServer.properties.fullyQualifiedDomainName
        AZURE_SQL_DATABASE: sqlDatabaseName
      }
    }
  }
}

// Service Connector: Web App to Redis Cache
resource serviceConnectorWebAppRedis 'Microsoft.ServiceLinker/linkers@2024-04-01' = {
  scope: webApp
  name: 'CacheConnection'
  properties: {
    targetService: {
      type: 'AzureResource'
      id: redisCache.id
    }
    authInfo: {
      authType: 'accessKey'
    }
    clientType: 'nodejs'
    configurationInfo: {
      additionalConfigurations: {
        AZURE_REDIS_HOSTNAME: redisCache.properties.hostName
        AZURE_REDIS_PORT: '6380'
        AZURE_REDIS_SSL: 'true'
      }
    }
  }
}

// ================================================================================
// Role Assignments for Managed Identities
// ================================================================================

// Storage Account Contributor role for Function App
resource functionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionApp.id, 'StorageAccountContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab') // Storage Account Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Account Contributor role for Web App
resource webAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, webApp.id, 'StorageAccountContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab') // Storage Account Contributor
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ================================================================================
// Outputs for verification and integration
// ================================================================================

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Storage Account name for service registry')
output storageAccountName string = storageAccount.name

@description('Storage Account connection string')
@secure()
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('Function App name for service discovery APIs')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Web App name for service discovery demo')
output webAppName string = webApp.name

@description('Web App URL')
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'

@description('SQL Server name')
output sqlServerName string = sqlServer.name

@description('SQL Server FQDN')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('SQL Database name')
output sqlDatabaseName string = sqlDatabase.name

@description('Redis Cache name')
output redisCacheName string = redisCache.name

@description('Redis Cache hostname')
output redisCacheHostname string = redisCache.properties.hostName

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights Connection String')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Service Registry Table name')
output serviceRegistryTableName string = serviceRegistryTable.name

@description('Health Status Table name')
output healthStatusTableName string = healthStatusTable.name

@description('Service Connector resource IDs')
output serviceConnectors object = {
  functionStorage: serviceConnectorFunctionStorage.id
  webAppStorage: serviceConnectorWebAppStorage.id
  webAppSQL: serviceConnectorWebAppSQL.id
  webAppRedis: serviceConnectorWebAppRedis.id
}

@description('Deployment summary with key endpoints')
output deploymentSummary object = {
  serviceDiscoveryApi: 'https://${functionApp.properties.defaultHostName}/api/ServiceDiscovery'
  serviceRegistrationApi: 'https://${functionApp.properties.defaultHostName}/api/ServiceRegistrar'
  webAppDemo: 'https://${webApp.properties.defaultHostName}'
  storageAccount: storageAccount.name
  tablesEndpoint: storageAccount.properties.primaryEndpoints.table
}