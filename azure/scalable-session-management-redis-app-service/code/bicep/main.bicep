// ===================================================================================
// Infrastructure as Code: Distributed Session Management with Azure Managed Redis
// ===================================================================================
// 
// This Bicep template deploys a complete distributed session management solution
// using Azure Managed Redis and Azure App Service with enterprise-grade security,
// monitoring, and performance optimization.
//
// Architecture Components:
// - Azure Managed Redis (Memory Optimized tier)
// - Azure App Service with multiple instances
// - Virtual Network with private endpoints
// - Azure Monitor and Application Insights
// - Log Analytics workspace for centralized logging
//

// ===================================================================================
// PARAMETERS
// ===================================================================================

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Application name prefix for resource naming')
@minLength(2)
@maxLength(10)
param applicationName string

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Redis cache tier (Memory Optimized recommended for sessions)')
@allowed(['M10', 'M20', 'M30', 'M50', 'M100', 'M200', 'M500'])
param redisCacheTier string = 'M10'

@description('App Service Plan SKU for web applications')
@allowed(['B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1', 'P2', 'P3'])
param appServicePlanSku string = 'S1'

@description('Number of App Service instances for load distribution')
@minValue(2)
@maxValue(10)
param appServiceInstanceCount int = 2

@description('Redis session timeout in minutes')
@minValue(1)
@maxValue(1440)
param sessionTimeoutMinutes int = 20

@description('Enable diagnostic logging and monitoring')
param enableDiagnostics bool = true

@description('Tags to apply to all resources')
param resourceTags object = {
  Environment: environment
  Application: applicationName
  Purpose: 'session-management'
  ManagedBy: 'bicep'
}

// ===================================================================================
// VARIABLES
// ===================================================================================

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var namingPrefix = '${applicationName}-${environment}-${uniqueSuffix}'

// Resource names following Azure naming conventions
var vnetName = 'vnet-${namingPrefix}'
var redisSubnetName = 'snet-redis-${namingPrefix}'
var appServiceSubnetName = 'snet-app-${namingPrefix}'
var redisName = 'redis-${namingPrefix}'
var appServicePlanName = 'plan-${namingPrefix}'
var webAppName = 'app-${namingPrefix}'
var logAnalyticsName = 'law-${namingPrefix}'
var appInsightsName = 'ai-${namingPrefix}'
var privateEndpointName = 'pe-redis-${namingPrefix}'
var networkSecurityGroupName = 'nsg-${namingPrefix}'

// Network configuration
var vnetAddressPrefix = '10.0.0.0/16'
var redisSubnetPrefix = '10.0.1.0/24'
var appServiceSubnetPrefix = '10.0.2.0/24'

// Redis configuration mapping
var redisSkuMapping = {
  M10: { family: 'M', capacity: 10 }
  M20: { family: 'M', capacity: 20 }
  M30: { family: 'M', capacity: 30 }
  M50: { family: 'M', capacity: 50 }
  M100: { family: 'M', capacity: 100 }
  M200: { family: 'M', capacity: 200 }
  M500: { family: 'M', capacity: 500 }
}

// ===================================================================================
// NETWORK INFRASTRUCTURE
// ===================================================================================

// Network Security Group for enhanced security
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: networkSecurityGroupName
  location: location
  tags: resourceTags
  properties: {
    securityRules: [
      {
        name: 'AllowRedisOutbound'
        properties: {
          description: 'Allow outbound Redis traffic from App Service subnet'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '6380'
          sourceAddressPrefix: appServiceSubnetPrefix
          destinationAddressPrefix: redisSubnetPrefix
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowHTTPSInbound'
        properties: {
          description: 'Allow HTTPS traffic to App Service'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: appServiceSubnetPrefix
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          description: 'Deny all other inbound traffic'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4000
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Virtual Network with optimized subnets for Redis and App Service
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: redisSubnetName
        properties: {
          addressPrefix: redisSubnetPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: appServiceSubnetName
        properties: {
          addressPrefix: appServiceSubnetPrefix
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          delegations: [
            {
              name: 'Microsoft.Web/serverFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
    ]
  }
}

// ===================================================================================
// MONITORING AND LOGGING INFRASTRUCTURE
// ===================================================================================

// Log Analytics Workspace for centralized logging
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableDiagnostics) {
  name: logAnalyticsName
  location: location
  tags: resourceTags
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

// Application Insights for application performance monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableDiagnostics) {
  name: appInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableDiagnostics ? logAnalyticsWorkspace.id : null
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ===================================================================================
// REDIS CACHE INFRASTRUCTURE
// ===================================================================================

// Azure Managed Redis - Memory Optimized for session management
resource redisCache 'Microsoft.Cache/redis@2023-08-01' = {
  name: redisName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: redisSkuMapping[redisCacheTier].family
      family: redisSkuMapping[redisCacheTier].family
      capacity: redisSkuMapping[redisCacheTier].capacity
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
      'maxmemory-reserved': '50'
      'maxfragmentationmemory-reserved': '50'
    }
    redisVersion: '6'
    publicNetworkAccess: 'Disabled'
  }
}

// Private Endpoint for Redis to ensure secure communication
resource redisPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: privateEndpointName
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: '${virtualNetwork.id}/subnets/${redisSubnetName}'
    }
    privateLinkServiceConnections: [
      {
        name: 'redis-connection'
        properties: {
          privateLinkServiceId: redisCache.id
          groupIds: ['redisCache']
        }
      }
    ]
  }
}

// Private DNS Zone for Redis private endpoint resolution
resource redisPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.redis.cache.windows.net'
  location: 'global'
  tags: resourceTags
}

// Link private DNS zone to virtual network
resource redisPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: redisPrivateDnsZone
  name: '${vnetName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

// DNS record for Redis private endpoint
resource redisPrivateDnsRecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: redisPrivateDnsZone
  name: redisName
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: redisPrivateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]
      }
    ]
  }
}

// Redis diagnostic settings for comprehensive monitoring
resource redisDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'redis-diagnostics'
  scope: redisCache
  properties: {
    workspaceId: enableDiagnostics ? logAnalyticsWorkspace.id : null
    logs: [
      {
        categoryGroup: 'allLogs'
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

// ===================================================================================
// APP SERVICE INFRASTRUCTURE
// ===================================================================================

// App Service Plan with horizontal scaling capability
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: resourceTags
  sku: {
    name: appServicePlanSku
    capacity: appServiceInstanceCount
  }
  kind: 'app'
  properties: {
    reserved: false
    zoneRedundant: false
  }
}

// Web Application with Redis session management configuration
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    virtualNetworkSubnetId: '${virtualNetwork.id}/subnets/${appServiceSubnetName}'
    httpsOnly: true
    clientAffinityEnabled: false // Disable session affinity for true load balancing
    siteConfig: {
      alwaysOn: true
      http20Enabled: true
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'FtpsOnly'
      netFrameworkVersion: 'v8.0'
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableDiagnostics ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableDiagnostics ? applicationInsights.properties.ConnectionString : ''
        }
        {
          name: 'RedisConnection'
          value: '${redisName}.privatelink.redis.cache.windows.net:6380,password=${redisCache.listKeys().primaryKey},ssl=True,abortConnect=False'
        }
        {
          name: 'SessionTimeout'
          value: string(sessionTimeoutMinutes)
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        }
        {
          name: 'WEBSITE_DNS_SERVER'
          value: '168.63.129.16'
        }
      ]
      connectionStrings: [
        {
          name: 'Redis'
          connectionString: '${redisName}.privatelink.redis.cache.windows.net:6380,password=${redisCache.listKeys().primaryKey},ssl=True,abortConnect=False'
          type: 'Custom'
        }
      ]
    }
  }
  dependsOn: [
    redisPrivateEndpoint
    redisPrivateDnsRecord
  ]
}

// Web App diagnostic settings for comprehensive monitoring
resource webAppDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'webapp-diagnostics'
  scope: webApp
  properties: {
    workspaceId: enableDiagnostics ? logAnalyticsWorkspace.id : null
    logs: [
      {
        categoryGroup: 'allLogs'
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

// ===================================================================================
// MONITORING AND ALERTING
// ===================================================================================

// Action Group for alert notifications
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (enableDiagnostics) {
  name: 'SessionAlerts'
  location: 'global'
  tags: resourceTags
  properties: {
    groupShortName: 'SessAlert'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

// Metric Alert for Redis Cache Miss Rate
resource cacheMissAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableDiagnostics) {
  name: 'HighCacheMissRate'
  location: 'global'
  tags: resourceTags
  properties: {
    description: 'Alert when Redis cache miss rate is high'
    severity: 2
    enabled: true
    scopes: [redisCache.id]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CacheMissRate'
          metricName: 'cachemisses'
          operator: 'GreaterThan'
          threshold: 100
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Metric Alert for Redis Connection Errors
resource connectionErrorAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableDiagnostics) {
  name: 'RedisConnectionErrors'
  location: 'global'
  tags: resourceTags
  properties: {
    description: 'Alert when Redis connection errors occur'
    severity: 1
    enabled: true
    scopes: [redisCache.id]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ConnectionErrors'
          metricName: 'errors'
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Total'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Metric Alert for App Service Response Time
resource responseTimeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableDiagnostics) {
  name: 'HighResponseTime'
  location: 'global'
  tags: resourceTags
  properties: {
    description: 'Alert when App Service response time is high'
    severity: 2
    enabled: true
    scopes: [webApp.id]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ResponseTime'
          metricName: 'AverageResponseTime'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ===================================================================================
// OUTPUTS
// ===================================================================================

@description('Resource Group name where resources are deployed')
output resourceGroupName string = resourceGroup().name

@description('Virtual Network resource ID for integration')
output virtualNetworkId string = virtualNetwork.id

@description('Redis Cache hostname for application configuration')
output redisHostname string = '${redisName}.privatelink.redis.cache.windows.net'

@description('Redis Cache resource ID')
output redisCacheId string = redisCache.id

@description('App Service Plan resource ID')
output appServicePlanId string = appServicePlan.id

@description('Web App resource ID')
output webAppId string = webApp.id

@description('Web App default hostname')
output webAppHostname string = webApp.properties.defaultHostName

@description('Web App URL for testing')
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = enableDiagnostics ? applicationInsights.properties.InstrumentationKey : ''

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = enableDiagnostics ? applicationInsights.properties.ConnectionString : ''

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = enableDiagnostics ? logAnalyticsWorkspace.id : ''

@description('Private Endpoint for Redis Cache')
output redisPrivateEndpointId string = redisPrivateEndpoint.id

@description('Redis connection string for application configuration')
output redisConnectionString string = '${redisName}.privatelink.redis.cache.windows.net:6380,password=${redisCache.listKeys().primaryKey},ssl=True,abortConnect=False'

@description('Session timeout configuration in minutes')
output sessionTimeoutMinutes int = sessionTimeoutMinutes

@description('Number of App Service instances deployed')
output appServiceInstanceCount int = appServiceInstanceCount

@description('Deployment summary with key configuration details')
output deploymentSummary object = {
  environment: environment
  applicationName: applicationName
  location: location
  redisCacheTier: redisCacheTier
  appServicePlanSku: appServicePlanSku
  instanceCount: appServiceInstanceCount
  sessionTimeout: '${sessionTimeoutMinutes} minutes'
  monitoringEnabled: enableDiagnostics
  deploymentDate: utcNow('yyyy-MM-dd HH:mm:ss')
}