// =============================================================================
// Main Bicep template for Container Security Scanning with ACR and Defender
// =============================================================================

@description('The location where all resources will be deployed')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('The name of the Azure Container Registry')
param acrName string = 'acrsecurity${resourceSuffix}'

@description('The SKU of the Azure Container Registry')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string = 'Standard'

@description('The name of the Azure Kubernetes Service cluster')
param aksClusterName string = 'aks-security-${resourceSuffix}'

@description('The name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string = 'law-security-${resourceSuffix}'

@description('Whether to enable Microsoft Defender for Containers')
param enableDefenderForContainers bool = true

@description('Whether to enable content trust for the Container Registry')
param enableContentTrust bool = true

@description('Whether to enable admin user for the Container Registry')
param enableAdminUser bool = false

@description('Whether to enable public network access for the Container Registry')
param enablePublicNetworkAccess bool = true

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'security'
  environment: environment
  solution: 'container-security-scanning'
}

// =============================================================================
// Variables
// =============================================================================

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var logAnalyticsReaderRoleId = '73c42c96-874c-492b-b04d-ab87fe914c48'

// =============================================================================
// Resources
// =============================================================================

// Log Analytics Workspace for monitoring and diagnostics
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

// Azure Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: enableAdminUser
    publicNetworkAccess: enablePublicNetworkAccess ? 'Enabled' : 'Disabled'
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
    networkRuleSet: {
      defaultAction: 'Allow'
      ipRules: []
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Diagnostic Settings for Container Registry
resource acrDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'acr-security-logs'
  scope: containerRegistry
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Azure Kubernetes Service cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-10-01' = {
  name: aksClusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: '${aksClusterName}-dns'
    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: 2
        vmSize: 'Standard_D2s_v3'
        osDiskSizeGB: 128
        osDiskType: 'Managed'
        kubeletDiskType: 'OS'
        maxPods: 30
        type: 'VirtualMachineScaleSets'
        availabilityZones: []
        enableAutoScaling: true
        minCount: 1
        maxCount: 5
        mode: 'System'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        enableNodePublicIP: false
        enableEncryptionAtHost: false
        enableUltraSSD: false
        enableFIPS: false
      }
    ]
    linuxProfile: {
      adminUsername: 'azureuser'
      ssh: {
        publicKeys: [
          {
            keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7RqhCgWcqLGKxOjxlKWrOzEXKMSS2gJ1RYjWQXQgLNMHTqGYSPyxkrKqZEfIzJoGSNQJdqoB0cVzq6PdEmhVYyBmTk/DKVlPSzQA6gGvQRqTmKhbZPKZgHpTzqQ7+ZGgL9IlQ5dEqGsZjqBhO1GbzjqnQAHiSNBKJ1PGVbQnV0YgMbzP6UjvG5zWGmH1KOFCsLJQZqpWzWQOjbQzOHlQpZlYzSfVVZjjOQVVwKfzp5qwVHlQ3wvdGLgJnFj8lLt8kMgzZdCJZzjCYKuF8qjjLgZF8rKe8QdWjVlhQEZTdPtxEZDd4+qyBGJnPGQcbNzqrABz7PLgvLdOvJh7XhYCJYbQQJhvdH7bnFLhyFnNGPLXbzKr3nHvYlqJJAqyYhVgUgJqZbXhHmj9gQTLFMzcQ1+GVxXxL2+kLJXhvvwXKMCqUxCZlvQWqhZCvMYZEQ3oJ3I+oNXFN8cYOT3qGrZYqPjZVzRjKlNzjLH9TkfLmfBj/H2TZjWxfUo+SrQXFcj5kXnDGP8='
          }
        ]
      }
    }
    servicePrincipalProfile: {
      clientId: 'msi'
    }
    addonProfiles: {
      azureKeyvaultSecretsProvider: {
        enabled: false
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
    nodeResourceGroup: '${resourceGroup().name}-aks-nodes'
    enableRBAC: true
    networkProfile: {
      networkPlugin: 'kubenet'
      loadBalancerSku: 'Standard'
      outboundType: 'loadBalancer'
    }
    autoScalerProfile: {
      'balance-similar-node-groups': 'false'
      expander: 'random'
      'max-empty-bulk-delete': '10'
      'max-graceful-termination-sec': '600'
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
    securityProfile: {
      defender: {
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.id
        securityMonitoring: {
          enabled: enableDefenderForContainers
        }
      }
    }
  }
}

// Role assignment for AKS to pull images from ACR
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(containerRegistry.id, aksCluster.id, acrPullRoleId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

// Service Principal for Azure DevOps integration
resource devOpsServicePrincipal 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'sp-acr-devops-${resourceSuffix}'
  location: location
  tags: tags
}

// Role assignment for DevOps Service Principal to push to ACR
resource devOpsAcrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(containerRegistry.id, devOpsServicePrincipal.id, contributorRoleId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: devOpsServicePrincipal.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Action Group for security alerts
resource securityActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'security-alerts-${resourceSuffix}'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'SecAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'Security Team'
        emailAddress: 'security@company.com'
        useCommonAlertSchema: true
      }
    ]
  }
}

// Metric Alert for critical vulnerabilities
resource criticalVulnerabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'critical-vulnerability-alert'
  location: 'global'
  tags: tags
  properties: {
    description: 'Critical vulnerabilities detected in container images'
    severity: 1
    enabled: true
    scopes: [
      containerRegistry.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighSeverityVulnerabilities'
          metricName: 'HighSeverityVulnerabilities'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: securityActionGroup.id
      }
    ]
  }
}

// Policy Assignment for vulnerability resolution
resource vulnerabilityResolutionPolicy 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'require-vuln-resolution'
  scope: resourceGroup()
  properties: {
    displayName: 'Container images must have vulnerabilities resolved'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/090c7b07-b4ed-4561-ad20-e9075f3ccaff'
    parameters: {
      effect: {
        value: 'AuditIfNotExists'
      }
    }
    enforcementMode: 'Default'
  }
}

// Policy Assignment to disable anonymous pull
resource disableAnonymousPullPolicy 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'disable-anonymous-pull'
  scope: containerRegistry
  properties: {
    displayName: 'Disable anonymous pull on container registries'
    policyDefinitionId: '/providers/Microsoft.Authorization/policyDefinitions/9f2dea28-e834-476c-99c5-3507b4728395'
    parameters: {
      effect: {
        value: 'Deny'
      }
    }
    enforcementMode: 'Default'
  }
}

// Security Center Pricing for Containers (if enabled)
resource defenderForContainers 'Microsoft.Security/pricings@2023-01-01' = if (enableDefenderForContainers) {
  name: 'Containers'
  properties: {
    pricingTier: 'Standard'
    subPlan: 'P1'
  }
}

// Security Center Pricing for Container Registry (if enabled)
resource defenderForContainerRegistry 'Microsoft.Security/pricings@2023-01-01' = if (enableDefenderForContainers) {
  name: 'ContainerRegistry'
  properties: {
    pricingTier: 'Standard'
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('The name of the Azure Container Registry')
output containerRegistryName string = containerRegistry.name

@description('The login server of the Azure Container Registry')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('The resource ID of the Azure Container Registry')
output containerRegistryId string = containerRegistry.id

@description('The name of the Azure Kubernetes Service cluster')
output aksClusterName string = aksCluster.name

@description('The resource ID of the Azure Kubernetes Service cluster')
output aksClusterId string = aksCluster.id

@description('The FQDN of the Azure Kubernetes Service cluster')
output aksClusterFqdn string = aksCluster.properties.fqdn

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The workspace ID of the Log Analytics workspace')
output logAnalyticsWorkspaceCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('The client ID of the DevOps Service Principal')
output devOpsServicePrincipalClientId string = devOpsServicePrincipal.properties.clientId

@description('The principal ID of the DevOps Service Principal')
output devOpsServicePrincipalPrincipalId string = devOpsServicePrincipal.properties.principalId

@description('The resource ID of the DevOps Service Principal')
output devOpsServicePrincipalId string = devOpsServicePrincipal.id

@description('Commands to configure kubectl for the AKS cluster')
output kubectlConfigCommand string = 'az aks get-credentials --resource-group ${resourceGroup().name} --name ${aksCluster.name}'

@description('Commands to login to the Container Registry')
output acrLoginCommand string = 'az acr login --name ${containerRegistry.name}'

@description('Sample Docker commands for testing')
output sampleDockerCommands object = {
  build: 'docker build -t ${containerRegistry.properties.loginServer}/sample-app:v1 .'
  push: 'docker push ${containerRegistry.properties.loginServer}/sample-app:v1'
  pull: 'docker pull ${containerRegistry.properties.loginServer}/sample-app:v1'
}

@description('Security monitoring queries for Log Analytics')
output securityQueries object = {
  containerEvents: 'ContainerRegistryRepositoryEvents | where TimeGenerated > ago(1h) | order by TimeGenerated desc'
  loginEvents: 'ContainerRegistryLoginEvents | where TimeGenerated > ago(1h) | order by TimeGenerated desc'
  vulnerabilityFindings: 'SecurityRecommendation | where RecommendationDisplayName contains "vulnerabilities" | order by TimeGenerated desc'
}