// Azure Environmental Impact Dashboards with Sustainability Manager and Power BI
// This template deploys the core infrastructure for environmental impact tracking and reporting

targetScope = 'resourceGroup'

// ========== PARAMETERS ==========

@description('Environment name for resource naming and tagging')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environmentName string = 'dev'

@description('Primary location for resource deployment')
param location string = resourceGroup().location

@description('Project name used for resource naming')
@minLength(2)
@maxLength(10)
param projectName string = 'sustain'

@description('Resource owner tag value')
param resourceOwner string = 'SustainabilityTeam'

@description('Cost center tag value')
param costCenter string = 'Environmental'

@description('Storage account SKU for sustainability data')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Log Analytics workspace SKU')
@allowed([
  'Free'
  'PerNode'
  'PerGB2018'
  'Standalone'
])
param logAnalyticsWorkspaceSku string = 'PerGB2018'

@description('Function App hosting plan SKU')
@allowed([
  'Y1'
  'EP1'
  'EP2'
  'EP3'
])
param functionAppPlanSku string = 'Y1'

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Enable automated data refresh Logic App')
param enableDataRefresh bool = true

@description('Data refresh schedule (cron expression)')
param dataRefreshSchedule string = '0 0 6 * * *' // Daily at 6 AM

@description('Enable budget alerts for cost monitoring')
param enableBudgetAlerts bool = true

@description('Monthly budget threshold in USD')
param monthlyBudgetThreshold int = 500

@description('Budget alert email addresses')
param budgetAlertEmails array = []

@description('Enable advanced threat protection for storage')
param enableAdvancedThreatProtection bool = false

@description('Enable private endpoints for enhanced security')
param enablePrivateEndpoints bool = false

@description('Virtual network resource ID for private endpoints')
param vnetResourceId string = ''

@description('Subnet resource ID for private endpoints')
param subnetResourceId string = ''

// ========== VARIABLES ==========

var uniqueSuffix = uniqueString(resourceGroup().id)
var resourcePrefix = '${projectName}-${environmentName}'

// Resource names with unique suffixes
var storageAccountName = replace('${resourcePrefix}stor${uniqueSuffix}', '-', '')
var logAnalyticsWorkspaceName = '${resourcePrefix}-law-${uniqueSuffix}'
var applicationInsightsName = '${resourcePrefix}-ai-${uniqueSuffix}'
var keyVaultName = '${resourcePrefix}-kv-${uniqueSuffix}'
var functionAppName = '${resourcePrefix}-func-${uniqueSuffix}'
var functionAppPlanName = '${resourcePrefix}-asp-${uniqueSuffix}'
var dataFactoryName = '${resourcePrefix}-adf-${uniqueSuffix}'
var logicAppName = '${resourcePrefix}-logic-${uniqueSuffix}'

// Common tags for all resources
var commonTags = {
  Environment: environmentName
  Project: projectName
  Owner: resourceOwner
  CostCenter: costCenter
  Purpose: 'Sustainability'
  DeployedBy: 'Bicep'
  LastUpdated: utcNow('yyyy-MM-dd')
}

// Storage containers
var storageContainers = [
  {
    name: 'sustainability-data'
    publicAccess: 'None'
  }
  {
    name: 'emissions-calculations'
    publicAccess: 'None'
  }
  {
    name: 'power-bi-datasets'
    publicAccess: 'None'
  }
  {
    name: 'audit-logs'
    publicAccess: 'None'
  }
]

// ========== RESOURCES ==========

// Storage Account for sustainability data
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
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
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Blob services for the storage account
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    changeFeed: {
      enabled: true
      retentionInDays: 30
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 30
    }
    isVersioningEnabled: true
  }
}

// Storage containers for sustainability data
resource storageContainerResources 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for container in storageContainers: {
  parent: blobServices
  name: container.name
  properties: {
    publicAccess: container.publicAccess
  }
}]

// Log Analytics workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: logAnalyticsWorkspaceSku
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
  location: location
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Key Vault for secure credential storage
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: commonTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: false
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Data Factory for data ingestion
resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
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

// Function App hosting plan
resource functionAppPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: functionAppPlanName
  location: location
  tags: commonTags
  sku: {
    name: functionAppPlanSku
    tier: functionAppPlanSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  kind: 'functionapp'
  properties: {
    reserved: true // Required for Linux
  }
}

// Function App for emissions calculations
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: commonTags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionAppPlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
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
          value: enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'EMISSIONS_FACTOR_SOURCE'
          value: 'EPA'
        }
        {
          name: 'CALCULATION_METHOD'
          value: 'GHG_PROTOCOL'
        }
        {
          name: 'KEY_VAULT_URL'
          value: keyVault.properties.vaultUri
        }
      ]
    }
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}azure-webjobs-hosts'
          authentication: {
            type: 'StorageAccountConnectionString'
            storageAccountConnectionStringName: 'AzureWebJobsStorage'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 200
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'python'
        version: '3.11'
      }
    }
  }
}

// Logic App for automated data refresh
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = if (enableDataRefresh) {
  name: logicAppName
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        storageAccountName: {
          type: 'string'
          defaultValue: storageAccount.name
        }
        functionAppName: {
          type: 'string'
          defaultValue: functionApp.name
        }
      }
      triggers: {
        recurrence: {
          type: 'Recurrence'
          recurrence: {
            frequency: 'Day'
            interval: 1
            schedule: {
              hours: [
                6
              ]
              minutes: [
                0
              ]
            }
            timeZone: 'UTC'
          }
        }
      }
      actions: {
        'Check_Storage_Data': {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: 'https://${storageAccount.name}.blob.${environment().suffixes.storage}/sustainability-data'
            authentication: {
              type: 'ManagedServiceIdentity'
            }
          }
          runAfter: {}
        }
        'Trigger_Emissions_Calculation': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://${functionApp.properties.defaultHostName}/api/calculate-emissions'
            body: {
              source: 'automated-refresh'
              timestamp: '@{utcNow()}'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
            }
          }
          runAfter: {
            'Check_Storage_Data': [
              'Succeeded'
            ]
          }
        }
        'Update_Power_BI_Dataset': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://api.powerbi.com/v1.0/myorg/datasets/refresh'
            body: {
              notifyOption: 'NoNotification'
            }
            authentication: {
              type: 'ManagedServiceIdentity'
            }
          }
          runAfter: {
            'Trigger_Emissions_Calculation': [
              'Succeeded'
            ]
          }
        }
      }
    }
  }
}

// RBAC assignments for Function App
resource functionAppStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
  }
}

// RBAC assignments for Data Factory
resource dataFactoryStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, dataFactory.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    principalId: dataFactory.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
  }
}

// RBAC assignments for Logic App (if enabled)
resource logicAppStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableDataRefresh) {
  name: guid(storageAccount.id, logicApp.id, 'StorageBlobDataReader')
  scope: storageAccount
  properties: {
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1') // Storage Blob Data Reader
  }
}

// Key Vault access for Function App
resource functionAppKeyVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
  }
}

// Alert rules for monitoring
resource dataProcessingAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableApplicationInsights) {
  name: '${resourcePrefix}-data-processing-alert'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'Alert when function execution count exceeds threshold'
    severity: 2
    enabled: true
    scopes: [
      functionApp.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'FunctionExecutionCount'
          metricNamespace: 'Microsoft.Web/sites'
          metricName: 'FunctionExecutionCount'
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Total'
        }
      ]
    }
    actions: []
  }
}

// Budget alert (if enabled)
resource budgetAlert 'Microsoft.Consumption/budgets@2023-05-01' = if (enableBudgetAlerts && length(budgetAlertEmails) > 0) {
  name: '${resourcePrefix}-monthly-budget'
  properties: {
    timePeriod: {
      startDate: '2024-01-01'
      endDate: '2030-12-31'
    }
    timeGrain: 'Monthly'
    amount: monthlyBudgetThreshold
    category: 'Cost'
    notifications: {
      actual_80: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: budgetAlertEmails
        contactGroups: []
        contactRoles: []
      }
      forecasted_100: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: budgetAlertEmails
        contactGroups: []
        contactRoles: []
      }
    }
    filter: {
      and: [
        {
          dimensions: {
            name: 'ResourceGroupName'
            operator: 'In'
            values: [
              resourceGroup().name
            ]
          }
        }
      ]
    }
  }
}

// ========== OUTPUTS ==========

@description('Storage account name for sustainability data')
output storageAccountName string = storageAccount.name

@description('Storage account primary endpoint for blob storage')
output storageAccountBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Application Insights instrumentation key')
@secure()
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Function App name for emissions calculations')
output functionAppName string = functionApp.name

@description('Function App default hostname')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('Data Factory name for data ingestion')
output dataFactoryName string = dataFactory.name

@description('Key Vault name for secure credential storage')
output keyVaultName string = keyVault.name

@description('Key Vault URI for secure credential storage')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Logic App name for automated data refresh')
output logicAppName string = enableDataRefresh ? logicApp.name : ''

@description('Resource group name containing all sustainability resources')
output resourceGroupName string = resourceGroup().name

@description('Common tags applied to all resources')
output commonTags object = commonTags

@description('Storage containers created for sustainability data')
output storageContainers array = [for container in storageContainers: container.name]

@description('Unique suffix used for resource naming')
output uniqueSuffix string = uniqueSuffix

@description('Primary location where resources are deployed')
output deploymentLocation string = location

@description('Environment name for the deployment')
output environmentName string = environmentName

@description('Project name for the deployment')
output projectName string = projectName