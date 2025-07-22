// Main Bicep template for orchestrating real-time data validation workflows
// with Azure Table Storage and Azure Event Grid

@description('The location for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id, deployment().name)

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Function App runtime stack')
@allowed(['python', 'dotnet', 'node', 'java'])
param functionAppRuntime string = 'python'

@description('Function App runtime version')
param functionAppRuntimeVersion string = '3.11'

@description('Enable Application Insights')
param enableApplicationInsights bool = true

@description('Enable Log Analytics workspace')
param enableLogAnalytics bool = true

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'DataValidation'
  Solution: 'RealTimeValidation'
}

// Variables
var storageAccountName = 'stdataval${uniqueSuffix}'
var eventGridTopicName = 'data-validation-events-${uniqueSuffix}'
var logicAppName = 'validation-workflow-${uniqueSuffix}'
var functionAppName = 'validation-functions-${uniqueSuffix}'
var appServicePlanName = 'asp-validation-${uniqueSuffix}'
var appInsightsName = 'validation-insights-${uniqueSuffix}'
var logAnalyticsName = 'validation-monitoring-${uniqueSuffix}'

// Storage Account for Table Storage
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
    networkAcls: {
      defaultAction: 'Allow'
    }
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
        table: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Table Services for the storage account
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

// Customer Orders Table
resource customerOrdersTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  parent: tableService
  name: 'CustomerOrders'
  properties: {}
}

// Validation Rules Table
resource validationRulesTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  parent: tableService
  name: 'ValidationRules'
  properties: {}
}

// Event Grid Topic for custom events
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: tags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
  }
}

// Log Analytics Workspace (conditional)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableLogAnalytics) {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights (conditional)
resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    Request_Source: 'rest'
    WorkspaceResourceId: enableLogAnalytics ? logAnalyticsWorkspace.id : null
  }
}

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    computeMode: 'Dynamic'
    reserved: true
  }
}

// Function App for data validation
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: '${functionAppRuntime}|${functionAppRuntimeVersion}'
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
          value: functionAppRuntime
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'EVENT_GRID_TOPIC_ENDPOINT'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EVENT_GRID_TOPIC_KEY'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableApplicationInsights ? appInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? appInsights.properties.ConnectionString : ''
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

// Logic App for complex validation workflows
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: tags
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        When_a_HTTP_request_is_received: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              properties: {
                data: {
                  properties: {
                    amount: {
                      type: 'number'
                    }
                    customerEmail: {
                      type: 'string'
                    }
                    orderId: {
                      type: 'string'
                    }
                  }
                  type: 'object'
                }
              }
              type: 'object'
            }
          }
        }
      }
      actions: {
        Initialize_validation_result: {
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'validationResult'
                type: 'object'
                value: {
                  isValid: true
                  errors: []
                }
              }
            ]
          }
        }
        Check_amount_threshold: {
          type: 'If'
          dependsOn: [
            'Initialize_validation_result'
          ]
          expression: {
            greater: [
              '@triggerBody().data.amount'
              1000
            ]
          }
          actions: {
            Send_high_value_notification: {
              type: 'Http'
              inputs: {
                method: 'POST'
                uri: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
                body: {
                  text: 'High-value order detected: Order @{triggerBody().data.orderId} for $@{triggerBody().data.amount} requires review'
                }
              }
            }
          }
        }
        Return_validation_result: {
          type: 'Response'
          dependsOn: [
            'Check_amount_threshold'
          ]
          inputs: {
            statusCode: 200
            body: '@variables(\'validationResult\')'
          }
        }
      }
    }
    parameters: {}
    state: 'Enabled'
  }
}

// Event Grid Subscription for Function App
resource functionEventSubscription 'Microsoft.EventGrid/eventSubscriptions@2023-12-15-preview' = {
  name: 'function-validation-subscription'
  scope: eventGridTopic
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/DataValidationFunction'
        maxEventsPerBatch: 10
        preferredBatchSizeInKilobytes: 1024
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
        'Custom.DataValidation.OrderCreated'
      ]
      subjectBeginsWith: '/tabledata'
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
  }
}

// Event Grid Subscription for Logic App
resource logicAppEventSubscription 'Microsoft.EventGrid/eventSubscriptions@2023-12-15-preview' = {
  name: 'logicapp-validation-subscription'
  scope: eventGridTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: '${logicApp.properties.accessEndpoint}/triggers/When_a_HTTP_request_is_received/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2FWhen_a_HTTP_request_is_received%2Frun&sv=1.0&sig=${logicApp.properties.accessEndpoint}'
      }
    }
    filter: {
      includedEventTypes: [
        'Custom.DataValidation.ComplexValidation'
      ]
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
  }
}

// Managed Identity for Function App (system-assigned)
resource functionAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${functionAppName}-identity'
  location: location
  tags: tags
}

// Role assignment for Function App to access storage
resource storageContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'StorageTableDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3') // Storage Table Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Function App to access Event Grid
resource eventGridContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, functionApp.id, 'EventGridDataSender')
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7') // EventGrid Data Sender
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output storageAccountName string = storageAccount.name
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
output eventGridTopicName string = eventGridTopic.name
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output logicAppName string = logicApp.name
output logicAppTriggerUrl string = logicApp.properties.accessEndpoint
output appInsightsName string = enableApplicationInsights ? appInsights.name : ''
output appInsightsInstrumentationKey string = enableApplicationInsights ? appInsights.properties.InstrumentationKey : ''
output logAnalyticsWorkspaceName string = enableLogAnalytics ? logAnalyticsWorkspace.name : ''
output resourceGroupName string = resourceGroup().name
output location string = location