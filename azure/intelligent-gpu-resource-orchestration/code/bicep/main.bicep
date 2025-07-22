@description('Intelligent GPU Resource Orchestration with Container Apps and Azure Batch')
@minLength(2)
@maxLength(10)
param resourceNameSuffix string = uniqueString(resourceGroup().id)

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment tag for resources')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Container Apps environment workload profiles')
param workloadProfiles array = [
  {
    name: 'Consumption'
    workloadProfileType: 'Consumption'
  }
]

@description('Azure Batch pool VM size for GPU nodes')
@allowed(['Standard_NC6s_v3', 'Standard_NC12s_v3', 'Standard_NC24s_v3', 'Standard_ND40rs_v2'])
param batchPoolVmSize string = 'Standard_NC6s_v3'

@description('Maximum number of low-priority nodes in Batch pool')
@minValue(0)
@maxValue(10)
param maxLowPriorityNodes int = 2

@description('Container Apps maximum replicas')
@minValue(1)
@maxValue(20)
param containerAppMaxReplicas int = 10

@description('Enable Azure Monitor for comprehensive observability')
param enableMonitoring bool = true

@description('Function App runtime stack')
@allowed(['python', 'node', 'dotnet'])
param functionAppRuntime string = 'python'

// Variables for resource naming
var resourceNames = {
  logAnalytics: 'logs-gpu-${resourceNameSuffix}'
  appInsights: 'appi-gpu-${resourceNameSuffix}'
  containerAppEnv: 'aca-env-${resourceNameSuffix}'
  containerApp: 'ml-inference-app'
  batchAccount: 'batch${resourceNameSuffix}'
  keyVault: 'kv-gpu-${resourceNameSuffix}'
  storageAccount: 'storage${resourceNameSuffix}'
  functionApp: 'router-func-${resourceNameSuffix}'
  appServicePlan: 'asp-func-${resourceNameSuffix}'
}

var commonTags = {
  Environment: environment
  Purpose: 'gpu-orchestration'
  ManagedBy: 'bicep'
  Recipe: 'orchestrating-dynamic-gpu-resource-allocation'
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableMonitoring) {
  name: resourceNames.logAnalytics
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

// Application Insights for Function App monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableMonitoring) {
  name: resourceNames.appInsights
  location: location
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableMonitoring ? logAnalyticsWorkspace.id : null
  }
}

// Storage Account for Function App and Batch queues
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: commonTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Storage Queue Service
resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

// Batch inference queue
resource batchInferenceQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-01-01' = {
  parent: queueService
  name: 'batch-inference-queue'
}

// Dead letter queue for failed batch jobs
resource deadLetterQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-01-01' = {
  parent: queueService
  name: 'batch-inference-dlq'
}

// Key Vault for secure configuration management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: commonTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enabledForDeployment: false
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

// Azure Batch Account
resource batchAccount 'Microsoft.Batch/batchAccounts@2024-02-01' = {
  name: resourceNames.batchAccount
  location: location
  tags: commonTags
  properties: {
    autoStorage: {
      storageAccountId: storageAccount.id
    }
    poolAllocationMode: 'BatchService'
    publicNetworkAccess: 'Enabled'
  }
}

// GPU Pool for Azure Batch
resource batchPool 'Microsoft.Batch/batchAccounts/pools@2024-02-01' = {
  parent: batchAccount
  name: 'gpu-pool'
  properties: {
    displayName: 'GPU Processing Pool'
    vmSize: batchPoolVmSize
    interNodeCommunication: 'Disabled'
    taskSlotsPerNode: 1
    taskSchedulingPolicy: {
      nodeFillType: 'Pack'
    }
    deploymentConfiguration: {
      virtualMachineConfiguration: {
        imageReference: {
          publisher: 'microsoft-azure-batch'
          offer: 'ubuntu-server-container'
          sku: '20-04-lts'
          version: 'latest'
        }
        nodeAgentSkuId: 'batch.node.ubuntu 20.04'
      }
    }
    scaleSettings: {
      autoScale: {
        evaluationInterval: 'PT5M'
        formula: '$TargetDedicatedNodes = min($PendingTasks.GetSample(180 * TimeInterval_Second, 70 * TimeInterval_Second), 4);'
      }
    }
    startTask: {
      commandLine: 'apt-get update && apt-get install -y python3-pip && pip3 install azure-storage-queue torch torchvision'
      userIdentity: {
        autoUser: {
          scope: 'Pool'
          elevationLevel: 'Admin'
        }
      }
      waitForSuccess: true
    }
    targetDedicatedNodes: 0
    targetLowPriorityNodes: maxLowPriorityNodes
  }
}

// Container Apps Environment
resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: resourceNames.containerAppEnv
  location: location
  tags: commonTags
  properties: {
    appLogsConfiguration: enableMonitoring ? {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    } : null
    workloadProfiles: workloadProfiles
  }
}

// ML Inference Container App
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: resourceNames.containerApp
  location: location
  tags: commonTags
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      secrets: []
    }
    template: {
      containers: [
        {
          name: resourceNames.containerApp
          image: 'mcr.microsoft.com/azuredocs/aci-tutorial-app:latest'
          env: [
            {
              name: 'MODEL_PATH'
              value: '/models'
            }
            {
              name: 'GPU_ENABLED'
              value: 'true'
            }
          ]
          resources: {
            cpu: '4.0'
            memory: '8Gi'
          }
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: containerAppMaxReplicas
        rules: [
          {
            name: 'http-scale-rule'
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

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: resourceNames.appServicePlan
  location: location
  tags: commonTags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

// Function App for request routing
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: resourceNames.functionApp
  location: location
  tags: commonTags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    reserved: true
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: functionAppRuntime == 'python' ? 'Python|3.11' : (functionAppRuntime == 'node' ? 'Node|18' : 'DOTNET|6.0')
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
          value: resourceNames.functionApp
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
          name: 'KEY_VAULT_URL'
          value: keyVault.properties.vaultUri
        }
        {
          name: 'ACA_ENDPOINT'
          value: 'https://${containerApp.properties.configuration.ingress.fqdn}'
        }
        {
          name: 'BATCH_ACCOUNT_NAME'
          value: batchAccount.name
        }
        {
          name: 'BATCH_POOL_ID'
          value: 'gpu-pool'
        }
        {
          name: 'STORAGE_QUEUE_NAME'
          value: 'batch-inference-queue'
        }
        {
          name: 'LOG_ANALYTICS_WORKSPACE_ID'
          value: enableMonitoring ? logAnalyticsWorkspace.properties.customerId : ''
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
    }
  }
}

// Key Vault Secrets User role assignment for Function App
resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionApp.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Store configuration secrets in Key Vault
resource realtimeThresholdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'realtime-threshold-ms'
  properties: {
    value: '2000'
    attributes: {
      enabled: true
    }
  }
}

resource batchCostThresholdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'batch-cost-threshold'
  properties: {
    value: '0.50'
    attributes: {
      enabled: true
    }
  }
}

resource maxAcaReplicasSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'max-aca-replicas'
  properties: {
    value: string(containerAppMaxReplicas)
    attributes: {
      enabled: true
    }
  }
}

resource maxBatchNodesSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'max-batch-nodes'
  properties: {
    value: '4'
    attributes: {
      enabled: true
    }
  }
}

resource modelVersionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'model-version'
  properties: {
    value: 'v1.0'
    attributes: {
      enabled: true
    }
  }
}

resource gpuMemoryLimitSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'gpu-memory-limit'
  properties: {
    value: '16384'
    attributes: {
      enabled: true
    }
  }
}

resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-connection-string'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    attributes: {
      enabled: true
    }
  }
}

// Azure Monitor Alert Rules (if monitoring is enabled)
resource highGpuUtilizationAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: 'HighGPUUtilization'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'High GPU utilization detected'
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
          name: 'HighRequests'
          metricName: 'Requests'
          operator: 'GreaterThan'
          threshold: 50
          timeAggregation: 'Average'
        }
      ]
    }
    actions: []
  }
}

resource highBatchQueueDepthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: 'HighBatchQueueDepth'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'High batch queue depth detected'
    severity: 3
    enabled: true
    scopes: [
      storageAccount.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighQueueDepth'
          metricName: 'ApproximateMessageCount'
          operator: 'GreaterThan'
          threshold: 100
          timeAggregation: 'Average'
        }
      ]
    }
    actions: []
  }
}

// Outputs for integration and verification
@description('Container App FQDN for ML inference endpoint')
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn

@description('Container App endpoint URL')
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'

@description('Azure Batch account name')
output batchAccountName string = batchAccount.name

@description('Azure Batch pool ID')
output batchPoolId string = 'gpu-pool'

@description('Function App name for request routing')
output functionAppName string = functionApp.name

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('Key Vault URI for configuration management')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage queue name for batch processing')
output batchQueueName string = 'batch-inference-queue'

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = enableMonitoring ? logAnalyticsWorkspace.properties.customerId : ''

@description('Application Insights instrumentation key')
output appInsightsInstrumentationKey string = enableMonitoring ? applicationInsights.properties.InstrumentationKey : ''

@description('Resource group name where resources are deployed')
output resourceGroupName string = resourceGroup().name

@description('Deployment location')
output deploymentLocation string = location

@description('Resource name suffix used for unique naming')
output resourceSuffix string = resourceNameSuffix

@description('All created resource names for reference')
output resourceNames object = {
  containerAppEnvironment: containerAppEnvironment.name
  containerApp: containerApp.name
  batchAccount: batchAccount.name
  keyVault: keyVault.name
  storageAccount: storageAccount.name
  functionApp: functionApp.name
  logAnalyticsWorkspace: enableMonitoring ? logAnalyticsWorkspace.name : ''
  applicationInsights: enableMonitoring ? applicationInsights.name : ''
}