@description('The name of the Azure Automation Account')
param automationAccountName string = 'aa-cleanup-${uniqueString(resourceGroup().id)}'

@description('The Azure region for resource deployment')
param location string = resourceGroup().location

@description('The environment tag for resources (e.g., dev, test, prod)')
param environment string = 'dev'

@description('The project name for resource tagging')
param projectName string = 'resource-cleanup'

@description('The cleanup schedule frequency in hours (default: weekly = 168 hours)')
param cleanupFrequencyHours int = 168

@description('The day of week for cleanup schedule (0=Sunday, 1=Monday, etc.)')
@minValue(0)
@maxValue(6)
param cleanupDayOfWeek int = 0

@description('The hour of day for cleanup schedule (0-23)')
@minValue(0)
@maxValue(23)
param cleanupHourOfDay int = 2

@description('Default number of days old for resource cleanup')
@minValue(1)
@maxValue(365)
param defaultDaysOld int = 7

@description('Enable dry run mode by default for safety')
param defaultDryRun bool = true

@description('Common tags applied to all resources')
param commonTags object = {
  Environment: environment
  Project: projectName
  Purpose: 'automation'
  CreatedBy: 'bicep-template'
  AutoCleanup: 'false'
  DoNotDelete: 'true'
}

// Variables for resource naming and configuration
var runbookName = 'ResourceCleanupRunbook'
var scheduleName = 'WeeklyCleanupSchedule'
var cleanupStartTime = dateTimeAdd(utcNow(), 'P1D', 'yyyy-MM-ddT${string(cleanupHourOfDay)}:00:00Z')

// PowerShell runbook content for resource cleanup
var runbookContent = '''
param(
    [int]$DaysOld = ${defaultDaysOld},
    [string]$Environment = "${environment}",
    [bool]$DryRun = $${defaultDryRun}
)

# Ensure no context inheritance and connect using managed identity
Disable-AzContextAutosave -Scope Process
$AzureContext = (Connect-AzAccount -Identity).context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription `
    -DefaultProfile $AzureContext

Write-Output "Starting resource cleanup process..."
Write-Output "Parameters: DaysOld=$DaysOld, Environment=$Environment, DryRun=$DryRun"
Write-Output "Automation Account: ${automationAccountName}"
Write-Output "Resource Group: ${resourceGroup().name}"

# Calculate cutoff date
$cutoffDate = (Get-Date).AddDays(-$DaysOld)
Write-Output "Resources created before $cutoffDate will be considered for cleanup"

# Get all resource groups with specified environment tag
$resourceGroups = Get-AzResourceGroup | Where-Object {
    $_.Tags.Environment -eq $Environment -and
    $_.Tags.AutoCleanup -eq "true"
}

Write-Output "Found $($resourceGroups.Count) resource groups with Environment='$Environment' and AutoCleanup='true'"

$cleanupSummary = @{
    ResourceGroupsProcessed = 0
    ResourcesFound = 0
    ResourcesDeleted = 0
    ResourcesSkipped = 0
    Errors = @()
}

foreach ($rg in $resourceGroups) {
    Write-Output "Processing resource group: $($rg.ResourceGroupName)"
    $cleanupSummary.ResourceGroupsProcessed++
    
    try {
        # Get all resources in the resource group
        $allResources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName
        Write-Output "Found $($allResources.Count) total resources in $($rg.ResourceGroupName)"
        
        # Filter resources based on cleanup criteria
        $oldResources = $allResources | Where-Object {
            # Skip if DoNotDelete tag is present
            if ($_.Tags.DoNotDelete -eq "true") {
                Write-Output "Skipping protected resource: $($_.Name) (DoNotDelete=true)"
                $cleanupSummary.ResourcesSkipped++
                return $false
            }
            
            # Skip if no creation time available
            if ($_.CreatedTime -eq $null) {
                Write-Output "Skipping resource with no creation time: $($_.Name)"
                $cleanupSummary.ResourcesSkipped++
                return $false
            }
            
            # Check if resource is older than cutoff date
            $createdTime = [DateTime]$_.CreatedTime
            if ($createdTime -lt $cutoffDate) {
                return $true
            } else {
                Write-Output "Skipping recent resource: $($_.Name) (Created: $createdTime)"
                $cleanupSummary.ResourcesSkipped++
                return $false
            }
        }
        
        $cleanupSummary.ResourcesFound += $oldResources.Count
        Write-Output "Identified $($oldResources.Count) resources for cleanup in $($rg.ResourceGroupName)"
        
        foreach ($resource in $oldResources) {
            Write-Output "Processing old resource: $($resource.Name) (Type: $($resource.ResourceType), Created: $($resource.CreatedTime))"
            
            if (-not $DryRun) {
                try {
                    Write-Output "Deleting resource: $($resource.Name)"
                    Remove-AzResource -ResourceId $resource.ResourceId -Force -ErrorAction Stop
                    $cleanupSummary.ResourcesDeleted++
                    Write-Output "Successfully deleted: $($resource.Name)"
                }
                catch {
                    $errorMsg = "Failed to delete resource $($resource.Name): $($_.Exception.Message)"
                    Write-Error $errorMsg
                    $cleanupSummary.Errors += $errorMsg
                }
            } else {
                Write-Output "DRY RUN: Would delete resource: $($resource.Name)"
                $cleanupSummary.ResourcesDeleted++
            }
        }
        
        # Check if resource group is empty and marked for cleanup
        if (-not $DryRun -and $rg.Tags.DeleteWhenEmpty -eq "true") {
            $remainingResources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName
            if ($remainingResources.Count -eq 0) {
                Write-Output "Resource group $($rg.ResourceGroupName) is empty and marked for deletion"
                try {
                    Remove-AzResourceGroup -Name $rg.ResourceGroupName -Force -ErrorAction Stop
                    Write-Output "Successfully deleted empty resource group: $($rg.ResourceGroupName)"
                }
                catch {
                    $errorMsg = "Failed to delete resource group $($rg.ResourceGroupName): $($_.Exception.Message)"
                    Write-Error $errorMsg
                    $cleanupSummary.Errors += $errorMsg
                }
            }
        }
    }
    catch {
        $errorMsg = "Error processing resource group $($rg.ResourceGroupName): $($_.Exception.Message)"
        Write-Error $errorMsg
        $cleanupSummary.Errors += $errorMsg
    }
}

# Output comprehensive summary
Write-Output "==================== CLEANUP SUMMARY ===================="
Write-Output "Execution Mode: $(if ($DryRun) { 'DRY RUN' } else { 'LIVE EXECUTION' })"
Write-Output "Environment Filter: $Environment"
Write-Output "Age Threshold: $DaysOld days (before $cutoffDate)"
Write-Output "Resource Groups Processed: $($cleanupSummary.ResourceGroupsProcessed)"
Write-Output "Resources Found for Cleanup: $($cleanupSummary.ResourcesFound)"
Write-Output "Resources Deleted/Would Delete: $($cleanupSummary.ResourcesDeleted)"
Write-Output "Resources Skipped: $($cleanupSummary.ResourcesSkipped)"
Write-Output "Errors Encountered: $($cleanupSummary.Errors.Count)"
Write-Output "=========================================================="

if ($cleanupSummary.Errors.Count -gt 0) {
    Write-Output "ERRORS DETAIL:"
    $cleanupSummary.Errors | ForEach-Object { Write-Output "  - $_" }
    Write-Output "=========================================================="
}

# Calculate potential cost savings (rough estimation)
if ($DryRun -and $cleanupSummary.ResourcesFound -gt 0) {
    Write-Output "COST SAVINGS ESTIMATE:"
    Write-Output "Note: This is a rough estimate. Actual savings depend on resource types and pricing."
    Write-Output "Resources that would be deleted: $($cleanupSummary.ResourcesFound)"
    Write-Output "Estimated monthly savings: Varies by resource type"
    Write-Output "Recommendation: Review resources individually for accurate cost impact"
    Write-Output "=========================================================="
}

Write-Output "Cleanup process completed successfully"
'''

// Azure Automation Account with System-Assigned Managed Identity
resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: commonTags
  properties: {
    disableLocalAuth: false
    publicNetworkAccess: true
    sku: {
      name: 'Basic'
    }
    encryption: {
      keySource: 'Microsoft.Automation'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// PowerShell Runbook for Resource Cleanup
resource cleanupRunbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: runbookName
  location: location
  tags: commonTags
  properties: {
    runbookType: 'PowerShell'
    logVerbose: true
    logProgress: true
    description: 'Automated cleanup of old Azure resources based on tags and age criteria'
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/quickstarts/microsoft.automation/101-automation-runbook-getvms/Runbooks/Get-AzureVMTutorial.ps1'
      version: '1.0.0.0'
    }
  }
}

// Schedule for Weekly Cleanup
resource cleanupSchedule 'Microsoft.Automation/automationAccounts/schedules@2023-11-01' = {
  parent: automationAccount
  name: scheduleName
  properties: {
    description: 'Weekly schedule for automated resource cleanup'
    startTime: cleanupStartTime
    frequency: 'Week'
    interval: 1
    timeZone: 'UTC'
    advancedSchedule: {
      weekDays: [
        ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][cleanupDayOfWeek]
      ]
    }
  }
}

// Job Schedule linking the runbook to the schedule
resource jobSchedule 'Microsoft.Automation/automationAccounts/jobSchedules@2023-11-01' = {
  parent: automationAccount
  name: guid(automationAccount.id, cleanupSchedule.id, runbookName)
  properties: {
    runbook: {
      name: cleanupRunbook.name
    }
    schedule: {
      name: cleanupSchedule.name
    }
    parameters: {
      DaysOld: string(defaultDaysOld)
      Environment: environment
      DryRun: string(defaultDryRun)
    }
  }
}

// Contributor role assignment for the managed identity at subscription level
resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, automationAccount.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor role
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
    description: 'Allows the Automation Account managed identity to manage resources for cleanup operations'
  }
}

// Log Analytics Workspace for monitoring (optional but recommended)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${automationAccountName}'
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Link Automation Account to Log Analytics for monitoring
resource automationLogAnalyticsLink 'Microsoft.OperationalInsights/workspaces/linkedServices@2020-08-01' = {
  parent: logAnalyticsWorkspace
  name: 'Automation'
  properties: {
    resourceId: automationAccount.id
  }
}

// Output values for reference and integration
output automationAccountName string = automationAccount.name
output automationAccountId string = automationAccount.id
output managedIdentityPrincipalId string = automationAccount.identity.principalId
output runbookName string = cleanupRunbook.name
output scheduleName string = cleanupSchedule.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output resourceGroupName string = resourceGroup().name
output cleanupStartTime string = cleanupStartTime
output deploymentTimestamp string = utcNow()

// Outputs for monitoring and validation
output automationAccountEndpoint string = 'https://management.azure.com${automationAccount.id}'
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output nextScheduledRun string = cleanupStartTime
output runbookUri string = 'https://portal.azure.com/#@/resource${automationAccount.id}/runbooks'