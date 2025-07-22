@description('Main Bicep template for Migrate Multi-tenant MariaDB Workloads to MySQL Flexible Server')

// ========== PARAMETERS ==========

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Project name for resource naming')
param projectName string

@description('Random suffix for unique resource names')
param randomSuffix string = uniqueString(resourceGroup().id)

// MySQL Flexible Server Parameters
@description('MySQL Flexible Server administrator login name')
param mysqlAdminLogin string

@description('MySQL Flexible Server administrator password')
@secure()
param mysqlAdminPassword string

@description('MySQL Flexible Server compute tier')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param mysqlComputeTier string = 'GeneralPurpose'

@description('MySQL Flexible Server SKU name')
param mysqlSkuName string = 'Standard_D2ds_v4'

@description('MySQL Flexible Server storage size in GB')
@minValue(20)
@maxValue(16384)
param mysqlStorageSize int = 128

@description('MySQL Flexible Server version')
@allowed([
  '5.7'
  '8.0'
])
param mysqlVersion string = '5.7'

@description('Enable high availability for MySQL Flexible Server')
param enableHighAvailability bool = true

@description('High availability mode')
@allowed([
  'ZoneRedundant'
  'SameZone'
])
param highAvailabilityMode string = 'ZoneRedundant'

@description('Backup retention days')
@minValue(1)
@maxValue(35)
param backupRetentionDays int = 35

@description('Enable geo-redundant backup')
param enableGeoRedundantBackup bool = true

// Monitoring Parameters
@description('Enable diagnostic settings')
param enableDiagnostics bool = true

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 90

// Network Parameters
@description('Enable private endpoint for MySQL server')
param enablePrivateEndpoint bool = false

@description('Virtual network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Database subnet address prefix')
param databaseSubnetPrefix string = '10.0.1.0/24'

@description('Private endpoint subnet address prefix')
param privateEndpointSubnetPrefix string = '10.0.2.0/24'

// Tags
@description('Resource tags')
param tags object = {
  Environment: environment
  Project: projectName
  Purpose: 'MariaDB to MySQL Migration'
  CreatedBy: 'Bicep Template'
}

// ========== VARIABLES ==========

var resourcePrefix = '${projectName}-${environment}'
var mysqlServerName = '${resourcePrefix}-mysql-${randomSuffix}'
var mysqlReplicaServerName = '${resourcePrefix}-mysql-replica-${randomSuffix}'
var storageAccountName = 'st${replace(projectName, '-', '')}${environment}${randomSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-logs-${randomSuffix}'
var applicationInsightsName = '${resourcePrefix}-insights-${randomSuffix}'
var virtualNetworkName = '${resourcePrefix}-vnet-${randomSuffix}'
var databaseSubnetName = 'database-subnet'
var privateEndpointSubnetName = 'private-endpoint-subnet'
var privateDnsZoneName = 'privatelink.mysql.database.azure.com'

// ========== RESOURCES ==========

// Storage Account for migration artifacts
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
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Storage Account Blob Service
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 30
    }
  }
}

// Container for migration artifacts
resource migrationContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'migration-artifacts'
  properties: {
    publicAccess: 'None'
  }
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableDiagnostics) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableDiagnostics) {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableDiagnostics ? logAnalyticsWorkspace.id : null
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Virtual Network (if private endpoint is enabled)
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = if (enablePrivateEndpoint) {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: databaseSubnetName
        properties: {
          addressPrefix: databaseSubnetPrefix
          delegations: [
            {
              name: 'dlg-MySQL'
              properties: {
                serviceName: 'Microsoft.DBforMySQL/flexibleServers'
              }
            }
          ]
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Private DNS Zone
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enablePrivateEndpoint) {
  name: privateDnsZoneName
  location: 'global'
  tags: tags
}

// Private DNS Zone VNet Link
resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enablePrivateEndpoint) {
  parent: privateDnsZone
  name: '${virtualNetworkName}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

// MySQL Flexible Server
resource mysqlFlexibleServer 'Microsoft.DBforMySQL/flexibleServers@2023-12-01-preview' = {
  name: mysqlServerName
  location: location
  tags: tags
  sku: {
    name: mysqlSkuName
    tier: mysqlComputeTier
  }
  properties: {
    administratorLogin: mysqlAdminLogin
    administratorLoginPassword: mysqlAdminPassword
    version: mysqlVersion
    storage: {
      storageSizeGB: mysqlStorageSize
      autoGrow: 'Enabled'
      autoIoScaling: 'Enabled'
      iops: 1000
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: enableGeoRedundantBackup ? 'Enabled' : 'Disabled'
    }
    highAvailability: enableHighAvailability ? {
      mode: highAvailabilityMode
    } : null
    network: enablePrivateEndpoint ? {
      delegatedSubnetResourceId: '${virtualNetwork.id}/subnets/${databaseSubnetName}'
      privateDnsZoneResourceId: privateDnsZone.id
    } : null
    replicationRole: 'Primary'
    createMode: 'Default'
  }
}

// MySQL Flexible Server Configuration - max_connections
resource mysqlConfigMaxConnections 'Microsoft.DBforMySQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: mysqlFlexibleServer
  name: 'max_connections'
  properties: {
    value: '1000'
    source: 'user-override'
  }
}

// MySQL Flexible Server Configuration - innodb_buffer_pool_size
resource mysqlConfigInnodbBufferPool 'Microsoft.DBforMySQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: mysqlFlexibleServer
  name: 'innodb_buffer_pool_size'
  properties: {
    value: '1073741824'
    source: 'user-override'
  }
}

// MySQL Flexible Server Configuration - slow_query_log
resource mysqlConfigSlowQueryLog 'Microsoft.DBforMySQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: mysqlFlexibleServer
  name: 'slow_query_log'
  properties: {
    value: 'ON'
    source: 'user-override'
  }
}

// MySQL Flexible Server Configuration - long_query_time
resource mysqlConfigLongQueryTime 'Microsoft.DBforMySQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: mysqlFlexibleServer
  name: 'long_query_time'
  properties: {
    value: '2'
    source: 'user-override'
  }
}

// Firewall rule for Azure services (if not using private endpoint)
resource mysqlFirewallRuleAzure 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2023-12-01-preview' = if (!enablePrivateEndpoint) {
  parent: mysqlFlexibleServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// MySQL Read Replica
resource mysqlReadReplica 'Microsoft.DBforMySQL/flexibleServers@2023-12-01-preview' = {
  name: mysqlReplicaServerName
  location: location
  tags: tags
  sku: {
    name: mysqlSkuName
    tier: mysqlComputeTier
  }
  properties: {
    createMode: 'Replica'
    sourceServerResourceId: mysqlFlexibleServer.id
    replicationRole: 'Replica'
  }
}

// Diagnostic Settings for MySQL Flexible Server
resource mysqlDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  scope: mysqlFlexibleServer
  name: 'mysql-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
    ]
  }
}

// Metric Alert - High CPU Usage
resource alertHighCpu 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableDiagnostics) {
  name: 'MySQL-CPU-High'
  location: 'global'
  tags: tags
  properties: {
    description: 'High CPU usage on MySQL Flexible Server'
    severity: 2
    enabled: true
    scopes: [
      mysqlFlexibleServer.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCpuUsage'
          metricName: 'cpu_percent'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
  }
}

// Metric Alert - High Connection Count
resource alertHighConnections 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableDiagnostics) {
  name: 'MySQL-Connections-High'
  location: 'global'
  tags: tags
  properties: {
    description: 'High connection count on MySQL Flexible Server'
    severity: 2
    enabled: true
    scopes: [
      mysqlFlexibleServer.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighConnectionCount'
          metricName: 'active_connections'
          operator: 'GreaterThan'
          threshold: 800
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
  }
}

// Metric Alert - High Storage Usage
resource alertHighStorage 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableDiagnostics) {
  name: 'MySQL-Storage-High'
  location: 'global'
  tags: tags
  properties: {
    description: 'High storage usage on MySQL Flexible Server'
    severity: 1
    enabled: true
    scopes: [
      mysqlFlexibleServer.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighStorageUsage'
          metricName: 'storage_percent'
          operator: 'GreaterThan'
          threshold: 85
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
  }
}

// ========== OUTPUTS ==========

@description('MySQL Flexible Server FQDN')
output mysqlServerFqdn string = mysqlFlexibleServer.properties.fullyQualifiedDomainName

@description('MySQL Flexible Server name')
output mysqlServerName string = mysqlFlexibleServer.name

@description('MySQL Read Replica FQDN')
output mysqlReplicaFqdn string = mysqlReadReplica.properties.fullyQualifiedDomainName

@description('MySQL Read Replica name')
output mysqlReplicaName string = mysqlReadReplica.name

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Storage Account connection string')
@secure()
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = enableDiagnostics ? logAnalyticsWorkspace.id : ''

@description('Application Insights Instrumentation Key')
@secure()
output applicationInsightsInstrumentationKey string = enableDiagnostics ? applicationInsights.properties.InstrumentationKey : ''

@description('Application Insights Connection String')
@secure()
output applicationInsightsConnectionString string = enableDiagnostics ? applicationInsights.properties.ConnectionString : ''

@description('Virtual Network ID (if private endpoint enabled)')
output virtualNetworkId string = enablePrivateEndpoint ? virtualNetwork.id : ''

@description('Private DNS Zone ID (if private endpoint enabled)')
output privateDnsZoneId string = enablePrivateEndpoint ? privateDnsZone.id : ''

@description('MySQL server resource ID')
output mysqlServerResourceId string = mysqlFlexibleServer.id

@description('MySQL replica resource ID')
output mysqlReplicaResourceId string = mysqlReadReplica.id

@description('Migration container URL')
output migrationContainerUrl string = '${storageAccount.properties.primaryEndpoints.blob}${migrationContainer.name}'

@description('Resource tags applied to all resources')
output appliedTags object = tags