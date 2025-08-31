@description('Bicep module for Azure Functions App with Python runtime for AI Assistant custom functions')

// Parameters
@description('The location/region where resources will be deployed')
param location string

@description('Function App name')
param functionAppName string

@description('App Service Plan name')
param appServicePlanName string

@description('Python runtime version')
@allowed(['3.9', '3.10', '3.11'])
param pythonVersion string = '3.11'

@description('Storage Account name for Function App')
param storageAccountName string

@description('Storage connection string')
@secure()
param storageConnectionString string

@description('Application Insights instrumentation key')
@secure()
param applicationInsightsInstrumentationKey string

@description('Application Insights connection string')
@secure()
param applicationInsightsConnectionString string

@description('OpenAI Service endpoint')
param openAIEndpoint string

@description('OpenAI API key reference from Key Vault')
param openAIKeySecretUri string

@description('Key Vault name for managed identity access')
param keyVaultName string

@description('Tags to apply to resources')
param tags object = {}

@description('Function App SKU and tier')
param functionAppSku object = {
  name: 'Y1'
  tier: 'Dynamic'
}

@description('Enable Application Insights')
param enableApplicationInsights bool = true

// Variables
var pythonVersionMap = {
  '3.9': 'python|3.9'
  '3.10': 'python|3.10'
  '3.11': 'python|3.11'
}

// App Service Plan (Consumption Plan for serverless)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: functionAppSku
  kind: 'functionapp'
  properties: {
    reserved: true // Required for Linux
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
    serverFarmId: appServicePlan.id
    reserved: true
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: pythonVersionMap[pythonVersion]
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 10
      minimumElasticInstanceCount: 0
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      healthCheckPath: '/api/health'
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
          'https://ms.portal.azure.com'
        ]
        supportCredentials: false
      }
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: storageConnectionString
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
          name: 'WEBSITE_PYTHON_VERSION'
          value: pythonVersion
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableApplicationInsights ? applicationInsightsInstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsightsConnectionString : ''
        }
        {
          name: 'OPENAI_ENDPOINT'
          value: openAIEndpoint
        }
        {
          name: 'OPENAI_KEY'
          value: openAIKeySecretUri
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_ENABLE_SYNC_UPDATE_SITE'
          value: 'true'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: 'true'
        }
      ]
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Key Vault Access Policy for Function App Managed Identity
resource keyVaultAccessPolicy 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, keyVaultName, 'Key Vault Secrets User')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Function App Configuration for detailed logging
resource functionAppConfig 'Microsoft.Web/sites/config@2023-01-01' = {
  parent: functionApp
  name: 'logs'
  properties: {
    applicationLogs: {
      fileSystem: {
        level: 'Information'
      }
    }
    httpLogs: {
      fileSystem: {
        retentionInMb: 35
        retentionInDays: 7
        enabled: true
      }
    }
    failedRequestsTracing: {
      enabled: true
    }
    detailedErrorMessages: {
      enabled: true
    }
  }
}

// Diagnostic Settings for Function App
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableApplicationInsights) {
  name: 'default'
  scope: functionApp
  properties: {
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

// Health Check Function (automatically created)
resource healthCheckFunction 'Microsoft.Web/sites/functions@2023-01-01' = {
  parent: functionApp
  name: 'health'
  properties: {
    config: {
      bindings: [
        {
          authLevel: 'anonymous'
          type: 'httpTrigger'
          direction: 'in'
          name: 'req'
          methods: [
            'get'
          ]
          route: 'health'
        }
        {
          type: 'http'
          direction: 'out'
          name: '$return'
        }
      ]
    }
    files: {
      '__init__.py': '''
import logging
import json
import azure.functions as func

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Health check request received.')
    
    health_status = {
        "status": "healthy",
        "timestamp": func.datetime.utcnow().isoformat(),
        "service": "AI Assistant Function App",
        "version": "1.0.0"
    }
    
    return func.HttpResponse(
        json.dumps(health_status),
        status_code=200,
        mimetype="application/json"
    )
'''
    }
  }
}

// Outputs
@description('Function App ID')
output functionAppId string = functionApp.id

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Function App principal ID (for role assignments)')
output principalId string = functionApp.identity.principalId

@description('Function App tenant ID')
output tenantId string = functionApp.identity.tenantId

@description('App Service Plan ID')
output appServicePlanId string = appServicePlan.id

@description('App Service Plan name')
output appServicePlanName string = appServicePlan.name

@description('Function App configuration')
output functionAppConfiguration object = {
  name: functionApp.name
  url: 'https://${functionApp.properties.defaultHostName}'
  pythonVersion: pythonVersion
  functionsVersion: '~4'
  healthCheckUrl: 'https://${functionApp.properties.defaultHostName}/api/health'
  scmUrl: 'https://${functionApp.properties.repositorySiteName}.scm.azurewebsites.net'
}