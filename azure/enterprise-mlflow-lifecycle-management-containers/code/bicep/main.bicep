// ==============================================================================
// MLflow Model Lifecycle Management with Azure Machine Learning and Container Apps
// ==============================================================================
// This Bicep template deploys a complete MLflow model lifecycle management solution
// using Azure Machine Learning for experiment tracking and model registry,
// Azure Container Apps for scalable model serving, and Azure Monitor for observability.

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@maxLength(10)
param environmentName string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
@maxLength(6)
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Machine Learning workspace name')
param mlWorkspaceName string = 'mlws-${environmentName}-${uniqueSuffix}'

@description('Container Apps environment name')
param containerAppsEnvironmentName string = 'cae-mlflow-${environmentName}-${uniqueSuffix}'

@description('Container app name for model serving')
param containerAppName string = 'ca-model-serve-${environmentName}-${uniqueSuffix}'

@description('Storage account name for ML workspace')
param storageAccountName string = 'stmlflow${environmentName}${uniqueSuffix}'

@description('Key Vault name for secrets management')
param keyVaultName string = 'kv-mlflow-${environmentName}-${uniqueSuffix}'

@description('Container Registry name')
param containerRegistryName string = 'acrmlflow${environmentName}${uniqueSuffix}'

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string = 'law-mlflow-${environmentName}-${uniqueSuffix}'

@description('Application Insights name')
param applicationInsightsName string = 'ai-mlflow-${environmentName}-${uniqueSuffix}'

@description('Model name for serving (can be updated after deployment)')
param modelName string = 'demo-regression-model'

@description('Model version for serving (latest or specific version)')
param modelVersion string = 'latest'

@description('Container app minimum replicas')
@minValue(0)
@maxValue(5)
param minReplicas int = 1

@description('Container app maximum replicas')
@minValue(1)
@maxValue(30)
param maxReplicas int = 10

@description('Container app CPU allocation')
@allowed(['0.25', '0.5', '0.75', '1.0', '1.25', '1.5', '1.75', '2.0'])
param cpuAllocation string = '1.0'

@description('Container app memory allocation')
@allowed(['0.5Gi', '1.0Gi', '1.5Gi', '2.0Gi', '2.5Gi', '3.0Gi', '3.5Gi', '4.0Gi'])
param memoryAllocation string = '2.0Gi'

@description('Enable Application Insights monitoring')
param enableApplicationInsights bool = true

@description('Container registry admin user enabled')
param acrAdminUserEnabled bool = true

@description('Tags to apply to all resources')
param tags object = {
  project: 'mlflow-lifecycle'
  environment: environmentName
  deployedBy: 'bicep'
  purpose: 'model-serving'
}

// ==============================================================================
// VARIABLES
// ==============================================================================

var containerImage = '${containerRegistry.properties.loginServer}/model-serving:latest'
var tenantId = subscription().tenantId

// ==============================================================================
// LOG ANALYTICS WORKSPACE
// ==============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 90
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    workspaceCapping: {
      dailyQuotaGb: 5
    }
  }
}

// ==============================================================================
// APPLICATION INSIGHTS
// ==============================================================================

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
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

// ==============================================================================
// STORAGE ACCOUNT
// ==============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: true
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

// ==============================================================================
// KEY VAULT
// ==============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    vaultUri: 'https://${keyVaultName}.vault.azure.net/'
    provisioningState: 'Succeeded'
    publicNetworkAccess: 'Enabled'
  }
}

// ==============================================================================
// CONTAINER REGISTRY
// ==============================================================================

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: acrAdminUserEnabled
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

// ==============================================================================
// MACHINE LEARNING WORKSPACE
// ==============================================================================

resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: mlWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: mlWorkspaceName
    description: 'Azure Machine Learning workspace for MLflow model lifecycle management'
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: enableApplicationInsights ? applicationInsights.id : null
    containerRegistry: containerRegistry.id
    v1LegacyMode: false
    publicNetworkAccess: 'Enabled'
    imageBuildCompute: null
    allowPublicAccessWhenBehindVnet: false
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
    mlFlowTrackingUri: 'azureml://subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.MachineLearningServices/workspaces/${mlWorkspaceName}'
  }
}

// ==============================================================================
// CONTAINER APPS ENVIRONMENT
// ==============================================================================

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
    kedaConfiguration: {}
    daprConfiguration: {}
    customDomainConfiguration: {}
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

// ==============================================================================
// CONTAINER APP FOR MODEL SERVING
// ==============================================================================

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
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
          username: containerRegistry.properties.adminUserEnabled ? containerRegistry.name : null
          passwordSecretRef: containerRegistry.properties.adminUserEnabled ? 'registry-password' : null
          identity: containerRegistry.properties.adminUserEnabled ? null : containerApp.identity.principalId
        }
      ]
      secrets: containerRegistry.properties.adminUserEnabled ? [
        {
          name: 'registry-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
      ] : []
      activeRevisionsMode: 'Single'
    }
    template: {
      containers: [
        {
          image: containerImage
          name: 'model-serving'
          env: [
            {
              name: 'MODEL_NAME'
              value: modelName
            }
            {
              name: 'MODEL_VERSION'
              value: modelVersion
            }
            {
              name: 'MLFLOW_TRACKING_URI'
              value: mlWorkspace.properties.mlFlowTrackingUri
            }
            {
              name: 'SUBSCRIPTION_ID'
              value: subscription().subscriptionId
            }
            {
              name: 'RESOURCE_GROUP'
              value: resourceGroup().name
            }
            {
              name: 'WORKSPACE_NAME'
              value: mlWorkspaceName
            }
          ]
          resources: {
            cpu: json(cpuAllocation)
            memory: memoryAllocation
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 30
              periodSeconds: 30
              timeoutSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 10
              periodSeconds: 5
              timeoutSeconds: 5
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
            name: 'http-rule'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
    workloadProfileName: 'Consumption'
  }
  dependsOn: [
    containerRegistry
    mlWorkspace
  ]
}

// ==============================================================================
// RBAC ASSIGNMENTS
// ==============================================================================

// Grant Container App access to ML workspace
resource mlWorkspaceContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: mlWorkspace
  name: guid(mlWorkspace.id, containerApp.id, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Container App access to Container Registry (if using managed identity)
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!acrAdminUserEnabled) {
  scope: containerRegistry
  name: guid(containerRegistry.id, containerApp.id, 'AcrPull')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ==============================================================================
// MONITORING ALERTS
// ==============================================================================

// Alert for high response time
resource highLatencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'model-high-latency-${environmentName}-${uniqueSuffix}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when model prediction latency exceeds threshold'
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
          name: 'HighLatency'
          metricName: 'HttpResponseTime'
          operator: 'GreaterThan'
          threshold: 5000
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
  }
}

// Alert for unhealthy replicas
resource unhealthyReplicasAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'container-app-unhealthy-${environmentName}-${uniqueSuffix}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when container app replicas are unhealthy'
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
          name: 'UnhealthyReplicas'
          metricName: 'Replicas'
          operator: 'LessThan'
          threshold: 1
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
  }
}

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('The Azure region where resources were deployed')
output location string = location

@description('Machine Learning workspace name')
output mlWorkspaceName string = mlWorkspace.name

@description('Machine Learning workspace ID')
output mlWorkspaceId string = mlWorkspace.id

@description('MLflow tracking URI')
output mlflowTrackingUri string = mlWorkspace.properties.mlFlowTrackingUri

@description('Container Apps environment name')
output containerAppsEnvironmentName string = containerAppsEnvironment.name

@description('Container app name')
output containerAppName string = containerApp.name

@description('Container app FQDN for model serving')
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn

@description('Model serving endpoint URL')
output modelServingUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'

@description('Health check endpoint URL')
output healthCheckUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}/health'

@description('Model info endpoint URL')
output modelInfoUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}/model-info'

@description('Prediction endpoint URL')
output predictionUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}/predict'

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Container Registry name')
output containerRegistryName string = containerRegistry.name

@description('Container Registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Application Insights name (if enabled)')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''

@description('Application Insights instrumentation key (if enabled)')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('Container App managed identity principal ID')
output containerAppPrincipalId string = containerApp.identity.principalId

@description('ML Workspace managed identity principal ID')
output mlWorkspacePrincipalId string = mlWorkspace.identity.principalId

@description('Environment-specific tags applied to resources')
output appliedTags object = tags