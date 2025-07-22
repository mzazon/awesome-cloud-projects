// Azure Enterprise API Protection with Premium Management and WAF
// This template creates a comprehensive enterprise-grade API security platform
// with multi-layered threat protection and high-performance caching

targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
param environment string = 'demo'

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Administrator email for API Management')
param adminEmail string

@description('Organization name for API Management')
param organizationName string = 'Enterprise APIs'

@description('API Management SKU')
@allowed([
  'Premium'
])
param apimSku string = 'Premium'

@description('Redis Cache SKU')
@allowed([
  'Premium'
])
param redisSku string = 'Premium'

@description('Redis Cache size')
@allowed([
  'P1'
  'P2'
  'P3'
  'P4'
  'P5'
])
param redisSize string = 'P1'

@description('Front Door SKU')
@allowed([
  'Standard_AzureFrontDoor'
  'Premium_AzureFrontDoor'
])
param frontDoorSku string = 'Premium_AzureFrontDoor'

@description('WAF policy mode')
@allowed([
  'Prevention'
  'Detection'
])
param wafMode string = 'Prevention'

@description('Enable diagnostic logging')
param enableDiagnostics bool = true

@description('Log retention in days')
param logRetentionDays int = 30

@description('Common tags for all resources')
param tags object = {
  purpose: 'enterprise-api-security'
  environment: environment
  recipe: 'enterprise-api-protection-premium-waf'
}

// Resource naming variables
var resourceNames = {
  apim: 'apim-enterprise-${uniqueSuffix}'
  wafPolicy: 'waf-enterprise-policy-${uniqueSuffix}'
  frontDoor: 'fd-enterprise-${uniqueSuffix}'
  redis: 'redis-enterprise-${uniqueSuffix}'
  appInsights: 'ai-enterprise-${uniqueSuffix}'
  logWorkspace: 'law-enterprise-${uniqueSuffix}'
}

// Log Analytics Workspace for centralized logging
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
      disableLocalAuth: false
    }
  }
}

// Application Insights for API monitoring
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

// Azure Cache for Redis Enterprise
resource redisCache 'Microsoft.Cache/Redis@2023-08-01' = {
  name: resourceNames.redis
  location: location
  tags: tags
  properties: {
    sku: {
      name: redisSku
      family: 'P'
      capacity: int(substring(redisSize, 1, 1))
    }
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    redisVersion: '6'
  }
}

// API Management Premium instance
resource apiManagement 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: resourceNames.apim
  location: location
  tags: tags
  sku: {
    name: apimSku
    capacity: 1
  }
  properties: {
    publisherName: organizationName
    publisherEmail: adminEmail
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
    }
    disableGateway: false
    virtualNetworkType: 'None'
    publicNetworkAccess: 'Enabled'
    apiVersionConstraint: {
      minApiVersion: '2021-08-01'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Redis connection named value in API Management
resource redisConnectionNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apiManagement
  name: 'redis-connection'
  properties: {
    displayName: 'Redis Connection'
    value: '${redisCache.properties.hostName}:${redisCache.properties.sslPort},password=${redisCache.listKeys().primaryKey},ssl=True'
    secret: true
  }
}

// Application Insights logger in API Management
resource appInsightsLogger 'Microsoft.ApiManagement/service/loggers@2023-05-01-preview' = {
  parent: apiManagement
  name: 'applicationinsights'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights Logger'
    credentials: {
      instrumentationKey: applicationInsights.properties.InstrumentationKey
    }
    isBuffered: true
    resourceId: applicationInsights.id
  }
}

// Global diagnostic settings for API Management
resource apimDiagnostics 'Microsoft.ApiManagement/service/diagnostics@2023-05-01-preview' = {
  parent: apiManagement
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    loggerId: appInsightsLogger.id
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        headers: ['Content-Type', 'Authorization']
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
    backend: {
      request: {
        headers: ['Content-Type']
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

// Sample API for demonstration
resource sampleApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apiManagement
  name: 'sample-api'
  properties: {
    displayName: 'Sample Enterprise API'
    description: 'Sample API for demonstrating enterprise security features'
    serviceUrl: 'https://httpbin.org'
    path: 'api/v1'
    protocols: ['https']
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    apiRevision: '1'
    isCurrent: true
  }
}

// API operation for GET requests
resource sampleApiOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: sampleApi
  name: 'get-sample'
  properties: {
    displayName: 'Get Sample Data'
    method: 'GET'
    urlTemplate: '/get'
    description: 'Sample GET operation for testing'
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
    ]
  }
}

// Enterprise security policies for the API
resource apiSecurityPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: sampleApi
  name: 'policy'
  properties: {
    value: '''
<policies>
    <inbound>
        <!-- Rate limiting per subscription key -->
        <rate-limit calls="100" renewal-period="60" />
        <quota calls="1000" renewal-period="3600" />
        
        <!-- IP filtering for additional security -->
        <ip-filter action="allow">
            <address-range from="0.0.0.0" to="255.255.255.255" />
        </ip-filter>
        
        <!-- Request size and timeout limits -->
        <set-variable name="requestSize" value="@(context.Request.Body.As<string>(preserveContent: true).Length)" />
        <choose>
            <when condition="@(int.Parse(context.Variables.GetValueOrDefault<string>("requestSize", "0")) > 1048576)">
                <return-response>
                    <set-status code="413" reason="Request Entity Too Large" />
                    <set-header name="Content-Type" exists-action="override">
                        <value>application/json</value>
                    </set-header>
                    <set-body>{"error": "Request size exceeds maximum allowed limit"}</set-body>
                </return-response>
            </when>
        </choose>
        
        <!-- Cache lookup for GET requests -->
        <cache-lookup vary-by-developer="false" vary-by-developer-groups="false" downstream-caching-type="none">
            <vary-by-header>Accept</vary-by-header>
            <vary-by-header>Accept-Charset</vary-by-header>
            <vary-by-query-parameter>*</vary-by-query-parameter>
        </cache-lookup>
        
        <!-- Custom request logging -->
        <log-to-eventhub logger-id="applicationinsights" partition-id="0">
            @{
                return new JObject(
                    new JProperty("timestamp", DateTime.UtcNow.ToString()),
                    new JProperty("requestId", context.RequestId),
                    new JProperty("method", context.Request.Method),
                    new JProperty("url", context.Request.Url.ToString()),
                    new JProperty("clientIp", context.Request.IpAddress),
                    new JProperty("userAgent", context.Request.Headers.GetValueOrDefault("User-Agent", ""))
                ).ToString();
            }
        </log-to-eventhub>
    </inbound>
    
    <backend>
        <base />
    </backend>
    
    <outbound>
        <!-- Cache store for successful responses -->
        <cache-store duration="300" />
        
        <!-- Security headers -->
        <set-header name="X-Content-Type-Options" exists-action="override">
            <value>nosniff</value>
        </set-header>
        <set-header name="X-Frame-Options" exists-action="override">
            <value>DENY</value>
        </set-header>
        <set-header name="X-XSS-Protection" exists-action="override">
            <value>1; mode=block</value>
        </set-header>
        <set-header name="Strict-Transport-Security" exists-action="override">
            <value>max-age=31536000; includeSubDomains</value>
        </set-header>
        <set-header name="Content-Security-Policy" exists-action="override">
            <value>default-src 'self'</value>
        </set-header>
        
        <!-- Remove server information -->
        <set-header name="Server" exists-action="delete" />
        <set-header name="X-Powered-By" exists-action="delete" />
        
        <!-- Response logging -->
        <log-to-eventhub logger-id="applicationinsights" partition-id="0">
            @{
                return new JObject(
                    new JProperty("timestamp", DateTime.UtcNow.ToString()),
                    new JProperty("requestId", context.RequestId),
                    new JProperty("responseCode", context.Response.StatusCode),
                    new JProperty("responseTime", context.Elapsed.TotalMilliseconds)
                ).ToString();
            }
        </log-to-eventhub>
    </outbound>
    
    <on-error>
        <!-- Error logging -->
        <log-to-eventhub logger-id="applicationinsights" partition-id="0">
            @{
                return new JObject(
                    new JProperty("timestamp", DateTime.UtcNow.ToString()),
                    new JProperty("requestId", context.RequestId),
                    new JProperty("error", context.LastError.Message),
                    new JProperty("source", context.LastError.Source)
                ).ToString();
            }
        </log-to-eventhub>
    </on-error>
</policies>
'''
  }
}

// WAF Policy with comprehensive security rules
resource wafPolicy 'Microsoft.Network/frontDoorWebApplicationFirewallPolicies@2022-05-01' = {
  name: resourceNames.wafPolicy
  location: 'Global'
  tags: tags
  sku: {
    name: frontDoorSku
  }
  properties: {
    policySettings: {
      mode: wafMode
      enabledState: 'Enabled'
      requestBodyCheck: 'Enabled'
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      redirectUrl: 'https://www.example.com/blocked'
      customBlockResponseStatusCode: 403
      customBlockResponseBody: 'UmVxdWVzdCBibG9ja2VkIGJ5IEF6dXJlIFdBRg=='
    }
    customRules: {
      rules: [
        {
          name: 'RateLimitRule'
          priority: 1
          ruleType: 'RateLimitRule'
          rateLimitDurationInMinutes: 1
          rateLimitThreshold: 100
          matchConditions: [
            {
              matchVariable: 'RemoteAddr'
              operator: 'IPMatch'
              negateCondition: false
              matchValue: [
                '0.0.0.0/0'
              ]
            }
          ]
          action: 'Block'
        }
        {
          name: 'GeoBlockRule'
          priority: 2
          ruleType: 'MatchRule'
          matchConditions: [
            {
              matchVariable: 'RemoteAddr'
              operator: 'GeoMatch'
              negateCondition: false
              matchValue: [
                'CN'
                'RU'
                'KP'
              ]
            }
          ]
          action: 'Block'
        }
        {
          name: 'SQLInjectionRule'
          priority: 3
          ruleType: 'MatchRule'
          matchConditions: [
            {
              matchVariable: 'QueryString'
              operator: 'Contains'
              negateCondition: false
              matchValue: [
                'union'
                'select'
                'insert'
                'delete'
                'drop'
                'exec'
                'script'
                '1=1'
                '1=2'
              ]
              transforms: [
                'Lowercase'
                'RemoveNulls'
                'Trim'
              ]
            }
          ]
          action: 'Block'
        }
      ]
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
          exclusions: []
          ruleGroupOverrides: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
          ruleSetAction: 'Block'
          exclusions: []
          ruleGroupOverrides: []
        }
      ]
    }
  }
}

// Front Door Profile
resource frontDoorProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: resourceNames.frontDoor
  location: 'Global'
  tags: tags
  sku: {
    name: frontDoorSku
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

// Front Door Endpoint
resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2023-05-01' = {
  parent: frontDoorProfile
  name: 'api-endpoint'
  location: 'Global'
  properties: {
    enabledState: 'Enabled'
  }
}

// Origin Group for API Management
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2023-05-01' = {
  parent: frontDoorProfile
  name: 'apim-origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/status-0123456789abcdef'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 120
    }
    sessionAffinityState: 'Disabled'
  }
}

// Origin for API Management
resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2023-05-01' = {
  parent: originGroup
  name: 'apim-origin'
  properties: {
    hostName: replace(replace(apiManagement.properties.gatewayUrl, 'https://', ''), 'http://', '')
    httpPort: 80
    httpsPort: 443
    originHostHeader: replace(replace(apiManagement.properties.gatewayUrl, 'https://', ''), 'http://', '')
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// Security Policy Association
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2023-05-01' = {
  parent: frontDoorProfile
  name: 'api-security-policy'
  properties: {
    parameters: {
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
      type: 'WebApplicationFirewall'
    }
  }
}

// Route for API traffic
resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2023-05-01' = {
  parent: frontDoorEndpoint
  name: 'api-route'
  properties: {
    customDomains: []
    originGroup: {
      id: originGroup.id
    }
    originPath: '/'
    ruleSets: []
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'MatchRequest'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
    compressionSettings: {
      contentTypesToCompress: [
        'application/json'
        'application/xml'
        'text/html'
        'text/css'
        'text/javascript'
        'text/plain'
      ]
      isCompressionEnabled: true
    }
    queryStringCachingBehavior: 'IgnoreQueryString'
    cacheConfiguration: {
      queryStringCachingBehavior: 'IgnoreQueryString'
      compressionSettings: {
        isCompressionEnabled: true
      }
    }
  }
  dependsOn: [
    origin
  ]
}

// Diagnostic settings for API Management
resource apimDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'apim-diagnostics'
  scope: apiManagement
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'GatewayLogs'
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

// Diagnostic settings for Redis Cache
resource redisDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'redis-diagnostics'
  scope: redisCache
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ConnectedClientList'
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
output apiManagementName string = apiManagement.name
output apiManagementGatewayUrl string = apiManagement.properties.gatewayUrl
output apiManagementPortalUrl string = apiManagement.properties.portalUrl
output apiManagementDeveloperPortalUrl string = apiManagement.properties.developerPortalUrl
output frontDoorEndpointUrl string = 'https://${frontDoorEndpoint.properties.hostName}'
output frontDoorProfileName string = frontDoorProfile.name
output wafPolicyName string = wafPolicy.name
output redisCacheName string = redisCache.name
output redisCacheHostName string = redisCache.properties.hostName
output redisCachePort int = redisCache.properties.port
output redisCacheSslPort int = redisCache.properties.sslPort
output applicationInsightsName string = applicationInsights.name
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId
output resourceGroupName string = resourceGroup().name
output sampleApiUrl string = '${apiManagement.properties.gatewayUrl}/api/v1'
output frontDoorApiUrl string = 'https://${frontDoorEndpoint.properties.hostName}/api/v1'