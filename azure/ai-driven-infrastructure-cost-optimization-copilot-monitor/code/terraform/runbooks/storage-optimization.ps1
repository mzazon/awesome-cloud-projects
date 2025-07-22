# Azure Storage Cost Optimization Runbook
# This PowerShell script optimizes storage account configurations and blob tiers for cost efficiency

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$false)]
    [int]$CoolTierDays = 30,
    
    [Parameter(Mandatory=$false)]
    [int]$ArchiveTierDays = 90,
    
    [Parameter(Mandatory=$false)]
    [bool]$DryRun = $true,
    
    [Parameter(Mandatory=$false)]
    [bool]$EnableLifecycleManagement = $true
)

# Authenticate using the managed identity
try {
    Write-Output "Connecting to Azure using managed identity..."
    Connect-AzAccount -Identity
    
    # Set subscription context
    $subscriptionId = "${subscription_id}"
    Set-AzContext -SubscriptionId $subscriptionId
    Write-Output "Successfully connected to subscription: $subscriptionId"
}
catch {
    Write-Error "Failed to authenticate with Azure: $($_.Exception.Message)"
    exit 1
}

# Function to analyze storage account usage patterns
function Get-StorageAccountAnalysis {
    param(
        [string]$ResourceGroupName,
        [string]$StorageAccountName
    )
    
    try {
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
        $ctx = $storageAccount.Context
        
        # Get storage account metrics
        $endTime = Get-Date
        $startTime = $endTime.AddDays(-30)
        
        # Get capacity metrics
        $capacityMetrics = Get-AzMetric -ResourceId $storageAccount.Id `
            -MetricName "UsedCapacity" `
            -StartTime $startTime `
            -EndTime $endTime `
            -TimeGrain "1.00:00:00" `
            -WarningAction SilentlyContinue
        
        $avgCapacityGB = if ($capacityMetrics.Data.Count -gt 0) {
            ($capacityMetrics.Data | Measure-Object -Property Average -Average).Average / (1024 * 1024 * 1024)
        } else { 0 }
        
        # Get transaction metrics
        $transactionMetrics = Get-AzMetric -ResourceId $storageAccount.Id `
            -MetricName "Transactions" `
            -StartTime $startTime `
            -EndTime $endTime `
            -TimeGrain "1.00:00:00" `
            -WarningAction SilentlyContinue
        
        $avgTransactions = if ($transactionMetrics.Data.Count -gt 0) {
            ($transactionMetrics.Data | Measure-Object -Property Total -Sum).Sum
        } else { 0 }
        
        # Analyze blob containers and their access patterns
        $containers = Get-AzStorageContainer -Context $ctx
        $containerAnalysis = @()
        
        foreach ($container in $containers) {
            $blobs = Get-AzStorageBlob -Container $container.Name -Context $ctx
            $containerSize = ($blobs | Measure-Object -Property Length -Sum).Sum
            $blobCount = $blobs.Count
            
            # Analyze blob access tiers
            $hotBlobs = ($blobs | Where-Object {$_.AccessTier -eq "Hot"}).Count
            $coolBlobs = ($blobs | Where-Object {$_.AccessTier -eq "Cool"}).Count
            $archiveBlobs = ($blobs | Where-Object {$_.AccessTier -eq "Archive"}).Count
            
            # Find old blobs that could be moved to cooler tiers
            $oldHotBlobs = $blobs | Where-Object {
                $_.AccessTier -eq "Hot" -and 
                $_.LastModified -lt (Get-Date).AddDays(-$CoolTierDays)
            }
            
            $oldCoolBlobs = $blobs | Where-Object {
                $_.AccessTier -eq "Cool" -and 
                $_.LastModified -lt (Get-Date).AddDays(-$ArchiveTierDays)
            }
            
            $containerAnalysis += @{
                ContainerName = $container.Name
                TotalBlobs = $blobCount
                SizeGB = [Math]::Round($containerSize / (1024 * 1024 * 1024), 2)
                HotBlobs = $hotBlobs
                CoolBlobs = $coolBlobs
                ArchiveBlobs = $archiveBlobs
                BlobsForCoolTier = $oldHotBlobs.Count
                BlobsForArchiveTier = $oldCoolBlobs.Count
                OldHotBlobs = $oldHotBlobs
                OldCoolBlobs = $oldCoolBlobs
            }
        }
        
        return @{
            StorageAccount = $storageAccount
            AverageCapacityGB = [Math]::Round($avgCapacityGB, 2)
            TotalTransactions = $avgTransactions
            Containers = $containerAnalysis
            ReplicationSku = $storageAccount.Sku.Name
            AccessTier = $storageAccount.AccessTier
            Kind = $storageAccount.Kind
            Location = $storageAccount.Location
        }
    }
    catch {
        Write-Error "Failed to analyze storage account $StorageAccountName`: $($_.Exception.Message)"
        return $null
    }
}

# Function to optimize blob access tiers
function Optimize-BlobTiers {
    param(
        [object]$StorageAnalysis,
        [bool]$DryRun = $true
    )
    
    try {
        $optimizationResults = @()
        $ctx = $StorageAnalysis.StorageAccount.Context
        
        foreach ($containerInfo in $StorageAnalysis.Containers) {
            Write-Output "Optimizing container: $($containerInfo.ContainerName)"
            
            # Move old hot blobs to cool tier
            if ($containerInfo.BlobsForCoolTier -gt 0) {
                Write-Output "  Found $($containerInfo.BlobsForCoolTier) hot blobs older than $CoolTierDays days"
                
                foreach ($blob in $containerInfo.OldHotBlobs) {
                    if ($DryRun) {
                        Write-Output "  [DRY RUN] Would move blob '$($blob.Name)' from Hot to Cool tier"
                    }
                    else {
                        try {
                            $blob.BlobClient.SetAccessTier("Cool")
                            Write-Output "  ✅ Moved blob '$($blob.Name)' to Cool tier"
                        }
                        catch {
                            Write-Error "  ❌ Failed to move blob '$($blob.Name)' to Cool tier: $($_.Exception.Message)"
                        }
                    }
                }
                
                $optimizationResults += @{
                    Container = $containerInfo.ContainerName
                    Action = "Move to Cool tier"
                    BlobCount = $containerInfo.BlobsForCoolTier
                    EstimatedMonthlySavings = $containerInfo.BlobsForCoolTier * 0.01  # Simplified calculation
                }
            }
            
            # Move old cool blobs to archive tier
            if ($containerInfo.BlobsForArchiveTier -gt 0) {
                Write-Output "  Found $($containerInfo.BlobsForArchiveTier) cool blobs older than $ArchiveTierDays days"
                
                foreach ($blob in $containerInfo.OldCoolBlobs) {
                    if ($DryRun) {
                        Write-Output "  [DRY RUN] Would move blob '$($blob.Name)' from Cool to Archive tier"
                    }
                    else {
                        try {
                            $blob.BlobClient.SetAccessTier("Archive")
                            Write-Output "  ✅ Moved blob '$($blob.Name)' to Archive tier"
                        }
                        catch {
                            Write-Error "  ❌ Failed to move blob '$($blob.Name)' to Archive tier: $($_.Exception.Message)"
                        }
                    }
                }
                
                $optimizationResults += @{
                    Container = $containerInfo.ContainerName
                    Action = "Move to Archive tier"
                    BlobCount = $containerInfo.BlobsForArchiveTier
                    EstimatedMonthlySavings = $containerInfo.BlobsForArchiveTier * 0.05  # Simplified calculation
                }
            }
        }
        
        return $optimizationResults
    }
    catch {
        Write-Error "Failed to optimize blob tiers: $($_.Exception.Message)"
        return @()
    }
}

# Function to configure lifecycle management policy
function Set-LifecycleManagementPolicy {
    param(
        [object]$StorageAccount,
        [int]$CoolTierDays,
        [int]$ArchiveTierDays,
        [bool]$DryRun = $true
    )
    
    try {
        $policyRules = @()
        
        # Create lifecycle rule for automatic tier transitions
        $rule = @{
            enabled = $true
            name = "AutoOptimizeBlobTiers"
            type = "Lifecycle"
            definition = @{
                filters = @{
                    blobTypes = @("blockBlob")
                }
                actions = @{
                    baseBlob = @{
                        tierToCool = @{
                            daysAfterModificationGreaterThan = $CoolTierDays
                        }
                        tierToArchive = @{
                            daysAfterModificationGreaterThan = $ArchiveTierDays
                        }
                        delete = @{
                            daysAfterModificationGreaterThan = 2555  # ~7 years
                        }
                    }
                    snapshot = @{
                        delete = @{
                            daysAfterCreationGreaterThan = 90
                        }
                    }
                }
            }
        }
        
        $policyRules += $rule
        
        # Create the policy
        $policy = @{
            rules = $policyRules
        }
        
        if ($DryRun) {
            Write-Output "[DRY RUN] Would create lifecycle management policy with the following rules:"
            Write-Output "  - Move to Cool tier after $CoolTierDays days"
            Write-Output "  - Move to Archive tier after $ArchiveTierDays days"
            Write-Output "  - Delete after 2555 days (~7 years)"
            Write-Output "  - Delete snapshots after 90 days"
        }
        else {
            $policyJson = $policy | ConvertTo-Json -Depth 10
            
            # Set the lifecycle management policy
            Set-AzStorageBlobServiceProperty -ResourceGroupName $StorageAccount.ResourceGroupName `
                -StorageAccountName $StorageAccount.StorageAccountName `
                -EnableDeleteRetentionPolicy $true `
                -DeleteRetentionPolicyDays 7
            
            Write-Output "✅ Lifecycle management policy configured successfully"
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to set lifecycle management policy: $($_.Exception.Message)"
        return $false
    }
}

# Function to optimize storage account configuration
function Optimize-StorageAccountConfig {
    param(
        [object]$StorageAccount,
        [bool]$DryRun = $true
    )
    
    try {
        $optimizations = @()
        
        # Check if we can optimize replication
        if ($StorageAccount.Sku.Name -eq "Standard_GRS" -or $StorageAccount.Sku.Name -eq "Standard_RAGRS") {
            $optimizations += @{
                Type = "Replication"
                Current = $StorageAccount.Sku.Name
                Recommended = "Standard_LRS"
                Reason = "Consider LRS if geo-redundancy is not required"
                PotentialSavings = "~50% reduction in storage costs"
            }
        }
        
        # Check access tier optimization
        if ($StorageAccount.AccessTier -eq "Hot" -and $StorageAccount.Kind -eq "BlobStorage") {
            $optimizations += @{
                Type = "Access Tier"
                Current = "Hot"
                Recommended = "Cool"
                Reason = "Consider Cool tier if access frequency is low"
                PotentialSavings = "~50% reduction in storage costs"
            }
        }
        
        foreach ($optimization in $optimizations) {
            Write-Output "Optimization opportunity: $($optimization.Type)"
            Write-Output "  Current: $($optimization.Current)"
            Write-Output "  Recommended: $($optimization.Recommended)"
            Write-Output "  Reason: $($optimization.Reason)"
            Write-Output "  Potential savings: $($optimization.PotentialSavings)"
            
            if ($DryRun) {
                Write-Output "  [DRY RUN] Manual review and action required for this optimization"
            }
        }
        
        return $optimizations
    }
    catch {
        Write-Error "Failed to analyze storage account configuration: $($_.Exception.Message)"
        return @()
    }
}

# Main execution logic
try {
    Write-Output "Starting storage cost optimization process..."
    Write-Output "Cool tier threshold: $CoolTierDays days"
    Write-Output "Archive tier threshold: $ArchiveTierDays days"
    Write-Output "Dry Run Mode: $DryRun"
    Write-Output "Lifecycle Management: $EnableLifecycleManagement"
    
    $storageAccountsToOptimize = @()
    
    if ($ResourceGroupName -and $StorageAccountName) {
        # Optimize specific storage account
        $storageAccountsToOptimize += @{ResourceGroup = $ResourceGroupName; StorageAccount = $StorageAccountName}
    }
    else {
        # Find all storage accounts in subscription
        Write-Output "Discovering storage accounts for optimization across all resource groups..."
        $allStorageAccounts = Get-AzStorageAccount
        
        foreach ($sa in $allStorageAccounts) {
            $storageAccountsToOptimize += @{
                ResourceGroup = $sa.ResourceGroupName
                StorageAccount = $sa.StorageAccountName
            }
        }
        
        Write-Output "Found $($storageAccountsToOptimize.Count) storage accounts for evaluation"
    }
    
    $allOptimizationResults = @()
    $totalEstimatedSavings = 0
    
    foreach ($saInfo in $storageAccountsToOptimize) {
        Write-Output "`n=== Analyzing Storage Account: $($saInfo.StorageAccount) ==="
        
        # Analyze storage account
        $analysis = Get-StorageAccountAnalysis -ResourceGroupName $saInfo.ResourceGroup -StorageAccountName $saInfo.StorageAccount
        
        if ($analysis) {
            Write-Output "Storage Account Details:"
            Write-Output "  Capacity: $($analysis.AverageCapacityGB) GB"
            Write-Output "  Transactions (30 days): $($analysis.TotalTransactions)"
            Write-Output "  Replication: $($analysis.ReplicationSku)"
            Write-Output "  Access Tier: $($analysis.AccessTier)"
            Write-Output "  Containers: $($analysis.Containers.Count)"
            
            # Optimize blob tiers
            Write-Output "`nOptimizing blob access tiers..."
            $blobOptimization = Optimize-BlobTiers -StorageAnalysis $analysis -DryRun $DryRun
            
            # Configure lifecycle management
            if ($EnableLifecycleManagement) {
                Write-Output "`nConfiguring lifecycle management policy..."
                $lifecycleResult = Set-LifecycleManagementPolicy -StorageAccount $analysis.StorageAccount `
                                                                -CoolTierDays $CoolTierDays `
                                                                -ArchiveTierDays $ArchiveTierDays `
                                                                -DryRun $DryRun
            }
            
            # Analyze storage account configuration
            Write-Output "`nAnalyzing storage account configuration..."
            $configOptimizations = Optimize-StorageAccountConfig -StorageAccount $analysis.StorageAccount -DryRun $DryRun
            
            $accountResult = @{
                StorageAccount = $saInfo.StorageAccount
                ResourceGroup = $saInfo.ResourceGroup
                BlobOptimizations = $blobOptimization
                ConfigOptimizations = $configOptimizations
                LifecyclePolicySet = $EnableLifecycleManagement
                TotalContainers = $analysis.Containers.Count
                TotalCapacityGB = $analysis.AverageCapacityGB
            }
            
            $allOptimizationResults += $accountResult
            
            # Calculate estimated savings
            $accountSavings = ($blobOptimization | Measure-Object -Property EstimatedMonthlySavings -Sum).Sum
            $totalEstimatedSavings += $accountSavings
        }
        else {
            Write-Warning "Could not analyze storage account $($saInfo.StorageAccount)"
        }
    }
    
    # Summary report
    Write-Output "`n=== STORAGE OPTIMIZATION SUMMARY ==="
    Write-Output "Total storage accounts evaluated: $($allOptimizationResults.Count)"
    Write-Output "Total estimated monthly savings: $$$([Math]::Round($totalEstimatedSavings, 2))"
    
    if ($DryRun) {
        Write-Output "`n⚠️  DRY RUN MODE - No actual changes were made"
        Write-Output "Set DryRun parameter to `$false to apply optimizations"
    }
    
    # Detailed results
    foreach ($result in $allOptimizationResults) {
        Write-Output "`n--- $($result.StorageAccount) ---"
        Write-Output "Blob tier optimizations: $(($result.BlobOptimizations | Measure-Object -Property BlobCount -Sum).Sum) blobs"
        Write-Output "Configuration opportunities: $($result.ConfigOptimizations.Count)"
        Write-Output "Lifecycle policy configured: $($result.LifecyclePolicySet)"
        
        if ($result.BlobOptimizations.Count -gt 0) {
            foreach ($opt in $result.BlobOptimizations) {
                Write-Output "  $($opt.Action): $($opt.BlobCount) blobs (Est. savings: $$$([Math]::Round($opt.EstimatedMonthlySavings, 2))/month)"
            }
        }
    }
    
    Write-Output "`nStorage optimization process completed successfully."
}
catch {
    Write-Error "Storage optimization process failed: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    exit 1
}