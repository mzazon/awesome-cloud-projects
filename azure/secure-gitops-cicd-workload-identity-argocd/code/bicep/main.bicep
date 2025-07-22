@description('Main Bicep template for secure GitOps CI/CD with Azure Workload Identity and ArgoCD')

// ===== PARAMETERS =====
@description('Location for all resources')
param location string = resourceGroup().location

@description('Name prefix for all resources')
@minLength(3)
@maxLength(10)
param namePrefix string = 'gitops'

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Random suffix for globally unique resources')
@minLength(3)
@maxLength(6)
param randomSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('AKS cluster configuration')
param aksConfig object = {
  nodeCount: 3
  nodeSize: 'Standard_D2s_v3'
  kubernetesVersion: '1.28.3'
  enableAutoUpgrade: true
  enablePrivateCluster: false
}

@description('ArgoCD configuration')
param argoCDConfig object = {
  version: '0.0.7-preview'
  enableHighAvailability: false
  namespace: 'argocd'
}

@description('Key Vault configuration')
param keyVaultConfig object = {
  enableRbacAuthorization: true
  enableSoftDelete: true
  softDeleteRetentionInDays: 90
  enablePurgeProtection: false
}

@description('Sample secrets to store in Key Vault')
@secure()
param sampleSecrets object = {
  'database-connection-string': 'Server=myserver;Database=mydb;User=myuser;Password=mypass'
  'api-key': 'your-secure-api-key-here'
}

@description('Tags to apply to all resources')
param tags object = {
  Purpose: 'GitOps Demo'
  Environment: environment
  Project: 'Azure Workload Identity'
  ManagedBy: 'Bicep'
}

// ===== VARIABLES =====
var aksClusterName = '${namePrefix}-aks-${environment}'
var keyVaultName = '${namePrefix}kv${randomSuffix}'
var managedIdentityName = '${namePrefix}-mi-argocd-${environment}'
var logAnalyticsWorkspaceName = '${namePrefix}-law-${environment}'
var containerRegistryName = '${namePrefix}acr${randomSuffix}'

// ===== RESOURCES =====

// Log Analytics Workspace for AKS monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
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
  }
}

// Container Registry for storing container images
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    dataEndpointEnabled: false
    encryption: {
      status: 'disabled'
    }
    networkRuleBypassOptions: 'AzureServices'
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
  }
}

// User-assigned managed identity for ArgoCD workload identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// AKS Cluster with workload identity enabled
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: aksClusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: '${namePrefix}-aks-${environment}'
    kubernetesVersion: aksConfig.kubernetesVersion
    enableRBAC: true
    
    // Agent pool configuration
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: aksConfig.nodeCount
        vmSize: aksConfig.nodeSize
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        osType: 'Linux'
        osDiskSizeGB: 128
        osDiskType: 'Managed'
        enableAutoScaling: true
        minCount: 1
        maxCount: 5
        enableNodePublicIP: false
        maxPods: 110
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        upgradeSettings: {
          maxSurge: '1'
        }
      }
    ]
    
    // Network configuration
    networkProfile: {
      networkPlugin: 'kubenet'
      loadBalancerSku: 'Standard'
      outboundType: 'loadBalancer'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      dockerBridgeCidr: '172.17.0.1/16'
    }
    
    // Workload identity configuration
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    
    // Auto-upgrade configuration
    autoUpgradeProfile: {
      upgradeChannel: aksConfig.enableAutoUpgrade ? 'stable' : 'none'
    }
    
    // Monitoring configuration
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspace.id
        }
      }
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
    }
    
    // API server configuration
    apiServerAccessProfile: {
      enablePrivateCluster: aksConfig.enablePrivateCluster
    }
    
    // Disable local accounts (use Azure AD only)
    disableLocalAccounts: true
    
    // Azure AD integration
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      adminGroupObjectIDs: []
    }
  }
}

// Key Vault for storing application secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: keyVaultConfig.enableRbacAuthorization
    enableSoftDelete: keyVaultConfig.enableSoftDelete
    softDeleteRetentionInDays: keyVaultConfig.softDeleteRetentionInDays
    enablePurgeProtection: keyVaultConfig.enablePurgeProtection
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Store sample secrets in Key Vault
resource keyVaultSecrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [for (secretName, secretValue) in items(sampleSecrets): {
  name: secretName
  parent: keyVault
  properties: {
    value: secretValue
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
}]

// Role assignment: Key Vault Secrets User for managed identity
resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentity.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment: AcrPull for AKS to Container Registry
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, aksCluster.id, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

// ArgoCD extension for AKS
resource argoCDExtension 'Microsoft.KubernetesConfiguration/extensions@2023-05-01' = {
  name: 'argocd'
  scope: aksCluster
  properties: {
    extensionType: 'Microsoft.ArgoCD'
    autoUpgradeMinorVersion: false
    releaseTrain: 'preview'
    version: argoCDConfig.version
    configurationSettings: {
      'workloadIdentity.enable': 'true'
      'workloadIdentity.clientId': managedIdentity.properties.clientId
      'deployWithHighAvailability': string(argoCDConfig.enableHighAvailability)
      'namespaceInstall': 'false'
    }
  }
  dependsOn: [
    keyVaultSecretsUserRoleAssignment
  ]
}

// Federated identity credentials for ArgoCD service accounts
resource argoCDApplicationControllerFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: 'argocd-application-controller'
  parent: managedIdentity
  properties: {
    issuer: aksCluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${argoCDConfig.namespace}:argocd-application-controller'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
  dependsOn: [
    argoCDExtension
  ]
}

resource argoCDServerFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: 'argocd-server'
  parent: managedIdentity
  properties: {
    issuer: aksCluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${argoCDConfig.namespace}:argocd-server'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
  dependsOn: [
    argoCDExtension
  ]
}

// Federated identity credential for sample application
resource sampleAppFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: 'sample-app'
  parent: managedIdentity
  properties: {
    issuer: aksCluster.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:sample-app:sample-app-sa'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
  dependsOn: [
    argoCDExtension
  ]
}

// ===== OUTPUTS =====

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('AKS cluster name')
output aksClusterName string = aksCluster.name

@description('AKS cluster resource ID')
output aksClusterResourceId string = aksCluster.id

@description('AKS cluster FQDN')
output aksClusterFqdn string = aksCluster.properties.fqdn

@description('AKS OIDC issuer URL')
output aksOidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Key Vault resource ID')
output keyVaultResourceId string = keyVault.id

@description('Managed identity name')
output managedIdentityName string = managedIdentity.name

@description('Managed identity client ID')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Managed identity principal ID')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Container registry name')
output containerRegistryName string = containerRegistry.name

@description('Container registry login server')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('ArgoCD extension status')
output argoCDExtensionProvisioningState string = argoCDExtension.properties.provisioningState

@description('Commands to connect to AKS cluster')
output aksConnectCommand string = 'az aks get-credentials --resource-group ${resourceGroup().name} --name ${aksCluster.name} --overwrite-existing'

@description('Command to get ArgoCD admin password')
output argoCDPasswordCommand string = 'kubectl get secret argocd-initial-admin-secret -n ${argoCDConfig.namespace} -o jsonpath="{.data.password}" | base64 -d'

@description('Environment variables for additional configuration')
output environmentVariables object = {
  RESOURCE_GROUP: resourceGroup().name
  LOCATION: location
  CLUSTER_NAME: aksCluster.name
  KEY_VAULT_NAME: keyVault.name
  MANAGED_IDENTITY_NAME: managedIdentity.name
  USER_ASSIGNED_CLIENT_ID: managedIdentity.properties.clientId
  AKS_OIDC_ISSUER: aksCluster.properties.oidcIssuerProfile.issuerURL
  CONTAINER_REGISTRY_NAME: containerRegistry.name
  SUBSCRIPTION_ID: subscription().subscriptionId
}