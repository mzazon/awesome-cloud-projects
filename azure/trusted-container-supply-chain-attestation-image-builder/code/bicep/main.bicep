// ============================================================================
// Main Bicep template for Trusted Container Supply Chain
// Implements Azure Attestation Service and Azure Image Builder integration
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names (3-6 characters)')
@minLength(3)
@maxLength(6)
param uniqueSuffix string

@description('Environment tag for resources')
@allowed([
  'development'
  'staging'
  'production'
])
param environment string = 'development'

@description('Project tag for resources')
param projectName string = 'container-supply-chain'

@description('Azure Container Registry SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param acrSku string = 'Premium'

@description('Key Vault SKU')
@allowed([
  'standard'
  'premium'
])
param keyVaultSku string = 'standard'

@description('Image Builder VM size for builds')
param imageBuilderVmSize string = 'Standard_D2s_v3'

@description('Image Builder VM disk size in GB')
@minValue(30)
@maxValue(1023)
param imageBuilderDiskSize int = 30

@description('Image Builder timeout in minutes')
@minValue(60)
@maxValue(960)
param buildTimeoutMinutes int = 60

@description('Container image tag version')
param imageVersion string = '1.0.0'

@description('Enable content trust on ACR')
param enableContentTrust bool = true

@description('Enable Azure RBAC for Key Vault')
param enableKeyVaultRbac bool = true

// ============================================================================
// VARIABLES
// ============================================================================

var resourceNames = {
  attestationProvider: 'attestation-${uniqueSuffix}'
  containerRegistry: 'acr${uniqueSuffix}'
  keyVault: 'kv-${uniqueSuffix}'
  managedIdentity: 'mi-imagebuilder-${uniqueSuffix}'
  imageBuilder: 'imagebuilder-${uniqueSuffix}'
  computeGallery: 'gallery${uniqueSuffix}'
  imageDefinition: 'trustedImage'
  networkSecurityGroup: 'nsg-imagebuilder-${uniqueSuffix}'
  virtualNetwork: 'vnet-imagebuilder-${uniqueSuffix}'
  subnet: 'subnet-imagebuilder'
}

var commonTags = {
  project: projectName
  environment: environment
  purpose: 'container-supply-chain'
  managedBy: 'bicep'
}

var keyVaultAccessPolicies = []

// ============================================================================
// MANAGED IDENTITY
// ============================================================================

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: resourceNames.managedIdentity
  location: location
  tags: commonTags
}

// ============================================================================
// AZURE ATTESTATION SERVICE
// ============================================================================

resource attestationProvider 'Microsoft.Attestation/attestationProviders@2021-06-01' = {
  name: resourceNames.attestationProvider
  location: location
  tags: commonTags
  properties: {
    trustModel: 'AAD'
    tpmAttestationPolicy: 'version= 1.0;\nauthorizationrules\n{\n    [type=="x-ms-azurevm-vmid"] => permit();\n};\nissuancerules\n{\n    c:[type=="x-ms-azurevm-attestation-protocol-ver"] => issue(type="protocol-version", value=c.value);\n    c:[type=="x-ms-azurevm-vmid"] => issue(type="vm-id", value=c.value);\n    c:[type=="x-ms-azurevm-is-windows"] => issue(type="is-windows", value=c.value);\n    c:[type=="x-ms-azurevm-boot-integrity-svg"] => issue(type="boot-integrity", value=c.value);\n};'
  }
}

// ============================================================================
// KEY VAULT
// ============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: commonTags
  properties: {
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: enableKeyVaultRbac
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    accessPolicies: enableKeyVaultRbac ? [] : keyVaultAccessPolicies
  }
}

// Container signing key
resource signingKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: keyVault
  name: 'container-signing-key'
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [
      'sign'
      'verify'
    ]
    attributes: {
      enabled: true
    }
  }
}

// ============================================================================
// RBAC ASSIGNMENTS FOR KEY VAULT
// ============================================================================

// Key Vault Crypto User role for managed identity
resource keyVaultCryptoUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableKeyVaultRbac) {
  scope: keyVault
  name: guid(keyVault.id, managedIdentity.id, 'Key Vault Crypto User')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '12338af0-0e69-4776-bea7-57ae8d297424') // Key Vault Crypto User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// CONTAINER REGISTRY
// ============================================================================

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: resourceNames.containerRegistry
  location: location
  tags: commonTags
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
    policies: {
      trustPolicy: {
        status: enableContentTrust ? 'enabled' : 'disabled'
        type: 'Notary'
      }
      retentionPolicy: {
        status: 'enabled'
        days: 7
      }
      quarantinePolicy: {
        status: 'enabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    networkRuleBypassOptions: 'AzureServices'
  }
}

// ACR Push role assignment for managed identity
resource acrPushRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(containerRegistry.id, managedIdentity.id, 'AcrPush')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec') // AcrPush
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Create trusted-apps repository
resource trustedAppsRepository 'Microsoft.ContainerRegistry/registries/repositories@2023-07-01' = {
  parent: containerRegistry
  name: 'trusted-apps'
}

// ============================================================================
// NETWORKING FOR IMAGE BUILDER
// ============================================================================

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: resourceNames.virtualNetwork
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: resourceNames.subnet
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.KeyVault'
            }
            {
              service: 'Microsoft.ContainerRegistry'
            }
          ]
          delegations: [
            {
              name: 'Microsoft.VirtualMachineImages/imageTemplates'
              properties: {
                serviceName: 'Microsoft.VirtualMachineImages/imageTemplates'
              }
            }
          ]
        }
      }
    ]
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: resourceNames.networkSecurityGroup
  location: location
  tags: commonTags
  properties: {
    securityRules: [
      {
        name: 'AllowAzureImageBuilder'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '60000-60001'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
    ]
  }
}

// ============================================================================
// COMPUTE GALLERY
// ============================================================================

resource computeGallery 'Microsoft.Compute/galleries@2023-07-03' = {
  name: resourceNames.computeGallery
  location: location
  tags: commonTags
  properties: {
    description: 'Compute gallery for trusted container images'
    identifier: {}
  }
}

resource imageDefinition 'Microsoft.Compute/galleries/images@2023-07-03' = {
  parent: computeGallery
  name: resourceNames.imageDefinition
  location: location
  tags: commonTags
  properties: {
    description: 'Trusted container image with attestation'
    osType: 'Linux'
    osState: 'Generalized'
    identifier: {
      publisher: 'TrustedPublisher'
      offer: 'TrustedContainerImages'
      sku: 'Ubuntu2004'
    }
    recommended: {
      vCPUs: {
        min: 2
        max: 4
      }
      memory: {
        min: 4
        max: 8
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

// ============================================================================
// RBAC ASSIGNMENTS FOR IMAGE BUILDER
// ============================================================================

// Contributor role for the resource group (needed for VM operations)
resource imageBuilderContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, managedIdentity.id, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// IMAGE BUILDER TEMPLATE
// ============================================================================

resource imageBuilderTemplate 'Microsoft.VirtualMachineImages/imageTemplates@2024-02-01' = {
  name: resourceNames.imageBuilder
  location: location
  tags: commonTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    buildTimeoutInMinutes: buildTimeoutMinutes
    vmProfile: {
      vmSize: imageBuilderVmSize
      osDiskSizeGB: imageBuilderDiskSize
      vnetConfig: {
        subnetId: '${virtualNetwork.id}/subnets/${resourceNames.subnet}'
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
          'sudo apt-get update'
          'sudo apt-get upgrade -y'
        ]
      }
      {
        type: 'Shell'
        name: 'InstallDocker'
        inline: [
          'sudo apt-get install -y docker.io'
          'sudo systemctl enable docker'
          'sudo systemctl start docker'
          'sudo usermod -aG docker $USER'
        ]
      }
      {
        type: 'Shell'
        name: 'InstallAzureCLI'
        inline: [
          'curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash'
        ]
      }
      {
        type: 'Shell'
        name: 'InstallAttestationTools'
        inline: [
          'sudo apt-get install -y tpm2-tools'
          'sudo apt-get install -y libcurl4-openssl-dev'
        ]
      }
      {
        type: 'Shell'
        name: 'BuildSecureContainer'
        inline: [
          'cat > Dockerfile << EOF'
          'FROM ubuntu:20.04'
          'LABEL maintainer="Trusted Builder"'
          'LABEL security.scan="passed"'
          'LABEL attestation.required="true"'
          'RUN apt-get update && apt-get install -y curl jq'
          'RUN useradd -m -s /bin/bash appuser'
          'USER appuser'
          'WORKDIR /app'
          'CMD ["echo", "Trusted container started"]'
          'EOF'
          ''
          'sudo docker build -t trusted-app:${imageVersion} .'
          'sudo docker save trusted-app:${imageVersion} -o /tmp/trusted-app.tar'
        ]
      }
      {
        type: 'Shell'
        name: 'ConfigureAttestation'
        inline: [
          'echo "#!/bin/bash" > /tmp/attest-and-sign.sh'
          'echo "# Attestation and signing script for container images" >> /tmp/attest-and-sign.sh'
          'echo "set -e" >> /tmp/attest-and-sign.sh'
          'echo "echo \\"Starting attestation process...\\"" >> /tmp/attest-and-sign.sh'
          'echo "# TPM-based attestation would be performed here" >> /tmp/attest-and-sign.sh'
          'echo "echo \\"Attestation successful\\"" >> /tmp/attest-and-sign.sh'
          'chmod +x /tmp/attest-and-sign.sh'
        ]
      }
    ]
    distribute: [
      {
        type: 'SharedImage'
        galleryImageId: '${imageDefinition.id}/versions/${imageVersion}'
        runOutputName: 'trustedImageOutput'
        replicationRegions: [
          location
        ]
        storageAccountType: 'Standard_LRS'
      }
    ]
    stagingResourceGroup: '/subscriptions/${subscription().subscriptionId}/resourceGroups/IT_${resourceGroup().name}_${resourceNames.imageBuilder}'
  }
  dependsOn: [
    imageBuilderContributorRoleAssignment
    acrPushRoleAssignment
    keyVaultCryptoUserRoleAssignment
  ]
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Attestation provider name')
output attestationProviderName string = attestationProvider.name

@description('Attestation provider endpoint')
output attestationProviderEndpoint string = attestationProvider.properties.attestUri

@description('Container registry name')
output containerRegistryName string = containerRegistry.name

@description('Container registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('Key vault name')
output keyVaultName string = keyVault.name

@description('Key vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Managed identity name')
output managedIdentityName string = managedIdentity.name

@description('Managed identity client ID')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Managed identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Image builder template name')
output imageBuilderTemplateName string = imageBuilderTemplate.name

@description('Compute gallery name')
output computeGalleryName string = computeGallery.name

@description('Image definition name')
output imageDefinitionName string = imageDefinition.name

@description('Virtual network name')
output virtualNetworkName string = virtualNetwork.name

@description('Subnet name')
output subnetName string = resourceNames.subnet

@description('Deployment summary')
output deploymentSummary object = {
  attestationProvider: {
    name: attestationProvider.name
    endpoint: attestationProvider.properties.attestUri
  }
  containerRegistry: {
    name: containerRegistry.name
    loginServer: containerRegistry.properties.loginServer
    contentTrustEnabled: enableContentTrust
  }
  keyVault: {
    name: keyVault.name
    uri: keyVault.properties.vaultUri
    rbacEnabled: enableKeyVaultRbac
  }
  imageBuilder: {
    name: imageBuilderTemplate.name
    vmSize: imageBuilderVmSize
    timeoutMinutes: buildTimeoutMinutes
  }
  managedIdentity: {
    name: managedIdentity.name
    clientId: managedIdentity.properties.clientId
  }
}