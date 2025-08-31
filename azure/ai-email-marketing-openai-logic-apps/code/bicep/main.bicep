@description('AI-Powered Email Marketing Campaigns with Azure OpenAI and Logic Apps')

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Project name for resource naming')
@minLength(3)
@maxLength(15)
param projectName string = 'emailmarketing'

@description('Unique suffix for resource naming')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('OpenAI service name')
param openAiServiceName string = '${projectName}-openai-${uniqueSuffix}'

@description('OpenAI service tier')
@allowed(['S0'])
param openAiSku string = 'S0'

@description('GPT-4o model deployment name')
param gptModelDeploymentName string = 'gpt-4o-marketing'

@description('GPT-4o model version')
param gptModelVersion string = '2024-11-20'

@description('GPT-4o model capacity (tokens per minute)')
@minValue(1)
@maxValue(100)
param gptModelCapacity int = 10

@description('Communication Services resource name')
param communicationServicesName string = '${projectName}-comms-${uniqueSuffix}'

@description('Email Communication Services resource name')
param emailServicesName string = '${projectName}-email-${uniqueSuffix}'

@description('Storage account name for Logic Apps')
param storageAccountName string = '${projectName}${uniqueSuffix}'

@description('Function App (Logic Apps Standard) name')
param functionAppName string = '${projectName}-logicapp-${uniqueSuffix}'

@description('Application Insights name')
param applicationInsightsName string = '${projectName}-insights-${uniqueSuffix}'

@description('Log Analytics Workspace name')
param logAnalyticsWorkspaceName string = '${projectName}-logs-${uniqueSuffix}'

@description('Key Vault name for storing secrets')
param keyVaultName string = '${projectName}-kv-${uniqueSuffix}'

@description('Email domain type')
@allowed(['AzureManaged', 'CustomDomain'])
param emailDomainType string = 'AzureManaged'

@description('Custom email domain name (if using CustomDomain)')
param customEmailDomain string = ''

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Project: 'AI Email Marketing'
  Purpose: 'Recipe Deployment'
  'Cost Center': 'Marketing'
}

// Variables
var openAiEndpointUrl = 'https://${openAiService.name}.openai.azure.com/'
var senderEmailAddress = emailDomainType == 'AzureManaged' ? 'DoNotReply@${emailService.outputs.azureManagedDomain}' : 'DoNotReply@${customEmailDomain}'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
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

// Key Vault for storing secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Azure OpenAI Service
resource openAiService 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: openAiServiceName
  location: location
  tags: tags
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openAiServiceName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
  sku: {
    name: openAiSku
  }
}

// GPT-4o Model Deployment
resource gptModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openAiService
  name: gptModelDeploymentName
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: gptModelVersion
    }
  }
  sku: {
    name: 'Standard'
    capacity: gptModelCapacity
  }
}

// Communication Services
resource communicationServices 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: communicationServicesName
  location: 'global'
  tags: tags
  properties: {
    dataLocation: 'United States'
  }
}

// Email Communication Services
module emailService 'modules/emailService.bicep' = {
  name: 'emailServiceDeployment'
  params: {
    emailServicesName: emailServicesName
    communicationServicesName: communicationServicesName
    location: 'global'
    emailDomainType: emailDomainType
    customEmailDomain: customEmailDomain
    tags: tags
  }
  dependsOn: [
    communicationServices
  ]
}

// Storage Account for Logic Apps
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// App Service Plan for Logic Apps Standard
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${functionAppName}-plan'
  location: location
  tags: tags
  sku: {
    name: 'WS1'
    tier: 'WorkflowStandard'
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: 20
  }
}

// Function App (Logic Apps Standard)
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,workflowapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
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
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'OPENAI_ENDPOINT'
          value: openAiEndpointUrl
        }
        {
          name: 'OPENAI_KEY'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/openai-key/)'
        }
        {
          name: 'COMMUNICATION_CONNECTION_STRING'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/communication-connection-string/)'
        }
        {
          name: 'SENDER_EMAIL'
          value: senderEmailAddress
        }
        {
          name: 'GPT_MODEL_DEPLOYMENT_NAME'
          value: gptModelDeploymentName
        }
      ]
    }
  }
  dependsOn: [
    applicationInsights
    storageAccount
    openAiService
    gptModelDeployment
    communicationServices
  ]
}

// Key Vault access policy for Function App
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: functionApp.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
  }
}

// Store OpenAI key in Key Vault
resource openAiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'openai-key'
  properties: {
    value: openAiService.listKeys().key1
  }
  dependsOn: [
    keyVaultAccessPolicy
  ]
}

// Store Communication Services connection string in Key Vault
resource communicationConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'communication-connection-string'
  properties: {
    value: communicationServices.listKeys().primaryConnectionString
  }
  dependsOn: [
    keyVaultAccessPolicy
  ]
}

// Cognitive Services Contributor role assignment for Function App
resource openAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiService.id, functionApp.id, 'Cognitive Services OpenAI User')
  scope: openAiService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Communication Services Contributor role assignment for Function App
resource communicationRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(communicationServices.id, functionApp.id, 'Communication Services Contributor')
  scope: communicationServices
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1204f6b8-454c-4de8-8e92-12f3cde5eed0') // Communication Services Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Azure OpenAI Service Name')
output openAiServiceName string = openAiService.name

@description('Azure OpenAI Endpoint URL')
output openAiEndpoint string = openAiEndpointUrl

@description('GPT-4o Model Deployment Name')
output gptModelDeploymentName string = gptModelDeployment.name

@description('Communication Services Name')
output communicationServicesName string = communicationServices.name

@description('Email Services Name')
output emailServicesName string = emailService.outputs.emailServicesName

@description('Sender Email Address')
output senderEmailAddress string = senderEmailAddress

@description('Function App Name')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('Application Insights Name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Key Vault Name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Deployment Instructions')
output deploymentInstructions object = {
  step1: 'Review and customize parameters in parameters.json'
  step2: 'Deploy the infrastructure: az deployment group create --resource-group <rg-name> --template-file main.bicep --parameters @parameters.json'
  step3: 'Configure email workflows in the Logic Apps designer'
  step4: 'Test the AI-powered email marketing functionality'
  step5: 'Monitor performance through Application Insights'
}

@description('Post-Deployment Configuration')
output postDeploymentTasks object = {
  emailDomain: emailDomainType == 'CustomDomain' ? 'Configure DNS records for custom email domain' : 'Azure Managed Domain configured automatically'
  logicAppWorkflows: 'Deploy workflow definitions to Logic Apps Standard'
  monitoring: 'Configure alerts and dashboards in Application Insights'
  testing: 'Test email generation and delivery functionality'
  scaling: 'Adjust OpenAI model capacity based on usage patterns'
}