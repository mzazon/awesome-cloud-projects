@description('Cosmos DB module with vector search capabilities for personalization data')

// Parameters
@description('Name of the Cosmos DB account')
param accountName string

@description('Azure region for resource deployment')
param location string

@description('Name of the Cosmos DB database')
param databaseName string

@description('Container configurations')
param containers array

@description('Tags to apply to the resource')
param tags object = {}

@description('Consistency level for the Cosmos DB account')
@allowed(['Eventual', 'ConsistentPrefix', 'Session', 'BoundedStaleness', 'Strong'])
param defaultConsistencyLevel string = 'Session'

@description('Enable automatic failover')
param enableAutomaticFailover bool = true

@description('Enable vector search capabilities')
param enableVectorSearch bool = true

// Variables
var consistencyPolicy = {
  defaultConsistencyLevel: defaultConsistencyLevel
  maxIntervalInSeconds: 300
  maxStalenessPrefix: 100000
}

var locations = [
  {
    locationName: location
    failoverPriority: 0
    isZoneRedundant: false
  }
]

// Resources
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: accountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    enableAutomaticFailover: enableAutomaticFailover
    enableMultipleWriteLocations: false
    isVirtualNetworkFilterEnabled: false
    virtualNetworkRules: []
    DisableKeyBasedMetadataWriteAccess: false
    enableFreeTier: false
    enableAnalyticalStorage: false
    databaseAccountOfferType: 'Standard'
    defaultIdentity: 'FirstPartyIdentity'
    networkAclBypass: 'None'
    disableLocalAuth: false
    enablePartitionMerge: false
    enableBurstCapacity: false
    minimalTlsVersion: 'Tls12'
    consistencyPolicy: consistencyPolicy
    locations: locations
    cors: []
    capabilities: enableVectorSearch ? [
      {
        name: 'EnableNoSQLVectorSearch'
      }
    ] : []
    ipRules: []
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Geo'
      }
    }
    networkAclBypassResourceIds: []
  }
}

// Create database
resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

// Create containers with vector search configuration
resource cosmosContainers 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = [for container in containers: {
  parent: database
  name: container.name
  properties: {
    resource: {
      id: container.name
      partitionKey: {
        paths: [
          container.partitionKeyPath
        ]
        kind: 'Hash'
      }
      indexingPolicy: container.name == 'ContentItems' ? {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/contentEmbedding/*'
          }
          {
            path: '/userPreferenceEmbedding/*'
          }
        ]
        vectorIndexes: [
          {
            path: '/contentEmbedding'
            type: 'quantizedFlat'
          }
          {
            path: '/userPreferenceEmbedding'
            type: 'quantizedFlat'
          }
        ]
      } : {
        indexingMode: 'consistent'
        automatic: true
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
      vectorEmbeddingPolicy: container.name == 'ContentItems' ? {
        vectorEmbeddings: [
          {
            path: '/contentEmbedding'
            dataType: 'float32'
            distanceFunction: 'cosine'
            dimensions: 1536
          }
          {
            path: '/userPreferenceEmbedding'
            dataType: 'float32'
            distanceFunction: 'cosine'
            dimensions: 1536
          }
        ]
      } : null
    }
    options: {
      throughput: container.throughput
    }
  }
}]

// Outputs
@description('Cosmos DB Account Resource ID')
output accountId string = cosmosAccount.id

@description('Cosmos DB Account Name')
output accountName string = cosmosAccount.name

@description('Cosmos DB Document Endpoint')
output documentEndpoint string = cosmosAccount.properties.documentEndpoint

@description('Cosmos DB Connection String')
@secure()
output connectionString string = cosmosAccount.listConnectionStrings().connectionStrings[0].connectionString

@description('Cosmos DB Primary Key')
@secure()
output primaryKey string = cosmosAccount.listKeys().primaryMasterKey

@description('Cosmos DB Secondary Key')
@secure()
output secondaryKey string = cosmosAccount.listKeys().secondaryMasterKey

@description('Cosmos DB Database Name')
output databaseName string = database.name

@description('Cosmos DB Container Names')
output containerNames array = [for i in range(0, length(containers)): cosmosContainers[i].name]