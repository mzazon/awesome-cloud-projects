@description('The location for all resources')
param location string = resourceGroup().location

@description('Prefix for all resource names')
param resourcePrefix string = 'config-mgmt'

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environmentName string = 'dev'

@description('App Configuration service tier')
@allowed(['free', 'standard'])
param appConfigSku string = 'standard'

@description('Service Bus namespace tier')
@allowed(['Basic', 'Standard', 'Premium'])
param serviceBusSku string = 'Standard'

@description('Function App plan SKU')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param functionAppSku string = 'Y1'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environmentName
  Purpose: 'EventDrivenConfiguration'
  Solution: 'ConfigurationManagement'
}

// Variables for consistent naming
var uniqueSuffix = uniqueString(resourceGroup().id)
var appConfigName = '${resourcePrefix}-appconfig-${uniqueSuffix}'
var serviceBusNamespaceName = '${resourcePrefix}-sb-${uniqueSuffix}'
var serviceBusTopicName = 'configuration-changes'
var storageAccountName = '${resourcePrefix}${uniqueSuffix}'
var functionAppName = '${resourcePrefix}-func-${uniqueSuffix}'
var logicAppName = '${resourcePrefix}-logic-${uniqueSuffix}'
var appServicePlanName = '${resourcePrefix}-plan-${uniqueSuffix}'

// Application Insights for monitoring
var appInsightsName = '${resourcePrefix}-insights-${uniqueSuffix}'

// Resource: Storage Account for Azure Functions
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
  tags: tags
}

// Resource: Application Insights for monitoring
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'rest'
  }
  tags: tags
}

// Resource: App Service Plan for Function Apps
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: functionAppSku
    tier: functionAppSku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  }
  properties: {
    reserved: false
  }
  tags: tags
}

// Resource: Azure App Configuration
resource appConfiguration 'Microsoft.AppConfiguration/configurationStores@2023-09-01' = {
  name: appConfigName
  location: location
  sku: {
    name: appConfigSku
  }
  properties: {
    enablePurgeProtection: false
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
  tags: tags
}

// Resource: Service Bus Namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: serviceBusNamespaceName
  location: location
  sku: {
    name: serviceBusSku
    tier: serviceBusSku
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
  tags: tags

  // Service Bus Topic for configuration changes
  resource configurationTopic 'topics@2022-10-01-preview' = {
    name: serviceBusTopicName
    properties: {
      maxSizeInMegabytes: 1024
      defaultMessageTimeToLive: 'P14D'
      enableBatchedOperations: true
      duplicateDetectionHistoryTimeWindow: 'PT10M'
      requiresDuplicateDetection: true
      supportOrdering: true
      enablePartitioning: false
    }

    // Subscription for web services
    resource webServicesSubscription 'subscriptions@2022-10-01-preview' = {
      name: 'web-services'
      properties: {
        defaultMessageTimeToLive: 'P14D'
        maxDeliveryCount: 10
        lockDuration: 'PT5M'
        enableBatchedOperations: true
        deadLetteringOnMessageExpiration: true
        deadLetteringOnFilterEvaluationExceptions: true
      }
    }

    // Subscription for API services
    resource apiServicesSubscription 'subscriptions@2022-10-01-preview' = {
      name: 'api-services'
      properties: {
        defaultMessageTimeToLive: 'P14D'
        maxDeliveryCount: 10
        lockDuration: 'PT5M'
        enableBatchedOperations: true
        deadLetteringOnMessageExpiration: true
        deadLetteringOnFilterEvaluationExceptions: true
      }
    }

    // Subscription for worker services
    resource workerServicesSubscription 'subscriptions@2022-10-01-preview' = {
      name: 'worker-services'
      properties: {
        defaultMessageTimeToLive: 'P14D'
        maxDeliveryCount: 10
        lockDuration: 'PT5M'
        enableBatchedOperations: true
        deadLetteringOnMessageExpiration: true
        deadLetteringOnFilterEvaluationExceptions: true
      }
    }
  }

  // Authorization rule for sending messages
  resource sendRule 'AuthorizationRules@2022-10-01-preview' = {
    name: 'SendRule'
    properties: {
      rights: ['Send']
    }
  }

  // Authorization rule for listening to messages
  resource listenRule 'AuthorizationRules@2022-10-01-preview' = {
    name: 'ListenRule'
    properties: {
      rights: ['Listen']
    }
  }

  // Authorization rule for managing (full access)
  resource manageRule 'AuthorizationRules@2022-10-01-preview' = {
    name: 'ManageRule'
    properties: {
      rights: ['Manage', 'Send', 'Listen']
    }
  }
}

// Resource: Function App for processing configuration changes
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
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
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
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
          name: 'ServiceBusConnection'
          value: serviceBusNamespace::manageRule.listKeys().primaryConnectionString
        }
        {
          name: 'AppConfigConnection'
          value: appConfiguration.listKeys().value[0].connectionString
        }
        {
          name: 'ServiceBusTopicName'
          value: serviceBusTopicName
        }
      ]
    }
  }
  tags: tags
}

// Resource: Logic App for complex configuration workflows
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
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
        'When_a_message_is_received_in_a_topic_subscription_(auto-complete)': {
          recurrence: {
            frequency: 'Minute'
            interval: 3
          }
          evaluatedRecurrence: {
            frequency: 'Minute'
            interval: 3
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'servicebus\'][\'connectionId\']'
              }
            }
            method: 'get'
            path: '/subscriptions/@{encodeURIComponent(encodeURIComponent(\'${serviceBusNamespace::configurationTopic::workerServicesSubscription.name}\'))}/messages/head'
            queries: {
              subscriptionType: 'Main'
              topicName: serviceBusTopicName
            }
          }
        }
      }
      actions: {
        'Process_Configuration_Change': {
          runAfter: {}
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://httpbin.org/post'
            body: {
              message: 'Configuration change processed'
              timestamp: '@{utcnow()}'
              data: '@triggerBody()'
            }
            headers: {
              'Content-Type': 'application/json'
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          servicebus: {
            connectionId: servicebus_connection.id
            connectionName: 'servicebus'
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/servicebus'
          }
        }
      }
    }
  }
  tags: tags
}

// API Connection for Logic App to Service Bus
resource servicebus_connection 'Microsoft.Web/connections@2016-06-01' = {
  name: 'servicebus'
  location: location
  properties: {
    displayName: 'Service Bus Connection'
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${location}/managedApis/servicebus'
    }
    parameterValues: {
      connectionString: serviceBusNamespace::manageRule.listKeys().primaryConnectionString
    }
  }
  tags: tags
}

// Event Grid System Topic for App Configuration events
resource eventGridSystemTopic 'Microsoft.EventGrid/systemTopics@2023-12-15-preview' = {
  name: '${appConfigName}-events'
  location: location
  properties: {
    source: appConfiguration.id
    topicType: 'Microsoft.AppConfiguration.ConfigurationStores'
  }
  tags: tags

  // Event subscription to forward App Configuration changes to Service Bus
  resource eventSubscription 'eventSubscriptions@2023-12-15-preview' = {
    name: 'config-changes-to-servicebus'
    properties: {
      destination: {
        endpointType: 'ServiceBusTopic'
        properties: {
          resourceId: serviceBusNamespace::configurationTopic.id
        }
      }
      filter: {
        includedEventTypes: [
          'Microsoft.AppConfiguration.KeyValueModified'
          'Microsoft.AppConfiguration.KeyValueDeleted'
        ]
        subjectBeginsWith: 'config/'
      }
      eventDeliverySchema: 'EventGridSchema'
      retryPolicy: {
        maxDeliveryAttempts: 30
        eventTimeToLiveInMinutes: 1440
      }
    }
  }
}

// Sample configuration keys for demonstration
resource sampleWebConfig 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-09-01' = {
  parent: appConfiguration
  name: 'config/web/app-title'
  properties: {
    value: 'My Web Application'
    contentType: 'text/plain'
    tags: {
      environment: environmentName
      service: 'web'
    }
  }
}

resource sampleApiConfig 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-09-01' = {
  parent: appConfiguration
  name: 'config/api/max-connections'
  properties: {
    value: '100'
    contentType: 'application/json'
    tags: {
      environment: environmentName
      service: 'api'
    }
  }
}

resource sampleWorkerConfig 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-09-01' = {
  parent: appConfiguration
  name: 'config/worker/batch-size'
  properties: {
    value: '50'
    contentType: 'application/json'
    tags: {
      environment: environmentName
      service: 'worker'
    }
  }
}

// Sample feature flag
resource sampleFeatureFlag 'Microsoft.AppConfiguration/configurationStores/keyValues@2023-09-01' = {
  parent: appConfiguration
  name: '.appconfig.featureflag~2Fconfig~2Ffeatures~2Fenable-notifications'
  properties: {
    value: '{"id":"config/features/enable-notifications","description":"Enable notification features","enabled":true,"conditions":{"client_filters":[]}}'
    contentType: 'application/vnd.microsoft.appconfig.ff+json;charset=utf-8'
    tags: {
      environment: environmentName
      type: 'feature-flag'
    }
  }
}

// Outputs for external consumption
@description('The name of the App Configuration store')
output appConfigurationName string = appConfiguration.name

@description('The connection string for the App Configuration store')
output appConfigurationConnectionString string = appConfiguration.listKeys().value[0].connectionString

@description('The endpoint URL for the App Configuration store')
output appConfigurationEndpoint string = appConfiguration.properties.endpoint

@description('The name of the Service Bus namespace')
output serviceBusNamespaceName string = serviceBusNamespace.name

@description('The connection string for the Service Bus namespace')
output serviceBusConnectionString string = serviceBusNamespace::manageRule.listKeys().primaryConnectionString

@description('The name of the Service Bus topic')
output serviceBusTopicName string = serviceBusTopicName

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The name of the Logic App')
output logicAppName string = logicApp.name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The name of the Application Insights component')
output applicationInsightsName string = appInsights.name

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('The resource names for easy reference')
output resourceNames object = {
  appConfiguration: appConfigurationName
  serviceBusNamespace: serviceBusNamespaceName
  serviceBusTopic: serviceBusTopicName
  functionApp: functionAppName
  logicApp: logicAppName
  storageAccount: storageAccountName
  applicationInsights: applicationInsightsName
}