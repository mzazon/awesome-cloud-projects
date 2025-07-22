@description('Implements a cost-optimized multi-tenant database architecture using Azure Elastic Database Pools and Azure Backup Vault')

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource naming')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('SQL Server administrator username')
param sqlAdminUsername string = 'sqladmin'

@description('SQL Server administrator password')
@secure()
param sqlAdminPassword string

@description('Elastic pool edition')
@allowed(['Basic', 'Standard', 'Premium'])
param elasticPoolEdition string = 'Standard'

@description('Elastic pool DTU capacity')
@allowed([50, 100, 200, 300, 400, 800, 1200, 1600])
param elasticPoolDtu int = 200

@description('Maximum DTU per database in the elastic pool')
param elasticPoolDatabaseDtuMax int = 50

@description('Minimum DTU per database in the elastic pool')
param elasticPoolDatabaseDtuMin int = 0

@description('Storage size for the elastic pool in MB')
param elasticPoolStorageMB int = 204800

@description('Number of tenant databases to create')
@minValue(1)
@maxValue(10)
param numberOfTenantDatabases int = 4

@description('Monthly budget amount in USD')
param budgetAmount int = 500

@description('Budget alert threshold percentage')
@minValue(1)
@maxValue(100)
param budgetAlertThreshold int = 80

@description('Backup retention period in days')
@minValue(7)
@maxValue(35)
param backupRetentionDays int = 30

@description('Tags to apply to all resources')
param resourceTags object = {
  purpose: 'multi-tenant-saas'
  environment: environment
  'cost-center': 'database-operations'
  managedBy: 'bicep-template'
}

// Variables
var sqlServerName = 'sqlserver-mt-${uniqueSuffix}'
var elasticPoolName = 'elasticpool-saas-${uniqueSuffix}'
var backupVaultName = 'bv-multitenant-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-multitenant-${uniqueSuffix}'
var backupPolicyName = 'sql-database-policy'
var actionGroupName = 'cost-alert-group-${uniqueSuffix}'
var budgetName = 'budget-multitenant-db-${uniqueSuffix}'

// Managed Identity for Backup Vault
resource backupVaultManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-backup-vault-${uniqueSuffix}'
  location: location
  tags: resourceTags
}

// SQL Database Server
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: sqlServerName
  location: location
  tags: resourceTags
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }
  
  // Firewall rule to allow Azure services
  resource firewallRuleAzureServices 'firewallRules@2023-05-01-preview' = {
    name: 'AllowAzureServices'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '0.0.0.0'
    }
  }
}

// Elastic Database Pool
resource elasticPool 'Microsoft.Sql/servers/elasticPools@2023-05-01-preview' = {
  parent: sqlServer
  name: elasticPoolName
  location: location
  tags: resourceTags
  sku: {
    name: elasticPoolEdition
    tier: elasticPoolEdition
    capacity: elasticPoolDtu
  }
  properties: {
    perDatabaseSettings: {
      minCapacity: elasticPoolDatabaseDtuMin
      maxCapacity: elasticPoolDatabaseDtuMax
    }
    maxSizeBytes: elasticPoolStorageMB * 1024 * 1024
    zoneRedundant: false
  }
}

// Tenant Databases
resource tenantDatabases 'Microsoft.Sql/servers/databases@2023-05-01-preview' = [for i in range(1, numberOfTenantDatabases): {
  parent: sqlServer
  name: 'tenant-${i}-db-${uniqueSuffix}'
  location: location
  tags: union(resourceTags, {
    tenantId: 'tenant-${i}'
  })
  properties: {
    elasticPoolId: elasticPool.id
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 268435456000 // 250 GB
    requestedBackupStorageRedundancy: 'Geo'
  }
}]

// Log Analytics Workspace for monitoring
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
      dailyQuotaGb: 1
    }
  }
}

// Diagnostic Settings for SQL Server
resource sqlServerDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sql-server-diagnostics'
  scope: sqlServer
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
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

// Diagnostic Settings for Elastic Pool
resource elasticPoolDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'elastic-pool-diagnostics'
  scope: elasticPool
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

// Data Protection Backup Vault
resource backupVault 'Microsoft.DataProtection/backupVaults@2023-11-01' = {
  name: backupVaultName
  location: location
  tags: resourceTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${backupVaultManagedIdentity.id}': {}
    }
  }
  properties: {
    storageSettings: [
      {
        datastoreType: 'VaultStore'
        type: 'GeoRedundant'
      }
    ]
    securitySettings: {
      softDeleteSettings: {
        state: 'On'
        retentionDurationInDays: 14
      }
    }
    monitoringSettings: {
      azureMonitorAlertSettings: {
        alertsForAllJobFailures: 'Enabled'
      }
    }
  }
}

// Backup Policy for SQL Databases
resource backupPolicy 'Microsoft.DataProtection/backupVaults/backupPolicies@2023-11-01' = {
  parent: backupVault
  name: backupPolicyName
  properties: {
    datasourceTypes: [
      'Microsoft.Sql/servers/databases'
    ]
    policyRules: [
      {
        name: 'Daily'
        objectType: 'AzureRetentionRule'
        isDefault: true
        lifecycles: [
          {
            deleteAfter: {
              objectType: 'AbsoluteDeleteOption'
              duration: 'P${backupRetentionDays}D'
            }
            sourceDataStore: {
              dataStoreType: 'VaultStore'
              objectType: 'DataStoreInfoBase'
            }
          }
        ]
      }
      {
        name: 'Weekly'
        objectType: 'AzureRetentionRule'
        isDefault: false
        lifecycles: [
          {
            deleteAfter: {
              objectType: 'AbsoluteDeleteOption'
              duration: 'P12W'
            }
            sourceDataStore: {
              dataStoreType: 'VaultStore'
              objectType: 'DataStoreInfoBase'
            }
          }
        ]
      }
      {
        name: 'Monthly'
        objectType: 'AzureRetentionRule'
        isDefault: false
        lifecycles: [
          {
            deleteAfter: {
              objectType: 'AbsoluteDeleteOption'
              duration: 'P12M'
            }
            sourceDataStore: {
              dataStoreType: 'VaultStore'
              objectType: 'DataStoreInfoBase'
            }
          }
        ]
      }
    ]
  }
}

// Action Group for Cost Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: resourceTags
  properties: {
    groupShortName: 'CostAlert'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    azureFunctionReceivers: []
    logicAppReceivers: []
  }
}

// Budget for Cost Management
resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: budgetName
  properties: {
    timePeriod: {
      startDate: '2025-01-01'
      endDate: '2026-01-01'
    }
    timeGrain: 'Monthly'
    amount: budgetAmount
    category: 'Cost'
    notifications: {
      'Actual_GreaterThan_${budgetAlertThreshold}_Percent': {
        enabled: true
        operator: 'GreaterThan'
        threshold: budgetAlertThreshold
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Actual'
      }
      'Forecasted_GreaterThan_${budgetAlertThreshold}_Percent': {
        enabled: true
        operator: 'GreaterThan'
        threshold: budgetAlertThreshold
        contactGroups: [
          actionGroup.id
        ]
        thresholdType: 'Forecasted'
      }
    }
    filter: {
      dimensions: {
        name: 'ResourceGroupName'
        operator: 'In'
        values: [
          resourceGroup().name
        ]
      }
    }
  }
}

// Role Assignment for Backup Vault to access SQL Databases
var sqlDbContributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c' // SQL DB Contributor
resource backupVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, backupVaultManagedIdentity.id, sqlDbContributorRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sqlDbContributorRoleId)
    principalId: backupVaultManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('The name of the SQL Server')
output sqlServerName string = sqlServer.name

@description('The fully qualified domain name of the SQL Server')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('The name of the Elastic Database Pool')
output elasticPoolName string = elasticPool.name

@description('The resource ID of the Elastic Database Pool')
output elasticPoolId string = elasticPool.id

@description('The names of the tenant databases')
output tenantDatabaseNames array = [for i in range(1, numberOfTenantDatabases): 'tenant-${i}-db-${uniqueSuffix}']

@description('The name of the Backup Vault')
output backupVaultName string = backupVault.name

@description('The resource ID of the Backup Vault')
output backupVaultId string = backupVault.id

@description('The name of the Log Analytics Workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The workspace ID of the Log Analytics Workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The name of the budget')
output budgetName string = budget.name

@description('Connection string template for tenant databases')
output connectionStringTemplate string = 'Server=${sqlServer.properties.fullyQualifiedDomainName};Database={{DATABASE_NAME}};User Id=${sqlAdminUsername};Password={{PASSWORD}};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'

@description('Resource group location')
output location string = location

@description('Resource tags applied')
output resourceTags object = resourceTags