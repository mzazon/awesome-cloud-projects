@description('Deployment configuration for Hybrid PostgreSQL Database Replication')
param deploymentConfig object = {
  environment: 'dev'
  location: 'eastus'
  projectName: 'hybrid-postgres'
  tags: {
    environment: 'dev'
    project: 'hybrid-postgres-replication'
    costCenter: 'it-operations'
  }
}

@description('PostgreSQL configuration parameters')
param postgresConfig object = {
  administratorLogin: 'pgadmin'
  administratorPassword: 'P@ssw0rd123!'
  skuName: 'Standard_D2ds_v4'
  storageSizeGB: 128
  version: '14'
  backupRetentionDays: 7
  geoRedundantBackup: false
  highAvailability: false
}

@description('Data Factory configuration parameters')
param dataFactoryConfig object = {
  managedVirtualNetworkEnabled: false
  publicNetworkAccess: true
  replicationSchedule: {
    frequency: 'Hour'
    interval: 1
    startTime: '2024-01-01T00:00:00Z'
  }
}

@description('Event Grid configuration parameters')
param eventGridConfig object = {
  inputSchema: 'EventGridSchema'
  publicNetworkAccess: 'Enabled'
  localAuthDisabled: false
}

@description('Monitoring configuration parameters')
param monitoringConfig object = {
  workspaceRetentionInDays: 30
  enableApplicationInsights: true
  enableDiagnostics: true
  alertThresholds: {
    replicationLagSeconds: 300
    dataFactoryFailureCount: 3
  }
}

@description('Network security configuration')
param networkConfig object = {
  allowAzureServices: true
  allowPublicAccess: true
  trustedServices: true
}

// Variables for resource naming
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var postgresServerName = '${deploymentConfig.projectName}-pg-${uniqueSuffix}'
var dataFactoryName = '${deploymentConfig.projectName}-adf-${uniqueSuffix}'
var eventGridTopicName = '${deploymentConfig.projectName}-eg-${uniqueSuffix}'
var keyVaultName = '${deploymentConfig.projectName}-kv-${uniqueSuffix}'
var workspaceName = '${deploymentConfig.projectName}-law-${uniqueSuffix}'
var applicationInsightsName = '${deploymentConfig.projectName}-ai-${uniqueSuffix}'
var managedIdentityName = '${deploymentConfig.projectName}-mi-${uniqueSuffix}'

// Azure Database for PostgreSQL Flexible Server
resource postgresServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: postgresServerName
  location: deploymentConfig.location
  tags: deploymentConfig.tags
  sku: {
    name: postgresConfig.skuName
    tier: 'GeneralPurpose'
  }
  properties: {
    administratorLogin: postgresConfig.administratorLogin
    administratorLoginPassword: postgresConfig.administratorPassword
    version: postgresConfig.version
    storage: {
      storageSizeGB: postgresConfig.storageSizeGB
      iops: 3000
      tier: 'P30'
    }
    backup: {
      backupRetentionDays: postgresConfig.backupRetentionDays
      geoRedundantBackup: postgresConfig.geoRedundantBackup ? 'Enabled' : 'Disabled'
    }
    network: {
      publicNetworkAccess: networkConfig.allowPublicAccess ? 'Enabled' : 'Disabled'
    }
    highAvailability: {
      mode: postgresConfig.highAvailability ? 'ZoneRedundant' : 'Disabled'
    }
    maintenanceWindow: {
      customWindow: 'Enabled'
      dayOfWeek: 0
      startHour: 2
      startMinute: 0
    }
  }
}

// PostgreSQL Server Configuration - Enable logical replication
resource postgresConfig_walLevel 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-06-01-preview' = {
  name: 'wal_level'
  parent: postgresServer
  properties: {
    value: 'logical'
    source: 'user-override'
  }
}

resource postgresConfig_maxWalSenders 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-06-01-preview' = {
  name: 'max_wal_senders'
  parent: postgresServer
  properties: {
    value: '10'
    source: 'user-override'
  }
}

resource postgresConfig_maxReplicationSlots 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-06-01-preview' = {
  name: 'max_replication_slots'
  parent: postgresServer
  properties: {
    value: '10'
    source: 'user-override'
  }
}

// PostgreSQL Firewall Rules
resource postgresFirewallAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-06-01-preview' = if (networkConfig.allowAzureServices) {
  name: 'AllowAzureServices'
  parent: postgresServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource postgresFirewallAll 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-06-01-preview' = if (networkConfig.allowPublicAccess) {
  name: 'AllowAllIPs'
  parent: postgresServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

// Managed Identity for Data Factory
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: deploymentConfig.location
  tags: deploymentConfig.tags
}

// Key Vault for secure credential storage
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: deploymentConfig.location
  tags: deploymentConfig.tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    purgeProtectionEnabled: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
    accessPolicies: []
  }
}

// Store PostgreSQL credentials in Key Vault
resource kvSecretPgPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'postgres-password'
  parent: keyVault
  properties: {
    value: postgresConfig.administratorPassword
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

resource kvSecretPgConnectionString 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'postgres-connection-string'
  parent: keyVault
  properties: {
    value: 'Server=${postgresServer.properties.fullyQualifiedDomainName};Database=postgres;Port=5432;UID=${postgresConfig.administratorLogin};Password=${postgresConfig.administratorPassword};SSL Mode=Require;'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: deploymentConfig.location
  tags: deploymentConfig.tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: monitoringConfig.workspaceRetentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights for application monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (monitoringConfig.enableApplicationInsights) {
  name: applicationInsightsName
  location: deploymentConfig.location
  tags: deploymentConfig.tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Data Factory
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: deploymentConfig.location
  tags: deploymentConfig.tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    publicNetworkAccess: dataFactoryConfig.publicNetworkAccess ? 'Enabled' : 'Disabled'
    managedVirtualNetworkSettings: dataFactoryConfig.managedVirtualNetworkEnabled ? {
      preventDataExfiltration: true
    } : null
  }
}

// Data Factory Linked Service for PostgreSQL
resource adfLinkedServicePostgres 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  name: 'AzurePostgreSQLLinkedService'
  parent: dataFactory
  properties: {
    type: 'AzurePostgreSql'
    typeProperties: {
      connectionString: {
        type: 'AzureKeyVaultSecret'
        store: {
          referenceName: 'KeyVaultLinkedService'
          type: 'LinkedServiceReference'
        }
        secretName: 'postgres-connection-string'
      }
    }
  }
  dependsOn: [
    adfLinkedServiceKeyVault
  ]
}

// Data Factory Linked Service for Key Vault
resource adfLinkedServiceKeyVault 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  name: 'KeyVaultLinkedService'
  parent: dataFactory
  properties: {
    type: 'AzureKeyVault'
    typeProperties: {
      baseUrl: keyVault.properties.vaultUri
    }
  }
}

// Data Factory Pipeline for PostgreSQL Replication
resource adfPipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  name: 'HybridPostgreSQLReplication'
  parent: dataFactory
  properties: {
    description: 'Pipeline for replicating data between Arc-enabled PostgreSQL and Azure Database for PostgreSQL'
    activities: [
      {
        name: 'IncrementalCopyActivity'
        type: 'Copy'
        dependsOn: []
        policy: {
          timeout: '0.12:00:00'
          retry: 3
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          source: {
            type: 'PostgreSqlSource'
            query: 'SELECT * FROM public.replicated_tables WHERE last_modified > \'@{pipeline().parameters.lastSyncTime}\''
            queryTimeout: '02:00:00'
          }
          sink: {
            type: 'AzurePostgreSqlSink'
            writeBatchSize: 10000
            writeBatchTimeout: '00:30:00'
            sqlWriterUseTableLock: false
            writeBehavior: 'upsert'
            upsertSettings: {
              useTempDB: false
              keys: [
                'id'
              ]
            }
          }
          enableStaging: false
          validateDataConsistency: true
          logSettings: {
            enableCopyActivityLog: true
            copyActivityLogSettings: {
              logLevel: 'Info'
              enableReliableLogging: true
            }
          }
        }
        inputs: [
          {
            referenceName: 'ArcPostgreSQLDataset'
            type: 'DatasetReference'
          }
        ]
        outputs: [
          {
            referenceName: 'AzurePostgreSQLDataset'
            type: 'DatasetReference'
          }
        ]
      }
    ]
    parameters: {
      lastSyncTime: {
        type: 'string'
        defaultValue: '2024-01-01T00:00:00Z'
      }
      tableName: {
        type: 'string'
        defaultValue: 'replicated_tables'
      }
    }
    annotations: []
  }
  dependsOn: [
    adfLinkedServicePostgres
  ]
}

// Data Factory Dataset for Azure PostgreSQL
resource adfDatasetAzurePostgres 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  name: 'AzurePostgreSQLDataset'
  parent: dataFactory
  properties: {
    type: 'AzurePostgreSqlTable'
    linkedServiceName: {
      referenceName: 'AzurePostgreSQLLinkedService'
      type: 'LinkedServiceReference'
    }
    typeProperties: {
      tableName: 'replicated_tables'
      schema: 'public'
    }
    annotations: []
  }
  dependsOn: [
    adfLinkedServicePostgres
  ]
}

// Data Factory Dataset for Arc PostgreSQL (placeholder - requires runtime configuration)
resource adfDatasetArcPostgres 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  name: 'ArcPostgreSQLDataset'
  parent: dataFactory
  properties: {
    type: 'PostgreSqlTable'
    linkedServiceName: {
      referenceName: 'ArcPostgreSQLLinkedService'
      type: 'LinkedServiceReference'
    }
    typeProperties: {
      tableName: 'replicated_tables'
      schema: 'public'
    }
    annotations: []
  }
  dependsOn: [
    adfLinkedServiceArcPostgres
  ]
}

// Data Factory Linked Service for Arc PostgreSQL (placeholder - requires runtime configuration)
resource adfLinkedServiceArcPostgres 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  name: 'ArcPostgreSQLLinkedService'
  parent: dataFactory
  properties: {
    type: 'PostgreSql'
    typeProperties: {
      connectionString: {
        type: 'AzureKeyVaultSecret'
        store: {
          referenceName: 'KeyVaultLinkedService'
          type: 'LinkedServiceReference'
        }
        secretName: 'arc-postgres-connection-string'
      }
    }
    annotations: []
  }
  dependsOn: [
    adfLinkedServiceKeyVault
  ]
}

// Event Grid Topic for change notifications
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: deploymentConfig.location
  tags: deploymentConfig.tags
  properties: {
    inputSchema: eventGridConfig.inputSchema
    publicNetworkAccess: eventGridConfig.publicNetworkAccess
    localAuthDisabled: eventGridConfig.localAuthDisabled
  }
}

// Event Grid System Topic for Data Factory events
resource eventGridSystemTopic 'Microsoft.EventGrid/systemTopics@2023-12-15-preview' = {
  name: '${dataFactoryName}-system-topic'
  location: deploymentConfig.location
  tags: deploymentConfig.tags
  properties: {
    source: dataFactory.id
    topicType: 'Microsoft.DataFactory.Factories'
  }
}

// Event Grid Subscription for Data Factory pipeline failures
resource eventGridSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2023-12-15-preview' = {
  name: 'pipeline-failure-subscription'
  parent: eventGridSystemTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://example.com/webhook' // Replace with actual webhook URL
        deliveryAttributeMappings: []
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.DataFactory.PipelineRunFailed'
      ]
      enableAdvancedFilteringOnArrays: false
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
  }
}

// Data Factory Trigger for scheduled replication
resource adfTriggerSchedule 'Microsoft.DataFactory/factories/triggers@2018-06-01' = {
  name: 'ReplicationScheduleTrigger'
  parent: dataFactory
  properties: {
    type: 'ScheduleTrigger'
    typeProperties: {
      recurrence: {
        frequency: dataFactoryConfig.replicationSchedule.frequency
        interval: dataFactoryConfig.replicationSchedule.interval
        startTime: dataFactoryConfig.replicationSchedule.startTime
        timeZone: 'UTC'
      }
    }
    pipelines: [
      {
        pipelineReference: {
          referenceName: 'HybridPostgreSQLReplication'
          type: 'PipelineReference'
        }
        parameters: {
          lastSyncTime: '@trigger().scheduledTime'
        }
      }
    ]
  }
  dependsOn: [
    adfPipeline
  ]
}

// PostgreSQL Diagnostic Settings
resource postgresqlDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (monitoringConfig.enableDiagnostics) {
  name: 'postgresql-diagnostics'
  scope: postgresServer
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
  }
}

// Data Factory Diagnostic Settings
resource dataFactoryDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (monitoringConfig.enableDiagnostics) {
  name: 'datafactory-diagnostics'
  scope: dataFactory
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
  }
}

// Alert Rule for Replication Lag
resource alertReplicationLag 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-replication-lag'
  location: 'global'
  tags: deploymentConfig.tags
  properties: {
    description: 'Alert when PostgreSQL replication lag exceeds threshold'
    severity: 2
    enabled: true
    scopes: [
      postgresServer.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ReplicationLag'
          metricName: 'replication_lag'
          metricNamespace: 'Microsoft.DBforPostgreSQL/flexibleServers'
          operator: 'GreaterThan'
          threshold: monitoringConfig.alertThresholds.replicationLagSeconds
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

// Alert Rule for Data Factory Pipeline Failures
resource alertPipelineFailures 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-pipeline-failures'
  location: 'global'
  tags: deploymentConfig.tags
  properties: {
    description: 'Alert when Data Factory pipeline failures exceed threshold'
    severity: 1
    enabled: true
    scopes: [
      dataFactory.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'PipelineFailures'
          metricName: 'PipelineFailedRuns'
          metricNamespace: 'Microsoft.DataFactory/factories'
          operator: 'GreaterThan'
          threshold: monitoringConfig.alertThresholds.dataFactoryFailureCount
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

// Role Assignment for Data Factory to access Key Vault
resource roleAssignmentDataFactoryKeyVault 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataFactory.id, keyVault.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for Data Factory to access PostgreSQL
resource roleAssignmentDataFactoryPostgres 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataFactory.id, postgresServer.id, 'PostgreSQL Contributor')
  scope: postgresServer
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output postgresServerName string = postgresServer.name
output postgresServerFqdn string = postgresServer.properties.fullyQualifiedDomainName
output postgresAdminLogin string = postgresConfig.administratorLogin
output dataFactoryName string = dataFactory.name
output dataFactoryId string = dataFactory.id
output eventGridTopicName string = eventGridTopic.name
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output applicationInsightsName string = monitoringConfig.enableApplicationInsights ? applicationInsights.name : ''
output applicationInsightsConnectionString string = monitoringConfig.enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
output managedIdentityName string = managedIdentity.name
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output managedIdentityClientId string = managedIdentity.properties.clientId
output resourceGroupName string = resourceGroup().name
output subscriptionId string = subscription().subscriptionId
output deploymentLocation string = deploymentConfig.location