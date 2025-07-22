// Azure Blockchain Supply Chain Transparency with Confidential Ledger and Cosmos DB
// This template deploys a complete blockchain-powered supply chain tracking solution

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Administrator object ID for Confidential Ledger')
param adminObjectId string

@description('Tenant ID for Azure AD authentication')
param tenantId string = subscription().tenantId

@description('Enable global distribution for Cosmos DB')
param enableGlobalDistribution bool = false

@description('Cosmos DB throughput (RU/s)')
@minValue(400)
@maxValue(100000)
param cosmosDbThroughput int = 1000

@description('API Management publisher name')
param apimPublisherName string = 'Supply Chain Demo'

@description('API Management publisher email')
param apimPublisherEmail string = 'admin@supplychain.demo'

@description('Enable Application Insights')
param enableApplicationInsights bool = true

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

// Variables for consistent naming
var confidentialLedgerName = 'scledger${uniqueSuffix}'
var cosmosAccountName = 'sccosmos${uniqueSuffix}'
var storageAccountName = 'scstorage${uniqueSuffix}'
var keyVaultName = 'sckv${uniqueSuffix}'
var logicAppName = 'sc-logic-app-${uniqueSuffix}'
var eventGridTopicName = 'sc-events-${uniqueSuffix}'
var apimName = 'sc-apim-${uniqueSuffix}'
var logAnalyticsName = 'supply-chain-logs-${uniqueSuffix}'
var appInsightsName = 'supply-chain-insights-${uniqueSuffix}'
var managedIdentityName = 'logic-app-identity-${uniqueSuffix}'

// Common tags
var commonTags = {
  purpose: 'supply-chain'
  environment: environment
  solution: 'blockchain-transparency'
  generatedBy: 'bicep'
}

// Managed Identity for Logic Apps
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: commonTags
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: location
  tags: commonTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    Flow_Type: 'Bluefield'
  }
}

// Azure Confidential Ledger
resource confidentialLedger 'Microsoft.ConfidentialLedger/ledgers@2023-09-27' = {
  name: confidentialLedgerName
  location: location
  tags: commonTags
  properties: {
    ledgerType: 'Public'
    aadBasedSecurityPrincipals: [
      {
        principalId: adminObjectId
        tenantId: tenantId
        ledgerRoleName: 'Administrator'
      }
      {
        principalId: managedIdentity.properties.principalId
        tenantId: tenantId
        ledgerRoleName: 'Contributor'
      }
    ]
  }
}

// Cosmos DB Account
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-11-15' = {
  name: cosmosAccountName
  location: location
  tags: commonTags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: enableGlobalDistribution ? [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
      {
        locationName: 'West US 2'
        failoverPriority: 1
        isZoneRedundant: false
      }
    ] : [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: [
      {
        name: 'EnableAnalyticalStorage'
      }
    ]
    enableMultipleWriteLocations: enableGlobalDistribution
    enableAnalyticalStorage: true
    analyticalStorageConfiguration: {
      schemaType: 'WellDefined'
    }
  }
}

// Cosmos DB Database
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-11-15' = {
  parent: cosmosAccount
  name: 'SupplyChainDB'
  properties: {
    resource: {
      id: 'SupplyChainDB'
    }
  }
}

// Cosmos DB Container for Products
resource cosmosContainerProducts 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = {
  parent: cosmosDatabase
  name: 'Products'
  properties: {
    resource: {
      id: 'Products'
      partitionKey: {
        paths: [
          '/productId'
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
      defaultTtl: -1
      analyticalStorageTtl: -1
    }
    options: {
      throughput: cosmosDbThroughput
    }
  }
}

// Cosmos DB Container for Transactions
resource cosmosContainerTransactions 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-11-15' = {
  parent: cosmosDatabase
  name: 'Transactions'
  properties: {
    resource: {
      id: 'Transactions'
      partitionKey: {
        paths: [
          '/transactionId'
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
      defaultTtl: -1
      analyticalStorageTtl: -1
    }
    options: {
      throughput: cosmosDbThroughput
    }
  }
}

// Storage Account for Documents
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    isVersioningEnabled: true
    changeFeed: {
      enabled: true
      retentionInDays: 7
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Storage Blob Services
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    versioning: {
      enabled: true
    }
    changeFeed: {
      enabled: true
      retentionInDays: 7
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Storage Container for Documents
resource documentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'documents'
  properties: {
    publicAccess: 'None'
  }
}

// Storage Container for Certificates
resource certificatesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobServices
  name: 'certificates'
  properties: {
    publicAccess: 'None'
  }
}

// Storage Lifecycle Management Policy
resource lifecyclePolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'archiveOldDocuments'
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: [
                'blockBlob'
              ]
              prefixMatch: [
                'documents/'
              ]
            }
            actions: {
              baseBlob: {
                tierToArchive: {
                  daysAfterModificationGreaterThan: 90
                }
                delete: {
                  daysAfterModificationGreaterThan: 365
                }
              }
              version: {
                delete: {
                  daysAfterCreationGreaterThan: 30
                }
              }
            }
          }
        }
      ]
    }
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: commonTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enableRbacAuthorization: true
    enabledForTemplateDeployment: true
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Key Vault Secret for Cosmos DB Connection String
resource cosmosConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'CosmosDBConnectionString'
  properties: {
    value: 'AccountEndpoint=${cosmosAccount.properties.documentEndpoint};AccountKey=${cosmosAccount.listKeys().primaryMasterKey};'
  }
}

// Key Vault Secret for Ledger Endpoint
resource ledgerEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'LedgerEndpoint'
  properties: {
    value: confidentialLedger.properties.ledgerUri
  }
}

// RBAC - Grant Logic App Managed Identity access to Key Vault
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentity.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Event Grid Topic
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: commonTags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
  }
}

// Logic App (Consumption Plan)
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: commonTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        'When_a_HTTP_request_is_received': {
          type: 'Request'
          kind: 'Http'
          inputs: {
            method: 'POST'
            schema: {
              type: 'object'
              properties: {
                transactionId: {
                  type: 'string'
                }
                productId: {
                  type: 'string'
                }
                action: {
                  type: 'string'
                }
                timestamp: {
                  type: 'string'
                }
                location: {
                  type: 'string'
                }
                participant: {
                  type: 'string'
                }
                metadata: {
                  type: 'object'
                }
              }
            }
          }
        }
      }
      actions: {
        'Record_to_Confidential_Ledger': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '${confidentialLedger.properties.ledgerUri}/app/transactions'
            headers: {
              'Content-Type': 'application/json'
            }
            body: '@triggerBody()'
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: managedIdentity.id
            }
          }
        }
        'Store_in_Cosmos_DB': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: '${cosmosAccount.properties.documentEndpoint}/dbs/SupplyChainDB/colls/Transactions/docs'
            headers: {
              'Content-Type': 'application/json'
              'Authorization': '@{concat(\'type%3dmaster%26ver%3d1.0%26sig%3d\', encodeUriComponent(base64(hmacsha256(base64(replace(replace(toLower(utcNow()), \':\', \'%3a\'), \' \', \'%20\')), \'${cosmosAccount.listKeys().primaryMasterKey}\'))))}'
              'x-ms-date': '@utcNow()'
              'x-ms-version': '2018-12-31'
            }
            body: '@triggerBody()'
          }
          runAfter: {
            'Record_to_Confidential_Ledger': [
              'Succeeded'
            ]
          }
        }
        'Publish_Event': {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: eventGridTopic.properties.endpoint
            headers: {
              'aeg-sas-key': eventGridTopic.listKeys().key1
              'Content-Type': 'application/json'
            }
            body: [
              {
                id: '@guid()'
                eventType: '@triggerBody()[\'action\']'
                subject: 'supplychain/products/@{triggerBody()[\'productId\']}'
                eventTime: '@utcNow()'
                data: '@triggerBody()'
                dataVersion: '1.0'
              }
            ]
          }
          runAfter: {
            'Store_in_Cosmos_DB': [
              'Succeeded'
            ]
          }
        }
      }
    }
  }
}

// API Management
resource apiManagement 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: apimName
  location: location
  tags: commonTags
  sku: {
    name: 'Consumption'
    capacity: 0
  }
  properties: {
    publisherName: apimPublisherName
    publisherEmail: apimPublisherEmail
    notificationSenderEmail: apimPublisherEmail
    hostnameConfigurations: [
      {
        type: 'Proxy'
        hostName: '${apimName}.azure-api.net'
        negotiateClientCertificate: false
        defaultSslBinding: true
        certificateSource: 'BuiltIn'
      }
    ]
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'False'
    }
  }
}

// API Management - Supply Chain API
resource supplyChainApi 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apiManagement
  name: 'supply-chain-api'
  properties: {
    displayName: 'Supply Chain API'
    description: 'API for blockchain-powered supply chain transparency'
    path: 'supply-chain'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    format: 'openapi+json'
    value: string({
      openapi: '3.0.0'
      info: {
        title: 'Supply Chain API'
        version: '1.0'
        description: 'API for blockchain-powered supply chain transparency'
      }
      paths: {
        '/transactions': {
          post: {
            summary: 'Submit Transaction'
            description: 'Submit a new supply chain transaction'
            operationId: 'submit-transaction'
            requestBody: {
              required: true
              content: {
                'application/json': {
                  schema: {
                    type: 'object'
                    properties: {
                      transactionId: {
                        type: 'string'
                      }
                      productId: {
                        type: 'string'
                      }
                      action: {
                        type: 'string'
                      }
                      timestamp: {
                        type: 'string'
                      }
                      location: {
                        type: 'string'
                      }
                      participant: {
                        type: 'string'
                      }
                      metadata: {
                        type: 'object'
                      }
                    }
                  }
                }
              }
            }
            responses: {
              '200': {
                description: 'Success'
              }
            }
          }
        }
      }
    })
  }
}

// API Management - Rate Limiting Policy
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: supplyChainApi
  name: 'policy'
  properties: {
    value: '''
      <policies>
        <inbound>
          <rate-limit-by-key calls="100" renewal-period="60" counter-key="@(context.Subscription?.Key ?? "anonymous")" />
          <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
            <openid-config url="https://login.microsoftonline.com/${tenantId}/v2.0/.well-known/openid-configuration" />
            <audiences>
              <audience>api://supply-chain-api</audience>
            </audiences>
          </validate-jwt>
          <set-backend-service base-url="${logicApp.properties.accessEndpoint}" />
        </inbound>
        <backend>
          <base />
        </backend>
        <outbound>
          <base />
        </outbound>
        <on-error>
          <base />
        </on-error>
      </policies>
    '''
  }
}

// Diagnostic Settings for Confidential Ledger
resource ledgerDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'ledger-diagnostics'
  scope: confidentialLedger
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ApplicationLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'Transaction'
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

// Alert Rule for High Transaction Volume
resource highTransactionVolumeAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'high-transaction-volume'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'Alert when transaction volume exceeds normal threshold'
    severity: 2
    enabled: true
    scopes: [
      confidentialLedger.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'TransactionCount'
          metricName: 'TransactionCount'
          operator: 'GreaterThan'
          threshold: 1000
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

// Outputs
output confidentialLedgerName string = confidentialLedger.name
output confidentialLedgerEndpoint string = confidentialLedger.properties.ledgerUri
output cosmosAccountName string = cosmosAccount.name
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output storageAccountName string = storageAccount.name
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output logicAppName string = logicApp.name
output logicAppTriggerUrl string = logicApp.properties.accessEndpoint
output eventGridTopicName string = eventGridTopic.name
output eventGridEndpoint string = eventGridTopic.properties.endpoint
output apiManagementName string = apiManagement.name
output apiManagementGatewayUrl string = 'https://${apiManagement.properties.gatewayUrl}'
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output managedIdentityClientId string = managedIdentity.properties.clientId
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? appInsights.properties.InstrumentationKey : ''
output applicationInsightsConnectionString string = enableApplicationInsights ? appInsights.properties.ConnectionString : ''