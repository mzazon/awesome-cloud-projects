# Carbon Optimization PowerShell Runbook
# This runbook analyzes carbon emissions data and executes optimization actions
# based on Azure Carbon Optimization recommendations and configurable thresholds

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$KeyVaultName
)

# Initialize logging and error handling
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

Write-Output "=== Starting Carbon Optimization Analysis ==="
Write-Output "Subscription ID: $SubscriptionId"
Write-Output "Resource Group: $ResourceGroupName"
Write-Output "Key Vault: $KeyVaultName"
Write-Output "Execution Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"

try {
    # Connect using managed identity
    Write-Output "Connecting to Azure using managed identity..."
    $null = Connect-AzAccount -Identity
    $null = Set-AzContext -SubscriptionId $SubscriptionId
    Write-Output "✅ Successfully connected to Azure subscription"
    
    # Retrieve configuration from Key Vault
    Write-Output "Retrieving carbon optimization configuration from Key Vault..."
    try {
        $carbonThreshold = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "carbon-threshold-kg" -AsPlainText
        $costThreshold = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "cost-threshold-usd" -AsPlainText
        $minCarbonReduction = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "min-carbon-reduction-percent" -AsPlainText
        $cpuThreshold = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "cpu-utilization-threshold" -AsPlainText
        
        Write-Output "✅ Configuration retrieved successfully:"
        Write-Output "  Carbon threshold: $carbonThreshold kg CO2e/month"
        Write-Output "  Cost threshold: $costThreshold USD/month"
        Write-Output "  Minimum carbon reduction: $minCarbonReduction%"
        Write-Output "  CPU utilization threshold: $cpuThreshold%"
    }
    catch {
        Write-Error "Failed to retrieve configuration from Key Vault: $($_.Exception.Message)"
        return
    }
    
    # Get access token for Azure Management API
    Write-Output "Obtaining access token for Azure Management API..."
    $context = Get-AzContext
    $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id, $null, "https://management.azure.com/", $null).AccessToken
    
    if (-not $token) {
        Write-Error "Failed to obtain access token for Azure Management API"
        return
    }
    Write-Output "✅ Access token obtained successfully"
    
    # Prepare headers for REST API calls
    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type' = 'application/json'
    }
    
    # Get carbon optimization recommendations from Azure Carbon Optimization API
    Write-Output "Retrieving carbon optimization recommendations..."
    $recommendationsUri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.CarbonOptimization/carbonOptimizationRecommendations?api-version=2023-10-01-preview"
    
    try {
        $response = Invoke-RestMethod -Uri $recommendationsUri -Headers $headers -Method GET -ErrorAction Stop
        $recommendations = $response.value
        
        if (-not $recommendations -or $recommendations.Count -eq 0) {
            Write-Output "ℹ️ No carbon optimization recommendations found for this subscription"
            Write-Output "This could be because:"
            Write-Output "  - No resources are currently generating sufficient carbon emissions"
            Write-Output "  - Azure Carbon Optimization is still analyzing your workloads"
            Write-Output "  - Your resources are already optimally configured"
            return
        }
        
        Write-Output "✅ Retrieved $($recommendations.Count) carbon optimization recommendations"
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $statusDescription = $_.Exception.Response.StatusDescription
        
        if ($statusCode -eq 404) {
            Write-Output "ℹ️ Carbon Optimization API returned 404 - service may not be available in this region yet"
            Write-Output "Proceeding with simulated optimization based on resource analysis..."
            
            # Fallback: Analyze existing resources for optimization opportunities
            Write-Output "Analyzing existing virtual machines for optimization opportunities..."
            $vms = Get-AzVM -Status
            
            foreach ($vm in $vms) {
                if ($vm.PowerState -eq "VM running") {
                    Write-Output "Analyzing VM: $($vm.Name) in resource group: $($vm.ResourceGroupName)"
                    
                    # Get VM metrics (simplified analysis for demo)
                    $vmDetail = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name
                    $vmSize = $vmDetail.HardwareProfile.VmSize
                    
                    # Simulate carbon and cost analysis
                    $estimatedMonthlyCost = switch -Regex ($vmSize) {
                        "Standard_B.*" { Get-Random -Minimum 50 -Maximum 150 }
                        "Standard_D.*" { Get-Random -Minimum 100 -Maximum 300 }
                        "Standard_F.*" { Get-Random -Minimum 80 -Maximum 250 }
                        default { Get-Random -Minimum 75 -Maximum 200 }
                    }
                    
                    $estimatedCarbonEmissions = [math]::Round($estimatedMonthlyCost * 0.5, 2) # Simplified carbon calculation
                    
                    Write-Output "  Current estimated monthly cost: $$estimatedMonthlyCost"
                    Write-Output "  Current estimated carbon emissions: $estimatedCarbonEmissions kg CO2e/month"
                    
                    # Check if VM meets optimization thresholds (simplified logic)
                    if ($estimatedCarbonEmissions -gt [double]$carbonThreshold -and $estimatedMonthlyCost -gt [double]$costThreshold) {
                        Write-Output "  🔍 VM meets optimization thresholds - potential candidate for optimization"
                        Write-Output "  Recommended actions: Consider rightsizing or scheduling during low-carbon periods"
                    }
                    else {
                        Write-Output "  ✅ VM does not exceed optimization thresholds"
                    }
                }
            }
            return
        }
        else {
            Write-Error "Failed to retrieve carbon optimization recommendations. Status: $statusCode - $statusDescription. Error: $($_.Exception.Message)"
            return
        }
    }
    
    # Analyze each recommendation
    Write-Output "Analyzing carbon optimization recommendations..."
    $optimizationActions = 0
    $totalCarbonSavings = 0
    $totalCostSavings = 0
    
    foreach ($recommendation in $recommendations) {
        try {
            $properties = $recommendation.properties
            $extendedProperties = $properties.extendedProperties
            $resourceMetadata = $properties.resourceMetadata
            
            $carbonSavings = [double]$extendedProperties.PotentialMonthlyCarbonSavings
            $costSavings = [double]$extendedProperties.savingsAmount
            $resourceId = $resourceMetadata.resourceId
            $recommendationType = $extendedProperties.recommendationType
            
            Write-Output ""
            Write-Output "📋 Analyzing recommendation for resource:"
            Write-Output "  Resource ID: $resourceId"
            Write-Output "  Recommendation Type: $recommendationType"
            Write-Output "  Potential carbon savings: $carbonSavings kg CO2e/month"
            Write-Output "  Potential cost savings: $$costSavings USD/month"
            
            # Check if recommendation meets configured thresholds
            $meetsThresholds = ($carbonSavings -ge [double]$carbonThreshold) -and ($costSavings -ge [double]$costThreshold)
            
            if ($meetsThresholds) {
                Write-Output "  ✅ Recommendation meets optimization thresholds - executing action"
                
                # Parse resource information
                $resourceParts = $resourceId -split '/'
                if ($resourceParts.Count -ge 9) {
                    $resourceGroupName = $resourceParts[4]
                    $resourceName = $resourceParts[8]
                    $resourceType = $resourceParts[7]
                    
                    Write-Output "  Resource Group: $resourceGroupName"
                    Write-Output "  Resource Name: $resourceName"
                    Write-Output "  Resource Type: $resourceType"
                    
                    # Execute optimization based on recommendation type
                    switch ($recommendationType.ToLower()) {
                        "shutdown" {
                            Write-Output "  🔄 Executing shutdown recommendation..."
                            try {
                                if ($resourceType -eq "virtualMachines") {
                                    $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $resourceName -ErrorAction SilentlyContinue
                                    if ($vm -and $vm.ProvisioningState -eq "Succeeded") {
                                        Write-Output "  Stopping virtual machine: $resourceName"
                                        $null = Stop-AzVM -ResourceGroupName $resourceGroupName -Name $resourceName -Force -NoWait
                                        Write-Output "  ✅ Virtual machine stop initiated successfully"
                                        $optimizationActions++
                                        $totalCarbonSavings += $carbonSavings
                                        $totalCostSavings += $costSavings
                                    }
                                    else {
                                        Write-Output "  ⚠️ Virtual machine not found or not in running state"
                                    }
                                }
                                else {
                                    Write-Output "  ⚠️ Shutdown action not supported for resource type: $resourceType"
                                }
                            }
                            catch {
                                Write-Warning "Failed to execute shutdown action: $($_.Exception.Message)"
                            }
                        }
                        
                        "resize" {
                            Write-Output "  🔄 Executing resize recommendation..."
                            try {
                                if ($resourceType -eq "virtualMachines") {
                                    $targetSku = $extendedProperties.targetSku
                                    if ($targetSku) {
                                        Write-Output "  Resizing virtual machine $resourceName to $targetSku"
                                        $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $resourceName
                                        $vm.HardwareProfile.VmSize = $targetSku
                                        $null = Update-AzVM -ResourceGroupName $resourceGroupName -VM $vm -NoWait
                                        Write-Output "  ✅ Virtual machine resize initiated successfully"
                                        $optimizationActions++
                                        $totalCarbonSavings += $carbonSavings
                                        $totalCostSavings += $costSavings
                                    }
                                    else {
                                        Write-Output "  ⚠️ Target SKU not specified in recommendation"
                                    }
                                }
                                else {
                                    Write-Output "  ⚠️ Resize action not supported for resource type: $resourceType"
                                }
                            }
                            catch {
                                Write-Warning "Failed to execute resize action: $($_.Exception.Message)"
                            }
                        }
                        
                        "schedule" {
                            Write-Output "  🔄 Analyzing scheduling recommendation..."
                            Write-Output "  ℹ️ Scheduling optimization requires custom automation based on business requirements"
                            Write-Output "  Recommendation: Schedule workload during low carbon intensity periods"
                        }
                        
                        default {
                            Write-Output "  ℹ️ Recommendation type '$recommendationType' requires manual analysis"
                            Write-Output "  Consider implementing custom automation for this optimization type"
                        }
                    }
                }
                else {
                    Write-Warning "Unable to parse resource ID format: $resourceId"
                }
            }
            else {
                Write-Output "  ⏭️ Recommendation does not meet configured thresholds - skipping action"
                Write-Output "    Required carbon savings: ≥$carbonThreshold kg CO2e/month (actual: $carbonSavings)"
                Write-Output "    Required cost savings: ≥$$costThreshold USD/month (actual: $$costSavings)"
            }
        }
        catch {
            Write-Warning "Error processing recommendation: $($_.Exception.Message)"
        }
    }
    
    # Summary of optimization actions
    Write-Output ""
    Write-Output "=== Carbon Optimization Summary ==="
    Write-Output "Total recommendations analyzed: $($recommendations.Count)"
    Write-Output "Optimization actions executed: $optimizationActions"
    Write-Output "Total potential carbon savings: $totalCarbonSavings kg CO2e/month"
    Write-Output "Total potential cost savings: $$totalCostSavings USD/month"
    
    if ($optimizationActions -gt 0) {
        $carbonReductionPercent = [math]::Round(($totalCarbonSavings / [double]$carbonThreshold) * 100, 2)
        Write-Output "Carbon reduction percentage: $carbonReductionPercent%"
        Write-Output "✅ Carbon optimization completed successfully"
    }
    else {
        Write-Output "ℹ️ No optimization actions were required at this time"
        Write-Output "This indicates your resources may already be well-optimized"
    }
    
    # Log optimization results for monitoring
    $optimizationResult = @{
        timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'
        subscriptionId = $SubscriptionId
        recommendationsAnalyzed = $recommendations.Count
        actionsExecuted = $optimizationActions
        carbonSavings = $totalCarbonSavings
        costSavings = $totalCostSavings
        thresholds = @{
            carbonThresholdKg = $carbonThreshold
            costThresholdUsd = $costThreshold
            minCarbonReductionPercent = $minCarbonReduction
        }
    }
    
    Write-Output ""
    Write-Output "Carbon optimization results logged for monitoring and reporting"
    Write-Output ($optimizationResult | ConvertTo-Json -Depth 3)
}
catch {
    Write-Error "Carbon optimization runbook failed: $($_.Exception.Message)"
    Write-Output "Stack trace: $($_.ScriptStackTrace)"
    throw
}
finally {
    Write-Output ""
    Write-Output "=== Carbon Optimization Analysis Completed ==="
    Write-Output "End time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
}