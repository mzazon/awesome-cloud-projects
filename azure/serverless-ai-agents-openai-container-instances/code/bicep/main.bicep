// ============================================================================
// Azure Serverless AI Agents - Bicep Template
// ============================================================================
// This template deploys a serverless AI agent system using Azure OpenAI Service,
// Azure Container Instances, Azure Event Grid, and Azure Functions.
// ============================================================================

@description('The base name for all resources. This will be used to generate unique names.')
@minLength(3)
@maxLength(15)
param baseName string = 'aiagents'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('OpenAI Service SKU')
@allowed([
  'S0'
  'S1'
  'S2'
])
param openAiSku string = 'S0'

@description('OpenAI model deployment settings')
param openAiModelDeployment object = {
  modelName: 'gpt-4'
  modelVersion: '0613'
  deploymentName: 'gpt-4'
  scaleType: 'Standard'
  capacity: 20
}

@description('Container Registry SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param containerRegistrySku string = 'Basic'

@description('Function App hosting plan SKU')
@allowed([
  'Y1'
  'EP1'
  'EP2'
  'EP3'
])
param functionAppSku string = 'Y1'

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_ZRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Enable Application Insights monitoring')
param enableMonitoring bool = true

@description('Enable Container Registry admin user')
param enableContainerRegistryAdmin bool = true

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Application: 'AI-Agents'
  ManagedBy: 'Bicep'
}

// ============================================================================
// Variables
// ============================================================================

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var resourceNames = {
  storageAccount: 'st${baseName}${uniqueSuffix}'
  containerRegistry: 'cr${baseName}${uniqueSuffix}'
  openAiService: 'oai-${baseName}-${uniqueSuffix}'
  eventGridTopic: 'egt-${baseName}-${uniqueSuffix}'
  functionApp: 'func-${baseName}-${uniqueSuffix}'
  hostingPlan: 'plan-${baseName}-${uniqueSuffix}'
  applicationInsights: 'appi-${baseName}-${uniqueSuffix}'
  logAnalytics: 'log-${baseName}-${uniqueSuffix}'
  keyVault: 'kv-${baseName}-${uniqueSuffix}'
  logicApp: 'logic-${baseName}-${uniqueSuffix}'
}

// ============================================================================
// Storage Account
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: false
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
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

// Storage containers for agent results and state
resource storageAccountBlobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: false
    }
  }
}

resource resultsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: storageAccountBlobServices
  name: 'results'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

resource stateContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: storageAccountBlobServices
  name: 'state'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// ============================================================================
// Container Registry
// ============================================================================

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: resourceNames.containerRegistry
  location: location
  tags: tags
  sku: {
    name: containerRegistrySku
  }
  properties: {
    adminUserEnabled: enableContainerRegistryAdmin
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
      exportPolicy: {
        status: 'enabled'
      }
      azureADAuthenticationAsArmPolicy: {
        status: 'enabled'
      }
      softDeletePolicy: {
        retentionDays: 7
        status: 'disabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
    anonymousPullEnabled: false
  }
}

// ============================================================================
// Key Vault for Secrets Management
// ============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: tags
  properties: {
    enabledForDeployment: false
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    tenantId: subscription().tenantId
    accessPolicies: []
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
  }
}

// ============================================================================
// Azure OpenAI Service
// ============================================================================

resource openAiService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: resourceNames.openAiService
  location: location
  tags: tags
  sku: {
    name: openAiSku
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: resourceNames.openAiService
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// OpenAI Model Deployment
resource openAiModelDeploymentResource 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAiService
  name: openAiModelDeployment.deploymentName
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiModelDeployment.modelName
      version: openAiModelDeployment.modelVersion
    }
    scaleSettings: {
      scaleType: openAiModelDeployment.scaleType
      capacity: openAiModelDeployment.capacity
    }
  }
}

// ============================================================================
// Event Grid Topic
// ============================================================================

resource eventGridTopic 'Microsoft.EventGrid/topics@2022-06-15' = {
  name: resourceNames.eventGridTopic
  location: location
  tags: tags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// ============================================================================
// Log Analytics Workspace (for Application Insights)
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableMonitoring) {
  name: resourceNames.logAnalytics
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
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// Application Insights
// ============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableMonitoring) {
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableMonitoring ? logAnalyticsWorkspace.id : null
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// Function App Service Plan
// ============================================================================

resource hostingPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: resourceNames.hostingPlan
  location: location
  tags: tags
  sku: {
    name: functionAppSku
  }
  properties: {
    reserved: true
  }
  kind: 'linux'
}

// ============================================================================
// Function App
// ============================================================================

resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: resourceNames.functionApp
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'Python|3.11'
      alwaysOn: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
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
          value: toLower(resourceNames.functionApp)
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
          name: 'EVENTGRID_ENDPOINT'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EVENTGRID_KEY'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'OPENAI_ENDPOINT'
          value: openAiService.properties.endpoint
        }
        {
          name: 'OPENAI_KEY'
          value: openAiService.listKeys().key1
        }
        {
          name: 'STORAGE_CONNECTION'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'CONTAINER_REGISTRY_URL'
          value: containerRegistry.properties.loginServer
        }
        {
          name: 'CONTAINER_REGISTRY_USERNAME'
          value: containerRegistry.listCredentials().username
        }
        {
          name: 'CONTAINER_REGISTRY_PASSWORD'
          value: containerRegistry.listCredentials().passwords[0].value
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
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableMonitoring ? applicationInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableMonitoring ? applicationInsights.properties.ConnectionString : ''
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    httpsOnly: true
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
  }
}

// ============================================================================
// Logic App for Container Instance Orchestration
// ============================================================================

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: resourceNames.logicApp
  location: location
  tags: tags
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
        resourceGroupName: {
          defaultValue: resourceGroup().name
          type: 'String'
        }
        subscriptionId: {
          defaultValue: subscription().subscriptionId
          type: 'String'
        }
        containerRegistryServer: {
          defaultValue: containerRegistry.properties.loginServer
          type: 'String'
        }
        containerRegistryUsername: {
          defaultValue: containerRegistry.listCredentials().username
          type: 'String'
        }
        containerRegistryPassword: {
          defaultValue: containerRegistry.listCredentials().passwords[0].value
          type: 'String'
        }
        openAiEndpoint: {
          defaultValue: openAiService.properties.endpoint
          type: 'String'
        }
        openAiKey: {
          defaultValue: openAiService.listKeys().key1
          type: 'String'
        }
        storageConnection: {
          defaultValue: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
          type: 'String'
        }
      }
      triggers: {
        'When_Event_Grid_event_occurs': {
          type: 'ApiConnectionWebhook'
          inputs: {
            body: {
              properties: {
                topic: eventGridTopic.id
                destination: {
                  endpointType: 'webhook'
                  properties: {
                    endpointUrl: '@{listCallbackUrl()}'
                  }
                }
                filter: {
                  subjectBeginsWith: 'agent/task'
                }
              }
            }
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azureeventgrid\'][\'connectionId\']'
              }
            }
            path: '/subscriptions/@{encodeURIComponent(subscription().subscriptionId)}/providers/@{encodeURIComponent(\'Microsoft.EventGrid.Topics\')}/resource/eventSubscriptions'
            queries: {
              'x-ms-api-version': '2017-09-15-preview'
            }
          }
        }
      }
      actions: {
        'Parse_Event_Data': {
          type: 'ParseJson'
          inputs: {
            content: '@triggerBody()?[\'data\']'
            schema: {
              type: 'object'
              properties: {
                taskId: {
                  type: 'string'
                }
                prompt: {
                  type: 'string'
                }
              }
            }
          }
        }
        'Create_Container_Instance': {
          type: 'Http'
          inputs: {
            method: 'PUT'
            uri: 'https://management.azure.com/subscriptions/@{parameters(\'subscriptionId\')}/resourceGroups/@{parameters(\'resourceGroupName\')}/providers/Microsoft.ContainerInstance/containerGroups/@{body(\'Parse_Event_Data\')?[\'taskId\']}?api-version=2021-10-01'
            headers: {
              'Authorization': 'Bearer @{body(\'Get_Access_Token\')?[\'access_token\']}'
              'Content-Type': 'application/json'
            }
            body: {
              location: location
              properties: {
                containers: [
                  {
                    name: 'ai-agent'
                    properties: {
                      image: '@{parameters(\'containerRegistryServer\')}/ai-agent:latest'
                      resources: {
                        requests: {
                          cpu: 1
                          memoryInGB: 1.5
                        }
                      }
                      environmentVariables: [
                        {
                          name: 'TASK_ID'
                          value: '@{body(\'Parse_Event_Data\')?[\'taskId\']}'
                        }
                        {
                          name: 'TASK_PROMPT'
                          value: '@{body(\'Parse_Event_Data\')?[\'prompt\']}'
                        }
                        {
                          name: 'OPENAI_ENDPOINT'
                          value: '@{parameters(\'openAiEndpoint\')}'
                        }
                        {
                          name: 'OPENAI_KEY'
                          secureValue: '@{parameters(\'openAiKey\')}'
                        }
                        {
                          name: 'STORAGE_CONNECTION'
                          secureValue: '@{parameters(\'storageConnection\')}'
                        }
                      ]
                    }
                  }
                ]
                osType: 'Linux'
                restartPolicy: 'Never'
                imageRegistryCredentials: [
                  {
                    server: '@{parameters(\'containerRegistryServer\')}'
                    username: '@{parameters(\'containerRegistryUsername\')}'
                    password: '@{parameters(\'containerRegistryPassword\')}'
                  }
                ]
              }
            }
          }
          runAfter: {
            'Get_Access_Token': [
              'Succeeded'
            ]
          }
        }
        'Get_Access_Token': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://login.microsoftonline.com/@{subscription().tenantId}/oauth2/token'
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded'
            }
            body: 'grant_type=client_credentials&client_id=@{workflow().identity.principalId}&client_secret=@{workflow().identity.token}&resource=https://management.azure.com/'
          }
          runAfter: {
            'Parse_Event_Data': [
              'Succeeded'
            ]
          }
        }
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ============================================================================
// Role Assignments
// ============================================================================

// Grant Logic App permission to manage Container Instances
resource logicAppContainerInstanceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, logicApp.id, 'Contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Function App permission to read storage
resource functionAppStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'StorageBlobDataReader')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1') // Storage Blob Data Reader
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Monitoring Alerts
// ============================================================================

resource agentFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: 'alert-agent-failures'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when agent failures exceed threshold'
    severity: 2
    enabled: true
    scopes: [
      functionApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Function failures'
          metricName: 'FunctionExecutionCount'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
          dimensions: [
            {
              name: 'Status'
              operator: 'Include'
              values: [
                'Failed'
              ]
            }
          ]
        }
      ]
    }
    actions: []
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The connection string for the storage account')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'

@description('The name of the container registry')
output containerRegistryName string = containerRegistry.name

@description('The login server for the container registry')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('The container registry username')
output containerRegistryUsername string = containerRegistry.listCredentials().username

@description('The container registry password')
@secure()
output containerRegistryPassword string = containerRegistry.listCredentials().passwords[0].value

@description('The name of the OpenAI service')
output openAiServiceName string = openAiService.name

@description('The endpoint URL for the OpenAI service')
output openAiEndpoint string = openAiService.properties.endpoint

@description('The access key for the OpenAI service')
@secure()
output openAiKey string = openAiService.listKeys().key1

@description('The name of the Event Grid topic')
output eventGridTopicName string = eventGridTopic.name

@description('The endpoint URL for the Event Grid topic')
output eventGridEndpoint string = eventGridTopic.properties.endpoint

@description('The access key for the Event Grid topic')
@secure()
output eventGridKey string = eventGridTopic.listKeys().key1

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The URL of the Function App')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The name of the Logic App')
output logicAppName string = logicApp.name

@description('The Key Vault name')
output keyVaultName string = keyVault.name

@description('The Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = enableMonitoring ? applicationInsights.properties.InstrumentationKey : ''

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = enableMonitoring ? applicationInsights.properties.ConnectionString : ''

@description('Deployment summary')
output deploymentSummary object = {
  resourceGroupName: resourceGroup().name
  location: location
  environment: environment
  baseName: baseName
  uniqueSuffix: uniqueSuffix
  resourcesCreated: {
    storageAccount: storageAccount.name
    containerRegistry: containerRegistry.name
    openAiService: openAiService.name
    eventGridTopic: eventGridTopic.name
    functionApp: functionApp.name
    logicApp: logicApp.name
    keyVault: keyVault.name
    applicationInsights: enableMonitoring ? applicationInsights.name : 'Not enabled'
  }
}