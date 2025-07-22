// Deploy script for the full-stack serverless web application
// This file demonstrates how to deploy the main template with modules

targetScope = 'resourceGroup'

@description('The name of the Static Web App')
param staticWebAppName string = 'swa-fullstack-app'

@description('The name of the Storage Account')
param storageAccountName string = 'stfullstack${uniqueString(resourceGroup().id)}'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The GitHub repository URL')
param repositoryUrl string = ''

@description('The GitHub branch to deploy from')
param branch string = 'main'

@description('The GitHub token for authentication')
@secure()
param repositoryToken string = ''

@description('The location of the app source code')
param appLocation string = '/'

@description('The location of the API source code')
param apiLocation string = 'api'

@description('The location of the built app content')
param outputLocation string = 'build'

@description('The SKU for the Static Web App')
@allowed([
  'Free'
  'Standard'
])
param staticWebAppSku string = 'Free'

@description('The SKU for the Storage Account')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
  'Premium_ZRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'recipe'
  environment: 'demo'
  recipe: 'building-full-stack-serverless-web-applications'
}

// Deploy the main template
module fullStackApp 'main.bicep' = {
  name: 'fullstack-serverless-deployment'
  params: {
    staticWebAppName: staticWebAppName
    storageAccountName: storageAccountName
    location: location
    repositoryUrl: repositoryUrl
    branch: branch
    repositoryToken: repositoryToken
    appLocation: appLocation
    apiLocation: apiLocation
    outputLocation: outputLocation
    staticWebAppSku: staticWebAppSku
    storageAccountSku: storageAccountSku
    tags: tags
  }
}

// Outputs from the main deployment
@description('The name of the Static Web App')
output staticWebAppName string = fullStackApp.outputs.staticWebAppName

@description('The URL of the Static Web App')
output staticWebAppUrl string = fullStackApp.outputs.staticWebAppUrl

@description('The hostname of the Static Web App')
output staticWebAppHostname string = fullStackApp.outputs.staticWebAppHostname

@description('The name of the Storage Account')
output storageAccountName string = fullStackApp.outputs.storageAccountName

@description('The connection string for the Storage Account')
output storageConnectionString string = fullStackApp.outputs.storageConnectionString

@description('The API key for the Static Web App')
output apiKey string = fullStackApp.outputs.apiKey

@description('Deployment summary')
output deploymentSummary object = {
  staticWebAppName: fullStackApp.outputs.staticWebAppName
  staticWebAppUrl: fullStackApp.outputs.staticWebAppUrl
  storageAccountName: fullStackApp.outputs.storageAccountName
  tasksTableName: fullStackApp.outputs.tasksTableName
  location: fullStackApp.outputs.location
  resourceGroupName: fullStackApp.outputs.resourceGroupName
}