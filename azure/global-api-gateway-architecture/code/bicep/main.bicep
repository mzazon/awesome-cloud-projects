// Multi-Region API Gateway with Azure API Management and Cosmos DB
// This template deploys a globally distributed API gateway solution

@description('The primary Azure region for deployment')
param primaryRegion string = 'eastus'

@description('Secondary Azure regions for multi-region deployment')
param secondaryRegions array = ['westeurope', 'southeastasia']

@description('Prefix for all resource names')
param resourcePrefix string = 'api-global'

@description('Environment tag for resources')
@allowed(['dev', 'staging', 'production'])
param environment string = 'production'

@description('API Management publisher name')
param publisherName string = 'Contoso API Platform'

@description('API Management publisher email')
param publisherEmail string = 'api-team@contoso.com'

@description('API Management SKU')
@allowed(['Developer', 'Standard', 'Premium'])
param apimSku string = 'Premium'

@description('API Management SKU capacity')
param apimCapacity int = 1

@description('Cosmos DB consistency level')
@allowed(['BoundedStaleness', 'Eventual', 'Session', 'Strong', 'ConsistentPrefix'])
param cosmosConsistencyLevel string = 'Session'

@description('Cosmos DB throughput for rate limiting container')
param rateLimitThroughput int = 10000

@description('Enable zone redundancy for resources')
param enableZoneRedundancy bool = true

@description('Log Analytics workspace retention days')
param logRetentionDays int = 30

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id)
var apimName = '${resourcePrefix}-apim-${uniqueSuffix}'
var cosmosAccountName = '${resourcePrefix}-cosmos-${uniqueSuffix}'
var trafficManagerName = '${resourcePrefix}-tm-${uniqueSuffix}'
var logAnalyticsName = '${resourcePrefix}-law-${uniqueSuffix}'
var appInsightsName = '${resourcePrefix}-ai-${uniqueSuffix}'

// All regions for Cosmos DB deployment
var allRegions = union([primaryRegion], secondaryRegions)

// Cosmos DB locations configuration
var cosmosLocations = [for (region, i) in allRegions: {
  locationName: region
  failoverPriority: i
  isZoneRedundant: enableZoneRedundancy
}]

// Common tags
var commonTags = {
  Environment: environment
  Purpose: 'multi-region-api-gateway'
  ManagedBy: 'bicep'
  CreatedDate: utcNow('yyyy-MM-dd')
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: primaryRegion
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      searchVersion: 1
      legacy: 0
    }
  }
}

// Application Insights
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: primaryRegion
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Cosmos DB Account with multi-region configuration
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosAccountName
  location: primaryRegion
  tags: commonTags
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: cosmosConsistencyLevel
      maxIntervalInSeconds: 300
      maxStalenessPrefix: 100000
    }
    locations: cosmosLocations
    databaseAccountOfferType: 'Standard'
    enableMultipleWriteLocations: true
    enableAutomaticFailover: true
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 720
        backupStorageRedundancy: 'Zone'
      }
    }
    networkAclBypass: 'AzureServices'
    publicNetworkAccess: 'Enabled'
  }
}

// Cosmos DB Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosAccount
  name: 'APIConfiguration'
  properties: {
    resource: {
      id: 'APIConfiguration'
    }
  }
}

// Cosmos DB Container for Rate Limiting
resource rateLimitContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDatabase
  name: 'RateLimits'
  properties: {
    resource: {
      id: 'RateLimits'
      partitionKey: {
        paths: [
          '/apiId'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
      defaultTtl: 3600 // 1 hour TTL for rate limit data
    }
    options: {
      throughput: rateLimitThroughput
    }
  }
}

// API Management Service
resource apiManagement 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: primaryRegion
  tags: commonTags
  sku: {
    name: apimSku
    capacity: apimCapacity
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
    }
    virtualNetworkType: 'None'
    disableGateway: false
    enableClientCertificate: false
    restore: false
    developerPortalStatus: 'Enabled'
    publicIpAddressId: null
    hostnameConfigurations: []
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// API Management Additional Locations (Secondary Regions)
resource apiManagementAdditionalLocations 'Microsoft.ApiManagement/service/locations@2023-05-01-preview' = [for region in secondaryRegions: {
  parent: apiManagement
  name: region
  properties: {
    location: region
    sku: {
      name: apimSku
      capacity: apimCapacity
    }
    publicIpAddressId: null
    virtualNetworkConfiguration: null
    disableGateway: false
  }
}]

// Role Assignment for API Management to access Cosmos DB
resource cosmosDbDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosAccount.id, apiManagement.id, 'CosmosDBDataContributor')
  scope: cosmosAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00000000-0000-0000-0000-000000000002') // Cosmos DB Built-in Data Contributor
    principalId: apiManagement.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Application Insights Logger for API Management
resource apiManagementLogger 'Microsoft.ApiManagement/service/loggers@2023-05-01-preview' = {
  parent: apiManagement
  name: 'appinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    credentials: {
      connectionString: applicationInsights.properties.ConnectionString
    }
    isBuffered: true
    resourceId: applicationInsights.id
  }
}

// Global API Policy with Cosmos DB Integration
resource globalPolicy 'Microsoft.ApiManagement/service/policies@2023-05-01-preview' = {
  parent: apiManagement
  name: 'policy'
  properties: {
    value: '''
    <policies>
      <inbound>
        <base />
        <set-variable name="requestId" value="@(Guid.NewGuid().ToString())" />
        <trace source="global-policy">@(context.Variables["requestId"])</trace>
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
        <set-header name="X-Request-ID" exists-action="override">
          <value>@(context.Variables["requestId"])</value>
        </set-header>
        <set-header name="X-Region" exists-action="override">
          <value>@(context.Deployment.Region)</value>
        </set-header>
      </outbound>
      <on-error>
        <base />
        <trace source="global-policy-error">@(context.LastError.Message)</trace>
      </on-error>
    </policies>
    '''
    format: 'xml'
  }
}

// Sample Weather API
resource weatherApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apiManagement
  name: 'weather-api'
  properties: {
    displayName: 'Global Weather API'
    apiRevision: '1'
    description: 'Multi-region weather API with global rate limiting'
    subscriptionRequired: true
    serviceUrl: 'https://api.openweathermap.org/data/2.5'
    path: 'weather'
    protocols: [
      'https'
    ]
    authenticationSettings: {
      subscriptionKeyRequired: true
    }
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    apiType: 'http'
    isCurrent: true
    format: 'openapi'
    value: '''
    {
      "openapi": "3.0.1",
      "info": {
        "title": "Global Weather API",
        "version": "1.0"
      },
      "servers": [
        {
          "url": "https://api.openweathermap.org/data/2.5"
        }
      ],
      "paths": {
        "/weather": {
          "get": {
            "summary": "Get current weather",
            "parameters": [
              {
                "name": "q",
                "in": "query",
                "required": true,
                "schema": {
                  "type": "string"
                },
                "description": "City name, state code and country code divided by comma"
              },
              {
                "name": "appid",
                "in": "query",
                "required": true,
                "schema": {
                  "type": "string"
                },
                "description": "API key"
              }
            ],
            "responses": {
              "200": {
                "description": "Success",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    '''
  }
  dependsOn: [
    globalPolicy
  ]
}

// Rate Limiting Policy for Weather API
resource weatherApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: weatherApi
  name: 'policy'
  properties: {
    value: '''
    <policies>
      <inbound>
        <base />
        <set-variable name="clientId" value="@(context.Subscription?.Key ?? "anonymous")" />
        <set-variable name="cosmosEndpoint" value="${cosmosAccount.properties.documentEndpoint}" />
        <cache-lookup-value key="@("rate-limit-" + context.Variables["clientId"])" variable-name="remainingCalls" />
        <choose>
          <when condition="@(context.Variables.ContainsKey("remainingCalls") && (int)context.Variables["remainingCalls"] <= 0)">
            <return-response>
              <set-status code="429" reason="Too Many Requests" />
              <set-header name="Retry-After" exists-action="override">
                <value>60</value>
              </set-header>
              <set-header name="X-RateLimit-Remaining" exists-action="override">
                <value>0</value>
              </set-header>
              <set-body>{"error": "Rate limit exceeded. Please try again later."}</set-body>
            </return-response>
          </when>
          <otherwise>
            <!-- Log request to Cosmos DB for global rate limiting -->
            <send-request mode="new" response-variable-name="cosmosResponse" timeout="5" ignore-error="true">
              <set-url>@(context.Variables["cosmosEndpoint"] + "dbs/APIConfiguration/colls/RateLimits/docs")</set-url>
              <set-method>POST</set-method>
              <set-header name="Authorization" exists-action="override">
                <value>@("Bearer " + context.Authentication.GetAccessToken("https://cosmos.azure.com"))</value>
              </set-header>
              <set-header name="Content-Type" exists-action="override">
                <value>application/json</value>
              </set-header>
              <set-header name="x-ms-documentdb-partitionkey" exists-action="override">
                <value>@("[\"" + context.Variables["clientId"] + "\"]")</value>
              </set-header>
              <set-body>@{
                return new JObject(
                  new JProperty("id", Guid.NewGuid().ToString()),
                  new JProperty("apiId", context.Variables["clientId"]),
                  new JProperty("timestamp", DateTime.UtcNow),
                  new JProperty("region", context.Deployment.Region),
                  new JProperty("operation", context.Operation.Name),
                  new JProperty("requestId", context.Variables["requestId"])
                ).ToString();
              }</set-body>
            </send-request>
            <cache-store-value key="@("rate-limit-" + context.Variables["clientId"])" value="100" duration="3600" />
          </otherwise>
        </choose>
      </inbound>
      <backend>
        <base />
      </backend>
      <outbound>
        <base />
        <set-header name="X-RateLimit-Remaining" exists-action="override">
          <value>@(context.Variables.ContainsKey("remainingCalls") ? context.Variables["remainingCalls"].ToString() : "100")</value>
        </set-header>
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
    '''
    format: 'xml'
  }
  dependsOn: [
    cosmosDbDataContributorRole
  ]
}

// Traffic Manager Profile
resource trafficManagerProfile 'Microsoft.Network/trafficmanagerprofiles@2022-04-01' = {
  name: trafficManagerName
  location: 'global'
  tags: commonTags
  properties: {
    profileStatus: 'Enabled'
    trafficRoutingMethod: 'Performance'
    dnsConfig: {
      relativeName: trafficManagerName
      ttl: 30
    }
    monitorConfig: {
      protocol: 'HTTPS'
      port: 443
      path: '/status-0123456789abcdef'
      intervalInSeconds: 30
      timeoutInSeconds: 10
      toleratedNumberOfFailures: 3
    }
    endpoints: []
  }
}

// Traffic Manager Endpoint for Primary Region
resource trafficManagerEndpointPrimary 'Microsoft.Network/trafficmanagerprofiles/endpoints@2022-04-01' = {
  parent: trafficManagerProfile
  name: 'endpoint-${primaryRegion}'
  properties: {
    type: 'Microsoft.Network/trafficManagerProfiles/azureEndpoints'
    targetResourceId: apiManagement.id
    endpointStatus: 'Enabled'
    endpointLocation: primaryRegion
    priority: 1
    weight: 1
  }
}

// Traffic Manager Endpoints for Secondary Regions
resource trafficManagerEndpointsSecondary 'Microsoft.Network/trafficmanagerprofiles/endpoints@2022-04-01' = [for (region, i) in secondaryRegions: {
  parent: trafficManagerProfile
  name: 'endpoint-${region}'
  properties: {
    type: 'Microsoft.Network/trafficManagerProfiles/externalEndpoints'
    target: '${apimName}-${region}-01.regional.azure-api.net'
    endpointStatus: 'Enabled'
    endpointLocation: region
    priority: i + 2
    weight: 1
  }
  dependsOn: [
    apiManagementAdditionalLocations
  ]
}]

// Diagnostic Settings for API Management
resource apiManagementDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
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
      {
        category: 'WebSocketConnectionLogs'
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

// Diagnostic Settings for Cosmos DB
resource cosmosDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'cosmos-diagnostics'
  scope: cosmosAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'DataPlaneRequests'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
      {
        category: 'QueryRuntimeStatistics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'Requests'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
  }
}

// Alert Rules for Regional Failures
resource apiFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-api-failures'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'Alert when API failure rate is high'
    severity: 2
    enabled: true
    scopes: [
      apiManagement.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'FailedRequests'
          metricName: 'FailedRequests'
          operator: 'GreaterThan'
          threshold: 100
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
    autoMitigate: true
  }
}

// Outputs
output apiManagementName string = apiManagement.name
output apiManagementId string = apiManagement.id
output apiManagementGatewayUrl string = apiManagement.properties.gatewayUrl
output apiManagementPrincipalId string = apiManagement.identity.principalId
output cosmosAccountName string = cosmosAccount.name
output cosmosAccountEndpoint string = cosmosAccount.properties.documentEndpoint
output trafficManagerFqdn string = trafficManagerProfile.properties.dnsConfig.fqdn
output trafficManagerEndpoint string = 'https://${trafficManagerProfile.properties.dnsConfig.fqdn}'
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output weatherApiUrl string = '${apiManagement.properties.gatewayUrl}/weather'
output globalApiEndpoint string = 'https://${trafficManagerProfile.properties.dnsConfig.fqdn}/weather'
output deployedRegions array = allRegions
output resourceGroupName string = resourceGroup().name