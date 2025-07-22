# Azure Content Delivery Solution Cleanup Script
# This script removes all resources created by the content delivery solution

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [switch]$Force = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf = $false
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to confirm action
function Confirm-Action {
    param(
        [string]$Message
    )
    
    if ($Force) {
        return $true
    }
    
    $response = Read-Host "$Message (y/N)"
    return ($response -eq "y" -or $response -eq "Y")
}

# Main cleanup script
try {
    Write-ColorOutput "Starting Azure Content Delivery Solution cleanup..." "Yellow"
    Write-ColorOutput "Subscription: $SubscriptionId" "Yellow"
    Write-ColorOutput "Resource Group: $ResourceGroupName" "Yellow"
    
    # Connect to Azure (if not already connected)
    Write-ColorOutput "Checking Azure connection..." "Cyan"
    $context = Get-AzContext
    if (-not $context) {
        Write-ColorOutput "Not connected to Azure. Please run Connect-AzAccount first." "Red"
        Connect-AzAccount
    }
    
    # Set the subscription context
    Write-ColorOutput "Setting subscription context..." "Cyan"
    Set-AzContext -SubscriptionId $SubscriptionId
    
    # Check if resource group exists
    Write-ColorOutput "Checking resource group..." "Cyan"
    $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $resourceGroup) {
        Write-ColorOutput "Resource group not found: $ResourceGroupName" "Yellow"
        Write-ColorOutput "Nothing to clean up." "Green"
        return
    }
    
    # List resources in the resource group
    Write-ColorOutput "Listing resources in resource group..." "Cyan"
    $resources = Get-AzResource -ResourceGroupName $ResourceGroupName
    
    if ($resources.Count -eq 0) {
        Write-ColorOutput "No resources found in resource group: $ResourceGroupName" "Yellow"
        
        if (Confirm-Action "Delete empty resource group?") {
            if ($WhatIf) {
                Write-ColorOutput "What-If: Would delete resource group $ResourceGroupName" "Cyan"
            }
            else {
                Remove-AzResourceGroup -Name $ResourceGroupName -Force
                Write-ColorOutput "Resource group deleted successfully!" "Green"
            }
        }
        return
    }
    
    Write-ColorOutput "Found $($resources.Count) resources:" "Yellow"
    $resources | ForEach-Object {
        Write-ColorOutput "  $($_.ResourceType): $($_.Name)" "Yellow"
    }
    
    # Warning about Azure NetApp Files
    $netAppResources = $resources | Where-Object { $_.ResourceType -like "Microsoft.NetApp/*" }
    if ($netAppResources.Count -gt 0) {
        Write-ColorOutput "`nWARNING: Azure NetApp Files resources found!" "Red"
        Write-ColorOutput "NetApp Files volumes must be deleted before capacity pools and accounts." "Red"
        Write-ColorOutput "This process may take several minutes." "Red"
    }
    
    # Warning about Front Door
    $frontDoorResources = $resources | Where-Object { $_.ResourceType -like "Microsoft.Cdn/*" }
    if ($frontDoorResources.Count -gt 0) {
        Write-ColorOutput "`nWARNING: Azure Front Door resources found!" "Red"
        Write-ColorOutput "Front Door resources are global and may take time to delete." "Red"
    }
    
    # Confirm deletion
    if (-not (Confirm-Action "`nAre you sure you want to delete ALL resources in resource group '$ResourceGroupName'?")) {
        Write-ColorOutput "Cleanup cancelled by user." "Yellow"
        return
    }
    
    if ($WhatIf) {
        Write-ColorOutput "What-If: Would delete the following resources:" "Cyan"
        $resources | ForEach-Object {
            Write-ColorOutput "  Would delete: $($_.ResourceType): $($_.Name)" "Cyan"
        }
        Write-ColorOutput "What-If: Would delete resource group: $ResourceGroupName" "Cyan"
        return
    }
    
    # Delete resources in specific order to handle dependencies
    Write-ColorOutput "Starting resource deletion..." "Cyan"
    
    # Step 1: Delete Front Door routes and security policies first
    Write-ColorOutput "Deleting Front Door routes and security policies..." "Cyan"
    $frontDoorRoutes = $resources | Where-Object { $_.ResourceType -eq "Microsoft.Cdn/profiles/afdEndpoints/routes" }
    $frontDoorSecurityPolicies = $resources | Where-Object { $_.ResourceType -eq "Microsoft.Cdn/profiles/securityPolicies" }
    
    foreach ($route in $frontDoorRoutes) {
        Write-ColorOutput "Deleting Front Door route: $($route.Name)" "Cyan"
        Remove-AzResource -ResourceId $route.ResourceId -Force
    }
    
    foreach ($policy in $frontDoorSecurityPolicies) {
        Write-ColorOutput "Deleting Front Door security policy: $($policy.Name)" "Cyan"
        Remove-AzResource -ResourceId $policy.ResourceId -Force
    }
    
    # Step 2: Delete NetApp Files volumes
    Write-ColorOutput "Deleting NetApp Files volumes..." "Cyan"
    $netAppVolumes = $resources | Where-Object { $_.ResourceType -eq "Microsoft.NetApp/netAppAccounts/capacityPools/volumes" }
    foreach ($volume in $netAppVolumes) {
        Write-ColorOutput "Deleting NetApp volume: $($volume.Name)" "Cyan"
        Remove-AzResource -ResourceId $volume.ResourceId -Force
        
        # Wait for volume deletion to complete
        do {
            Start-Sleep -Seconds 30
            $volumeStatus = Get-AzResource -ResourceId $volume.ResourceId -ErrorAction SilentlyContinue
            if (-not $volumeStatus) {
                Write-ColorOutput "Volume $($volume.Name) deleted successfully" "Green"
                break
            }
            Write-ColorOutput "Waiting for volume $($volume.Name) to be deleted..." "Yellow"
        } while ($volumeStatus)
    }
    
    # Step 3: Delete NetApp Files capacity pools
    Write-ColorOutput "Deleting NetApp Files capacity pools..." "Cyan"
    $netAppPools = $resources | Where-Object { $_.ResourceType -eq "Microsoft.NetApp/netAppAccounts/capacityPools" }
    foreach ($pool in $netAppPools) {
        Write-ColorOutput "Deleting NetApp capacity pool: $($pool.Name)" "Cyan"
        Remove-AzResource -ResourceId $pool.ResourceId -Force
        
        # Wait for pool deletion to complete
        do {
            Start-Sleep -Seconds 30
            $poolStatus = Get-AzResource -ResourceId $pool.ResourceId -ErrorAction SilentlyContinue
            if (-not $poolStatus) {
                Write-ColorOutput "Capacity pool $($pool.Name) deleted successfully" "Green"
                break
            }
            Write-ColorOutput "Waiting for capacity pool $($pool.Name) to be deleted..." "Yellow"
        } while ($poolStatus)
    }
    
    # Step 4: Delete the entire resource group (this will handle remaining resources)
    Write-ColorOutput "Deleting resource group: $ResourceGroupName" "Cyan"
    Remove-AzResourceGroup -Name $ResourceGroupName -Force
    
    Write-ColorOutput "Cleanup completed successfully!" "Green"
    Write-ColorOutput "All resources have been deleted." "Green"
    
    # Verify deletion
    Write-ColorOutput "Verifying resource group deletion..." "Cyan"
    $deletedResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $deletedResourceGroup) {
        Write-ColorOutput "Resource group deletion confirmed!" "Green"
    }
    else {
        Write-ColorOutput "Resource group still exists. Deletion may be in progress..." "Yellow"
    }
}
catch {
    Write-ColorOutput "Error occurred during cleanup:" "Red"
    Write-ColorOutput $_.Exception.Message "Red"
    
    Write-ColorOutput "`nTroubleshooting tips:" "Cyan"
    Write-ColorOutput "1. Some resources may have dependencies that prevent deletion" "Yellow"
    Write-ColorOutput "2. NetApp Files resources may require additional time to delete" "Yellow"
    Write-ColorOutput "3. Front Door resources are global and may take time to propagate" "Yellow"
    Write-ColorOutput "4. Try running the script again after a few minutes" "Yellow"
    Write-ColorOutput "5. Check the Azure portal for any remaining resources" "Yellow"
    
    exit 1
}

Write-ColorOutput "Cleanup script completed!" "Green"