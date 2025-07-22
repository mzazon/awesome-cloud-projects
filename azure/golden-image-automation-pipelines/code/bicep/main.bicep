@description('The name of the resource group where all resources will be deployed')
param resourceGroupName string = 'rg-golden-image-${uniqueString(resourceGroup().id)}'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('The name prefix for all resources')
param namePrefix string = 'golden-image'

@description('The name of the hub virtual network')
param hubVnetName string = 'vnet-hub-${uniqueString(resourceGroup().id)}'

@description('The name of the build virtual network')
param buildVnetName string = 'vnet-build-${uniqueString(resourceGroup().id)}'

@description('The name of the Private DNS Resolver')
param privateDnsResolverName string = 'pdns-resolver-${uniqueString(resourceGroup().id)}'

@description('The name of the Azure Compute Gallery')
param computeGalleryName string = 'gallery${uniqueString(resourceGroup().id)}'

@description('The name of the VM Image Builder template')
param imageTemplateName string = 'template-ubuntu-${uniqueString(resourceGroup().id)}'

@description('The name of the managed identity for VM Image Builder')
param managedIdentityName string = 'id-image-builder-${uniqueString(resourceGroup().id)}'

@description('The address space for the hub virtual network')
param hubVnetAddressPrefix string = '10.0.0.0/16'

@description('The address space for the build virtual network')
param buildVnetAddressPrefix string = '10.1.0.0/16'

@description('The address prefix for the DNS resolver inbound subnet')
param resolverInboundSubnetPrefix string = '10.0.1.0/24'

@description('The address prefix for the DNS resolver outbound subnet')
param resolverOutboundSubnetPrefix string = '10.0.2.0/24'

@description('The address prefix for the build subnet')
param buildSubnetPrefix string = '10.1.1.0/24'

@description('The on-premises DNS server IP address for forwarding')
param onPremisesDnsServer string = '10.0.0.10'

@description('The on-premises domain name for DNS forwarding')
param onPremisesDomain string = 'corp.contoso.com'

@description('The VM size for the image builder')
param vmSize string = 'Standard_D2s_v3'

@description('The OS disk size in GB for the image builder')
param osDiskSizeGB int = 30

@description('The build timeout in minutes')
param buildTimeoutInMinutes int = 80

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'golden-image-pipeline'
  environment: 'production'
  solution: 'vm-image-builder'
}

// Variables for unique naming
var uniqueSuffix = uniqueString(resourceGroup().id)
var hubVnetNameUnique = '${hubVnetName}-${uniqueSuffix}'
var buildVnetNameUnique = '${buildVnetName}-${uniqueSuffix}'
var privateDnsResolverNameUnique = '${privateDnsResolverName}-${uniqueSuffix}'
var computeGalleryNameUnique = 'gallery${uniqueSuffix}'
var imageTemplateNameUnique = '${imageTemplateName}-${uniqueSuffix}'
var managedIdentityNameUnique = '${managedIdentityName}-${uniqueSuffix}'

// Hub Virtual Network with DNS Resolver subnets
resource hubVnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: hubVnetNameUnique
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubVnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'resolver-inbound-subnet'
        properties: {
          addressPrefix: resolverInboundSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.Network.dnsResolvers'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
        }
      }
      {
        name: 'resolver-outbound-subnet'
        properties: {
          addressPrefix: resolverOutboundSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.Network.dnsResolvers'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
        }
      }
    ]
  }
}

// Build Virtual Network
resource buildVnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: buildVnetNameUnique
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        buildVnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'build-subnet'
        properties: {
          addressPrefix: buildSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Virtual Network Peering from Build to Hub
resource buildToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-05-01' = {
  name: 'build-to-hub'
  parent: buildVnet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
  }
}

// Virtual Network Peering from Hub to Build
resource hubToBuildPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-05-01' = {
  name: 'hub-to-build'
  parent: hubVnet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: buildVnet.id
    }
  }
}

// Azure Private DNS Resolver
resource privateDnsResolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: privateDnsResolverNameUnique
  location: location
  tags: tags
  properties: {
    virtualNetwork: {
      id: hubVnet.id
    }
  }
}

// DNS Resolver Inbound Endpoint
resource inboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  name: 'inbound-endpoint'
  parent: privateDnsResolver
  location: location
  properties: {
    ipConfigurations: [
      {
        privateIpAllocationMethod: 'Dynamic'
        subnet: {
          id: '${hubVnet.id}/subnets/resolver-inbound-subnet'
        }
      }
    ]
  }
}

// DNS Resolver Outbound Endpoint
resource outboundEndpoint 'Microsoft.Network/dnsResolvers/outboundEndpoints@2022-07-01' = {
  name: 'outbound-endpoint'
  parent: privateDnsResolver
  location: location
  properties: {
    subnet: {
      id: '${hubVnet.id}/subnets/resolver-outbound-subnet'
    }
  }
}

// DNS Forwarding Ruleset
resource dnsForwardingRuleset 'Microsoft.Network/dnsForwardingRulesets@2022-07-01' = {
  name: 'corporate-ruleset'
  location: location
  tags: tags
  properties: {
    dnsResolverOutboundEndpoints: [
      {
        id: outboundEndpoint.id
      }
    ]
  }
}

// DNS Forwarding Rule for On-Premises Domain
resource dnsForwardingRule 'Microsoft.Network/dnsForwardingRulesets/forwardingRules@2022-07-01' = {
  name: 'on-premises-rule'
  parent: dnsForwardingRuleset
  properties: {
    domainName: onPremisesDomain
    forwardingRuleState: 'Enabled'
    targetDnsServers: [
      {
        ipAddress: onPremisesDnsServer
        port: 53
      }
    ]
  }
}

// Virtual Network Link for DNS Forwarding Ruleset
resource dnsForwardingRulesetVnetLink 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2022-07-01' = {
  name: 'build-vnet-link'
  parent: dnsForwardingRuleset
  properties: {
    virtualNetwork: {
      id: buildVnet.id
    }
  }
}

// Managed Identity for VM Image Builder
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityNameUnique
  location: location
  tags: tags
}

// Azure Compute Gallery
resource computeGallery 'Microsoft.Compute/galleries@2023-07-03' = {
  name: computeGalleryNameUnique
  location: location
  tags: tags
  properties: {
    description: 'Corporate Golden Image Gallery'
    identifier: {
      uniqueName: computeGalleryNameUnique
    }
  }
}

// Image Definition for Ubuntu Server
resource ubuntuImageDefinition 'Microsoft.Compute/galleries/images@2023-07-03' = {
  name: 'ubuntu-server-hardened'
  parent: computeGallery
  location: location
  tags: tags
  properties: {
    osType: 'Linux'
    osState: 'Generalized'
    identifier: {
      publisher: 'CorporateIT'
      offer: 'UbuntuServer'
      sku: '20.04-LTS-Hardened'
    }
    description: 'Corporate hardened Ubuntu 20.04 LTS server image'
    recommended: {
      vCPUs: {
        min: 2
        max: 8
      }
      memory: {
        min: 4
        max: 32
      }
    }
    hyperVGeneration: 'V2'
    features: [
      {
        name: 'SecurityType'
        value: 'TrustedLaunch'
      }
    ]
  }
}

// Role Assignment: Virtual Machine Contributor
resource vmContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'Virtual Machine Contributor')
  scope: resourceGroup()
  properties: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9980e02c-c2be-4d73-94e8-173b1dc7cf3c')
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment: Storage Account Contributor
resource storageContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'Storage Account Contributor')
  scope: resourceGroup()
  properties: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab')
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment: Network Contributor
resource networkContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'Network Contributor')
  scope: resourceGroup()
  properties: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7')
    principalType: 'ServicePrincipal'
  }
}

// Custom Role Definition for Compute Gallery Access
resource imageBuilderGalleryRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(resourceGroup().id, 'Image Builder Gallery Role')
  scope: resourceGroup()
  properties: {
    roleName: 'Image Builder Gallery Role'
    description: 'Custom role for VM Image Builder to access Compute Gallery'
    permissions: [
      {
        actions: [
          'Microsoft.Compute/galleries/read'
          'Microsoft.Compute/galleries/images/read'
          'Microsoft.Compute/galleries/images/versions/read'
          'Microsoft.Compute/galleries/images/versions/write'
          'Microsoft.Compute/images/read'
          'Microsoft.Compute/images/write'
          'Microsoft.Compute/images/delete'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
    assignableScopes: [
      resourceGroup().id
    ]
  }
}

// Role Assignment: Custom Image Builder Gallery Role
resource imageBuilderGalleryRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'Image Builder Gallery Role')
  scope: resourceGroup()
  properties: {
    principalId: managedIdentity.properties.principalId
    roleDefinitionId: imageBuilderGalleryRole.id
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    imageBuilderGalleryRole
  ]
}

// VM Image Builder Template
resource imageTemplate 'Microsoft.VirtualMachineImages/imageTemplates@2023-07-01' = {
  name: imageTemplateNameUnique
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    buildTimeoutInMinutes: buildTimeoutInMinutes
    vmProfile: {
      vmSize: vmSize
      osDiskSizeGB: osDiskSizeGB
      vnetConfig: {
        subnetId: '${buildVnet.id}/subnets/build-subnet'
      }
    }
    source: {
      type: 'PlatformImage'
      publisher: 'Canonical'
      offer: '0001-com-ubuntu-server-focal'
      sku: '20_04-lts-gen2'
      version: 'latest'
    }
    customize: [
      {
        type: 'Shell'
        name: 'UpdateSystem'
        inline: [
          'sudo apt-get update -y'
          'sudo apt-get upgrade -y'
          'sudo apt-get install -y curl wget unzip'
        ]
      }
      {
        type: 'Shell'
        name: 'InstallSecurity'
        inline: [
          'sudo apt-get install -y fail2ban ufw'
          'sudo ufw --force enable'
          'sudo systemctl enable fail2ban'
          'sudo systemctl start fail2ban'
        ]
      }
      {
        type: 'Shell'
        name: 'InstallMonitoring'
        inline: [
          'curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash'
          'wget -q https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb'
          'sudo dpkg -i packages-microsoft-prod.deb'
          'sudo apt-get update'
          'sudo apt-get install -y azure-cli'
        ]
      }
      {
        type: 'Shell'
        name: 'ConfigureCompliance'
        inline: [
          'sudo mkdir -p /etc/corporate'
          'echo "Golden Image Build Date: $(date)" | sudo tee /etc/corporate/build-info.txt'
          'sudo chmod 644 /etc/corporate/build-info.txt'
        ]
      }
    ]
    distribute: [
      {
        type: 'SharedImage'
        galleryImageId: ubuntuImageDefinition.id
        runOutputName: 'ubuntu-hardened-image'
        replicationRegions: [
          location
        ]
        storageAccountType: 'Standard_LRS'
      }
    ]
  }
  dependsOn: [
    vmContributorRoleAssignment
    storageContributorRoleAssignment
    networkContributorRoleAssignment
    imageBuilderGalleryRoleAssignment
    dnsForwardingRulesetVnetLink
  ]
}

// Outputs
output resourceGroupName string = resourceGroup().name
output hubVnetName string = hubVnet.name
output buildVnetName string = buildVnet.name
output privateDnsResolverName string = privateDnsResolver.name
output computeGalleryName string = computeGallery.name
output imageTemplateName string = imageTemplate.name
output managedIdentityName string = managedIdentity.name
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output managedIdentityResourceId string = managedIdentity.id
output inboundEndpointIpAddress string = inboundEndpoint.properties.ipConfigurations[0].privateIpAddress
output imageDefinitionResourceId string = ubuntuImageDefinition.id
output deploymentLocation string = location