@description('Name of the Static Web App. Must be globally unique.')
param staticWebAppName string

@description('Location for the Static Web App resource.')
@allowed([
  'westus'
  'eastus'
  'eastus2'
  'westus2'
  'centralus'
  'northcentralus'
  'southcentralus'
  'westcentralus'
  'eastasia'
  'southeastasia'
  'northeurope'
  'westeurope'
  'japaneast'
  'japanwest'
  'australiaeast'
  'australiasoutheast'
  'brazilsouth'
  'uksouth'
  'ukwest'
  'canadacentral'
  'canadaeast'
  'francecentral'
  'francesouth'
  'germanywestcentral'
  'norwayeast'
  'switzerlandnorth'
  'uaenorth'
  'southafricanorth'
  'koreacentral'
  'koreasouth'
  'southindia'
  'centralindia'
  'westindia'
])
param location string = 'eastus'

@description('SKU for the Static Web App.')
@allowed([
  'Free'
  'Standard'
])
param sku string = 'Free'

@description('Repository URL for automated deployment (optional).')
param repositoryUrl string = ''

@description('Branch name for automated deployment.')
param branch string = 'main'

@description('App location in the repository.')
param appLocation string = '/'

@description('API location in the repository (for Azure Functions).')
param apiLocation string = ''

@description('Output location for built files.')
param outputLocation string = ''

@description('Build command to run during deployment.')
param buildCommand string = ''

@description('Tags to apply to the Static Web App resource.')
param tags object = {
  environment: 'demo'
  purpose: 'recipe'
  recipe: 'simple-website-hosting-static-web-apps-cli'
}

@description('Whether to enable staging environments.')
param enableStagingEnvironments bool = true

@description('Custom domain configurations (optional).')
param customDomains array = []

// Static Web App resource
resource staticWebApp 'Microsoft.Web/staticSites@2023-01-01' = {
  name: staticWebAppName
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
  }
  properties: {
    repositoryUrl: !empty(repositoryUrl) ? repositoryUrl : null
    branch: !empty(repositoryUrl) ? branch : null
    buildProperties: !empty(repositoryUrl) ? {
      appLocation: appLocation
      apiLocation: !empty(apiLocation) ? apiLocation : null
      outputLocation: !empty(outputLocation) ? outputLocation : null
      appBuildCommand: !empty(buildCommand) ? buildCommand : null
    } : null
    stagingEnvironmentPolicy: enableStagingEnvironments ? 'Enabled' : 'Disabled'
    allowConfigFileUpdates: true
    enterpriseGradeCdnStatus: 'Disabled'
  }
}

// Custom domains configuration (if provided)
resource customDomain 'Microsoft.Web/staticSites/customDomains@2023-01-01' = [for domain in customDomains: {
  parent: staticWebApp
  name: domain.name
  properties: {
    validationMethod: domain.validationMethod
  }
}]

// App settings for the Static Web App
resource appSettings 'Microsoft.Web/staticSites/config@2023-01-01' = {
  parent: staticWebApp
  name: 'appsettings'
  properties: {
    // Add any application settings here
    WEBSITE_NODE_DEFAULT_VERSION: '18.17.0'
  }
}

// Function app settings (if API location is specified)
resource functionAppSettings 'Microsoft.Web/staticSites/config@2023-01-01' = if (!empty(apiLocation)) {
  parent: staticWebApp
  name: 'functionappsettings'
  properties: {
    // Add any Azure Functions settings here
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=;AccountKey=;EndpointSuffix=core.windows.net'
  }
}

// Outputs
@description('The resource ID of the Static Web App.')
output staticWebAppId string = staticWebApp.id

@description('The default hostname of the Static Web App.')
output defaultHostname string = staticWebApp.properties.defaultHostname

@description('The repository token for GitHub integration (if applicable).')
output repositoryToken string = !empty(repositoryUrl) ? staticWebApp.listSecrets().properties.repositoryToken : ''

@description('The deployment token for manual deployments.')
output deploymentToken string = staticWebApp.listSecrets().properties.apiKey

@description('The resource name of the Static Web App.')
output staticWebAppName string = staticWebApp.name

@description('The location of the Static Web App.')
output location string = staticWebApp.location

@description('The SKU of the Static Web App.')
output sku string = staticWebApp.sku.name

@description('The full URL of the Static Web App.')
output websiteUrl string = 'https://${staticWebApp.properties.defaultHostname}'

@description('The staging environments configuration.')
output stagingEnvironmentPolicy string = staticWebApp.properties.stagingEnvironmentPolicy

@description('Custom domains configured for the Static Web App.')
output customDomains array = [for i in range(0, length(customDomains)): {
  name: customDomains[i].name
  status: customDomain[i].properties.status
  validationMethod: customDomains[i].validationMethod
}]