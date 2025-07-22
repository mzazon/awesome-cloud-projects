@description('Main Bicep template for orchestrating multi-modal content processing workflows')
@description('Creates Azure Cognitive Services, Event Hubs, Logic Apps, and Storage for automated content analysis')

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Prefix for all resource names to ensure uniqueness')
@minLength(3)
@maxLength(8)
param resourcePrefix string

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'ContentProcessing'
  CreatedBy: 'BicepTemplate'
}

@description('Cognitive Services pricing tier')
@allowed(['F0', 'S0', 'S1', 'S2', 'S3', 'S4'])
param cognitiveServicesSku string = 'S0'

@description('Event Hubs pricing tier')
@allowed(['Basic', 'Standard', 'Premium'])
param eventHubsSku string = 'Standard'

@description('Number of Event Hub partitions')
@minValue(1)
@maxValue(32)
param eventHubPartitionCount int = 4

@description('Event Hub message retention in days')
@minValue(1)
@maxValue(7)
param eventHubRetentionDays int = 7

@description('Storage account performance tier')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS', 'Premium_LRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Storage account access tier')
@allowed(['Hot', 'Cool'])
param storageAccessTier string = 'Hot'

@description('Enable Event Hubs auto-inflate')
param enableAutoInflate bool = true

@description('Maximum throughput units for Event Hubs auto-inflate')
@minValue(1)
@maxValue(40)
param maxThroughputUnits int = 10

@description('Email address for alert notifications')
param alertEmailAddress string = 'admin@company.com'

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id)
var cognitiveServicesName = '${resourcePrefix}-cs-${uniqueSuffix}'
var eventHubsNamespaceName = '${resourcePrefix}-eh-${uniqueSuffix}'
var eventHubName = 'content-stream'
var storageAccountName = '${resourcePrefix}st${uniqueSuffix}'
var logicAppName = '${resourcePrefix}-la-${uniqueSuffix}'

// Storage container names
var containers = [
  'processed-insights'
  'raw-content'
  'sentiment-archives'
]

// Resource definitions

// Cognitive Services Language resource
resource cognitiveServices 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: cognitiveServicesName
  location: location
  tags: tags
  kind: 'TextAnalytics'
  sku: {
    name: cognitiveServicesSku
  }
  properties: {
    customSubDomainName: cognitiveServicesName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Event Hubs namespace
resource eventHubsNamespace 'Microsoft.EventHub/namespaces@2023-01-01-preview' = {
  name: eventHubsNamespaceName
  location: location
  tags: tags
  sku: {
    name: eventHubsSku
    tier: eventHubsSku
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: enableAutoInflate
    maximumThroughputUnits: enableAutoInflate ? maxThroughputUnits : null
  }
}

// Event Hub
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2023-01-01-preview' = {
  parent: eventHubsNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: eventHubRetentionDays
    partitionCount: eventHubPartitionCount
    status: 'Active'
  }
}

// Event Hub authorization rule for sending
resource eventHubSendRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2023-01-01-preview' = {
  parent: eventHub
  name: 'SendPolicy'
  properties: {
    rights: [
      'Send'
    ]
  }
}

// Event Hub authorization rule for Logic Apps (Send and Listen)
resource eventHubLogicAppRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2023-01-01-preview' = {
  parent: eventHub
  name: 'LogicAppPolicy'
  properties: {
    rights: [
      'Send'
      'Listen'
    ]
  }
}

// Storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: storageAccessTier
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
  }
}

// Blob service
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Storage containers
resource storageContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = [for container in containers: {
  parent: blobService
  name: container
  properties: {
    publicAccess: 'None'
  }
}]

// Logic App
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
        'When_events_are_available_in_Event_Hub': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'eventhubs\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/messages/head'
            queries: {
              eventHubName: eventHubName
            }
          }
          recurrence: {
            frequency: 'Second'
            interval: 30
          }
        }
      }
      actions: {
        'Parse_Event_Content': {
          type: 'ParseJson'
          inputs: {
            content: '@triggerBody()'
            schema: {
              type: 'object'
              properties: {
                content: {
                  type: 'string'
                }
                source: {
                  type: 'string'
                }
                timestamp: {
                  type: 'string'
                }
              }
            }
          }
        }
        'Detect_Language': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'cognitiveservicestextanalytics\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/text/analytics/v3.1/languages'
            body: {
              documents: [
                {
                  id: '1'
                  text: '@body(\'Parse_Event_Content\')?[\'content\']'
                }
              ]
            }
          }
          runAfter: {
            'Parse_Event_Content': [
              'Succeeded'
            ]
          }
        }
        'Analyze_Sentiment': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'cognitiveservicestextanalytics\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/text/analytics/v3.1/sentiment'
            body: {
              documents: [
                {
                  id: '1'
                  text: '@body(\'Parse_Event_Content\')?[\'content\']'
                  language: '@first(body(\'Detect_Language\')?[\'documents\'])?[\'detectedLanguage\']?[\'iso6391Name\']'
                }
              ]
            }
          }
          runAfter: {
            'Detect_Language': [
              'Succeeded'
            ]
          }
        }
        'Extract_Key_Phrases': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'cognitiveservicestextanalytics\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/text/analytics/v3.1/keyPhrases'
            body: {
              documents: [
                {
                  id: '1'
                  text: '@body(\'Parse_Event_Content\')?[\'content\']'
                  language: '@first(body(\'Detect_Language\')?[\'documents\'])?[\'detectedLanguage\']?[\'iso6391Name\']'
                }
              ]
            }
          }
          runAfter: {
            'Detect_Language': [
              'Succeeded'
            ]
          }
        }
        'Store_Analysis_Results': {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v2/datasets/@{encodeURIComponent(encodeURIComponent(\'${storageAccount.name}\'))}/files'
            queries: {
              folderPath: '/processed-insights'
              name: 'analysis-@{utcNow(\'yyyyMMddHHmmss\')}.json'
            }
            body: {
              timestamp: '@utcNow()'
              source: '@body(\'Parse_Event_Content\')?[\'source\']'
              language: '@first(body(\'Detect_Language\')?[\'documents\'])?[\'detectedLanguage\']?[\'name\']'
              sentiment: '@first(body(\'Analyze_Sentiment\')?[\'documents\'])?[\'sentiment\']'
              confidence: '@first(body(\'Analyze_Sentiment\')?[\'documents\'])?[\'confidenceScores\']'
              keyPhrases: '@first(body(\'Extract_Key_Phrases\')?[\'documents\'])?[\'keyPhrases\']'
              originalContent: '@body(\'Parse_Event_Content\')?[\'content\']'
            }
          }
          runAfter: {
            'Analyze_Sentiment': [
              'Succeeded'
            ]
            'Extract_Key_Phrases': [
              'Succeeded'
            ]
          }
        }
        'Check_Negative_Sentiment': {
          type: 'If'
          expression: {
            and: [
              {
                equals: [
                  '@first(body(\'Analyze_Sentiment\')?[\'documents\'])?[\'sentiment\']'
                  'negative'
                ]
              }
            ]
          }
          actions: {
            'Send_Alert_Email': {
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
                  To: alertEmailAddress
                  Subject: 'Negative Sentiment Alert - Content Processing'
                  Body: '<p>Negative sentiment detected in content from <strong>@{body(\'Parse_Event_Content\')?[\'source\']}</strong></p><p><strong>Key phrases:</strong> @{join(first(body(\'Extract_Key_Phrases\')?[\'documents\'])?[\'keyPhrases\'], \', \')}</p><p><strong>Original content:</strong> @{body(\'Parse_Event_Content\')?[\'content\']}</p>'
                  Importance: 'High'
                }
              }
            }
          }
          runAfter: {
            'Store_Analysis_Results': [
              'Succeeded'
            ]
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          eventhubs: {
            connectionId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/connections/eventhub-connection'
            connectionName: 'eventhub-connection'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/eventhubs'
          }
          cognitiveservicestextanalytics: {
            connectionId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/connections/cognitiveservices-connection'
            connectionName: 'cognitiveservices-connection'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/cognitiveservicestextanalytics'
          }
          azureblob: {
            connectionId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/connections/azureblob-connection'
            connectionName: 'azureblob-connection'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azureblob'
          }
          office365: {
            connectionId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Web/connections/office365-connection'
            connectionName: 'office365-connection'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/office365'
          }
        }
      }
    }
  }
}

// API Connections

// Event Hubs API Connection
resource eventHubConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'eventhub-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'Event Hub Connection'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/eventhubs'
    }
    parameterValues: {
      connectionString: eventHubLogicAppRule.listKeys().primaryConnectionString
    }
  }
}

// Cognitive Services API Connection
resource cognitiveServicesConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'cognitiveservices-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'Text Analytics Connection'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/cognitiveservicestextanalytics'
    }
    parameterValues: {
      apiKey: cognitiveServices.listKeys().key1
      siteUrl: cognitiveServices.properties.endpoint
    }
  }
}

// Azure Blob Storage API Connection
resource azureBlobConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'azureblob-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'Azure Blob Storage Connection'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/azureblob'
    }
    parameterValues: {
      connectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    }
  }
}

// Office 365 API Connection (for email alerts)
resource office365Connection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'office365-connection'
  location: location
  tags: tags
  properties: {
    displayName: 'Office 365 Connection'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/office365'
    }
    // Note: Office 365 connection requires OAuth authentication
    // This will need to be configured manually or through ARM template deployment
  }
}

// Outputs
@description('The name of the Cognitive Services resource')
output cognitiveServicesName string = cognitiveServices.name

@description('The endpoint URL of the Cognitive Services resource')
output cognitiveServicesEndpoint string = cognitiveServices.properties.endpoint

@description('The name of the Event Hubs namespace')
output eventHubsNamespaceName string = eventHubsNamespace.name

@description('The name of the Event Hub')
output eventHubName string = eventHub.name

@description('The primary connection string for Event Hub sending')
output eventHubSendConnectionString string = eventHubSendRule.listKeys().primaryConnectionString

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The primary endpoint of the storage account')
output storageAccountEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The name of the Logic App')
output logicAppName string = logicApp.name

@description('The Logic App resource ID')
output logicAppResourceId string = logicApp.id

@description('The Logic App trigger URL (for webhook scenarios)')
output logicAppTriggerUrl string = logicApp.listCallbackUrl().value

@description('Container names created in the storage account')
output storageContainers array = containers

@description('Resource group location')
output deploymentLocation string = location

@description('Resource prefix used for naming')
output resourcePrefix string = resourcePrefix

@description('Unique suffix used for globally unique resources')
output uniqueSuffix string = uniqueSuffix