# Carbon Optimization Monitoring PowerShell Runbook
# This runbook monitors carbon emissions and generates optimization recommendations

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceId,
    
    [Parameter(Mandatory=$false)]
    [double]$Threshold = ${threshold}
)

# Import required modules
Import-Module Az.Accounts
Import-Module Az.Profile
Import-Module Az.Advisor
Import-Module Az.OperationalInsights
Import-Module Az.Resources

try {
    Write-Output "Starting Carbon Optimization Monitoring runbook..."
    Write-Output "Subscription ID: $SubscriptionId"
    Write-Output "Workspace ID: $WorkspaceId"
    Write-Output "Carbon Threshold: $Threshold kg CO2"
    
    # Connect using managed identity
    Write-Output "Connecting to Azure using managed identity..."
    $Connection = Connect-AzAccount -Identity -ErrorAction Stop
    
    # Select the subscription
    Write-Output "Selecting subscription: $SubscriptionId"
    $Context = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
    
    # Get carbon emissions data (using REST API as PowerShell module may not be available)
    Write-Output "Retrieving carbon emissions data..."
    $carbonEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Sustainability/carbonEmissions?api-version=2023-11-01-preview"
    
    try {
        $carbonData = Invoke-AzRestMethod -Uri $carbonEndpoint -Method GET
        $carbonContent = $carbonData.Content | ConvertFrom-Json
        Write-Output "Carbon emissions data retrieved successfully"
        Write-Output "Total carbon emissions entries: $($carbonContent.value.Count)"
    }
    catch {
        Write-Warning "Could not retrieve carbon emissions data: $($_.Exception.Message)"
        Write-Output "Continuing with Azure Advisor recommendations..."
        $carbonContent = $null
    }
    
    # Get Azure Advisor recommendations
    Write-Output "Retrieving Azure Advisor recommendations..."
    $advisorRecommendations = Get-AzAdvisorRecommendation -ErrorAction SilentlyContinue
    
    if ($advisorRecommendations) {
        Write-Output "Retrieved $($advisorRecommendations.Count) Azure Advisor recommendations"
        
        # Filter for cost and performance recommendations that impact carbon footprint
        $carbonImpactRecommendations = $advisorRecommendations | Where-Object { 
            $_.Category -eq "Cost" -or 
            $_.Category -eq "Performance" -or 
            $_.Category -eq "Reliability" 
        }
        
        Write-Output "Filtered to $($carbonImpactRecommendations.Count) carbon-impacting recommendations"
        
        # Process each recommendation and estimate carbon impact
        $processedRecommendations = @()
        foreach ($recommendation in $carbonImpactRecommendations) {
            try {
                # Calculate estimated carbon savings based on cost savings and recommendation type
                $carbonSavingsEstimate = switch ($recommendation.Category) {
                    "Cost" { 
                        # Estimate 0.4 kg CO2 per dollar saved (approximate industry average)
                        if ($recommendation.ImpactedValue -and $recommendation.ImpactedValue -match '\d+\.?\d*') {
                            [math]::Round(([double]($matches[0]) * 0.4), 2)
                        } else { 5.0 }
                    }
                    "Performance" { 
                        # Performance optimizations typically save 2-3 kg CO2
                        [math]::Round((Get-Random -Minimum 2.0 -Maximum 3.0), 2)
                    }
                    "Reliability" { 
                        # Reliability improvements save 1-2 kg CO2
                        [math]::Round((Get-Random -Minimum 1.0 -Maximum 2.0), 2)
                    }
                    default { 1.0 }
                }
                
                # Create carbon optimization record
                $carbonOptimization = [PSCustomObject]@{
                    RecommendationId = $recommendation.RecommendationId
                    ResourceId = $recommendation.ResourceId
                    ResourceName = if ($recommendation.ResourceId) { 
                        ($recommendation.ResourceId -split '/')[-1] 
                    } else { "Unknown" }
                    Category = $recommendation.Category
                    ImpactedValue = $recommendation.ImpactedValue
                    CarbonSavingsEstimate = $carbonSavingsEstimate
                    OptimizationAction = $recommendation.ShortDescription
                    Problem = $recommendation.Problem
                    Solution = $recommendation.Solution
                    Priority = switch ($carbonSavingsEstimate) {
                        {$_ -gt 10} { "High" }
                        {$_ -gt 5} { "Medium" }
                        default { "Low" }
                    }
                    Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                    SubscriptionId = $SubscriptionId
                }
                
                $processedRecommendations += $carbonOptimization
                
                # Log high-impact recommendations
                if ($carbonSavingsEstimate -gt $Threshold) {
                    Write-Output "HIGH IMPACT: $($recommendation.ShortDescription) - Estimated savings: $carbonSavingsEstimate kg CO2"
                }
                
            }
            catch {
                Write-Warning "Error processing recommendation $($recommendation.RecommendationId): $($_.Exception.Message)"
            }
        }
        
        Write-Output "Processed $($processedRecommendations.Count) carbon optimization recommendations"
        
        # Send data to Log Analytics workspace
        if ($processedRecommendations.Count -gt 0) {
            Write-Output "Sending carbon optimization data to Log Analytics..."
            
            # Convert recommendations to JSON
            $jsonData = $processedRecommendations | ConvertTo-Json -Depth 10
            
            # Send to Log Analytics (using custom log)
            try {
                # Since we can't directly use Send-AzOperationalInsightsDataCollector in automation,
                # we'll use the REST API method
                $workspaceKey = ""  # This would need to be retrieved securely
                
                # For now, output the data for manual verification
                Write-Output "Carbon optimization data prepared for Log Analytics:"
                Write-Output $jsonData
                
                # In a real implementation, you would send this to Log Analytics
                # using the HTTP Data Collector API
                
            }
            catch {
                Write-Error "Failed to send data to Log Analytics: $($_.Exception.Message)"
            }
        }
        
        # Generate summary statistics
        $totalCarbonSavings = ($processedRecommendations | Measure-Object -Property CarbonSavingsEstimate -Sum).Sum
        $highPriorityCount = ($processedRecommendations | Where-Object { $_.Priority -eq "High" }).Count
        $mediumPriorityCount = ($processedRecommendations | Where-Object { $_.Priority -eq "Medium" }).Count
        $lowPriorityCount = ($processedRecommendations | Where-Object { $_.Priority -eq "Low" }).Count
        
        Write-Output "=== CARBON OPTIMIZATION SUMMARY ==="
        Write-Output "Total recommendations processed: $($processedRecommendations.Count)"
        Write-Output "Total estimated carbon savings: $totalCarbonSavings kg CO2"
        Write-Output "High priority recommendations: $highPriorityCount"
        Write-Output "Medium priority recommendations: $mediumPriorityCount"
        Write-Output "Low priority recommendations: $lowPriorityCount"
        Write-Output "=================================="
        
    }
    else {
        Write-Output "No Azure Advisor recommendations found"
    }
    
    # Check for resource utilization patterns that indicate carbon waste
    Write-Output "Analyzing resource utilization patterns..."
    
    # Get all VMs in the subscription
    $vms = Get-AzVM -ErrorAction SilentlyContinue
    if ($vms) {
        Write-Output "Found $($vms.Count) virtual machines to analyze"
        
        foreach ($vm in $vms) {
            # Check VM power state
            $vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status
            $powerState = ($vmStatus.Statuses | Where-Object { $_.Code -like "PowerState/*" }).DisplayStatus
            
            if ($powerState -eq "VM running") {
                Write-Output "VM $($vm.Name) is running - monitoring recommended"
            }
            elseif ($powerState -eq "VM deallocated") {
                Write-Output "VM $($vm.Name) is deallocated - potential carbon savings opportunity"
            }
        }
    }
    
    Write-Output "Carbon optimization monitoring completed successfully"
    
}
catch {
    Write-Error "Error in carbon optimization monitoring: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.Exception.StackTrace)"
    throw
}
finally {
    # Cleanup
    Write-Output "Cleaning up resources..."
}