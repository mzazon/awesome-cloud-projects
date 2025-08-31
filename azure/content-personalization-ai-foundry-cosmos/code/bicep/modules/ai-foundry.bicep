@description('AI Foundry Workspace module (Machine Learning Workspace) for AI orchestration')

// Parameters
@description('Name of the AI Foundry workspace')
param workspaceName string

@description('Azure region for resource deployment')
param location string

@description('Resource ID of the storage account')
param storageAccountId string

@description('Resource ID of the Application Insights component')
param applicationInsightsId string

@description('Tags to apply to the resource')
param tags object = {}

@description('Description of the workspace')
param description string = 'AI Foundry workspace for content personalization orchestration'

@description('Discovery URL for the workspace')
param discoveryUrl string = ''

@description('Whether to allow public access when behind VNet')
@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

@description('Workspace SKU')
@allowed(['Basic', 'Free'])
param sku string = 'Basic'

// Variables
var keyVaultName = 'kv-${take(replace(workspaceName, '-', ''), 17)}-${uniqueString(resourceGroup().id)}'

// Resources

// Key Vault for AI Foundry workspace
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: []
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// AI Foundry Workspace (Machine Learning Workspace)
resource aiFoundryWorkspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: workspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: description
    friendlyName: workspaceName
    discoveryUrl: discoveryUrl
    storageAccount: storageAccountId
    keyVault: keyVault.id
    applicationInsights: applicationInsightsId
    publicNetworkAccess: publicNetworkAccess
    imageBuildCompute: null
    allowPublicAccessWhenBehindVnet: publicNetworkAccess == 'Enabled'
    v1LegacyMode: false
    containerRegistry: null
    encryption: {
      status: 'Disabled'
    }
    hbiWorkspace: false
    featureStoreSettings: {
      computeRuntime: {
        sparkRuntimeVersion: '3.3'
      }
      offlineStoreConnectionName: ''
      onlineStoreConnectionName: ''
    }
  }
  sku: {
    name: sku
    tier: sku
  }
}

// Outputs
@description('AI Foundry Workspace Resource ID')
output workspaceId string = aiFoundryWorkspace.id

@description('AI Foundry Workspace Name')
output workspaceName string = aiFoundryWorkspace.name

@description('AI Foundry Workspace Discovery URL')
output discoveryUrl string = aiFoundryWorkspace.properties.discoveryUrl

@description('AI Foundry Workspace MLFlow Tracking URI')
output mlflowTrackingUri string = aiFoundryWorkspace.properties.mlFlowTrackingUri

@description('Key Vault Resource ID')
output keyVaultId string = keyVault.id

@description('Key Vault Name')
output keyVaultName string = keyVault.name

@description('Workspace Principal ID for RBAC assignments')
output workspacePrincipalId string = aiFoundryWorkspace.identity.principalId

@description('Workspace Configuration Summary')
output workspaceConfig object = {
  name: aiFoundryWorkspace.name
  location: location
  sku: sku
  publicNetworkAccess: publicNetworkAccess
  storageAccount: storageAccountId
  keyVault: keyVault.id
  applicationInsights: applicationInsightsId
}