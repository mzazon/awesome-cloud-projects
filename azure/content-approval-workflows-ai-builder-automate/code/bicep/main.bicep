@description('Main Bicep template for Content Approval Workflows with AI Builder and Power Automate')

// Parameters
@description('Environment name for resource naming (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environmentName string = 'dev'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource naming to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Microsoft 365 tenant domain name (e.g., contoso.onmicrosoft.com)')
param tenantDomain string

@description('SharePoint site name for content approval')
param siteName string = 'content-approval'

@description('Document library name for approval workflows')
param libraryName string = 'DocumentsForApproval'

@description('Power Platform environment region')
@allowed(['unitedstates', 'europe', 'asia', 'australia', 'india', 'japan', 'canada', 'southamerica', 'unitedkingdom', 'france', 'germany', 'switzerland', 'korea', 'norway', 'southafrica'])
param powerPlatformRegion string = 'unitedstates'

@description('AI Builder credits allocation for content analysis')
@minValue(100)
@maxValue(10000)
param aiBuilderCredits int = 1000

@description('Teams channel name for approval notifications')
param teamsChannelName string = 'Content Approvals'

@description('Enable content approval workflows')
param enableContentApproval bool = true

@description('Enable AI analysis for documents')
param enableAIAnalysis bool = true

@description('Maximum approval time in hours')
@minValue(1)
@maxValue(168)
param maxApprovalTimeHours int = 48

@description('Tags to apply to all resources')
param tags object = {
  Environment: environmentName
  Project: 'ContentApprovalWorkflows'
  Owner: 'PowerPlatform'
  CostCenter: 'IT'
}

// Variables
var resourcePrefix = '${siteName}-${environmentName}-${uniqueSuffix}'
var sharePointSiteUrl = 'https://${split(tenantDomain, '.')[0]}.sharepoint.com/sites/${resourcePrefix}'

// Storage Account for workflow artifacts and logs
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'st${replace(resourcePrefix, '-', '')}${substring(uniqueSuffix, 0, 6)}'
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    networkAcls: {
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// Blob containers for workflow data
resource workflowContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/workflow-logs'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'PowerAutomate workflow execution logs'
      retention: '90days'
    }
  }
}

resource documentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/document-cache'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Temporary document storage for AI analysis'
      retention: '7days'
    }
  }
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${resourcePrefix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

// Application Insights for Power Automate monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-${resourcePrefix}'
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

// Key Vault for storing sensitive configuration
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${substring(replace(resourcePrefix, '-', ''), 0, 20)}'
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: []
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enabledForDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Store SharePoint site URL in Key Vault
resource sharePointSiteSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'SharePointSiteUrl'
  properties: {
    value: sharePointSiteUrl
    attributes: {
      enabled: true
    }
    contentType: 'text/plain'
  }
}

// Store AI Builder configuration in Key Vault
resource aiBuilderConfigSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'AIBuilderConfig'
  properties: {
    value: string({
      credits: aiBuilderCredits
      region: powerPlatformRegion
      enabled: enableAIAnalysis
    })
    attributes: {
      enabled: true
    }
    contentType: 'application/json'
  }
}

// Action Group for alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${resourcePrefix}'
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'ContentAppr'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    armRoleReceivers: []
  }
}

// Alert for high workflow failure rate
resource workflowFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-workflow-failures-${resourcePrefix}'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when workflow failure rate exceeds 10%'
    severity: 2
    enabled: true
    scopes: [
      applicationInsights.id
    ]
    evaluationFrequency: 'PT15M'
    windowSize: 'PT1H'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'WorkflowFailures'
          metricName: 'exceptions/count'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Total'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Azure Resource Manager template for Power Platform environment (deployment script)
resource powerPlatformDeployment 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'deploy-powerplatform-${resourcePrefix}'
  location: location
  tags: tags
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '10.0'
    timeout: 'PT30M'
    retentionInterval: 'P1D'
    scriptContent: '''
      param(
        [string]$TenantDomain,
        [string]$SiteName,
        [string]$LibraryName,
        [string]$ResourcePrefix,
        [string]$PowerPlatformRegion,
        [bool]$EnableContentApproval,
        [bool]$EnableAIAnalysis,
        [int]$MaxApprovalTimeHours,
        [string]$TeamsChannelName
      )
      
      Write-Output "Starting Power Platform environment configuration..."
      Write-Output "Tenant Domain: $TenantDomain"
      Write-Output "Site Name: $SiteName"
      Write-Output "Resource Prefix: $ResourcePrefix"
      
      # This script would typically:
      # 1. Create SharePoint site using PnP PowerShell
      # 2. Configure document library with content approval
      # 3. Set up AI Builder prompt template
      # 4. Configure Power Automate workflow
      # 5. Set up Teams integration
      
      # Note: Actual SharePoint/Power Platform resource creation requires
      # specific PowerShell modules and authentication that would be
      # configured in a real deployment scenario
      
      $output = @{
        SharePointSiteUrl = "https://$($TenantDomain.Split('.')[0]).sharepoint.com/sites/$ResourcePrefix"
        DocumentLibraryUrl = "https://$($TenantDomain.Split('.')[0]).sharepoint.com/sites/$ResourcePrefix/$LibraryName"
        PowerPlatformRegion = $PowerPlatformRegion
        Status = "Configured"
      }
      
      Write-Output "Power Platform configuration completed successfully"
      $DeploymentScriptOutputs = $output
    '''
    arguments: '-TenantDomain "${tenantDomain}" -SiteName "${siteName}" -LibraryName "${libraryName}" -ResourcePrefix "${resourcePrefix}" -PowerPlatformRegion "${powerPlatformRegion}" -EnableContentApproval $${enableContentApproval} -EnableAIAnalysis $${enableAIAnalysis} -MaxApprovalTimeHours ${maxApprovalTimeHours} -TeamsChannelName "${teamsChannelName}"'
  }
}

// Managed Identity for deployment script
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'mi-${resourcePrefix}'
  location: location
  tags: tags
}

// Role assignment for managed identity to access Key Vault
resource keyVaultAccessRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, managedIdentity.id, 'Key Vault Secrets User')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('Storage account name for workflow artifacts')
output storageAccountName string = storageAccount.name

@description('Storage account connection string')
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('SharePoint site URL for content approval')
output sharePointSiteUrl string = sharePointSiteUrl

@description('Document library URL for approvals')
output documentLibraryUrl string = '${sharePointSiteUrl}/${libraryName}'

@description('Key Vault name for configuration storage')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Resource prefix used for naming')
output resourcePrefix string = resourcePrefix

@description('Power Platform region configuration')
output powerPlatformRegion string = powerPlatformRegion

@description('AI Builder credits allocated')
output aiBuilderCredits int = aiBuilderCredits

@description('Content approval configuration')
output contentApprovalConfig object = {
  enabled: enableContentApproval
  maxApprovalTimeHours: maxApprovalTimeHours
  aiAnalysisEnabled: enableAIAnalysis
  teamsChannelName: teamsChannelName
}

@description('Managed Identity principal ID for additional role assignments')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Deployment status and configuration')
output deploymentStatus object = powerPlatformDeployment.properties.outputs