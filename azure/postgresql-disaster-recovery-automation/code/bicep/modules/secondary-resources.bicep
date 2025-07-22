// =============================================================================
// Secondary Resources Module for PostgreSQL Disaster Recovery
// =============================================================================
// This module deploys secondary region resources including read replica and
// backup vault for disaster recovery purposes.
// =============================================================================

@description('Name of the PostgreSQL read replica server')
param postgresReplicaName string

@description('Resource ID of the primary PostgreSQL server')
param primaryServerId string

@description('Secondary region location')
param secondaryLocation string

@description('Name of the secondary backup vault')
param backupVaultSecondaryName string

@description('Tags to apply to all resources')
param tags object

@description('Enable backup policies in secondary region')
param enableBackupPolicies bool = true

// =============================================================================
// PostgreSQL Read Replica
// =============================================================================

resource postgresReplica 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: postgresReplicaName
  location: secondaryLocation
  tags: tags
  properties: {
    createMode: 'Replica'
    sourceServerResourceId: primaryServerId
    pointInTimeUTC: null
    availabilityZone: null
    replicationRole: 'AsyncReplica'
  }
}

// =============================================================================
// PostgreSQL Replica Firewall Rules
// =============================================================================

resource postgresReplicaFirewallRule 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-06-01-preview' = {
  name: 'AllowAzureServices'
  parent: postgresReplica
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// =============================================================================
// Secondary Backup Vault
// =============================================================================

resource backupVaultSecondary 'Microsoft.DataProtection/backupVaults@2023-05-01' = if (enableBackupPolicies) {
  name: backupVaultSecondaryName
  location: secondaryLocation
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
// Secondary Backup Policy
// =============================================================================

resource backupPolicySecondary 'Microsoft.DataProtection/backupVaults/backupPolicies@2023-05-01' = if (enableBackupPolicies) {
  name: 'PostgreSQLBackupPolicySecondary'
  parent: backupVaultSecondary
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
// Outputs
// =============================================================================

@description('The name of the PostgreSQL replica server')
output replicaServerName string = postgresReplica.name

@description('The FQDN of the PostgreSQL replica server')
output replicaServerFQDN string = postgresReplica.properties.fullyQualifiedDomainName

@description('The resource ID of the PostgreSQL replica server')
output replicaServerResourceId string = postgresReplica.id

@description('The name of the secondary backup vault')
output backupVaultSecondaryName string = enableBackupPolicies ? backupVaultSecondary.name : ''

@description('The resource ID of the secondary backup vault')
output backupVaultSecondaryResourceId string = enableBackupPolicies ? backupVaultSecondary.id : ''

@description('The replication role of the replica server')
output replicationRole string = postgresReplica.properties.replicationRole

@description('The source server resource ID')
output sourceServerResourceId string = postgresReplica.properties.sourceServerResourceId