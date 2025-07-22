// =============================================================================
// Azure Database for PostgreSQL Flexible Server Disaster Recovery Solution
// =============================================================================
// This Bicep template deploys a comprehensive disaster recovery solution for
// Azure Database for PostgreSQL Flexible Server with cross-region replication,
// automated backups, monitoring, and recovery automation.
// =============================================================================

@description('Base name for all resources')
param baseName string = 'postgres-dr'

@description('Primary region for the PostgreSQL server')
param primaryLocation string = 'East US'

@description('Secondary region for disaster recovery')
param secondaryLocation string = 'West US 2'

@description('Environment name (dev, staging, prod)')
param environment string = 'prod'

@description('PostgreSQL server administrator username')
param administratorLogin string = 'pgadmin'

@description('PostgreSQL server administrator password')
@secure()
param administratorPassword string

@description('PostgreSQL server SKU name')
param skuName string = 'Standard_D4s_v3'

@description('PostgreSQL server tier')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param tier string = 'GeneralPurpose'

@description('PostgreSQL server storage size in GB')
param storageSizeGB int = 128

@description('PostgreSQL server backup retention days')
param backupRetentionDays int = 35

@description('Enable geo-redundant backup')
param geoRedundantBackup bool = true

@description('Enable high availability')
param highAvailability bool = true

@description('High availability mode')
@allowed([
  'ZoneRedundant'
  'SameZone'
])
param highAvailabilityMode string = 'ZoneRedundant'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'disaster-recovery'
  Solution: 'postgresql-dr'
}

@description('Email address for disaster recovery notifications')
param notificationEmail string = 'disaster-recovery@company.com'

@description('Enable read replica in secondary region')
param enableReadReplica bool = true

@description('Enable automated backup policies')
param enableBackupPolicies bool = true

@description('Enable monitoring and alerting')
param enableMonitoring bool = true

@description('Enable automation runbooks')
param enableAutomation bool = true

// =============================================================================
// Variables
// =============================================================================

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var primaryResourceGroupName = resourceGroup().name
var secondaryResourceGroupName = '${primaryResourceGroupName}-secondary'

var postgresServerName = '${baseName}-primary-${uniqueSuffix}'
var postgresReplicaName = '${baseName}-replica-${uniqueSuffix}'
var backupVaultName = '${baseName}-backup-${uniqueSuffix}'
var backupVaultSecondaryName = '${baseName}-backup-sec-${uniqueSuffix}'
var storageAccountName = '${replace(baseName, '-', '')}st${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${baseName}-logs-${uniqueSuffix}'
var automationAccountName = '${baseName}-automation-${uniqueSuffix}'
var actionGroupName = '${baseName}-alerts-${uniqueSuffix}'

// =============================================================================
// Log Analytics Workspace
// =============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableMonitoring) {
  name: logAnalyticsWorkspaceName
  location: primaryLocation
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// =============================================================================
// Primary PostgreSQL Flexible Server
// =============================================================================

resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: postgresServerName
  location: primaryLocation
  tags: tags
  sku: {
    name: skuName
    tier: tier
  }
  properties: {
    version: '15'
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: geoRedundantBackup ? 'Enabled' : 'Disabled'
    }
    highAvailability: highAvailability ? {
      mode: highAvailabilityMode
    } : null
    network: {
      delegatedSubnetResourceId: null
      privateDnsZoneArmResourceId: null
    }
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    dataEncryption: {
      type: 'SystemManaged'
    }
    maintenanceWindow: {
      customWindow: 'Enabled'
      dayOfWeek: 0
      startHour: 2
      startMinute: 0
    }
  }
}

// =============================================================================
// PostgreSQL Server Firewall Rules
// =============================================================================

resource postgresFirewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-06-01-preview' = {
  name: 'AllowAzureServices'
  parent: postgresServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// =============================================================================
// PostgreSQL Server Diagnostic Settings
// =============================================================================

resource postgresDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: 'PostgreSQLDiagnostics'
  scope: postgresServer
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

// =============================================================================
// Storage Account for Backup Artifacts
// =============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: primaryLocation
  tags: tags
  sku: {
    name: 'Standard_GRS'
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: false
    allowCrossTenantReplication: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
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
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

// =============================================================================
// Storage Account Containers
// =============================================================================

resource storageAccountBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    changeFeed: {
      enabled: false
    }
    restorePolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource databaseBackupsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'database-backups'
  parent: storageAccountBlobService
  properties: {
    publicAccess: 'None'
  }
}

resource recoveryScriptsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'recovery-scripts'
  parent: storageAccountBlobService
  properties: {
    publicAccess: 'None'
  }
}

resource recoveryLogsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'recovery-logs'
  parent: storageAccountBlobService
  properties: {
    publicAccess: 'None'
  }
}

// =============================================================================
// Data Protection Backup Vault
// =============================================================================

resource backupVault 'Microsoft.DataProtection/backupVaults@2023-05-01' = if (enableBackupPolicies) {
  name: backupVaultName
  location: primaryLocation
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    storageSettings: [
      {
        dataStoreType: 'VaultStore'
        type: 'GeoRedundant'
      }
    ]
    securitySettings: {
      softDeleteSettings: {
        state: 'On'
        retentionDurationInDays: 14
      }
    }
  }
}

// =============================================================================
// Backup Policy
// =============================================================================

resource backupPolicy 'Microsoft.DataProtection/backupVaults/backupPolicies@2023-05-01' = if (enableBackupPolicies) {
  name: 'PostgreSQLBackupPolicy'
  parent: backupVault
  properties: {
    datasourceTypes: [
      'Microsoft.DBforPostgreSQL/flexibleServers'
    ]
    objectType: 'BackupPolicy'
    policyRules: [
      {
        backupParameters: {
          backupType: 'Full'
          objectType: 'AzureBackupParams'
        }
        trigger: {
          schedule: {
            repeatingTimeIntervals: [
              'R/2024-01-01T02:00:00+00:00/P1D'
            ]
          }
          objectType: 'ScheduleBasedTriggerContext'
        }
        dataStore: {
          dataStoreType: 'VaultStore'
          objectType: 'DataStoreInfoBase'
        }
        name: 'BackupDaily'
        objectType: 'AzureBackupRule'
      }
      {
        lifecycles: [
          {
            deleteAfter: {
              duration: 'P30D'
              objectType: 'AbsoluteDeleteOption'
            }
            sourceDataStore: {
              dataStoreType: 'VaultStore'
              objectType: 'DataStoreInfoBase'
            }
            targetDataStoreCopySettings: []
          }
        ]
        name: 'Default'
        objectType: 'AzureRetentionRule'
      }
    ]
  }
}

// =============================================================================
// Azure Automation Account
// =============================================================================

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = if (enableAutomation) {
  name: automationAccountName
  location: primaryLocation
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    disableLocalAuth: false
    publicNetworkAccess: true
    sku: {
      name: 'Basic'
    }
    encryption: {
      keySource: 'Microsoft.Automation'
      identity: {}
    }
  }
}

// =============================================================================
// Automation Credential
// =============================================================================

resource automationCredential 'Microsoft.Automation/automationAccounts/credentials@2020-01-13-preview' = if (enableAutomation) {
  name: 'PostgreSQLAdmin'
  parent: automationAccount
  properties: {
    userName: administratorLogin
    password: administratorPassword
    description: 'PostgreSQL administrator credentials for disaster recovery'
  }
}

// =============================================================================
// Disaster Recovery Runbook
// =============================================================================

resource disasterRecoveryRunbook 'Microsoft.Automation/automationAccounts/runbooks@2020-01-13-preview' = if (enableAutomation) {
  name: 'PostgreSQL-DisasterRecovery'
  parent: automationAccount
  properties: {
    runbookType: 'PowerShell'
    logVerbose: false
    logProgress: false
    description: 'Automated disaster recovery runbook for PostgreSQL Flexible Server'
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/quickstarts/microsoft.automation/101-automation-runbook-getvms/Runbooks/Get-AzureVMTutorial.ps1'
      version: '1.0.0.0'
    }
  }
}

// =============================================================================
// Action Group for Alerts
// =============================================================================

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (enableMonitoring) {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'DRAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'DRTeam'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    eventHubReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

// =============================================================================
// Metric Alert Rules
// =============================================================================

resource connectionFailuresAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: 'PostgreSQL-ConnectionFailures'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when PostgreSQL connection failures exceed threshold'
    enabled: true
    severity: 2
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ConnectionFailures'
          metricName: 'connections_failed'
          metricNamespace: 'Microsoft.DBforPostgreSQL/flexibleServers'
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Count'
          skipMetricValidation: false
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
    scopes: [
      postgresServer.id
    ]
  }
}

resource replicationLagAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring && enableReadReplica) {
  name: 'PostgreSQL-ReplicationLag'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when PostgreSQL replication lag exceeds threshold'
    enabled: true
    severity: 1
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ReplicationLag'
          metricName: 'replica_lag'
          metricNamespace: 'Microsoft.DBforPostgreSQL/flexibleServers'
          operator: 'GreaterThan'
          threshold: 300
          timeAggregation: 'Average'
          skipMetricValidation: false
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
    scopes: [
      postgresServer.id
    ]
  }
}

resource backupFailuresAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: 'PostgreSQL-BackupFailures'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when PostgreSQL backup failures occur'
    enabled: true
    severity: 1
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'BackupFailures'
          metricName: 'backup_failures'
          metricNamespace: 'Microsoft.DBforPostgreSQL/flexibleServers'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Count'
          skipMetricValidation: false
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
    scopes: [
      postgresServer.id
    ]
  }
}

// =============================================================================
// Secondary Resource Group (for read replica)
// =============================================================================

module secondaryResourceGroup 'modules/secondary-resources.bicep' = if (enableReadReplica) {
  name: 'secondary-resources-deployment'
  scope: resourceGroup(secondaryResourceGroupName)
  params: {
    postgresReplicaName: postgresReplicaName
    primaryServerId: postgresServer.id
    secondaryLocation: secondaryLocation
    backupVaultSecondaryName: backupVaultSecondaryName
    tags: tags
    enableBackupPolicies: enableBackupPolicies
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('The name of the primary PostgreSQL server')
output primaryPostgreSQLServerName string = postgresServer.name

@description('The FQDN of the primary PostgreSQL server')
output primaryPostgreSQLServerFQDN string = postgresServer.properties.fullyQualifiedDomainName

@description('The name of the replica PostgreSQL server')
output replicaPostgreSQLServerName string = enableReadReplica ? postgresReplicaName : ''

@description('The resource ID of the primary PostgreSQL server')
output primaryPostgreSQLServerResourceId string = postgresServer.id

@description('The name of the backup vault')
output backupVaultName string = enableBackupPolicies ? backupVault.name : ''

@description('The resource ID of the backup vault')
output backupVaultResourceId string = enableBackupPolicies ? backupVault.id : ''

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the storage account')
output storageAccountResourceId string = storageAccount.id

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = enableMonitoring ? logAnalyticsWorkspace.name : ''

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceResourceId string = enableMonitoring ? logAnalyticsWorkspace.id : ''

@description('The name of the automation account')
output automationAccountName string = enableAutomation ? automationAccount.name : ''

@description('The resource ID of the automation account')
output automationAccountResourceId string = enableAutomation ? automationAccount.id : ''

@description('The name of the action group')
output actionGroupName string = enableMonitoring ? actionGroup.name : ''

@description('The resource ID of the action group')
output actionGroupResourceId string = enableMonitoring ? actionGroup.id : ''

@description('Connection string for the primary PostgreSQL server')
output primaryConnectionString string = 'postgresql://${administratorLogin}:${administratorPassword}@${postgresServer.properties.fullyQualifiedDomainName}:5432'

@description('Connection string for the replica PostgreSQL server (if enabled)')
output replicaConnectionString string = enableReadReplica ? 'postgresql://${administratorLogin}:${administratorPassword}@${postgresReplicaName}.postgres.database.azure.com:5432' : ''

@description('Primary resource group name')
output primaryResourceGroupName string = primaryResourceGroupName

@description('Secondary resource group name')
output secondaryResourceGroupName string = secondaryResourceGroupName

@description('Deployment summary')
output deploymentSummary object = {
  primaryLocation: primaryLocation
  secondaryLocation: secondaryLocation
  highAvailabilityEnabled: highAvailability
  geoRedundantBackupEnabled: geoRedundantBackup
  readReplicaEnabled: enableReadReplica
  backupPoliciesEnabled: enableBackupPolicies
  monitoringEnabled: enableMonitoring
  automationEnabled: enableAutomation
  backupRetentionDays: backupRetentionDays
  storageSizeGB: storageSizeGB
}