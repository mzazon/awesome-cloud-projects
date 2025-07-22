# =============================================================================
# PostgreSQL Disaster Recovery Deployment Script
# =============================================================================
# This PowerShell script deploys the PostgreSQL disaster recovery solution
# using Azure Bicep templates with proper resource group management.
# =============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $true)]
    [string]$Location,
    
    [Parameter(Mandatory = $false)]
    [string]$SecondaryLocation = "West US 2",
    
    [Parameter(Mandatory = $false)]
    [string]$ParametersFile = "parameters.json",
    
    [Parameter(Mandatory = $false)]
    [string]$DeploymentName = "postgresql-dr-deployment",
    
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

try {
    Write-ColoredOutput "Starting PostgreSQL Disaster Recovery deployment..." "Green"
    
    # Set Azure subscription context
    Write-ColoredOutput "Setting Azure subscription context..." "Yellow"
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    
    # Validate parameters file exists
    if (!(Test-Path $ParametersFile)) {
        throw "Parameters file '$ParametersFile' not found."
    }
    
    Write-ColoredOutput "Using parameters file: $ParametersFile" "Yellow"
    
    # Create primary resource group if it doesn't exist
    if (!(Test-ResourceGroupExists -ResourceGroupName $ResourceGroupName)) {
        Write-ColoredOutput "Creating primary resource group: $ResourceGroupName" "Yellow"
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag @{
            Purpose = "disaster-recovery"
            Environment = "production"
            Solution = "postgresql-dr"
        } | Out-Null
    }
    else {
        Write-ColoredOutput "Primary resource group already exists: $ResourceGroupName" "Yellow"
    }
    
    # Create secondary resource group if it doesn't exist
    $secondaryResourceGroupName = "$ResourceGroupName-secondary"
    if (!(Test-ResourceGroupExists -ResourceGroupName $secondaryResourceGroupName)) {
        Write-ColoredOutput "Creating secondary resource group: $secondaryResourceGroupName" "Yellow"
        New-AzResourceGroup -Name $secondaryResourceGroupName -Location $SecondaryLocation -Tag @{
            Purpose = "disaster-recovery"
            Environment = "production"
            Solution = "postgresql-dr"
        } | Out-Null
    }
    else {
        Write-ColoredOutput "Secondary resource group already exists: $secondaryResourceGroupName" "Yellow"
    }
    
    # Prepare deployment parameters
    $deploymentParams = @{
        ResourceGroupName = $ResourceGroupName
        TemplateFile = "main.bicep"
        TemplateParameterFile = $ParametersFile
        Name = $DeploymentName
        Verbose = $true
    }
    
    # Execute deployment or what-if analysis
    if ($WhatIf) {
        Write-ColoredOutput "Performing what-if analysis..." "Yellow"
        $result = New-AzResourceGroupDeployment @deploymentParams -WhatIf
        Write-ColoredOutput "What-if analysis completed." "Green"
    }
    else {
        Write-ColoredOutput "Starting deployment..." "Yellow"
        $result = New-AzResourceGroupDeployment @deploymentParams
        
        if ($result.ProvisioningState -eq "Succeeded") {
            Write-ColoredOutput "Deployment completed successfully!" "Green"
            
            # Display deployment outputs
            Write-ColoredOutput "`nDeployment Outputs:" "Cyan"
            Write-ColoredOutput "===================" "Cyan"
            
            foreach ($output in $result.Outputs.GetEnumerator()) {
                $name = $output.Key
                $value = $output.Value.Value
                
                # Mask sensitive information
                if ($name -like "*Password*" -or $name -like "*ConnectionString*") {
                    $value = "***MASKED***"
                }
                
                Write-ColoredOutput "$name`: $value" "White"
            }
        }
        else {
            Write-ColoredOutput "Deployment failed with state: $($result.ProvisioningState)" "Red"
            throw "Deployment failed"
        }
    }
    
    Write-ColoredOutput "`nDeployment process completed!" "Green"
    
    # Provide next steps
    Write-ColoredOutput "`nNext Steps:" "Cyan"
    Write-ColoredOutput "===========" "Cyan"
    Write-ColoredOutput "1. Verify PostgreSQL servers are running and accessible" "White"
    Write-ColoredOutput "2. Test read replica connectivity and replication lag" "White"
    Write-ColoredOutput "3. Validate backup policies and retention settings" "White"
    Write-ColoredOutput "4. Review monitoring alerts and action groups" "White"
    Write-ColoredOutput "5. Test disaster recovery automation runbooks" "White"
    Write-ColoredOutput "6. Update application connection strings if needed" "White"
    
}
catch {
    Write-ColoredOutput "Error occurred during deployment:" "Red"
    Write-ColoredOutput $_.Exception.Message "Red"
    
    # Provide troubleshooting information
    Write-ColoredOutput "`nTroubleshooting:" "Yellow"
    Write-ColoredOutput "===============" "Yellow"
    Write-ColoredOutput "1. Check Azure subscription permissions" "White"
    Write-ColoredOutput "2. Verify resource quotas and limits" "White"
    Write-ColoredOutput "3. Review deployment logs in Azure portal" "White"
    Write-ColoredOutput "4. Validate parameters file syntax" "White"
    Write-ColoredOutput "5. Check region availability for selected services" "White"
    
    exit 1
}

Write-ColoredOutput "`nDeployment script completed." "Green"