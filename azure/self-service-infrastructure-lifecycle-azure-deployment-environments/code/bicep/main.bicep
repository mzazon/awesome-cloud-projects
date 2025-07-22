// Azure Deployment Environments - Self-Service Infrastructure Lifecycle
// This template deploys a complete Azure Deployment Environments solution with DevCenter, 
// Projects, Environment Types, and supporting resources for self-service infrastructure management.

@description('The name of the Azure DevCenter. Must be globally unique.')
@minLength(3)
@maxLength(26)
param devCenterName string

@description('The name of the project within the DevCenter.')
@minLength(3)
@maxLength(63)
param projectName string

@description('The name of the environment catalog.')
@minLength(3)
@maxLength(63)
param catalogName string = 'infrastructure-catalog'

@description('The name of the storage account for storing infrastructure templates.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('The Azure region where resources will be deployed.')
param location string = resourceGroup().location

@description('The environment type for the deployment (dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environmentType string = 'dev'

@description('Tags to be applied to all resources.')
param tags object = {
  purpose: 'self-service-infrastructure'
  environment: environmentType
  'deployment-method': 'bicep'
}

@description('The subscription ID where environments will be deployed.')
param deploymentSubscriptionId string = subscription().subscriptionId

@description('The resource group where environments will be deployed.')
param deploymentResourceGroupName string = resourceGroup().name

@description('Array of environment type configurations.')
param environmentTypes array = [
  {
    name: 'development'
    displayName: 'Development'
    description: 'Development environment for rapid prototyping and testing'
    tags: {
      tier: 'development'
      'cost-center': 'engineering'
    }
  }
  {
    name: 'staging'
    displayName: 'Staging'
    description: 'Staging environment for pre-production testing'
    tags: {
      tier: 'staging'
      'cost-center': 'engineering'
      monitoring: 'enhanced'
    }
  }
  {
    name: 'production'
    displayName: 'Production'
    description: 'Production environment with enterprise controls'
    tags: {
      tier: 'production'
      'cost-center': 'operations'
      monitoring: 'enterprise'
    }
  }
]

@description('Array of environment definitions to create.')
param environmentDefinitions array = [
  {
    name: 'webapp-basic'
    displayName: 'Basic Web Application'
    description: 'Simple web application with App Service and App Service Plan'
    templatePath: 'webapp-basic.json'
    parameters: []
  }
  {
    name: 'webapp-database'
    displayName: 'Web Application with Database'
    description: 'Web application with App Service and Azure SQL Database'
    templatePath: 'webapp-database.json'
    parameters: []
  }
  {
    name: 'static-webapp'
    displayName: 'Static Web App'
    description: 'Static web application with Azure Static Web Apps'
    templatePath: 'static-webapp.json'
    parameters: []
  }
]

// Variables for resource naming and configuration
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 8)
var devCenterResourceName = '${devCenterName}-${uniqueSuffix}'
var projectResourceName = '${projectName}-${uniqueSuffix}'
var storageAccountResourceName = '${storageAccountName}${uniqueSuffix}'
var catalogResourceName = '${catalogName}-${uniqueSuffix}'

// Storage account for infrastructure templates
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountResourceName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Blob container for infrastructure templates
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource templatesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'templates'
  properties: {
    publicAccess: 'None'
    metadata: {}
  }
}

// Azure DevCenter - Central hub for environment management
resource devCenter 'Microsoft.DevCenter/devcenters@2024-02-01' = {
  name: devCenterResourceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: devCenterResourceName
    projectCatalogSettings: {
      catalogItemSyncEnableStatus: 'Enabled'
    }
  }
}

// Environment types configuration
resource environmentType 'Microsoft.DevCenter/devcenters/environmentTypes@2024-02-01' = [for envType in environmentTypes: {
  parent: devCenter
  name: envType.name
  properties: {
    displayName: envType.displayName
    tags: union(tags, envType.tags)
  }
}]

// Catalog for infrastructure templates
resource catalog 'Microsoft.DevCenter/devcenters/catalogs@2024-02-01' = {
  parent: devCenter
  name: catalogResourceName
  properties: {
    adoGit: {
      uri: 'https://${storageAccount.name}.blob.core.windows.net/templates'
      branch: 'main'
      path: '/'
      secretIdentifier: ''
    }
    syncType: 'Manual'
  }
  dependsOn: [
    templatesContainer
  ]
}

// Project for organizing development teams and environments
resource project 'Microsoft.DevCenter/projects@2024-02-01' = {
  name: projectResourceName
  location: location
  tags: tags
  properties: {
    displayName: projectResourceName
    description: 'Self-service infrastructure project for development teams'
    devCenterId: devCenter.id
    maxDevBoxesPerUser: 5
  }
}

// Associate environment types with the project
resource projectEnvironmentType 'Microsoft.DevCenter/projects/environmentTypes@2024-02-01' = [for (envType, index) in environmentTypes: {
  parent: project
  name: envType.name
  properties: {
    displayName: envType.displayName
    deploymentTargetId: '/subscriptions/${deploymentSubscriptionId}/resourceGroups/${deploymentResourceGroupName}'
    status: 'Enabled'
    creatorRoleAssignment: {
      roles: {
        '8e3af657-a8ff-443c-a75c-2fe8c4bcb635': {} // Owner role
      }
    }
    userRoleAssignments: {
      '8e3af657-a8ff-443c-a75c-2fe8c4bcb635': {} // Owner role for users
    }
  }
  dependsOn: [
    environmentType[index]
  ]
}]

// Role assignments for DevCenter managed identity
resource storageDataReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(devCenter.id, storageAccount.id, 'Storage Blob Data Reader')
  properties: {
    principalId: devCenter.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1') // Storage Blob Data Reader
    principalType: 'ServicePrincipal'
  }
}

// Environment definitions (would be created via templates in the catalog)
// Note: Environment definitions are typically created through the catalog sync process
// This output provides the template structure for reference

// Basic web application template for upload to storage
var webAppTemplate = {
  '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
  contentVersion: '1.0.0.0'
  parameters: {
    appName: {
      type: 'string'
      defaultValue: '[concat(\'webapp-\', uniqueString(resourceGroup().id))]'
      metadata: {
        description: 'Name of the web application'
      }
    }
    location: {
      type: 'string'
      defaultValue: '[resourceGroup().location]'
      metadata: {
        description: 'Location for all resources'
      }
    }
    environmentType: {
      type: 'string'
      defaultValue: 'dev'
      allowedValues: [
        'dev'
        'staging'
        'prod'
      ]
      metadata: {
        description: 'Environment type for resource sizing'
      }
    }
  }
  variables: {
    appServicePlanName: '[concat(parameters(\'appName\'), \'-plan\')]'
    appServiceSku: '[if(equals(parameters(\'environmentType\'), \'prod\'), \'P1v2\', \'F1\')]'
    appServiceSkuTier: '[if(equals(parameters(\'environmentType\'), \'prod\'), \'PremiumV2\', \'Free\')]'
  }
  resources: [
    {
      type: 'Microsoft.Web/serverfarms'
      apiVersion: '2023-12-01'
      name: '[variables(\'appServicePlanName\')]'
      location: '[parameters(\'location\')]'
      tags: {
        'azd-service-name': 'web'
        environment: '[parameters(\'environmentType\')]'
      }
      sku: {
        name: '[variables(\'appServiceSku\')]'
        tier: '[variables(\'appServiceSkuTier\')]'
      }
      properties: {
        reserved: true
      }
    }
    {
      type: 'Microsoft.Web/sites'
      apiVersion: '2023-12-01'
      name: '[parameters(\'appName\')]'
      location: '[parameters(\'location\')]'
      tags: {
        'azd-service-name': 'web'
        environment: '[parameters(\'environmentType\')]'
      }
      dependsOn: [
        '[resourceId(\'Microsoft.Web/serverfarms\', variables(\'appServicePlanName\'))]'
      ]
      properties: {
        serverFarmId: '[resourceId(\'Microsoft.Web/serverfarms\', variables(\'appServicePlanName\'))]'
        siteConfig: {
          linuxFxVersion: 'NODE|18-lts'
          alwaysOn: '[if(equals(parameters(\'environmentType\'), \'prod\'), true(), false())]'
          ftpsState: 'Disabled'
          minTlsVersion: '1.2'
          scmMinTlsVersion: '1.2'
          use32BitWorkerProcess: false
          httpLoggingEnabled: true
          logsDirectorySizeLimit: 35
          detailedErrorLoggingEnabled: true
          requestTracingEnabled: true
          remoteDebuggingEnabled: false
        }
        httpsOnly: true
        redundancyMode: '[if(equals(parameters(\'environmentType\'), \'prod\'), \'GeoRedundant\', \'None\')]'
        clientAffinityEnabled: false
      }
    }
  ]
  outputs: {
    webAppUrl: {
      type: 'string'
      value: '[concat(\'https://\', reference(parameters(\'appName\')).defaultHostName)]'
    }
    webAppName: {
      type: 'string'
      value: '[parameters(\'appName\')]'
    }
    resourceGroupName: {
      type: 'string'
      value: '[resourceGroup().name]'
    }
  }
}

// Outputs for deployment validation and integration
output devCenterName string = devCenter.name
output devCenterId string = devCenter.id
output devCenterEndpoint string = 'https://${devCenter.name}-${location}.devcenter.azure.com/'
output projectName string = project.name
output projectId string = project.id
output catalogName string = catalog.name
output catalogId string = catalog.id
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output templatesContainerUrl string = 'https://${storageAccount.name}.blob.core.windows.net/templates'
output environmentTypes array = [for (envType, index) in environmentTypes: {
  name: envType.name
  displayName: envType.displayName
  resourceId: environmentType[index].id
}]
output webAppTemplate object = webAppTemplate
output principalId string = devCenter.identity.principalId
output resourceGroupName string = resourceGroup().name
output subscriptionId string = subscription().subscriptionId
output deploymentRegion string = location