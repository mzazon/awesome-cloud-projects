@description('Main Bicep template for Automated Disaster Recovery with Azure Site Recovery and Azure Update Manager')

// Parameters
@description('Primary Azure region for resources')
param primaryLocation string = 'eastus'

@description('Secondary Azure region for disaster recovery')
param secondaryLocation string = 'westus'

@description('Prefix for resource names')
param resourcePrefix string = 'dr'

@description('Admin username for VMs')
param adminUsername string = 'azureuser'

@description('Admin password for VMs')
@secure()
param adminPassword string

@description('VM size for test virtual machines')
param vmSize string = 'Standard_B2s'

@description('Storage account type')
@allowed([
  'Premium_LRS'
  'Standard_LRS'
  'StandardSSD_LRS'
])
param storageAccountType string = 'Premium_LRS'

@description('Email address for disaster recovery alerts')
param adminEmail string

@description('Tags to be applied to all resources')
param tags object = {
  purpose: 'disaster-recovery'
  environment: 'production'
  solution: 'azure-site-recovery'
}

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id)
var primaryResourceGroupName = 'rg-${resourcePrefix}-primary-${uniqueSuffix}'
var secondaryResourceGroupName = 'rg-${resourcePrefix}-secondary-${uniqueSuffix}'
var vaultName = 'rsv-${resourcePrefix}-${uniqueSuffix}'
var automationAccountName = 'auto-updates-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-${resourcePrefix}-${uniqueSuffix}'
var actionGroupName = 'ag-${resourcePrefix}-${uniqueSuffix}'
var primaryVnetName = 'vnet-primary-${uniqueSuffix}'
var secondaryVnetName = 'vnet-secondary-${uniqueSuffix}'
var primaryNsgName = 'nsg-primary-${uniqueSuffix}'
var secondaryNsgName = 'nsg-secondary-${uniqueSuffix}'
var primaryVmName = 'vm-primary-${uniqueSuffix}'
var storageAccountName = 'storage${uniqueSuffix}'

// Primary Region Resources
module primaryInfrastructure 'modules/primary-infrastructure.bicep' = {
  name: 'primary-infrastructure'
  params: {
    location: primaryLocation
    resourcePrefix: resourcePrefix
    uniqueSuffix: uniqueSuffix
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
    storageAccountType: storageAccountType
    tags: tags
  }
}

// Secondary Region Resources
module secondaryInfrastructure 'modules/secondary-infrastructure.bicep' = {
  name: 'secondary-infrastructure'
  params: {
    location: secondaryLocation
    resourcePrefix: resourcePrefix
    uniqueSuffix: uniqueSuffix
    tags: tags
  }
}

// Recovery Services Vault
module recoveryVault 'modules/recovery-vault.bicep' = {
  name: 'recovery-vault'
  params: {
    location: secondaryLocation
    vaultName: vaultName
    tags: tags
  }
  dependsOn: [
    secondaryInfrastructure
  ]
}

// Automation Account for Update Management
module automationAccount 'modules/automation-account.bicep' = {
  name: 'automation-account'
  params: {
    location: primaryLocation
    automationAccountName: automationAccountName
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    tags: tags
  }
  dependsOn: [
    primaryInfrastructure
  ]
}

// Monitoring and Alerting
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: primaryLocation
    actionGroupName: actionGroupName
    adminEmail: adminEmail
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    primaryVmResourceId: primaryInfrastructure.outputs.primaryVmResourceId
    tags: tags
  }
  dependsOn: [
    primaryInfrastructure
    automationAccount
  ]
}

// Site Recovery Configuration
module siteRecovery 'modules/site-recovery.bicep' = {
  name: 'site-recovery'
  params: {
    vaultName: vaultName
    primaryLocation: primaryLocation
    secondaryLocation: secondaryLocation
    primaryVmResourceId: primaryInfrastructure.outputs.primaryVmResourceId
    primaryVnetId: primaryInfrastructure.outputs.primaryVnetId
    secondaryVnetId: secondaryInfrastructure.outputs.secondaryVnetId
    storageAccountName: storageAccountName
    tags: tags
  }
  dependsOn: [
    primaryInfrastructure
    secondaryInfrastructure
    recoveryVault
  ]
}

// Outputs
@description('Primary VM resource ID')
output primaryVmResourceId string = primaryInfrastructure.outputs.primaryVmResourceId

@description('Primary VM name')
output primaryVmName string = primaryInfrastructure.outputs.primaryVmName

@description('Recovery Services Vault name')
output vaultName string = vaultName

@description('Automation Account name')
output automationAccountName string = automationAccount.outputs.automationAccountName

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = automationAccount.outputs.logAnalyticsWorkspaceName

@description('Primary Virtual Network ID')
output primaryVnetId string = primaryInfrastructure.outputs.primaryVnetId

@description('Secondary Virtual Network ID')
output secondaryVnetId string = secondaryInfrastructure.outputs.secondaryVnetId

@description('Storage Account name for Site Recovery')
output storageAccountName string = storageAccountName

@description('Action Group name for alerts')
output actionGroupName string = actionGroupName

@description('Primary region')
output primaryLocation string = primaryLocation

@description('Secondary region')
output secondaryLocation string = secondaryLocation