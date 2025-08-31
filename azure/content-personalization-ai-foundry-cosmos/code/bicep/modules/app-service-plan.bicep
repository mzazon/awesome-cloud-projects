@description('App Service Plan module for Azure Functions hosting')

// Parameters
@description('Name of the App Service Plan')
param planName string

@description('Azure region for resource deployment')
param location string

@description('Tags to apply to the resource')
param tags object = {}

@description('SKU for the App Service Plan')
@allowed(['Y1', 'EP1', 'EP2', 'EP3'])
param sku string = 'Y1'

@description('OS type for the App Service Plan')
@allowed(['Linux', 'Windows'])
param osType string = 'Linux'

@description('Whether this is a consumption plan')
param isConsumption bool = true

// Variables
var appServicePlanSku = {
  name: sku
  tier: sku == 'Y1' ? 'Dynamic' : 'ElasticPremium'
  size: sku
  family: sku == 'Y1' ? 'Y' : 'EP'
  capacity: sku == 'Y1' ? 0 : 1
}

// Resources
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  tags: tags
  sku: appServicePlanSku
  kind: osType == 'Linux' ? 'linux' : ''
  properties: {
    reserved: osType == 'Linux'
    maximumElasticWorkerCount: sku == 'Y1' ? null : 20
    isSpot: false
    perSiteScaling: false
    elasticScaleEnabled: sku != 'Y1'
    hyperV: false
    targetWorkerCount: sku == 'Y1' ? 0 : 1
    targetWorkerSizeId: sku == 'Y1' ? 0 : null
  }
}

// Outputs
@description('App Service Plan Resource ID')
output appServicePlanId string = appServicePlan.id

@description('App Service Plan Name')
output appServicePlanName string = appServicePlan.name

@description('App Service Plan SKU')
output skuName string = appServicePlan.sku.name

@description('App Service Plan Tier')
output skuTier string = appServicePlan.sku.tier

@description('App Service Plan Configuration Summary')
output planConfig object = {
  name: appServicePlan.name
  sku: appServicePlan.sku.name
  tier: appServicePlan.sku.tier
  osType: osType
  isConsumption: isConsumption
  location: location
}