@description('Name of the Azure Migrate project')
param migrateProjectName string

@description('Name of the Azure OpenAI Service')
param openAIServiceName string

@description('Name of the Azure Function App')
param functionAppName string

@description('Name of the storage account')
param storageAccountName string

@description('Name of the Application Insights instance')
param applicationInsightsName string

@description('Name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string

@description('Name of the user-assigned managed identity')
param userAssignedIdentityName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name for resource tagging')
param environmentName string = 'demo'

@description('Project name for resource tagging')
param projectName string = 'ai-migration-assessment'

@description('OpenAI model name to deploy')
param openAIModelName string = 'gpt-4'

@description('OpenAI model version to deploy')
param openAIModelVersion string = '0613'

@description('OpenAI deployment name')
param openAIDeploymentName string = 'gpt-4-migration-analysis'

@description('OpenAI deployment capacity')
param openAIDeploymentCapacity int = 20

@description('Function App runtime stack')
param functionAppRuntime string = 'python'

@description('Function App runtime version')
param functionAppRuntimeVersion string = '3.11'

@description('Storage account SKU')
param storageAccountSku string = 'Standard_LRS'

@description('Application Insights type')
param applicationInsightsType string = 'web'

// Variables for consistent naming and configuration
var commonTags = {
  Environment: environmentName
  Project: projectName
  Purpose: 'Migration Assessment'
}

var storageAccountNameClean = take(replace(storageAccountName, '-', ''), 24)

// User-assigned managed identity for secure service-to-service communication
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: userAssignedIdentityName
  location: location
  tags: commonTags
}

// Log Analytics workspace for monitoring and logging
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: commonTags
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

// Application Insights for application monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: commonTags
  kind: applicationInsightsType
  properties: {
    Application_Type: applicationInsightsType
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage account for function app and migration data
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountNameClean
  location: location
  tags: commonTags
  kind: 'StorageV2'
  sku: {
    name: storageAccountSku
  }
  properties: {
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    accessTier: 'Hot'
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
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Blob containers for assessment data and AI insights
resource assessmentDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storageAccount.name}/default/assessment-data'
  properties: {
    publicAccess: 'None'
  }
}

resource aiInsightsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storageAccount.name}/default/ai-insights'
  properties: {
    publicAccess: 'None'
  }
}

resource modernizationReportsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storageAccount.name}/default/modernization-reports'
  properties: {
    publicAccess: 'None'
  }
}

// Azure OpenAI Service account
resource openAIService 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openAIServiceName
  location: location
  tags: commonTags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: openAIServiceName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
}

// OpenAI model deployment
resource openAIDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAIService
  name: openAIDeploymentName
  properties: {
    model: {
      format: 'OpenAI'
      name: openAIModelName
      version: openAIModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'Standard'
    capacity: openAIDeploymentCapacity
  }
}

// Azure Migrate project
resource migrateProject 'Microsoft.Migrate/migrateProjects@2020-05-01' = {
  name: migrateProjectName
  location: location
  tags: commonTags
  properties: {
    registeredTools: [
      'ServerDiscovery'
      'ServerAssessment'
      'ServerMigration'
    ]
  }
}

// App Service plan for Function App (Consumption plan)
resource functionAppServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${functionAppName}-plan'
  location: location
  tags: commonTags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'functionapp'
  properties: {
    reserved: true
  }
}

// Function App for AI processing
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: commonTags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: functionAppServicePlan.id
    reserved: true
    siteConfig: {
      linuxFxVersion: '${upper(functionAppRuntime)}|${functionAppRuntimeVersion}'
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
          name: 'OPENAI_ENDPOINT'
          value: openAIService.properties.endpoint
        }
        {
          name: 'OPENAI_KEY'
          value: openAIService.listKeys().key1
        }
        {
          name: 'OPENAI_MODEL_DEPLOYMENT'
          value: openAIDeploymentName
        }
        {
          name: 'MIGRATE_PROJECT'
          value: migrateProjectName
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
      ]
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    httpsOnly: true
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
}

// Role assignments for managed identity
resource cognitiveServicesUserRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
}

resource storageBlobDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
}

resource migrateContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '6e2f5c01-e7e5-46d4-ac9e-8d23e1a5e1c5' // Migrate Contributor
}

// Assign Cognitive Services User role to managed identity
resource cognitiveServicesRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: openAIService
  name: guid(openAIService.id, userAssignedIdentity.id, cognitiveServicesUserRoleDefinition.id)
  properties: {
    roleDefinitionId: cognitiveServicesUserRoleDefinition.id
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Assign Storage Blob Data Contributor role to managed identity
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, userAssignedIdentity.id, storageBlobDataContributorRoleDefinition.id)
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleDefinition.id
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Assign Migrate Contributor role to managed identity
resource migrateRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: migrateProject
  name: guid(migrateProject.id, userAssignedIdentity.id, migrateContributorRoleDefinition.id)
  properties: {
    roleDefinitionId: migrateContributorRoleDefinition.id
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs for reference and integration
@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Azure Migrate project name')
output migrateProjectName string = migrateProject.name

@description('Azure OpenAI Service name')
output openAIServiceName string = openAIService.name

@description('Azure OpenAI Service endpoint')
output openAIServiceEndpoint string = openAIService.properties.endpoint

@description('OpenAI deployment name')
output openAIDeploymentName string = openAIDeployment.name

@description('Function App name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('User-assigned managed identity name')
output userAssignedIdentityName string = userAssignedIdentity.name

@description('User-assigned managed identity principal ID')
output userAssignedIdentityPrincipalId string = userAssignedIdentity.properties.principalId

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Storage containers created')
output storageContainers array = [
  'assessment-data'
  'ai-insights'
  'modernization-reports'
]

@description('Migration assessment pipeline endpoints')
output endpoints object = {
  functionAppUrl: 'https://${functionApp.properties.defaultHostName}'
  openAIEndpoint: openAIService.properties.endpoint
  migrateProject: migrateProject.name
}