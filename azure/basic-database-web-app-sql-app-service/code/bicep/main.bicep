@description('The location where all resources will be deployed')
param location string = resourceGroup().location

@description('A unique suffix to ensure resource names are globally unique')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('The name prefix for all resources')
param resourceNamePrefix string = 'webapp-demo'

@description('The name of the SQL Database')
param sqlDatabaseName string = 'TasksDB'

@description('The admin username for the SQL Server')
param sqlAdminUsername string = 'sqladmin'

@description('The admin password for the SQL Server')
@secure()
param sqlAdminPassword string

@description('The SKU for the SQL Database')
@allowed([
  'Basic'
  'S0'
  'S1'
  'S2'
])
param sqlDatabaseSku string = 'Basic'

@description('The SKU for the App Service Plan')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
])
param appServicePlanSku string = 'B1'

@description('The .NET runtime version for the web app')
param dotnetVersion string = 'v8.0'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'recipe'
  environment: 'demo'
}

// Variables for resource names
var sqlServerName = '${resourceNamePrefix}-sql-${uniqueSuffix}'
var appServicePlanName = '${resourceNamePrefix}-asp-${uniqueSuffix}'
var webAppName = '${resourceNamePrefix}-app-${uniqueSuffix}'

// SQL Server resource
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// SQL Database resource
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-05-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: {
    name: sqlDatabaseSku
    tier: sqlDatabaseSku == 'Basic' ? 'Basic' : 'Standard'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: sqlDatabaseSku == 'Basic' ? 2147483648 : 268435456000 // 2GB for Basic, 250GB for Standard
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    requestedBackupStorageRedundancy: 'Local'
  }
}

// Firewall rule to allow Azure services
resource sqlServerFirewallRule 'Microsoft.Sql/servers/firewallRules@2023-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
    tier: startsWith(appServicePlanSku, 'B') ? 'Basic' : 'Standard'
    capacity: 1
  }
  kind: 'app'
  properties: {
    reserved: false // false for Windows, true for Linux
  }
}

// Web App with managed identity
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: dotnetVersion
      defaultDocuments: [
        'index.html'
        'Default.htm'
        'Default.html'
        'Default.asp'
        'index.htm'
        'iisstart.htm'
        'default.aspx'
      ]
      minTlsVersion: '1.2'
      ftpsState: 'FtpsOnly'
      use32BitWorkerProcess: false
      alwaysOn: appServicePlanSku != 'F1' && appServicePlanSku != 'D1' // Always On not supported on Free/Shared tiers
      http20Enabled: true
      connectionStrings: [
        {
          name: 'DefaultConnection'
          connectionString: 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${sqlDatabaseName};Persist Security Info=False;User ID=${sqlAdminUsername};Password=${sqlAdminPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
          type: 'SQLAzure'
        }
      ]
    }
  }
  dependsOn: [
    sqlDatabase
    sqlServerFirewallRule
  ]
}

// Optional: Create sample database schema (requires SQL script deployment)
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${resourceNamePrefix}-db-init-${uniqueSuffix}'
  location: location
  tags: tags
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.50.0'
    timeout: 'PT10M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'SQL_SERVER_NAME'
        value: sqlServer.properties.fullyQualifiedDomainName
      }
      {
        name: 'SQL_DATABASE_NAME'
        value: sqlDatabaseName
      }
      {
        name: 'SQL_ADMIN_USERNAME'
        value: sqlAdminUsername
      }
      {
        name: 'SQL_ADMIN_PASSWORD'
        secureValue: sqlAdminPassword
      }
    ]
    scriptContent: '''
      # Install sqlcmd
      curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
      curl https://packages.microsoft.com/config/ubuntu/20.04/prod.list > /etc/apt/sources.list.d/mssql-release.list
      apt-get update
      ACCEPT_EULA=Y apt-get install -y mssql-tools18 unixodbc-dev
      
      # Create database schema
      /opt/mssql-tools18/bin/sqlcmd -S $SQL_SERVER_NAME -d $SQL_DATABASE_NAME -U $SQL_ADMIN_USERNAME -P $SQL_ADMIN_PASSWORD -C -Q "
      CREATE TABLE Tasks (
          Id INT IDENTITY(1,1) PRIMARY KEY,
          Title NVARCHAR(100) NOT NULL,
          Description NVARCHAR(500),
          IsCompleted BIT DEFAULT 0,
          CreatedDate DATETIME2 DEFAULT GETUTCDATE()
      );
      
      INSERT INTO Tasks (Title, Description) VALUES 
      ('Setup Database', 'Configure Azure SQL Database for the application'),
      ('Deploy Web App', 'Deploy the web application to Azure App Service'),
      ('Test Application', 'Verify database connectivity and functionality');"
    '''
  }
  dependsOn: [
    sqlDatabase
    sqlServerFirewallRule
  ]
}

// Outputs
@description('The name of the created resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the SQL Server')
output sqlServerName string = sqlServer.name

@description('The fully qualified domain name of the SQL Server')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('The name of the SQL Database')
output sqlDatabaseName string = sqlDatabase.name

@description('The name of the App Service Plan')
output appServicePlanName string = appServicePlan.name

@description('The name of the Web App')
output webAppName string = webApp.name

@description('The URL of the Web App')
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'

@description('The principal ID of the Web App managed identity')
output webAppManagedIdentityPrincipalId string = webApp.identity.principalId

@description('The connection string for the SQL Database')
output sqlConnectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${sqlDatabaseName};Persist Security Info=False;User ID=${sqlAdminUsername};Password=${sqlAdminPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'