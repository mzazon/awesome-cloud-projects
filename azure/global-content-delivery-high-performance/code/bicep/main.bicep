@description('The primary Azure region for deployment')
param primaryLocation string = 'eastus'

@description('The secondary Azure region for deployment')
param secondaryLocation string = 'westeurope'

@description('Prefix for all resource names')
param resourcePrefix string = 'content-delivery'

@description('Environment name (dev, staging, prod)')
param environment string = 'prod'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'content-delivery'
  Solution: 'azure-front-door-netapp'
}

@description('NetApp Files service level (Standard, Premium, Ultra)')
@allowed(['Standard', 'Premium', 'Ultra'])
param netAppServiceLevel string = 'Premium'

@description('NetApp Files capacity pool size in TiB')
param capacityPoolSize int = 4

@description('NetApp Files volume size in GiB')
param volumeSize int = 1000

@description('Enable Web Application Firewall')
param enableWaf bool = true

@description('WAF mode (Prevention, Detection)')
@allowed(['Prevention', 'Detection'])
param wafMode string = 'Prevention'

@description('Enable monitoring and diagnostics')
param enableMonitoring bool = true

// Variables
var uniqueSuffix = take(uniqueString(resourceGroup().id), 6)
var namingPrefix = '${resourcePrefix}-${uniqueSuffix}'

// Resource names
var vnetPrimaryName = '${namingPrefix}-vnet-primary'
var vnetSecondaryName = '${namingPrefix}-vnet-secondary'
var anfAccountPrimaryName = '${namingPrefix}-anf-primary'
var anfAccountSecondaryName = '${namingPrefix}-anf-secondary'
var capacityPoolName = 'pool-premium'
var volumeName = 'content-volume'
var frontDoorName = '${namingPrefix}-fd'
var wafPolicyName = '${namingPrefix}-waf'
var lawName = '${namingPrefix}-law'
var loadBalancerName = '${namingPrefix}-lb'

// Network configuration
var vnetPrimaryAddressSpace = '10.1.0.0/16'
var vnetSecondaryAddressSpace = '10.2.0.0/16'
var anfSubnetPrimaryPrefix = '10.1.1.0/24'
var anfSubnetSecondaryPrefix = '10.2.1.0/24'
var privateEndpointSubnetPrimaryPrefix = '10.1.2.0/24'
var privateEndpointSubnetSecondaryPrefix = '10.2.2.0/24'

// Primary Region Resources
module primaryRegion 'modules/region.bicep' = {
  name: 'primary-region-deployment'
  params: {
    location: primaryLocation
    vnetName: vnetPrimaryName
    vnetAddressSpace: vnetPrimaryAddressSpace
    anfSubnetPrefix: anfSubnetPrimaryPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrimaryPrefix
    anfAccountName: anfAccountPrimaryName
    capacityPoolName: capacityPoolName
    volumeName: volumeName
    netAppServiceLevel: netAppServiceLevel
    capacityPoolSize: capacityPoolSize
    volumeSize: volumeSize
    loadBalancerName: loadBalancerName
    namingPrefix: namingPrefix
    tags: tags
  }
}

// Secondary Region Resources
module secondaryRegion 'modules/region.bicep' = {
  name: 'secondary-region-deployment'
  params: {
    location: secondaryLocation
    vnetName: vnetSecondaryName
    vnetAddressSpace: vnetSecondaryAddressSpace
    anfSubnetPrefix: anfSubnetSecondaryPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetSecondaryPrefix
    anfAccountName: anfAccountSecondaryName
    capacityPoolName: capacityPoolName
    volumeName: volumeName
    netAppServiceLevel: netAppServiceLevel
    capacityPoolSize: capacityPoolSize
    volumeSize: volumeSize
    loadBalancerName: '${loadBalancerName}-secondary'
    namingPrefix: namingPrefix
    tags: tags
  }
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableMonitoring) {
  name: lawName
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

// Web Application Firewall Policy
resource wafPolicy 'Microsoft.Network/frontDoorWebApplicationFirewallPolicies@2022-05-01' = if (enableWaf) {
  name: wafPolicyName
  location: 'Global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
      requestBodyCheck: 'Enabled'
      maxRequestBodySizeInKb: 128
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
          ruleGroupOverrides: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
          ruleSetAction: 'Block'
          ruleGroupOverrides: []
        }
      ]
    }
    customRules: {
      rules: [
        {
          name: 'RateLimitRule'
          priority: 100
          enabledState: 'Enabled'
          ruleType: 'RateLimitRule'
          rateLimitDurationInMinutes: 1
          rateLimitThreshold: 100
          matchConditions: [
            {
              matchVariable: 'RemoteAddr'
              operator: 'IPMatch'
              matchValue: [
                '0.0.0.0/0'
              ]
            }
          ]
          action: 'Block'
        }
      ]
    }
  }
}

// Azure Front Door Premium Profile
resource frontDoorProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: frontDoorName
  location: 'Global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

// Front Door Endpoint
resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  parent: frontDoorProfile
  name: 'content-endpoint'
  location: 'Global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

// Origin Group
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = {
  parent: frontDoorProfile
  name: 'content-origins'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'GET'
      probeProtocol: 'Http'
      probeIntervalInSeconds: 60
    }
    sessionAffinityState: 'Disabled'
  }
}

// Primary Origin
resource primaryOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  parent: originGroup
  name: 'primary-origin'
  properties: {
    hostName: '10.1.1.10'
    httpPort: 80
    httpsPort: 443
    originHostHeader: 'content.example.com'
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: false
    sharedPrivateLinkResource: {
      privateLink: {
        id: primaryRegion.outputs.privateLinkServiceId
      }
      privateLinkLocation: primaryLocation
      requestMessage: 'Front Door Private Link Connection'
    }
  }
}

// Secondary Origin
resource secondaryOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  parent: originGroup
  name: 'secondary-origin'
  properties: {
    hostName: '10.2.1.10'
    httpPort: 80
    httpsPort: 443
    originHostHeader: 'content.example.com'
    priority: 2
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: false
    sharedPrivateLinkResource: {
      privateLink: {
        id: secondaryRegion.outputs.privateLinkServiceId
      }
      privateLinkLocation: secondaryLocation
      requestMessage: 'Front Door Private Link Connection'
    }
  }
}

// Rule Set for Caching
resource ruleSet 'Microsoft.Cdn/profiles/ruleSets@2023-05-01' = {
  parent: frontDoorProfile
  name: 'caching-rules'
}

// Caching Rule for Static Content
resource cachingRule 'Microsoft.Cdn/profiles/ruleSets/rules@2023-05-01' = {
  parent: ruleSet
  name: 'static-content-caching'
  properties: {
    order: 1
    conditions: [
      {
        name: 'UrlFileExtension'
        parameters: {
          typeName: 'DeliveryRuleUrlFileExtensionMatchConditionParameters'
          operator: 'Equal'
          matchValues: [
            'jpg'
            'jpeg'
            'png'
            'gif'
            'css'
            'js'
            'pdf'
            'mp4'
            'mp3'
            'svg'
            'woff'
            'woff2'
          ]
          transforms: [
            'Lowercase'
          ]
        }
      }
    ]
    actions: [
      {
        name: 'CacheExpiration'
        parameters: {
          typeName: 'DeliveryRuleCacheExpirationActionParameters'
          cacheBehavior: 'Override'
          cacheType: 'All'
          cacheDuration: '1.00:00:00'
        }
      }
      {
        name: 'ModifyResponseHeader'
        parameters: {
          typeName: 'DeliveryRuleHeaderActionParameters'
          headerAction: 'Overwrite'
          headerName: 'Cache-Control'
          value: 'public, max-age=31536000'
        }
      }
    ]
  }
}

// Front Door Route
resource frontDoorRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = {
  parent: frontDoorEndpoint
  name: 'content-route'
  properties: {
    customDomains: []
    originGroup: {
      id: originGroup.id
    }
    ruleSets: [
      {
        id: ruleSet.id
      }
    ]
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
}

// Security Policy (WAF association)
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2023-05-01' = if (enableWaf) {
  parent: frontDoorProfile
  name: 'content-security-policy'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: frontDoorEndpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

// Diagnostic Settings for Front Door
resource frontDoorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring) {
  name: 'fd-diagnostics'
  scope: frontDoorProfile
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'FrontDoorAccessLog'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'FrontDoorHealthProbeLog'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
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

// Alert Rules
resource highLatencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: 'high-latency-alert'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when Front Door response latency exceeds threshold'
    severity: 2
    enabled: true
    scopes: [
      frontDoorProfile.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighLatency'
          metricName: 'OriginLatency'
          operator: 'GreaterThan'
          threshold: 1000
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

resource errorRateAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: 'error-rate-alert'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when Front Door error rate exceeds threshold'
    severity: 1
    enabled: true
    scopes: [
      frontDoorProfile.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighErrorRate'
          metricName: 'ResponseSize'
          operator: 'GreaterThan'
          threshold: 10
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

// Outputs
output frontDoorEndpointHostname string = frontDoorEndpoint.properties.hostName
output frontDoorProfileId string = frontDoorProfile.id
output wafPolicyId string = enableWaf ? wafPolicy.id : ''
output logAnalyticsWorkspaceId string = enableMonitoring ? logAnalyticsWorkspace.id : ''
output primaryRegionOutputs object = primaryRegion.outputs
output secondaryRegionOutputs object = secondaryRegion.outputs
output resourceNames object = {
  frontDoorProfile: frontDoorProfile.name
  frontDoorEndpoint: frontDoorEndpoint.name
  wafPolicy: enableWaf ? wafPolicy.name : ''
  logAnalyticsWorkspace: enableMonitoring ? logAnalyticsWorkspace.name : ''
}