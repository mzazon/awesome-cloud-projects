// ================================================
// Azure Healthcare Chatbot with Personalization
// ================================================
// This Bicep template deploys a complete personalized healthcare chatbot solution
// using Azure Health Bot, Azure Personalizer, and supporting services.

targetScope = 'resourceGroup'

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Project name used for resource naming')
@minLength(3)
@maxLength(10)
param projectName string = 'healthbot'

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('SQL Admin username')
param sqlAdminUsername string = 'sqladmin'

@description('SQL Admin password')
@secure()
param sqlAdminPassword string

@description('Organization name for API Management')
param organizationName string = 'Healthcare Organization'

@description('Administrator email for API Management')
param adminEmail string = 'admin@healthcare.org'

@description('Health Bot SKU')
@allowed(['F0', 'S1'])
param healthBotSku string = 'F0'

@description('Personalizer SKU')
@allowed(['F0', 'S0'])
param personalizerSku string = 'S0'

@description('API Management SKU')
@allowed(['Developer', 'Basic', 'Standard', 'Premium'])
param apiManagementSku string = 'Developer'

@description('Enable managed identity for resources')
param enableManagedIdentity bool = true

@description('Tags to apply to all resources')
param tags object = {
  environment: environment
  project: projectName
  purpose: 'healthcare-chatbot'
  compliance: 'hipaa'
}

// Variables
var resourcePrefix = '${projectName}-${environment}'
var storageAccountName = 'st${uniqueSuffix}'
var healthBotName = '${resourcePrefix}-healthbot-${uniqueSuffix}'
var personalizerName = '${resourcePrefix}-personalizer-${uniqueSuffix}'
var functionAppName = '${resourcePrefix}-func-${uniqueSuffix}'
var apiManagementName = '${resourcePrefix}-apim-${uniqueSuffix}'
var sqlManagedInstanceName = '${resourcePrefix}-sqlmi-${uniqueSuffix}'
var keyVaultName = '${resourcePrefix}-kv-${uniqueSuffix}'
var virtualNetworkName = '${resourcePrefix}-vnet'
var subnetName = 'sqlmi-subnet'
var appServicePlanName = '${resourcePrefix}-plan-${uniqueSuffix}'

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    encryption: {
      services: {
        blob: {
          keyType: 'Account'
          enabled: true
        }
        file: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Key Vault for secure credential management
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
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Virtual Network for SQL Managed Instance
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.1.0/24'
          delegations: [
            {
              name: 'sqlManagedInstance'
              properties: {
                serviceName: 'Microsoft.Sql/managedInstances'
              }
            }
          ]
        }
      }
    ]
  }
}

// Route Table for SQL Managed Instance subnet
resource routeTable 'Microsoft.Network/routeTables@2023-09-01' = {
  name: '${virtualNetworkName}-rt'
  location: location
  tags: tags
  properties: {
    routes: []
  }
}

// Network Security Group for SQL Managed Instance
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${virtualNetworkName}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow_management_inbound'
        properties: {
          priority: 106
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '9000'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'allow_misubnet_inbound'
        properties: {
          priority: 200
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '*'
          protocol: '*'
          sourceAddressPrefix: '10.0.1.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'allow_health_probe_inbound'
        properties: {
          priority: 300
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '*'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// Update subnet with NSG and Route Table
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: virtualNetwork
  name: subnetName
  properties: {
    addressPrefix: '10.0.1.0/24'
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
    routeTable: {
      id: routeTable.id
    }
    delegations: [
      {
        name: 'sqlManagedInstance'
        properties: {
          serviceName: 'Microsoft.Sql/managedInstances'
        }
      }
    ]
  }
}

// SQL Managed Instance
resource sqlManagedInstance 'Microsoft.Sql/managedInstances@2023-08-01-preview' = {
  name: sqlManagedInstanceName
  location: location
  tags: tags
  sku: {
    name: 'GP_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 4
  }
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    subnetId: subnet.id
    storageSizeInGB: 32
    vCores: 4
    licenseType: 'LicenseIncluded'
    publicDataEndpointEnabled: false
    minimalTlsVersion: '1.2'
  }
}

// SQL Database on Managed Instance
resource sqlDatabase 'Microsoft.Sql/managedInstances/databases@2023-08-01-preview' = {
  parent: sqlManagedInstance
  name: 'HealthBotDB'
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
  }
}

// Azure Health Bot Service
resource healthBot 'Microsoft.HealthBot/healthBots@2023-05-01' = {
  name: healthBotName
  location: location
  tags: tags
  sku: {
    name: healthBotSku
  }
  properties: {
    // Health Bot configuration properties
  }
}

// Azure Personalizer Cognitive Service
resource personalizer 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: personalizerName
  location: location
  tags: tags
  sku: {
    name: personalizerSku
  }
  kind: 'Personalizer'
  properties: {
    customSubDomainName: personalizerName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'functionapp'
  properties: {
    reserved: false
  }
}

// Function App for integration logic
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  identity: enableManagedIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'PersonalizerEndpoint'
          value: personalizer.properties.endpoint
        }
        {
          name: 'PersonalizerKey'
          value: personalizer.listKeys().key1
        }
        {
          name: 'SqlConnectionString'
          value: 'Server=${sqlManagedInstance.properties.fullyQualifiedDomainName};Database=HealthBotDB;User Id=${sqlAdminUsername};Password=${sqlAdminPassword};Encrypt=true;TrustServerCertificate=false;'
        }
        {
          name: 'KeyVaultEndpoint'
          value: keyVault.properties.vaultUri
        }
      ]
      netFrameworkVersion: 'v6.0'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    httpsOnly: true
  }
}

// API Management Service
resource apiManagement 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apiManagementName
  location: location
  tags: tags
  sku: {
    name: apiManagementSku
    capacity: 1
  }
  identity: enableManagedIdentity ? {
    type: 'SystemAssigned'
  } : null
  properties: {
    publisherName: organizationName
    publisherEmail: adminEmail
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
    }
  }
}

// API Management Policy for healthcare compliance
resource apiManagementPolicy 'Microsoft.ApiManagement/service/policies@2023-05-01-preview' = {
  parent: apiManagement
  name: 'policy'
  properties: {
    value: '''
    <policies>
      <inbound>
        <rate-limit calls="100" renewal-period="60" />
        <cors allow-credentials="true">
          <allowed-origins>
            <origin>*</origin>
          </allowed-origins>
          <allowed-methods>
            <method>GET</method>
            <method>POST</method>
          </allowed-methods>
          <allowed-headers>
            <header>*</header>
          </allowed-headers>
        </cors>
        <set-header name="X-Powered-By" exists-action="delete" />
        <set-header name="X-AspNet-Version" exists-action="delete" />
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <set-header name="X-Healthcare-Disclaimer" exists-action="override">
          <value>This chatbot provides general information only. Consult healthcare professionals for medical advice.</value>
        </set-header>
        <set-header name="X-Content-Type-Options" exists-action="override">
          <value>nosniff</value>
        </set-header>
        <set-header name="X-Frame-Options" exists-action="override">
          <value>DENY</value>
        </set-header>
        <set-header name="Strict-Transport-Security" exists-action="override">
          <value>max-age=31536000; includeSubDomains</value>
        </set-header>
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
    '''
  }
}

// Store secrets in Key Vault
resource personalizerKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'PersonalizerKey'
  properties: {
    value: personalizer.listKeys().key1
  }
}

resource sqlConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'SqlConnectionString'
  properties: {
    value: 'Server=${sqlManagedInstance.properties.fullyQualifiedDomainName};Database=HealthBotDB;User Id=${sqlAdminUsername};Password=${sqlAdminPassword};Encrypt=true;TrustServerCertificate=false;'
  }
}

// RBAC assignments for Function App managed identity
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableManagedIdentity) {
  scope: keyVault
  name: guid(keyVault.id, functionApp.id, 'Key Vault Secrets User')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output resourceGroupName string = resourceGroup().name
output healthBotName string = healthBot.name
output healthBotEndpoint string = healthBot.properties.botManagementPortalLink
output personalizerName string = personalizer.name
output personalizerEndpoint string = personalizer.properties.endpoint
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output apiManagementName string = apiManagement.name
output apiManagementUrl string = 'https://${apiManagement.properties.gatewayUrl}'
output sqlManagedInstanceName string = sqlManagedInstance.name
output sqlManagedInstanceEndpoint string = sqlManagedInstance.properties.fullyQualifiedDomainName
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output storageAccountName string = storageAccount.name
output virtualNetworkName string = virtualNetwork.name
output subnetId string = subnet.id