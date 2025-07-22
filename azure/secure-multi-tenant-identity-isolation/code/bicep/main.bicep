// ==================================================
// Main Bicep Template for Multi-Tenant Customer Identity Isolation
// Recipe: Secure Multi-Tenant Identity Isolation with External ID
// ==================================================

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Unique suffix for globally unique resource names')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Name of the virtual network for private connectivity')
param vnetName string = 'vnet-private-isolation'

@description('Address prefix for the virtual network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for private endpoints subnet')
param privateEndpointsSubnetPrefix string = '10.0.1.0/24'

@description('Address prefix for API Management subnet')
param apimSubnetPrefix string = '10.0.2.0/24'

@description('API Management service name')
param apimName string = 'apim-tenant-isolation-${uniqueSuffix}'

@description('API Management publisher name')
param apimPublisherName string = 'Multi-Tenant SaaS Provider'

@description('API Management publisher email')
param apimPublisherEmail string = 'admin@example.com'

@description('API Management SKU')
@allowed(['Developer', 'Basic', 'Standard', 'Premium'])
param apimSku string = 'Developer'

@description('Key Vault name')
param keyVaultName string = 'kv-tenants-${uniqueSuffix}'

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string = 'law-tenant-isolation'

@description('Storage account name for diagnostics')
param storageAccountName string = 'stmtidentity${uniqueSuffix}'

@description('List of tenant identifiers for multi-tenant configuration')
param tenantIds array = ['tenant-a', 'tenant-b']

@description('Tags to apply to all resources')
param resourceTags object = {
  environment: environment
  purpose: 'multi-tenant-isolation'
  solution: 'azure-external-id-isolation'
}

// ==================================================
// Virtual Network and Subnets
// ==================================================

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-06-01' = {
  name: vnetName
  location: location
  tags: resourceTags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: privateEndpointsSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'api-management'
        properties: {
          addressPrefix: apimSubnetPrefix
          delegations: [
            {
              name: 'apimDelegation'
              properties: {
                serviceName: 'Microsoft.ApiManagement/service'
              }
            }
          ]
        }
      }
    ]
  }
}

// Reference to existing subnets for private endpoints
resource privateEndpointsSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-06-01' existing = {
  parent: virtualNetwork
  name: 'private-endpoints'
}

resource apiManagementSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-06-01' existing = {
  parent: virtualNetwork
  name: 'api-management'
}

// ==================================================
// Storage Account for Diagnostics
// ==================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
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
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: privateEndpointsSubnet.id
          action: 'Allow'
        }
      ]
    }
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// ==================================================
// Log Analytics Workspace
// ==================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 10
    }
  }
}

// ==================================================
// Key Vault with Advanced Security Configuration
// ==================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      family: 'A'
      name: 'premium'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: [
        {
          id: privateEndpointsSubnet.id
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
    publicNetworkAccess: 'Disabled'
  }
}

// Create tenant-specific secrets in Key Vault
resource tenantSecrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [for tenantId in tenantIds: {
  parent: keyVault
  name: '${tenantId}-api-key'
  properties: {
    value: 'secure-api-key-${tenantId}-${uniqueString(resourceGroup().id, tenantId)}'
    attributes: {
      enabled: true
    }
    contentType: 'API Key for ${tenantId} tenant'
  }
}]

// ==================================================
// API Management Service
// ==================================================

resource apiManagement 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: location
  tags: resourceTags
  sku: {
    name: apimSku
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherName: apimPublisherName
    publisherEmail: apimPublisherEmail
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: apiManagementSubnet.id
    }
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
    }
  }
}

// API Management tenant isolation policy
resource tenantIsolationPolicy 'Microsoft.ApiManagement/service/policies@2023-05-01-preview' = {
  parent: apiManagement
  name: 'policy'
  properties: {
    value: '''
    <policies>
        <inbound>
            <base />
            <!-- Extract tenant ID from JWT token or header -->
            <choose>
                <when condition="@(context.Request.Headers.ContainsKey("X-Tenant-ID"))">
                    <set-variable name="tenantId" value="@(context.Request.Headers["X-Tenant-ID"].First())" />
                </when>
                <otherwise>
                    <return-response>
                        <set-status code="400" reason="Bad Request" />
                        <set-body>Missing tenant identification</set-body>
                    </return-response>
                </otherwise>
            </choose>
            
            <!-- Validate tenant against allowed list -->
            <choose>
                <when condition="@(new string[] {"tenant-a", "tenant-b"}.Contains(context.Variables["tenantId"].ToString()))">
                    <!-- Set tenant-specific backend URL -->
                    <set-backend-service base-url="@($"https://api-{context.Variables["tenantId"]}.internal.com")" />
                </when>
                <otherwise>
                    <return-response>
                        <set-status code="403" reason="Forbidden" />
                        <set-body>Invalid tenant identifier</set-body>
                    </return-response>
                </otherwise>
            </choose>
            
            <!-- Add security headers for tenant isolation -->
            <set-header name="X-Isolated-Tenant" exists-action="override">
                <value>@(context.Variables["tenantId"].ToString())</value>
            </set-header>
        </inbound>
        <backend>
            <base />
        </backend>
        <outbound>
            <base />
            <!-- Remove sensitive tenant information from response -->
            <set-header name="X-Tenant-ID" exists-action="delete" />
        </outbound>
        <on-error>
            <base />
            <set-header name="X-Error-Source" exists-action="override">
                <value>Tenant-Isolation-Policy</value>
            </set-header>
        </on-error>
    </policies>
    '''
    format: 'xml'
  }
}

// ==================================================
// Private DNS Zones
// ==================================================

resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: resourceTags
}

resource apimPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azure-api.net'
  location: 'global'
  tags: resourceTags
}

// Link private DNS zones to virtual network
resource keyVaultDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: keyVaultPrivateDnsZone
  name: '${keyVaultPrivateDnsZone.name}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource apimDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: apimPrivateDnsZone
  name: '${apimPrivateDnsZone.name}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

// ==================================================
// Private Endpoints
// ==================================================

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-06-01' = {
  name: 'pe-keyvault'
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'keyvault-private-connection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: ['vault']
        }
      }
    ]
  }
}

resource apimPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-06-01' = {
  name: 'pe-apim-gateway'
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'apim-private-connection'
        properties: {
          privateLinkServiceId: apiManagement.id
          groupIds: ['gateway']
        }
      }
    ]
  }
}

// Private DNS Zone Groups for automatic DNS registration
resource keyVaultPrivateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-06-01' = {
  parent: keyVaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'keyvault-config'
        properties: {
          privateDnsZoneId: keyVaultPrivateDnsZone.id
        }
      }
    ]
  }
}

resource apimPrivateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-06-01' = {
  parent: apimPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'apim-config'
        properties: {
          privateDnsZoneId: apimPrivateDnsZone.id
        }
      }
    ]
  }
}

// ==================================================
// RBAC Assignments
// ==================================================

// Grant API Management managed identity access to Key Vault
resource apimKeyVaultSecretUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, apiManagement.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: apiManagement.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ==================================================
// Diagnostic Settings
// ==================================================

resource apimDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'apim-tenant-isolation-logs'
  scope: apiManagement
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'Gateway Requests'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

resource keyVaultDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'keyvault-audit-logs'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 90
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// ==================================================
// Azure Monitor Private Link Scope
// ==================================================

resource monitorPrivateLinkScope 'Microsoft.Insights/privateLinkScopes@2021-09-01' = {
  name: 'pls-arm-management'
  location: 'global'
  tags: resourceTags
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
  }
}

resource monitorPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-06-01' = {
  name: 'pe-arm-management'
  location: location
  tags: resourceTags
  properties: {
    subnet: {
      id: privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'arm-management-connection'
        properties: {
          privateLinkServiceId: monitorPrivateLinkScope.id
          groupIds: ['azuremonitor']
        }
      }
    ]
  }
}

// ==================================================
// Security and Monitoring Alerts
// ==================================================

resource tenantIsolationViolationAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'tenant-isolation-violation-alert'
  location: 'global'
  tags: resourceTags
  properties: {
    description: 'Alert when API Management returns 403 responses indicating potential tenant isolation violations'
    severity: 2
    enabled: true
    scopes: [apiManagement.id]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Forbidden responses'
          metricName: 'Requests'
          operator: 'GreaterThan'
          threshold: 1
          timeAggregation: 'Count'
          dimensions: [
            {
              name: 'GatewayResponseCodeCategory'
              operator: 'Include'
              values: ['4XX']
            }
          ]
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-tenant-isolation-alerts'
  location: 'global'
  tags: resourceTags
  properties: {
    groupShortName: 'TenantAlert'
    enabled: true
    emailReceivers: [
      {
        name: 'SecurityTeam'
        emailAddress: apimPublisherEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// ==================================================
// Outputs
// ==================================================

@description('The resource ID of the API Management service')
output apiManagementId string = apiManagement.id

@description('The resource ID of the Key Vault')
output keyVaultId string = keyVault.id

@description('The resource ID of the virtual network')
output virtualNetworkId string = virtualNetwork.id

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The gateway URL for API Management')
output apiManagementGatewayUrl string = 'https://${apiManagement.name}.azure-api.net'

@description('The Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Private endpoint IP addresses for verification')
output privateEndpointIPs object = {
  keyVault: keyVaultPrivateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]
  apiManagement: apimPrivateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]
}

@description('Tenant identifiers configured in the system')
output configuredTenants array = tenantIds

@description('Resource tags applied to all resources')
output appliedTags object = resourceTags

@description('Private DNS zone names for external DNS configuration')
output privateDnsZones array = [
  keyVaultPrivateDnsZone.name
  apimPrivateDnsZone.name
]