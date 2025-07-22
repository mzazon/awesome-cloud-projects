@description('Deploys an intelligent content moderation solution using Azure AI Content Safety and Logic Apps')
@minLength(2)
@maxLength(10)
param namePrefix string = 'contmod'

@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('Environment type (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('The pricing tier for the AI Content Safety service')
@allowed(['F0', 'S0'])
param contentSafetySkuName string = 'S0'

@description('The pricing tier for the storage account')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Premium_LRS'])
param storageAccountSkuName string = 'Standard_LRS'

@description('Email address for content moderation notifications')
param notificationEmail string

@description('Enable diagnostic logging')
param enableDiagnostics bool = true

@description('Log retention in days')
@minValue(1)
@maxValue(365)
param logRetentionDays int = 30

@description('Tags to be applied to all resources')
param tags object = {
  Environment: environment
  Purpose: 'Content Moderation'
  Owner: 'DevOps Team'
}

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id)
var storageAccountName = '${namePrefix}storage${uniqueSuffix}'
var aiServicesName = '${namePrefix}-ai-${uniqueSuffix}'
var logicAppName = '${namePrefix}-logic-${uniqueSuffix}'
var eventGridTopicName = '${namePrefix}-events-${uniqueSuffix}'
var functionAppName = '${namePrefix}-func-${uniqueSuffix}'
var hostingPlanName = '${namePrefix}-plan-${uniqueSuffix}'
var logAnalyticsName = '${namePrefix}-logs-${uniqueSuffix}'
var applicationInsightsName = '${namePrefix}-insights-${uniqueSuffix}'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Storage Account for content and function app
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSkuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
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
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
  }
}

// Blob Services for the storage account
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Storage containers for different content states
resource uploadsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'uploads'
  properties: {
    publicAccess: 'None'
    metadata: {
      description: 'Container for uploaded content awaiting moderation'
    }
  }
}

resource quarantineContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'quarantine'
  properties: {
    publicAccess: 'None'
    metadata: {
      description: 'Container for quarantined content'
    }
  }
}

resource approvedContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'approved'
  properties: {
    publicAccess: 'None'
    metadata: {
      description: 'Container for approved content'
    }
  }
}

// Queue Services for processing
resource queueServices 'Microsoft.Storage/storageAccounts/queueServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource processingQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-01-01' = {
  parent: queueServices
  name: 'content-processing'
  properties: {
    metadata: {
      description: 'Queue for content processing tasks'
    }
  }
}

// Azure AI Content Safety Service
resource aiContentSafety 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: aiServicesName
  location: location
  tags: tags
  sku: {
    name: contentSafetySkuName
  }
  kind: 'ContentSafety'
  properties: {
    customSubDomainName: aiServicesName
    networkAcls: {
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Event Grid Topic
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: tags
  properties: {
    inputSchema: 'EventGridSchema'
  }
}

// App Service Plan for Function App
resource hostingPlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: hostingPlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

// Function App for content processing
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
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
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'AI_ENDPOINT'
          value: aiContentSafety.properties.endpoint
        }
        {
          name: 'AI_KEY'
          value: aiContentSafety.listKeys().key1
        }
        {
          name: 'STORAGE_CONNECTION'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'NOTIFICATION_EMAIL'
          value: notificationEmail
        }
      ]
      linuxFxVersion: 'Python|3.11'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
}

// Logic App (Consumption)
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
        'When_a_blob_is_added_or_modified': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccount.name}\'))}/triggers/batch/onupdatedfile'
            queries: {
              folderId: '/uploads'
              maxFileCount: 1
            }
          }
          recurrence: {
            frequency: 'Minute'
            interval: 1
          }
          splitOn: '@triggerBody()'
        }
      }
      actions: {
        'Get_blob_content': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccount.name}\'))}/files/@{encodeURIComponent(encodeURIComponent(triggerBody()?[\'Path\']))}/content'
          }
          runAfter: {}
        }
        'Analyze_content_safety': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '${aiContentSafety.properties.endpoint}contentsafety/text:analyze?api-version=2023-10-01'
            headers: {
              'Ocp-Apim-Subscription-Key': '@parameters(\'ai_key\')'
              'Content-Type': 'application/json'
            }
            body: {
              text: '@{base64ToString(body(\'Get_blob_content\')?[\'$content\'])}'
              categories: ['Hate', 'Violence', 'Sexual', 'SelfHarm']
              outputType: 'FourSeverityLevels'
            }
          }
          runAfter: {
            'Get_blob_content': ['Succeeded']
          }
        }
        'Check_content_safety': {
          type: 'If'
          expression: {
            or: [
              {
                greater: [
                  '@body(\'Analyze_content_safety\')?[\'categoriesAnalysis\']?[0]?[\'severity\']'
                  2
                ]
              }
              {
                greater: [
                  '@body(\'Analyze_content_safety\')?[\'categoriesAnalysis\']?[1]?[\'severity\']'
                  2
                ]
              }
              {
                greater: [
                  '@body(\'Analyze_content_safety\')?[\'categoriesAnalysis\']?[2]?[\'severity\']'
                  2
                ]
              }
              {
                greater: [
                  '@body(\'Analyze_content_safety\')?[\'categoriesAnalysis\']?[3]?[\'severity\']'
                  2
                ]
              }
            ]
          }
          actions: {
            'Move_to_quarantine': {
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccount.name}\'))}/copyFile'
                queries: {
                  source: '@triggerBody()?[\'Path\']'
                  destination: '@{replace(triggerBody()?[\'Path\'], \'/uploads/\', \'/quarantine/\')}'
                }
              }
            }
            'Send_notification_email': {
              type: 'ApiConnection'
              inputs: {
                host: {
                  connection: {
                    name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
                  }
                }
                method: 'post'
                path: '/v2/Mail'
                body: {
                  To: notificationEmail
                  Subject: 'Content Moderation Alert - Harmful Content Detected'
                  Body: 'Harmful content has been detected and quarantined. File: @{triggerBody()?[\'DisplayName\']} Analysis: @{body(\'Analyze_content_safety\')}'
                }
              }
              runAfter: {
                'Move_to_quarantine': ['Succeeded']
              }
            }
          }
          'else': {
            actions: {
              'Move_to_approved': {
                type: 'ApiConnection'
                inputs: {
                  host: {
                    connection: {
                      name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
                    }
                  }
                  method: 'post'
                  path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccount.name}\'))}/copyFile'
                  queries: {
                    source: '@triggerBody()?[\'Path\']'
                    destination: '@{replace(triggerBody()?[\'Path\'], \'/uploads/\', \'/approved/\')}'
                  }
                }
              }
            }
          }
          runAfter: {
            'Analyze_content_safety': ['Succeeded']
          }
        }
        'Log_analysis_result': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '${logAnalyticsWorkspace.properties.customerId}/api/logs'
            headers: {
              'Content-Type': 'application/json'
              'Log-Type': 'ContentModerationLog'
            }
            body: {
              FileName: '@triggerBody()?[\'DisplayName\']'
              FilePath: '@triggerBody()?[\'Path\']'
              AnalysisResult: '@body(\'Analyze_content_safety\')'
              ProcessedAt: '@utcnow()'
            }
          }
          runAfter: {
            'Check_content_safety': ['Succeeded']
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          azureblob: {
            connectionId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/connections/azureblob'
            connectionName: 'azureblob'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azureblob'
          }
          office365: {
            connectionId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/connections/office365'
            connectionName: 'office365'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/office365'
          }
        }
      }
      ai_key: {
        value: aiContentSafety.listKeys().key1
      }
    }
  }
}

// Event Grid Subscription for storage blob events
resource eventGridSubscription 'Microsoft.EventGrid/eventSubscriptions@2023-12-15-preview' = {
  name: 'content-upload-subscription'
  scope: storageAccount
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: '${eventGridTopic.properties.endpoint}'
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/uploads/'
    }
    eventDeliverySchema: 'EventGridSchema'
  }
}

// API Connections for Logic App
resource azureBlobConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'azureblob'
  location: location
  tags: tags
  properties: {
    displayName: 'Azure Blob Storage Connection'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azureblob'
    }
    parameterValues: {
      accountName: storageAccount.name
      accessKey: storageAccount.listKeys().keys[0].value
    }
  }
}

resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'office365'
  location: location
  tags: tags
  properties: {
    displayName: 'Office 365 Outlook Connection'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/office365'
    }
  }
}

// Diagnostic Settings
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'storage-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

resource logicAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'logic-app-diagnostics'
  scope: logicApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
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
          days: logRetentionDays
        }
      }
    ]
  }
}

resource aiContentSafetyDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'ai-content-safety-diagnostics'
  scope: aiContentSafety
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
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
          days: logRetentionDays
        }
      }
    ]
  }
}

// Outputs
@description('The name of the deployed resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The primary endpoint of the storage account')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The name of the AI Content Safety service')
output aiContentSafetyName string = aiContentSafety.name

@description('The endpoint of the AI Content Safety service')
output aiContentSafetyEndpoint string = aiContentSafety.properties.endpoint

@description('The name of the Logic App')
output logicAppName string = logicApp.name

@description('The callback URL of the Logic App')
output logicAppCallbackUrl string = logicApp.properties.accessEndpoint

@description('The name of the Event Grid Topic')
output eventGridTopicName string = eventGridTopic.name

@description('The endpoint of the Event Grid Topic')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppDefaultHostname string = functionApp.properties.defaultHostName

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The workspace ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('The name of the Application Insights component')
output applicationInsightsName string = applicationInsights.name

@description('The instrumentation key of the Application Insights component')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The connection string of the Application Insights component')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Container URLs for content management')
output containerUrls object = {
  uploads: '${storageAccount.properties.primaryEndpoints.blob}uploads'
  quarantine: '${storageAccount.properties.primaryEndpoints.blob}quarantine'
  approved: '${storageAccount.properties.primaryEndpoints.blob}approved'
}

@description('Resource connection strings for testing')
output connectionStrings object = {
  storage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
  applicationInsights: applicationInsights.properties.ConnectionString
}