// ================================================================================================
// Bicep Template: Orchestrating Serverless AI Prompt Workflows
// Description: Deploys Azure AI Studio, Prompt Flow, Container Apps, and monitoring infrastructure
// Author: Generated with Claude Code
// Version: 1.0
// ================================================================================================

targetScope = 'resourceGroup'

// ================================================================================================
// PARAMETERS
// ================================================================================================

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment prefix for resource naming (dev, test, prod)')
@minLength(2)
@maxLength(4)
param environmentPrefix string = 'dev'

@description('Project name for resource naming')
@minLength(3)
@maxLength(10)
param projectName string = 'aiprompt'

@description('Random suffix for globally unique resource names')
@minLength(6)
@maxLength(8)
param randomSuffix string = take(uniqueString(resourceGroup().id), 6)

@description('SKU for Azure OpenAI service')
@allowed(['S0'])
param openAiSku string = 'S0'

@description('Azure OpenAI model name to deploy')
@allowed(['gpt-35-turbo', 'gpt-4', 'gpt-4-32k'])
param modelName string = 'gpt-35-turbo'

@description('Azure OpenAI model version')
param modelVersion string = '0613'

@description('Model deployment capacity (tokens per minute)')
@minValue(1)
@maxValue(100)
param modelCapacity int = 10

@description('Container Apps minimum replica count')
@minValue(0)
@maxValue(5)
param minReplicas int = 0

@description('Container Apps maximum replica count')
@minValue(1)
@maxValue(50)
param maxReplicas int = 10

@description('HTTP concurrency per replica for scaling')
@minValue(1)
@maxValue(100)
param httpConcurrency int = 10

@description('Enable Application Insights for monitoring')
param enableApplicationInsights bool = true

@description('Tags to apply to all resources')
param resourceTags object = {
  Environment: environmentPrefix
  Project: projectName
  DeployedBy: 'Bicep'
  Purpose: 'AI-Prompt-Workflows'
}

// ================================================================================================
// VARIABLES
// ================================================================================================

var namingPrefix = '${environmentPrefix}-${projectName}'
var uniqueSuffix = '${namingPrefix}-${randomSuffix}'

// Resource names
var storageAccountName = replace('st${uniqueSuffix}', '-', '')
var containerRegistryName = replace('acr${uniqueSuffix}', '-', '')
var logAnalyticsName = 'law-${uniqueSuffix}'
var applicationInsightsName = 'ai-${uniqueSuffix}'
var aiHubName = 'hub-${uniqueSuffix}'
var aiProjectName = 'proj-${uniqueSuffix}'
var openAiAccountName = 'aoai-${uniqueSuffix}'
var containerAppsEnvironmentName = 'cae-${uniqueSuffix}'
var containerAppName = 'ca-${uniqueSuffix}'
var keyVaultName = 'kv-${take(uniqueSuffix, 20)}'

// Container image details
var containerImageName = 'promptflow-app'
var containerImageTag = 'latest'
var containerPort = 8080

// ================================================================================================
// EXISTING RESOURCES
// ================================================================================================

// Reference to the resource group for tagging
resource resourceGroupRef 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: resourceGroup().name
}

// ================================================================================================
// STORAGE ACCOUNT
// ================================================================================================

@description('Storage account for AI Hub and general storage needs')
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: false
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
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
  }
}

// ================================================================================================
// KEY VAULT
// ================================================================================================

@description('Key Vault for storing sensitive configuration')
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    accessPolicies: []
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// ================================================================================================
// CONTAINER REGISTRY
// ================================================================================================

@description('Azure Container Registry for storing container images')
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: resourceTags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
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
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
  }
}

// ================================================================================================
// LOG ANALYTICS WORKSPACE
// ================================================================================================

@description('Log Analytics workspace for monitoring and logging')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ================================================================================================
// APPLICATION INSIGHTS
// ================================================================================================

@description('Application Insights for application monitoring')
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 90
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ================================================================================================
// AZURE OPENAI SERVICE
// ================================================================================================

@description('Azure OpenAI service for language model capabilities')
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: openAiAccountName
  location: location
  tags: resourceTags
  sku: {
    name: openAiSku
  }
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openAiAccountName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
  }
}

@description('Deploy the specified OpenAI model')
resource openAiModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openAiAccount
  name: modelName
  sku: {
    name: 'Standard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

// ================================================================================================
// AI HUB (Machine Learning Workspace)
// ================================================================================================

@description('Azure AI Hub for centralized AI development')
resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: aiHubName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'AI Hub for ${projectName}'
    description: 'Centralized hub for AI development and prompt flow management'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: enableApplicationInsights ? applicationInsights.id : null
    hbiWorkspace: false
    publicNetworkAccess: 'Enabled'
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
  }
  kind: 'Hub'
}

@description('Azure AI Project for prompt flow development')
resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: aiProjectName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'AI Project for ${projectName}'
    description: 'Project workspace for prompt flow development and deployment'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: enableApplicationInsights ? applicationInsights.id : null
    hbiWorkspace: false
    publicNetworkAccess: 'Enabled'
    hubResourceId: aiHub.id
  }
  kind: 'Project'
}

// ================================================================================================
// CONTAINER APPS ENVIRONMENT
// ================================================================================================

@description('Container Apps environment for serverless deployment')
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: resourceTags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
  }
}

// ================================================================================================
// CONTAINER APP
// ================================================================================================

@description('Container App for hosting the prompt flow application')
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: resourceTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: containerPort
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistry.listCredentials().username
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
        {
          name: 'openai-api-key'
          value: openAiAccount.listKeys().key1
        }
        {
          name: 'appinsights-connection-string'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerImageName
          image: '${containerRegistry.properties.loginServer}/${containerImageName}:${containerImageTag}'
          env: [
            {
              name: 'AZURE_OPENAI_ENDPOINT'
              value: openAiAccount.properties.endpoint
            }
            {
              name: 'AZURE_OPENAI_API_KEY'
              secretRef: 'openai-api-key'
            }
            {
              name: 'AZURE_OPENAI_DEPLOYMENT_NAME'
              value: modelName
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-connection-string'
            }
            {
              name: 'PORT'
              value: string(containerPort)
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          probes: [
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: containerPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: containerPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 30
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaler'
            http: {
              metadata: {
                concurrentRequests: string(httpConcurrency)
              }
            }
          }
        ]
      }
    }
  }
}

// ================================================================================================
// RBAC ASSIGNMENTS
// ================================================================================================

// Grant AI Hub access to storage account
resource aiHubStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, aiHub.id, 'StorageBlobDataContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: aiHub.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant AI Project access to storage account
resource aiProjectStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, aiProject.id, 'StorageBlobDataContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: aiProject.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Container App access to Key Vault secrets
resource containerAppKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, containerApp.id, 'KeyVaultSecretsUser')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Container App access to OpenAI
resource containerAppOpenAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: openAiAccount
  name: guid(openAiAccount.id, containerApp.id, 'CognitiveServicesOpenAIUser')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ================================================================================================
// MONITORING ALERTS
// ================================================================================================

@description('Alert rule for high response time')
resource responseTimeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableApplicationInsights) {
  name: '${containerAppName}-high-response-time'
  location: 'global'
  tags: resourceTags
  properties: {
    description: 'Alert when average response time exceeds 2 seconds'
    severity: 2
    enabled: true
    scopes: [
      containerApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 2000
          name: 'ResponseTime'
          metricNamespace: 'Microsoft.App/containerApps'
          metricName: 'ResponseTime'
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: []
  }
}

@description('Alert rule for high error rate')
resource errorRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableApplicationInsights) {
  name: '${containerAppName}-high-error-rate'
  location: 'global'
  tags: resourceTags
  properties: {
    description: 'Alert when error rate exceeds 5%'
    severity: 1
    enabled: true
    scopes: [
      containerApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 5
          name: 'ErrorRate'
          metricNamespace: 'Microsoft.App/containerApps'
          metricName: 'RequestsPerSecond'
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: []
  }
}

// ================================================================================================
// OUTPUTS
// ================================================================================================

@description('The resource group where resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('The Azure region where resources were deployed')
output location string = location

@description('Storage Account name for AI Hub')
output storageAccountName string = storageAccount.name

@description('Storage Account connection string')
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Container Registry name')
output containerRegistryName string = containerRegistry.name

@description('Container Registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('Container Registry admin username')
output containerRegistryUsername string = containerRegistry.listCredentials().username

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Application Insights name')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : 'Not deployed'

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : 'Not deployed'

@description('Application Insights connection string')
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : 'Not deployed'

@description('Azure OpenAI account name')
output openAiAccountName string = openAiAccount.name

@description('Azure OpenAI endpoint URL')
output openAiEndpoint string = openAiAccount.properties.endpoint

@description('Azure OpenAI deployed model name')
output openAiModelName string = modelName

@description('AI Hub name')
output aiHubName string = aiHub.name

@description('AI Hub resource ID')
output aiHubId string = aiHub.id

@description('AI Project name')
output aiProjectName string = aiProject.name

@description('AI Project resource ID')
output aiProjectId string = aiProject.id

@description('Container Apps Environment name')
output containerAppsEnvironmentName string = containerAppsEnvironment.name

@description('Container App name')
output containerAppName string = containerApp.name

@description('Container App FQDN')
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn

@description('Container App URL')
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Resource tags applied to all resources')
output resourceTags object = resourceTags

@description('Deployment summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  aiHubName: aiHub.name
  aiProjectName: aiProject.name
  containerAppUrl: 'https://${containerApp.properties.configuration.ingress.fqdn}'
  openAiEndpoint: openAiAccount.properties.endpoint
  modelDeployed: modelName
  monitoringEnabled: enableApplicationInsights
  estimatedMonthlyCost: 'Varies based on usage - Container Apps, OpenAI tokens, and storage consumption'
}