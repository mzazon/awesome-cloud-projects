// ==============================================================================
// Azure Intelligent API Lifecycle with API Center and AI Services
// ==============================================================================
// This template deploys a complete intelligent API lifecycle management solution
// using Azure API Center, AI Services, and monitoring capabilities.
// ==============================================================================

targetScope = 'resourceGroup'

// ==============================================================================
// Parameters
// ==============================================================================

@description('The location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param nameSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Administrator email address for API Management')
param adminEmail string

@description('Administrator name for API Management')
param adminName string = 'API Administrator'

@description('Azure OpenAI model deployment name')
param openAiModelName string = 'gpt-4'

@description('Azure OpenAI model version')
param openAiModelVersion string = '0613'

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'intelligent-api-lifecycle'
  environment: environment
  managedBy: 'bicep'
}

// ==============================================================================
// Variables
// ==============================================================================

var resourceNames = {
  apiCenter: 'apic-${nameSuffix}'
  openAi: 'openai-${nameSuffix}'
  anomalyDetector: 'anomaly-${nameSuffix}'
  apiManagement: 'apim-${nameSuffix}'
  logAnalytics: 'law-${nameSuffix}'
  applicationInsights: 'appins-${nameSuffix}'
  storageAccount: 'st${replace(nameSuffix, '-', '')}'
  logicApp: 'logic-${nameSuffix}'
  actionGroup: 'ag-${nameSuffix}'
}

// ==============================================================================
// Azure API Center
// ==============================================================================

resource apiCenter 'Microsoft.ApiCenter/services@2024-03-01' = {
  name: resourceNames.apiCenter
  location: location
  tags: tags
  properties: {
    // Free tier for demonstration, use Standard for production
    tier: 'Free'
  }
}

// Custom metadata schema for API lifecycle management
resource apiLifecycleMetadata 'Microsoft.ApiCenter/services/metadataSchemas@2024-03-01' = {
  name: 'api-lifecycle'
  parent: apiCenter
  properties: {
    schema: {
      type: 'object'
      properties: {
        lifecycleStage: {
          type: 'string'
          enum: ['design', 'development', 'testing', 'production', 'deprecated']
        }
        businessDomain: {
          type: 'string'
          enum: ['finance', 'hr', 'operations', 'customer', 'analytics']
        }
        dataClassification: {
          type: 'string'
          enum: ['public', 'internal', 'confidential', 'restricted']
        }
      }
    }
  }
}

// ==============================================================================
// Azure OpenAI Service
// ==============================================================================

resource openAiService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: resourceNames.openAi
  location: location
  tags: tags
  kind: 'OpenAI'
  properties: {
    customSubDomainName: resourceNames.openAi
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
  sku: {
    name: 'S0'
  }
}

// GPT-4 model deployment for documentation generation
resource gpt4Deployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  name: openAiModelName
  parent: openAiService
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiModelName
      version: openAiModelVersion
    }
    scaleSettings: {
      scaleType: 'Standard'
    }
  }
  sku: {
    name: 'Standard'
    capacity: 20
  }
}

// ==============================================================================
// Azure Anomaly Detector
// ==============================================================================

resource anomalyDetector 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: resourceNames.anomalyDetector
  location: location
  tags: tags
  kind: 'AnomalyDetector'
  properties: {
    customSubDomainName: resourceNames.anomalyDetector
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
  sku: {
    name: 'F0' // Free tier for demonstration
  }
}

// ==============================================================================
// Log Analytics Workspace
// ==============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalytics
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

// ==============================================================================
// Application Insights
// ==============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
  }
}

// ==============================================================================
// API Management Service
// ==============================================================================

resource apiManagement 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: resourceNames.apiManagement
  location: location
  tags: tags
  sku: {
    name: 'Consumption'
    capacity: 0
  }
  properties: {
    publisherEmail: adminEmail
    publisherName: adminName
    notificationSenderEmail: 'apimgmt-noreply@mail.windowsazure.com'
    virtualNetworkType: 'None'
    apiVersionConstraint: {
      minApiVersion: '2021-08-01'
    }
  }
}

// Configure Application Insights for API Management
resource apiManagementLogger 'Microsoft.ApiManagement/service/loggers@2023-09-01-preview' = {
  name: 'applicationinsights'
  parent: apiManagement
  properties: {
    loggerType: 'applicationInsights'
    resourceId: applicationInsights.id
    credentials: {
      instrumentationKey: applicationInsights.properties.InstrumentationKey
    }
  }
}

// ==============================================================================
// Storage Account for Portal Assets
// ==============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
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

// Enable static website hosting for API Center portal
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'HEAD', 'OPTIONS']
          allowedHeaders: ['*']
          exposedHeaders: ['*']
          maxAgeInSeconds: 3600
        }
      ]
    }
  }
}

// ==============================================================================
// Action Group for Alerts
// ==============================================================================

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: resourceNames.actionGroup
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'APIAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'AdminEmail'
        emailAddress: adminEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// ==============================================================================
// Anomaly Detection Alert Rule
// ==============================================================================

resource anomalyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'api-anomaly-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when API performance anomalies are detected'
    severity: 2
    enabled: true
    scopes: [
      apiManagement.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighResponseTime'
          metricName: 'Duration'
          dimensions: []
          operator: 'GreaterThan'
          threshold: 5000
          timeAggregation: 'Average'
          metricNamespace: 'Microsoft.ApiManagement/service'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ==============================================================================
// Logic App for Documentation Automation
// ==============================================================================

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: resourceNames.logicApp
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        openAiEndpoint: {
          type: 'string'
          defaultValue: openAiService.properties.endpoint
        }
        openAiKey: {
          type: 'securestring'
          defaultValue: openAiService.listKeys().key1
        }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            method: 'POST'
            schema: {
              type: 'object'
              properties: {
                apiId: {
                  type: 'string'
                }
                apiDefinition: {
                  type: 'string'
                }
              }
            }
          }
        }
      }
      actions: {
        'Generate-Documentation': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '@{concat(parameters(\'openAiEndpoint\'), \'/openai/deployments/${openAiModelName}/chat/completions?api-version=2023-05-15\')}'
            headers: {
              'Content-Type': 'application/json'
              'api-key': '@parameters(\'openAiKey\')'
            }
            body: {
              messages: [
                {
                  role: 'system'
                  content: 'You are an expert API documentation generator. Generate comprehensive documentation for the provided API specification.'
                }
                {
                  role: 'user'
                  content: '@{triggerBody()?[\'apiDefinition\']}'
                }
              ]
              max_tokens: 2000
              temperature: 0.3
            }
          }
        }
        'Return-Documentation': {
          type: 'Response'
          inputs: {
            statusCode: 200
            headers: {
              'Content-Type': 'application/json'
            }
            body: '@body(\'Generate-Documentation\')'
          }
          runAfter: {
            'Generate-Documentation': ['Succeeded']
          }
        }
      }
    }
  }
}

// ==============================================================================
// Sample API Registration
// ==============================================================================

resource sampleApi 'Microsoft.ApiCenter/services/apis@2024-03-01' = {
  name: 'customer-api'
  parent: apiCenter
  properties: {
    title: 'Customer Management API'
    description: 'API for managing customer data and operations'
    type: 'rest'
    customProperties: {
      lifecycleStage: 'production'
      businessDomain: 'customer'
      dataClassification: 'internal'
    }
  }
}

resource sampleApiVersion 'Microsoft.ApiCenter/services/apis/versions@2024-03-01' = {
  name: 'v1'
  parent: sampleApi
  properties: {
    title: 'Version 1.0'
    lifecycleStage: 'active'
  }
}

resource sampleApiDefinition 'Microsoft.ApiCenter/services/apis/versions/definitions@2024-03-01' = {
  name: 'openapi'
  parent: sampleApiVersion
  properties: {
    title: 'OpenAPI Definition'
    description: 'OpenAPI 3.0 specification for Customer Management API'
    specification: {
      name: 'openapi'
      version: '3.0.0'
    }
  }
}

// ==============================================================================
// Outputs
// ==============================================================================

@description('The name of the API Center instance')
output apiCenterName string = apiCenter.name

@description('The resource ID of the API Center instance')
output apiCenterId string = apiCenter.id

@description('The endpoint URL of the Azure OpenAI service')
output openAiEndpoint string = openAiService.properties.endpoint

@description('The name of the Azure OpenAI service')
output openAiServiceName string = openAiService.name

@description('The resource ID of the Anomaly Detector service')
output anomalyDetectorId string = anomalyDetector.id

@description('The name of the API Management service')
output apiManagementName string = apiManagement.name

@description('The gateway URL of the API Management service')
output apiManagementGatewayUrl string = apiManagement.properties.gatewayUrl

@description('The management API URL of the API Management service')
output apiManagementManagementApiUrl string = apiManagement.properties.managementApiUrl

@description('The developer portal URL of the API Management service')
output apiManagementPortalUrl string = apiManagement.properties.portalUrl

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The workspace ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('The Logic App trigger URL for documentation automation')
output logicAppTriggerUrl string = logicApp.listCallbackUrl().value

@description('The primary endpoint of the storage account for portal assets')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('Resource group location')
output location string = location

@description('Environment name')
output environment string = environment

@description('Resource name suffix')
output nameSuffix string = nameSuffix