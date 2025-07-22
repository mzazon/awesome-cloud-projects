// ==============================================================================
// Main Bicep template for Securing Global Web Applications
// with Azure Static Web Apps and Azure Front Door WAF
// ==============================================================================

targetScope = 'resourceGroup'

// ==============================================================================
// PARAMETERS
// ==============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed([
  'dev'
  'staging' 
  'prod'
])
param environment string = 'dev'

@description('Application name prefix for resource naming')
@minLength(2)
@maxLength(10)
param appName string = 'secureapp'

@description('Random suffix for globally unique resource names')
param randomSuffix string = uniqueString(resourceGroup().id)

@description('Static Web App configuration')
param staticWebApp object = {
  repositoryUrl: 'https://github.com/staticwebdev/vanilla-basic'
  branch: 'main'
  appLocation: '/'
  outputLocation: 'public'
  buildCommand: ''
  sku: 'Standard'
}

@description('WAF policy configuration')
param wafPolicy object = {
  mode: 'Prevention'
  enableManagedRuleSets: true
  enableCustomRules: true
  rateLimitThreshold: 100
  rateLimitDurationMinutes: 1
  enableGeoFiltering: true
  allowedCountries: [
    'US'
    'CA'
    'GB'
    'DE'
  ]
}

@description('Front Door configuration')
param frontDoor object = {
  sku: 'Standard_AzureFrontDoor'
  enableCaching: true
  cacheExpirationDays: 7
  enableCompression: true
  httpsRedirect: true
  forwardingProtocol: 'HttpsOnly'
}

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Application: appName
  Purpose: 'Security Demo'
  Deployment: 'Automated'
}

// ==============================================================================
// VARIABLES
// ==============================================================================

var resourceNames = {
  staticWebApp: 'swa-${appName}-${environment}-${randomSuffix}'
  frontDoorProfile: 'afd-${appName}-${environment}-${randomSuffix}'
  frontDoorEndpoint: 'endpoint-${appName}-${environment}-${randomSuffix}'
  wafPolicy: 'wafpolicy${appName}${environment}${randomSuffix}'
  originGroup: 'og-staticwebapp'
  origin: 'origin-swa'
  route: 'route-secure'
  securityPolicy: 'security-policy-waf'
  ruleSetCaching: 'ruleset-caching'
  ruleSetCompression: 'ruleset-compression'
}

// ==============================================================================
// AZURE STATIC WEB APPS
// ==============================================================================

resource staticWebApp 'Microsoft.Web/staticSites@2023-01-01' = {
  name: resourceNames.staticWebApp
  location: location
  tags: tags
  sku: {
    name: staticWebApp.sku
    tier: staticWebApp.sku
  }
  properties: {
    repositoryUrl: staticWebApp.repositoryUrl
    branch: staticWebApp.branch
    buildProperties: {
      appLocation: staticWebApp.appLocation
      outputLocation: staticWebApp.outputLocation
      appBuildCommand: staticWebApp.buildCommand
    }
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    enterpriseGradeCdnStatus: 'Enabled'
  }
}

// ==============================================================================
// WEB APPLICATION FIREWALL (WAF) POLICY
// ==============================================================================

resource wafPolicyResource 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2022-05-01' = {
  name: resourceNames.wafPolicy
  location: 'Global'
  tags: tags
  sku: {
    name: frontDoor.sku
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafPolicy.mode
      requestBodyCheck: 'Enabled'
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    }
    managedRules: wafPolicy.enableManagedRuleSets ? {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleGroupOverrides: []
          exclusions: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
          ruleGroupOverrides: []
          exclusions: []
        }
      ]
    } : null
    customRules: wafPolicy.enableCustomRules ? {
      rules: [
        // Rate limiting rule
        {
          name: 'RateLimitRule'
          priority: 1
          enabledState: 'Enabled'
          ruleType: 'RateLimitRule'
          rateLimitThreshold: wafPolicy.rateLimitThreshold
          rateLimitDurationInMinutes: wafPolicy.rateLimitDurationMinutes
          action: 'Block'
          matchConditions: [
            {
              matchVariable: 'RemoteAddr'
              operator: 'IPMatch'
              matchValue: [
                '0.0.0.0/0'
              ]
            }
          ]
        }
        // Geo-filtering rule (if enabled)
        ...(wafPolicy.enableGeoFiltering ? [
          {
            name: 'GeoFilterRule'
            priority: 2
            enabledState: 'Enabled'
            ruleType: 'MatchRule'
            action: 'Allow'
            matchConditions: [
              {
                matchVariable: 'RemoteAddr'
                operator: 'GeoMatch'
                matchValue: wafPolicy.allowedCountries
              }
            ]
          }
        ] : [])
      ]
    } : null
  }
}

// ==============================================================================
// AZURE FRONT DOOR
// ==============================================================================

resource frontDoorProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: resourceNames.frontDoorProfile
  location: 'Global'
  tags: tags
  sku: {
    name: frontDoor.sku
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  name: resourceNames.frontDoorEndpoint
  parent: frontDoorProfile
  location: 'Global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

// ==============================================================================
// ORIGIN GROUP AND ORIGIN
// ==============================================================================

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = {
  name: resourceNames.originGroup
  parent: frontDoorProfile
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 30
    }
    sessionAffinityState: 'Disabled'
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  name: resourceNames.origin
  parent: originGroup
  properties: {
    hostName: staticWebApp.properties.defaultHostname
    httpPort: 80
    httpsPort: 443
    originHostHeader: staticWebApp.properties.defaultHostname
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// ==============================================================================
// RULE SETS FOR CACHING AND COMPRESSION
// ==============================================================================

resource ruleSetCaching 'Microsoft.Cdn/profiles/ruleSets@2023-05-01' = if (frontDoor.enableCaching) {
  name: resourceNames.ruleSetCaching
  parent: frontDoorProfile
}

resource cachingRule 'Microsoft.Cdn/profiles/ruleSets/rules@2023-05-01' = if (frontDoor.enableCaching) {
  name: 'rule-cache-static'
  parent: ruleSetCaching
  properties: {
    order: 1
    conditions: [
      {
        name: 'UrlFileExtension'
        parameters: {
          typeName: 'DeliveryRuleUrlFileExtensionMatchConditionParameters'
          operator: 'Contains'
          matchValues: [
            'css'
            'js'
            'jpg'
            'jpeg'
            'png'
            'gif'
            'svg'
            'woff'
            'woff2'
            'ico'
            'pdf'
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
          cacheDuration: '${frontDoor.cacheExpirationDays}.00:00:00'
        }
      }
    ]
  }
}

resource ruleSetCompression 'Microsoft.Cdn/profiles/ruleSets@2023-05-01' = if (frontDoor.enableCompression) {
  name: resourceNames.ruleSetCompression
  parent: frontDoorProfile
}

resource compressionRule 'Microsoft.Cdn/profiles/ruleSets/rules@2023-05-01' = if (frontDoor.enableCompression) {
  name: 'rule-compression'
  parent: ruleSetCompression
  properties: {
    order: 1
    conditions: [
      {
        name: 'RequestHeader'
        parameters: {
          typeName: 'DeliveryRuleRequestHeaderConditionParameters'
          selector: 'Accept-Encoding'
          operator: 'Contains'
          matchValues: [
            'gzip'
          ]
          transforms: [
            'Lowercase'
          ]
        }
      }
    ]
    actions: [
      {
        name: 'ModifyResponseHeader'
        parameters: {
          typeName: 'DeliveryRuleResponseHeaderActionParameters'
          headerAction: 'Append'
          headerName: 'Content-Encoding'
          value: 'gzip'
        }
      }
    ]
  }
}

// ==============================================================================
// ROUTES
// ==============================================================================

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = {
  name: resourceNames.route
  parent: frontDoorEndpoint
  dependsOn: [
    origin
  ]
  properties: {
    originGroup: {
      id: originGroup.id
    }
    ruleSets: concat(
      frontDoor.enableCaching ? [
        {
          id: ruleSetCaching.id
        }
      ] : [],
      frontDoor.enableCompression ? [
        {
          id: ruleSetCompression.id
        }
      ] : []
    )
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: frontDoor.forwardingProtocol
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: frontDoor.httpsRedirect ? 'Enabled' : 'Disabled'
    enabledState: 'Enabled'
  }
}

// ==============================================================================
// SECURITY POLICY
// ==============================================================================

resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2023-05-01' = {
  name: resourceNames.securityPolicy
  parent: frontDoorProfile
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicyResource.id
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

// ==============================================================================
// OUTPUTS
// ==============================================================================

@description('Static Web App details')
output staticWebApp object = {
  name: staticWebApp.name
  id: staticWebApp.id
  defaultHostname: staticWebApp.properties.defaultHostname
  repositoryUrl: staticWebApp.properties.repositoryUrl
  customDomains: staticWebApp.properties.customDomains
}

@description('Front Door profile details')
output frontDoorProfile object = {
  name: frontDoorProfile.name
  id: frontDoorProfile.id
  frontDoorId: frontDoorProfile.properties.frontDoorId
  resourceState: frontDoorProfile.properties.resourceState
}

@description('Front Door endpoint details')
output frontDoorEndpoint object = {
  name: frontDoorEndpoint.name
  id: frontDoorEndpoint.id
  hostName: frontDoorEndpoint.properties.hostName
  enabledState: frontDoorEndpoint.properties.enabledState
}

@description('WAF policy details')
output wafPolicy object = {
  name: wafPolicyResource.name
  id: wafPolicyResource.id
  resourceState: wafPolicyResource.properties.resourceState
  policySettings: wafPolicyResource.properties.policySettings
}

@description('Origin group and origin details')
output origins object = {
  originGroup: {
    name: originGroup.name
    id: originGroup.id
  }
  origin: {
    name: origin.name
    id: origin.id
    hostName: origin.properties.hostName
  }
}

@description('Security configuration details')
output security object = {
  wafPolicyId: wafPolicyResource.id
  securityPolicyId: securityPolicy.id
  frontDoorId: frontDoorProfile.properties.frontDoorId
}

@description('Application URLs')
output applicationUrls object = {
  staticWebAppUrl: 'https://${staticWebApp.properties.defaultHostname}'
  frontDoorUrl: 'https://${frontDoorEndpoint.properties.hostName}'
  managementPortal: 'https://portal.azure.com/#@/resource${staticWebApp.id}'
}

@description('Configuration values for Static Web App integration')
output staticWebAppConfig object = {
  frontDoorId: frontDoorProfile.properties.frontDoorId
  allowedForwardedHost: frontDoorEndpoint.properties.hostName
  configurationFile: {
    networking: {
      allowedIpRanges: [
        'AzureFrontDoor.Backend'
      ]
    }
    forwardingGateway: {
      requiredHeaders: {
        'X-Azure-FDID': frontDoorProfile.properties.frontDoorId
      }
      allowedForwardedHosts: [
        frontDoorEndpoint.properties.hostName
      ]
    }
    routes: [
      {
        route: '/.auth/*'
        headers: {
          'Cache-Control': 'no-store'
        }
      }
    ]
  }
}

@description('Resource names for reference')
output resourceNames object = resourceNames

@description('Deployment summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  environment: environment
  staticWebAppName: staticWebApp.name
  frontDoorName: frontDoorProfile.name
  wafPolicyName: wafPolicyResource.name
  deploymentTime: utcNow()
  tags: tags
}