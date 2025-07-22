// ============================================================================
// Bicep Template: Federated Container Storage Security with Azure Workload Identity and Container Storage
// Description: Complete infrastructure for workload identity and ephemeral storage in AKS
// Author: Generated from recipe template
// Version: 1.0
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('The location for all resources')
param location string = resourceGroup().location

@description('The name of the AKS cluster')
param aksClusterName string = 'aks-workload-identity-${uniqueString(resourceGroup().id)}'

@description('The name of the Key Vault')
param keyVaultName string = 'kv-workload-${uniqueString(resourceGroup().id)}'

@description('The name of the user-assigned managed identity')
param identityName string = 'workload-identity-${uniqueString(resourceGroup().id)}'

@description('The name of the storage account for backing storage')
param storageAccountName string = 'stworkload${uniqueString(resourceGroup().id)}'

@description('The Kubernetes version for the AKS cluster')
param kubernetesVersion string = '1.28.5'

@description('The node count for the AKS cluster')
@minValue(1)
@maxValue(100)
param nodeCount int = 3

@description('The VM size for the AKS nodes')
param nodeVmSize string = 'Standard_D2s_v3'

@description('The DNS prefix for the AKS cluster')
param dnsPrefix string = '${aksClusterName}-dns'

@description('The service account name for workload identity')
param serviceAccountName string = 'workload-identity-sa'

@description('The namespace for the workload identity demo')
param workloadNamespace string = 'workload-identity-demo'

@description('Enable Azure Container Storage extension')
param enableContainerStorage bool = true

@description('Storage pool disk size in GB')
@minValue(50)
@maxValue(1000)
param storagePoolDiskSize int = 100

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'workload-identity-demo'
  environment: 'demo'
  solution: 'ephemeral-workload-storage'
}

@description('Enable system-assigned managed identity for AKS')
param enableSystemAssignedIdentity bool = true

// ============================================================================
// VARIABLES
// ============================================================================

var federatedCredentialName = 'workload-identity-federation'
var extensionName = 'azure-container-storage'
var extensionNamespace = 'acstor'
var storageClassName = 'ephemeral-storage'
var storagePoolName = 'ephemeral-pool'

// ============================================================================
// EXISTING RESOURCES
// ============================================================================

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: resourceGroup().name
}

// ============================================================================
// USER-ASSIGNED MANAGED IDENTITY
// ============================================================================

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

// ============================================================================
// KEY VAULT
// ============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    accessPolicies: []
  }
}

// Key Vault secret for demonstration
resource storageEncryptionKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'storage-encryption-key'
  properties: {
    value: 'demo-encryption-key-value'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}

// ============================================================================
// RBAC ASSIGNMENTS
// ============================================================================

// Key Vault Secrets User role for the managed identity
resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, userAssignedIdentity.id, 'Key Vault Secrets User')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// STORAGE ACCOUNT
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// ============================================================================
// AKS CLUSTER
// ============================================================================

resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-10-01' = {
  name: aksClusterName
  location: location
  tags: tags
  identity: {
    type: enableSystemAssignedIdentity ? 'SystemAssigned' : 'None'
  }
  properties: {
    dnsPrefix: dnsPrefix
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    
    // Enable OIDC Issuer for Workload Identity
    oidcIssuerProfile: {
      enabled: true
    }
    
    // Enable Workload Identity
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    
    // Network profile
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      loadBalancerSku: 'standard'
    }
    
    // Agent pool profile
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: nodeCount
        vmSize: nodeVmSize
        osDiskSizeGB: 128
        osDiskType: 'Ephemeral'
        osType: 'Linux'
        mode: 'System'
        enableAutoScaling: true
        minCount: 1
        maxCount: 5
        enableNodePublicIP: false
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        upgradeSettings: {
          maxSurge: '10%'
        }
        nodeTaints: []
        tags: tags
      }
    ]
    
    // Addon profiles
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
    
    // Auto-scaler profile
    autoScalerProfile: {
      'scale-down-delay-after-add': '10m'
      'scale-down-unneeded-time': '10m'
      'scale-down-utilization-threshold': '0.5'
      'max-graceful-termination-sec': '600'
    }
    
    // API server access profile
    apiServerAccessProfile: {
      enablePrivateCluster: false
      authorizedIPRanges: []
    }
  }
}

// ============================================================================
// LOG ANALYTICS WORKSPACE
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${aksClusterName}-logs'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 5
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// CONTAINER STORAGE EXTENSION
// ============================================================================

resource containerStorageExtension 'Microsoft.KubernetesConfiguration/extensions@2023-05-01' = if (enableContainerStorage) {
  scope: aksCluster
  name: extensionName
  properties: {
    extensionType: 'microsoft.azurecontainerstorage'
    autoUpgradeMinorVersion: false
    releaseTrain: 'stable'
    scope: {
      cluster: {
        releaseNamespace: extensionNamespace
      }
    }
    configurationSettings: {
      'global.cli.install': 'true'
    }
    configurationProtectedSettings: {}
  }
}

// ============================================================================
// FEDERATED CREDENTIALS
// ============================================================================

resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: userAssignedIdentity
  name: federatedCredentialName
  properties: {
    audiences: [
      'api://AzureADTokenExchange'
    ]
    issuer: aksCluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${workloadNamespace}:${serviceAccountName}'
  }
}

// ============================================================================
// RBAC ROLE ASSIGNMENTS FOR AKS
// ============================================================================

// AKS Cluster Admin role for the current user (for kubectl access)
resource aksClusterAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: aksCluster
  name: guid(aksCluster.id, 'current-user', 'Azure Kubernetes Service Cluster Admin Role')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0ab0b1a8-8adf-4205-bc72-d9e90b0d3c8b') // Azure Kubernetes Service Cluster Admin Role
    principalId: 'REPLACE_WITH_CURRENT_USER_OBJECT_ID' // This should be replaced with actual user object ID
    principalType: 'User'
  }
}

// Storage Account Contributor role for AKS managed identity on storage account
resource storageContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, aksCluster.id, 'Storage Account Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab') // Storage Account Contributor
    principalId: aksCluster.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// DIAGNOSTIC SETTINGS
// ============================================================================

resource aksClusterDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: aksCluster
  name: 'default'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'kube-apiserver'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 7
        }
      }
      {
        category: 'kube-audit'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 7
        }
      }
      {
        category: 'kube-controller-manager'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 7
        }
      }
      {
        category: 'kube-scheduler'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 7
        }
      }
      {
        category: 'cluster-autoscaler'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 7
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 7
        }
      }
    ]
  }
}

resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: keyVault
  name: 'default'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 7
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 7
        }
      }
    ]
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('The name of the AKS cluster')
output aksClusterName string = aksCluster.name

@description('The resource ID of the AKS cluster')
output aksClusterResourceId string = aksCluster.id

@description('The OIDC issuer URL for the AKS cluster')
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL

@description('The FQDN of the AKS cluster')
output aksClusterFqdn string = aksCluster.properties.fqdn

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The URI of the Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The resource ID of the Key Vault')
output keyVaultResourceId string = keyVault.id

@description('The client ID of the user-assigned managed identity')
output identityClientId string = userAssignedIdentity.properties.clientId

@description('The resource ID of the user-assigned managed identity')
output identityResourceId string = userAssignedIdentity.id

@description('The principal ID of the user-assigned managed identity')
output identityPrincipalId string = userAssignedIdentity.properties.principalId

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the storage account')
output storageAccountResourceId string = storageAccount.id

@description('The primary endpoints of the storage account')
output storageAccountPrimaryEndpoints object = storageAccount.properties.primaryEndpoints

@description('The Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The federated credential name')
output federatedCredentialName string = federatedCredential.name

@description('The service account name for workload identity')
output serviceAccountName string = serviceAccountName

@description('The namespace for workload identity demo')
output workloadNamespace string = workloadNamespace

@description('The storage class name for ephemeral storage')
output storageClassName string = storageClassName

@description('The storage pool name')
output storagePoolName string = storagePoolName

@description('Container Storage extension name')
output containerStorageExtensionName string = enableContainerStorage ? containerStorageExtension.name : 'not-deployed'

@description('Deployment configuration for kubectl')
output kubernetesConfiguration object = {
  serviceAccount: {
    name: serviceAccountName
    namespace: workloadNamespace
    annotations: {
      'azure.workload.identity/client-id': userAssignedIdentity.properties.clientId
    }
    labels: {
      'azure.workload.identity/use': 'true'
    }
  }
  storageClass: {
    name: storageClassName
    provisioner: 'containerstorage.csi.azure.com'
    parameters: {
      protocol: 'nfs'
      storagePool: storagePoolName
      server: '${storagePoolName}.${extensionNamespace}.svc.cluster.local'
    }
    reclaimPolicy: 'Delete'
  }
  storagePool: {
    name: storagePoolName
    namespace: extensionNamespace
    diskType: 'temp'
    diskSize: '${storagePoolDiskSize}Gi'
    nodePoolName: 'nodepool1'
  }
}

@description('Commands to run after deployment')
output postDeploymentCommands array = [
  'az aks get-credentials --resource-group ${resourceGroup().name} --name ${aksCluster.name} --overwrite-existing'
  'kubectl create namespace ${workloadNamespace}'
  'kubectl apply -f kubernetes-manifests/'
  'kubectl get pods -n ${workloadNamespace}'
]

@description('Resource tags applied to all resources')
output resourceTags object = tags