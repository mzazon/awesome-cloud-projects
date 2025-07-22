@description('The name of the environment (e.g., dev, staging, prod)')
param environmentName string = 'dev'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('A unique suffix to append to resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('The name of the Data Factory instance')
param dataFactoryName string = 'adf-env-pipeline-${uniqueSuffix}'

@description('The name of the storage account for data lake')
param storageAccountName string = 'stenvdata${uniqueSuffix}'

@description('The name of the Function App for data transformation')
param functionAppName string = 'func-env-transform-${uniqueSuffix}'

@description('The name of the Log Analytics workspace')
param logAnalyticsName string = 'log-env-monitor-${uniqueSuffix}'

@description('The name of the Application Insights instance')
param appInsightsName string = 'ai-env-pipeline-${uniqueSuffix}'

@description('The SKU for the storage account')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('The SKU for the Log Analytics workspace')
@allowed([
  'PerGB2018'
  'Free'
  'Standalone'
  'PerNode'
  'Standard'
  'Premium'
])
param logAnalyticsSku string = 'PerGB2018'

@description('Retention period for logs in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 90

@description('Email address for alert notifications')
param alertEmail string

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'environmental-data'
  environment: environmentName
  project: 'sustainability-pipeline'
  managedBy: 'bicep'
}

// Variables for resource naming and configuration
var containerNames = [
  'environmental-data'
  'processed-data'
  'archive-data'
  'temp-data'
]

var alertActionGroupName = 'ag-environmental-alerts-${uniqueSuffix}'
var keyVaultName = 'kv-env-pipeline-${uniqueSuffix}'
var servicePlanName = 'asp-env-functions-${uniqueSuffix}'

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsSku
    }
    retentionInDays: logRetentionDays
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account with Data Lake Gen2 capabilities
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
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
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    isHnsEnabled: true // Enable hierarchical namespace for Data Lake Gen2
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
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

// Blob containers for environmental data
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
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
  }
}

// Create containers for different data stages
resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for containerName in containerNames: {
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

// Key Vault for storing secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    enabledForDeployment: false
    enabledForTemplateDeployment: false
    enabledForDiskEncryption: false
    tenantId: tenant().tenantId
    accessPolicies: []
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
  }
}

// Store storage account connection string in Key Vault
resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-connection-string'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
  }
}

// App Service Plan for Azure Functions
resource servicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: servicePlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true // Linux
  }
}

// Azure Function App for data transformation
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: servicePlan.id
    reserved: true
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'Python|3.11'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'LOG_ANALYTICS_WORKSPACE_ID'
          value: logAnalytics.properties.customerId
        }
        {
          name: 'ENVIRONMENT_NAME'
          value: environmentName
        }
      ]
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    containerSize: 1536
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Azure Data Factory
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    encryption: {
      identity: {
        userAssignedIdentity: null
      }
      keyName: null
      keyVersion: null
      vaultBaseUrl: null
    }
  }
}

// Data Factory Linked Service for Storage Account
resource storageLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: 'StorageLinkedService'
  properties: {
    type: 'AzureBlobStorage'
    typeProperties: {
      connectionString: {
        type: 'SecureString'
        value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
      }
    }
  }
}

// Data Factory Linked Service for Azure Functions
resource functionLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: 'FunctionLinkedService'
  properties: {
    type: 'AzureFunction'
    typeProperties: {
      functionAppUrl: 'https://${functionApp.properties.defaultHostName}'
      functionKey: {
        type: 'SecureString'
        value: 'dummy-key-placeholder'
      }
    }
  }
}

// Data Factory Dataset for Environmental Data
resource environmentalDataSet 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'EnvironmentalDataSet'
  properties: {
    type: 'DelimitedText'
    linkedServiceName: {
      referenceName: storageLinkedService.name
      type: 'LinkedServiceReference'
    }
    typeProperties: {
      location: {
        type: 'AzureBlobStorageLocation'
        container: 'environmental-data'
        fileName: '*.csv'
      }
      columnDelimiter: ','
      rowDelimiter: '\n'
      firstRowAsHeader: true
      compressionCodec: 'none'
    }
    schema: [
      {
        name: 'timestamp'
        type: 'String'
      }
      {
        name: 'sensor_id'
        type: 'String'
      }
      {
        name: 'location'
        type: 'String'
      }
      {
        name: 'temperature'
        type: 'Decimal'
      }
      {
        name: 'humidity'
        type: 'Decimal'
      }
      {
        name: 'co2_level'
        type: 'Decimal'
      }
      {
        name: 'energy_consumption'
        type: 'Decimal'
      }
    ]
  }
}

// Data Factory Dataset for Processed Data
resource processedDataSet 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'ProcessedDataSet'
  properties: {
    type: 'DelimitedText'
    linkedServiceName: {
      referenceName: storageLinkedService.name
      type: 'LinkedServiceReference'
    }
    typeProperties: {
      location: {
        type: 'AzureBlobStorageLocation'
        container: 'processed-data'
        fileName: 'processed-environmental-data.csv'
      }
      columnDelimiter: ','
      rowDelimiter: '\n'
      firstRowAsHeader: true
      compressionCodec: 'none'
    }
  }
}

// Data Factory Pipeline for Environmental Data Processing
resource environmentalDataPipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  parent: dataFactory
  name: 'EnvironmentalDataPipeline'
  properties: {
    activities: [
      {
        name: 'CopyEnvironmentalData'
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
            type: 'DelimitedTextSource'
            storeSettings: {
              type: 'AzureBlobStorageReadSettings'
              recursive: true
              wildcardFolderPath: null
              wildcardFileName: '*.csv'
              enablePartitionDiscovery: false
            }
            formatSettings: {
              type: 'DelimitedTextReadSettings'
            }
          }
          sink: {
            type: 'DelimitedTextSink'
            storeSettings: {
              type: 'AzureBlobStorageWriteSettings'
            }
            formatSettings: {
              type: 'DelimitedTextWriteSettings'
              quoteAllText: false
              fileExtension: '.csv'
            }
          }
          enableStaging: false
          translator: {
            type: 'TabularTranslator'
            typeConversion: true
            typeConversionSettings: {
              allowDataTruncation: true
              treatBooleanAsNumber: false
            }
          }
        }
        inputs: [
          {
            referenceName: environmentalDataSet.name
            type: 'DatasetReference'
          }
        ]
        outputs: [
          {
            referenceName: processedDataSet.name
            type: 'DatasetReference'
          }
        ]
      }
      {
        name: 'ProcessEnvironmentalMetrics'
        type: 'AzureFunctionActivity'
        dependsOn: [
          {
            activity: 'CopyEnvironmentalData'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        policy: {
          timeout: '0.12:00:00'
          retry: 3
          retryIntervalInSeconds: 30
          secureOutput: false
          secureInput: false
        }
        userProperties: []
        typeProperties: {
          functionName: 'ProcessEnvironmentalData'
          method: 'POST'
          body: {
            message: 'Environmental data processing request'
            timestamp: '@utcnow()'
            pipeline: '@pipeline().RunId'
          }
        }
        linkedServiceName: {
          referenceName: functionLinkedService.name
          type: 'LinkedServiceReference'
        }
      }
    ]
    parameters: {
      inputContainer: {
        type: 'string'
        defaultValue: 'environmental-data'
      }
      outputContainer: {
        type: 'string'
        defaultValue: 'processed-data'
      }
    }
    annotations: [
      'Environmental Data Processing'
    ]
  }
}

// Data Factory Trigger for Daily Execution
resource dailyTrigger 'Microsoft.DataFactory/factories/triggers@2018-06-01' = {
  parent: dataFactory
  name: 'DailyEnvironmentalDataTrigger'
  properties: {
    type: 'ScheduleTrigger'
    typeProperties: {
      recurrence: {
        frequency: 'Day'
        interval: 1
        startTime: '2024-01-01T06:00:00Z'
        timeZone: 'UTC'
      }
    }
    pipelines: [
      {
        pipelineReference: {
          referenceName: environmentalDataPipeline.name
          type: 'PipelineReference'
        }
        parameters: {}
      }
    ]
  }
}

// Action Group for Alert Notifications
resource alertActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: alertActionGroupName
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'EnvAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'admin'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
    eventHubReceivers: []
  }
}

// Metric Alert for Data Factory Pipeline Failures
resource pipelineFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'EnvironmentalPipelineFailures'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when environmental data pipeline fails'
    severity: 2
    enabled: true
    scopes: [
      dataFactory.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    targetResourceType: 'Microsoft.DataFactory/factories'
    targetResourceRegion: location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 0
          name: 'PipelineFailures'
          metricNamespace: 'Microsoft.DataFactory/factories'
          metricName: 'PipelineFailedRuns'
          operator: 'GreaterThan'
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: alertActionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// Metric Alert for Data Processing Delays
resource processingDelayAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'EnvironmentalDataProcessingDelay'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when environmental data processing is delayed'
    severity: 3
    enabled: true
    scopes: [
      dataFactory.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    targetResourceType: 'Microsoft.DataFactory/factories'
    targetResourceRegion: location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 1800
          name: 'ProcessingDelay'
          metricNamespace: 'Microsoft.DataFactory/factories'
          metricName: 'PipelineRunDuration'
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: alertActionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// Diagnostic Settings for Data Factory
resource dataFactoryDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'EnvironmentalDataFactoryDiagnostics'
  scope: dataFactory
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'PipelineRuns'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'ActivityRuns'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'TriggerRuns'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Diagnostic Settings for Storage Account
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'EnvironmentalStorageDiagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalytics.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'Capacity'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Diagnostic Settings for Function App
resource functionAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'EnvironmentalFunctionDiagnostics'
  scope: functionApp
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Role Assignment: Data Factory Managed Identity -> Storage Blob Data Contributor
resource dataFactoryStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(dataFactory.id, storageAccount.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: dataFactory.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment: Function App Managed Identity -> Storage Blob Data Contributor
resource functionAppStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(functionApp.id, storageAccount.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment: Function App Managed Identity -> Key Vault Secrets User
resource functionAppKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(functionApp.id, keyVault.id, '4633458b-17de-408a-b874-0445c86b69e6')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('The name of the created Data Factory')
output dataFactoryName string = dataFactory.name

@description('The name of the created Storage Account')
output storageAccountName string = storageAccount.name

@description('The name of the created Function App')
output functionAppName string = functionApp.name

@description('The name of the created Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalytics.name

@description('The resource ID of the Data Factory')
output dataFactoryId string = dataFactory.id

@description('The resource ID of the Storage Account')
output storageAccountId string = storageAccount.id

@description('The resource ID of the Function App')
output functionAppId string = functionApp.id

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalytics.id

@description('The Log Analytics workspace customer ID')
output logAnalyticsCustomerId string = logAnalytics.properties.customerId

@description('The Application Insights instrumentation key')
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('The Application Insights connection string')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('The Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The Function App default hostname')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The storage account primary endpoints')
output storageAccountEndpoints object = storageAccount.properties.primaryEndpoints

@description('The Data Factory managed identity principal ID')
output dataFactoryPrincipalId string = dataFactory.identity.principalId

@description('The Function App managed identity principal ID')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('The list of created container names')
output containerNames array = containerNames