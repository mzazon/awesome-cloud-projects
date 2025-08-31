@description('Simple File Backup Automation using Logic Apps and Storage')
@description('This template creates Azure Logic Apps and Storage Account for automated file backup')

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name for resource naming (e.g., dev, prod)')
@maxLength(10)
param environment string = 'demo'

@description('Project name for resource naming and tagging')
@maxLength(20)
param projectName string = 'filebackup'

@description('Storage account access tier for backup files')
@allowed(['Hot', 'Cool'])
param storageAccessTier string = 'Cool'

@description('Storage account SKU for backup data')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS', 'Premium_LRS'])
param storageSku string = 'Standard_LRS'

@description('Backup schedule frequency')
@allowed(['Day', 'Week', 'Month'])
param backupFrequency string = 'Day'

@description('Backup schedule interval (1 for daily, 7 for weekly, etc.)')
@minValue(1)
@maxValue(30)
param backupInterval int = 1

@description('Backup execution time (hour in 24-hour format)')
@minValue(0)
@maxValue(23)
param backupHour int = 2

@description('Time zone for backup schedule')
param timeZone string = 'Eastern Standard Time'

@description('Container name for backup files')
@maxLength(63)
param containerName string = 'backup-files'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'backup'
  environment: environment
  project: projectName
  automation: 'file-backup'
  'cost-center': 'IT'
}

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var storageAccountName = 'st${projectName}${uniqueSuffix}'
var logicAppName = 'la-${projectName}-${environment}-${uniqueSuffix}'

// Storage Account for backup files
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: storageAccessTier
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Blob Service for storage account
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
      days: 7
    }
  }
}

// Container for backup files
resource backupContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'backup'
      created: utcNow()
      environment: environment
    }
  }
}

// Logic Apps Workflow for backup automation
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        storageAccountName: {
          type: 'string'
          defaultValue: storageAccountName
        }
        containerName: {
          type: 'string'
          defaultValue: containerName
        }
        storageAccountKey: {
          type: 'securestring'
          defaultValue: ''
        }
      }
      triggers: {
        Recurrence: {
          recurrence: {
            frequency: backupFrequency
            interval: backupInterval
            schedule: {
              hours: [backupHour]
              minutes: [0]
            }
            timeZone: timeZone
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Initialize_backup_status: {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'BackupStatus'
                type: 'String'
                value: 'Starting backup process'
              }
            ]
          }
          runAfter: {}
        }
        Initialize_timestamp: {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'BackupTimestamp'
                type: 'String'
                value: '@{formatDateTime(utcNow(), \'yyyy-MM-dd-HH-mm-ss\')}'
              }
            ]
          }
          runAfter: {
            Initialize_backup_status: ['Succeeded']
          }
        }
        Create_backup_log: {
          type: 'Http'
          inputs: {
            method: 'PUT'
            uri: 'https://@{parameters(\'storageAccountName\')}.blob.core.windows.net/@{parameters(\'containerName\')}/backup-log-@{variables(\'BackupTimestamp\')}.txt'
            headers: {
              'x-ms-blob-type': 'BlockBlob'
              'Content-Type': 'text/plain'
              'x-ms-date': '@{formatDateTime(utcNow(), \'r\')}'
              'x-ms-version': '2020-04-08'
              Authorization: 'SharedKey @{parameters(\'storageAccountName\')}:@{base64(hmacSha256(base64(concat(\'PUT\', \'\\n\', \'\\n\', \'text/plain\', \'\\n\', \'\\n\', \'\\n\', \'\\n\', \'\\n\', \'\\n\', \'\\n\', \'\\n\', \'\\n\', \'x-ms-blob-type:BlockBlob\', \'\\n\', \'x-ms-date:\', formatDateTime(utcNow(), \'r\'), \'\\n\', \'x-ms-version:2020-04-08\', \'\\n\', \'/\', parameters(\'storageAccountName\'), \'/\', parameters(\'containerName\'), \'/backup-log-\', variables(\'BackupTimestamp\'), \'.txt\')), base64(parameters(\'storageAccountKey\'))))}'
            }
            body: 'Backup process initiated at @{utcNow()}\nEnvironment: ${environment}\nProject: ${projectName}\nStorage Account: @{parameters(\'storageAccountName\')}\nContainer: @{parameters(\'containerName\')}\nSchedule: ${backupFrequency} every ${backupInterval} at ${backupHour}:00 ${timeZone}\nStatus: @{variables(\'BackupStatus\')}'
          }
          runAfter: {
            Initialize_timestamp: ['Succeeded']
          }
        }
        Set_backup_completed: {
          type: 'SetVariable'
          inputs: {
            name: 'BackupStatus'
            value: 'Backup process completed successfully'
          }
          runAfter: {
            Create_backup_log: ['Succeeded']
          }
        }
        Handle_backup_failure: {
          type: 'SetVariable'
          inputs: {
            name: 'BackupStatus'
            value: 'Backup process failed - @{outputs(\'Create_backup_log\')?[\'statusCode\']}'
          }
          runAfter: {
            Create_backup_log: ['Failed', 'Skipped', 'TimedOut']
          }
        }
      }
      outputs: {
        backupStatus: {
          type: 'String'
          value: '@variables(\'BackupStatus\')'
        }
        executionTime: {
          type: 'String'
          value: '@utcNow()'
        }
        storageAccount: {
          type: 'String'
          value: '@parameters(\'storageAccountName\')'
        }
      }
    }
    parameters: {
      storageAccountName: {
        value: storageAccountName
      }
      containerName: {
        value: containerName
      }
      storageAccountKey: {
        value: storageAccount.listKeys().keys[0].value
      }
    }
  }
  dependsOn: [
    storageAccount
    backupContainer
  ]
}

// Outputs
@description('The name of the created storage account')
output storageAccountName string = storageAccount.name

@description('The name of the created Logic Apps workflow')
output logicAppName string = logicApp.name

@description('The name of the backup container')
output containerName string = backupContainer.name

@description('The storage account primary endpoint')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The Logic Apps workflow callback URL')
output logicAppCallbackUrl string = logicApp.listCallbackUrl().value

@description('The resource group name where resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('The Azure region where resources were deployed')
output deploymentLocation string = location

@description('Storage account connection string for external applications')
@secure()
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Backup schedule summary')
output backupSchedule string = '${backupFrequency} every ${backupInterval} at ${backupHour}:00 ${timeZone}'

@description('All resource tags applied to the deployment')
output appliedTags object = tags