# Azure Content Delivery Solution Deployment Script
# This script deploys the high-performance multi-regional content delivery solution
# using Azure Front Door Premium and Azure NetApp Files

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory = $false)]
    [string]$ParametersFile = "main.parameters.json",
    
    [Parameter(Mandatory = $false)]
    [string]$DeploymentName = "content-delivery-deployment-$(Get-Date -Format 'yyyyMMdd-HHmm')",
    
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

# Main deployment script
try {
    Write-ColorOutput "Starting Azure Content Delivery Solution deployment..." "Green"
    Write-ColorOutput "Subscription: $SubscriptionId" "Yellow"
    Write-ColorOutput "Resource Group: $ResourceGroupName" "Yellow"
    Write-ColorOutput "Location: $Location" "Yellow"
    Write-ColorOutput "Parameters File: $ParametersFile" "Yellow"
    Write-ColorOutput "Deployment Name: $DeploymentName" "Yellow"
    
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
    
    # Create resource group if it doesn't exist
    Write-ColorOutput "Checking resource group..." "Cyan"
    $resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $resourceGroup) {
        Write-ColorOutput "Creating resource group: $ResourceGroupName" "Cyan"
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location
    }
    else {
        Write-ColorOutput "Resource group already exists: $ResourceGroupName" "Yellow"
    }
    
    # Register required resource providers
    Write-ColorOutput "Registering required resource providers..." "Cyan"
    $providers = @(
        "Microsoft.NetApp",
        "Microsoft.Cdn",
        "Microsoft.Network",
        "Microsoft.OperationalInsights",
        "Microsoft.Insights"
    )
    
    foreach ($provider in $providers) {
        Write-ColorOutput "Registering $provider..." "Cyan"
        Register-AzResourceProvider -ProviderNamespace $provider
    }
    
    # Wait for resource providers to be registered
    Write-ColorOutput "Waiting for resource providers to be registered..." "Cyan"
    foreach ($provider in $providers) {
        do {
            $registration = Get-AzResourceProvider -ProviderNamespace $provider
            $registrationState = $registration.RegistrationState
            if ($registrationState -eq "Registered") {
                Write-ColorOutput "$provider is registered" "Green"
                break
            }
            else {
                Write-ColorOutput "$provider registration state: $registrationState" "Yellow"
                Start-Sleep -Seconds 10
            }
        } while ($registrationState -ne "Registered")
    }
    
    # Validate the parameters file exists
    if (-not (Test-Path $ParametersFile)) {
        Write-ColorOutput "Parameters file not found: $ParametersFile" "Red"
        exit 1
    }
    
    # Deploy the Bicep template
    Write-ColorOutput "Starting deployment..." "Cyan"
    
    $deploymentParameters = @{
        ResourceGroupName     = $ResourceGroupName
        TemplateFile         = "main.bicep"
        TemplateParameterFile = $ParametersFile
        Name                 = $DeploymentName
        Verbose              = $true
    }
    
    if ($WhatIf) {
        Write-ColorOutput "Running What-If deployment..." "Cyan"
        $result = New-AzResourceGroupDeployment @deploymentParameters -WhatIf
        Write-ColorOutput "What-If deployment completed successfully!" "Green"
    }
    else {
        Write-ColorOutput "Running actual deployment..." "Cyan"
        $result = New-AzResourceGroupDeployment @deploymentParameters
        
        if ($result.ProvisioningState -eq "Succeeded") {
            Write-ColorOutput "Deployment completed successfully!" "Green"
            
            # Display outputs
            Write-ColorOutput "Deployment Outputs:" "Cyan"
            $result.Outputs.Keys | ForEach-Object {
                $key = $_
                $value = $result.Outputs[$key].Value
                Write-ColorOutput "  $key : $value" "Yellow"
            }
        }
        else {
            Write-ColorOutput "Deployment failed with state: $($result.ProvisioningState)" "Red"
            exit 1
        }
    }
    
    Write-ColorOutput "Script completed successfully!" "Green"
}
catch {
    Write-ColorOutput "Error occurred during deployment:" "Red"
    Write-ColorOutput $_.Exception.Message "Red"
    exit 1
}

# Post-deployment verification
if (-not $WhatIf) {
    Write-ColorOutput "Running post-deployment verification..." "Cyan"
    
    # Check Front Door endpoint
    $frontDoorEndpoint = $result.Outputs.frontDoorEndpointHostname.Value
    Write-ColorOutput "Front Door Endpoint: https://$frontDoorEndpoint" "Yellow"
    
    # Check resource group resources
    Write-ColorOutput "Listing deployed resources..." "Cyan"
    $resources = Get-AzResource -ResourceGroupName $ResourceGroupName
    $resources | ForEach-Object {
        Write-ColorOutput "  $($_.ResourceType): $($_.Name)" "Yellow"
    }
    
    Write-ColorOutput "Post-deployment verification completed!" "Green"
    
    # Display next steps
    Write-ColorOutput "`nNext Steps:" "Cyan"
    Write-ColorOutput "1. Configure your origin servers to mount the Azure NetApp Files volumes" "Yellow"
    Write-ColorOutput "2. Upload your content to the NetApp Files volumes" "Yellow"
    Write-ColorOutput "3. Test the Front Door endpoint: https://$frontDoorEndpoint" "Yellow"
    Write-ColorOutput "4. Monitor the solution using Azure Monitor and Log Analytics" "Yellow"
    Write-ColorOutput "5. Configure custom domains if needed" "Yellow"
}