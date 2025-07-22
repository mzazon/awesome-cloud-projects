// Main Bicep template for implementing secure container orchestration
// with Azure Container Apps and Azure Key Vault

@description('Environment name for consistent resource naming')
@minLength(3)
@maxLength(8)
param environmentName string = 'secure'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Unique suffix for globally unique resource names')
@minLength(3)
@maxLength(6)
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Resource tags to apply to all resources')
param tags object = {
  purpose: 'recipe'
  environment: 'demo'
  owner: 'container-apps-recipe'
}

@description('Container registry admin user enabled')
param acrAdminUserEnabled bool = false

@description('Container registry SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string = 'Standard'

@description('Key Vault SKU')
@allowed(['standard', 'premium'])
param keyVaultSku string = 'standard'

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Container Apps Environment internal Load Balancer enabled')
param containerAppsInternalOnly bool = false

@description('API service container image')
param apiServiceImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Worker service container image')
param workerServiceImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('API service CPU allocation')
@allowed(['0.25', '0.5', '0.75', '1.0', '1.25', '1.5', '1.75', '2.0'])
param apiServiceCpu string = '0.5'

@description('API service memory allocation')
@allowed(['0.5Gi', '1.0Gi', '1.5Gi', '2.0Gi', '3.0Gi', '4.0Gi'])
param apiServiceMemory string = '1.0Gi'

@description('Worker service CPU allocation')
@allowed(['0.25', '0.5', '0.75', '1.0', '1.25', '1.5', '1.75', '2.0'])
param workerServiceCpu string = '0.25'

@description('Worker service memory allocation')
@allowed(['0.5Gi', '1.0Gi', '1.5Gi', '2.0Gi', '3.0Gi', '4.0Gi'])
param workerServiceMemory string = '0.5Gi'

@description('API service minimum replicas')
@minValue(0)
@maxValue(10)
param apiServiceMinReplicas int = 1

@description('API service maximum replicas')
@minValue(1)
@maxValue(25)
param apiServiceMaxReplicas int = 5

@description('Worker service minimum replicas')
@minValue(0)
@maxValue(10)
param workerServiceMinReplicas int = 0

@description('Worker service maximum replicas')
@minValue(1)
@maxValue(25)
param workerServiceMaxReplicas int = 3

// Variables for resource naming
var acrName = 'acr${environmentName}${uniqueSuffix}'
var keyVaultName = 'kv-${environmentName}-${uniqueSuffix}'
var logAnalyticsName = 'law-${environmentName}-${uniqueSuffix}'
var containerAppsEnvironmentName = 'cae-${environmentName}-${uniqueSuffix}'
var appInsightsName = 'ai-${environmentName}-${uniqueSuffix}'
var apiServiceName = 'api-service'
var workerServiceName = 'worker-service'

// Sample secrets for demonstration
var secrets = {
  databaseConnectionString: 'Server=tcp:myserver.database.windows.net;Database=mydb;Authentication=Active Directory Managed Identity;'
  apiKey: 'sample-api-key-${uniqueSuffix}'
  serviceBusConnection: 'Endpoint=sb://namespace.servicebus.windows.net/;Authentication=Managed Identity'
}

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// Azure Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: acrAdminUserEnabled
    anonymousPullEnabled: false
    networkRuleSet: {
      defaultAction: 'Allow'
    }
    policies: {
      exportPolicy: {
        status: 'enabled'
      }
      quarantinePolicy: {
        status: 'disabled'
      }
      retentionPolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        status: 'disabled'
      }
    }
  }
}

// Azure Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    tenantId: subscription().tenantId
    accessPolicies: []
    enableRbacAuthorization: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Key Vault Secrets
resource secretDatabaseConnection 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'DatabaseConnectionString'
  properties: {
    value: secrets.databaseConnectionString
  }
}

resource secretApiKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ApiKey'
  properties: {
    value: secrets.apiKey
  }
}

resource secretServiceBusConnection 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ServiceBusConnection'
  properties: {
    value: secrets.serviceBusConnection
  }
}

// Container Apps Environment
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: containerAppsInternalOnly ? {
      internal: true
    } : null
  }
}

// API Service Container App
resource apiServiceApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: apiServiceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: false
      }
      registries: [
        {
          identity: 'system'
          server: containerRegistry.properties.loginServer
        }
      ]
      secrets: [
        {
          name: 'db-connection'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/DatabaseConnectionString'
          identity: 'system'
        }
        {
          name: 'api-key'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/ApiKey'
          identity: 'system'
        }
        {
          name: 'appinsights-key'
          value: appInsights.properties.InstrumentationKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: apiServiceName
          image: apiServiceImage
          resources: {
            cpu: json(apiServiceCpu)
            memory: apiServiceMemory
          }
          env: [
            {
              name: 'DATABASE_CONNECTION'
              secretRef: 'db-connection'
            }
            {
              name: 'API_KEY'
              secretRef: 'api-key'
            }
            {
              name: 'ENVIRONMENT'
              value: 'Production'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-key'
            }
          ]
        }
      ]
      scale: {
        minReplicas: apiServiceMinReplicas
        maxReplicas: apiServiceMaxReplicas
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
  }
}

// Worker Service Container App
resource workerServiceApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: workerServiceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: false
        targetPort: 80
        allowInsecure: false
      }
      registries: [
        {
          identity: 'system'
          server: containerRegistry.properties.loginServer
        }
      ]
      secrets: [
        {
          name: 'servicebus-connection'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/ServiceBusConnection'
          identity: 'system'
        }
      ]
    }
    template: {
      containers: [
        {
          name: workerServiceName
          image: workerServiceImage
          resources: {
            cpu: json(workerServiceCpu)
            memory: workerServiceMemory
          }
          env: [
            {
              name: 'SERVICEBUS_CONNECTION'
              secretRef: 'servicebus-connection'
            }
            {
              name: 'ENVIRONMENT'
              value: 'Production'
            }
          ]
        }
      ]
      scale: {
        minReplicas: workerServiceMinReplicas
        maxReplicas: workerServiceMaxReplicas
        rules: [
          {
            name: 'cpu-rule'
            custom: {
              type: 'cpu'
              metadata: {
                type: 'Utilization'
                value: '70'
              }
            }
          }
        ]
      }
    }
  }
}

// Key Vault Access Policy for API Service
resource keyVaultAccessPolicyApiService 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: apiServiceApp.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
}

// Key Vault Access Policy for Worker Service
resource keyVaultAccessPolicyWorkerService 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: workerServiceApp.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
  }
  dependsOn: [
    keyVaultAccessPolicyApiService
  ]
}

// Container Registry Role Assignment for API Service
resource acrPullRoleApiService 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(containerRegistry.id, apiServiceApp.id, 'AcrPull')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: apiServiceApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Container Registry Role Assignment for Worker Service
resource acrPullRoleWorkerService 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(containerRegistry.id, workerServiceApp.id, 'AcrPull')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: workerServiceApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// High CPU Alert for API Service
resource highCpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'high-cpu-alert-${apiServiceName}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when CPU usage exceeds 80% for API service'
    severity: 2
    enabled: true
    scopes: [
      apiServiceApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'cpu-usage'
          metricName: 'UsageNanoCores'
          metricNamespace: 'Microsoft.App/containerApps'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

// Outputs
@description('Container Registry name')
output containerRegistryName string = containerRegistry.name

@description('Container Registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Container Apps Environment name')
output containerAppsEnvironmentName string = containerAppsEnvironment.name

@description('API Service FQDN')
output apiServiceFqdn string = apiServiceApp.properties.configuration.ingress.fqdn

@description('API Service URL')
output apiServiceUrl string = 'https://${apiServiceApp.properties.configuration.ingress.fqdn}'

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalytics.name

@description('Application Insights name')
output applicationInsightsName string = appInsights.name

@description('API Service managed identity principal ID')
output apiServicePrincipalId string = apiServiceApp.identity.principalId

@description('Worker Service managed identity principal ID')
output workerServicePrincipalId string = workerServiceApp.identity.principalId

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Environment unique suffix')
output uniqueSuffix string = uniqueSuffix