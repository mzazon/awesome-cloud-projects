@description('Main Bicep template for Defense-in-Depth API Security with Azure API Management and Web Application Firewall')

// Parameters
@description('The Azure region for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('API Management publisher email')
param publisherEmail string

@description('API Management publisher name')
param publisherName string = 'Zero Trust API Security'

@description('API Management SKU')
@allowed(['Developer', 'Standard', 'Premium'])
param apimSku string = 'Standard'

@description('Application Gateway capacity (instance count)')
@minValue(1)
@maxValue(10)
param applicationGatewayCapacity int = 2

@description('Log Analytics workspace retention days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('Enable diagnostic logging')
param enableDiagnostics bool = true

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'zero-trust-api-security'
  Recipe: 'orchestrating-zero-trust-api-security'
}

// Variables
var resourceNames = {
  vnet: 'vnet-zerotrust-${uniqueSuffix}'
  apim: 'apim-zerotrust-${uniqueSuffix}'
  applicationGateway: 'agw-zerotrust-${uniqueSuffix}'
  publicIp: 'pip-agw-${uniqueSuffix}'
  wafPolicy: 'waf-zerotrust-${uniqueSuffix}'
  logWorkspace: 'log-zerotrust-${uniqueSuffix}'
  appInsights: 'ai-zerotrust-${uniqueSuffix}'
  privateEndpoint: 'pe-backend-${uniqueSuffix}'
  privateDnsZone: 'privatelink.azure-api.net'
  nsg: 'nsg-zerotrust-${uniqueSuffix}'
}

var networkConfig = {
  vnetAddressPrefix: '10.0.0.0/16'
  agwSubnetPrefix: '10.0.1.0/24'
  apimSubnetPrefix: '10.0.2.0/24'
  privateEndpointSubnetPrefix: '10.0.3.0/24'
}

var subnets = [
  {
    name: 'agw-subnet'
    addressPrefix: networkConfig.agwSubnetPrefix
    delegations: []
    serviceEndpoints: []
    networkSecurityGroup: true
  }
  {
    name: 'apim-subnet'
    addressPrefix: networkConfig.apimSubnetPrefix
    delegations: [
      {
        name: 'Microsoft.ApiManagement/service'
        properties: {
          serviceName: 'Microsoft.ApiManagement/service'
        }
      }
    ]
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
      }
      {
        service: 'Microsoft.Sql'
      }
      {
        service: 'Microsoft.EventHub'
      }
    ]
    networkSecurityGroup: true
  }
  {
    name: 'pe-subnet'
    addressPrefix: networkConfig.privateEndpointSubnetPrefix
    delegations: []
    serviceEndpoints: []
    networkSecurityGroup: true
  }
]

// Network Security Group
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: resourceNames.nsg
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowAPIManagementInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3443'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowApplicationGatewayInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['65200-65535']
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHTTPSInbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['80', '443']
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4000
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Virtual Network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: resourceNames.vnet
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [networkConfig.vnetAddressPrefix]
    }
    subnets: [for subnet in subnets: {
      name: subnet.name
      properties: {
        addressPrefix: subnet.addressPrefix
        delegations: subnet.delegations
        serviceEndpoints: subnet.serviceEndpoints
        networkSecurityGroup: subnet.networkSecurityGroup ? {
          id: networkSecurityGroup.id
        } : null
        privateEndpointNetworkPolicies: 'Disabled'
        privateLinkServiceNetworkPolicies: 'Enabled'
      }
    }]
  }
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logWorkspace
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
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

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.appInsights
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Public IP for Application Gateway
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: resourceNames.publicIp
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: '${resourceNames.applicationGateway}-${uniqueSuffix}'
    }
  }
}

// WAF Policy
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-09-01' = {
  name: resourceNames.wafPolicy
  location: location
  tags: tags
  properties: {
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: 'Prevention'
      requestBodyInspectLimitInKB: 128
      requestBodyEnforcement: true
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
          ruleGroupOverrides: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '0.1'
          ruleGroupOverrides: []
        }
      ]
      exclusions: []
    }
    customRules: [
      {
        name: 'RateLimitRule'
        priority: 100
        ruleType: 'RateLimitRule'
        rateLimitDuration: 'OneMin'
        rateLimitThreshold: 100
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            operator: 'IPMatch'
            negationConditon: false
            matchValues: [
              '0.0.0.0/0'
            ]
          }
        ]
        action: 'Block'
      }
      {
        name: 'BlockMaliciousUserAgents'
        priority: 200
        ruleType: 'MatchRule'
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'RequestHeaders'
                selector: 'User-Agent'
              }
            ]
            operator: 'Contains'
            negationConditon: false
            matchValues: [
              'sqlmap'
              'nikto'
              'scanner'
              'bot'
              'crawler'
            ]
            transforms: [
              'Lowercase'
            ]
          }
        ]
        action: 'Block'
      }
    ]
  }
}

// API Management Service
resource apiManagement 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: resourceNames.apim
  location: location
  tags: tags
  sku: {
    name: apimSku
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: '${virtualNetwork.id}/subnets/apim-subnet'
    }
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Protocols.Server.Http2': 'True'
    }
    disableGateway: false
    natGatewayState: 'Disabled'
  }
}

// Application Insights Logger for API Management
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2023-05-01-preview' = {
  name: 'appInsights'
  parent: apiManagement
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights Logger for Zero Trust API Security'
    credentials: {
      instrumentationKey: applicationInsights.properties.InstrumentationKey
    }
    isBuffered: true
  }
}

// API Management Diagnostic Settings
resource apimDiagnostic 'Microsoft.ApiManagement/service/diagnostics@2023-05-01-preview' = {
  name: 'applicationinsights'
  parent: apiManagement
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
    logClientIp: true
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        headers: ['Authorization', 'User-Agent', 'X-Forwarded-For']
        body: {
          bytes: 1024
        }
      }
      response: {
        headers: ['Content-Type', 'Set-Cookie']
        body: {
          bytes: 1024
        }
      }
    }
    backend: {
      request: {
        headers: ['Authorization', 'User-Agent']
        body: {
          bytes: 1024
        }
      }
      response: {
        headers: ['Content-Type']
        body: {
          bytes: 1024
        }
      }
    }
  }
}

// Sample Secure API
resource sampleApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  name: 'sample-secure-api'
  parent: apiManagement
  properties: {
    displayName: 'Sample Secure API'
    description: 'A sample API demonstrating zero-trust security policies'
    serviceUrl: 'https://httpbin.org'
    path: '/secure'
    protocols: ['https']
    subscriptionRequired: true
    format: 'openapi+json'
    value: loadTextContent('../../openapi-spec.json')
  }
}

// Sample API Operation
resource sampleApiOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  name: 'get-secure-data'
  parent: sampleApi
  properties: {
    displayName: 'Get Secure Data'
    method: 'GET'
    urlTemplate: '/data'
    description: 'Retrieve secure data with zero-trust validation'
    request: {
      queryParameters: []
      headers: [
        {
          name: 'Authorization'
          description: 'Bearer token for authentication'
          type: 'string'
          required: true
        }
      ]
      representations: []
    }
    responses: [
      {
        statusCode: 200
        description: 'Success'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
      {
        statusCode: 401
        description: 'Unauthorized'
      }
      {
        statusCode: 429
        description: 'Too Many Requests'
      }
    ]
  }
}

// API Security Policy
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  name: 'policy'
  parent: sampleApi
  properties: {
    value: loadTextContent('../../security-policy.xml')
    format: 'xml'
  }
}

// Application Gateway
resource applicationGateway 'Microsoft.Network/applicationGateways@2023-09-01' = {
  name: resourceNames.applicationGateway
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: applicationGatewayCapacity
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: '${virtualNetwork.id}/subnets/agw-subnet'
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
      {
        name: 'port_443'
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'apimBackendPool'
        properties: {
          backendAddresses: [
            {
              fqdn: replace(replace(apiManagement.properties.gatewayUrl, 'https://', ''), 'http://', '')
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'apimBackendHttpSettings'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 30
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', resourceNames.applicationGateway, 'apimHealthProbe')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'appGatewayHttpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', resourceNames.applicationGateway, 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', resourceNames.applicationGateway, 'port_80')
          }
          protocol: 'Http'
          requireServerNameIndication: false
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'apimRoutingRule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', resourceNames.applicationGateway, 'appGatewayHttpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', resourceNames.applicationGateway, 'apimBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', resourceNames.applicationGateway, 'apimBackendHttpSettings')
          }
        }
      }
    ]
    probes: [
      {
        name: 'apimHealthProbe'
        properties: {
          protocol: 'Https'
          path: '/status-0123456789abcdef'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {
            statusCodes: ['200-399']
          }
        }
      }
    ]
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Prevention'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
      disabledRuleGroups: []
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    }
    firewallPolicy: {
      id: wafPolicy.id
    }
    enableHttp2: true
    autoscaleConfiguration: {
      minCapacity: 1
      maxCapacity: 5
    }
  }
}

// Private DNS Zone
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: resourceNames.privateDnsZone
  location: 'global'
  tags: tags
  properties: {}
}

// Private DNS Zone Virtual Network Link
resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: 'dns-link'
  parent: privateDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

// Private Endpoint for API Management
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: resourceNames.privateEndpoint
  location: location
  tags: tags
  properties: {
    subnet: {
      id: '${virtualNetwork.id}/subnets/pe-subnet'
    }
    privateLinkServiceConnections: [
      {
        name: 'apim-connection'
        properties: {
          privateLinkServiceId: apiManagement.id
          groupIds: ['gateway']
          requestMessage: 'Private endpoint connection for API Management'
        }
      }
    ]
  }
}

// Private DNS Zone Group
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  name: 'default'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azure-api-net'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// Diagnostic Settings for Application Gateway
resource agwDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'agw-diagnostics'
  scope: applicationGateway
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// Diagnostic Settings for API Management
resource apimDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'apim-diagnostics'
  scope: apiManagement
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// Outputs
@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Virtual Network ID')
output virtualNetworkId string = virtualNetwork.id

@description('API Management Service Name')
output apiManagementName string = apiManagement.name

@description('API Management Gateway URL')
output apiManagementGatewayUrl string = apiManagement.properties.gatewayUrl

@description('Application Gateway Public IP Address')
output applicationGatewayPublicIp string = publicIp.properties.ipAddress

@description('Application Gateway FQDN')
output applicationGatewayFqdn string = publicIp.properties.dnsSettings.fqdn

@description('WAF Policy ID')
output wafPolicyId string = wafPolicy.id

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Application Insights Instrumentation Key')
@secure()
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights Connection String')
@secure()
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Private Endpoint ID')
output privateEndpointId string = privateEndpoint.id

@description('Private DNS Zone Name')
output privateDnsZoneName string = privateDnsZone.name

@description('Sample API URL')
output sampleApiUrl string = 'https://${publicIp.properties.dnsSettings.fqdn}/secure/data'

@description('API Management Portal URL')
output apiManagementPortalUrl string = apiManagement.properties.portalUrl

@description('Network Security Group ID')
output networkSecurityGroupId string = networkSecurityGroup.id