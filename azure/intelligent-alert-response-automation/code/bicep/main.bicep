// main.bicep - Intelligent Alert Response System with Azure Monitor Workbooks and Azure Functions
// This template deploys a complete intelligent alert response system with monitoring, automation, and notification capabilities

targetScope = 'resourceGroup'

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param resourceNameSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'intelligent-alerts'
  DeployedBy: 'bicep'
}

@description('Log Analytics workspace SKU')
@allowed(['PerGB2018', 'Free', 'Standalone', 'PerNode'])
param logAnalyticsWorkspaceSku string = 'PerGB2018'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Function App plan SKU')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppPlanSku string = 'Y1'

@description('Cosmos DB consistency level')
@allowed(['Session', 'Strong', 'ConsistentPrefix', 'BoundedStaleness', 'Eventual'])
param cosmosDbConsistencyLevel string = 'Session'

@description('Notification email address for testing')
param notificationEmail string = 'admin@example.com'

@description('Enable Application Insights')
param enableApplicationInsights bool = true

@description('Enable diagnostic settings')
param enableDiagnostics bool = true

// Variables
var storageAccountName = 'stintelligent${resourceNameSuffix}'
var functionAppName = 'func-alert-response-${resourceNameSuffix}'
var functionAppPlanName = 'plan-functions-${resourceNameSuffix}'
var eventGridTopicName = 'eg-alerts-${resourceNameSuffix}'
var logicAppName = 'logic-notifications-${resourceNameSuffix}'
var cosmosDbAccountName = 'cosmos-alertstate-${resourceNameSuffix}'
var keyVaultName = 'kv-alerts-${resourceNameSuffix}'
var logAnalyticsWorkspaceName = 'law-monitoring-${resourceNameSuffix}'
var applicationInsightsName = 'ai-alerts-${resourceNameSuffix}'
var workbookName = 'workbook-alerts-${resourceNameSuffix}'
var actionGroupName = 'ag-alert-responses-${resourceNameSuffix}'
var alertRuleName = 'alert-test-cpu-${resourceNameSuffix}'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsWorkspaceSku
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    networkAcls: {
      defaultAction: 'Allow'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Key Vault for secure configuration
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Cosmos DB Account for alert state management
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosDbAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    enableFreeTier: false
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: cosmosDbConsistencyLevel
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    publicNetworkAccess: 'Enabled'
    networkAclBypass: 'AzureServices'
    disableLocalAuth: false
    enableAnalyticalStorage: false
  }
}

// Cosmos DB Database
resource cosmosDbDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosDbAccount
  name: 'AlertDatabase'
  properties: {
    resource: {
      id: 'AlertDatabase'
    }
  }
}

// Cosmos DB Container for alert states
resource cosmosDbContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDbDatabase
  name: 'AlertStates'
  properties: {
    resource: {
      id: 'AlertStates'
      partitionKey: {
        paths: ['/alertId']
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/_etag/?'
          }
        ]
      }
      defaultTtl: -1
    }
  }
}

// Event Grid Topic
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: tags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// Function App Plan
resource functionAppPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: functionAppPlanName
  location: location
  tags: tags
  sku: {
    name: functionAppPlanSku
    tier: functionAppPlanSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  kind: 'functionapp'
  properties: {
    reserved: true // Linux
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionAppPlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
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
          name: 'COSMOS_DB_CONNECTION_STRING'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/cosmos-connection/)'
        }
        {
          name: 'EVENT_GRID_ENDPOINT'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EVENT_GRID_KEY'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/eventgrid-key/)'
        }
        {
          name: 'LOG_ANALYTICS_WORKSPACE_ID'
          value: logAnalyticsWorkspace.properties.customerId
        }
        {
          name: 'KEY_VAULT_URL'
          value: keyVault.properties.vaultUri
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
  }
}

// Logic App for notification orchestration
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                alertId: {
                  type: 'string'
                }
                severity: {
                  type: 'string'
                }
                resourceId: {
                  type: 'string'
                }
                alertContext: {
                  type: 'object'
                }
                timestamp: {
                  type: 'string'
                }
              }
              required: ['alertId', 'severity']
            }
          }
        }
      }
      actions: {
        Initialize_Response: {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'notificationSent'
                type: 'boolean'
                value: true
              }
            ]
          }
        }
        Condition_Check_Severity: {
          type: 'If'
          expression: {
            or: [
              {
                equals: [
                  '@triggerBody()?[\'severity\']'
                  'high'
                ]
              }
              {
                equals: [
                  '@triggerBody()?[\'severity\']'
                  'critical'
                ]
              }
            ]
          }
          actions: {
            Send_High_Priority_Notification: {
              type: 'Http'
              inputs: {
                method: 'POST'
                uri: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
                headers: {
                  'Content-Type': 'application/json'
                }
                body: {
                  text: 'High Priority Alert: @{triggerBody()?[\'alertId\']} - Severity: @{triggerBody()?[\'severity\']}'
                  channel: '#alerts'
                }
              }
            }
          }
          else: {
            actions: {
              Send_Normal_Notification: {
                type: 'Http'
                inputs: {
                  method: 'POST'
                  uri: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
                  headers: {
                    'Content-Type': 'application/json'
                  }
                  body: {
                    text: 'Alert: @{triggerBody()?[\'alertId\']} - Severity: @{triggerBody()?[\'severity\']}'
                    channel: '#monitoring'
                  }
                }
              }
            }
          }
        }
        Response: {
          type: 'Response'
          inputs: {
            statusCode: 200
            body: {
              message: 'Alert notification processed successfully'
              alertId: '@{triggerBody()?[\'alertId\']}'
              timestamp: '@{utcNow()}'
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {}
  }
}

// Action Group for alert notifications
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'AlertResp'
    enabled: true
    emailReceivers: [
      {
        name: 'NotificationEmail'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ]
    webhookReceivers: [
      {
        name: 'EventGridWebhook'
        serviceUri: eventGridTopic.properties.endpoint
        useCommonAlertSchema: true
      }
      {
        name: 'LogicAppWebhook'
        serviceUri: '${logicApp.properties.accessEndpoint}/triggers/manual/paths/invoke?api-version=2016-10-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=${listCallbackURL(resourceId('Microsoft.Logic/workflows/triggers', logicApp.name, 'manual'), '2019-05-01').value}'
        useCommonAlertSchema: true
      }
    ]
    azureFunctionReceivers: [
      {
        name: 'FunctionAppReceiver'
        functionAppResourceId: functionApp.id
        functionName: 'ProcessAlert'
        httpTriggerUrl: 'https://${functionApp.properties.defaultHostName}/api/ProcessAlert'
        useCommonAlertSchema: true
      }
    ]
  }
}

// Test Alert Rule for CPU monitoring
resource testAlertRule 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: alertRuleName
  location: 'Global'
  tags: tags
  properties: {
    description: 'Test alert rule for intelligent response system validation'
    severity: 2
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 80
          name: 'HighCPUUsage'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          metricName: 'Percentage CPU'
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {
          eventGridKey: eventGridTopic.listKeys().key1
        }
      }
    ]
  }
}

// Azure Monitor Workbook for alert dashboard
resource alertWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: workbookName
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Intelligent Alert Response Dashboard'
    category: 'workbook'
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        {
          type: 1
          content: {
            json: '# Intelligent Alert Response Dashboard\n\nThis workbook provides real-time insights into alert patterns, response effectiveness, and system health metrics for the intelligent alert response system.'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AlertsManagementResources\n| where type == "microsoft.alertsmanagement/alerts"\n| summarize AlertCount = count() by tostring(properties.severity)\n| order by AlertCount desc'
            size: 1
            title: 'Alert Count by Severity (Last 24 Hours)'
            queryType: 1
            resourceType: 'microsoft.resourcegraph/resources'
            visualization: 'piechart'
            graphSettings: {
              type: 0
              topContent: {
                columnMatch: 'AlertCount'
                formatter: 1
              }
              centerContent: {
                columnMatch: 'AlertCount'
                formatter: 1
                numberFormat: {
                  unit: 17
                  options: {
                    maximumSignificantDigits: 3
                    useGrouping: true
                  }
                }
              }
            }
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AlertsManagementResources\n| where type == "microsoft.alertsmanagement/alerts"\n| extend AlertTime = todatetime(properties.essentials.startDateTime)\n| where AlertTime > ago(24h)\n| summarize AlertCount = count() by bin(AlertTime, 1h)\n| order by AlertTime asc'
            size: 0
            title: 'Alert Trends (24 Hours)'
            queryType: 1
            resourceType: 'microsoft.resourcegraph/resources'
            visualization: 'timechart'
            graphSettings: {
              type: 0
              topContent: {
                columnMatch: 'AlertCount'
                formatter: 1
              }
            }
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AlertsManagementResources\n| where type == "microsoft.alertsmanagement/alerts"\n| extend ResourceType = tostring(split(properties.essentials.targetResourceType, "/")[-1])\n| summarize AlertCount = count() by ResourceType\n| order by AlertCount desc\n| take 10'
            size: 0
            title: 'Top 10 Resource Types by Alert Count'
            queryType: 1
            resourceType: 'microsoft.resourcegraph/resources'
            visualization: 'barchart'
            graphSettings: {
              type: 0
              topContent: {
                columnMatch: 'AlertCount'
                formatter: 1
              }
            }
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AlertsManagementResources\n| where type == "microsoft.alertsmanagement/alerts"\n| extend AlertState = tostring(properties.essentials.monitorCondition)\n| summarize AlertCount = count() by AlertState\n| order by AlertCount desc'
            size: 0
            title: 'Alert States Distribution'
            queryType: 1
            resourceType: 'microsoft.resourcegraph/resources'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'AlertCount'
                  formatter: 8
                  formatOptions: {
                    palette: 'blue'
                  }
                }
              ]
            }
          }
        }
        {
          type: 1
          content: {
            json: '## Response Metrics\n\nThe following section shows metrics related to alert response effectiveness and system performance.'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'traces\n| where cloud_RoleName == "${functionAppName}"\n| where message contains "Alert processed"\n| summarize ProcessedAlerts = count() by bin(timestamp, 1h)\n| order by timestamp desc'
            size: 0
            title: 'Alert Processing Rate'
            queryType: 0
            resourceType: 'microsoft.insights/components'
            visualization: 'linechart'
            graphSettings: {
              type: 0
              topContent: {
                columnMatch: 'ProcessedAlerts'
                formatter: 1
              }
            }
          }
        }
      ]
    })
    sourceId: logAnalyticsWorkspace.id
  }
}

// Role assignments for Function App
resource functionAppKeyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, keyVault.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppCosmosContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, cosmosDbAccount.id, 'Cosmos DB Contributor')
  scope: cosmosDbAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00000000-0000-0000-0000-000000000002') // Cosmos DB Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionAppEventGridContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, eventGridTopic.id, 'EventGrid Contributor')
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1e241071-0855-49ea-94dc-649edcd759de') // EventGrid Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignments for Logic App
resource logicAppKeyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logicApp.id, keyVault.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Event Grid Subscriptions
resource eventGridSubscriptionFunction 'Microsoft.EventGrid/topics/eventSubscriptions@2023-12-15-preview' = {
  name: 'alerts-to-function'
  parent: eventGridTopic
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/ProcessAlert'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.AlertManagement.Alert.Activated'
        'Microsoft.AlertManagement.Alert.Resolved'
      ]
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 10
      eventTimeToLiveInMinutes: 1440
    }
  }
}

resource eventGridSubscriptionLogic 'Microsoft.EventGrid/topics/eventSubscriptions@2023-12-15-preview' = {
  name: 'alerts-to-logic'
  parent: eventGridTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: '${logicApp.properties.accessEndpoint}/triggers/manual/paths/invoke?api-version=2016-10-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=${listCallbackURL(resourceId('Microsoft.Logic/workflows/triggers', logicApp.name, 'manual'), '2019-05-01').value}'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.AlertManagement.Alert.Activated'
      ]
      advancedFilters: [
        {
          operatorType: 'StringIn'
          key: 'data.severity'
          values: [
            'high'
            'critical'
          ]
        }
      ]
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 10
      eventTimeToLiveInMinutes: 1440
    }
  }
}

// Key Vault Secrets
resource cosmosConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'cosmos-connection'
  parent: keyVault
  properties: {
    value: cosmosDbAccount.listConnectionStrings().connectionStrings[0].connectionString
    contentType: 'text/plain'
  }
  dependsOn: [
    functionAppKeyVaultSecretsUserRole
  ]
}

resource eventGridKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'eventgrid-key'
  parent: keyVault
  properties: {
    value: eventGridTopic.listKeys().key1
    contentType: 'text/plain'
  }
  dependsOn: [
    functionAppKeyVaultSecretsUserRole
  ]
}

// Diagnostic Settings
resource functionAppDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'function-app-diagnostics'
  scope: functionApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
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

resource eventGridDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'eventgrid-diagnostics'
  scope: eventGridTopic
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'DeliveryFailures'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'PublishFailures'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
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

resource cosmosDbDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'cosmosdb-diagnostics'
  scope: cosmosDbAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'DataPlaneRequests'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'PartitionKeyStatistics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'Requests'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Outputs
output resourceGroupName string = resourceGroup().name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''
output storageAccountName string = storageAccount.name
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output eventGridTopicName string = eventGridTopic.name
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint
output logicAppName string = logicApp.name
output logicAppUrl string = logicApp.properties.accessEndpoint
output cosmosDbAccountName string = cosmosDbAccount.name
output cosmosDbEndpoint string = cosmosDbAccount.properties.documentEndpoint
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output workbookName string = alertWorkbook.name
output workbookId string = alertWorkbook.id
output actionGroupName string = actionGroup.name
output testAlertRuleName string = testAlertRule.name
output deploymentSummary object = {
  resourceCount: 20
  mainComponents: [
    'Log Analytics Workspace'
    'Application Insights'
    'Storage Account'
    'Key Vault'
    'Cosmos DB Account'
    'Event Grid Topic'
    'Function App'
    'Logic App'
    'Monitor Workbook'
    'Action Group'
    'Test Alert Rule'
  ]
  securityFeatures: [
    'Managed Identity Authentication'
    'Key Vault Secret Management'
    'RBAC Role Assignments'
    'HTTPS Only Access'
    'TLS 1.2 Minimum'
  ]
  monitoringFeatures: [
    'Application Insights Integration'
    'Diagnostic Settings'
    'Custom Workbook Dashboard'
    'Alert Rules'
    'Log Analytics Workspace'
  ]
}