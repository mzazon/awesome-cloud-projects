@description('Azure OpenAI Service module for content generation and embeddings')

// Parameters
@description('Name of the Azure OpenAI service')
param openAiServiceName string

@description('Azure region for resource deployment')
param location string

@description('Model deployment configurations')
param models object

@description('Tags to apply to the resource')
param tags object = {}

@description('SKU for the Azure OpenAI service')
@allowed(['S0'])
param sku string = 'S0'

@description('Public network access setting')
@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

// Resources
resource openAiService 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openAiServiceName
  location: location
  tags: tags
  kind: 'OpenAI'
  properties: {
    customSubDomainName: openAiServiceName
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
  sku: {
    name: sku
  }
}

// Deploy GPT-4 model for content generation
resource gpt4Deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAiService
  name: models.gpt4.name
  properties: {
    model: {
      format: 'OpenAI'
      name: models.gpt4.modelName
      version: models.gpt4.modelVersion
    }
  }
  sku: {
    name: 'Standard'
    capacity: models.gpt4.skuCapacity
  }
}

// Deploy text embedding model for vector search
resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAiService
  name: models.embedding.name
  properties: {
    model: {
      format: 'OpenAI'
      name: models.embedding.modelName
      version: models.embedding.modelVersion
    }
  }
  sku: {
    name: 'Standard'
    capacity: models.embedding.skuCapacity
  }
  dependsOn: [
    gpt4Deployment
  ]
}

// Outputs
@description('Azure OpenAI Service Resource ID')
output serviceId string = openAiService.id

@description('Azure OpenAI Service Name')
output serviceName string = openAiService.name

@description('Azure OpenAI Service Endpoint')
output endpoint string = openAiService.properties.endpoint

@description('Azure OpenAI API Key')
@secure()
output apiKey string = openAiService.listKeys().key1

@description('Azure OpenAI Secondary API Key')
@secure()
output secondaryApiKey string = openAiService.listKeys().key2

@description('GPT-4 Deployment Name')
output gpt4DeploymentName string = gpt4Deployment.name

@description('Embedding Model Deployment Name')
output embeddingDeploymentName string = embeddingDeployment.name

@description('Model Deployment Summary')
output modelDeployments object = {
  gpt4: {
    name: gpt4Deployment.name
    model: models.gpt4.modelName
    version: models.gpt4.modelVersion
    capacity: models.gpt4.skuCapacity
  }
  embedding: {
    name: embeddingDeployment.name
    model: models.embedding.modelName
    version: models.embedding.modelVersion
    capacity: models.embedding.skuCapacity
  }
}