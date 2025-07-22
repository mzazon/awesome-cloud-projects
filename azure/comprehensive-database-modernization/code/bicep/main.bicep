@description('The name of the resource group where resources will be deployed')
param resourceGroupName string = resourceGroup().name

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('A unique suffix to append to resource names to ensure uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('The name of the SQL Server instance')
param sqlServerName string = 'sqlserver-${uniqueSuffix}'

@description('The name of the SQL Database')
param sqlDatabaseName string = 'modernized-db'

@description('The administrator username for the SQL Server')
param sqlAdminUsername string = 'sqladmin'

@description('The administrator password for the SQL Server')
@secure()
param sqlAdminPassword string

@description('The name of the Database Migration Service')
param dmsServiceName string = 'dms-${uniqueSuffix}'

@description('The name of the Storage Account for migration assets')
param storageAccountName string = 'stgmigration${uniqueSuffix}'

@description('The name of the Recovery Services Vault for backup')
param backupVaultName string = 'rsv-backup-${uniqueSuffix}'

@description('The name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string = 'la-monitoring-${uniqueSuffix}'

@description('The pricing tier for the SQL Database')
@allowed([
  'Basic'
  'Standard'
  'Premium'
  'GeneralPurpose'
  'BusinessCritical'
])
param sqlDatabaseSku string = 'Standard'

@description('The service objective for the SQL Database')
param sqlDatabaseServiceObjective string = 'S2'

@description('The SKU for the Database Migration Service')
@allowed([
  'Basic_1vCore'
  'Standard_1vCores'
  'Standard_2vCores'
  'Standard_4vCores'
  'Premium_4vCores'
])
param dmsSkuName string = 'Premium_4vCores'

@description('The backup storage redundancy type')
@allowed([
  'LocallyRedundant'
  'GeoRedundant'
  'ReadAccessGeoRedundant'
])
param backupStorageRedundancy string = 'LocallyRedundant'

@description('Email address for monitoring alerts')
param alertEmailAddress string = 'admin@contoso.com'

@description('Tags to apply to all resources')
param resourceTags object = {
  purpose: 'database-migration'
  environment: 'demo'
  project: 'modernization'
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
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

// Storage Account for migration assets
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
    }
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
  }
}

// Storage container for database backups
resource storageContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/database-backups'
  properties: {
    publicAccess: 'None'
  }
}

// SQL Server
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: sqlServerName
  location: location
  tags: resourceTags
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    publicNetworkAccess: 'Enabled'
    minimalTlsVersion: '1.2'
  }
}

// SQL Server firewall rule to allow Azure services
resource sqlServerFirewallRule 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// SQL Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: resourceTags
  sku: {
    name: sqlDatabaseServiceObjective
    tier: sqlDatabaseSku
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 268435456000 // 250 GB
    requestedBackupStorageRedundancy: backupStorageRedundancy
  }
}

// Database Migration Service
resource dmsService 'Microsoft.DataMigration/services@2021-06-30' = {
  name: dmsServiceName
  location: location
  tags: resourceTags
  sku: {
    name: dmsSkuName
  }
  properties: {
    publicKey: ''
  }
}

// Migration Project
resource migrationProject 'Microsoft.DataMigration/services/projects@2021-06-30' = {
  parent: dmsService
  name: 'sqlserver-to-azuresql-migration'
  location: location
  tags: resourceTags
  properties: {
    sourcePlatform: 'SQL'
    targetPlatform: 'SQLDB'
  }
}

// Recovery Services Vault for backup
resource recoveryServicesVault 'Microsoft.RecoveryServices/vaults@2023-06-01' = {
  name: backupVaultName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// Backup policy for SQL Database
resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-06-01' = {
  parent: recoveryServicesVault
  name: 'CustomSQLBackupPolicy'
  properties: {
    backupManagementType: 'AzureSql'
    workLoadType: 'SQLDataBase'
    settings: {
      timeZone: 'UTC'
      issqlcompression: true
      isCompression: true
    }
    subProtectionPolicy: [
      {
        policyType: 'Full'
        schedulePolicy: {
          schedulePolicyType: 'SimpleSchedulePolicy'
          scheduleRunFrequency: 'Daily'
          scheduleRunTimes: [
            '2023-12-01T02:00:00Z'
          ]
        }
        retentionPolicy: {
          retentionPolicyType: 'LongTermRetentionPolicy'
          dailySchedule: {
            retentionTimes: [
              '2023-12-01T02:00:00Z'
            ]
            retentionDuration: {
              count: 30
              durationType: 'Days'
            }
          }
        }
      }
    ]
  }
}

// Action Group for alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'migration-alerts'
  location: 'Global'
  tags: resourceTags
  properties: {
    groupShortName: 'migration'
    enabled: true
    emailReceivers: [
      {
        name: 'admin'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// Metric Alert for migration failures
resource migrationFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'migration-failure-alert'
  location: 'Global'
  tags: resourceTags
  properties: {
    description: 'Alert for migration failures'
    severity: 1
    enabled: true
    scopes: [
      dmsService.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'MigrationFailures'
          metricName: 'FailedMigrations'
          metricNamespace: 'Microsoft.DataMigration/services'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Count'
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

// Metric Alert for backup failures
resource backupFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'backup-failure-alert'
  location: 'Global'
  tags: resourceTags
  properties: {
    description: 'Alert for backup failures'
    severity: 1
    enabled: true
    scopes: [
      recoveryServicesVault.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'BackupFailures'
          metricName: 'BackupFailures'
          metricNamespace: 'Microsoft.RecoveryServices/vaults'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Count'
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

// Diagnostic Settings for Database Migration Service
resource dmsDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'dms-diagnostics'
  scope: dmsService
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'DataMigrationService'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Diagnostic Settings for SQL Database
resource sqlDatabaseDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sqldb-diagnostics'
  scope: sqlDatabase
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'SQLSecurityAuditEvents'
        enabled: true
      }
      {
        category: 'QueryStoreRuntimeStatistics'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Diagnostic Settings for Recovery Services Vault
resource vaultDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'vault-diagnostics'
  scope: recoveryServicesVault
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AzureBackupReport'
        enabled: true
      }
      {
        category: 'AzureSiteRecoveryJobs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// Outputs
@description('The name of the created SQL Server')
output sqlServerName string = sqlServer.name

@description('The fully qualified domain name of the SQL Server')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('The name of the created SQL Database')
output sqlDatabaseName string = sqlDatabase.name

@description('The name of the Database Migration Service')
output dmsServiceName string = dmsService.name

@description('The name of the Storage Account for migration assets')
output storageAccountName string = storageAccount.name

@description('The name of the Recovery Services Vault')
output backupVaultName string = recoveryServicesVault.name

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The resource ID of the Migration Project')
output migrationProjectId string = migrationProject.id

@description('The connection string for the SQL Database')
output sqlDatabaseConnectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${sqlDatabase.name};Persist Security Info=False;User ID=${sqlAdminUsername};Password={your_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

@description('The primary endpoint of the Storage Account')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The resource ID of the Action Group for alerts')
output actionGroupId string = actionGroup.id