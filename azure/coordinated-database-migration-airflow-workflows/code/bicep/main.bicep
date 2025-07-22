// ===================================================================================
// Bicep Template: Intelligent Database Migration Orchestration
// Description: Deploys Azure Data Factory with Workflow Orchestration Manager,
//              Database Migration Service, and comprehensive monitoring
// Version: 1.0
// ===================================================================================

targetScope = 'resourceGroup'

// ===================================================================================
// PARAMETERS
// ===================================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'database-migration'
  environment: environment
  recipe: 'intelligent-migration-orchestration'
}

// Data Factory Parameters
@description('Azure Data Factory name')
param dataFactoryName string = 'adf-migration-${uniqueSuffix}'

@description('Enable managed virtual network for Data Factory')
param enableManagedVNet bool = true

@description('Enable Git repository integration')
param enableGitIntegration bool = false

@description('Git repository configuration (if enabled)')
param gitConfiguration object = {}

// Database Migration Service Parameters
@description('Database Migration Service name')
param dmsName string = 'dms-migration-${uniqueSuffix}'

@description('Database Migration Service SKU')
@allowed(['Standard_1vCore', 'Standard_2vCores', 'Standard_4vCores'])
param dmsSku string = 'Standard_4vCores'

// Storage Parameters
@description('Storage account name for Airflow DAGs and artifacts')
param storageAccountName string = 'st${replace(uniqueSuffix, '-', '')}migration'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountSku string = 'Standard_LRS'

// Log Analytics Parameters
@description('Log Analytics workspace name')
param logAnalyticsName string = 'law-migration-${uniqueSuffix}'

@description('Log Analytics workspace SKU')
@allowed(['PerGB2018', 'Free', 'Standalone'])
param logAnalyticsSku string = 'PerGB2018'

@description('Log Analytics data retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

// Monitoring Parameters
@description('Enable Azure Monitor alerts')
param enableAlerts bool = true

@description('Notification email for alerts')
param alertNotificationEmail string = 'admin@company.com'

@description('Action group name for alerts')
param actionGroupName string = 'ag-migration-${uniqueSuffix}'

// Network Parameters
@description('Enable private endpoints for storage')
param enablePrivateEndpoints bool = false

@description('Virtual network resource ID for private endpoints')
param vnetResourceId string = ''

@description('Subnet resource ID for private endpoints')
param subnetResourceId string = ''

// ===================================================================================
// VARIABLES
// ===================================================================================

var containerNames = [
  'airflow-dags'
  'migration-artifacts'
  'migration-logs'
  'configuration'
]

var alertRules = [
  {
    name: 'migration-failure-alert'
    description: 'Alert when database migration errors occur'
    severity: 1
    condition: 'count static.microsoft.datamigration/services.MigrationErrors > 0'
    windowSize: 'PT5M'
    evaluationFrequency: 'PT1M'
  }
  {
    name: 'long-migration-alert'
    description: 'Alert when migration duration exceeds 1 hour'
    severity: 2
    condition: 'average static.microsoft.datamigration/services.MigrationDuration > 3600'
    windowSize: 'PT15M'
    evaluationFrequency: 'PT5M'
  }
  {
    name: 'high-cpu-alert'
    description: 'Alert when DMS CPU usage is high'
    severity: 2
    condition: 'average static.microsoft.datamigration/services.CpuPercent > 80'
    windowSize: 'PT10M'
    evaluationFrequency: 'PT5M'
  }
]

// ===================================================================================
// RESOURCES
// ===================================================================================

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsSku
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

// Storage Account for Airflow and Migration Artifacts
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: enablePrivateEndpoints ? 'Disabled' : 'Enabled'
    allowCrossTenantReplication: false
    isSftpEnabled: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    isHnsEnabled: false
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: enablePrivateEndpoints ? 'Deny' : 'Allow'
    }
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
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

// Storage Blob Services
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-04-01' = {
  parent: storageAccount
  name: 'default'
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
      allowPermanentDelete: false
      enabled: true
      days: 7
    }
    isVersioningEnabled: false
  }
}

// Storage Containers
resource storageContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-04-01' = [for containerName in containerNames: {
  parent: blobServices
  name: containerName
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}]

// Azure Data Factory
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    repoConfiguration: enableGitIntegration ? gitConfiguration : null
    globalParameters: {}
    encryption: {
      identity: {
        userAssignedIdentity: null
      }
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Data Factory Managed Virtual Network (if enabled)
resource managedVirtualNetwork 'Microsoft.DataFactory/factories/managedVirtualNetworks@2018-06-01' = if (enableManagedVNet) {
  parent: dataFactory
  name: 'default'
  properties: {}
}

// Self-hosted Integration Runtime
resource integrationRuntime 'Microsoft.DataFactory/factories/integrationRuntimes@2018-06-01' = {
  parent: dataFactory
  name: 'OnPremisesIR'
  properties: {
    type: 'SelfHosted'
    description: 'Self-hosted Integration Runtime for on-premises connectivity'
    typeProperties: {}
  }
}

// Linked Service for Storage Account
resource storageLinkedService 'Microsoft.DataFactory/factories/linkedServices@2018-06-01' = {
  parent: dataFactory
  name: 'AirflowStorage'
  properties: {
    type: 'AzureBlobStorage'
    connectVia: {
      referenceName: integrationRuntime.name
      type: 'IntegrationRuntimeReference'
    }
    description: 'Azure Blob Storage for Airflow DAGs and artifacts'
    typeProperties: {
      connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    }
  }
}

// Database Migration Service
resource databaseMigrationService 'Microsoft.DataMigration/services@2022-03-30-preview' = {
  name: dmsName
  location: location
  tags: tags
  sku: {
    name: dmsSku
  }
  properties: {
    virtualSubnetId: enablePrivateEndpoints && !empty(subnetResourceId) ? subnetResourceId : null
    publicKey: null
  }
}

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (enableAlerts) {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'migration'
    enabled: true
    emailReceivers: [
      {
        name: 'migration-team'
        emailAddress: alertNotificationEmail
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

// Metric Alert Rules
resource metricAlerts 'Microsoft.Insights/metricAlerts@2018-03-01' = [for (alertRule, i) in alertRules: if (enableAlerts) {
  name: '${alertRule.name}-${uniqueSuffix}'
  location: 'global'
  tags: tags
  properties: {
    description: alertRule.description
    severity: alertRule.severity
    enabled: true
    scopes: [
      databaseMigrationService.id
    ]
    evaluationFrequency: alertRule.evaluationFrequency
    windowSize: alertRule.windowSize
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: contains(alertRule.condition, '> ') ? int(split(alertRule.condition, '> ')[1]) : 0
          name: 'Metric1'
          metricNamespace: 'Microsoft.DataMigration/services'
          metricName: contains(alertRule.condition, 'MigrationErrors') ? 'MigrationErrors' : contains(alertRule.condition, 'MigrationDuration') ? 'MigrationDuration' : 'CpuPercent'
          operator: contains(alertRule.condition, 'count') ? 'GreaterThan' : 'GreaterThan'
          timeAggregation: contains(alertRule.condition, 'count') ? 'Count' : contains(alertRule.condition, 'average') ? 'Average' : 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    targetResourceType: 'Microsoft.DataMigration/services'
    targetResourceRegion: location
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
  }
}]

// Diagnostic Settings for Data Factory
resource dataFactoryDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'adf-diagnostics'
  scope: dataFactory
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Diagnostic Settings for Database Migration Service
resource dmsDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'dms-diagnostics'
  scope: databaseMigrationService
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Diagnostic Settings for Storage Account
resource storageDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'storage-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Role Assignment: Data Factory Managed Identity -> Storage Blob Data Contributor
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, dataFactory.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: dataFactory.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Private Endpoint for Storage Account (if enabled)
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = if (enablePrivateEndpoints && !empty(subnetResourceId)) {
  name: '${storageAccountName}-blob-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetResourceId
    }
    privateLinkServiceConnections: [
      {
        name: '${storageAccountName}-blob-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

// ===================================================================================
// OUTPUTS
// ===================================================================================

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Azure Data Factory name')
output dataFactoryName string = dataFactory.name

@description('Azure Data Factory resource ID')
output dataFactoryId string = dataFactory.id

@description('Azure Data Factory managed identity principal ID')
output dataFactoryPrincipalId string = dataFactory.identity.principalId

@description('Integration Runtime name')
output integrationRuntimeName string = integrationRuntime.name

@description('Integration Runtime authentication key')
output integrationRuntimeAuthKey string = integrationRuntime.listAuthKeys().authKey1

@description('Database Migration Service name')
output dmsName string = databaseMigrationService.name

@description('Database Migration Service resource ID')
output dmsId string = databaseMigrationService.id

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Storage Account resource ID')
output storageAccountId string = storageAccount.id

@description('Storage Account primary key')
@secure()
output storageAccountKey string = storageAccount.listKeys().keys[0].value

@description('Storage Account connection string')
@secure()
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace resource ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics workspace customer ID')
output logAnalyticsCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('Action Group resource ID')
output actionGroupId string = enableAlerts ? actionGroup.id : ''

@description('Storage container names')
output containerNames array = containerNames

@description('Airflow DAG upload command')
output airflowDagUploadCommand string = 'az storage blob upload --container-name airflow-dags --file <dag-file> --name <dag-name> --account-name ${storageAccount.name} --account-key <storage-key>'

@description('Data Factory Studio URL')
output dataFactoryStudioUrl string = 'https://adf.azure.com/en/home?factory=%2Fsubscriptions%2F${subscription().subscriptionId}%2FresourceGroups%2F${resourceGroup().name}%2Fproviders%2FMicrosoft.DataFactory%2Ffactories%2F${dataFactory.name}'

@description('Next steps for setup completion')
output nextSteps array = [
  'Install Integration Runtime on on-premises server using the authentication key'
  'Configure linked services for your on-premises SQL Server instances'
  'Set up Workflow Orchestration Manager in Data Factory Studio'
  'Upload Airflow DAGs to the airflow-dags storage container'
  'Configure database connection strings in Data Factory'
  'Test connectivity between on-premises and Azure services'
  'Create migration projects in Database Migration Service'
  'Monitor migration progress through Azure Monitor dashboards'
]