// ===================================================================================================
// Azure Notification Hubs Basic Push Notifications - Main Bicep Template
// ===================================================================================================
// This template creates an Azure Notification Hubs namespace and notification hub for 
// cross-platform push notifications. It provides a unified push notification engine
// that simplifies delivery to any platform (iOS, Android, Windows) from any backend.
//
// Recipe: Basic Push Notifications with Notification Hubs
// Author: Microsoft Azure Recipes
// Version: 1.0
// ===================================================================================================

// ===================================================================================================
// METADATA
// ===================================================================================================
metadata name = 'Azure Notification Hubs Basic Push Notifications'
metadata description = 'Creates Azure Notification Hubs infrastructure for cross-platform push notifications'
metadata author = 'Microsoft Azure Recipes'
metadata version = '1.0.0'

// ===================================================================================================
// PARAMETERS
// ===================================================================================================

@description('The Azure region where all resources will be deployed.')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'westus3'
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
  'switzerlandnorth'
  'norwayeast'
  'japaneast'
  'japanwest'
  'eastasia'
  'southeastasia'
  'australiaeast'
  'australiasoutheast'
  'australiacentral'
  'koreacentral'
  'southindia'
  'centralindia'
  'westindia'
])
param location string = resourceGroup().location

@description('Name of the Notification Hub namespace. Must be globally unique.')
@minLength(6)
@maxLength(50)
param namespaceName string

@description('Name of the notification hub within the namespace.')
@minLength(1)
@maxLength(260)
param notificationHubName string

@description('SKU tier for the Notification Hub namespace.')
@allowed([
  'Free'
  'Basic'
  'Standard'
])
param skuName string = 'Free'

@description('Resource tags to apply to all resources.')
param tags object = {
  environment: 'demo'
  purpose: 'recipe'
  service: 'notification-hubs'
}

@description('Enable or disable public network access to the namespace.')
param enablePublicNetworkAccess bool = true

@description('Enable or disable zone redundancy for the namespace.')
param enableZoneRedundancy bool = false

// ===================================================================================================
// VARIABLES
// ===================================================================================================

// Construct unique resource names using the provided parameters
var resourcePrefix = 'nh-${uniqueString(resourceGroup().id)}'
var actualNamespaceName = !empty(namespaceName) ? namespaceName : '${resourcePrefix}-namespace'
var actualNotificationHubName = !empty(notificationHubName) ? notificationHubName : '${resourcePrefix}-hub'

// SKU configuration based on selected tier
var skuConfig = {
  Free: {
    name: 'Free'
    tier: 'Free'
    capacity: 1
  }
  Basic: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 1
  }
  Standard: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
}

// Common resource tags merged with user-provided tags
var resourceTags = union(tags, {
  deployedBy: 'bicep'
  templateVersion: '1.0.0'
  lastDeployed: utcNow('yyyy-MM-dd')
})

// ===================================================================================================
// RESOURCES
// ===================================================================================================

@description('Azure Notification Hubs namespace - provides messaging infrastructure and security boundary')
resource notificationHubNamespace 'Microsoft.NotificationHubs/namespaces@2023-09-01' = {
  name: actualNamespaceName
  location: location
  tags: resourceTags
  sku: {
    name: skuConfig[skuName].name
    tier: skuConfig[skuName].tier
    capacity: skuConfig[skuName].capacity
  }
  properties: {
    // Configure namespace-level settings
    namespaceType: 'NotificationHub'
    
    // Network access configuration
    publicNetworkAccess: enablePublicNetworkAccess ? 'Enabled' : 'Disabled'
    
    // Zone redundancy configuration (only available in Standard tier)
    zoneRedundancy: (skuName == 'Standard' && enableZoneRedundancy) ? 'Enabled' : 'Disabled'
    
    // Data residency and encryption settings
    dataResidency: location
  }
}

@description('Notification Hub within the namespace - handles device registrations and notification delivery')
resource notificationHub 'Microsoft.NotificationHubs/namespaces/notificationHubs@2023-09-01' = {
  parent: notificationHubNamespace
  name: actualNotificationHubName
  location: location
  tags: resourceTags
  properties: {
    // Notification hub configuration
    authorizationRules: []
    
    // Platform notification service credentials (configured separately)
    // apnsCredential: {} // Configure for iOS notifications
    // fcmV1Credential: {} // Configure for Android notifications  
    // wnsCredential: {} // Configure for Windows notifications
    
    // Registration time-to-live settings
    registrationTtl: 'P30D' // 30 days registration TTL
  }
}

// ===================================================================================================
// AUTHORIZATION RULES
// ===================================================================================================

@description('Default listen authorization rule for client applications')
resource listenAuthRule 'Microsoft.NotificationHubs/namespaces/notificationHubs/authorizationRules@2023-09-01' = {
  parent: notificationHub
  name: 'DefaultListenSharedAccessSignature'
  properties: {
    rights: [
      'Listen'
    ]
  }
}

@description('Default full access authorization rule for backend applications')
resource fullAccessAuthRule 'Microsoft.NotificationHubs/namespaces/notificationHubs/authorizationRules@2023-09-01' = {
  parent: notificationHub
  name: 'DefaultFullSharedAccessSignature'
  properties: {
    rights: [
      'Listen'
      'Manage'
      'Send'
    ]
  }
}

// ===================================================================================================
// OUTPUTS
// ===================================================================================================

@description('Resource ID of the Notification Hub namespace')
output namespaceResourceId string = notificationHubNamespace.id

@description('Name of the Notification Hub namespace')
output namespaceName string = notificationHubNamespace.name

@description('Resource ID of the notification hub')
output notificationHubResourceId string = notificationHub.id

@description('Name of the notification hub')
output notificationHubName string = notificationHub.name

@description('Primary connection string for client applications (Listen permissions)')
output listenConnectionString string = listenAuthRule.listKeys().primaryConnectionString

@description('Secondary connection string for client applications (Listen permissions)')
output listenConnectionStringSecondary string = listenAuthRule.listKeys().secondaryConnectionString

@description('Primary connection string for backend applications (Full permissions)')
output fullAccessConnectionString string = fullAccessAuthRule.listKeys().primaryConnectionString

@description('Secondary connection string for backend applications (Full permissions)')
output fullAccessConnectionStringSecondary string = fullAccessAuthRule.listKeys().secondaryConnectionString

@description('Primary access key for listen operations')
output listenPrimaryKey string = listenAuthRule.listKeys().primaryKey

@description('Primary access key for full access operations')
output fullAccessPrimaryKey string = fullAccessAuthRule.listKeys().primaryKey

@description('Notification Hub endpoint for REST API operations')
output notificationHubEndpoint string = 'https://${notificationHubNamespace.name}.servicebus.windows.net/'

@description('Resource group location where resources are deployed')
output deploymentLocation string = location

@description('SKU tier used for the namespace')
output skuTier string = skuConfig[skuName].tier

@description('Tags applied to the resources')
output appliedTags object = resourceTags

@description('Deployment summary with key information')
output deploymentSummary object = {
  namespaceName: notificationHubNamespace.name
  notificationHubName: notificationHub.name
  location: location
  skuTier: skuConfig[skuName].tier
  publicNetworkAccess: enablePublicNetworkAccess
  zoneRedundancy: enableZoneRedundancy
  endpoint: 'https://${notificationHubNamespace.name}.servicebus.windows.net/'
  status: 'Deployed'
}