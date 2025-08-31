// ========================================================================
// Azure Maps Store Locator - Main Bicep Template
// ========================================================================
// This template deploys Azure Maps account infrastructure for a simple
// store locator web application with interactive mapping capabilities.
// 
// Resources deployed:
// - Azure Maps Account (Gen2 pricing tier)
// - Resource tags for organization and cost tracking
// 
// Prerequisites:
// - Azure subscription with Maps account creation permissions
// - Azure CLI or PowerShell with Bicep support
// ========================================================================

@description('Specifies the Azure region where the Maps account will be deployed')
param location string = resourceGroup().location

@description('Name of the Azure Maps account (must be globally unique)')
@minLength(3)
@maxLength(50)
param mapsAccountName string

@description('Environment tag for resource organization')
@allowed([
  'dev'
  'test'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Project or application name for resource tagging')
param projectName string = 'store-locator'

@description('Cost center identifier for billing allocation')
param costCenter string = 'demo'

@description('Enable system-assigned managed identity for the Maps account')
param enableSystemIdentity bool = false

@description('Disable local authentication (subscription key) and use only Microsoft Entra ID')
param disableLocalAuth bool = false

@description('Additional data processing regions for improved performance')
param additionalDataProcessingRegions array = []

@description('CORS rules for web application access')
param corsRules array = [
  {
    allowedOrigins: [
      'http://localhost:*'
      'https://localhost:*'
    ]
  }
]

// ========================================================================
// VARIABLES
// ========================================================================

var commonTags = {
  Environment: environment
  Project: projectName
  CostCenter: costCenter
  DeployedBy: 'Bicep'
  Purpose: 'Interactive store locator application'
  Service: 'Azure Maps'
}

// ========================================================================
// RESOURCES
// ========================================================================

@description('Azure Maps account for geospatial services and interactive mapping')
resource mapsAccount 'Microsoft.Maps/accounts@2024-07-01-preview' = {
  name: mapsAccountName
  location: location
  tags: commonTags
  
  // Configure Maps account identity
  identity: enableSystemIdentity ? {
    type: 'SystemAssigned'
  } : null
  
  // Maps account SKU and configuration
  sku: {
    name: 'G2'     // Gen2 pricing tier (replaces deprecated S0/S1)
    tier: 'Standard'
  }
  
  kind: 'Gen2'    // Generation 2 Maps account
  
  properties: {
    // Disable local authentication if specified (forces Microsoft Entra ID)
    disableLocalAuth: disableLocalAuth
    
    // CORS configuration for web application
    cors: {
      corsRules: corsRules
    }
    
    // Additional data processing regions for global performance
    additionalDataProcessingRegions: additionalDataProcessingRegions
    
    // Linked resources (none required for basic store locator)
    linkedResources: []
  }
}

// ========================================================================
// OUTPUTS
// ========================================================================

@description('The resource ID of the Azure Maps account')
output mapsAccountId string = mapsAccount.id

@description('The name of the deployed Azure Maps account')
output mapsAccountName string = mapsAccount.name

@description('The location where the Maps account was deployed')
output location string = mapsAccount.location

@description('The primary subscription key for Azure Maps authentication')
@secure()
output primaryKey string = mapsAccount.listKeys().primaryKey

@description('The secondary subscription key for Azure Maps authentication')
@secure()
output secondaryKey string = mapsAccount.listKeys().secondaryKey

@description('The client ID for Microsoft Entra ID authentication')
output clientId string = mapsAccount.properties.uniqueId

@description('The endpoint URL for Azure Maps REST APIs')
output mapsApiEndpoint string = 'https://atlas.microsoft.com/'

@description('The Web SDK URL for client-side mapping')
output webSdkUrl string = 'https://atlas.microsoft.com/sdk/javascript/mapcontrol/3/atlas.min.js'

@description('The Web SDK CSS URL for styling')
output webSdkCssUrl string = 'https://atlas.microsoft.com/sdk/javascript/mapcontrol/3/atlas.min.css'

@description('System-assigned managed identity principal ID (if enabled)')
output systemIdentityPrincipalId string = enableSystemIdentity ? mapsAccount.identity.principalId : ''

@description('Pricing tier information')
output pricingTier object = {
  name: mapsAccount.sku.name
  tier: mapsAccount.sku.tier
  description: 'Azure Maps Gen2 - 1,000 free transactions monthly, then pay-per-use'
  freeTransactions: 1000
  transactionUrl: 'https://docs.microsoft.com/en-us/azure/azure-maps/understanding-azure-maps-transactions'
}

@description('Configuration summary for the deployed Maps account')
output configurationSummary object = {
  accountName: mapsAccount.name
  location: mapsAccount.location
  pricingTier: 'Gen2 (G2)'
  localAuthEnabled: !disableLocalAuth
  systemIdentityEnabled: enableSystemIdentity
  corsConfigured: !empty(corsRules)
  additionalRegions: length(additionalDataProcessingRegions)
  capabilities: [
    'Interactive Maps'
    'Search Services'
    'Routing Services'
    'Geolocation Services'
    'Time Zone Services'
    'Weather Services'
    'Traffic Services'
  ]
}