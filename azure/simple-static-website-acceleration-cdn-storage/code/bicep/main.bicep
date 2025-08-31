// =============================================================================
// Bicep template for Static Website Acceleration with CDN and Storage
// =============================================================================
// This template deploys a globally distributed static website using Azure 
// Storage Account's static hosting capabilities combined with Azure CDN for 
// worldwide content acceleration.
// =============================================================================

// =============================================================================
// PARAMETERS
// =============================================================================

@description('The base name used for all resources. This will be suffixed with a unique string.')
@minLength(3)
@maxLength(15)
param baseName string = 'staticsite'

@description('The Azure region where resources will be deployed')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'centralus'
  'northcentralus'
  'southcentralus'
  'westcentralus'
  'canadacentral'
  'canadaeast'
  'brazilsouth'
  'northeurope'
  'westeurope'
  'uksouth'
  'ukwest'
  'francecentral'
  'germanywestcentral'
  'norwayeast'
  'switzerlandnorth'
  'swedencentral'
  'australiaeast'
  'australiasoutheast'
  'southeastasia'
  'eastasia'
  'japaneast'
  'japanwest'
  'koreacentral'
  'southafricanorth'
  'southindia'
  'centralindia'
  'westindia'
])
param location string = resourceGroup().location

@description('Storage account replication type')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
])
param storageAccountReplication string = 'Standard_LRS'

@description('Storage account access tier for blob storage')
@allowed([
  'Hot'
  'Cool'
])
param storageAccessTier string = 'Hot'

@description('CDN SKU for the CDN profile')
@allowed([
  'Standard_Microsoft'
  'Standard_Akamai'
  'Standard_Verizon'
  'Premium_Verizon'
])
param cdnSku string = 'Standard_Microsoft'

@description('Enable compression on the CDN endpoint')
param enableCompression bool = true

@description('Query string caching behavior for CDN')
@allowed([
  'IgnoreQueryString'
  'BypassCaching'
  'UseQueryString'
])
param queryStringCachingBehavior string = 'IgnoreQueryString'

@description('Index document name for static website')
param indexDocument string = 'index.html'

@description('Error document name for static website')
param errorDocument string = '404.html'

@description('Environment tag for resources')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Purpose tag for resources')
param purpose string = 'static-website'

@description('Owner tag for resources')
param owner string = 'DevOps Team'

// =============================================================================
// VARIABLES
// =============================================================================

// Generate unique suffix for resource names to avoid conflicts
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var storageAccountName = '${baseName}${uniqueSuffix}'
var cdnProfileName = 'cdn-profile-${baseName}-${uniqueSuffix}'
var cdnEndpointName = 'website-${baseName}-${uniqueSuffix}'

// Common tags applied to all resources
var commonTags = {
  environment: environment
  purpose: purpose
  owner: owner
  'cost-center': 'IT-Infrastructure'
  'created-by': 'bicep-template'
  'recipe-name': 'simple-static-website-acceleration-cdn-storage'
}

// Content types to compress for better performance
var contentTypesToCompress = [
  'text/html'
  'text/css'
  'text/javascript'
  'application/javascript'
  'application/json'
  'text/plain'
  'text/xml'
  'application/xml'
  'image/svg+xml'
]

// =============================================================================
// RESOURCES
// =============================================================================

// Storage Account for static website hosting
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
  sku: {
    name: storageAccountReplication
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: storageAccessTier
  }
}

// Enable static website hosting on the storage account
resource staticWebsite 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'HEAD', 'OPTIONS']
          maxAgeInSeconds: 86400
          exposedHeaders: ['*']
          allowedHeaders: ['*']
        }
      ]
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    isVersioningEnabled: false
    changeFeed: {
      enabled: false
    }
    restorePolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// CDN Profile for global content delivery
resource cdnProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: cdnProfileName
  location: 'Global'
  tags: commonTags
  sku: {
    name: cdnSku
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

// CDN Endpoint for accelerated content delivery
resource cdnEndpoint 'Microsoft.Cdn/profiles/endpoints@2023-05-01' = {
  parent: cdnProfile
  name: cdnEndpointName
  location: 'Global'
  tags: commonTags
  properties: {
    originHostHeader: replace(replace(storageAccount.properties.primaryEndpoints.web, 'https://', ''), '/', '')
    isHttpAllowed: false
    isHttpsAllowed: true
    queryStringCachingBehavior: queryStringCachingBehavior
    isCompressionEnabled: enableCompression
    contentTypesToCompress: contentTypesToCompress
    optimizationType: 'GeneralWebDelivery'
    origins: [
      {
        name: 'storage-origin'
        properties: {
          hostName: replace(replace(storageAccount.properties.primaryEndpoints.web, 'https://', ''), '/', '')
          httpPort: 80
          httpsPort: 443
          originHostHeader: replace(replace(storageAccount.properties.primaryEndpoints.web, 'https://', ''), '/', '')
          priority: 1
          weight: 1000
          enabled: true
        }
      }
    ]
    deliveryPolicy: {
      rules: [
        {
          name: 'EnforceHTTPS'
          order: 1
          conditions: [
            {
              name: 'RequestScheme'
              parameters: {
                typeName: 'DeliveryRuleRequestSchemeConditionParameters'
                matchValues: ['HTTP']
                operator: 'Equal'
                negateCondition: false
              }
            }
          ]
          actions: [
            {
              name: 'UrlRedirect'
              parameters: {
                typeName: 'DeliveryRuleUrlRedirectActionParameters'
                redirectType: 'Found'
                destinationProtocol: 'Https'
              }
            }
          ]
        }
        {
          name: 'CacheOptimization'
          order: 2
          conditions: [
            {
              name: 'UrlFileExtension'
              parameters: {
                typeName: 'DeliveryRuleUrlFileExtensionMatchConditionParameters'
                operator: 'Equal'
                negateCondition: false
                matchValues: ['css', 'js', 'png', 'jpg', 'jpeg', 'gif', 'ico', 'svg', 'woff', 'woff2', 'ttf', 'eot']
              }
            }
          ]
          actions: [
            {
              name: 'CacheExpiration'
              parameters: {
                typeName: 'DeliveryRuleCacheExpirationActionParameters'
                cacheBehavior: 'SetIfMissing'
                cacheType: 'All'
                cacheDuration: '365.00:00:00'
              }
            }
          ]
        }
      ]
    }
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('The name of the created storage account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the storage account')
output storageAccountId string = storageAccount.id

@description('The primary endpoint for the static website')
output staticWebsiteUrl string = storageAccount.properties.primaryEndpoints.web

@description('The hostname of the static website (without https://)')
output staticWebsiteHostname string = replace(replace(storageAccount.properties.primaryEndpoints.web, 'https://', ''), '/', '')

@description('The name of the CDN profile')
output cdnProfileName string = cdnProfile.name

@description('The resource ID of the CDN profile')
output cdnProfileId string = cdnProfile.id

@description('The name of the CDN endpoint')
output cdnEndpointName string = cdnEndpoint.name

@description('The resource ID of the CDN endpoint')
output cdnEndpointId string = cdnEndpoint.id

@description('The URL of the CDN endpoint for global access')
output cdnEndpointUrl string = 'https://${cdnEndpoint.properties.hostName}'

@description('The hostname of the CDN endpoint')
output cdnEndpointHostname string = cdnEndpoint.properties.hostName

@description('Resource group name where resources were deployed')
output resourceGroupName string = resourceGroup().name

@description('Azure region where resources were deployed')
output deploymentLocation string = location

@description('Tags applied to all resources')
output appliedTags object = commonTags

@description('Instructions for uploading content to the static website')
output uploadInstructions string = 'Use Azure CLI: az storage blob upload-batch --account-name ${storageAccount.name} --source ./website-content --destination $web'

@description('Deployment summary with key information')
output deploymentSummary object = {
  storageAccountName: storageAccount.name
  staticWebsiteUrl: storageAccount.properties.primaryEndpoints.web
  cdnEndpointUrl: 'https://${cdnEndpoint.properties.hostName}'
  resourceGroupName: resourceGroup().name
  deploymentLocation: location
  compressionEnabled: enableCompression
  queryStringCaching: queryStringCachingBehavior
  storageReplication: storageAccountReplication
  cdnSku: cdnSku
}