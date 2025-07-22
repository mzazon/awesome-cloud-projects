// =============================================================================
// Azure Bicep Template: Distributed Cache Warm-up Workflows
// Recipe: Distributed Cache Warm-up Automation with Container Apps Jobs and Redis Enterprise
// =============================================================================

targetScope = 'resourceGroup'

// =============================================================================
// PARAMETERS
// =============================================================================

@description('The location for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Redis Enterprise VM size')
@allowed(['E10', 'E20', 'E50', 'E100'])
param redisVmSize string = 'E10'

@description('Redis cache size in GB')
@allowed([12, 25, 50, 100])
param redisCacheSize int = 12

@description('Container Apps job schedule (cron expression)')
param coordinatorJobSchedule string = '0 */6 * * *'

@description('Worker job parallelism count')
@minValue(1)
@maxValue(10)
param workerParallelism int = 4

@description('Container image registry and repository')
param containerRegistry string = 'mcr.microsoft.com'

@description('Coordinator container image tag')
param coordinatorImageTag string = 'dotnet/runtime:8.0-alpine'

@description('Worker container image tag')
param workerImageTag string = 'dotnet/runtime:8.0-alpine'

@description('Alert email address for notifications')
param alertEmailAddress string = 'admin@company.com'

@description('Tags to apply to all resources')
param resourceTags object = {
  purpose: 'cache-warmup'
  environment: environment
  recipe: 'distributed-cache-warmup'
}

// =============================================================================
// VARIABLES
// =============================================================================

var namingPrefix = 'cachewarmup-${environment}-${uniqueSuffix}'

var resourceNames = {
  logAnalytics: 'log-${namingPrefix}'
  containerEnv: 'env-${namingPrefix}'
  coordinatorJob: 'job-coordinator-${namingPrefix}'
  workerJob: 'job-worker-${namingPrefix}'
  redis: 'redis-${namingPrefix}'
  storage: 'st${replace(namingPrefix, '-', '')}'
  keyVault: 'kv-${namingPrefix}'
  actionGroup: 'ag-${namingPrefix}'
  managedIdentity: 'mi-${namingPrefix}'
}

// =============================================================================
// MANAGED IDENTITY
// =============================================================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: resourceNames.managedIdentity
  location: location
  tags: resourceTags
}

// =============================================================================
// LOG ANALYTICS WORKSPACE
// =============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalytics
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
  }
}

// =============================================================================
// STORAGE ACCOUNT
// =============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: resourceNames.storage
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource coordinationContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'coordination'
  properties: {
    publicAccess: 'None'
  }
}

// =============================================================================
// KEY VAULT
// =============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: resourceTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
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

// =============================================================================
// REDIS ENTERPRISE CACHE
// =============================================================================

resource redisEnterprise 'Microsoft.Cache/redis@2024-03-01' = {
  name: resourceNames.redis
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'Enterprise'
      family: 'E'
      capacity: redisCacheSize
    }
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
    }
    redisVersion: '6.0'
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// Store Redis connection string in Key Vault
resource redisConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-connection-string'
  properties: {
    value: 'Server=${redisEnterprise.properties.hostName}:${redisEnterprise.properties.sslPort};Password=${redisEnterprise.listKeys().primaryKey};Database=0;Ssl=True'
  }
}

// =============================================================================
// CONTAINER APPS ENVIRONMENT
// =============================================================================

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: resourceNames.containerEnv
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

// =============================================================================
// RBAC ASSIGNMENTS
// =============================================================================

// Storage Blob Data Contributor role for managed identity
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Secrets User role for managed identity
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentity.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// CONTAINER APPS JOBS
// =============================================================================

// Coordinator Job - Orchestrates cache warm-up workflow
resource coordinatorJob 'Microsoft.App/jobs@2024-03-01' = {
  name: resourceNames.coordinatorJob
  location: location
  tags: resourceTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      scheduleTriggerConfig: {
        cronExpression: coordinatorJobSchedule
        parallelism: 1
        completions: 1
      }
      triggerType: 'Schedule'
      replicaTimeout: 1800
      replicaRetryLimit: 1
    }
    template: {
      containers: [
        {
          name: 'coordinator'
          image: '${containerRegistry}/${coordinatorImageTag}'
          resources: {
            cpu: '0.5'
            memory: '1.0Gi'
          }
          env: [
            {
              name: 'AZURE_CLIENT_ID'
              value: managedIdentity.properties.clientId
            }
            {
              name: 'STORAGE_ACCOUNT_NAME'
              value: storageAccount.name
            }
            {
              name: 'KEY_VAULT_NAME'
              value: keyVault.name
            }
            {
              name: 'WORKER_JOB_NAME'
              value: resourceNames.workerJob
            }
            {
              name: 'RESOURCE_GROUP'
              value: resourceGroup().name
            }
            {
              name: 'SUBSCRIPTION_ID'
              value: subscription().subscriptionId
            }
          ]
        }
      ]
    }
  }
  dependsOn: [
    storageRoleAssignment
    keyVaultRoleAssignment
  ]
}

// Worker Job - Executes cache population tasks
resource workerJob 'Microsoft.App/jobs@2024-03-01' = {
  name: resourceNames.workerJob
  location: location
  tags: resourceTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      manualTriggerConfig: {
        parallelism: workerParallelism
        completions: workerParallelism
      }
      triggerType: 'Manual'
      replicaTimeout: 3600
      replicaRetryLimit: 2
    }
    template: {
      containers: [
        {
          name: 'worker'
          image: '${containerRegistry}/${workerImageTag}'
          resources: {
            cpu: '0.25'
            memory: '0.5Gi'
          }
          env: [
            {
              name: 'AZURE_CLIENT_ID'
              value: managedIdentity.properties.clientId
            }
            {
              name: 'STORAGE_ACCOUNT_NAME'
              value: storageAccount.name
            }
            {
              name: 'KEY_VAULT_NAME'
              value: keyVault.name
            }
            {
              name: 'WORKER_ID'
              value: '{{.JobName}}-{{.ReplicaName}}'
            }
          ]
        }
      ]
    }
  }
  dependsOn: [
    storageRoleAssignment
    keyVaultRoleAssignment
  ]
}

// =============================================================================
// MONITORING AND ALERTS
// =============================================================================

// Action Group for alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: resourceNames.actionGroup
  location: 'Global'
  tags: resourceTags
  properties: {
    groupShortName: 'CacheWarmup'
    enabled: true
    emailReceivers: [
      {
        name: 'admin'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// Alert rule for job failures
resource jobFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Cache Warmup Job Failures'
  location: 'Global'
  tags: resourceTags
  properties: {
    description: 'Alert when cache warm-up job fails'
    severity: 2
    enabled: true
    scopes: [
      coordinatorJob.id
      workerJob.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'JobFailures'
          metricName: 'JobExecutions'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Count'
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
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Alert rule for Redis high memory usage
resource redisMemoryAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Redis High Memory Usage'
  location: 'Global'
  tags: resourceTags
  properties: {
    description: 'Alert when Redis memory usage exceeds 80%'
    severity: 2
    enabled: true
    scopes: [
      redisEnterprise.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighMemoryUsage'
          metricName: 'percentProcessorTime'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
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

// =============================================================================
// OUTPUTS
// =============================================================================

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Container Apps Environment name')
output containerEnvironmentName string = containerAppsEnvironment.name

@description('Container Apps Environment ID')
output containerEnvironmentId string = containerAppsEnvironment.id

@description('Coordinator Job name')
output coordinatorJobName string = coordinatorJob.name

@description('Worker Job name')
output workerJobName string = workerJob.name

@description('Redis Enterprise hostname')
output redisHostname string = redisEnterprise.properties.hostName

@description('Redis Enterprise SSL port')
output redisPort int = redisEnterprise.properties.sslPort

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Managed Identity Client ID')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Managed Identity Principal ID')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Action Group ID for monitoring alerts')
output actionGroupId string = actionGroup.id

@description('Deployment summary with key resource information')
output deploymentSummary object = {
  environment: environment
  location: location
  redis: {
    name: redisEnterprise.name
    hostname: redisEnterprise.properties.hostName
    port: redisEnterprise.properties.sslPort
    vmSize: redisVmSize
  }
  containerApps: {
    environment: containerAppsEnvironment.name
    coordinatorJob: coordinatorJob.name
    workerJob: workerJob.name
    parallelism: workerParallelism
  }
  storage: {
    account: storageAccount.name
    coordinationContainer: coordinationContainer.name
  }
  security: {
    keyVault: keyVault.name
    managedIdentity: managedIdentity.name
  }
  monitoring: {
    logAnalytics: logAnalyticsWorkspace.name
    actionGroup: actionGroup.name
  }
}