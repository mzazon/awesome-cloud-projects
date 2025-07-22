// ====================================================================================================
// Azure Web Application Performance Optimization with Redis Cache and CDN
// ====================================================================================================
// This template deploys a complete web application performance optimization solution including:
// - Azure App Service with App Service Plan
// - Azure Cache for Redis (Standard tier)
// - Azure CDN Profile and Endpoint
// - Azure Database for PostgreSQL Flexible Server
// - Application Insights for monitoring
// - Diagnostic settings and logging
// ====================================================================================================

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environmentName string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Administrator username for PostgreSQL server')
param dbAdminUsername string = 'dbadmin'

@description('Administrator password for PostgreSQL server')
@secure()
param dbAdminPassword string

@description('App Service Plan SKU')
@allowed(['S1', 'S2', 'S3', 'P1v2', 'P2v2', 'P3v2'])
param appServicePlanSku string = 'S1'

@description('Redis Cache SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param redisCacheSku string = 'Standard'

@description('Redis Cache VM size')
@allowed(['C0', 'C1', 'C2', 'C3', 'C4', 'C5', 'C6'])
param redisCacheVmSize string = 'C1'

@description('CDN Profile SKU')
@allowed(['Standard_Microsoft', 'Standard_Akamai', 'Standard_Verizon', 'Premium_Verizon'])
param cdnProfileSku string = 'Standard_Microsoft'

@description('PostgreSQL server SKU')
param postgresqlSku string = 'Standard_B1ms'

@description('PostgreSQL storage size in GB')
@minValue(32)
@maxValue(16384)
param postgresqlStorageSize int = 32

@description('PostgreSQL version')
@allowed(['11', '12', '13', '14', '15'])
param postgresqlVersion string = '13'

@description('Common tags for all resources')
param tags object = {
  Environment: environmentName
  Project: 'webapp-performance-optimization'
  Purpose: 'performance-demo'
  ManagedBy: 'bicep'
}

// ====================================================================================================
// Variables
// ====================================================================================================

var resourceNames = {
  appServicePlan: 'asp-webapp-${uniqueSuffix}'
  webApp: 'webapp-${uniqueSuffix}'
  redisCache: 'cache-${uniqueSuffix}'
  cdnProfile: 'cdn-profile-${uniqueSuffix}'
  cdnEndpoint: 'cdn-${uniqueSuffix}'
  postgresqlServer: 'db-server-${uniqueSuffix}'
  applicationInsights: 'ai-webapp-${uniqueSuffix}'
  logAnalyticsWorkspace: 'log-webapp-${uniqueSuffix}'
}

var databaseName = 'ecommerce_db'
var redisPort = 6380
var redisSslEnabled = true

// ====================================================================================================
// Log Analytics Workspace
// ====================================================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
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
    }
  }
}

// ====================================================================================================
// Application Insights
// ====================================================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
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

// ====================================================================================================
// Azure Cache for Redis
// ====================================================================================================

resource redisCache 'Microsoft.Cache/redis@2023-08-01' = {
  name: resourceNames.redisCache
  location: location
  tags: tags
  properties: {
    sku: {
      name: redisCacheSku
      family: redisCacheSku == 'Premium' ? 'P' : 'C'
      capacity: redisCacheVmSize == 'C0' ? 0 : int(substring(redisCacheVmSize, 1, 1))
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
      'maxmemory-reserved': redisCacheSku == 'Premium' ? '200' : '50'
      'maxfragmentationmemory-reserved': redisCacheSku == 'Premium' ? '200' : '50'
    }
    redisVersion: '6'
    publicNetworkAccess: 'Enabled'
  }
}

// ====================================================================================================
// PostgreSQL Flexible Server
// ====================================================================================================

resource postgresqlServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: resourceNames.postgresqlServer
  location: location
  tags: tags
  sku: {
    name: postgresqlSku
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: dbAdminUsername
    administratorLoginPassword: dbAdminPassword
    version: postgresqlVersion
    storage: {
      storageSizeGB: postgresqlStorageSize
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    maintenanceWindow: {
      customWindow: 'Disabled'
    }
    replicationRole: 'Primary'
  }
}

// Create database within PostgreSQL server
resource postgresqlDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = {
  parent: postgresqlServer
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.UTF8'
  }
}

// Configure firewall rule to allow Azure services
resource postgresqlFirewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-06-01-preview' = {
  parent: postgresqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ====================================================================================================
// App Service Plan
// ====================================================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: resourceNames.appServicePlan
  location: location
  tags: tags
  kind: 'linux'
  properties: {
    reserved: true
    targetWorkerCount: 1
    targetWorkerSizeId: 0
  }
  sku: {
    name: appServicePlanSku
    tier: startsWith(appServicePlanSku, 'S') ? 'Standard' : 'PremiumV2'
    size: appServicePlanSku
    family: startsWith(appServicePlanSku, 'S') ? 'S' : 'Pv2'
    capacity: 1
  }
}

// ====================================================================================================
// Web App
// ====================================================================================================

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: resourceNames.webApp
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'NODE|18-lts'
      alwaysOn: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      use32BitWorkerProcess: false
      webSocketsEnabled: false
      managedPipelineMode: 'Integrated'
      remoteDebuggingEnabled: false
      httpLoggingEnabled: true
      detailedErrorLoggingEnabled: true
      requestTracingEnabled: true
      appSettings: [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'REDIS_HOSTNAME'
          value: redisCache.properties.hostName
        }
        {
          name: 'REDIS_KEY'
          value: redisCache.listKeys().primaryKey
        }
        {
          name: 'REDIS_PORT'
          value: string(redisPort)
        }
        {
          name: 'REDIS_SSL'
          value: string(redisSslEnabled)
        }
        {
          name: 'DATABASE_URL'
          value: 'postgresql://${dbAdminUsername}:${dbAdminPassword}@${postgresqlServer.properties.fullyQualifiedDomainName}:5432/${databaseName}'
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
          name: 'NODE_ENV'
          value: environmentName
        }
      ]
    }
    httpsOnly: true
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

// ====================================================================================================
// Web App Diagnostic Settings
// ====================================================================================================

resource webAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'webAppDiagnostics'
  scope: webApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// ====================================================================================================
// CDN Profile
// ====================================================================================================

resource cdnProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: resourceNames.cdnProfile
  location: 'Global'
  tags: tags
  sku: {
    name: cdnProfileSku
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

// ====================================================================================================
// CDN Endpoint
// ====================================================================================================

resource cdnEndpoint 'Microsoft.Cdn/profiles/endpoints@2023-05-01' = {
  parent: cdnProfile
  name: resourceNames.cdnEndpoint
  location: 'Global'
  tags: tags
  properties: {
    originHostHeader: webApp.properties.defaultHostName
    isHttpAllowed: false
    isHttpsAllowed: true
    queryStringCachingBehavior: 'IgnoreQueryString'
    isCompressionEnabled: true
    contentTypesToCompress: [
      'text/plain'
      'text/html'
      'text/css'
      'text/javascript'
      'application/x-javascript'
      'application/javascript'
      'application/json'
      'application/xml'
      'image/svg+xml'
    ]
    origins: [
      {
        name: 'webapp-origin'
        properties: {
          hostName: webApp.properties.defaultHostName
          httpPort: 80
          httpsPort: 443
          originHostHeader: webApp.properties.defaultHostName
          priority: 1
          weight: 1000
          enabled: true
        }
      }
    ]
    deliveryPolicy: {
      rules: [
        {
          name: 'StaticAssets'
          order: 1
          conditions: [
            {
              name: 'UrlPath'
              parameters: {
                '@odata.type': '#Microsoft.Azure.Cdn.Models.DeliveryRuleUrlPathMatchConditionParameters'
                operator: 'BeginsWith'
                negateCondition: false
                matchValues: [
                  '/static/'
                  '/images/'
                  '/css/'
                  '/js/'
                ]
                transforms: []
              }
            }
          ]
          actions: [
            {
              name: 'CacheExpiration'
              parameters: {
                '@odata.type': '#Microsoft.Azure.Cdn.Models.DeliveryRuleCacheExpirationActionParameters'
                cacheBehavior: 'Override'
                cacheType: 'All'
                cacheDuration: '30.00:00:00'
              }
            }
          ]
        }
        {
          name: 'ApiEndpoints'
          order: 2
          conditions: [
            {
              name: 'UrlPath'
              parameters: {
                '@odata.type': '#Microsoft.Azure.Cdn.Models.DeliveryRuleUrlPathMatchConditionParameters'
                operator: 'BeginsWith'
                negateCondition: false
                matchValues: [
                  '/api/'
                ]
                transforms: []
              }
            }
          ]
          actions: [
            {
              name: 'CacheExpiration'
              parameters: {
                '@odata.type': '#Microsoft.Azure.Cdn.Models.DeliveryRuleCacheExpirationActionParameters'
                cacheBehavior: 'Override'
                cacheType: 'All'
                cacheDuration: '0.00:05:00'
              }
            }
          ]
        }
      ]
    }
    optimizationType: 'GeneralWebDelivery'
  }
}

// ====================================================================================================
// Redis Cache Diagnostic Settings
// ====================================================================================================

resource redisDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'redisDiagnostics'
  scope: redisCache
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ConnectedClientList'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// ====================================================================================================
// PostgreSQL Diagnostic Settings
// ====================================================================================================

resource postgresqlDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'postgresqlDiagnostics'
  scope: postgresqlServer
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'PostgreSQLLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// ====================================================================================================
// Outputs
// ====================================================================================================

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Web App Name')
output webAppName string = webApp.name

@description('Web App Default Hostname')
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'

@description('CDN Endpoint Hostname')
output cdnEndpointUrl string = 'https://${cdnEndpoint.properties.hostName}'

@description('Redis Cache Hostname')
output redisCacheHostname string = redisCache.properties.hostName

@description('Redis Cache Primary Key')
@secure()
output redisCachePrimaryKey string = redisCache.listKeys().primaryKey

@description('Redis Cache Port')
output redisCachePort int = redisPort

@description('Redis Cache SSL Enabled')
output redisCacheSslEnabled bool = redisSslEnabled

@description('PostgreSQL Server FQDN')
output postgresqlServerFqdn string = postgresqlServer.properties.fullyQualifiedDomainName

@description('PostgreSQL Database Name')
output postgresqlDatabaseName string = databaseName

@description('Application Insights Instrumentation Key')
@secure()
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights Connection String')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Deployment Information')
output deploymentInfo object = {
  environmentName: environmentName
  location: location
  uniqueSuffix: uniqueSuffix
  deploymentTimestamp: utcNow('yyyy-MM-ddTHH:mm:ssZ')
  resourceNames: resourceNames
}