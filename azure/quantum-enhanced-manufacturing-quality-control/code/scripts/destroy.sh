#!/bin/bash

# Destroy Azure Quantum Manufacturing Quality Control Solution
# This script removes all resources created by the deploy.sh script

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Script banner
echo -e "${RED}================================================${NC}"
echo -e "${RED}  Azure Quantum Manufacturing Quality Control${NC}"
echo -e "${RED}  Infrastructure Cleanup Script${NC}"
echo -e "${RED}================================================${NC}"
echo

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warning "Running in DRY-RUN mode. No resources will be deleted."
            shift
            ;;
        --force)
            FORCE_DELETE=true
            warning "Force delete mode enabled. Skipping confirmations."
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --force      Skip confirmation prompts"
            echo "  -h, --help   Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Prerequisites check
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in to Azure
if ! az account show &> /dev/null; then
    error "Please log in to Azure using 'az login'"
    exit 1
fi

success "Prerequisites check completed"

# Load configuration from deployment
if [ -f ".deployment_config" ]; then
    log "Loading configuration from .deployment_config..."
    source .deployment_config
    success "Configuration loaded successfully"
else
    warning "No .deployment_config file found. You may need to provide resource names manually."
    read -p "Enter the resource group name to delete: " RESOURCE_GROUP
    if [ -z "$RESOURCE_GROUP" ]; then
        error "Resource group name is required"
        exit 1
    fi
fi

# Display configuration
log "Configuration loaded:"
log "  Resource Group: ${RESOURCE_GROUP:-'Not set'}"
log "  Location: ${LOCATION:-'Not set'}"
log "  Subscription ID: ${SUBSCRIPTION_ID:-'Not set'}"
log "  Workspace Name: ${WORKSPACE_NAME:-'Not set'}"
log "  IoT Hub Name: ${IOT_HUB_NAME:-'Not set'}"
log "  Storage Account: ${STORAGE_ACCOUNT:-'Not set'}"
log "  Quantum Workspace: ${QUANTUM_WORKSPACE:-'Not set'}"

# Function to execute command with dry-run support
execute_command() {
    local command="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $description"
        echo -e "${YELLOW}[DRY-RUN]${NC} Command: $command"
    else
        log "$description"
        eval "$command"
    fi
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="${3:-$RESOURCE_GROUP}"
    
    case $resource_type in
        "group")
            az group exists --name "$resource_name" --output tsv 2>/dev/null
            ;;
        "ml-workspace")
            az ml workspace show --name "$resource_name" --resource-group "$resource_group" &>/dev/null && echo "true" || echo "false"
            ;;
        "iot-hub")
            az iot hub show --name "$resource_name" --resource-group "$resource_group" &>/dev/null && echo "true" || echo "false"
            ;;
        "quantum-workspace")
            az quantum workspace show --name "$resource_name" --resource-group "$resource_group" &>/dev/null && echo "true" || echo "false"
            ;;
        "storage-account")
            az storage account show --name "$resource_name" --resource-group "$resource_group" &>/dev/null && echo "true" || echo "false"
            ;;
        "stream-analytics")
            az stream-analytics job show --name "$resource_name" --resource-group "$resource_group" &>/dev/null && echo "true" || echo "false"
            ;;
        "cosmos-db")
            az cosmosdb show --name "$resource_name" --resource-group "$resource_group" &>/dev/null && echo "true" || echo "false"
            ;;
        "function-app")
            az functionapp show --name "$resource_name" --resource-group "$resource_group" &>/dev/null && echo "true" || echo "false"
            ;;
        *)
            echo "false"
            ;;
    esac
}

# Confirmation prompt
if [ "$FORCE_DELETE" = false ] && [ "$DRY_RUN" = false ]; then
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete all resources in the resource group: ${RESOURCE_GROUP}${NC}"
    echo -e "${YELLOW}⚠️  This action cannot be undone!${NC}"
    echo
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Operation cancelled by user"
        exit 0
    fi
fi

# Check if resource group exists
if [ "$(resource_exists "group" "$RESOURCE_GROUP")" = "false" ]; then
    warning "Resource group '$RESOURCE_GROUP' does not exist. Nothing to delete."
    exit 0
fi

# Stop running services first to prevent charges
log "Stopping running services to prevent additional charges..."

# Stop Stream Analytics job if it exists
if [ -n "$STREAM_ANALYTICS_JOB" ] && [ "$(resource_exists "stream-analytics" "$STREAM_ANALYTICS_JOB")" = "true" ]; then
    execute_command "az stream-analytics job stop --name '$STREAM_ANALYTICS_JOB' --resource-group '$RESOURCE_GROUP'" \
                   "Stopping Stream Analytics job: $STREAM_ANALYTICS_JOB"
fi

# Stop ML compute clusters if they exist
if [ -n "$WORKSPACE_NAME" ] && [ "$(resource_exists "ml-workspace" "$WORKSPACE_NAME")" = "true" ]; then
    execute_command "az ml compute stop --name 'quantum-ml-cluster' --workspace-name '$WORKSPACE_NAME' --resource-group '$RESOURCE_GROUP' || true" \
                   "Stopping ML compute cluster (if running)"
    
    execute_command "az ml compute stop --name 'quantum-dev-instance' --workspace-name '$WORKSPACE_NAME' --resource-group '$RESOURCE_GROUP' || true" \
                   "Stopping ML compute instance (if running)"
fi

if [ "$DRY_RUN" = false ]; then
    success "Services stopped successfully"
fi

# Delete individual resources in reverse order of creation
log "Deleting individual resources in reverse order..."

# Delete Function App
if [ -n "$FUNCTION_APP_NAME" ] && [ "$(resource_exists "function-app" "$FUNCTION_APP_NAME")" = "true" ]; then
    execute_command "az functionapp delete --name '$FUNCTION_APP_NAME' --resource-group '$RESOURCE_GROUP'" \
                   "Deleting Function App: $FUNCTION_APP_NAME"
fi

# Delete Cosmos DB
if [ -n "$COSMOS_DB_NAME" ] && [ "$(resource_exists "cosmos-db" "$COSMOS_DB_NAME")" = "true" ]; then
    execute_command "az cosmosdb delete --name '$COSMOS_DB_NAME' --resource-group '$RESOURCE_GROUP' --yes" \
                   "Deleting Cosmos DB: $COSMOS_DB_NAME"
fi

# Delete ML compute resources
if [ -n "$WORKSPACE_NAME" ] && [ "$(resource_exists "ml-workspace" "$WORKSPACE_NAME")" = "true" ]; then
    execute_command "az ml compute delete --name 'quantum-ml-cluster' --workspace-name '$WORKSPACE_NAME' --resource-group '$RESOURCE_GROUP' --yes || true" \
                   "Deleting ML compute cluster"
    
    execute_command "az ml compute delete --name 'quantum-dev-instance' --workspace-name '$WORKSPACE_NAME' --resource-group '$RESOURCE_GROUP' --yes || true" \
                   "Deleting ML compute instance"
fi

# Delete Stream Analytics job
if [ -n "$STREAM_ANALYTICS_JOB" ] && [ "$(resource_exists "stream-analytics" "$STREAM_ANALYTICS_JOB")" = "true" ]; then
    execute_command "az stream-analytics job delete --name '$STREAM_ANALYTICS_JOB' --resource-group '$RESOURCE_GROUP' --yes" \
                   "Deleting Stream Analytics job: $STREAM_ANALYTICS_JOB"
fi

# Delete Quantum workspace
if [ -n "$QUANTUM_WORKSPACE" ] && [ "$(resource_exists "quantum-workspace" "$QUANTUM_WORKSPACE")" = "true" ]; then
    execute_command "az quantum workspace delete --name '$QUANTUM_WORKSPACE' --resource-group '$RESOURCE_GROUP' --yes" \
                   "Deleting Quantum workspace: $QUANTUM_WORKSPACE"
fi

# Delete IoT Hub
if [ -n "$IOT_HUB_NAME" ] && [ "$(resource_exists "iot-hub" "$IOT_HUB_NAME")" = "true" ]; then
    execute_command "az iot hub delete --name '$IOT_HUB_NAME' --resource-group '$RESOURCE_GROUP'" \
                   "Deleting IoT Hub: $IOT_HUB_NAME"
fi

# Delete ML workspace (this will also delete associated resources)
if [ -n "$WORKSPACE_NAME" ] && [ "$(resource_exists "ml-workspace" "$WORKSPACE_NAME")" = "true" ]; then
    execute_command "az ml workspace delete --name '$WORKSPACE_NAME' --resource-group '$RESOURCE_GROUP' --delete-dependent-resources --yes" \
                   "Deleting ML workspace and dependent resources: $WORKSPACE_NAME"
fi

# Delete Storage Account
if [ -n "$STORAGE_ACCOUNT" ] && [ "$(resource_exists "storage-account" "$STORAGE_ACCOUNT")" = "true" ]; then
    execute_command "az storage account delete --name '$STORAGE_ACCOUNT' --resource-group '$RESOURCE_GROUP' --yes" \
                   "Deleting Storage Account: $STORAGE_ACCOUNT"
fi

# Wait for some resources to be fully deleted before proceeding
if [ "$DRY_RUN" = false ]; then
    log "Waiting for critical resources to be fully deleted..."
    sleep 30
    success "Wait period completed"
fi

# Final step: Delete the entire resource group
log "Deleting resource group and all remaining resources..."
execute_command "az group delete --name '$RESOURCE_GROUP' --yes --no-wait" \
               "Deleting resource group: $RESOURCE_GROUP"

if [ "$DRY_RUN" = false ]; then
    success "Resource group deletion initiated"
    
    # Monitor deletion progress
    log "Monitoring resource group deletion progress..."
    while [ "$(resource_exists "group" "$RESOURCE_GROUP")" = "true" ]; do
        log "Resource group still exists, waiting for deletion to complete..."
        sleep 30
    done
    
    success "Resource group '$RESOURCE_GROUP' has been completely deleted"
fi

# Clean up local files
log "Cleaning up local files..."
local_files_to_delete=(
    ".deployment_config"
    "quantum_optimization.py"
    "solve_quantum_optimization.py"
    "train_quality_model.py"
    "dashboard_aggregator.py"
    "training-job.yml"
    "mlflow.db"
    "mlruns/"
)

for file in "${local_files_to_delete[@]}"; do
    if [ -f "$file" ] || [ -d "$file" ]; then
        execute_command "rm -rf '$file'" "Removing local file/directory: $file"
    fi
done

if [ "$DRY_RUN" = false ]; then
    success "Local files cleaned up"
fi

# Final summary
echo
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}  Cleanup Summary${NC}"
echo -e "${GREEN}================================================${NC}"

if [ "$DRY_RUN" = true ]; then
    success "Dry-run completed successfully!"
    echo -e "${YELLOW}No resources were actually deleted.${NC}"
    echo -e "${YELLOW}Run without --dry-run to perform actual deletion.${NC}"
else
    success "Cleanup completed successfully!"
    echo -e "${GREEN}All resources have been deleted:${NC}"
    echo -e "${GREEN}✅ Resource Group:${NC} $RESOURCE_GROUP"
    echo -e "${GREEN}✅ All contained resources${NC}"
    echo -e "${GREEN}✅ Local configuration files${NC}"
    echo
    echo -e "${YELLOW}Important Notes:${NC}"
    echo "- Complete deletion may take up to 10-15 minutes"
    echo "- Check your Azure portal to verify all resources are removed"
    echo "- Review your Azure billing to confirm no ongoing charges"
    echo "- Some resources may have soft-delete enabled and require additional cleanup"
fi

echo -e "${BLUE}================================================${NC}"

# Exit with appropriate code
if [ "$DRY_RUN" = true ]; then
    exit 0
else
    log "Cleanup script completed successfully"
    exit 0
fi