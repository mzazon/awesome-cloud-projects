@description('The unique suffix to append to resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment designation (development, production, shared)')
@allowed([
  'development'
  'production'
  'shared'
])
param environment string = 'development'

@description('Department responsible for the resources')
param department string = 'engineering'

@description('Cost center for billing allocation')
param costCenter string

@description('Project name for resource organization')
param projectName string = 'resource-organization'

@description('Owner of the resources')
param owner string

@description('Purpose of the resource group')
param purpose string = 'demo'

@description('SLA requirement for production resources')
@allowed([
  'standard'
  'high'
])
param slaRequirement string = 'standard'

@description('Backup requirement for production resources')
@allowed([
  'none'
  'daily'
  'hourly'
])
param backupRequirement string = 'none'

@description('Compliance requirement for production resources')
param complianceRequirement string = ''

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('App Service Plan SKU')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1V2'
  'P2V2'
  'P3V2'
])
param appServicePlanSku string = 'B1'

@description('Whether to create sample resources for demonstration')
param createSampleResources bool = true

// Variables for resource naming
var storageAccountName = 'st${environment}${uniqueSuffix}'
var appServicePlanName = 'asp-${environment}-${uniqueSuffix}'

// Common tags that will be applied to all resources
var commonTags = {
  environment: environment
  purpose: purpose
  department: department
  costcenter: costCenter
  owner: owner
  project: projectName
  lastUpdated: '2025-07-12'
  managedBy: 'bicep'
  automation: 'enabled'
}

// Environment-specific tags
var environmentSpecificTags = environment == 'production' ? union(commonTags, {
    sla: slaRequirement
    backup: backupRequirement
    compliance: complianceRequirement
    auditRequired: 'true'
  }) : environment == 'shared' ? union(commonTags, {
    scope: 'multi-environment'
  }) : commonTags

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = if (createSampleResources) {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
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
  tags: union(environmentSpecificTags, {
    tier: environment == 'production' ? 'premium' : 'standard'
    dataclass: environment == 'production' ? 'sensitive' : 'non-sensitive'
    encryption: environment == 'production' ? 'enabled' : 'standard'
    backup: environment == 'production' ? 'enabled' : 'standard'
  })
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = if (createSampleResources) {
  name: appServicePlanName
  location: location
  sku: {
    name: appServicePlanSku
    capacity: 1
  }
  kind: 'app'
  properties: {
    reserved: false
  }
  tags: union(environmentSpecificTags, {
    tier: environment == 'production' ? 'premium' : 'basic'
    workload: 'web-app'
    monitoring: environment == 'production' ? 'enabled' : 'basic'
  })
}

// Output important information
@description('The name of the created storage account')
output storageAccountName string = createSampleResources ? storageAccount.name : ''

@description('The resource ID of the created storage account')
output storageAccountId string = createSampleResources ? storageAccount.id : ''

@description('The name of the created App Service Plan')
output appServicePlanName string = createSampleResources ? appServicePlan.name : ''

@description('The resource ID of the created App Service Plan')
output appServicePlanId string = createSampleResources ? appServicePlan.id : ''

@description('The common tags applied to all resources')
output commonTags object = commonTags

@description('The environment-specific tags applied to resources')
output environmentTags object = environmentSpecificTags

@description('The resource group location')
output resourceGroupLocation string = location

@description('The unique suffix used for resource naming')
output uniqueSuffix string = uniqueSuffix