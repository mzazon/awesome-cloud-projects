# =============================================================================
# PostgreSQL Disaster Recovery Cleanup Script
# =============================================================================
# This PowerShell script removes all resources created by the PostgreSQL 
# disaster recovery solution, including both primary and secondary regions.
# =============================================================================

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
function Write-ColoredOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# Function to check if resource group exists
function Test-ResourceGroupExists {
    param([string]$ResourceGroupName)
    
    try {
        $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
        return $rg -ne $null
    }
    catch {
        return $false
    }
}

# Function to get user confirmation
function Get-UserConfirmation {
    param([string]$Message)
    
    if ($Force) {
        return $true
    }
    
    $response = Read-Host "$Message (y/N)"
    return $response -match "^[Yy]$"
}

# Function to remove resource group safely
function Remove-ResourceGroupSafely {
    param(
        [string]$ResourceGroupName,
        [string]$Description
    )
    
    if (!(Test-ResourceGroupExists -ResourceGroupName $ResourceGroupName)) {
        Write-ColoredOutput "$Description does not exist: $ResourceGroupName" "Yellow"
        return
    }
    
    Write-ColoredOutput "Found $Description`: $ResourceGroupName" "Yellow"
    
    # List resources in the group
    $resources = Get-AzResource -ResourceGroupName $ResourceGroupName
    if ($resources) {
        Write-ColoredOutput "Resources to be deleted:" "Cyan"
        foreach ($resource in $resources) {
            Write-ColoredOutput "  - $($resource.Name) ($($resource.ResourceType))" "White"
        }
    }
    else {
        Write-ColoredOutput "No resources found in $ResourceGroupName" "Yellow"
    }
    
    if ($WhatIf) {
        Write-ColoredOutput "WHAT-IF: Would delete resource group $ResourceGroupName" "Magenta"
        return
    }
    
    if (Get-UserConfirmation "Delete $Description '$ResourceGroupName' and all its resources?") {
        Write-ColoredOutput "Deleting $Description`: $ResourceGroupName..." "Red"
        
        # Delete specific resource types in order to avoid dependency issues
        Write-ColoredOutput "Removing PostgreSQL servers..." "Yellow"
        $pgServers = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.DBforPostgreSQL/flexibleServers"
        foreach ($server in $pgServers) {
            Write-ColoredOutput "  Deleting PostgreSQL server: $($server.Name)" "Yellow"
            Remove-AzResource -ResourceId $server.ResourceId -Force
        }
        
        Write-ColoredOutput "Removing backup vaults..." "Yellow"
        $backupVaults = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.DataProtection/backupVaults"
        foreach ($vault in $backupVaults) {
            Write-ColoredOutput "  Deleting backup vault: $($vault.Name)" "Yellow"
            Remove-AzResource -ResourceId $vault.ResourceId -Force
        }
        
        Write-ColoredOutput "Removing automation accounts..." "Yellow"
        $automationAccounts = Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.Automation/automationAccounts"
        foreach ($account in $automationAccounts) {
            Write-ColoredOutput "  Deleting automation account: $($account.Name)" "Yellow"
            Remove-AzResource -ResourceId $account.ResourceId -Force
        }
        
        # Remove the entire resource group
        Write-ColoredOutput "Removing resource group: $ResourceGroupName" "Red"
        Remove-AzResourceGroup -Name $ResourceGroupName -Force
        
        Write-ColoredOutput "$Description deleted successfully!" "Green"
    }
    else {
        Write-ColoredOutput "Skipping deletion of $Description" "Yellow"
    }
}

try {
    Write-ColoredOutput "Starting PostgreSQL Disaster Recovery cleanup..." "Red"
    
    # Set Azure subscription context
    Write-ColoredOutput "Setting Azure subscription context..." "Yellow"
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    
    # Define resource group names
    $primaryResourceGroupName = $ResourceGroupName
    $secondaryResourceGroupName = "$ResourceGroupName-secondary"
    
    # Warning message
    Write-ColoredOutput "`nWARNING: This script will permanently delete all resources!" "Red"
    Write-ColoredOutput "This action cannot be undone." "Red"
    Write-ColoredOutput "Resources to be deleted:" "Red"
    Write-ColoredOutput "- Primary resource group: $primaryResourceGroupName" "Red"
    Write-ColoredOutput "- Secondary resource group: $secondaryResourceGroupName" "Red"
    
    if ($WhatIf) {
        Write-ColoredOutput "`nRunning in WHAT-IF mode - no resources will be deleted." "Magenta"
    }
    else {
        Write-ColoredOutput "`nUse -WhatIf to see what would be deleted without actually deleting." "Yellow"
    }
    
    if (!$WhatIf -and !$Force) {
        if (!(Get-UserConfirmation "`nDo you want to proceed with the cleanup?")) {
            Write-ColoredOutput "Cleanup cancelled by user." "Yellow"
            exit 0
        }
    }
    
    # Remove secondary resource group first (contains read replica)
    Write-ColoredOutput "`nProcessing secondary resource group..." "Cyan"
    Remove-ResourceGroupSafely -ResourceGroupName $secondaryResourceGroupName -Description "secondary resource group"
    
    # Remove primary resource group
    Write-ColoredOutput "`nProcessing primary resource group..." "Cyan"
    Remove-ResourceGroupSafely -ResourceGroupName $primaryResourceGroupName -Description "primary resource group"
    
    if (!$WhatIf) {
        Write-ColoredOutput "`nCleanup completed successfully!" "Green"
        
        # Verify cleanup
        Write-ColoredOutput "`nVerifying cleanup..." "Yellow"
        $remainingPrimary = Test-ResourceGroupExists -ResourceGroupName $primaryResourceGroupName
        $remainingSecondary = Test-ResourceGroupExists -ResourceGroupName $secondaryResourceGroupName
        
        if (!$remainingPrimary -and !$remainingSecondary) {
            Write-ColoredOutput "All resource groups have been successfully deleted." "Green"
        }
        else {
            Write-ColoredOutput "Some resource groups may still exist:" "Yellow"
            if ($remainingPrimary) {
                Write-ColoredOutput "- Primary resource group still exists: $primaryResourceGroupName" "Yellow"
            }
            if ($remainingSecondary) {
                Write-ColoredOutput "- Secondary resource group still exists: $secondaryResourceGroupName" "Yellow"
            }
        }
        
        # Cost savings message
        Write-ColoredOutput "`nCost Impact:" "Cyan"
        Write-ColoredOutput "============" "Cyan"
        Write-ColoredOutput "All PostgreSQL servers, storage accounts, and monitoring resources have been deleted." "Green"
        Write-ColoredOutput "This will stop all ongoing charges related to this disaster recovery solution." "Green"
        Write-ColoredOutput "Backup retention may still apply for geo-redundant backups." "Yellow"
    }
    
}
catch {
    Write-ColoredOutput "Error occurred during cleanup:" "Red"
    Write-ColoredOutput $_.Exception.Message "Red"
    
    # Provide troubleshooting information
    Write-ColoredOutput "`nTroubleshooting:" "Yellow"
    Write-ColoredOutput "===============" "Yellow"
    Write-ColoredOutput "1. Check Azure subscription permissions" "White"
    Write-ColoredOutput "2. Verify resource dependencies and locks" "White"
    Write-ColoredOutput "3. Review resource deletion logs in Azure portal" "White"
    Write-ColoredOutput "4. Some resources may require manual deletion" "White"
    Write-ColoredOutput "5. Check for backup retention policies" "White"
    
    exit 1
}

Write-ColoredOutput "`nCleanup script completed." "Green"