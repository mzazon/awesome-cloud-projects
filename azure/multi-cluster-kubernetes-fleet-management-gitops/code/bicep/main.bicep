@description('The name of the resource group where all resources will be deployed')
param resourceGroupName string = 'rg-fleet-demo'

@description('The primary location for the Fleet Manager and first AKS cluster')
param primaryLocation string = 'eastus'

@description('Additional regions for AKS clusters')
param additionalRegions array = [
  'westus2'
  'centralus'
]

@description('The name of the Azure Kubernetes Fleet Manager')
param fleetName string = 'multicluster-fleet'

@description('The name prefix for AKS clusters')
param aksClusterNamePrefix string = 'aks-fleet'

@description('The node count for each AKS cluster')
@minValue(1)
@maxValue(10)
param nodeCount int = 2

@description('The VM size for AKS nodes')
param nodeVmSize string = 'Standard_DS2_v2'

@description('The Kubernetes version for AKS clusters')
param kubernetesVersion string = '1.28.5'

@description('The name of the Azure Container Registry')
param acrName string = 'acrfleet${uniqueString(resourceGroup().id)}'

@description('The name of the Azure Key Vault')
param keyVaultName string = 'kv-fleet-${uniqueString(resourceGroup().id)}'

@description('The Azure AD tenant ID')
param tenantId string = tenant().tenantId

@description('The subscription ID')
param subscriptionId string = subscription().subscriptionId

@description('Tags to be applied to all resources')
param tags object = {
  purpose: 'fleet-demo'
  environment: 'demo'
  'recipe-name': 'orchestrating-multi-cluster-kubernetes-deployments'
}

@description('Enable Azure Service Operator installation')
param enableAzureServiceOperator bool = true

@description('Service Principal Client ID for Azure Service Operator')
@secure()
param asoClientId string = ''

@description('Service Principal Client Secret for Azure Service Operator')
@secure()
param asoClientSecret string = ''

// Variables
var allRegions = concat([primaryLocation], additionalRegions)
var totalClusters = length(allRegions)

// Resource Group (if not existing)
resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: primaryLocation
  tags: tags
}

// Azure Kubernetes Fleet Manager
resource fleetManager 'Microsoft.ContainerService/fleets@2023-10-15' = {
  name: fleetName
  location: primaryLocation
  tags: tags
  properties: {
    hubProfile: {
      dnsPrefix: '${fleetName}-hub'
    }
  }
}

// Managed Identity for AKS clusters
resource aksIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = [for i in range(0, totalClusters): {
  name: '${aksClusterNamePrefix}-${i + 1}-identity'
  location: allRegions[i]
  tags: tags
}]

// AKS Clusters in different regions
resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-10-01' = [for i in range(0, totalClusters): {
  name: '${aksClusterNamePrefix}-${i + 1}'
  location: allRegions[i]
  tags: union(tags, {
    region: allRegions[i]
    'cluster-index': string(i + 1)
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksIdentity[i].id}': {}
    }
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: '${aksClusterNamePrefix}-${i + 1}'
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        mode: 'System'
        enableAutoScaling: true
        minCount: 1
        maxCount: 5
        type: 'VirtualMachineScaleSets'
        availabilityZones: []
        enableNodePublicIP: false
        tags: tags
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }
    addonProfiles: {
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
      azurepolicy: {
        enabled: true
      }
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspace.id
        }
      }
    }
    autoScalerProfile: {
      'balance-similar-node-groups': 'false'
      expander: 'random'
      'max-empty-bulk-delete': '10'
      'max-graceful-termination-sec': '600'
      'max-node-provision-time': '15m'
      'max-total-unready-percentage': '45'
      'new-pod-scale-up-delay': '0s'
      'ok-total-unready-count': '3'
      'scale-down-delay-after-add': '10m'
      'scale-down-delay-after-delete': '10s'
      'scale-down-delay-after-failure': '3m'
      'scale-down-unneeded-time': '10m'
      'scale-down-utilization-threshold': '0.5'
      'scan-interval': '10s'
      'skip-nodes-with-local-storage': 'false'
      'skip-nodes-with-system-pods': 'true'
    }
    servicePrincipalProfile: {
      clientId: 'msi'
    }
    enableRBAC: true
    disableLocalAccounts: false
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
      imageCleaner: {
        enabled: true
        intervalHours: 24
      }
    }
    storageProfile: {
      diskCSIDriver: {
        enabled: true
      }
      fileCSIDriver: {
        enabled: true
      }
      snapshotController: {
        enabled: true
      }
    }
    workloadAutoScalerProfile: {
      keda: {
        enabled: true
      }
      verticalPodAutoscaler: {
        enabled: true
      }
    }
  }
}]

// Fleet Members - Join AKS clusters to Fleet Manager
resource fleetMember 'Microsoft.ContainerService/fleets/members@2023-10-15' = [for i in range(0, totalClusters): {
  parent: fleetManager
  name: 'member-${i + 1}'
  properties: {
    clusterResourceId: aksCluster[i].id
  }
}]

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'law-fleet-${uniqueString(resourceGroup().id)}'
  location: primaryLocation
  tags: tags
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

// Azure Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: primaryLocation
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    adminUserEnabled: false
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    zoneRedundancy: 'Disabled'
  }
}

// Key Vault for secrets management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: primaryLocation
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    accessPolicies: []
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Storage Accounts for regional applications
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = [for i in range(0, totalClusters): {
  name: 'stfleet${uniqueString(resourceGroup().id)}${i}'
  location: allRegions[i]
  tags: union(tags, {
    region: allRegions[i]
    'cluster-index': string(i + 1)
  })
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}]

// Role assignments for AKS clusters to access ACR
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for i in range(0, totalClusters): {
  name: guid(containerRegistry.id, aksIdentity[i].id, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: aksIdentity[i].properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

// Role assignments for AKS clusters to access Key Vault
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for i in range(0, totalClusters): {
  name: guid(keyVault.id, aksIdentity[i].id, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: aksIdentity[i].properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

// Service Principal for Azure Service Operator (if enabled)
resource asoServicePrincipal 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableAzureServiceOperator && !empty(asoClientId)) {
  name: guid(resourceGroup.id, asoClientId, 'Contributor')
  scope: resourceGroup
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: asoClientId
    principalType: 'ServicePrincipal'
  }
}

// Fleet Update Strategy (example for coordinated updates)
resource fleetUpdateStrategy 'Microsoft.ContainerService/fleets/updatestrategies@2023-10-15' = {
  parent: fleetManager
  name: 'coordinated-upgrade'
  properties: {
    strategy: {
      stages: [
        {
          name: 'stage1'
          groups: [
            {
              name: 'test-group'
            }
          ]
          afterStageWaitInSeconds: 3600
        }
        {
          name: 'stage2'
          groups: [
            {
              name: 'prod-group'
            }
          ]
        }
      ]
    }
  }
}

// Outputs
output fleetManagerName string = fleetManager.name
output fleetManagerId string = fleetManager.id
output fleetManagerFqdn string = fleetManager.properties.fqdn

output aksClusterNames array = [for i in range(0, totalClusters): aksCluster[i].name]
output aksClusterIds array = [for i in range(0, totalClusters): aksCluster[i].id]
output aksClusterFqdns array = [for i in range(0, totalClusters): aksCluster[i].properties.fqdn]

output containerRegistryName string = containerRegistry.name
output containerRegistryId string = containerRegistry.id
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri

output storageAccountNames array = [for i in range(0, totalClusters): storageAccount[i].name]
output storageAccountIds array = [for i in range(0, totalClusters): storageAccount[i].id]

output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

output aksIdentityIds array = [for i in range(0, totalClusters): aksIdentity[i].id]
output aksIdentityClientIds array = [for i in range(0, totalClusters): aksIdentity[i].properties.clientId]

output deploymentRegions array = allRegions
output resourceGroupName string = resourceGroup.name
output subscriptionId string = subscriptionId
output tenantId string = tenantId