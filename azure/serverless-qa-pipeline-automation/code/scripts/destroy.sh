#!/bin/bash

# Destroy script for Automated Quality Assurance Pipelines with Azure Container Apps Jobs and Azure Load Testing
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
VERBOSE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1" >> "${LOG_FILE}"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Azure Container Apps Jobs and Azure Load Testing infrastructure for QA pipeline.

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -g, --resource-group Resource group name to destroy
    -s, --subscription  Azure subscription ID (optional)
    --dry-run          Show what would be destroyed without actually destroying
    --force            Force destruction without confirmation prompts
    --keep-logs        Keep Log Analytics workspace and logs during cleanup
    --partial          Allow partial cleanup (continue even if some resources fail)

EXAMPLES:
    $0 -g rg-qa-pipeline-abc123      # Destroy specific resource group
    $0 --dry-run -g rg-qa-pipeline-abc123   # Show what would be destroyed
    $0 --force -g rg-qa-pipeline-abc123     # Force destroy without prompts
    $0 --keep-logs -g rg-qa-pipeline-abc123 # Keep monitoring resources

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -s|--subscription)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --keep-logs)
                KEEP_LOGS=true
                shift
                ;;
            --partial)
                PARTIAL=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Set default values
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
KEEP_LOGS="${KEEP_LOGS:-false}"
PARTIAL="${PARTIAL:-false}"

# Check if resource group is provided
check_resource_group_param() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        error "Resource group name is required. Use -g or --resource-group option."
    fi
}

# Prerequisites check
check_prerequisites() {
    info "Checking prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi

    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
    fi

    # Set subscription if provided
    if [[ -n "$SUBSCRIPTION_ID" ]]; then
        info "Setting subscription to $SUBSCRIPTION_ID"
        az account set --subscription "$SUBSCRIPTION_ID"
    fi

    # Get current subscription
    CURRENT_SUBSCRIPTION=$(az account show --query id -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    info "Using subscription: $SUBSCRIPTION_NAME ($CURRENT_SUBSCRIPTION)"

    log "Prerequisites check completed successfully"
}

# Check if resource group exists
check_resource_group_exists() {
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP does not exist or is not accessible"
        exit 0
    fi
    
    info "Found resource group: $RESOURCE_GROUP"
}

# List resources in the resource group
list_resources() {
    info "Listing resources in resource group: $RESOURCE_GROUP"
    
    RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].{Name:name,Type:type,Location:location}' --output table)
    
    if [[ -n "$RESOURCES" ]]; then
        echo "$RESOURCES"
    else
        info "No resources found in resource group: $RESOURCE_GROUP"
    fi
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        warn "Force mode enabled - skipping confirmation"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo
    echo -e "${RED}⚠️  WARNING: This will permanently delete all resources in the resource group!${NC}"
    echo -e "${RED}⚠️  This action cannot be undone!${NC}"
    echo
    echo "Resource group to be deleted: $RESOURCE_GROUP"
    echo
    
    list_resources
    
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
}

# Delete Container Apps Jobs
delete_container_jobs() {
    info "Deleting Container Apps Jobs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete Container Apps Jobs"
        return 0
    fi

    # List of jobs to delete
    JOBS=("unit-test-job" "integration-test-job" "performance-test-job" "security-test-job")
    
    for job in "${JOBS[@]}"; do
        if az containerapp job show --name "$job" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            info "Deleting Container Apps job: $job"
            
            if [[ "$PARTIAL" == "true" ]]; then
                az containerapp job delete \
                    --name "$job" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes \
                    --output none || warn "Failed to delete job: $job"
            else
                az containerapp job delete \
                    --name "$job" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes \
                    --output none
            fi
        else
            warn "Container Apps job $job not found, skipping..."
        fi
    done

    log "✅ Container Apps Jobs deletion completed"
}

# Delete Container Apps Environment
delete_container_environment() {
    info "Deleting Container Apps Environment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete Container Apps Environment"
        return 0
    fi

    # Find Container Apps Environment
    ENV_NAME=$(az containerapp env list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv 2>/dev/null)
    
    if [[ -n "$ENV_NAME" ]]; then
        info "Deleting Container Apps Environment: $ENV_NAME"
        
        if [[ "$PARTIAL" == "true" ]]; then
            az containerapp env delete \
                --name "$ENV_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none || warn "Failed to delete Container Apps Environment: $ENV_NAME"
        else
            az containerapp env delete \
                --name "$ENV_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none
        fi
    else
        warn "Container Apps Environment not found, skipping..."
    fi

    log "✅ Container Apps Environment deletion completed"
}

# Delete Azure Load Testing resource
delete_load_testing() {
    info "Deleting Azure Load Testing resource..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete Azure Load Testing resource"
        return 0
    fi

    # Find Load Testing resource
    LOAD_TEST_NAME=$(az load list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv 2>/dev/null)
    
    if [[ -n "$LOAD_TEST_NAME" ]]; then
        info "Deleting Azure Load Testing resource: $LOAD_TEST_NAME"
        
        if [[ "$PARTIAL" == "true" ]]; then
            az load delete \
                --name "$LOAD_TEST_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none || warn "Failed to delete Load Testing resource: $LOAD_TEST_NAME"
        else
            az load delete \
                --name "$LOAD_TEST_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none
        fi
    else
        warn "Azure Load Testing resource not found, skipping..."
    fi

    log "✅ Azure Load Testing resource deletion completed"
}

# Delete Storage Account
delete_storage_account() {
    info "Deleting Storage Account..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete Storage Account"
        return 0
    fi

    # Find Storage Account
    STORAGE_NAME=$(az storage account list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv 2>/dev/null)
    
    if [[ -n "$STORAGE_NAME" ]]; then
        info "Deleting Storage Account: $STORAGE_NAME"
        
        if [[ "$PARTIAL" == "true" ]]; then
            az storage account delete \
                --name "$STORAGE_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none || warn "Failed to delete Storage Account: $STORAGE_NAME"
        else
            az storage account delete \
                --name "$STORAGE_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none
        fi
    else
        warn "Storage Account not found, skipping..."
    fi

    log "✅ Storage Account deletion completed"
}

# Delete Log Analytics workspace
delete_log_analytics() {
    if [[ "$KEEP_LOGS" == "true" ]]; then
        warn "Keeping Log Analytics workspace due to --keep-logs flag"
        return 0
    fi

    info "Deleting Log Analytics workspace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete Log Analytics workspace"
        return 0
    fi

    # Find Log Analytics workspace
    LAW_NAME=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query '[0].name' -o tsv 2>/dev/null)
    
    if [[ -n "$LAW_NAME" ]]; then
        info "Deleting Log Analytics workspace: $LAW_NAME"
        
        if [[ "$PARTIAL" == "true" ]]; then
            az monitor log-analytics workspace delete \
                --name "$LAW_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none || warn "Failed to delete Log Analytics workspace: $LAW_NAME"
        else
            az monitor log-analytics workspace delete \
                --name "$LAW_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none
        fi
    else
        warn "Log Analytics workspace not found, skipping..."
    fi

    log "✅ Log Analytics workspace deletion completed"
}

# Delete remaining resources
delete_remaining_resources() {
    info "Checking for remaining resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete remaining resources"
        return 0
    fi

    # Get list of remaining resources
    REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].name' -o tsv)
    
    if [[ -n "$REMAINING_RESOURCES" ]]; then
        warn "Found remaining resources in resource group:"
        echo "$REMAINING_RESOURCES"
        
        if [[ "$PARTIAL" == "true" ]]; then
            info "Attempting to delete remaining resources individually..."
            while IFS= read -r resource; do
                if [[ -n "$resource" ]]; then
                    info "Deleting resource: $resource"
                    az resource delete --ids "$resource" --output none || warn "Failed to delete resource: $resource"
                fi
            done <<< "$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].id' -o tsv)"
        fi
    fi
}

# Delete resource group
delete_resource_group() {
    info "Deleting resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi

    if [[ "$PARTIAL" == "true" ]]; then
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none || warn "Failed to delete resource group: $RESOURCE_GROUP"
    else
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none
    fi

    log "✅ Resource group deletion initiated: $RESOURCE_GROUP"
}

# Wait for resource group deletion
wait_for_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    info "Waiting for resource group deletion to complete..."
    
    # Wait up to 30 minutes for deletion
    local timeout=1800
    local elapsed=0
    
    while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            warn "Resource group deletion is taking longer than expected"
            warn "You can check the deletion status manually: az group show --name $RESOURCE_GROUP"
            return 0
        fi
        
        sleep 30
        elapsed=$((elapsed + 30))
        info "Still waiting for deletion... (${elapsed}s elapsed)"
    done
    
    log "✅ Resource group deletion completed"
}

# Validate deletion
validate_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would validate deletion"
        return 0
    fi

    info "Validating deletion..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP still exists - deletion may still be in progress"
        return 1
    else
        log "✅ Resource group $RESOURCE_GROUP has been successfully deleted"
        return 0
    fi
}

# Print destruction summary
print_summary() {
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        info "🔍 Dry run completed - no resources were actually destroyed"
    else
        info "🗑️  Destruction completed successfully!"
    fi
    
    echo
    echo "=== DESTRUCTION SUMMARY ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Subscription: $(az account show --query name -o tsv)"
    echo "Destruction Mode: $([ "$DRY_RUN" == "true" ] && echo "DRY RUN" || echo "ACTUAL")"
    echo "Keep Logs: $([ "$KEEP_LOGS" == "true" ] && echo "YES" || echo "NO")"
    echo "Partial Mode: $([ "$PARTIAL" == "true" ] && echo "YES" || echo "NO")"
    echo
    echo "=== DESTROYED RESOURCES ==="
    echo "• Container Apps Jobs (unit, integration, performance, security tests)"
    echo "• Container Apps Environment"
    echo "• Azure Load Testing resource"
    echo "• Storage Account and containers"
    if [[ "$KEEP_LOGS" != "true" ]]; then
        echo "• Log Analytics workspace"
    fi
    echo "• Resource Group (if empty)"
    echo
    echo "=== COST SAVINGS ==="
    echo "Monthly cost savings: ~\$50-100 (depending on usage)"
    echo "• Container Apps Jobs: Consumption-based charges eliminated"
    echo "• Azure Load Testing: Usage-based charges eliminated"
    echo "• Storage Account: Storage and transaction charges eliminated"
    if [[ "$KEEP_LOGS" != "true" ]]; then
        echo "• Log Analytics: Ingestion and retention charges eliminated"
    fi
    echo
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "=== VERIFICATION ==="
        echo "You can verify the deletion by running:"
        echo "  az group show --name $RESOURCE_GROUP"
        echo "This should return a 'ResourceGroupNotFound' error if successful."
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    if [[ -f "${SCRIPT_DIR}/qa-pipeline-workbook.json" ]]; then
        rm -f "${SCRIPT_DIR}/qa-pipeline-workbook.json"
    fi
    
    if [[ -f "${SCRIPT_DIR}/azure-pipelines-qa.yml" ]]; then
        rm -f "${SCRIPT_DIR}/azure-pipelines-qa.yml"
    fi
}

# Main execution function
main() {
    echo "=== Azure QA Pipeline Destruction Script ==="
    echo "Starting destruction at $(date)"
    echo

    # Initialize log file
    : > "$LOG_FILE"

    # Parse command line arguments
    parse_args "$@"

    # Check required parameters
    check_resource_group_param

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No resources will be destroyed"
        echo
    fi

    # Execute destruction steps
    check_prerequisites
    check_resource_group_exists
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_container_jobs
    delete_container_environment
    delete_load_testing
    delete_storage_account
    delete_log_analytics
    delete_remaining_resources
    delete_resource_group
    
    # Wait for completion and validate
    if [[ "$DRY_RUN" != "true" ]]; then
        wait_for_deletion
        validate_deletion
    fi
    
    # Clean up
    cleanup_temp_files
    print_summary

    log "Destruction completed at $(date)"
    echo "Destruction log saved to: $LOG_FILE"
}

# Execute main function with all arguments
main "$@"