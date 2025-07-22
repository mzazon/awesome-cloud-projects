@description('Location for primary region resources')
param primaryLocation string = 'eastus'

@description('Location for secondary region resources')
param secondaryLocation string = 'uksouth'

@description('Location for tertiary region resources')
param tertiaryLocation string = 'southeastasia'

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Admin username for VM Scale Sets')
param adminUsername string = 'azureuser'

@description('SSH public key for VM Scale Sets')
@secure()
param sshPublicKey string

@description('VM Scale Set instance count per region')
param vmssInstanceCount int = 2

@description('VM Scale Set SKU')
param vmssSkuName string = 'Standard_B2s'

@description('Application Gateway capacity')
param appGatewayCapacity int = 2

@description('Traffic Manager TTL in seconds')
param trafficManagerTtl int = 30

@description('Environment tag')
param environmentTag string = 'production'

@description('Purpose tag')
param purposeTag string = 'global-traffic-distribution'

// Variables for consistent naming
var trafficManagerProfileName = 'tm-global-app-${uniqueSuffix}'
var appGatewayPrimaryName = 'agw-primary-${uniqueSuffix}'
var appGatewaySecondaryName = 'agw-secondary-${uniqueSuffix}'
var appGatewayTertiaryName = 'agw-tertiary-${uniqueSuffix}'

// Common tags
var commonTags = {
  environment: environmentTag
  purpose: purposeTag
  'created-by': 'bicep-template'
}

// Primary region resources
module primaryRegion 'modules/regional-infrastructure.bicep' = {
  name: 'primary-region-deployment'
  params: {
    location: primaryLocation
    regionName: 'primary'
    uniqueSuffix: uniqueSuffix
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmssInstanceCount: vmssInstanceCount
    vmssSkuName: vmssSkuName
    appGatewayCapacity: appGatewayCapacity
    appGatewayName: appGatewayPrimaryName
    regionDisplayName: 'Primary Region - East US'
    tags: commonTags
  }
}

// Secondary region resources
module secondaryRegion 'modules/regional-infrastructure.bicep' = {
  name: 'secondary-region-deployment'
  params: {
    location: secondaryLocation
    regionName: 'secondary'
    uniqueSuffix: uniqueSuffix
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmssInstanceCount: vmssInstanceCount
    vmssSkuName: vmssSkuName
    appGatewayCapacity: appGatewayCapacity
    appGatewayName: appGatewaySecondaryName
    regionDisplayName: 'Secondary Region - UK South'
    tags: commonTags
  }
}

// Tertiary region resources
module tertiaryRegion 'modules/regional-infrastructure.bicep' = {
  name: 'tertiary-region-deployment'
  params: {
    location: tertiaryLocation
    regionName: 'tertiary'
    uniqueSuffix: uniqueSuffix
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmssInstanceCount: vmssInstanceCount
    vmssSkuName: vmssSkuName
    appGatewayCapacity: appGatewayCapacity
    appGatewayName: appGatewayTertiaryName
    regionDisplayName: 'Tertiary Region - Southeast Asia'
    tags: commonTags
  }
}

// Log Analytics workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-global-traffic-${uniqueSuffix}'
  location: primaryLocation
  tags: commonTags
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

// Traffic Manager Profile
resource trafficManagerProfile 'Microsoft.Network/trafficManagerProfiles@2022-04-01' = {
  name: trafficManagerProfileName
  location: 'global'
  tags: commonTags
  properties: {
    profileStatus: 'Enabled'
    trafficRoutingMethod: 'Performance'
    dnsConfig: {
      relativeName: trafficManagerProfileName
      ttl: trafficManagerTtl
    }
    monitorConfig: {
      protocol: 'HTTP'
      port: 80
      path: '/'
      intervalInSeconds: 30
      timeoutInSeconds: 10
      toleratedNumberOfFailures: 3
    }
  }
}

// Traffic Manager Endpoints
resource trafficManagerEndpointPrimary 'Microsoft.Network/trafficManagerProfiles/externalEndpoints@2022-04-01' = {
  parent: trafficManagerProfile
  name: 'endpoint-primary'
  properties: {
    target: primaryRegion.outputs.appGatewayPublicIp
    endpointStatus: 'Enabled'
    endpointLocation: primaryLocation
    priority: 1
    weight: 100
  }
}

resource trafficManagerEndpointSecondary 'Microsoft.Network/trafficManagerProfiles/externalEndpoints@2022-04-01' = {
  parent: trafficManagerProfile
  name: 'endpoint-secondary'
  properties: {
    target: secondaryRegion.outputs.appGatewayPublicIp
    endpointStatus: 'Enabled'
    endpointLocation: secondaryLocation
    priority: 2
    weight: 100
  }
}

resource trafficManagerEndpointTertiary 'Microsoft.Network/trafficManagerProfiles/externalEndpoints@2022-04-01' = {
  parent: trafficManagerProfile
  name: 'endpoint-tertiary'
  properties: {
    target: tertiaryRegion.outputs.appGatewayPublicIp
    endpointStatus: 'Enabled'
    endpointLocation: tertiaryLocation
    priority: 3
    weight: 100
  }
}

// Diagnostic settings for Traffic Manager
resource trafficManagerDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'traffic-manager-diagnostics'
  scope: trafficManagerProfile
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
    logs: [
      {
        category: 'ProbeHealthStatusEvents'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
  }
}

// Outputs
@description('Traffic Manager Profile FQDN')
output trafficManagerFqdn string = trafficManagerProfile.properties.dnsConfig.fqdn

@description('Traffic Manager Profile Name')
output trafficManagerProfileName string = trafficManagerProfile.name

@description('Primary Region Application Gateway Public IP')
output primaryAppGatewayPublicIp string = primaryRegion.outputs.appGatewayPublicIp

@description('Secondary Region Application Gateway Public IP')
output secondaryAppGatewayPublicIp string = secondaryRegion.outputs.appGatewayPublicIp

@description('Tertiary Region Application Gateway Public IP')
output tertiaryAppGatewayPublicIp string = tertiaryRegion.outputs.appGatewayPublicIp

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Primary Region Resource Group')
output primaryResourceGroup string = primaryRegion.outputs.resourceGroupName

@description('Secondary Region Resource Group')
output secondaryResourceGroup string = secondaryRegion.outputs.resourceGroupName

@description('Tertiary Region Resource Group')
output tertiaryResourceGroup string = tertiaryRegion.outputs.resourceGroupName