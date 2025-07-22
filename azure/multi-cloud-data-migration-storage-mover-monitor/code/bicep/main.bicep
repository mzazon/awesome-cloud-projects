@description('Location for all resources')
param location string = resourceGroup().location

@description('Storage account name for migration target')
param storageAccountName string

@description('Storage Mover resource name')
param storageMoverName string

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string

@description('Logic App name for migration automation')
param logicAppName string

@description('AWS S3 bucket name (source)')
param awsS3BucketName string

@description('AWS Account ID')
param awsAccountId string

@description('AWS Region for S3 bucket')
param awsRegion string = 'us-east-1'

@description('Email address for alert notifications')
param adminEmail string

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Standard_GZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Storage account access tier')
@allowed([
  'Hot'
  'Cool'
])
param storageAccountAccessTier string = 'Hot'

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Log Analytics workspace pricing tier')
@allowed([
  'pergb2018'
  'Free'
  'Standalone'
  'PerNode'
  'Standard'
  'Premium'
])
param logAnalyticsPricingTier string = 'pergb2018'

@description('Enable hierarchical namespace for storage account')
param enableHierarchicalNamespace bool = false

@description('Container name for migrated data')
param migrationContainerName string = 'migrated-data'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'migration'
  environment: 'demo'
  source: 'aws-s3'
  'migration-type': 's3-to-blob'
}

// Storage Account for target data
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: storageAccountAccessTier
    supportsHttpsTrafficOnly: true
    isHnsEnabled: enableHierarchicalNamespace
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
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
  }
}

// Blob Services for the storage account
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    isVersioningEnabled: true
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
  }
}

// Container for migrated data
resource migrationContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: migrationContainerName
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'migration-target'
      source: 'aws-s3'
    }
  }
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsPricingTier
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Mover resource
resource storageMover 'Microsoft.StorageMover/storageMovers@2023-10-01' = {
  name: storageMoverName
  location: location
  tags: tags
  properties: {
    description: 'Multi-cloud migration from AWS S3 to Azure Blob Storage'
  }
}

// AWS S3 source endpoint
resource awsS3Endpoint 'Microsoft.StorageMover/storageMovers/endpoints@2023-10-01' = {
  parent: storageMover
  name: 'aws-s3-source'
  properties: {
    endpointType: 'AzureStorageContainer'
    description: 'AWS S3 source endpoint'
    properties: {
      storageAccountResourceId: storageAccount.id
      blobContainerName: awsS3BucketName
    }
  }
}

// Azure Blob target endpoint
resource azureBlobEndpoint 'Microsoft.StorageMover/storageMovers/endpoints@2023-10-01' = {
  parent: storageMover
  name: 'azure-blob-target'
  properties: {
    endpointType: 'AzureStorageContainer'
    description: 'Azure Blob Storage target endpoint'
    properties: {
      storageAccountResourceId: storageAccount.id
      blobContainerName: migrationContainerName
    }
  }
}

// Project for organizing migration jobs
resource migrationProject 'Microsoft.StorageMover/storageMovers/projects@2023-10-01' = {
  parent: storageMover
  name: 's3-to-blob-migration'
  properties: {
    description: 'Project for S3 to Azure Blob migration'
  }
}

// Job definition for migration
resource migrationJobDefinition 'Microsoft.StorageMover/storageMovers/projects/jobDefinitions@2023-10-01' = {
  parent: migrationProject
  name: 'initial-migration'
  properties: {
    description: 'Initial migration from AWS S3 to Azure Blob Storage'
    sourceEndpointName: awsS3Endpoint.name
    targetEndpointName: azureBlobEndpoint.name
    copyMode: 'Mirror'
  }
}

// Action Group for alert notifications
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'migration-alerts'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'migration'
    enabled: true
    emailReceivers: [
      {
        name: 'admin'
        emailAddress: adminEmail
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    armRoleReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    eventHubReceivers: []
  }
}

// Metric Alert for migration job failures
resource migrationFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'migration-job-failure'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when migration job fails'
    severity: 1
    enabled: true
    scopes: [
      storageMover.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 1
          name: 'JobFailure'
          metricNamespace: 'Microsoft.StorageMover/storageMovers'
          metricName: 'JobStatus'
          operator: 'GreaterThanOrEqual'
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'Status'
              operator: 'Include'
              values: [
                'Failed'
              ]
            }
          ]
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// Metric Alert for migration job success
resource migrationSuccessAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'migration-job-success'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when migration job completes successfully'
    severity: 3
    enabled: true
    scopes: [
      storageMover.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 1
          name: 'JobSuccess'
          metricNamespace: 'Microsoft.StorageMover/storageMovers'
          metricName: 'JobStatus'
          operator: 'GreaterThanOrEqual'
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'Status'
              operator: 'Include'
              values: [
                'Succeeded'
              ]
            }
          ]
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// Logic App for migration automation
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
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                jobName: {
                  type: 'string'
                }
                copyMode: {
                  type: 'string'
                }
              }
            }
          }
        }
      }
      actions: {
        StartMigration: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://management.azure.com/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.StorageMover/storageMovers/${storageMoverName}/projects/s3-to-blob-migration/jobDefinitions/initial-migration/jobRuns'
            headers: {
              'Content-Type': 'application/json'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
            }
            body: {
              properties: {
                sourceEndpoint: 'aws-s3-source'
                targetEndpoint: 'azure-blob-target'
                copyMode: 'Mirror'
              }
            }
          }
        }
        Response: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: {
              message: 'Migration job started successfully'
              jobId: '@{body(\'StartMigration\')?[\'id\']}'
            }
          }
          runAfter: {
            StartMigration: [
              'Succeeded'
            ]
          }
        }
        ErrorResponse: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 400
            body: {
              message: 'Failed to start migration job'
              error: '@{body(\'StartMigration\')}'
            }
          }
          runAfter: {
            StartMigration: [
              'Failed'
            ]
          }
        }
      }
    }
  }
}

// Diagnostic Settings for Storage Mover
resource storageMoverDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${storageMoverName}-diagnostics'
  scope: storageMover
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'StorageMoverLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
  }
}

// Diagnostic Settings for Storage Account
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${storageAccountName}-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
      {
        category: 'Capacity'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
  }
}

// Outputs
@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Storage Account resource ID')
output storageAccountId string = storageAccount.id

@description('Storage Account primary endpoints')
output storageAccountEndpoints object = storageAccount.properties.primaryEndpoints

@description('Storage Mover name')
output storageMoverName string = storageMover.name

@description('Storage Mover resource ID')
output storageMoverResourceId string = storageMover.id

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Logic App name')
output logicAppName string = logicApp.name

@description('Logic App trigger URL')
output logicAppTriggerUrl string = listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicApp.name, 'manual'), '2019-05-01').value

@description('Migration container name')
output migrationContainerName string = migrationContainer.name

@description('Action Group resource ID')
output actionGroupId string = actionGroup.id

@description('AWS S3 source endpoint name')
output awsS3EndpointName string = awsS3Endpoint.name

@description('Azure Blob target endpoint name')
output azureBlobEndpointName string = azureBlobEndpoint.name

@description('Migration project name')
output migrationProjectName string = migrationProject.name

@description('Migration job definition name')
output migrationJobDefinitionName string = migrationJobDefinition.name

@description('Resource Group location')
output location string = location

@description('Resource tags applied')
output appliedTags object = tags