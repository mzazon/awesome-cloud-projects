#!/bin/bash

# Code Tutorial Generator Cleanup Script
# Safely removes all Azure resources created by the deployment script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display script usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Code Tutorial Generator infrastructure from Azure.

Options:
    -r, --resource-group NAME    Resource group name (required)
    -f, --force                  Skip confirmation prompts
    -l, --log-file FILE          Deployment log file to read settings from
    --keep-logs                  Keep deployment logs after cleanup
    --individual                 Delete resources individually (safer)
    -h, --help                   Show this help message
    --dry-run                    Preview changes without deletion
    --verbose                    Enable verbose logging

Example:
    $0 --resource-group rg-tutorial-prod
    $0 --log-file deployment-abc123.log --force
EOF
}

# Initialize variables with defaults
RESOURCE_GROUP=""
FORCE=false
LOG_FILE=""
KEEP_LOGS=false
INDIVIDUAL=false
DRY_RUN=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -l|--log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        --keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        --individual)
            INDIVIDUAL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Enable verbose output if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

# Set Azure CLI output format
export AZURE_CORE_OUTPUT="table"

log_info "Starting Code Tutorial Generator cleanup..."

# Check prerequisites
log_info "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    log_error "Azure CLI not found. Please install Azure CLI."
    exit 1
fi

# Check Azure login status
if ! az account show &> /dev/null; then
    log_error "Not logged in to Azure. Please run 'az login'."
    exit 1
fi

# Load settings from deployment log if provided
if [[ -n "$LOG_FILE" ]]; then
    if [[ ! -f "$LOG_FILE" ]]; then
        log_error "Deployment log file not found: $LOG_FILE"
        exit 1
    fi
    
    log_info "Loading settings from deployment log: $LOG_FILE"
    
    # Source the log file to get environment variables
    # shellcheck source=/dev/null
    source "$LOG_FILE"
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log_error "Resource group not found in deployment log"
        exit 1
    fi
    
    log_info "Loaded settings:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    [[ -n "${STORAGE_ACCOUNT:-}" ]] && log_info "  Storage Account: $STORAGE_ACCOUNT"
    [[ -n "${FUNCTION_APP:-}" ]] && log_info "  Function App: $FUNCTION_APP"
    [[ -n "${OPENAI_ACCOUNT:-}" ]] && log_info "  OpenAI Account: $OPENAI_ACCOUNT"
fi

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    log_error "Resource group name is required. Use -r/--resource-group or -l/--log-file."
    usage
    exit 1
fi

# Check if resource group exists
log_info "Checking if resource group exists..."
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    log_warning "Resource group '$RESOURCE_GROUP' does not exist"
    log_info "Nothing to clean up"
    exit 0
fi

# Get subscription information
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
log_info "Using subscription: $SUBSCRIPTION_ID"

# List resources in the resource group
log_info "Discovering resources in resource group '$RESOURCE_GROUP'..."
RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output json)
RESOURCE_COUNT=$(echo "$RESOURCES" | jq length)

if [[ "$RESOURCE_COUNT" -eq 0 ]]; then
    log_warning "No resources found in resource group '$RESOURCE_GROUP'"
    log_info "Resource group appears to be empty"
else
    log_info "Found $RESOURCE_COUNT resources:"
    echo "$RESOURCES" | jq -r '.[] | "  - \(.Name) (\(.Type))"'
fi

# Exit if dry run
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry run complete. No resources were deleted."
    exit 0
fi

# Confirmation prompt (unless forced)
if [[ "$FORCE" != "true" ]]; then
    echo
    log_warning "This will permanently delete ALL resources in resource group: $RESOURCE_GROUP"
    log_warning "This action cannot be undone!"
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r REPLY
    echo
    
    if [[ ! "$REPLY" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
fi

# Function to delete individual resources
delete_individual_resources() {
    log_info "Deleting resources individually..."
    
    # Get all resources sorted by dependency order (reverse creation order)
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{id:id, type:type, name:name}" --output json)
    
    # Delete Function Apps first (they depend on storage)
    echo "$resources" | jq -r '.[] | select(.type == "Microsoft.Web/sites") | .id' | while read -r resource_id; do
        if [[ -n "$resource_id" ]]; then
            local resource_name
            resource_name=$(echo "$resource_id" | awk -F'/' '{print $NF}')
            log_info "Deleting Function App: $resource_name"
            
            if az resource delete --ids "$resource_id" --verbose; then
                log_success "Function App deleted: $resource_name"
            else
                log_error "Failed to delete Function App: $resource_name"
            fi
        fi
    done
    
    # Delete Cognitive Services (OpenAI) accounts
    echo "$resources" | jq -r '.[] | select(.type == "Microsoft.CognitiveServices/accounts") | .id' | while read -r resource_id; do
        if [[ -n "$resource_id" ]]; then
            local resource_name
            resource_name=$(echo "$resource_id" | awk -F'/' '{print $NF}')
            log_info "Deleting OpenAI Service: $resource_name"
            
            if az resource delete --ids "$resource_id" --verbose; then
                log_success "OpenAI Service deleted: $resource_name"
            else
                log_error "Failed to delete OpenAI Service: $resource_name"
            fi
        fi
    done
    
    # Delete Storage Accounts
    echo "$resources" | jq -r '.[] | select(.type == "Microsoft.Storage/storageAccounts") | .id' | while read -r resource_id; do
        if [[ -n "$resource_id" ]]; then
            local resource_name
            resource_name=$(echo "$resource_id" | awk -F'/' '{print $NF}')
            log_info "Deleting Storage Account: $resource_name"
            
            if az resource delete --ids "$resource_id" --verbose; then
                log_success "Storage Account deleted: $resource_name"
            else
                log_error "Failed to delete Storage Account: $resource_name"
            fi
        fi
    done
    
    # Delete any remaining resources
    echo "$resources" | jq -r '.[] | .id' | while read -r resource_id; do
        if [[ -n "$resource_id" ]] && az resource show --ids "$resource_id" &> /dev/null; then
            local resource_name
            local resource_type
            resource_name=$(echo "$resource_id" | awk -F'/' '{print $NF}')
            resource_type=$(az resource show --ids "$resource_id" --query "type" --output tsv)
            
            log_info "Deleting remaining resource: $resource_name ($resource_type)"
            
            if az resource delete --ids "$resource_id" --verbose; then
                log_success "Resource deleted: $resource_name"
            else
                log_warning "Failed to delete resource: $resource_name"
            fi
        fi
    done
}

# Function to delete entire resource group
delete_resource_group() {
    log_info "Deleting entire resource group..."
    
    if az group delete --name "$RESOURCE_GROUP" --yes --no-wait; then
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log_info "Note: Deletion may take several minutes to complete"
        
        # Optional: Wait for deletion to complete
        if [[ "$FORCE" != "true" ]]; then
            read -p "Wait for deletion to complete? (y/n): " -r WAIT_REPLY
            if [[ "$WAIT_REPLY" =~ ^[Yy]$ ]]; then
                log_info "Waiting for resource group deletion to complete..."
                
                local timeout=600  # 10 minutes timeout
                local elapsed=0
                local interval=30
                
                while az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; do
                    if [[ $elapsed -ge $timeout ]]; then
                        log_warning "Timeout waiting for deletion. Check Azure portal for status."
                        break
                    fi
                    
                    log_info "Still deleting... (${elapsed}s elapsed)"
                    sleep $interval
                    elapsed=$((elapsed + interval))
                done
                
                if ! az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
                    log_success "Resource group deleted successfully"
                fi
            fi
        fi
    else
        log_error "Failed to initiate resource group deletion"
        exit 1
    fi
}

# Perform cleanup based on method choice
if [[ "$INDIVIDUAL" == "true" ]]; then
    delete_individual_resources
    
    # Check if resource group is now empty
    remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv)
    if [[ "$remaining_resources" -eq 0 ]]; then
        log_info "All resources deleted. Removing empty resource group..."
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait
        log_success "Empty resource group deletion initiated"
    else
        log_warning "$remaining_resources resources remain in the resource group"
        log_info "You may need to delete the resource group manually"
    fi
else
    delete_resource_group
fi

# Cleanup deployment logs if not keeping them
if [[ "$KEEP_LOGS" != "true" ]] && [[ -n "$LOG_FILE" ]] && [[ -f "$LOG_FILE" ]]; then
    log_info "Cleaning up deployment log file..."
    rm -f "$LOG_FILE"
    log_success "Deployment log file removed: $LOG_FILE"
fi

# Look for and optionally clean up other deployment logs in current directory
if [[ "$KEEP_LOGS" != "true" ]]; then
    local deployment_logs
    deployment_logs=$(find . -maxdepth 1 -name "deployment-*.log" 2>/dev/null || true)
    
    if [[ -n "$deployment_logs" ]]; then
        log_info "Found additional deployment logs:"
        echo "$deployment_logs"
        
        if [[ "$FORCE" != "true" ]]; then
            read -p "Remove these log files as well? (y/n): " -r LOG_REPLY
            if [[ "$LOG_REPLY" =~ ^[Yy]$ ]]; then
                echo "$deployment_logs" | xargs rm -f
                log_success "Additional deployment logs removed"
            fi
        else
            echo "$deployment_logs" | xargs rm -f
            log_success "Additional deployment logs removed"
        fi
    fi
fi

# Final verification
log_info "Verifying cleanup..."
if az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "false"; then
    log_success "Cleanup completed successfully!"
    log_info "Resource group '$RESOURCE_GROUP' has been deleted"
else
    remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "unknown")
    if [[ "$remaining_resources" == "0" ]]; then
        log_success "All resources deleted successfully!"
        log_info "Empty resource group '$RESOURCE_GROUP' may still exist"
    else
        log_warning "Cleanup may be incomplete"
        log_warning "Resource group '$RESOURCE_GROUP' still exists with $remaining_resources resources"
        log_info "Check the Azure portal for remaining resources"
    fi
fi

echo
log_info "Cleanup Summary:"
log_info "  Resource Group: $RESOURCE_GROUP"
log_info "  Method: $(if [[ "$INDIVIDUAL" == "true" ]]; then echo "Individual resource deletion"; else echo "Resource group deletion"; fi)"
log_info "  Logs Kept: $(if [[ "$KEEP_LOGS" == "true" ]]; then echo "Yes"; else echo "No"; fi)"
echo
log_success "Code Tutorial Generator cleanup completed!"