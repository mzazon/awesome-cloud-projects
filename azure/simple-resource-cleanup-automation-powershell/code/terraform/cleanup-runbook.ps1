# Azure Resource Cleanup PowerShell Runbook
# This runbook automatically identifies and removes unused Azure resources
# based on configurable criteria like tags, creation dates, and resource types

param(
    [int]$DaysOld = ${default_days_old},
    [string]$Environment = "${default_environment}",
    [bool]$DryRun = ${default_dry_run}
)

try {
    Write-Output "=== Azure Resource Cleanup Runbook Started ==="
    Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
    Write-Output "Parameters:"
    Write-Output "  - DaysOld: $DaysOld"
    Write-Output "  - Environment: $Environment"
    Write-Output "  - DryRun: $DryRun"
    Write-Output ""

    # Ensure no context inheritance and connect using managed identity
    Write-Output "Authenticating using managed identity..."
    Disable-AzContextAutosave -Scope Process
    $AzureContext = (Connect-AzAccount -Identity).context
    $AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext
    
    Write-Output "Successfully authenticated to subscription: $($AzureContext.Subscription.Name)"
    Write-Output "Subscription ID: $($AzureContext.Subscription.Id)"
    Write-Output ""

    # Calculate cutoff date for resource age
    $cutoffDate = (Get-Date).AddDays(-$DaysOld)
    Write-Output "Resources created before $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss UTC')) will be considered for cleanup"
    Write-Output ""

    # Initialize cleanup summary
    $cleanupSummary = @{
        ResourceGroupsProcessed = 0
        ResourcesFound = 0
        ResourcesEligible = 0
        ResourcesDeleted = 0
        ResourcesProtected = 0
        Errors = @()
        ProcessedResourceGroups = @()
        EligibleResources = @()
        ProtectedResources = @()
        DeletedResources = @()
    }

    # Get all resource groups with specified environment tag and AutoCleanup enabled
    Write-Output "Searching for resource groups with Environment='$Environment' and AutoCleanup='true'..."
    
    $resourceGroups = Get-AzResourceGroup | Where-Object {
        $_.Tags.Environment -eq $Environment -and
        $_.Tags.AutoCleanup -eq "true"
    }

    if ($resourceGroups.Count -eq 0) {
        Write-Output "No resource groups found matching criteria (Environment='$Environment', AutoCleanup='true')"
        Write-Output "Ensure resource groups have the required tags to enable cleanup"
        return $cleanupSummary
    }

    Write-Output "Found $($resourceGroups.Count) resource group(s) matching cleanup criteria:"
    foreach ($rg in $resourceGroups) {
        Write-Output "  - $($rg.ResourceGroupName) (Location: $($rg.Location))"
    }
    Write-Output ""

    # Process each eligible resource group
    foreach ($rg in $resourceGroups) {
        Write-Output "Processing resource group: $($rg.ResourceGroupName)"
        $cleanupSummary.ResourceGroupsProcessed++
        $cleanupSummary.ProcessedResourceGroups += $rg.ResourceGroupName
        
        try {
            # Get all resources in the resource group
            $allResources = Get-AzResource -ResourceGroupName $rg.ResourceGroupName
            Write-Output "  Found $($allResources.Count) total resources in resource group"
            
            if ($allResources.Count -eq 0) {
                Write-Output "  No resources found in resource group"
                continue
            }

            $cleanupSummary.ResourcesFound += $allResources.Count

            # Filter resources based on cleanup criteria
            $eligibleResources = $allResources | Where-Object {
                # Check if resource is protected by DoNotDelete tag
                $isProtected = $_.Tags.DoNotDelete -eq "true"
                
                # Check if resource has creation time and is older than cutoff
                $isOldEnough = $_.CreatedTime -ne $null -and [DateTime]$_.CreatedTime -lt $cutoffDate
                
                # Resource is eligible if it's not protected and is old enough
                return -not $isProtected -and $isOldEnough
            }

            # Separate protected resources for reporting
            $protectedResources = $allResources | Where-Object {
                $_.Tags.DoNotDelete -eq "true"
            }

            $cleanupSummary.ResourcesEligible += $eligibleResources.Count
            $cleanupSummary.ResourcesProtected += $protectedResources.Count

            # Report on protected resources
            if ($protectedResources.Count -gt 0) {
                Write-Output "  Found $($protectedResources.Count) protected resource(s) (DoNotDelete=true):"
                foreach ($resource in $protectedResources) {
                    Write-Output "    - $($resource.Name) ($($resource.ResourceType)) - PROTECTED"
                    $cleanupSummary.ProtectedResources += @{
                        Name = $resource.Name
                        Type = $resource.ResourceType
                        ResourceGroup = $rg.ResourceGroupName
                        CreatedTime = $resource.CreatedTime
                    }
                }
            }

            # Process eligible resources for cleanup
            if ($eligibleResources.Count -eq 0) {
                Write-Output "  No resources eligible for cleanup in this resource group"
                continue
            }

            Write-Output "  Found $($eligibleResources.Count) resource(s) eligible for cleanup:"
            
            foreach ($resource in $eligibleResources) {
                $resourceInfo = @{
                    Name = $resource.Name
                    Type = $resource.ResourceType
                    ResourceGroup = $rg.ResourceGroupName
                    CreatedTime = $resource.CreatedTime
                    ResourceId = $resource.ResourceId
                }
                
                Write-Output "    - $($resource.Name) (Type: $($resource.ResourceType), Created: $($resource.CreatedTime))"
                $cleanupSummary.EligibleResources += $resourceInfo
                
                if ($DryRun) {
                    Write-Output "      DRY RUN: Would delete this resource"
                } else {
                    Write-Output "      Attempting to delete resource..."
                    try {
                        # Attempt to delete the resource
                        Remove-AzResource -ResourceId $resource.ResourceId -Force -Confirm:$false
                        Write-Output "      ✅ Successfully deleted: $($resource.Name)"
                        $cleanupSummary.ResourcesDeleted++
                        $cleanupSummary.DeletedResources += $resourceInfo
                    }
                    catch {
                        $errorMsg = "Failed to delete resource '$($resource.Name)': $($_.Exception.Message)"
                        Write-Error "      ❌ $errorMsg"
                        $cleanupSummary.Errors += $errorMsg
                    }
                }
            }
        }
        catch {
            $errorMsg = "Error processing resource group '$($rg.ResourceGroupName)': $($_.Exception.Message)"
            Write-Error $errorMsg
            $cleanupSummary.Errors += $errorMsg
        }
        
        Write-Output ""
    }

    # Output comprehensive summary
    Write-Output "=== CLEANUP SUMMARY ==="
    Write-Output "Execution Mode: $(if ($DryRun) { 'DRY RUN' } else { 'LIVE EXECUTION' })"
    Write-Output "Resource Groups Processed: $($cleanupSummary.ResourceGroupsProcessed)"
    Write-Output "Total Resources Found: $($cleanupSummary.ResourcesFound)"
    Write-Output "Resources Eligible for Cleanup: $($cleanupSummary.ResourcesEligible)"
    Write-Output "Resources Protected: $($cleanupSummary.ResourcesProtected)"
    Write-Output "Resources Deleted: $($cleanupSummary.ResourcesDeleted)"
    Write-Output "Errors Encountered: $($cleanupSummary.Errors.Count)"
    Write-Output ""

    if ($cleanupSummary.ProcessedResourceGroups.Count -gt 0) {
        Write-Output "Processed Resource Groups:"
        foreach ($rgName in $cleanupSummary.ProcessedResourceGroups) {
            Write-Output "  - $rgName"
        }
        Write-Output ""
    }

    if ($cleanupSummary.DeletedResources.Count -gt 0) {
        Write-Output "Successfully Deleted Resources:"
        foreach ($resource in $cleanupSummary.DeletedResources) {
            Write-Output "  - $($resource.Name) ($($resource.Type)) from $($resource.ResourceGroup)"
        }
        Write-Output ""
    }

    if ($cleanupSummary.ProtectedResources.Count -gt 0) {
        Write-Output "Protected Resources (Skipped):"
        foreach ($resource in $cleanupSummary.ProtectedResources) {
            Write-Output "  - $($resource.Name) ($($resource.Type)) from $($resource.ResourceGroup)"
        }
        Write-Output ""
    }

    if ($cleanupSummary.Errors.Count -gt 0) {
        Write-Output "Errors Encountered:"
        foreach ($error in $cleanupSummary.Errors) {
            Write-Output "  - $error"
        }
        Write-Output ""
    }

    # Cost savings estimation (rough calculation)
    if ($cleanupSummary.ResourcesDeleted -gt 0 -and -not $DryRun) {
        $estimatedMonthlySavings = $cleanupSummary.ResourcesDeleted * 10  # Rough estimate of $10/month per resource
        Write-Output "Estimated Monthly Cost Savings: ~`$$estimatedMonthlySavings USD"
        Write-Output "(This is a rough estimate - actual savings may vary significantly)"
        Write-Output ""
    }

    Write-Output "=== CLEANUP COMPLETED ==="
    Write-Output "Completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
    
    return $cleanupSummary
}
catch {
    $criticalError = "CRITICAL ERROR in cleanup runbook: $($_.Exception.Message)"
    Write-Error $criticalError
    Write-Output ""
    Write-Output "=== CLEANUP FAILED ==="
    Write-Output "Failed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
    Write-Output "Error: $criticalError"
    
    # Return error summary
    return @{
        ResourceGroupsProcessed = 0
        ResourcesFound = 0
        ResourcesEligible = 0
        ResourcesDeleted = 0
        ResourcesProtected = 0
        Errors = @($criticalError)
        Status = "Failed"
    }
}