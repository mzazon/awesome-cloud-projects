@description('Bicep module for Azure OpenAI Service with GPT model deployment')

// Parameters
@description('The location/region where resources will be deployed')
param location string

@description('Cognitive Services account name')
param cognitiveServicesName string

@description('OpenAI model name to deploy')
@allowed(['gpt-4', 'gpt-4-32k', 'gpt-35-turbo', 'gpt-35-turbo-16k'])
param modelName string = 'gpt-4'

@description('OpenAI model version')
param modelVersion string = '0613'

@description('Model deployment capacity (TPM - Tokens per minute)')
@minValue(1)
@maxValue(120)
param modelCapacity int = 10

@description('Tags to apply to resources')
param tags object = {}

@description('Custom subdomain for the cognitive services account')
param customSubDomainName string = cognitiveServicesName

@description('Public network access setting')
@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

@description('SKU for the Cognitive Services account')
@allowed(['S0'])
param sku string = 'S0'

// Variables
var modelDeploymentName = '${modelName}-deployment'

// Azure OpenAI Service (Cognitive Services)
resource cognitiveServicesAccount 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: cognitiveServicesName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  kind: 'OpenAI'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: customSubDomainName
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: publicNetworkAccess
    apiProperties: {
      statisticsEnabled: false
    }
    disableLocalAuth: false
  }
}

// Model Deployment
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: cognitiveServicesAccount
  name: modelDeploymentName
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
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.Default'
  }
}

// Diagnostic Settings for OpenAI Service
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: cognitiveServicesAccount
  properties: {
    logs: [
      {
        category: 'Audit'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'RequestResponse'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'Trace'
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

// Content Filter Policy (optional - for custom content filtering)
resource contentFilterPolicy 'Microsoft.CognitiveServices/accounts/raiPolicies@2023-10-01-preview' = {
  parent: cognitiveServicesAccount
  name: 'CustomContentFilter'
  properties: {
    mode: 'Default'
    contentFilters: [
      {
        name: 'Hate'
        allowedContentLevel: 'Medium'
        blocking: true
        enabled: true
        source: 'Prompt'
      }
      {
        name: 'Violence'
        allowedContentLevel: 'Medium'
        blocking: true
        enabled: true
        source: 'Prompt'
      }
      {
        name: 'SelfHarm'
        allowedContentLevel: 'Medium'
        blocking: true
        enabled: true
        source: 'Prompt'
      }
      {
        name: 'Sexual'
        allowedContentLevel: 'Medium'
        blocking: true
        enabled: true
        source: 'Prompt'
      }
    ]
  }
}

// Outputs
@description('Cognitive Services account ID')
output cognitiveServicesId string = cognitiveServicesAccount.id

@description('Cognitive Services account name')
output cognitiveServicesName string = cognitiveServicesAccount.name

@description('OpenAI Service endpoint')
output endpoint string = cognitiveServicesAccount.properties.endpoint

@description('Model deployment name')
output modelDeploymentName string = modelDeployment.name

@description('Model deployment ID')
output modelDeploymentId string = modelDeployment.id

@description('Primary access key for OpenAI Service')
@secure()
output primaryKey string = cognitiveServicesAccount.listKeys().key1

@description('Secondary access key for OpenAI Service')
@secure()
output secondaryKey string = cognitiveServicesAccount.listKeys().key2

@description('Custom subdomain name')
output customSubDomainName string = cognitiveServicesAccount.properties.customSubDomainName

@description('Principal ID of the system-assigned managed identity')
output principalId string = cognitiveServicesAccount.identity.principalId

@description('Tenant ID of the system-assigned managed identity')
output tenantId string = cognitiveServicesAccount.identity.tenantId

@description('Secret name for Key Vault storage')
output keySecretName string = 'openai-api-key'

@description('Model configuration')
output modelConfiguration object = {
  name: modelName
  version: modelVersion
  deploymentName: modelDeploymentName
  capacity: modelCapacity
  endpoint: cognitiveServicesAccount.properties.endpoint
}