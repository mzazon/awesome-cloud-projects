@description('The name of the resource group where resources will be deployed')
param resourceGroupName string = 'rg-playwright-testing'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('A unique suffix to append to resource names')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Name of the Key Vault for storing test credentials')
param keyVaultName string = 'kv-playwright-${uniqueSuffix}'

@description('Name of the Application Insights component')
param applicationInsightsName string = 'ai-playwright-testing'

@description('Name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string = 'law-playwright-${uniqueSuffix}'

@description('Name of the Playwright Testing workspace')
param playwrightWorkspaceName string = 'playwright-workspace-${uniqueSuffix}'

@description('SKU for the Key Vault')
@allowed(['standard', 'premium'])
param keyVaultSku string = 'standard'

@description('Test application URL to store in Key Vault')
param testAppUrl string = 'https://your-test-app.azurewebsites.net'

@description('Test username to store in Key Vault')
param testUsername string = 'testuser@example.com'

@description('Test password to store in Key Vault (will be generated if not provided)')
@secure()
param testPassword string = ''

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'e2e-testing'
  environment: 'testing'
  recipe: 'playwright-testing'
}

// Generate a secure password if not provided
var generatedPassword = empty(testPassword) ? '${uniqueString(resourceGroup().id)}Pw!' : testPassword

// Get current user information for Key Vault access
var currentUser = {
  objectId: ''  // This will need to be set during deployment
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
    }
  }
}

// Application Insights Component
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Key Vault Secrets Officer role definition
var keyVaultSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

// Role assignment for Key Vault (this will need to be done post-deployment with actual user ObjectId)
// Note: In practice, this would be assigned to the user deploying the template or a managed identity

// Store Application Insights Connection String in Key Vault
resource appInsightsConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'AppInsightsConnectionString'
  properties: {
    value: applicationInsights.properties.ConnectionString
    contentType: 'Application Insights Connection String'
  }
}

// Store Test Application URL in Key Vault
resource testAppUrlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'TestAppUrl'
  properties: {
    value: testAppUrl
    contentType: 'Test Application URL'
  }
}

// Store Test Username in Key Vault
resource testUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'TestUsername'
  properties: {
    value: testUsername
    contentType: 'Test Username'
  }
}

// Store Test Password in Key Vault
resource testPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'TestPassword'
  properties: {
    value: generatedPassword
    contentType: 'Test Password'
  }
}

// Alert Rule for High Test Failure Rate
resource testFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'High Test Failure Rate'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when test failure rate exceeds 20%'
    severity: 2
    enabled: true
    scopes: [
      applicationInsights.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'TestFailureRate'
          metricName: 'customMetrics/TestFailureRate'
          operator: 'GreaterThan'
          threshold: 20
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: []
  }
}

// Workbook for Test Analytics Dashboard
resource testAnalyticsWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'test-analytics-workbook')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Playwright Test Analytics Dashboard'
    description: 'Dashboard for monitoring Playwright test execution metrics'
    category: 'workbook'
    serializedData: json({
      version: 'Notebook/1.0'
      items: [
        {
          type: 1
          content: {
            json: '# Playwright Test Analytics Dashboard\n\nThis dashboard provides insights into your end-to-end browser test execution.'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'customEvents\n| where name == "TestCompleted"\n| summarize \n    TotalTests = count(),\n    PassedTests = countif(tostring(customDimensions.passed) == "True"),\n    FailedTests = countif(tostring(customDimensions.passed) == "False"),\n    AvgDuration = avg(todouble(customMeasurements.duration))\n  by Browser = tostring(customDimensions.browser)\n| extend PassRate = round(100.0 * PassedTests / TotalTests, 2)\n| order by Browser'
            size: 0
            title: 'Test Execution Summary by Browser'
            timeContext: {
              durationMs: 86400000
            }
            queryType: 0
            resourceType: 'microsoft.insights/components'
            visualization: 'table'
          }
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'customMetrics\n| where name == "TestDuration"\n| summarize AvgDuration = avg(value) by bin(timestamp, 1h), \n    TestName = tostring(customDimensions.testName)\n| render timechart'
            size: 0
            title: 'Test Duration Trends'
            timeContext: {
              durationMs: 86400000
            }
            queryType: 0
            resourceType: 'microsoft.insights/components'
            visualization: 'timechart'
          }
        }
      ]
    })
    sourceId: applicationInsights.id
  }
}

// Outputs
@description('The connection string for Application Insights')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The instrumentation key for Application Insights')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The name of the created Key Vault')
output keyVaultName string = keyVault.name

@description('The URI of the created Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The Application Insights component ID')
output applicationInsightsId string = applicationInsights.id

@description('The generated test password (for reference)')
@secure()
output generatedTestPassword string = generatedPassword

@description('Manual steps required after deployment')
output manualSteps array = [
  'Create Playwright Testing workspace at https://aka.ms/mpt/portal'
  'Assign Key Vault Secrets Officer role to users who need access to test credentials'
  'Configure CI/CD pipeline with the Application Insights connection string'
  'Update test configuration with the Key Vault URI and Application Insights settings'
]

@description('Key Vault Secrets Officer role ID for manual role assignment')
output keyVaultSecretsOfficerRoleId string = keyVaultSecretsOfficerRoleId

@description('Commands to assign Key Vault access to current user')
output roleAssignmentCommands array = [
  'az role assignment create --role "Key Vault Secrets Officer" --assignee <user-object-id> --scope ${keyVault.id}'
  'Replace <user-object-id> with: az ad signed-in-user show --query id --output tsv'
]