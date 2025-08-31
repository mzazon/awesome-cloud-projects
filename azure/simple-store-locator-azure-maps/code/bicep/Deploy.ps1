# ========================================================================
# Azure Maps Store Locator - PowerShell Deployment Script
# ========================================================================
# This script automates the deployment of Azure Maps infrastructure
# for the store locator application using Bicep templates.
#
# Usage:
#   .\Deploy.ps1 -Environment <env> -ResourceGroup <rg> -Location <location>
#
# Examples:
#   .\Deploy.ps1
#   .\Deploy.ps1 -Environment dev -ResourceGroup rg-storemaps-dev -Location eastus
#   .\Deploy.ps1 -Environment prod -ResourceGroup rg-storemaps-prod -Location eastus
# ========================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "test", "staging", "prod")]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "rg-storemaps-demo",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory = $false)]
    [switch]$WhatIf,
    
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

# ========================================================================
# CONFIGURATION
# ========================================================================

$DefaultMapsAccountPrefix = "mapstore"
$SubscriptionId = $null
$DeploymentName = "maps-store-locator-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# ========================================================================
# HELPER FUNCTIONS
# ========================================================================

function Write-InfoMessage {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Blue
}

function Write-SuccessMessage {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-WarningMessage {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-HeaderMessage {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host $Message -ForegroundColor Blue
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host ""
}

function Show-Usage {
    Write-Host "Azure Maps Store Locator - PowerShell Deployment Script" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "SYNOPSIS" -ForegroundColor Yellow
    Write-Host "    Deploys Azure Maps infrastructure for the store locator application"
    Write-Host ""
    Write-Host "SYNTAX" -ForegroundColor Yellow
    Write-Host "    .\Deploy.ps1 [-Environment <string>] [-ResourceGroup <string>] [-Location <string>] [-WhatIf] [-Help]"
    Write-Host ""
    Write-Host "PARAMETERS" -ForegroundColor Yellow
    Write-Host "    -Environment      Environment name (dev, test, staging, prod) [Default: dev]"
    Write-Host "    -ResourceGroup    Azure resource group name [Default: rg-storemaps-demo]"
    Write-Host "    -Location         Azure region [Default: eastus]"
    Write-Host "    -WhatIf           Show what would be deployed without actually deploying"
    Write-Host "    -Help             Show this help message"
    Write-Host ""
    Write-Host "EXAMPLES" -ForegroundColor Yellow
    Write-Host "    .\Deploy.ps1"
    Write-Host "        Deploy to dev environment with default settings"
    Write-Host ""
    Write-Host "    .\Deploy.ps1 -Environment prod -ResourceGroup rg-storemaps-prod -Location westus2"
    Write-Host "        Deploy to production environment in West US 2"
    Write-Host ""
    Write-Host "    .\Deploy.ps1 -WhatIf"
    Write-Host "        Preview deployment without making changes"
    Write-Host ""
    Write-Host "ENVIRONMENT-SPECIFIC FEATURES" -ForegroundColor Yellow
    Write-Host "    dev:      Basic configuration with local development CORS rules"
    Write-Host "    prod:     Enhanced security, system identity, additional regions"
}

function Test-Prerequisites {
    Write-HeaderMessage "Validating Prerequisites"
    
    # Check if Azure PowerShell is installed
    try {
        $azVersion = Get-Module Az -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $azVersion) {
            Write-ErrorMessage "Azure PowerShell (Az module) is not installed."
            Write-InfoMessage "Install it with: Install-Module -Name Az -Repository PSGallery -Force"
            return $false
        }
        Write-SuccessMessage "Azure PowerShell is installed (version: $($azVersion.Version))"
    }
    catch {
        Write-ErrorMessage "Error checking Azure PowerShell installation: $($_.Exception.Message)"
        return $false
    }
    
    # Check if logged in to Azure
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-ErrorMessage "Not logged in to Azure. Please run 'Connect-AzAccount' first."
            return $false
        }
        Write-SuccessMessage "Logged in to Azure"
        Write-InfoMessage "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
        $script:SubscriptionId = $context.Subscription.Id
    }
    catch {
        Write-ErrorMessage "Error checking Azure login status: $($_.Exception.Message)"
        return $false
    }
    
    return $true
}

function New-MapsAccountName {
    param([string]$Environment)
    
    $suffix = -join ((1..6) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    return "$DefaultMapsAccountPrefix-$Environment-$suffix"
}

function Test-ResourceGroup {
    param([string]$ResourceGroupName)
    
    try {
        $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
        return $null -ne $rg
    }
    catch {
        return $false
    }
}

function New-ResourceGroupIfNotExists {
    param(
        [string]$ResourceGroupName,
        [string]$Location
    )
    
    if (Test-ResourceGroup -ResourceGroupName $ResourceGroupName) {
        Write-SuccessMessage "Resource group exists: $ResourceGroupName"
        return $true
    }
    else {
        Write-WarningMessage "Resource group does not exist: $ResourceGroupName"
        
        if ($WhatIf) {
            Write-InfoMessage "WhatIf: Would create resource group '$ResourceGroupName' in '$Location'"
            return $true
        }
        
        $response = Read-Host "Create resource group? (y/N)"
        if ($response -eq 'y' -or $response -eq 'Y') {
            try {
                New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag @{
                    Environment = $Environment
                    Project = "store-locator"
                } | Out-Null
                Write-SuccessMessage "Resource group created: $ResourceGroupName"
                return $true
            }
            catch {
                Write-ErrorMessage "Failed to create resource group: $($_.Exception.Message)"
                return $false
            }
        }
        else {
            Write-ErrorMessage "Cannot proceed without resource group"
            return $false
        }
    }
}

function Invoke-BicepDeployment {
    param(
        [string]$ResourceGroupName,
        [string]$Environment,
        [string]$MapsAccountName,
        [string]$Location
    )
    
    Write-HeaderMessage "Deploying Azure Maps Infrastructure"
    
    # Determine which parameters file to use
    $paramsFile = "parameters.json"
    if ($Environment -eq "prod" -and (Test-Path "parameters.prod.json")) {
        $paramsFile = "parameters.prod.json"
        Write-InfoMessage "Using production parameters file: $paramsFile"
    }
    else {
        Write-InfoMessage "Using parameters file: $paramsFile"
    }
    
    # Read and modify parameters
    try {
        $params = Get-Content $paramsFile | ConvertFrom-Json
        $params.parameters.mapsAccountName.value = $MapsAccountName
        $params.parameters.location.value = $Location
        $params.parameters.environment.value = $Environment
        
        $tempParamsFile = "temp-parameters-$(Get-Date -Format 'yyyyMMddHHmmss').json"
        $params | ConvertTo-Json -Depth 10 | Set-Content $tempParamsFile
    }
    catch {
        Write-ErrorMessage "Error processing parameters file: $($_.Exception.Message)"
        return $false
    }
    
    Write-InfoMessage "Starting deployment..."
    Write-InfoMessage "Resource Group: $ResourceGroupName"
    Write-InfoMessage "Maps Account: $MapsAccountName"
    Write-InfoMessage "Location: $Location"
    Write-InfoMessage "Environment: $Environment"
    
    if ($WhatIf) {
        Write-InfoMessage "WhatIf: Would deploy the following template:"
        Write-InfoMessage "  Template: main.bicep"
        Write-InfoMessage "  Parameters: $tempParamsFile"
        Write-InfoMessage "  Deployment Name: $DeploymentName"
        
        try {
            New-AzResourceGroupDeployment `
                -ResourceGroupName $ResourceGroupName `
                -Name $DeploymentName `
                -TemplateFile "main.bicep" `
                -TemplateParameterFile $tempParamsFile `
                -WhatIf
            
            Remove-Item $tempParamsFile -Force -ErrorAction SilentlyContinue
            return $true
        }
        catch {
            Write-ErrorMessage "WhatIf deployment validation failed: $($_.Exception.Message)"
            Remove-Item $tempParamsFile -Force -ErrorAction SilentlyContinue
            return $false
        }
    }
    else {
        try {
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $ResourceGroupName `
                -Name $DeploymentName `
                -TemplateFile "main.bicep" `
                -TemplateParameterFile $tempParamsFile `
                -Verbose
            
            Remove-Item $tempParamsFile -Force -ErrorAction SilentlyContinue
            
            if ($deployment.ProvisioningState -eq "Succeeded") {
                Write-SuccessMessage "Deployment completed successfully!"
                
                # Display outputs
                Write-HeaderMessage "Deployment Outputs"
                
                Write-SuccessMessage "Maps Account: $($deployment.Outputs.mapsAccountName.Value)"
                Write-SuccessMessage "Location: $($deployment.Outputs.location.Value)"
                Write-SuccessMessage "Environment: $Environment"
                
                Write-WarningMessage "Subscription keys are available in the Azure portal or via:"
                Write-InfoMessage "Get-AzMapsAccountKey -ResourceGroupName $ResourceGroupName -Name $($deployment.Outputs.mapsAccountName.Value)"
                
                if ($deployment.Outputs.configurationSummary) {
                    Write-InfoMessage "Configuration Summary:"
                    $deployment.Outputs.configurationSummary.Value | ConvertTo-Json -Depth 3 | Write-Host
                }
                
                return $true
            }
            else {
                Write-ErrorMessage "Deployment failed with state: $($deployment.ProvisioningState)"
                return $false
            }
        }
        catch {
            Write-ErrorMessage "Deployment failed: $($_.Exception.Message)"
            Remove-Item $tempParamsFile -Force -ErrorAction SilentlyContinue
            return $false
        }
    }
}

# ========================================================================
# MAIN SCRIPT
# ========================================================================

# Show help if requested
if ($Help) {
    Show-Usage
    exit 0
}

# Set error action preference
$ErrorActionPreference = "Stop"

Write-HeaderMessage "Azure Maps Store Locator Deployment"
Write-InfoMessage "Environment: $Environment"
Write-InfoMessage "Resource Group: $ResourceGroup"
Write-InfoMessage "Location: $Location"

if ($WhatIf) {
    Write-WarningMessage "Running in WhatIf mode - no resources will be created"
}

# Validate prerequisites
if (-not (Test-Prerequisites)) {
    Write-ErrorMessage "Prerequisites validation failed"
    exit 1
}

# Generate unique Maps account name
$mapsAccountName = New-MapsAccountName -Environment $Environment
Write-InfoMessage "Generated Maps account name: $mapsAccountName"

# Check/create resource group
if (-not (New-ResourceGroupIfNotExists -ResourceGroupName $ResourceGroup -Location $Location)) {
    Write-ErrorMessage "Resource group validation/creation failed"
    exit 1
}

# Confirm deployment (unless WhatIf)
if (-not $WhatIf) {
    Write-WarningMessage "About to deploy Azure Maps infrastructure:"
    Write-InfoMessage "  Environment: $Environment"
    Write-InfoMessage "  Resource Group: $ResourceGroup"
    Write-InfoMessage "  Maps Account: $mapsAccountName"
    Write-InfoMessage "  Location: $Location"
    Write-Host ""
    
    $response = Read-Host "Continue with deployment? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-InfoMessage "Deployment cancelled by user"
        exit 0
    }
}

# Deploy the template
if (Invoke-BicepDeployment -ResourceGroupName $ResourceGroup -Environment $Environment -MapsAccountName $mapsAccountName -Location $Location) {
    Write-HeaderMessage "Deployment Complete"
    
    if ($WhatIf) {
        Write-SuccessMessage "WhatIf validation completed successfully!"
        Write-InfoMessage "Run the script without -WhatIf to perform the actual deployment."
    }
    else {
        Write-SuccessMessage "Azure Maps Store Locator infrastructure has been deployed successfully!"
        Write-InfoMessage "Next steps:"
        Write-InfoMessage "1. Retrieve your Maps subscription key from the Azure portal"
        Write-InfoMessage "2. Update your web application configuration"
        Write-InfoMessage "3. Test your store locator application"
        Write-InfoMessage ""
        Write-InfoMessage "For more information, see the README.md file in this directory."
    }
    
    exit 0
}
else {
    Write-ErrorMessage "Deployment failed"
    exit 1
}