// Deployment script for Infrastructure Inventory Reports with Resource Graph
// This file demonstrates subscription-level deployment for multiple resource groups

targetScope = 'subscription'

@description('The Azure region where resources will be deployed')
param location string = 'East US'

@description('Name of the resource group to create')
param resourceGroupName string = 'rg-inventory-resource-graph'

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Organization name for resource naming')
@minLength(2)
@maxLength(10)
param organizationName string

@description('Enable automated inventory reports')
param enableAutomatedReports bool = true

@description('Inventory report frequency in hours (24, 48, 72, 168)')
@allowed([24, 48, 72, 168])
param reportFrequencyHours int = 24

@description('Storage account tier for inventory reports')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountType string = 'Standard_LRS'

@description('Enable compliance monitoring queries')
param enableComplianceMonitoring bool = true

@description('Resource tags to apply to all resources')
param tags object = {
  Environment: environment
  Solution: 'Infrastructure-Inventory-Resource-Graph'
  ManagedBy: 'Bicep'
  DeployedBy: 'Azure-CLI'
  CreatedDate: utcNow('yyyy-MM-dd')
}

// Create resource group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// Deploy main infrastructure to the resource group
module infrastructureDeployment 'main.bicep' = {
  name: 'infrastructure-inventory-deployment'
  scope: resourceGroup
  params: {
    location: location
    environment: environment
    organizationName: organizationName
    enableAutomatedReports: enableAutomatedReports
    reportFrequencyHours: reportFrequencyHours
    storageAccountType: storageAccountType
    enableComplianceMonitoring: enableComplianceMonitoring
    tags: tags
  }
}

// Outputs
@description('Name of the created resource group')
output resourceGroupName string = resourceGroup.name

@description('Name of the storage account containing inventory reports')
output storageAccountName string = infrastructureDeployment.outputs.storageAccountName

@description('Resource ID of the managed identity for Resource Graph access')
output managedIdentityId string = infrastructureDeployment.outputs.managedIdentityId

@description('Principal ID of the managed identity')
output managedIdentityPrincipalId string = infrastructureDeployment.outputs.managedIdentityPrincipalId

@description('Client ID of the managed identity')
output managedIdentityClientId string = infrastructureDeployment.outputs.managedIdentityClientId

@description('Name of the Function App (if automated reports are enabled)')
output functionAppName string = infrastructureDeployment.outputs.functionAppName

@description('Name of the Key Vault containing secrets')
output keyVaultName string = infrastructureDeployment.outputs.keyVaultName

@description('Name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = infrastructureDeployment.outputs.logAnalyticsWorkspaceName

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = infrastructureDeployment.outputs.applicationInsightsInstrumentationKey

@description('URL to access the inventory dashboard workbook')
output workbookUrl string = infrastructureDeployment.outputs.workbookUrl

@description('Sample Resource Graph queries for inventory reporting')
output sampleQueries object = infrastructureDeployment.outputs.sampleQueries

@description('Instructions for using the deployed infrastructure')
output usageInstructions object = infrastructureDeployment.outputs.usageInstructions

@description('Next steps for configuration')
output nextSteps array = [
  'Install Azure Resource Graph CLI extension: az extension add --name resource-graph'
  'Test Resource Graph connectivity: az graph query -q "Resources | limit 5" --output table'
  'Access the inventory dashboard using the provided workbook URL'
  'Configure automated reports in the Function App (if enabled)'
  'Set up alerting rules in Azure Monitor for compliance violations'
  'Export inventory data using the sample queries provided in outputs'
]