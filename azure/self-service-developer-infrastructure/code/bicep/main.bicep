@description('The name of the Azure Dev Center')
@maxLength(63)
param devCenterName string = 'dc-selfservice-${uniqueString(resourceGroup().id)}'

@description('The name of the project')
@maxLength(63)
param projectName string = 'proj-webapp-team'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The tags to apply to all resources')
param tags object = {
  purpose: 'demo'
  environment: 'development'
  solution: 'dev-infrastructure'
}

@description('The address prefix for the virtual network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('The address prefix for the dev box subnet')
param devBoxSubnetPrefix string = '10.0.1.0/24'

@description('The name of the dev box pool')
param devBoxPoolName string = 'WebDevPool'

@description('The name of the dev box definition')
param devBoxDefinitionName string = 'VSEnterprise-8cpu-32gb'

@description('The SKU name for the dev box')
@allowed([
  'general_i_8c32gb256ssd_v2'
  'general_i_16c64gb512ssd_v2'
  'general_i_32c128gb1024ssd_v2'
])
param devBoxSku string = 'general_i_8c32gb256ssd_v2'

@description('Enable hibernate support for dev boxes')
param hibernateSupport bool = true

@description('Auto-stop time in 24-hour format (e.g., 19:00)')
param autoStopTime string = '19:00'

@description('Timezone for the auto-stop schedule')
param autoStopTimezone string = 'Eastern Standard Time'

@description('Environment types to create')
param environmentTypes array = [
  {
    name: 'Development'
    tags: {
      purpose: 'development'
      'cost-center': 'engineering'
    }
  }
  {
    name: 'Staging'
    tags: {
      purpose: 'staging'
      'cost-center': 'engineering'
    }
  }
]

@description('The object ID of the user to assign developer roles to')
param developerUserObjectId string = ''

// Variables
var networkConnectionName = 'nc-devbox-${uniqueString(resourceGroup().id)}'
var vnetName = 'vnet-devbox-${uniqueString(resourceGroup().id)}'
var subnetName = 'snet-devbox'
var catalogName = 'QuickStartCatalog'
var devBoxImageReference = 'MicrosoftWindowsDesktop_windows-ent-cpc_win11-22h2-ent-cpc-vs2022'

// Virtual Network for Dev Boxes
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: devBoxSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// Network Security Group for Dev Box subnet
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: '${subnetName}-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowRDPInbound'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'AllowHTTPSOutbound'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

// Network Connection for Dev Center
resource networkConnection 'Microsoft.DevCenter/networkConnections@2024-02-01' = {
  name: networkConnectionName
  location: location
  tags: tags
  properties: {
    networkingResourceGroupName: resourceGroup().name
    subnetId: '${vnet.id}/subnets/${subnetName}'
    domainJoinType: 'AzureADJoin'
  }
}

// Dev Center
resource devCenter 'Microsoft.DevCenter/devcenters@2024-02-01' = {
  name: devCenterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: devCenterName
  }
}

// Attach Network Connection to Dev Center
resource attachedNetwork 'Microsoft.DevCenter/devcenters/attachednetworks@2024-02-01' = {
  name: 'default'
  parent: devCenter
  properties: {
    networkConnectionId: networkConnection.id
  }
}

// Create Catalog for Environment Definitions
resource catalog 'Microsoft.DevCenter/devcenters/catalogs@2024-02-01' = {
  name: catalogName
  parent: devCenter
  properties: {
    gitHub: {
      uri: 'https://github.com/microsoft/devcenter-catalog.git'
      branch: 'main'
      path: '/Environment-Definitions'
    }
  }
}

// Create Environment Types in Dev Center
resource devCenterEnvironmentTypes 'Microsoft.DevCenter/devcenters/environmentTypes@2024-02-01' = [for envType in environmentTypes: {
  name: envType.name
  parent: devCenter
  tags: envType.tags
  properties: {
    displayName: envType.name
  }
}]

// Dev Box Definition
resource devBoxDefinition 'Microsoft.DevCenter/devcenters/devboxdefinitions@2024-02-01' = {
  name: devBoxDefinitionName
  parent: devCenter
  location: location
  tags: tags
  properties: {
    imageReference: {
      id: '${devCenter.id}/galleries/default/images/${devBoxImageReference}'
    }
    sku: {
      name: devBoxSku
    }
    hibernateSupport: hibernateSupport ? 'Enabled' : 'Disabled'
    osStorageType: 'ssd_256gb'
  }
}

// Project
resource project 'Microsoft.DevCenter/projects@2024-02-01' = {
  name: projectName
  location: location
  tags: tags
  properties: {
    devCenterId: devCenter.id
    description: 'Web application team development project'
    displayName: projectName
  }
}

// Project Environment Types
resource projectEnvironmentTypes 'Microsoft.DevCenter/projects/environmentTypes@2024-02-01' = [for envType in environmentTypes: {
  name: envType.name
  parent: project
  properties: {
    creatorRoleAssignment: {
      roles: {
        '4f8fab4f-1852-4a58-a46a-8eaf358af14a': {} // Owner role
      }
    }
    deploymentTargetId: '/subscriptions/${subscription().subscriptionId}'
    status: 'Enabled'
  }
  identity: {
    type: 'SystemAssigned'
  }
}]

// Dev Box Pool
resource devBoxPool 'Microsoft.DevCenter/projects/pools@2024-02-01' = {
  name: devBoxPoolName
  parent: project
  location: location
  tags: tags
  properties: {
    devBoxDefinitionName: devBoxDefinition.name
    networkConnectionName: attachedNetwork.name
    localAdministrator: 'Enabled'
    licenseType: 'Windows_Client'
    singleSignOnStatus: 'Enabled'
    displayName: devBoxPoolName
  }
}

// Auto-stop Schedule for Dev Box Pool
resource autoStopSchedule 'Microsoft.DevCenter/projects/pools/schedules@2024-02-01' = {
  name: 'AutoStop-7PM'
  parent: devBoxPool
  properties: {
    type: 'StopDevBox'
    frequency: 'Daily'
    time: autoStopTime
    timeZone: autoStopTimezone
    state: 'Enabled'
  }
}

// Role Assignments for Dev Center System Identity
resource devCenterContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, devCenter.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: devCenter.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource devCenterUserAccessAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, devCenter.id, '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9') // User Access Administrator
    principalId: devCenter.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Developer Role Assignments (conditional on user object ID being provided)
resource devBoxUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(developerUserObjectId)) {
  name: guid(project.id, developerUserObjectId, '45d50f46-0b78-4001-a660-4198cbe8cd05')
  scope: project
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '45d50f46-0b78-4001-a660-4198cbe8cd05') // DevCenter Dev Box User
    principalId: developerUserObjectId
    principalType: 'User'
  }
}

resource deploymentEnvironmentsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(developerUserObjectId)) {
  name: guid(project.id, developerUserObjectId, '18e40d4e-8d2e-438d-97e1-9528336e149c')
  scope: project
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '18e40d4e-8d2e-438d-97e1-9528336e149c') // Deployment Environments User
    principalId: developerUserObjectId
    principalType: 'User'
  }
}

// Outputs
@description('The name of the created Dev Center')
output devCenterName string = devCenter.name

@description('The resource ID of the created Dev Center')
output devCenterResourceId string = devCenter.id

@description('The name of the created project')
output projectName string = project.name

@description('The resource ID of the created project')
output projectResourceId string = project.id

@description('The name of the created Dev Box pool')
output devBoxPoolName string = devBoxPool.name

@description('The developer portal URL')
output developerPortalUrl string = 'https://devportal.microsoft.com'

@description('The virtual network resource ID')
output vnetResourceId string = vnet.id

@description('The network connection resource ID')
output networkConnectionResourceId string = networkConnection.id

@description('The Dev Center system identity principal ID')
output devCenterPrincipalId string = devCenter.identity.principalId

@description('The created environment types')
output environmentTypes array = [for i in range(0, length(environmentTypes)): {
  name: environmentTypes[i].name
  resourceId: devCenterEnvironmentTypes[i].id
}]

@description('The catalog sync status (check in portal)')
output catalogInfo object = {
  name: catalog.name
  resourceId: catalog.id
  gitHubUri: 'https://github.com/microsoft/devcenter-catalog.git'
}