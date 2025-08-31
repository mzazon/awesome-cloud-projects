@description('Name of the Static Web App')
param staticWebAppName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('SKU for the Static Web App')
@allowed([
  'Free'
  'Standard'
])
param staticWebAppSku string = 'Free'

@description('App location (folder path relative to repository root)')
param appLocation string = '/src'

@description('API location (folder path relative to repository root)')
param apiLocation string = '/api'

@description('Output location (folder path relative to repository root)')
param outputLocation string = ''

@description('OpenWeatherMap API key for weather data')
@secure()
param openWeatherApiKey string

@description('Optional GitHub repository URL for automated deployments')
param repositoryUrl string = ''

@description('Optional GitHub branch for automated deployments')
param branch string = 'main'

@description('Optional GitHub repository token for automated deployments')
@secure()
param repositoryToken string = ''

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'recipe'
  environment: 'demo'
  recipe: 'simple-weather-dashboard'
}

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
    repositoryUrl: empty(repositoryUrl) ? null : repositoryUrl
    branch: empty(repositoryUrl) ? null : branch
    repositoryToken: empty(repositoryToken) ? null : repositoryToken
    buildProperties: {
      appLocation: appLocation
      apiLocation: apiLocation
      outputLocation: outputLocation
    }
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    provider: empty(repositoryUrl) ? 'None' : 'GitHub'
    enterpriseGradeCdnStatus: 'Disabled'
  }
}

// Application settings for the Static Web App
resource staticWebAppSettings 'Microsoft.Web/staticSites/config@2023-01-01' = {
  parent: staticWebApp
  name: 'appsettings'
  properties: {
    OPENWEATHER_API_KEY: openWeatherApiKey
  }
}

// Function app settings (part of Static Web App managed functions)
resource staticWebAppFunctionSettings 'Microsoft.Web/staticSites/config@2023-01-01' = {
  parent: staticWebApp
  name: 'functionappsettings'
  properties: {
    OPENWEATHER_API_KEY: openWeatherApiKey
    FUNCTIONS_WORKER_RUNTIME: 'node'
    WEBSITE_NODE_DEFAULT_VERSION: '~18'
  }
}

// Custom domain (optional - only if provided)
resource customDomain 'Microsoft.Web/staticSites/customDomains@2023-01-01' = if (!empty(repositoryUrl)) {
  parent: staticWebApp
  name: 'default'
  properties: {
    domainName: staticWebApp.properties.defaultHostname
  }
}

// Output values for verification and integration
@description('The default hostname of the Static Web App')
output staticWebAppUrl string = staticWebApp.properties.defaultHostname

@description('The resource ID of the Static Web App')
output staticWebAppId string = staticWebApp.id

@description('The name of the Static Web App')
output staticWebAppName string = staticWebApp.name

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('The deployment token for GitHub Actions (if using repository deployment)')
output deploymentToken string = staticWebApp.listSecrets().properties.apiKey

@description('The managed Functions endpoint')
output functionsEndpoint string = 'https://${staticWebApp.properties.defaultHostname}/api'

@description('Static Web App configuration summary')
output configuration object = {
  name: staticWebApp.name
  url: staticWebApp.properties.defaultHostname
  sku: staticWebAppSku
  location: location
  appLocation: appLocation
  apiLocation: apiLocation
  repositoryConfigured: !empty(repositoryUrl)
  customDomainConfigured: !empty(repositoryUrl)
}