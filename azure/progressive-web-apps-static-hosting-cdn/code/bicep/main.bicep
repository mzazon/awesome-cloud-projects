// =============================================================================
// Bicep Template for Progressive Web Apps with Azure Static Web Apps and CDN
// =============================================================================
// This template deploys a complete Progressive Web App infrastructure including:
// - Azure Static Web Apps for PWA hosting with serverless API
// - Azure CDN for global content delivery and performance optimization
// - Application Insights for comprehensive monitoring and analytics
// - Proper security configurations and best practices
// =============================================================================

targetScope = 'resourceGroup'

// =============================================================================
// PARAMETERS
// =============================================================================

@description('Base name for all resources. Used to ensure consistent naming.')
@minLength(2)
@maxLength(10)
param baseName string = 'pwa'

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('GitHub repository URL for Static Web Apps CI/CD integration')
param repositoryUrl string = ''

@description('GitHub repository branch for deployment')
param repositoryBranch string = 'main'

@description('GitHub repository token for authentication (optional)')
@secure()
param repositoryToken string = ''

@description('Path to the app source code within the repository')
param appLocation string = 'src'

@description('Path to the API source code within the repository')
param apiLocation string = 'src/api'

@description('Path to the build output directory')
param outputLocation string = 'src'

@description('Static Web Apps SKU (Free or Standard)')
@allowed(['Free', 'Standard'])
param staticWebAppSku string = 'Free'

@description('CDN SKU for performance and features')
@allowed(['Standard_Microsoft', 'Standard_Akamai', 'Standard_Verizon', 'Premium_Verizon'])
param cdnSku string = 'Standard_Microsoft'

@description('Application Insights pricing tier')
@allowed(['Basic', 'Application Insights Enterprise'])
param appInsightsPricingTier string = 'Basic'

@description('Enable compression for CDN endpoint')
param enableCdnCompression bool = true

@description('Content types to compress at CDN edge')
param compressionContentTypes array = [
  'application/javascript'
  'application/json'
  'application/xml'
  'text/css'
  'text/html'
  'text/javascript'
  'text/plain'
  'text/xml'
  'image/svg+xml'
  'application/font-woff'
  'application/font-woff2'
]

@description('Cache duration for static assets in hours')
param staticAssetsCacheDuration string = '24:00:00'

@description('Cache duration for dynamic content in hours')
param dynamicContentCacheDuration string = '1:00:00'

@description('Common tags to apply to all resources')
param tags object = {
  Environment: environment
  Application: 'PWA'
  ManagedBy: 'Bicep'
  Recipe: 'building-progressive-web-apps-with-azure-static-web-apps-and-cdn'
}

// =============================================================================
// VARIABLES
// =============================================================================

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var resourceNames = {
  staticWebApp: 'swa-${baseName}-${environment}-${uniqueSuffix}'
  cdnProfile: 'cdn-${baseName}-${environment}-${uniqueSuffix}'
  cdnEndpoint: 'cdnep-${baseName}-${environment}-${uniqueSuffix}'
  applicationInsights: 'ai-${baseName}-${environment}-${uniqueSuffix}'
  logAnalyticsWorkspace: 'law-${baseName}-${environment}-${uniqueSuffix}'
}

// CDN caching rules configuration
var cachingRules = [
  {
    name: 'StaticAssetsCaching'
    order: 1
    conditions: [
      {
        name: 'UrlPath'
        parameters: {
          operator: 'BeginsWith'
          matchValues: ['/css/', '/js/', '/images/', '/fonts/', '/icons/']
        }
      }
    ]
    actions: [
      {
        name: 'CacheExpiration'
        parameters: {
          cacheBehavior: 'Override'
          cacheType: 'All'
          cacheDuration: staticAssetsCacheDuration
        }
      }
    ]
  }
  {
    name: 'PWAManifestCaching'
    order: 2
    conditions: [
      {
        name: 'UrlPath'
        parameters: {
          operator: 'EndsWith'
          matchValues: ['/manifest.json', '/sw.js', '/service-worker.js']
        }
      }
    ]
    actions: [
      {
        name: 'CacheExpiration'
        parameters: {
          cacheBehavior: 'Override'
          cacheType: 'All'
          cacheDuration: '1:00:00'
        }
      }
    ]
  }
  {
    name: 'APICaching'
    order: 3
    conditions: [
      {
        name: 'UrlPath'
        parameters: {
          operator: 'BeginsWith'
          matchValues: ['/api/']
        }
      }
    ]
    actions: [
      {
        name: 'CacheExpiration'
        parameters: {
          cacheBehavior: 'Override'
          cacheType: 'All'
          cacheDuration: dynamicContentCacheDuration
        }
      }
    ]
  }
]

// =============================================================================
// RESOURCES
// =============================================================================

// Log Analytics Workspace for Application Insights
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for PWA monitoring and analytics
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.applicationInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    RetentionInDays: 90
  }
}

// Azure Static Web Apps for PWA hosting with serverless API
resource staticWebApp 'Microsoft.Web/staticSites@2023-01-01' = {
  name: resourceNames.staticWebApp
  location: location
  tags: tags
  sku: {
    name: staticWebAppSku
    tier: staticWebAppSku
  }
  properties: {
    // GitHub integration properties
    repositoryUrl: repositoryUrl
    branch: repositoryBranch
    repositoryToken: empty(repositoryToken) ? null : repositoryToken
    
    // Build configuration
    buildProperties: {
      appLocation: appLocation
      apiLocation: apiLocation
      outputLocation: outputLocation
      skipGithubActionWorkflowGeneration: false
    }
    
    // Static Web Apps configuration
    allowConfigFileUpdates: true
    stagingEnvironmentPolicy: 'Enabled'
    
    // Enterprise features (available in Standard SKU)
    enterpriseGradeCdnStatus: staticWebAppSku == 'Standard' ? 'Enabled' : 'Disabled'
  }
}

// Application Insights configuration for Static Web Apps
resource staticWebAppAppInsights 'Microsoft.Web/staticSites/config@2023-01-01' = {
  parent: staticWebApp
  name: 'appsettings'
  properties: {
    APPINSIGHTS_INSTRUMENTATIONKEY: applicationInsights.properties.InstrumentationKey
    APPINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
  }
}

// Azure CDN Profile for global content delivery
resource cdnProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: resourceNames.cdnProfile
  location: 'global'
  tags: tags
  sku: {
    name: cdnSku
  }
  properties: {
    originResponseTimeoutSeconds: 240
  }
}

// CDN Endpoint for Static Web Apps
resource cdnEndpoint 'Microsoft.Cdn/profiles/endpoints@2023-05-01' = {
  parent: cdnProfile
  name: resourceNames.cdnEndpoint
  location: 'global'
  tags: tags
  properties: {
    // Origin configuration pointing to Static Web Apps
    origins: [
      {
        name: 'staticwebapp-origin'
        properties: {
          hostName: staticWebApp.properties.defaultHostname
          httpsPort: 443
          originHostHeader: staticWebApp.properties.defaultHostname
          priority: 1
          weight: 1000
          enabled: true
        }
      }
    ]
    
    // CDN optimization settings
    isHttpAllowed: false
    isHttpsAllowed: true
    queryStringCachingBehavior: 'UseQueryString'
    isCompressionEnabled: enableCdnCompression
    contentTypesToCompress: compressionContentTypes
    
    // Origin request policy
    originRequestPolicy: {
      name: 'pwa-origin-request-policy'
      properties: {
        requestHeadersToForward: [
          'Accept'
          'Accept-Language'
          'User-Agent'
          'X-Forwarded-For'
          'X-Forwarded-Host'
          'X-Forwarded-Proto'
        ]
        queryStringParameters: {
          queryStringBehavior: 'Include'
          queryStringParameters: ['*']
        }
      }
    }
  }
}

// CDN Caching Rules for PWA optimization
resource cdnCachingRules 'Microsoft.Cdn/profiles/endpoints/deliveryPolicies@2023-05-01' = [for rule in cachingRules: {
  parent: cdnEndpoint
  name: rule.name
  properties: {
    order: rule.order
    conditions: rule.conditions
    actions: rule.actions
  }
}]

// Custom domain support (requires manual domain verification)
resource cdnCustomDomain 'Microsoft.Cdn/profiles/endpoints/customDomains@2023-05-01' = if (!empty(repositoryUrl)) {
  parent: cdnEndpoint
  name: 'custom-domain'
  properties: {
    hostName: '${resourceNames.cdnEndpoint}.azureedge.net'
    httpsParameters: {
      certificateSource: 'Cdn'
      protocolType: 'ServerNameIndication'
    }
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('Static Web App resource ID')
output staticWebAppId string = staticWebApp.id

@description('Static Web App default hostname')
output staticWebAppUrl string = 'https://${staticWebApp.properties.defaultHostname}'

@description('Static Web App custom domains')
output staticWebAppCustomDomains array = staticWebApp.properties.customDomains

@description('CDN Profile resource ID')
output cdnProfileId string = cdnProfile.id

@description('CDN Endpoint hostname')
output cdnEndpointUrl string = 'https://${cdnEndpoint.properties.hostName}'

@description('CDN Endpoint resource ID')
output cdnEndpointId string = cdnEndpoint.id

@description('Application Insights resource ID')
output applicationInsightsId string = applicationInsights.id

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Resource group information')
output resourceGroup object = {
  id: resourceGroup().id
  name: resourceGroup().name
  location: resourceGroup().location
}

@description('Deployment configuration summary')
output deploymentSummary object = {
  staticWebAppSku: staticWebAppSku
  cdnSku: cdnSku
  environment: environment
  location: location
  repositoryUrl: repositoryUrl
  repositoryBranch: repositoryBranch
  compressionEnabled: enableCdnCompression
  enterpriseCdnEnabled: staticWebAppSku == 'Standard'
}

@description('Next steps for PWA deployment')
output nextSteps array = [
  'Configure GitHub repository integration in the Azure portal'
  'Set up custom domain and SSL certificate for CDN endpoint'
  'Configure Application Insights dashboard for PWA monitoring'
  'Review and customize CDN caching rules based on your PWA requirements'
  'Set up staging environments for testing deployments'
  'Configure authentication providers if needed'
]