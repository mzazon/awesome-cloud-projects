// ================================================================
// Main Bicep template for Enterprise-Grade Multi-Database ETL Orchestration
// with Azure Data Factory and Azure Database for MySQL
// ================================================================

@description('The Azure region where all resources will be deployed')
param location string = resourceGroup().location

@description('Prefix for all resource names to ensure uniqueness')
param resourcePrefix string = 'etl'

@description('Environment name (dev, staging, prod)')
param environmentName string = 'dev'

@description('Administrator username for MySQL server')
@secure()
param mysqlAdminUsername string

@description('Administrator password for MySQL server')
@secure()
param mysqlAdminPassword string

@description('MySQL server SKU name')
param mysqlSkuName string = 'Standard_D2ds_v4'

@description('MySQL server tier')
@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param mysqlTier string = 'GeneralPurpose'

@description('MySQL server storage size in GB')
@minValue(20)
@maxValue(16384)
param mysqlStorageSize int = 128

@description('MySQL server version')
@allowed([
  '5.7'
  '8.0'
])
param mysqlVersion string = '8.0'

@description('Enable high availability for MySQL server')
param mysqlHighAvailability bool = true

@description('Primary availability zone for MySQL server')
param mysqlZone string = '1'

@description('Standby availability zone for MySQL server')
param mysqlStandbyZone string = '2'

@description('Tags to apply to all resources')
param tags object = {
  environment: environmentName
  project: 'etl-orchestration'
  cost-center: 'data-engineering'
}

@description('Log Analytics workspace retention period in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 90

@description('Enable soft delete for Key Vault')
param keyVaultSoftDeleteEnabled bool = true

@description('Enable purge protection for Key Vault')
param keyVaultPurgeProtectionEnabled bool = true

@description('Key Vault SKU')
@allowed([
  'standard'
  'premium'
])
param keyVaultSku string = 'standard'

// ================================================================
// Variables
// ================================================================

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var dataFactoryName = '${resourcePrefix}-adf-${uniqueSuffix}'
var mysqlServerName = '${resourcePrefix}-mysql-${uniqueSuffix}'
var keyVaultName = '${resourcePrefix}-kv-${uniqueSuffix}'
var logAnalyticsName = '${resourcePrefix}-la-${uniqueSuffix}'
var mysqlDatabaseName = 'consolidated_data'
var integrationRuntimeName = 'SelfHostedIR'

// ================================================================
// Azure Log Analytics Workspace
// ================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
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

// ================================================================
// Azure Key Vault
// ================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    enableSoftDelete: keyVaultSoftDeleteEnabled
    enablePurgeProtection: keyVaultPurgeProtectionEnabled
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForTemplateDeployment: false
    enabledForDiskEncryption: false
    accessPolicies: []
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Store MySQL admin credentials in Key Vault
resource mysqlAdminUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'mysql-admin-username'
  properties: {
    value: mysqlAdminUsername
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource mysqlAdminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'mysql-admin-password'
  properties: {
    value: mysqlAdminPassword
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// ================================================================
// Azure Database for MySQL Flexible Server
// ================================================================

resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2023-12-30' = {
  name: mysqlServerName
  location: location
  tags: tags
  sku: {
    name: mysqlSkuName
    tier: mysqlTier
  }
  properties: {
    administratorLogin: mysqlAdminUsername
    administratorLoginPassword: mysqlAdminPassword
    version: mysqlVersion
    storage: {
      storageSizeGB: mysqlStorageSize
      iops: 400
      autoGrow: 'Enabled'
      autoIoScaling: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Enabled'
    }
    highAvailability: mysqlHighAvailability ? {
      mode: 'ZoneRedundant'
      standbyAvailabilityZone: mysqlStandbyZone
    } : null
    maintenanceWindow: {
      customWindow: 'Enabled'
      dayOfWeek: 0
      startHour: 2
      startMinute: 0
    }
    availabilityZone: mysqlZone
  }
}

// Configure firewall rules for Azure services
resource mysqlFirewallRule 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2023-12-30' = {
  parent: mysqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Create target database for ETL operations
resource mysqlDatabase 'Microsoft.DBforMySQL/flexibleServers/databases@2023-12-30' = {
  parent: mysqlServer
  name: mysqlDatabaseName
  properties: {
    charset: 'utf8mb4'
    collation: 'utf8mb4_unicode_ci'
  }
}

// ================================================================
// Azure Data Factory
// ================================================================

resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    globalParameters: {
      environment: {
        type: 'string'
        value: environmentName
      }
      mysqlServerName: {
        type: 'string'
        value: mysqlServer.properties.fullyQualifiedDomainName
      }
      targetDatabaseName: {
        type: 'string'
        value: mysqlDatabaseName
      }
    }
  }
}

// Create Self-Hosted Integration Runtime
resource integrationRuntime 'Microsoft.DataFactory/factories/integrationRuntimes@2018-06-01' = {
  parent: dataFactory
  name: integrationRuntimeName
  properties: {
    type: 'SelfHosted'
    description: 'Self-hosted Integration Runtime for on-premises MySQL connectivity'
    typeProperties: {}
  }
}

// Create Azure Key Vault Linked Service
resource keyVaultLinkedService 'Microsoft.DataFactory/factories/linkedServices@2018-06-01' = {
  parent: dataFactory
  name: 'AzureKeyVaultLinkedService'
  properties: {
    type: 'AzureKeyVault'
    description: 'Azure Key Vault linked service for secure credential management'
    typeProperties: {
      baseUrl: keyVault.properties.vaultUri
    }
  }
}

// Create MySQL Source Linked Service
resource mysqlSourceLinkedService 'Microsoft.DataFactory/factories/linkedServices@2018-06-01' = {
  parent: dataFactory
  name: 'MySQLSourceLinkedService'
  properties: {
    type: 'MySql'
    description: 'On-premises MySQL source linked service'
    connectVia: {
      referenceName: integrationRuntime.name
      type: 'IntegrationRuntimeReference'
    }
    typeProperties: {
      connectionString: {
        type: 'AzureKeyVaultSecret'
        store: {
          referenceName: keyVaultLinkedService.name
          type: 'LinkedServiceReference'
        }
        secretName: 'mysql-source-connection-string'
      }
    }
  }
}

// Create MySQL Target Linked Service
resource mysqlTargetLinkedService 'Microsoft.DataFactory/factories/linkedServices@2018-06-01' = {
  parent: dataFactory
  name: 'MySQLTargetLinkedService'
  properties: {
    type: 'AzureMySql'
    description: 'Azure Database for MySQL target linked service'
    typeProperties: {
      connectionString: 'server=${mysqlServer.properties.fullyQualifiedDomainName};port=3306;database=${mysqlDatabaseName};uid=${mysqlAdminUsername};pwd=${mysqlAdminPassword};sslmode=required'
    }
  }
}

// Create MySQL Source Dataset
resource mysqlSourceDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'MySQLSourceDataset'
  properties: {
    type: 'MySqlTable'
    linkedServiceName: {
      referenceName: mysqlSourceLinkedService.name
      type: 'LinkedServiceReference'
    }
    typeProperties: {
      tableName: 'customers'
    }
    schema: []
  }
}

// Create MySQL Target Dataset
resource mysqlTargetDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'MySQLTargetDataset'
  properties: {
    type: 'AzureMySqlTable'
    linkedServiceName: {
      referenceName: mysqlTargetLinkedService.name
      type: 'LinkedServiceReference'
    }
    typeProperties: {
      tableName: 'customers'
    }
    schema: []
  }
}

// Create ETL Pipeline
resource etlPipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  parent: dataFactory
  name: 'MultiDatabaseETLPipeline'
  properties: {
    description: 'Enterprise ETL pipeline for multi-database orchestration'
    activities: [
      {
        name: 'CopyCustomerData'
        type: 'Copy'
        dependsOn: []
        policy: {
          timeout: '7.00:00:00'
          retry: 3
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          source: {
            type: 'MySqlSource'
            query: 'SELECT customer_id, customer_name, email, registration_date, last_login FROM customers WHERE last_modified >= DATE_SUB(NOW(), INTERVAL 1 DAY)'
          }
          sink: {
            type: 'AzureMySqlSink'
            writeBehavior: 'upsert'
            upsertSettings: {
              useTempDB: true
              keys: ['customer_id']
            }
          }
          enableStaging: false
          parallelCopies: 4
          dataIntegrationUnits: 8
          enableSkipIncompatibleRow: true
          logSettings: {
            enableCopyActivityLog: true
            copyActivityLogSettings: {
              logLevel: 'Warning'
              enableReliableLogging: true
            }
          }
        }
        inputs: [
          {
            referenceName: mysqlSourceDataset.name
            type: 'DatasetReference'
          }
        ]
        outputs: [
          {
            referenceName: mysqlTargetDataset.name
            type: 'DatasetReference'
          }
        ]
      }
      {
        name: 'ValidationActivity'
        type: 'Validation'
        dependsOn: [
          {
            activity: 'CopyCustomerData'
            dependencyConditions: ['Succeeded']
          }
        ]
        userProperties: []
        typeProperties: {
          dataset: {
            referenceName: mysqlTargetDataset.name
            type: 'DatasetReference'
          }
          timeout: '0.00:05:00'
          sleep: 10
          minimumSize: 1
        }
      }
    ]
    parameters: {
      sourceServer: {
        type: 'string'
        defaultValue: 'onprem-mysql.domain.com'
      }
      targetServer: {
        type: 'string'
        defaultValue: mysqlServer.properties.fullyQualifiedDomainName
      }
      batchSize: {
        type: 'int'
        defaultValue: 1000
      }
    }
    variables: {
      processedRecords: {
        type: 'Integer'
        defaultValue: 0
      }
    }
    folder: {
      name: 'ETL-Pipelines'
    }
    annotations: ['production', 'mysql', 'etl']
  }
}

// Create Daily ETL Trigger
resource dailyETLTrigger 'Microsoft.DataFactory/factories/triggers@2018-06-01' = {
  parent: dataFactory
  name: 'DailyETLTrigger'
  properties: {
    type: 'ScheduleTrigger'
    description: 'Daily ETL execution at 2 AM UTC'
    typeProperties: {
      recurrence: {
        frequency: 'Day'
        interval: 1
        startTime: '2025-01-01T02:00:00Z'
        timeZone: 'UTC'
        schedule: {
          hours: [2]
          minutes: [0]
        }
      }
    }
    pipelines: [
      {
        pipelineReference: {
          referenceName: etlPipeline.name
          type: 'PipelineReference'
        }
        parameters: {}
      }
    ]
  }
}

// ================================================================
// RBAC Assignments
// ================================================================

// Grant Data Factory managed identity access to Key Vault
resource dataFactoryKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, dataFactory.id, 'Key Vault Secrets User')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: dataFactory.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Data Factory managed identity access to MySQL server
resource dataFactoryMySQLRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: mysqlServer
  name: guid(mysqlServer.id, dataFactory.id, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: dataFactory.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ================================================================
// Diagnostic Settings
// ================================================================

// Data Factory diagnostic settings
resource dataFactoryDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: dataFactory
  name: 'DataFactoryDiagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'PipelineRuns'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
      {
        category: 'ActivityRuns'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
      {
        category: 'TriggerRuns'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
      {
        category: 'SandboxPipelineRuns'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
      {
        category: 'SandboxActivityRuns'
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

// MySQL server diagnostic settings
resource mysqlDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: mysqlServer
  name: 'MySQLDiagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'MySqlSlowLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
      {
        category: 'MySqlAuditLogs'
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

// ================================================================
// Monitoring and Alerting
// ================================================================

// Pipeline failure alert
resource pipelineFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'ETL-Pipeline-Failure-Alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when ETL pipeline fails'
    severity: 2
    enabled: true
    scopes: [
      dataFactory.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    targetResourceType: 'Microsoft.DataFactory/factories'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Pipeline failed runs'
          metricName: 'PipelineFailedRuns'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

// MySQL high CPU alert
resource mysqlHighCPUAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'MySQL-High-CPU-Alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when MySQL server CPU usage is high'
    severity: 3
    enabled: true
    scopes: [
      mysqlServer.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    targetResourceType: 'Microsoft.DBforMySQL/flexibleServers'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CPU percent'
          metricName: 'cpu_percent'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

// ================================================================
// Outputs
// ================================================================

@description('The name of the Data Factory instance')
output dataFactoryName string = dataFactory.name

@description('The resource ID of the Data Factory instance')
output dataFactoryId string = dataFactory.id

@description('The managed identity principal ID of the Data Factory')
output dataFactoryPrincipalId string = dataFactory.identity.principalId

@description('The name of the MySQL server')
output mysqlServerName string = mysqlServer.name

@description('The fully qualified domain name of the MySQL server')
output mysqlServerFQDN string = mysqlServer.properties.fullyQualifiedDomainName

@description('The resource ID of the MySQL server')
output mysqlServerId string = mysqlServer.id

@description('The name of the target database')
output mysqlDatabaseName string = mysqlDatabase.name

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The URI of the Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The resource ID of the Key Vault')
output keyVaultId string = keyVault.id

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The name of the Self-Hosted Integration Runtime')
output integrationRuntimeName string = integrationRuntime.name

@description('The name of the ETL pipeline')
output etlPipelineName string = etlPipeline.name

@description('The name of the daily ETL trigger')
output dailyETLTriggerName string = dailyETLTrigger.name

@description('Connection string template for applications')
output connectionStringTemplate string = 'server=${mysqlServer.properties.fullyQualifiedDomainName};port=3306;database=${mysqlDatabaseName};uid=${mysqlAdminUsername};pwd=<password>;sslmode=required'

@description('Data Factory Studio URL')
output dataFactoryStudioUrl string = 'https://adf.azure.com/en-us/home?factory=%2Fsubscriptions%2F${subscription().subscriptionId}%2FresourceGroups%2F${resourceGroup().name}%2Fproviders%2FMicrosoft.DataFactory%2Ffactories%2F${dataFactory.name}'

@description('Azure portal URL for MySQL server')
output mysqlServerPortalUrl string = 'https://portal.azure.com/#@${subscription().tenantId}/resource${mysqlServer.id}'

@description('Key Vault portal URL')
output keyVaultPortalUrl string = 'https://portal.azure.com/#@${subscription().tenantId}/resource${keyVault.id}'

@description('Log Analytics workspace portal URL')
output logAnalyticsPortalUrl string = 'https://portal.azure.com/#@${subscription().tenantId}/resource${logAnalyticsWorkspace.id}'