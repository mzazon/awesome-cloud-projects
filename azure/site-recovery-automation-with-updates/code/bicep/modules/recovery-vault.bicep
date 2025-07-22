@description('Recovery Services Vault module for Azure Site Recovery')

// Parameters
@description('Location for Recovery Services Vault')
param location string

@description('Recovery Services Vault name')
param vaultName string

@description('Resource tags')
param tags object

// Recovery Services Vault
resource recoveryServicesVault 'Microsoft.RecoveryServices/vaults@2023-06-01' = {
  name: vaultName
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    restoreSettings: {
      crossSubscriptionRestoreSettings: {
        crossSubscriptionRestoreState: 'Enabled'
      }
    }
  }
}

// Backup policy for VMs
resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-06-01' = {
  parent: recoveryServicesVault
  name: 'DefaultPolicy'
  properties: {
    backupManagementType: 'AzureIaasVM'
    instantRpRetentionRangeInDays: 2
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: [
        '2023-01-01T02:00:00Z'
      ]
      scheduleWeeklyFrequency: 0
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: [
          '2023-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 30
          durationType: 'Days'
        }
      }
      weeklySchedule: {
        daysOfTheWeek: [
          'Sunday'
        ]
        retentionTimes: [
          '2023-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 12
          durationType: 'Weeks'
        }
      }
      monthlySchedule: {
        retentionScheduleFormatType: 'Weekly'
        retentionScheduleWeekly: {
          daysOfTheWeek: [
            'Sunday'
          ]
          weeksOfTheMonth: [
            'First'
          ]
        }
        retentionTimes: [
          '2023-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 12
          durationType: 'Months'
        }
      }
      yearlySchedule: {
        retentionScheduleFormatType: 'Weekly'
        monthsOfYear: [
          'January'
        ]
        retentionScheduleWeekly: {
          daysOfTheWeek: [
            'Sunday'
          ]
          weeksOfTheMonth: [
            'First'
          ]
        }
        retentionTimes: [
          '2023-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 10
          durationType: 'Years'
        }
      }
    }
    timeZone: 'UTC'
  }
}

// Site Recovery replication policy
resource replicationPolicy 'Microsoft.RecoveryServices/vaults/replicationPolicies@2023-06-01' = {
  parent: recoveryServicesVault
  name: 'DefaultReplicationPolicy'
  properties: {
    providerSpecificInput: {
      instanceType: 'A2A'
      recoveryPointRetentionInHours: 24
      appConsistentFrequencyInHours: 4
      crashConsistentFrequencyInHours: 4
      multiVmSyncStatus: 'Enable'
    }
  }
}

// Outputs
@description('Recovery Services Vault ID')
output vaultId string = recoveryServicesVault.id

@description('Recovery Services Vault name')
output vaultName string = recoveryServicesVault.name

@description('Backup policy ID')
output backupPolicyId string = backupPolicy.id

@description('Replication policy ID')
output replicationPolicyId string = replicationPolicy.id