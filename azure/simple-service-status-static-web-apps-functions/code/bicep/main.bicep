@description('The name prefix for all resources')
param resourcePrefix string = 'status-page'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The app location for the Static Web App (path to frontend files)')
param appLocation string = 'public'

@description('The API location for the Static Web App (path to Azure Functions)')
param apiLocation string = 'api'

@description('The SKU for the Static Web App')
@allowed([
  'Free'
  'Standard'
])
param staticWebAppSku string = 'Free'

@description('Repository URL for GitHub deployment (optional)')
param repositoryUrl string = ''

@description('Repository branch for deployment')
param repositoryBranch string = 'main'

@description('GitHub repository token for deployment (optional)')
@secure()
param repositoryToken string = ''

@description('Environment name for tagging')
param environment string = 'demo'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'recipe'
  environment: environment
  solution: 'service-status-page'
  'managed-by': 'bicep'
}

// Generate unique suffix for resource naming
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var staticWebAppName = '${resourcePrefix}-${uniqueSuffix}'

// Static Web App resource
resource staticWebApp 'Microsoft.Web/staticSites@2023-01-01' = {
  name: staticWebAppName
  location: location
  tags: tags
  sku: {
    name: staticWebAppSku
    tier: staticWebAppSku
  }
  properties: {
    // Repository configuration (optional)
    repositoryUrl: empty(repositoryUrl) ? null : repositoryUrl
    branch: repositoryBranch
    repositoryToken: empty(repositoryToken) ? null : repositoryToken
    
    // Build configuration
    buildProperties: {
      appLocation: appLocation
      apiLocation: apiLocation
      outputLocation: ''
      appBuildCommand: ''
      apiBuildCommand: 'npm install'
      skipGithubActionWorkflowGeneration: empty(repositoryUrl)
    }
    
    // Provider configuration
    provider: empty(repositoryUrl) ? 'None' : 'GitHub'
    
    // Enterprise-grade features (available in Standard SKU)
    enterpriseGradeCdnStatus: staticWebAppSku == 'Standard' ? 'Enabled' : 'Disabled'
    
    // Staging environments configuration
    stagingEnvironmentPolicy: 'Enabled'
    
    // Allow configuration overrides
    allowConfigFileUpdates: true
  }
}

// Static Web App configuration for API routing and security
resource staticWebAppConfig 'Microsoft.Web/staticSites/config@2023-01-01' = {
  parent: staticWebApp
  name: 'functionAppSettings'
  properties: {
    // Azure Functions runtime configuration
    FUNCTIONS_WORKER_RUNTIME: 'node'
    FUNCTIONS_EXTENSION_VERSION: '~4'
    WEBSITE_NODE_DEFAULT_VERSION: '~18'
    
    // Static Web App specific settings
    AZURE_STATIC_WEB_APPS_API_TOKEN: staticWebApp.listSecrets().properties.apiKey
    
    // CORS configuration for API
    'api:cors:allowedOrigins': staticWebApp.properties.defaultHostname
    'api:cors:supportCredentials': 'false'
    
    // Application Insights integration (optional)
    APPINSIGHTS_INSTRUMENTATIONKEY: ''
    APPLICATIONINSIGHTS_CONNECTION_STRING: ''
  }
}

// Custom domain configuration (optional)
resource customDomain 'Microsoft.Web/staticSites/customDomains@2023-01-01' = if (!empty(repositoryUrl)) {
  parent: staticWebApp
  name: 'default'
  properties: {
    domainName: staticWebApp.properties.defaultHostname
    validationMethod: 'cname-delegation'
  }
}

// Role assignments for managed identity (if needed for advanced scenarios)
resource staticWebAppIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (staticWebAppSku == 'Standard') {
  name: '${staticWebAppName}-identity'
  location: location
  tags: tags
}

// Assign managed identity to Static Web App (Standard SKU only)
resource staticWebAppIdentityAssignment 'Microsoft.Web/staticSites@2023-01-01' = if (staticWebAppSku == 'Standard') {
  name: staticWebAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${staticWebAppIdentity.id}': {}
    }
  }
  dependsOn: [
    staticWebApp
  ]
}

// Application Insights for monitoring (optional enhancement)
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${staticWebAppName}-insights'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${staticWebAppName}-logs'
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Link Application Insights to Log Analytics
resource applicationInsightsWorkspaceLink 'Microsoft.Insights/components@2020-02-02' = {
  name: '${staticWebAppName}-insights-linked'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    RetentionInDays: 30
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
  dependsOn: [
    logAnalyticsWorkspace
  ]
}

// Outputs for integration and verification
@description('The name of the Static Web App')
output staticWebAppName string = staticWebApp.name

@description('The default hostname of the Static Web App')
output staticWebAppUrl string = 'https://${staticWebApp.properties.defaultHostname}'

@description('The resource ID of the Static Web App')
output staticWebAppId string = staticWebApp.id

@description('The API key for deployment')
@secure()
output deploymentToken string = staticWebApp.listSecrets().properties.apiKey

@description('The repository URL (if configured)')
output repositoryUrl string = staticWebApp.properties.repositoryUrl

@description('The API endpoint URL')
output apiEndpoint string = 'https://${staticWebApp.properties.defaultHostname}/api'

@description('The status endpoint URL for health checks')
output statusEndpoint string = 'https://${staticWebApp.properties.defaultHostname}/api/status'

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights Connection String')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Resource Group Location')
output location string = location

@description('Managed Identity ID (Standard SKU only)')
output managedIdentityId string = staticWebAppSku == 'Standard' ? staticWebAppIdentity.id : ''

@description('All created resource names for verification')
output createdResources object = {
  staticWebApp: staticWebApp.name
  applicationInsights: applicationInsights.name
  logAnalyticsWorkspace: logAnalyticsWorkspace.name
  managedIdentity: staticWebAppSku == 'Standard' ? staticWebAppIdentity.name : ''
}