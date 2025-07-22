@description('Main Bicep template for implementing automated infrastructure deployment workflows with Azure Container Apps Jobs and ARM templates')

// Parameters
@description('Base name for all resources. A unique suffix will be appended to ensure global uniqueness.')
@minLength(3)
@maxLength(15)
param baseName string = 'deploy-auto'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment tag for resource organization')
@allowed(['dev', 'test', 'staging', 'prod'])
param environment string = 'dev'

@description('Container image for deployment jobs')
param containerImage string = 'mcr.microsoft.com/azure-cli:latest'

@description('CPU allocation for Container Apps Jobs')
@allowed(['0.25', '0.5', '0.75', '1.0', '1.25', '1.5', '1.75', '2.0'])
param cpuCores string = '0.5'

@description('Memory allocation for Container Apps Jobs')
@allowed(['0.5Gi', '1.0Gi', '1.5Gi', '2.0Gi', '3.0Gi', '4.0Gi'])
param memorySize string = '1.0Gi'

@description('Cron expression for scheduled deployments (default: daily at 2 AM UTC)')
param cronExpression string = '0 2 * * *'

@description('Enable Key Vault integration for secure credential storage')
param enableKeyVault bool = true

@description('Enable scheduled deployment job')
param enableScheduledJob bool = true

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var containerAppsEnvironmentName = '${baseName}-cae-${uniqueSuffix}'
var deploymentJobName = '${baseName}-job-${uniqueSuffix}'
var scheduledJobName = '${baseName}-scheduled-${uniqueSuffix}'
var storageAccountName = '${replace(baseName, '-', '')}st${uniqueSuffix}'
var keyVaultName = '${baseName}-kv-${uniqueSuffix}'
var managedIdentityName = '${baseName}-id-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${baseName}-logs-${uniqueSuffix}'

// Common tags
var commonTags = {
  Environment: environment
  Purpose: 'deployment-automation'
  ManagedBy: 'bicep'
  Solution: 'container-apps-deployment-workflow'
}

// Log Analytics Workspace for Container Apps
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

// Managed Identity for Container Apps Jobs
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: commonTags
}

// Storage Account for deployment artifacts
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
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
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
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

// Storage containers for organized artifact storage
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource armTemplatesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'arm-templates'
  properties: {
    publicAccess: 'None'
  }
}

resource deploymentLogsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'deployment-logs'
  properties: {
    publicAccess: 'None'
  }
}

resource deploymentScriptsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'deployment-scripts'
  properties: {
    publicAccess: 'None'
  }
}

// Key Vault for secure credential storage
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = if (enableKeyVault) {
  name: keyVaultName
  location: location
  tags: commonTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    purgeProtectionEnabled: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Container Apps Environment
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: commonTags
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

// Manual trigger deployment job
resource deploymentJob 'Microsoft.App/jobs@2024-03-01' = {
  name: deploymentJobName
  location: location
  tags: commonTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 1800
      replicaRetryLimit: 3
    }
    template: {
      containers: [
        {
          name: 'deployment-container'
          image: containerImage
          resources: {
            cpu: json(cpuCores)
            memory: memorySize
          }
          env: [
            {
              name: 'STORAGE_ACCOUNT_NAME'
              value: storageAccount.name
            }
            {
              name: 'LOCATION'
              value: location
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: managedIdentity.properties.clientId
            }
            {
              name: 'KEY_VAULT_NAME'
              value: enableKeyVault ? keyVault.name : ''
            }
          ]
          command: [
            '/bin/bash'
          ]
          args: [
            '-c'
            'az login --identity && az storage blob download --container-name deployment-scripts --name deploy-script.sh --file /tmp/deploy-script.sh --account-name $STORAGE_ACCOUNT_NAME --auth-mode login && chmod +x /tmp/deploy-script.sh && /tmp/deploy-script.sh'
          ]
        }
      ]
    }
  }
}

// Scheduled deployment job (conditional)
resource scheduledDeploymentJob 'Microsoft.App/jobs@2024-03-01' = if (enableScheduledJob) {
  name: scheduledJobName
  location: location
  tags: commonTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      triggerType: 'Schedule'
      scheduleTriggerConfig: {
        cronExpression: cronExpression
      }
      replicaTimeout: 1800
      replicaRetryLimit: 3
    }
    template: {
      containers: [
        {
          name: 'scheduled-deployment-container'
          image: containerImage
          resources: {
            cpu: json(cpuCores)
            memory: memorySize
          }
          env: [
            {
              name: 'STORAGE_ACCOUNT_NAME'
              value: storageAccount.name
            }
            {
              name: 'LOCATION'
              value: location
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: managedIdentity.properties.clientId
            }
            {
              name: 'KEY_VAULT_NAME'
              value: enableKeyVault ? keyVault.name : ''
            }
          ]
          command: [
            '/bin/bash'
          ]
          args: [
            '-c'
            'az login --identity && az storage blob download --container-name deployment-scripts --name deploy-script.sh --file /tmp/deploy-script.sh --account-name $STORAGE_ACCOUNT_NAME --auth-mode login && chmod +x /tmp/deploy-script.sh && /tmp/deploy-script.sh'
          ]
        }
      ]
    }
  }
}

// RBAC Role Assignments

// Contributor role for ARM deployments at subscription level
resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, managedIdentity.id, 'contributor')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Data Contributor role
resource storageBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, 'storage-blob-data-contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Secrets User role (conditional)
resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableKeyVault) {
  name: guid(keyVault.id, managedIdentity.id, 'key-vault-secrets-user')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('Resource group name where resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('Container Apps Environment name')
output containerAppsEnvironmentName string = containerAppsEnvironment.name

@description('Manual deployment job name')
output deploymentJobName string = deploymentJob.name

@description('Scheduled deployment job name (if enabled)')
output scheduledJobName string = enableScheduledJob ? scheduledDeploymentJob.name : ''

@description('Storage account name for deployment artifacts')
output storageAccountName string = storageAccount.name

@description('Key Vault name for secure credential storage (if enabled)')
output keyVaultName string = enableKeyVault ? keyVault.name : ''

@description('Managed identity name for Container Apps Jobs')
output managedIdentityName string = managedIdentity.name

@description('Managed identity client ID')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Managed identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Log Analytics Workspace ID for monitoring')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Storage account connection information')
output storageAccountDetails object = {
  name: storageAccount.name
  primaryEndpoints: storageAccount.properties.primaryEndpoints
  containers: [
    'arm-templates'
    'deployment-logs'
    'deployment-scripts'
  ]
}

@description('Container Apps Jobs information')
output containerAppsJobsInfo object = {
  environment: {
    name: containerAppsEnvironment.name
    id: containerAppsEnvironment.id
  }
  manualJob: {
    name: deploymentJob.name
    id: deploymentJob.id
  }
  scheduledJob: enableScheduledJob ? {
    name: scheduledDeploymentJob.name
    id: scheduledDeploymentJob.id
    cronExpression: cronExpression
  } : null
}

@description('RBAC assignments created')
output rbacAssignments object = {
  contributor: {
    scope: 'subscription'
    roleDefinitionId: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
  }
  storageBlobDataContributor: {
    scope: storageAccount.name
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  }
  keyVaultSecretsUser: enableKeyVault ? {
    scope: keyVault.name
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6'
  } : null
}