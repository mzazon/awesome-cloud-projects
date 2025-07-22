// ============================================================================
// AZURE INFRASTRUCTURE HEALTH MONITORING WITH FUNCTIONS FLEX CONSUMPTION
// ============================================================================
// This template deploys an automated infrastructure health monitoring solution
// using Azure Functions Flex Consumption plan with VNet integration,
// Azure Update Manager, and Azure Event Grid for event-driven automation.

@description('Specifies the Azure location for all resources.')
param location string = resourceGroup().location

@description('Environment name for resource naming (e.g., dev, test, prod)')
@maxLength(4)
param environment string = 'dev'

@description('Project name for resource naming')
@maxLength(8)
param projectName string = 'healthmon'

@description('Tags to be applied to all resources')
param tags object = {
  environment: environment
  project: projectName
  purpose: 'infrastructure-monitoring'
  deployedBy: 'bicep'
}

@description('Virtual network address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Functions subnet address prefix')
param functionsSubnetPrefix string = '10.0.1.0/24'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Function App runtime stack')
@allowed(['python'])
param functionRuntime string = 'python'

@description('Function App runtime version')
param functionRuntimeVersion string = '3.11'

@description('Log Analytics workspace SKU')
@allowed(['PerGB2018', 'Free', 'Standalone', 'PerNode', 'Standard', 'Premium'])
param logAnalyticsSku string = 'PerGB2018'

@description('Enable Application Insights for Function App monitoring')
param enableApplicationInsights bool = true

@description('Key Vault access policies for additional users/services (optional)')
param additionalKeyVaultAccessPolicies array = []

// ============================================================================
// VARIABLES
// ============================================================================

var resourcePrefix = '${projectName}-${environment}'
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)

// Resource names with consistent naming convention
var vnetName = 'vnet-${resourcePrefix}'
var functionsSubnetName = 'snet-functions-${resourcePrefix}'
var storageAccountName = 'st${projectName}${environment}${uniqueSuffix}'
var functionAppName = 'func-${resourcePrefix}-${uniqueSuffix}'
var logAnalyticsName = 'la-${resourcePrefix}-${uniqueSuffix}'
var applicationInsightsName = 'ai-${resourcePrefix}-${uniqueSuffix}'
var keyVaultName = 'kv-${resourcePrefix}-${uniqueSuffix}'
var eventGridTopicName = 'egt-${resourcePrefix}-${uniqueSuffix}'

// ============================================================================
// NETWORKING RESOURCES
// ============================================================================

@description('Virtual Network for secure Function App connectivity')
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: functionsSubnetName
        properties: {
          addressPrefix: functionsSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.KeyVault'
            }
          ]
        }
      }
    ]
  }
}

// Reference to the functions subnet
resource functionsSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: virtualNetwork
  name: functionsSubnetName
}

// ============================================================================
// STORAGE RESOURCES
// ============================================================================

@description('Storage Account for Azure Functions runtime and data')
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: [
        {
          id: functionsSubnet.id
          action: 'Allow'
        }
      ]
    }
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
  }
}

// ============================================================================
// MONITORING RESOURCES
// ============================================================================

@description('Log Analytics Workspace for centralized logging and monitoring')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsSku
    }
    retentionInDays: 30
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

@description('Application Insights for Function App performance monitoring')
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

// ============================================================================
// SECURITY RESOURCES
// ============================================================================

@description('Key Vault for secure storage of connection strings and secrets')
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    enableRbacAuthorization: false
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: [
        {
          id: functionsSubnet.id
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
    accessPolicies: union([
      {
        tenantId: tenant().tenantId
        objectId: functionApp.identity.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ], additionalKeyVaultAccessPolicies)
  }
}

// Store storage account connection string in Key Vault
resource storageConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'StorageConnectionString'
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
  }
}

// ============================================================================
// EVENT GRID RESOURCES
// ============================================================================

@description('Event Grid Topic for infrastructure health event distribution')
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: tags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// Store Event Grid credentials in Key Vault
resource eventGridEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'EventGridEndpoint'
  properties: {
    value: eventGridTopic.properties.endpoint
  }
}

resource eventGridKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'EventGridKey'
  properties: {
    value: eventGridTopic.listKeys().key1
  }
}

// ============================================================================
// AZURE FUNCTIONS RESOURCES
// ============================================================================

@description('Function App with Flex Consumption plan and VNet integration')
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionAppServicePlan.id
    siteConfig: {
      linuxFxVersion: '${upper(functionRuntime)}|${functionRuntimeVersion}'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${storageConnectionStringSecret.name})'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${storageConnectionStringSecret.name})'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: '${functionAppName}-content'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionRuntime
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        }
        {
          name: 'AzureWebJobsFeatureFlags'
          value: 'EnableWorkerIndexing'
        }
        {
          name: 'KEY_VAULT_NAME'
          value: keyVault.name
        }
        {
          name: 'EVENT_GRID_TOPIC_NAME'
          value: eventGridTopic.name
        }
        {
          name: 'LOG_ANALYTICS_WORKSPACE'
          value: logAnalyticsWorkspace.name
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        }
        {
          name: 'WEBSITE_DNS_SERVER'
          value: '168.63.129.16'
        }
      ]
      cors: {
        allowedOrigins: ['https://portal.azure.com']
      }
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      alwaysOn: false
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    virtualNetworkSubnetId: functionsSubnet.id
  }
  dependsOn: [
    storageConnectionStringSecret
    eventGridEndpointSecret
    eventGridKeySecret
  ]
}

@description('Function App Service Plan with Flex Consumption')
resource functionAppServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${functionAppName}-plan'
  location: location
  tags: tags
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  kind: 'functionapp'
  properties: {
    reserved: true
  }
}

// ============================================================================
// RBAC ASSIGNMENTS
// ============================================================================

@description('Event Grid Data Sender role assignment for Function App')
resource eventGridDataSenderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventGridTopic.id, functionApp.id, 'EventGrid Data Sender')
  scope: eventGridTopic
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'd5a91429-5739-47e2-a06b-3470a27159e7') // EventGrid Data Sender
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Monitoring Contributor role assignment for Function App')
resource monitoringContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(logAnalyticsWorkspace.id, functionApp.id, 'Monitoring Contributor')
  scope: logAnalyticsWorkspace
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '749f88d5-cbae-40b8-bcfc-e573ddc772fa') // Monitoring Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// EVENT GRID SUBSCRIPTIONS
// ============================================================================

@description('Event Grid subscription for Update Manager events')
resource updateManagerEventSubscription 'Microsoft.EventGrid/eventSubscriptions@2023-12-15-preview' = {
  name: 'update-manager-events'
  scope: resourceGroup()
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${functionApp.properties.defaultHostName}/runtime/webhooks/eventgrid?functionName=UpdateEventHandler'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Automation.UpdateManagement.AssessmentCompleted'
        'Microsoft.Automation.UpdateManagement.InstallationCompleted'
      ]
      enableAdvancedFilteringOnArrays: true
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('The name of the deployed resource group')
output resourceGroupName string = resourceGroup().name

@description('The location where resources were deployed')
output location string = location

@description('The name of the Function App')
output functionAppName string = functionApp.name

@description('The default hostname of the Function App')
output functionAppHostname string = functionApp.properties.defaultHostName

@description('The Function App principal ID for additional RBAC assignments')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('The name of the Virtual Network')
output virtualNetworkName string = virtualNetwork.name

@description('The resource ID of the Virtual Network')
output virtualNetworkId string = virtualNetwork.id

@description('The name of the Functions subnet')
output functionsSubnetName string = functionsSubnet.name

@description('The resource ID of the Functions subnet')
output functionsSubnetId string = functionsSubnet.id

@description('The name of the Storage Account')
output storageAccountName string = storageAccount.name

@description('The name of the Log Analytics Workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The workspace ID of the Log Analytics Workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('The name of the Application Insights component')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''

@description('The instrumentation key of Application Insights')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('The connection string of Application Insights')
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The URI of the Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The name of the Event Grid Topic')
output eventGridTopicName string = eventGridTopic.name

@description('The endpoint URL of the Event Grid Topic')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('Configuration summary for verification')
output deploymentSummary object = {
  functionApp: {
    name: functionApp.name
    hostname: functionApp.properties.defaultHostName
    runtime: functionRuntime
    runtimeVersion: functionRuntimeVersion
    vnetIntegrated: true
  }
  monitoring: {
    logAnalytics: logAnalyticsWorkspace.name
    applicationInsights: enableApplicationInsights ? applicationInsights.name : 'disabled'
  }
  networking: {
    virtualNetwork: virtualNetwork.name
    functionsSubnet: functionsSubnet.name
    addressPrefix: vnetAddressPrefix
  }
  security: {
    keyVault: keyVault.name
    managedIdentity: 'SystemAssigned'
    rbacEnabled: true
  }
  eventProcessing: {
    eventGridTopic: eventGridTopic.name
    updateManagerSubscription: updateManagerEventSubscription.name
  }
}