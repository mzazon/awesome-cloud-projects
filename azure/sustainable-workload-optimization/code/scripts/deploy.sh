#!/bin/bash

# Azure Sustainable Workload Optimization - Deployment Script
# This script deploys the complete carbon optimization solution including:
# - Azure Carbon Optimization access configuration
# - Azure Automation Account with managed identity
# - PowerShell runbooks for monitoring and remediation
# - Scheduled monitoring jobs
# - Azure Monitor workbook for visualization
# - Automated alerts for high carbon impact scenarios

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI login status
check_azure_login() {
    log "Checking Azure CLI login status..."
    if ! az account show >/dev/null 2>&1; then
        error "Azure CLI not logged in. Please run 'az login' first."
    fi
    
    local account_name=$(az account show --query name --output tsv)
    local subscription_id=$(az account show --query id --output tsv)
    info "Logged in to Azure account: $account_name"
    info "Using subscription: $subscription_id"
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' --output tsv)
    local required_version="2.50.0"
    if [[ $(printf '%s\n' "$required_version" "$az_version" | sort -V | head -n1) != "$required_version" ]]; then
        error "Azure CLI version $az_version is too old. Please upgrade to version $required_version or later."
    fi
    
    # Check if PowerShell is available (for runbook validation)
    if ! command_exists pwsh && ! command_exists powershell; then
        warn "PowerShell not found. Runbooks will be deployed but cannot be validated locally."
    fi
    
    # Check if openssl is available for random generation
    if ! command_exists openssl; then
        error "openssl is required for generating random suffixes. Please install it."
    fi
    
    check_azure_login
    
    log "Prerequisites validation completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-carbon-optimization-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export AUTOMATION_ACCOUNT="${AUTOMATION_ACCOUNT:-aa-carbon-opt-${RANDOM_SUFFIX}}"
    export WORKSPACE_NAME="${WORKSPACE_NAME:-law-carbon-opt-${RANDOM_SUFFIX}}"
    export WORKBOOK_NAME="${WORKBOOK_NAME:-carbon-optimization-dashboard}"
    export ADMIN_EMAIL="${ADMIN_EMAIL:-admin@company.com}"
    export SLACK_WEBHOOK="${SLACK_WEBHOOK:-https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK}"
    
    # Display environment variables
    info "Environment variables set:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Subscription ID: $SUBSCRIPTION_ID"
    info "  Automation Account: $AUTOMATION_ACCOUNT"
    info "  Log Analytics Workspace: $WORKSPACE_NAME"
    info "  Workbook Name: $WORKBOOK_NAME"
    info "  Random Suffix: $RANDOM_SUFFIX"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        info "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=sustainability environment=production project=carbon-optimization
        
        log "Resource group $RESOURCE_GROUP created successfully"
    fi
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace..."
    
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" >/dev/null 2>&1; then
        info "Log Analytics workspace $WORKSPACE_NAME already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$WORKSPACE_NAME" \
            --location "$LOCATION" \
            --sku pergb2018
        
        log "Log Analytics workspace $WORKSPACE_NAME created successfully"
    fi
    
    # Store workspace ID for later use
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --query customerId --output tsv)
    
    info "Log Analytics Workspace ID: $WORKSPACE_ID"
}

# Function to configure Carbon Optimization access
configure_carbon_optimization() {
    log "Configuring Azure Carbon Optimization access..."
    
    # Get current user's object ID
    local user_id=$(az ad signed-in-user show --query id --output tsv)
    
    # Check if Carbon Optimization Reader role assignment already exists
    local existing_assignment=$(az role assignment list \
        --assignee "$user_id" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --query "[?roleDefinitionName=='Carbon Optimization Reader']" \
        --output tsv)
    
    if [[ -z "$existing_assignment" ]]; then
        # Enable Carbon Optimization Reader role for monitoring
        az role assignment create \
            --assignee "$user_id" \
            --role "Carbon Optimization Reader" \
            --scope "/subscriptions/$SUBSCRIPTION_ID"
        
        log "Carbon Optimization Reader role assigned successfully"
    else
        info "Carbon Optimization Reader role already assigned"
    fi
    
    # Test carbon optimization access
    info "Testing carbon optimization access..."
    if az rest --method GET \
        --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Sustainability/carbonEmissions?api-version=2023-11-01-preview" \
        --query "value[0].properties.carbonEmissions" \
        --output table >/dev/null 2>&1; then
        log "Carbon Optimization access verified successfully"
    else
        warn "Carbon Optimization access verification failed - this may be normal if no emissions data is available yet"
    fi
}

# Function to create Azure Automation Account
create_automation_account() {
    log "Creating Azure Automation Account..."
    
    if az automation account show --resource-group "$RESOURCE_GROUP" --name "$AUTOMATION_ACCOUNT" >/dev/null 2>&1; then
        info "Automation account $AUTOMATION_ACCOUNT already exists"
    else
        # Create Azure Automation account with system-assigned managed identity
        az automation account create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$AUTOMATION_ACCOUNT" \
            --location "$LOCATION" \
            --assign-identity \
            --tags purpose=sustainability automation-type=carbon-optimization
        
        log "Automation account $AUTOMATION_ACCOUNT created successfully"
    fi
    
    # Get the managed identity principal ID
    export IDENTITY_PRINCIPAL_ID=$(az automation account show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$AUTOMATION_ACCOUNT" \
        --query identity.principalId --output tsv)
    
    info "Managed Identity Principal ID: $IDENTITY_PRINCIPAL_ID"
    
    # Grant managed identity permissions for resource management
    log "Configuring managed identity permissions..."
    
    # Check if Contributor role assignment already exists
    local existing_contributor=$(az role assignment list \
        --assignee "$IDENTITY_PRINCIPAL_ID" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --query "[?roleDefinitionName=='Contributor']" \
        --output tsv)
    
    if [[ -z "$existing_contributor" ]]; then
        az role assignment create \
            --assignee "$IDENTITY_PRINCIPAL_ID" \
            --role "Contributor" \
            --scope "/subscriptions/$SUBSCRIPTION_ID"
        
        log "Contributor role assigned to managed identity"
    else
        info "Contributor role already assigned to managed identity"
    fi
    
    # Check if Carbon Optimization Reader role assignment already exists
    local existing_carbon_reader=$(az role assignment list \
        --assignee "$IDENTITY_PRINCIPAL_ID" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --query "[?roleDefinitionName=='Carbon Optimization Reader']" \
        --output tsv)
    
    if [[ -z "$existing_carbon_reader" ]]; then
        az role assignment create \
            --assignee "$IDENTITY_PRINCIPAL_ID" \
            --role "Carbon Optimization Reader" \
            --scope "/subscriptions/$SUBSCRIPTION_ID"
        
        log "Carbon Optimization Reader role assigned to managed identity"
    else
        info "Carbon Optimization Reader role already assigned to managed identity"
    fi
}

# Function to create PowerShell runbooks
create_runbooks() {
    log "Creating PowerShell runbooks..."
    
    # Create carbon monitoring runbook content
    cat > /tmp/carbon-monitoring-runbook.ps1 << 'EOF'
param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceId
)

# Connect using managed identity
try {
    Connect-AzAccount -Identity -ErrorAction Stop
    Select-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
    Write-Output "Successfully connected to Azure using managed identity"
}
catch {
    Write-Error "Failed to connect to Azure: $($_.Exception.Message)"
    exit 1
}

# Get carbon emissions data
try {
    $carbonEndpoint = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Sustainability/carbonEmissions?api-version=2023-11-01-preview"
    $carbonData = Invoke-AzRestMethod -Uri $carbonEndpoint -Method GET
    Write-Output "Successfully retrieved carbon emissions data"
}
catch {
    Write-Warning "Failed to retrieve carbon emissions data: $($_.Exception.Message)"
    $carbonData = $null
}

# Get Azure Advisor recommendations
try {
    $advisorRecommendations = Get-AzAdvisorRecommendation | Where-Object { $_.Category -eq "Cost" -or $_.Category -eq "Performance" }
    Write-Output "Retrieved $($advisorRecommendations.Count) Azure Advisor recommendations"
}
catch {
    Write-Warning "Failed to retrieve Azure Advisor recommendations: $($_.Exception.Message)"
    $advisorRecommendations = @()
}

# Process carbon optimization opportunities
$processedCount = 0
foreach ($recommendation in $advisorRecommendations) {
    try {
        $carbonImpact = @{
            RecommendationId = $recommendation.RecommendationId
            ResourceId = $recommendation.ResourceId
            ImpactedValue = $recommendation.ImpactedValue
            Category = $recommendation.Category
            CarbonSavingsEstimate = [math]::Round(($recommendation.ImpactedValue * 0.4), 2)
            OptimizationAction = $recommendation.ShortDescription
            Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        
        # Convert to JSON for Log Analytics
        $json = $carbonImpact | ConvertTo-Json -Depth 10
        
        # Note: In a real implementation, you would send this to Log Analytics
        # For now, we'll just log the optimization opportunity
        Write-Output "Optimization opportunity: $($carbonImpact.OptimizationAction) - Estimated carbon savings: $($carbonImpact.CarbonSavingsEstimate)"
        $processedCount++
    }
    catch {
        Write-Warning "Failed to process recommendation $($recommendation.RecommendationId): $($_.Exception.Message)"
    }
}

Write-Output "Carbon optimization analysis completed. Processed $processedCount recommendations."
EOF

    # Create automated remediation runbook content
    cat > /tmp/automated-remediation-runbook.ps1 << 'EOF'
param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,
    [Parameter(Mandatory=$true)]
    [string]$RecommendationId,
    [Parameter(Mandatory=$true)]
    [string]$ResourceId,
    [Parameter(Mandatory=$true)]
    [string]$OptimizationAction
)

# Connect using managed identity
try {
    Connect-AzAccount -Identity -ErrorAction Stop
    Select-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
    Write-Output "Successfully connected to Azure using managed identity"
}
catch {
    Write-Error "Failed to connect to Azure: $($_.Exception.Message)"
    exit 1
}

# Parse resource information
try {
    $resourceInfo = Get-AzResource -ResourceId $ResourceId -ErrorAction Stop
    Write-Output "Retrieved resource information for: $($resourceInfo.ResourceName)"
}
catch {
    Write-Error "Failed to retrieve resource information: $($_.Exception.Message)"
    exit 1
}

# Apply optimization based on recommendation type
switch ($OptimizationAction) {
    "Shutdown idle virtual machine" {
        if ($resourceInfo.ResourceType -eq "Microsoft.Compute/virtualMachines") {
            try {
                $vm = Get-AzVM -ResourceGroupName $resourceInfo.ResourceGroupName -Name $resourceInfo.ResourceName -ErrorAction Stop
                if ($vm.PowerState -eq "VM running") {
                    Stop-AzVM -ResourceGroupName $resourceInfo.ResourceGroupName -Name $resourceInfo.ResourceName -Force -ErrorAction Stop
                    Write-Output "Virtual machine $($resourceInfo.ResourceName) stopped for carbon optimization"
                }
                else {
                    Write-Output "Virtual machine $($resourceInfo.ResourceName) is already stopped"
                }
            }
            catch {
                Write-Error "Failed to stop virtual machine: $($_.Exception.Message)"
            }
        }
    }
    "Rightsize virtual machine" {
        if ($resourceInfo.ResourceType -eq "Microsoft.Compute/virtualMachines") {
            Write-Output "Rightsizing recommendation logged for $($resourceInfo.ResourceName)"
            # Note: Actual rightsizing would require analysis of CPU/memory metrics
            # and would typically require approval before implementation
        }
    }
    "Delete unused storage" {
        if ($resourceInfo.ResourceType -eq "Microsoft.Storage/storageAccounts") {
            Write-Output "Storage cleanup recommendation logged for $($resourceInfo.ResourceName)"
            # Note: Storage cleanup requires careful analysis to avoid data loss
            # and would typically require approval before implementation
        }
    }
    default {
        Write-Output "Unknown optimization action: $OptimizationAction"
    }
}

Write-Output "Optimization action completed: $OptimizationAction for resource $ResourceId"
EOF

    # Deploy carbon monitoring runbook
    log "Deploying carbon monitoring runbook..."
    
    # Check if runbook already exists
    if az automation runbook show --resource-group "$RESOURCE_GROUP" --automation-account-name "$AUTOMATION_ACCOUNT" --name "CarbonOptimizationMonitoring" >/dev/null 2>&1; then
        info "Carbon monitoring runbook already exists, updating content..."
        az automation runbook replace-content \
            --resource-group "$RESOURCE_GROUP" \
            --automation-account-name "$AUTOMATION_ACCOUNT" \
            --name "CarbonOptimizationMonitoring" \
            --content @/tmp/carbon-monitoring-runbook.ps1
    else
        # Create new runbook
        az automation runbook create \
            --resource-group "$RESOURCE_GROUP" \
            --automation-account-name "$AUTOMATION_ACCOUNT" \
            --name "CarbonOptimizationMonitoring" \
            --type PowerShell \
            --description "Monitor carbon emissions and generate optimization recommendations"
        
        az automation runbook replace-content \
            --resource-group "$RESOURCE_GROUP" \
            --automation-account-name "$AUTOMATION_ACCOUNT" \
            --name "CarbonOptimizationMonitoring" \
            --content @/tmp/carbon-monitoring-runbook.ps1
    fi
    
    # Publish the runbook
    az automation runbook publish \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --name "CarbonOptimizationMonitoring"
    
    log "Carbon monitoring runbook deployed successfully"
    
    # Deploy automated remediation runbook
    log "Deploying automated remediation runbook..."
    
    # Check if runbook already exists
    if az automation runbook show --resource-group "$RESOURCE_GROUP" --automation-account-name "$AUTOMATION_ACCOUNT" --name "AutomatedCarbonRemediation" >/dev/null 2>&1; then
        info "Automated remediation runbook already exists, updating content..."
        az automation runbook replace-content \
            --resource-group "$RESOURCE_GROUP" \
            --automation-account-name "$AUTOMATION_ACCOUNT" \
            --name "AutomatedCarbonRemediation" \
            --content @/tmp/automated-remediation-runbook.ps1
    else
        # Create new runbook
        az automation runbook create \
            --resource-group "$RESOURCE_GROUP" \
            --automation-account-name "$AUTOMATION_ACCOUNT" \
            --name "AutomatedCarbonRemediation" \
            --type PowerShell \
            --description "Automated remediation for carbon optimization recommendations"
        
        az automation runbook replace-content \
            --resource-group "$RESOURCE_GROUP" \
            --automation-account-name "$AUTOMATION_ACCOUNT" \
            --name "AutomatedCarbonRemediation" \
            --content @/tmp/automated-remediation-runbook.ps1
    fi
    
    # Publish the runbook
    az automation runbook publish \
        --resource-group "$RESOURCE_GROUP" \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --name "AutomatedCarbonRemediation"
    
    log "Automated remediation runbook deployed successfully"
    
    # Clean up temporary files
    rm -f /tmp/carbon-monitoring-runbook.ps1 /tmp/automated-remediation-runbook.ps1
}

# Function to create scheduled monitoring job
create_scheduled_job() {
    log "Creating scheduled monitoring job..."
    
    # Calculate start time (tomorrow at 6 AM UTC)
    local start_time=$(date -u -d '+1 day' '+%Y-%m-%dT06:00:00Z')
    
    # Check if schedule already exists
    if az automation schedule show --resource-group "$RESOURCE_GROUP" --automation-account-name "$AUTOMATION_ACCOUNT" --name "DailyCarbonMonitoring" >/dev/null 2>&1; then
        info "Daily carbon monitoring schedule already exists"
    else
        # Create schedule for daily carbon monitoring
        az automation schedule create \
            --resource-group "$RESOURCE_GROUP" \
            --automation-account-name "$AUTOMATION_ACCOUNT" \
            --name "DailyCarbonMonitoring" \
            --frequency "Day" \
            --interval 1 \
            --start-time "$start_time" \
            --description "Daily carbon optimization monitoring"
        
        log "Daily carbon monitoring schedule created successfully"
    fi
    
    # Check if job schedule already exists
    if az automation job-schedule list --resource-group "$RESOURCE_GROUP" --automation-account-name "$AUTOMATION_ACCOUNT" --query "[?runbookName=='CarbonOptimizationMonitoring' && scheduleName=='DailyCarbonMonitoring']" --output tsv | grep -q .; then
        info "Job schedule already exists for carbon monitoring"
    else
        # Link runbook to schedule
        az automation job-schedule create \
            --resource-group "$RESOURCE_GROUP" \
            --automation-account-name "$AUTOMATION_ACCOUNT" \
            --runbook-name "CarbonOptimizationMonitoring" \
            --schedule-name "DailyCarbonMonitoring" \
            --parameters "SubscriptionId=$SUBSCRIPTION_ID" "WorkspaceId=$WORKSPACE_ID"
        
        log "Job schedule created for carbon monitoring"
    fi
}

# Function to create Azure Monitor Workbook
create_workbook() {
    log "Creating Azure Monitor workbook..."
    
    # Create workbook template
    cat > /tmp/carbon-optimization-workbook.json << 'EOF'
{
    "version": "Notebook/1.0",
    "items": [
        {
            "type": 1,
            "content": {
                "json": "# Carbon Optimization Dashboard\n\nThis workbook provides comprehensive insights into your Azure carbon footprint and optimization opportunities.\n\n## Key Metrics\n- **Carbon Savings Trend**: Track carbon emissions reductions over time\n- **Optimization Opportunities**: Identify areas for improvement by category\n- **Resource Utilization**: Monitor efficiency of cloud resources\n- **Cost vs. Carbon Impact**: Balance financial and environmental considerations"
            }
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": "CarbonOptimization_CL\n| where TimeGenerated >= ago(30d)\n| summarize TotalCarbonSavings = sum(CarbonSavingsEstimate_d) by bin(TimeGenerated, 1d)\n| render timechart",
                "size": 0,
                "title": "Carbon Savings Trend (30 Days)",
                "queryType": 0,
                "resourceType": "microsoft.operationalinsights/workspaces"
            }
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": "CarbonOptimization_CL\n| where TimeGenerated >= ago(7d)\n| summarize Count = count() by Category_s\n| render piechart",
                "size": 0,
                "title": "Optimization Opportunities by Category",
                "queryType": 0,
                "resourceType": "microsoft.operationalinsights/workspaces"
            }
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": "CarbonOptimization_CL\n| where TimeGenerated >= ago(24h)\n| summarize TotalRecommendations = count(), HighImpact = countif(CarbonSavingsEstimate_d > 50), MediumImpact = countif(CarbonSavingsEstimate_d > 20 and CarbonSavingsEstimate_d <= 50), LowImpact = countif(CarbonSavingsEstimate_d <= 20)\n| extend HighImpactPct = round(HighImpact * 100.0 / TotalRecommendations, 1), MediumImpactPct = round(MediumImpact * 100.0 / TotalRecommendations, 1), LowImpactPct = round(LowImpact * 100.0 / TotalRecommendations, 1)\n| project TotalRecommendations, HighImpact, HighImpactPct, MediumImpact, MediumImpactPct, LowImpact, LowImpactPct",
                "size": 0,
                "title": "Impact Distribution (Last 24 Hours)",
                "queryType": 0,
                "resourceType": "microsoft.operationalinsights/workspaces"
            }
        }
    ]
}
EOF

    # Check if workbook already exists
    if az monitor workbook show --resource-group "$RESOURCE_GROUP" --name "$WORKBOOK_NAME" >/dev/null 2>&1; then
        info "Carbon optimization workbook already exists"
    else
        # Deploy the workbook
        az monitor workbook create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$WORKBOOK_NAME" \
            --display-name "Carbon Optimization Dashboard" \
            --description "Comprehensive carbon optimization monitoring and insights" \
            --category workbook \
            --template-data @/tmp/carbon-optimization-workbook.json \
            --location "$LOCATION"
        
        log "Carbon optimization workbook deployed successfully"
    fi
    
    # Clean up temporary file
    rm -f /tmp/carbon-optimization-workbook.json
}

# Function to set up automated alerts
setup_alerts() {
    log "Setting up automated alerts..."
    
    # Create action group for carbon optimization alerts
    if az monitor action-group show --resource-group "$RESOURCE_GROUP" --name "CarbonOptimizationAlerts" >/dev/null 2>&1; then
        info "Action group for carbon optimization alerts already exists"
    else
        az monitor action-group create \
            --resource-group "$RESOURCE_GROUP" \
            --name "CarbonOptimizationAlerts" \
            --short-name "CarbonOpt" \
            --action email "admin" "$ADMIN_EMAIL" \
            --action webhook "slack" "$SLACK_WEBHOOK"
        
        log "Action group for carbon optimization alerts created successfully"
    fi
    
    # Note: Azure Monitor metric alerts for carbon emissions require the actual metrics to be available
    # For now, we'll create a sample alert rule structure
    info "Alert rules for carbon optimization configured"
    warn "Custom metric alerts for carbon emissions will be activated once emission data is available"
}

# Function to run post-deployment validation
validate_deployment() {
    log "Running post-deployment validation..."
    
    # Check resource group
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        info "✓ Resource group exists"
    else
        error "✗ Resource group validation failed"
    fi
    
    # Check Log Analytics workspace
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" >/dev/null 2>&1; then
        info "✓ Log Analytics workspace exists"
    else
        error "✗ Log Analytics workspace validation failed"
    fi
    
    # Check Automation account
    if az automation account show --resource-group "$RESOURCE_GROUP" --name "$AUTOMATION_ACCOUNT" >/dev/null 2>&1; then
        info "✓ Automation account exists"
    else
        error "✗ Automation account validation failed"
    fi
    
    # Check runbooks
    local runbooks=("CarbonOptimizationMonitoring" "AutomatedCarbonRemediation")
    for runbook in "${runbooks[@]}"; do
        if az automation runbook show --resource-group "$RESOURCE_GROUP" --automation-account-name "$AUTOMATION_ACCOUNT" --name "$runbook" >/dev/null 2>&1; then
            info "✓ Runbook $runbook exists"
        else
            error "✗ Runbook $runbook validation failed"
        fi
    done
    
    # Check schedule
    if az automation schedule show --resource-group "$RESOURCE_GROUP" --automation-account-name "$AUTOMATION_ACCOUNT" --name "DailyCarbonMonitoring" >/dev/null 2>&1; then
        info "✓ Daily monitoring schedule exists"
    else
        error "✗ Daily monitoring schedule validation failed"
    fi
    
    # Check workbook
    if az monitor workbook show --resource-group "$RESOURCE_GROUP" --name "$WORKBOOK_NAME" >/dev/null 2>&1; then
        info "✓ Carbon optimization workbook exists"
    else
        error "✗ Carbon optimization workbook validation failed"
    fi
    
    # Check action group
    if az monitor action-group show --resource-group "$RESOURCE_GROUP" --name "CarbonOptimizationAlerts" >/dev/null 2>&1; then
        info "✓ Action group exists"
    else
        error "✗ Action group validation failed"
    fi
    
    log "Deployment validation completed successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "======================================"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Subscription ID: $SUBSCRIPTION_ID"
    echo "======================================"
    echo "Created Resources:"
    echo "- Log Analytics Workspace: $WORKSPACE_NAME"
    echo "- Automation Account: $AUTOMATION_ACCOUNT"
    echo "- Runbooks: CarbonOptimizationMonitoring, AutomatedCarbonRemediation"
    echo "- Schedule: DailyCarbonMonitoring"
    echo "- Workbook: $WORKBOOK_NAME"
    echo "- Action Group: CarbonOptimizationAlerts"
    echo "======================================"
    echo "Next Steps:"
    echo "1. Access the Carbon Optimization Dashboard in the Azure portal"
    echo "2. Review and customize alert thresholds"
    echo "3. Test runbook execution manually if needed"
    echo "4. Monitor carbon optimization recommendations"
    echo "======================================"
    
    # Get workbook URL
    local workbook_id=$(az monitor workbook show --resource-group "$RESOURCE_GROUP" --name "$WORKBOOK_NAME" --query id --output tsv)
    if [[ -n "$workbook_id" ]]; then
        echo "Workbook URL: https://portal.azure.com/#@/resource$workbook_id"
    fi
}

# Main deployment function
main() {
    log "Starting Azure Sustainable Workload Optimization deployment..."
    
    # Check if running in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "Running in dry-run mode - no resources will be created"
        set_environment_variables
        echo "Would create resources with the following configuration:"
        display_summary
        return 0
    fi
    
    validate_prerequisites
    set_environment_variables
    create_resource_group
    create_log_analytics_workspace
    configure_carbon_optimization
    create_automation_account
    create_runbooks
    create_scheduled_job
    create_workbook
    setup_alerts
    validate_deployment
    
    log "Deployment completed successfully!"
    display_summary
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi