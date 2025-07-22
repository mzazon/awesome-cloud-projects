#!/bin/bash

# Real-Time Fraud Detection Pipeline Cleanup Script
# This script removes all Azure resources created for the fraud detection pipeline

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
ENV_FILE="${SCRIPT_DIR}/../.env"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$ERROR_LOG" >&2
}

success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1" | tee -a "$LOG_FILE"
}

warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  WARNING: $1" | tee -a "$LOG_FILE"
}

# Function to prompt for confirmation
confirm_destruction() {
    echo ""
    echo "⚠️  WARNING: This will permanently delete ALL fraud detection resources!"
    echo ""
    echo "Resources to be deleted:"
    echo "- Resource Group: ${RESOURCE_GROUP:-N/A}"
    echo "- Stream Analytics Job: ${STREAM_ANALYTICS_JOB:-N/A}"
    echo "- Event Hubs Namespace: ${EVENT_HUB_NAMESPACE:-N/A}"
    echo "- Machine Learning Workspace: ${ML_WORKSPACE:-N/A}"
    echo "- Functions App: ${FUNCTION_APP:-N/A}"
    echo "- Cosmos DB Account: ${COSMOS_DB_ACCOUNT:-N/A}"
    echo "- Storage Account: ${STORAGE_ACCOUNT:-N/A}"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        echo "Operation cancelled."
        exit 0
    fi
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    
    case "$resource_type" in
        "group")
            az group show --name "$resource_name" &>/dev/null
            ;;
        "stream-analytics")
            az stream-analytics job show --name "$resource_name" --resource-group "$resource_group" &>/dev/null
            ;;
        "eventhub-namespace")
            az eventhubs namespace show --name "$resource_name" --resource-group "$resource_group" &>/dev/null
            ;;
        "ml-workspace")
            az ml workspace show --name "$resource_name" --resource-group "$resource_group" &>/dev/null
            ;;
        "functionapp")
            az functionapp show --name "$resource_name" --resource-group "$resource_group" &>/dev/null
            ;;
        "cosmosdb")
            az cosmosdb show --name "$resource_name" --resource-group "$resource_group" &>/dev/null
            ;;
        "storage")
            az storage account show --name "$resource_name" --resource-group "$resource_group" &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Banner
echo "=================================================="
echo "Azure Fraud Detection Pipeline Cleanup"
echo "=================================================="
echo ""

# Initialize log files
> "$LOG_FILE"
> "$ERROR_LOG"

log "Starting cleanup process..."

# Check prerequisites
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install Azure CLI first."
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Not logged into Azure. Please run 'az login' first."
    exit 1
fi

success "Prerequisites check completed"

# Load environment variables if available
if [[ -f "$ENV_FILE" ]]; then
    log "Loading environment variables from .env file..."
    source "$ENV_FILE"
    success "Environment variables loaded"
else
    warning "No .env file found. Will attempt to use environment variables."
fi

# Validate required environment variables
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
    echo ""
    echo "No RESOURCE_GROUP found in environment variables."
    echo "Available resource groups:"
    az group list --query "[?contains(name, 'fraud-detection')].{Name:name, Location:location}" --output table
    echo ""
    read -p "Enter the resource group name to delete: " RESOURCE_GROUP
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        error "Resource group name is required"
        exit 1
    fi
fi

# Verify resource group exists
if ! resource_exists "group" "$RESOURCE_GROUP" ""; then
    warning "Resource group '$RESOURCE_GROUP' does not exist or has already been deleted."
    echo "Cleanup completed - no resources to delete."
    exit 0
fi

# Extract resource names from environment or set defaults
STREAM_ANALYTICS_JOB="${STREAM_ANALYTICS_JOB:-}"
EVENT_HUB_NAMESPACE="${EVENT_HUB_NAMESPACE:-}"
ML_WORKSPACE="${ML_WORKSPACE:-}"
FUNCTION_APP="${FUNCTION_APP:-}"
COSMOS_DB_ACCOUNT="${COSMOS_DB_ACCOUNT:-}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"

# If individual resource names aren't available, list them from the resource group
if [[ -z "$STREAM_ANALYTICS_JOB" ]] || [[ -z "$EVENT_HUB_NAMESPACE" ]]; then
    log "Discovering resources in resource group..."
    
    # Get Stream Analytics jobs
    if [[ -z "$STREAM_ANALYTICS_JOB" ]]; then
        STREAM_ANALYTICS_JOB=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --resource-type "Microsoft.StreamAnalytics/streamingjobs" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi
    
    # Get Event Hub namespaces
    if [[ -z "$EVENT_HUB_NAMESPACE" ]]; then
        EVENT_HUB_NAMESPACE=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --resource-type "Microsoft.EventHub/namespaces" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi
    
    # Get ML workspaces
    if [[ -z "$ML_WORKSPACE" ]]; then
        ML_WORKSPACE=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --resource-type "Microsoft.MachineLearningServices/workspaces" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi
    
    # Get Function Apps
    if [[ -z "$FUNCTION_APP" ]]; then
        FUNCTION_APP=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --resource-type "Microsoft.Web/sites" \
            --query "[?kind=='functionapp,linux'].name | [0]" -o tsv 2>/dev/null || echo "")
    fi
    
    # Get Cosmos DB accounts
    if [[ -z "$COSMOS_DB_ACCOUNT" ]]; then
        COSMOS_DB_ACCOUNT=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --resource-type "Microsoft.DocumentDB/databaseAccounts" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi
    
    # Get Storage accounts
    if [[ -z "$STORAGE_ACCOUNT" ]]; then
        STORAGE_ACCOUNT=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --resource-type "Microsoft.Storage/storageAccounts" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi
fi

# Show what will be deleted and confirm
confirm_destruction

log "Beginning resource cleanup..."

# Option 1: Quick cleanup - Delete entire resource group
echo ""
echo "Choose cleanup method:"
echo "1. Quick cleanup - Delete entire resource group (recommended)"
echo "2. Individual resource cleanup - Delete resources one by one"
echo ""
read -p "Enter your choice (1 or 2): " cleanup_method

if [[ "$cleanup_method" == "1" ]]; then
    log "Performing quick cleanup - deleting resource group..."
    
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    success "Resource group deletion initiated: $RESOURCE_GROUP"
    echo ""
    echo "🕐 Note: Complete deletion may take 10-15 minutes."
    echo "   You can monitor progress in the Azure portal or with:"
    echo "   az group show --name $RESOURCE_GROUP"
    echo ""
    
else
    # Individual resource cleanup
    log "Performing individual resource cleanup..."
    
    # Stop Stream Analytics job first
    if [[ -n "$STREAM_ANALYTICS_JOB" ]] && resource_exists "stream-analytics" "$STREAM_ANALYTICS_JOB" "$RESOURCE_GROUP"; then
        log "Stopping Stream Analytics job: $STREAM_ANALYTICS_JOB"
        az stream-analytics job stop \
            --name "$STREAM_ANALYTICS_JOB" \
            --resource-group "$RESOURCE_GROUP" \
            >> "$LOG_FILE" 2>> "$ERROR_LOG" || warning "Failed to stop Stream Analytics job"
        
        log "Deleting Stream Analytics job: $STREAM_ANALYTICS_JOB"
        az stream-analytics job delete \
            --name "$STREAM_ANALYTICS_JOB" \
            --resource-group "$RESOURCE_GROUP" \
            --no-wait \
            >> "$LOG_FILE" 2>> "$ERROR_LOG" || warning "Failed to delete Stream Analytics job"
        
        success "Stream Analytics job deletion initiated"
    else
        warning "Stream Analytics job not found or already deleted"
    fi
    
    # Delete ML workspace (this will also delete associated compute)
    if [[ -n "$ML_WORKSPACE" ]] && resource_exists "ml-workspace" "$ML_WORKSPACE" "$RESOURCE_GROUP"; then
        log "Deleting Machine Learning workspace: $ML_WORKSPACE"
        az ml workspace delete \
            --name "$ML_WORKSPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            >> "$LOG_FILE" 2>> "$ERROR_LOG" || warning "Failed to delete ML workspace"
        
        success "Machine Learning workspace deletion initiated"
    else
        warning "ML workspace not found or already deleted"
    fi
    
    # Delete Function App
    if [[ -n "$FUNCTION_APP" ]] && resource_exists "functionapp" "$FUNCTION_APP" "$RESOURCE_GROUP"; then
        log "Deleting Functions App: $FUNCTION_APP"
        az functionapp delete \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            >> "$LOG_FILE" 2>> "$ERROR_LOG" || warning "Failed to delete Functions App"
        
        success "Functions App deleted"
    else
        warning "Functions App not found or already deleted"
    fi
    
    # Delete Cosmos DB account
    if [[ -n "$COSMOS_DB_ACCOUNT" ]] && resource_exists "cosmosdb" "$COSMOS_DB_ACCOUNT" "$RESOURCE_GROUP"; then
        log "Deleting Cosmos DB account: $COSMOS_DB_ACCOUNT"
        az cosmosdb delete \
            --name "$COSMOS_DB_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            >> "$LOG_FILE" 2>> "$ERROR_LOG" || warning "Failed to delete Cosmos DB account"
        
        success "Cosmos DB account deletion initiated"
    else
        warning "Cosmos DB account not found or already deleted"
    fi
    
    # Delete Event Hub namespace (this will delete all hubs and auth rules)
    if [[ -n "$EVENT_HUB_NAMESPACE" ]] && resource_exists "eventhub-namespace" "$EVENT_HUB_NAMESPACE" "$RESOURCE_GROUP"; then
        log "Deleting Event Hub namespace: $EVENT_HUB_NAMESPACE"
        az eventhubs namespace delete \
            --name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --no-wait \
            >> "$LOG_FILE" 2>> "$ERROR_LOG" || warning "Failed to delete Event Hub namespace"
        
        success "Event Hub namespace deletion initiated"
    else
        warning "Event Hub namespace not found or already deleted"
    fi
    
    # Delete Storage account
    if [[ -n "$STORAGE_ACCOUNT" ]] && resource_exists "storage" "$STORAGE_ACCOUNT" "$RESOURCE_GROUP"; then
        log "Deleting Storage account: $STORAGE_ACCOUNT"
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            >> "$LOG_FILE" 2>> "$ERROR_LOG" || warning "Failed to delete Storage account"
        
        success "Storage account deleted"
    else
        warning "Storage account not found or already deleted"
    fi
    
    # Wait a moment for deletions to propagate
    log "Waiting for resource deletions to complete..."
    sleep 30
    
    # Finally delete the resource group if it's empty or nearly empty
    log "Deleting resource group: $RESOURCE_GROUP"
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        >> "$LOG_FILE" 2>> "$ERROR_LOG" || warning "Failed to delete resource group"
    
    success "Resource group deletion initiated"
fi

# Clean up local files
log "Cleaning up local files..."

# Remove environment file
if [[ -f "$ENV_FILE" ]]; then
    rm -f "$ENV_FILE"
    success "Environment file removed"
fi

# Remove sample data files
sample_files=(
    "${SCRIPT_DIR}/../sample-transaction.json"
    "${SCRIPT_DIR}/../high-risk-transaction.json"
    "${SCRIPT_DIR}/../function-code"
)

for file in "${sample_files[@]}"; do
    if [[ -e "$file" ]]; then
        rm -rf "$file"
        success "Removed: $(basename "$file")"
    fi
done

# Clean up any temporary files
rm -f /tmp/eventhub-input.json /tmp/input-serialization.json 2>/dev/null || true
rm -f /tmp/cosmos-output.json /tmp/function-output.json 2>/dev/null || true
rm -f /tmp/fraud-detection-query.sql 2>/dev/null || true
rm -rf /tmp/fraud-alert-function 2>/dev/null || true

success "Local files cleaned up"

echo ""
echo "=================================================="
echo "🧹 CLEANUP COMPLETED SUCCESSFULLY! 🧹"
echo "=================================================="
echo ""
echo "✅ All fraud detection pipeline resources have been deleted"
echo ""
echo "📄 Cleanup logs:"
echo "   Success: ${LOG_FILE}"
echo "   Errors: ${ERROR_LOG}"
echo ""
echo "🕐 Note: Some resources may take additional time to fully delete."
echo "   You can verify complete deletion in the Azure portal."
echo ""

if [[ "$cleanup_method" == "1" ]]; then
    echo "💡 To verify resource group deletion:"
    echo "   az group show --name $RESOURCE_GROUP"
    echo "   (Should return 'ResourceGroupNotFound' when fully deleted)"
fi

echo ""
success "Fraud detection pipeline cleanup completed successfully"

# Final verification (optional)
if [[ "${1:-}" == "--verify" ]]; then
    echo ""
    log "Performing verification check..."
    
    if resource_exists "group" "$RESOURCE_GROUP" ""; then
        warning "Resource group still exists (deletion may still be in progress)"
        
        # List remaining resources
        remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([*])" -o tsv 2>/dev/null || echo "0")
        if [[ "$remaining_resources" -gt 0 ]]; then
            echo "Remaining resources in group:"
            az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table
        else
            log "Resource group is empty and should be deleted shortly"
        fi
    else
        success "Resource group has been completely deleted"
    fi
fi

log "Cleanup script execution completed"