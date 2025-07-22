// Main Bicep template for Serverless Data Mesh with Azure Databricks and API Management
@description('The name of the resource group')
param resourceGroupName string = 'rg-data-mesh-demo'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('The name of the Databricks workspace')
param databricksWorkspaceName string = 'databricks-${uniqueSuffix}'

@description('The name of the API Management service')
param apiManagementName string = 'apim-mesh-${uniqueSuffix}'

@description('The name of the Key Vault')
param keyVaultName string = 'kv-mesh-${uniqueSuffix}'

@description('The name of the Event Grid topic')
param eventGridTopicName string = 'eg-mesh-${uniqueSuffix}'

@description('The SKU for the Databricks workspace')
@allowed([
  'standard'
  'premium'
])
param databricksSku string = 'premium'

@description('The SKU for the API Management service')
@allowed([
  'Consumption'
  'Developer'
  'Basic'
  'Standard'
  'Premium'
])
param apiManagementSku string = 'Consumption'

@description('The publisher name for API Management')
param publisherName string = 'DataMeshTeam'

@description('The publisher email for API Management')
param publisherEmail string = 'datamesh@example.com'

@description('Enable public network access for Databricks')
param enablePublicNetworkAccess bool = false

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'data-mesh'
  environment: 'demo'
  project: 'serverless-data-mesh'
}

// Variables
var tenantId = subscription().tenantId
var subscriptionId = subscription().subscriptionId

// Azure Databricks Workspace
resource databricksWorkspace 'Microsoft.Databricks/workspaces@2023-02-01' = {
  name: databricksWorkspaceName
  location: location
  tags: tags
  sku: {
    name: databricksSku
  }
  properties: {
    managedResourceGroupId: subscriptionResourceId('Microsoft.Resources/resourceGroups', 'databricks-rg-${databricksWorkspaceName}-${uniqueString(databricksWorkspaceName, resourceGroup().id)}')
    parameters: {
      enableNoPublicIp: {
        value: enablePublicNetworkAccess ? false : true
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
      name: 'standard'
    }
    tenantId: tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    publicNetworkAccess: 'Enabled'
  }
}

// Event Grid Topic
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
  }
}

// API Management Service
resource apiManagement 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apiManagementName
  location: location
  tags: tags
  sku: {
    name: apiManagementSku
    capacity: apiManagementSku == 'Consumption' ? 0 : 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherName: publisherName
    publisherEmail: publisherEmail
    notificationSenderEmail: publisherEmail
    hostnameConfigurations: [
      {
        type: 'Proxy'
        hostName: '${apiManagementName}.azure-api.net'
        negotiateClientCertificate: false
        defaultSslBinding: true
        certificateSource: 'BuiltIn'
      }
    ]
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
    }
  }
}

// Service Principal for Databricks Integration
resource servicePrincipal 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-databricks-${uniqueSuffix}'
  location: location
  tags: tags
}

// Role Assignment for Service Principal - Contributor on Resource Group
resource servicePrincipalRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, servicePrincipal.id, 'Contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: servicePrincipal.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for API Management - Key Vault Secrets User
resource apiManagementKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, apiManagement.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: apiManagement.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment for Event Grid Topic - EventGrid Data Sender
resource eventGridDataSenderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, apiManagement.id, 'EventGrid Data Sender')
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7') // EventGrid Data Sender
    principalId: apiManagement.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Store Databricks URL in Key Vault
resource databricksUrlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'databricks-url'
  parent: keyVault
  properties: {
    value: 'https://${databricksWorkspace.properties.workspaceUrl}'
    contentType: 'text/plain'
  }
}

// Store Event Grid Endpoint in Key Vault
resource eventGridEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'eventgrid-endpoint'
  parent: keyVault
  properties: {
    value: eventGridTopic.properties.endpoint
    contentType: 'text/plain'
  }
}

// Store Event Grid Access Key in Key Vault
resource eventGridKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'eventgrid-key'
  parent: keyVault
  properties: {
    value: eventGridTopic.listKeys().key1
    contentType: 'text/plain'
  }
}

// Store Service Principal details in Key Vault
resource servicePrincipalIdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'databricks-sp-id'
  parent: keyVault
  properties: {
    value: servicePrincipal.properties.clientId
    contentType: 'text/plain'
  }
}

// Customer Analytics API
resource customerAnalyticsApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  name: 'customer-analytics-api'
  parent: apiManagement
  properties: {
    displayName: 'Customer Analytics Data Product'
    path: 'customer-analytics'
    protocols: [
      'https'
    ]
    serviceUrl: 'https://${databricksWorkspace.properties.workspaceUrl}/api/2.0'
    subscriptionRequired: true
    apiVersion: '1.0'
    apiVersionSet: {
      versionHeaderName: 'Api-Version'
      versioningScheme: 'Header'
    }
    value: '''
{
  "openapi": "3.0.1",
  "info": {
    "title": "Customer Analytics Data Product",
    "description": "Domain-owned customer analytics data product API",
    "version": "1.0"
  },
  "paths": {
    "/metrics": {
      "get": {
        "summary": "Get customer metrics",
        "operationId": "getCustomerMetrics",
        "parameters": [
          {
            "name": "dateFrom",
            "in": "query",
            "required": true,
            "schema": {
              "type": "string",
              "format": "date"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object"
                }
              }
            }
          }
        }
      }
    }
  }
}
'''
    format: 'openapi+json'
  }
}

// API Policy for Customer Analytics
resource customerAnalyticsApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  name: 'policy'
  parent: customerAnalyticsApi
  properties: {
    value: '''
<policies>
  <inbound>
    <base />
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <openid-config url="https://login.microsoftonline.com/${tenantId}/.well-known/openid-configuration" />
      <audiences>
        <audience>https://${apiManagementName}.azure-api.net</audience>
      </audiences>
    </validate-jwt>
    <rate-limit calls="100" renewal-period="60" />
    <cors>
      <allowed-origins>
        <origin>*</origin>
      </allowed-origins>
      <allowed-methods>
        <method>GET</method>
        <method>POST</method>
        <method>PUT</method>
        <method>DELETE</method>
      </allowed-methods>
      <allowed-headers>
        <header>*</header>
      </allowed-headers>
    </cors>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <cache-store duration="300" />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
    format: 'xml'
  }
}

// API Subscription for Data Consumers
resource dataConsumerSubscription 'Microsoft.ApiManagement/service/subscriptions@2023-05-01-preview' = {
  name: 'data-consumer-subscription'
  parent: apiManagement
  properties: {
    displayName: 'Data Consumer Subscription'
    scope: '/apis/${customerAnalyticsApi.name}'
    state: 'active'
    allowTracing: true
  }
}

// Event Grid Subscription for Data Product Updates
resource dataProductUpdatesSubscription 'Microsoft.EventGrid/topics/eventSubscriptions@2023-12-15-preview' = {
  name: 'data-product-updates'
  parent: eventGridTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://webhook.site/unique-endpoint'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'DataProductUpdated'
        'DataProductCreated'
      ]
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 10
      eventTimeToLiveInMinutes: 1440
    }
  }
}

// Outputs
@description('The resource ID of the Databricks workspace')
output databricksWorkspaceId string = databricksWorkspace.id

@description('The URL of the Databricks workspace')
output databricksWorkspaceUrl string = 'https://${databricksWorkspace.properties.workspaceUrl}'

@description('The resource ID of the API Management service')
output apiManagementId string = apiManagement.id

@description('The URL of the API Management service')
output apiManagementUrl string = 'https://${apiManagement.properties.gatewayUrl}'

@description('The developer portal URL')
output developerPortalUrl string = 'https://${apiManagement.properties.developerPortalUrl}'

@description('The resource ID of the Key Vault')
output keyVaultId string = keyVault.id

@description('The URI of the Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The resource ID of the Event Grid topic')
output eventGridTopicId string = eventGridTopic.id

@description('The endpoint of the Event Grid topic')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('The resource ID of the service principal')
output servicePrincipalId string = servicePrincipal.id

@description('The client ID of the service principal')
output servicePrincipalClientId string = servicePrincipal.properties.clientId

@description('The subscription key for the API')
output apiSubscriptionKey string = dataConsumerSubscription.listSecrets().primaryKey

@description('The customer analytics API URL')
output customerAnalyticsApiUrl string = 'https://${apiManagement.properties.gatewayUrl}/customer-analytics'

@description('Summary of deployed resources')
output deploymentSummary object = {
  databricksWorkspace: {
    name: databricksWorkspaceName
    url: 'https://${databricksWorkspace.properties.workspaceUrl}'
    sku: databricksSku
  }
  apiManagement: {
    name: apiManagementName
    url: 'https://${apiManagement.properties.gatewayUrl}'
    developerPortal: 'https://${apiManagement.properties.developerPortalUrl}'
    sku: apiManagementSku
  }
  keyVault: {
    name: keyVaultName
    uri: keyVault.properties.vaultUri
  }
  eventGrid: {
    name: eventGridTopicName
    endpoint: eventGridTopic.properties.endpoint
  }
  servicePrincipal: {
    name: servicePrincipal.name
    clientId: servicePrincipal.properties.clientId
  }
}