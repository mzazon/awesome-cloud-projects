# Azure VM Cost Optimization Runbook
# This PowerShell script optimizes VM sizes based on utilization metrics and cost analysis

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$VMName,
    
    [Parameter(Mandatory=$false)]
    [string]$NewSize,
    
    [Parameter(Mandatory=$false)]
    [int]$CPUThreshold = 5,
    
    [Parameter(Mandatory=$false)]
    [int]$MemoryThreshold = 20,
    
    [Parameter(Mandatory=$false)]
    [bool]$DryRun = $true
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

# Function to get VM utilization metrics from Azure Monitor
function Get-VMUtilization {
    param(
        [string]$ResourceGroupName,
        [string]$VMName,
        [int]$DaysBack = 7
    )
    
    try {
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
        $vmResourceId = $vm.Id
        
        $endTime = Get-Date
        $startTime = $endTime.AddDays(-$DaysBack)
        
        # Get CPU utilization
        $cpuMetrics = Get-AzMetric -ResourceId $vmResourceId `
            -MetricName "Percentage CPU" `
            -StartTime $startTime `
            -EndTime $endTime `
            -TimeGrain "01:00:00" `
            -WarningAction SilentlyContinue
        
        $avgCPU = if ($cpuMetrics.Data.Count -gt 0) {
            ($cpuMetrics.Data | Measure-Object -Property Average -Average).Average
        } else { 0 }
        
        # Get memory utilization (requires Azure Monitor agent)
        $memoryMetrics = Get-AzMetric -ResourceId $vmResourceId `
            -MetricName "Available Memory Bytes" `
            -StartTime $startTime `
            -EndTime $endTime `
            -TimeGrain "01:00:00" `
            -WarningAction SilentlyContinue
        
        $avgMemoryUsedPercent = if ($memoryMetrics.Data.Count -gt 0 -and $vm.HardwareProfile.VmSize) {
            # Calculate memory usage percentage (simplified calculation)
            $vmSizeInfo = Get-AzVMSize -Location $vm.Location | Where-Object {$_.Name -eq $vm.HardwareProfile.VmSize}
            if ($vmSizeInfo) {
                $totalMemoryMB = $vmSizeInfo.MemoryInMB
                $avgAvailableBytes = ($memoryMetrics.Data | Measure-Object -Property Average -Average).Average
                $avgUsedPercent = (1 - ($avgAvailableBytes / ($totalMemoryMB * 1024 * 1024))) * 100
                [Math]::Max(0, $avgUsedPercent)
            } else { 50 } # Default if unable to determine
        } else { 50 } # Default if no metrics available
        
        return @{
            VMName = $VMName
            ResourceGroup = $ResourceGroupName
            AverageCPU = [Math]::Round($avgCPU, 2)
            AverageMemoryUsed = [Math]::Round($avgMemoryUsedPercent, 2)
            CurrentSize = $vm.HardwareProfile.VmSize
            Location = $vm.Location
            PowerState = (Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Status).Statuses | 
                        Where-Object {$_.Code -like "PowerState/*"} | 
                        Select-Object -ExpandProperty DisplayStatus
        }
    }
    catch {
        Write-Error "Failed to get utilization metrics for VM $VMName`: $($_.Exception.Message)"
        return $null
    }
}

# Function to suggest optimal VM size based on utilization
function Get-OptimalVMSize {
    param(
        [string]$CurrentSize,
        [string]$Location,
        [double]$CPUUtilization,
        [double]$MemoryUtilization
    )
    
    try {
        $availableSizes = Get-AzVMSize -Location $Location | Sort-Object NumberOfCores, MemoryInMB
        $currentSizeInfo = $availableSizes | Where-Object {$_.Name -eq $CurrentSize}
        
        if (-not $currentSizeInfo) {
            Write-Warning "Current VM size $CurrentSize not found in available sizes"
            return $CurrentSize
        }
        
        # Logic for size optimization
        if ($CPUUtilization -lt $CPUThreshold -and $MemoryUtilization -lt $MemoryThreshold) {
            # Find smaller size with similar VM family
            $family = ($CurrentSize -split '_')[0]
            $smallerSizes = $availableSizes | Where-Object {
                $_.Name -like "$family*" -and 
                $_.NumberOfCores -lt $currentSizeInfo.NumberOfCores -and
                $_.MemoryInMB -lt $currentSizeInfo.MemoryInMB
            } | Sort-Object NumberOfCores -Descending
            
            if ($smallerSizes.Count -gt 0) {
                return $smallerSizes[0].Name
            }
        }
        elseif ($CPUUtilization -gt 80 -or $MemoryUtilization -gt 80) {
            # Find larger size with similar VM family
            $family = ($CurrentSize -split '_')[0]
            $largerSizes = $availableSizes | Where-Object {
                $_.Name -like "$family*" -and 
                $_.NumberOfCores -gt $currentSizeInfo.NumberOfCores
            } | Sort-Object NumberOfCores
            
            if ($largerSizes.Count -gt 0) {
                return $largerSizes[0].Name
            }
        }
        
        return $CurrentSize  # No change needed
    }
    catch {
        Write-Error "Failed to determine optimal VM size: $($_.Exception.Message)"
        return $CurrentSize
    }
}

# Function to resize VM
function Resize-VM {
    param(
        [string]$ResourceGroupName,
        [string]$VMName,
        [string]$NewSize,
        [bool]$DryRun = $true
    )
    
    try {
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
        
        if ($vm.HardwareProfile.VmSize -eq $NewSize) {
            Write-Output "VM $VMName is already size $NewSize. No action needed."
            return $true
        }
        
        if ($DryRun) {
            Write-Output "[DRY RUN] Would resize VM $VMName from $($vm.HardwareProfile.VmSize) to $NewSize"
            return $true
        }
        
        Write-Output "Resizing VM $VMName from $($vm.HardwareProfile.VmSize) to $NewSize..."
        
        # Stop the VM
        Write-Output "Stopping VM $VMName..."
        Stop-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -Force
        
        # Resize the VM
        Write-Output "Changing VM size to $NewSize..."
        $vm.HardwareProfile.VmSize = $NewSize
        Update-AzVM -VM $vm -ResourceGroupName $ResourceGroupName
        
        # Start the VM
        Write-Output "Starting VM $VMName..."
        Start-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
        
        Write-Output "✅ Successfully resized VM $VMName to $NewSize"
        return $true
    }
    catch {
        Write-Error "Failed to resize VM $VMName`: $($_.Exception.Message)"
        return $false
    }
}

# Main execution logic
try {
    Write-Output "Starting VM cost optimization process..."
    Write-Output "CPU Threshold: $CPUThreshold%"
    Write-Output "Memory Threshold: $MemoryThreshold%"
    Write-Output "Dry Run Mode: $DryRun"
    
    $vmsToOptimize = @()
    
    if ($ResourceGroupName -and $VMName) {
        # Optimize specific VM
        $vmsToOptimize += @{ResourceGroup = $ResourceGroupName; VMName = $VMName}
    }
    else {
        # Find all VMs in subscription for optimization
        Write-Output "Discovering VMs for optimization across all resource groups..."
        $allVMs = Get-AzVM
        
        foreach ($vm in $allVMs) {
            $vmsToOptimize += @{
                ResourceGroup = $vm.ResourceGroupName
                VMName = $vm.Name
            }
        }
        
        Write-Output "Found $($vmsToOptimize.Count) VMs for evaluation"
    }
    
    $optimizationResults = @()
    
    foreach ($vmInfo in $vmsToOptimize) {
        Write-Output "`nEvaluating VM: $($vmInfo.VMName) in resource group: $($vmInfo.ResourceGroup)"
        
        # Get VM utilization metrics
        $utilization = Get-VMUtilization -ResourceGroupName $vmInfo.ResourceGroup -VMName $vmInfo.VMName
        
        if ($utilization) {
            Write-Output "Current utilization - CPU: $($utilization.AverageCPU)%, Memory: $($utilization.AverageMemoryUsed)%"
            Write-Output "Current size: $($utilization.CurrentSize), Power state: $($utilization.PowerState)"
            
            # Skip if VM is not running
            if ($utilization.PowerState -ne "VM running") {
                Write-Output "VM is not running. Skipping optimization."
                continue
            }
            
            # Get optimal size recommendation
            $optimalSize = if ($NewSize) { $NewSize } else {
                Get-OptimalVMSize -CurrentSize $utilization.CurrentSize `
                                 -Location $utilization.Location `
                                 -CPUUtilization $utilization.AverageCPU `
                                 -MemoryUtilization $utilization.AverageMemoryUsed
            }
            
            $result = @{
                VMName = $vmInfo.VMName
                ResourceGroup = $vmInfo.ResourceGroup
                CurrentSize = $utilization.CurrentSize
                RecommendedSize = $optimalSize
                CPUUtilization = $utilization.AverageCPU
                MemoryUtilization = $utilization.AverageMemoryUsed
                OptimizationNeeded = ($utilization.CurrentSize -ne $optimalSize)
                Success = $false
            }
            
            if ($result.OptimizationNeeded) {
                Write-Output "Recommendation: Resize from $($utilization.CurrentSize) to $optimalSize"
                
                # Perform the resize
                $resizeSuccess = Resize-VM -ResourceGroupName $vmInfo.ResourceGroup `
                                          -VMName $vmInfo.VMName `
                                          -NewSize $optimalSize `
                                          -DryRun $DryRun
                
                $result.Success = $resizeSuccess
            }
            else {
                Write-Output "VM size is already optimal. No action needed."
                $result.Success = $true
            }
            
            $optimizationResults += $result
        }
        else {
            Write-Warning "Could not retrieve utilization data for VM $($vmInfo.VMName)"
        }
    }
    
    # Summary report
    Write-Output "`n=== VM OPTIMIZATION SUMMARY ==="
    Write-Output "Total VMs evaluated: $($optimizationResults.Count)"
    Write-Output "VMs requiring optimization: $(($optimizationResults | Where-Object {$_.OptimizationNeeded}).Count)"
    Write-Output "Successful optimizations: $(($optimizationResults | Where-Object {$_.Success -and $_.OptimizationNeeded}).Count)"
    
    if ($DryRun) {
        Write-Output "`n⚠️  DRY RUN MODE - No actual changes were made"
        Write-Output "Set DryRun parameter to `$false to apply optimizations"
    }
    
    # Detailed results
    foreach ($result in $optimizationResults) {
        if ($result.OptimizationNeeded) {
            $status = if ($result.Success) { "✅ SUCCESS" } else { "❌ FAILED" }
            Write-Output "$status - $($result.VMName): $($result.CurrentSize) → $($result.RecommendedSize)"
        }
    }
    
    Write-Output "`nVM optimization process completed successfully."
}
catch {
    Write-Error "VM optimization process failed: $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    exit 1
}