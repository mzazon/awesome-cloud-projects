@description('Main Bicep template for Serverless Containers with Event Grid and Container Instances')

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@maxLength(10)
param environmentName string = 'dev'

@description('Project name for resource naming')
@maxLength(10)
param projectName string = 'eventcontainer'

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Container registry SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param containerRegistrySku string = 'Basic'

@description('Container CPU allocation')
@minValue(1)
@maxValue(4)
param containerCpu int = 1

@description('Container memory allocation in GB')
@minValue(1)
@maxValue(8)
param containerMemoryInGB int = 2

@description('Log Analytics workspace SKU')
@allowed([
  'Free'
  'Standard'
  'Premium'
  'PerNode'
  'PerGB2018'
  'Standalone'
])
param logAnalyticsWorkspaceSku string = 'PerGB2018'

@description('Function app runtime')
@allowed([
  'node'
  'dotnet'
  'java'
  'python'
])
param functionAppRuntime string = 'node'

@description('Function app runtime version')
param functionAppRuntimeVersion string = '18'

@description('Enable diagnostic logging')
param enableDiagnostics bool = true

@description('Tags to apply to all resources')
param tags object = {
  Environment: environmentName
  Project: projectName
  Purpose: 'event-driven-containers'
  CreatedBy: 'bicep-template'
}

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var storageAccountName = 'st${projectName}${uniqueSuffix}'
var containerRegistryName = 'acr${projectName}${uniqueSuffix}'
var eventGridTopicName = 'egt-${projectName}-${environmentName}'
var functionAppName = 'func-${projectName}-${environmentName}-${uniqueSuffix}'
var appServicePlanName = 'plan-${projectName}-${environmentName}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-${projectName}-${environmentName}-${uniqueSuffix}'
var applicationInsightsName = 'appi-${projectName}-${environmentName}-${uniqueSuffix}'
var actionGroupName = 'ag-${projectName}-${environmentName}'
var containerGroupName = 'cg-event-processor-${uniqueSuffix}'

// Storage Account
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
    isHnsEnabled: false
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
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Storage Account Blob Service
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
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

// Input Container
resource inputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'input'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'event-trigger-input'
    }
  }
}

// Output Container
resource outputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'output'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'processed-output'
    }
  }
}

// Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: containerRegistrySku
  }
  properties: {
    adminUserEnabled: true
    networkRuleSet: {
      defaultAction: 'Allow'
    }
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
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
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    dataResidencyBoundary: 'WithinGeopair'
  }
}

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
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
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
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// App Service Plan (Consumption)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'functionapp'
  properties: {
    reserved: true
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: '${functionAppRuntime.toUpper()}|${functionAppRuntimeVersion}'
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
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'CONTAINER_REGISTRY_NAME'
          value: containerRegistry.name
        }
        {
          name: 'CONTAINER_REGISTRY_SERVER'
          value: containerRegistry.properties.loginServer
        }
        {
          name: 'CONTAINER_REGISTRY_USERNAME'
          value: containerRegistry.name
        }
        {
          name: 'CONTAINER_REGISTRY_PASSWORD'
          value: containerRegistry.listCredentials().passwords[0].value
        }
        {
          name: 'STORAGE_ACCOUNT_NAME'
          value: storageAccount.name
        }
        {
          name: 'STORAGE_ACCOUNT_KEY'
          value: storageAccount.listKeys().keys[0].value
        }
        {
          name: 'EVENTGRID_TOPIC_ENDPOINT'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EVENTGRID_TOPIC_KEY'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'RESOURCE_GROUP_NAME'
          value: resourceGroup().name
        }
        {
          name: 'SUBSCRIPTION_ID'
          value: subscription().subscriptionId
        }
        {
          name: 'AZURE_LOCATION'
          value: location
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      http20Enabled: true
      alwaysOn: false
    }
    httpsOnly: true
    clientAffinityEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

// Container Group for Event Processing
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  tags: tags
  properties: {
    containers: [
      {
        name: 'event-processor'
        properties: {
          image: 'mcr.microsoft.com/azure-functions/dotnet:4-appservice'
          ports: [
            {
              port: 80
              protocol: 'TCP'
            }
          ]
          environmentVariables: [
            {
              name: 'STORAGE_ACCOUNT_NAME'
              value: storageAccount.name
            }
            {
              name: 'STORAGE_ACCOUNT_KEY'
              secureValue: storageAccount.listKeys().keys[0].value
            }
            {
              name: 'EVENTGRID_TOPIC_ENDPOINT'
              value: eventGridTopic.properties.endpoint
            }
            {
              name: 'EVENTGRID_TOPIC_KEY'
              secureValue: eventGridTopic.listKeys().key1
            }
            {
              name: 'CONTAINER_REGISTRY_SERVER'
              value: containerRegistry.properties.loginServer
            }
            {
              name: 'RESOURCE_GROUP_NAME'
              value: resourceGroup().name
            }
          ]
          resources: {
            requests: {
              cpu: containerCpu
              memoryInGB: containerMemoryInGB
            }
          }
          volumeMounts: []
        }
      }
    ]
    restartPolicy: 'OnFailure'
    osType: 'Linux'
    ipAddress: {
      type: 'Public'
      ports: [
        {
          port: 80
          protocol: 'TCP'
        }
      ]
      dnsNameLabel: 'event-processor-${uniqueSuffix}'
    }
    imageRegistryCredentials: [
      {
        server: containerRegistry.properties.loginServer
        username: containerRegistry.name
        password: containerRegistry.listCredentials().passwords[0].value
      }
    ]
    diagnostics: {
      logAnalytics: {
        workspaceId: logAnalyticsWorkspace.properties.customerId
        workspaceKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

// Action Group for Monitoring Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'ContainerAlert'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    azureResourceReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
    eventHubReceivers: []
  }
}

// Event Grid Subscription for Storage Events
resource storageEventSubscription 'Microsoft.EventGrid/eventSubscriptions@2023-12-15-preview' = {
  name: 'storage-blob-events'
  scope: storageAccount
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${functionApp.properties.defaultHostName}/api/ProcessStorageEvent'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/input/'
      advancedFilters: [
        {
          operatorType: 'StringContains'
          key: 'data.contentType'
          values: [
            'image'
            'text'
            'application'
          ]
        }
      ]
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
    deadLetterDestination: {
      endpointType: 'StorageBlob'
      properties: {
        resourceId: storageAccount.id
        blobContainerName: 'deadletter'
      }
    }
  }
}

// Dead Letter Container
resource deadLetterContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'deadletter'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'dead-letter-queue'
    }
  }
}

// Diagnostic Settings for Storage Account
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
          enabled: false
          days: 0
        }
      }
    ]
    logs: []
  }
}

// Diagnostic Settings for Event Grid Topic
resource eventGridDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'eventgrid-diagnostics'
  scope: eventGridTopic
  properties: {
    workspaceId: logAnalyticsWorkspace.id
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
    logs: [
      {
        category: 'DeliveryFailures'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'PublishFailures'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Diagnostic Settings for Function App
resource functionAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'functionapp-diagnostics'
  scope: functionApp
  properties: {
    workspaceId: logAnalyticsWorkspace.id
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
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Outputs
@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account primary key')
@secure()
output storageAccountKey string = storageAccount.listKeys().keys[0].value

@description('Storage account connection string')
@secure()
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('Container registry name')
output containerRegistryName string = containerRegistry.name

@description('Container registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('Container registry admin username')
output containerRegistryUsername string = containerRegistry.name

@description('Container registry admin password')
@secure()
output containerRegistryPassword string = containerRegistry.listCredentials().passwords[0].value

@description('Event Grid topic name')
output eventGridTopicName string = eventGridTopic.name

@description('Event Grid topic endpoint')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('Event Grid topic access key')
@secure()
output eventGridTopicKey string = eventGridTopic.listKeys().key1

@description('Function app name')
output functionAppName string = functionApp.name

@description('Function app default hostname')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('Function app webhook URL')
output functionAppWebhookUrl string = 'https://${functionApp.properties.defaultHostName}/api/ProcessStorageEvent'

@description('Container group name')
output containerGroupName string = containerGroup.name

@description('Container group FQDN')
output containerGroupFqdn string = containerGroup.properties.ipAddress.fqdn

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Application Insights instrumentation key')
@secure()
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Unique suffix used for resource naming')
output uniqueSuffix string = uniqueSuffix

@description('Input container name')
output inputContainerName string = inputContainer.name

@description('Output container name')
output outputContainerName string = outputContainer.name

@description('Dead letter container name')
output deadLetterContainerName string = deadLetterContainer.name