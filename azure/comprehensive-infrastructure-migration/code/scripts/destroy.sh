#!/bin/bash

# Azure Infrastructure Migration Workflows - Cleanup Script
# Recipe: Comprehensive Infrastructure Migration with Resource Mover and Update Manager
# Description: Safely removes all Azure resources created for the migration workflow demonstration

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
DEPLOYMENT_ENV="${SCRIPT_DIR}/deployment.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE" >&2
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $1${NC}" | tee -a "$LOG_FILE"
    fi
}

# Error handling
trap 'error "Script failed at line $LINENO. Exit code: $?"' ERR

# Help function
show_help() {
    cat << EOF
Azure Infrastructure Migration Workflows - Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Skip confirmation prompts and force deletion
    -d, --debug             Enable debug logging
    -k, --keep-logs         Keep Log Analytics workspace (for cost optimization)
    --dry-run              Show what would be deleted without actually deleting
    --config-file          Specify custom deployment.env file location
    --partial              Allow partial cleanup on errors (continue with other resources)

EXAMPLES:
    $0                      # Interactive cleanup with confirmations
    $0 --force             # Force cleanup without prompts
    $0 --dry-run           # Show what would be deleted
    $0 --partial --force   # Force cleanup, continue on errors

SAFETY FEATURES:
    - Resource validation before deletion
    - Confirmation prompts for destructive actions
    - Detailed logging of all operations
    - Partial cleanup support on failures
EOF
}

# Default configuration
FORCE=false
DEBUG=false
KEEP_LOGS=false
DRY_RUN=false
CONFIG_FILE=""
PARTIAL_CLEANUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -k|--keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --config-file)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --partial)
            PARTIAL_CLEANUP=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Load deployment configuration
load_deployment_config() {
    log "Loading deployment configuration..."
    
    # Use custom config file if provided
    if [[ -n "$CONFIG_FILE" ]]; then
        DEPLOYMENT_ENV="$CONFIG_FILE"
    fi
    
    if [[ ! -f "$DEPLOYMENT_ENV" ]]; then
        error "Deployment configuration file not found: $DEPLOYMENT_ENV"
        error "This file is created during deployment and contains resource information."
        error "If you deployed manually, you can create this file with your resource details."
        exit 1
    fi
    
    # Source the deployment environment
    source "$DEPLOYMENT_ENV"
    
    # Validate required variables
    local required_vars=("SOURCE_REGION" "TARGET_REGION" "RESOURCE_GROUP" "RANDOM_SUFFIX" "SUBSCRIPTION_ID")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var not found in deployment configuration"
            exit 1
        fi
    done
    
    log "Configuration loaded successfully:"
    log "  Source Region: ${SOURCE_REGION}"
    log "  Target Region: ${TARGET_REGION}"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Random Suffix: ${RANDOM_SUFFIX}"
    log "  Deployment Date: ${DEPLOYMENT_DATE:-'unknown'}"
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Verify subscription
    local current_subscription=$(az account show --query id -o tsv)
    if [[ "$current_subscription" != "$SUBSCRIPTION_ID" ]]; then
        warn "Current subscription ($current_subscription) differs from deployment subscription ($SUBSCRIPTION_ID)"
        if [[ "$FORCE" != "true" ]]; then
            read -p "Continue with current subscription? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Cleanup cancelled by user"
                exit 0
            fi
        fi
    fi
    
    log "Prerequisites check completed successfully"
}

# Resource validation
validate_resources() {
    log "Validating resources to be deleted..."
    
    local resources_found=0
    
    # Check source resource group
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "Found source resource group: $RESOURCE_GROUP"
        resources_found=$((resources_found + 1))
    else
        warn "Source resource group not found: $RESOURCE_GROUP"
    fi
    
    # Check target resource group
    if az group show --name "${RESOURCE_GROUP}-target" &> /dev/null; then
        log "Found target resource group: ${RESOURCE_GROUP}-target"
        resources_found=$((resources_found + 1))
    else
        warn "Target resource group not found: ${RESOURCE_GROUP}-target"
    fi
    
    # List resources in groups for confirmation
    if [[ "$resources_found" -eq 0 ]]; then
        warn "No resource groups found. Resources may have already been deleted."
        return 1
    fi
    
    log "Found $resources_found resource group(s) to delete"
    
    # Show detailed resource inventory if not in force mode
    if [[ "$FORCE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        log "Resource inventory:"
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            echo "Source Region Resources ($RESOURCE_GROUP):"
            az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null || echo "  No resources found"
        fi
        
        if az group show --name "${RESOURCE_GROUP}-target" &> /dev/null; then
            echo "Target Region Resources (${RESOURCE_GROUP}-target):"
            az resource list --resource-group "${RESOURCE_GROUP}-target" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null || echo "  No resources found"
        fi
    fi
    
    return 0
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    warn "This will permanently delete ALL resources created by the migration deployment."
    warn "This includes:"
    warn "  - Resource groups: $RESOURCE_GROUP and ${RESOURCE_GROUP}-target"
    warn "  - All virtual machines, networks, and storage in these groups"
    warn "  - Log Analytics workspace (unless --keep-logs is specified)"
    warn "  - All monitoring and migration configurations"
    echo
    warn "This action CANNOT be undone!"
    echo
    read -p "Are you absolutely sure you want to continue? Type 'DELETE' to confirm: " -r
    echo
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Cleanup cancelled by user (confirmation not provided)"
        exit 0
    fi
    
    # Second confirmation for safety
    read -p "Last chance! Type 'YES' to proceed with deletion: " -r
    echo
    if [[ "$REPLY" != "YES" ]]; then
        log "Cleanup cancelled by user (final confirmation not provided)"
        exit 0
    fi
}

# Delete move collection and Resource Mover resources
cleanup_resource_mover() {
    log "Cleaning up Azure Resource Mover resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would delete move collection: ${MOVE_COLLECTION_NAME:-'unknown'}"
        return 0
    fi
    
    # Check if move collection exists and clean it up
    if [[ -n "${MOVE_COLLECTION_NAME:-}" ]]; then
        if az resource-mover move-collection show --resource-group "$RESOURCE_GROUP" --move-collection-name "$MOVE_COLLECTION_NAME" &> /dev/null; then
            log "Deleting move collection: $MOVE_COLLECTION_NAME"
            
            # First, try to discard any pending moves
            if ! az resource-mover move-collection discard --resource-group "$RESOURCE_GROUP" --move-collection-name "$MOVE_COLLECTION_NAME" --yes 2>> "$ERROR_LOG"; then
                warn "Failed to discard move collection (may not be necessary)"
            fi
            
            # Delete the move collection
            if az resource-mover move-collection delete --resource-group "$RESOURCE_GROUP" --move-collection-name "$MOVE_COLLECTION_NAME" --yes 2>> "$ERROR_LOG"; then
                log "✅ Move collection deleted successfully"
            else
                if [[ "$PARTIAL_CLEANUP" == "true" ]]; then
                    warn "Failed to delete move collection, continuing with partial cleanup"
                else
                    error "Failed to delete move collection"
                    return 1
                fi
            fi
        else
            log "Move collection not found or already deleted"
        fi
    else
        log "Move collection name not found in configuration"
    fi
    
    # Remove Resource Mover extension if it was installed
    if az extension show --name resource-mover &> /dev/null; then
        log "Removing Azure Resource Mover CLI extension"
        az extension remove --name resource-mover 2>> "$ERROR_LOG" || warn "Failed to remove resource-mover extension"
    fi
}

# Delete maintenance configurations
cleanup_update_manager() {
    log "Cleaning up Azure Update Manager resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would delete maintenance configuration: ${MAINTENANCE_CONFIG_NAME:-'unknown'}"
        return 0
    fi
    
    # Clean up maintenance configuration
    if [[ -n "${MAINTENANCE_CONFIG_NAME:-}" ]]; then
        if az maintenance configuration show --resource-group "${RESOURCE_GROUP}-target" --name "$MAINTENANCE_CONFIG_NAME" &> /dev/null; then
            log "Deleting maintenance configuration: $MAINTENANCE_CONFIG_NAME"
            
            if az maintenance configuration delete --resource-group "${RESOURCE_GROUP}-target" --name "$MAINTENANCE_CONFIG_NAME" --yes 2>> "$ERROR_LOG"; then
                log "✅ Maintenance configuration deleted successfully"
            else
                if [[ "$PARTIAL_CLEANUP" == "true" ]]; then
                    warn "Failed to delete maintenance configuration, continuing with partial cleanup"
                else
                    error "Failed to delete maintenance configuration"
                    return 1
                fi
            fi
        else
            log "Maintenance configuration not found or already deleted"
        fi
    else
        log "Maintenance configuration name not found in configuration"
    fi
}

# Delete Log Analytics workspace (optional)
cleanup_log_analytics() {
    if [[ "$KEEP_LOGS" == "true" ]]; then
        log "Skipping Log Analytics workspace deletion (--keep-logs flag)"
        warn "Remember to manually delete the Log Analytics workspace to avoid ongoing charges:"
        warn "  Resource: ${LOG_WORKSPACE_NAME:-'unknown'}"
        warn "  Resource Group: $RESOURCE_GROUP"
        return 0
    fi
    
    log "Cleaning up Log Analytics workspace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would delete Log Analytics workspace: ${LOG_WORKSPACE_NAME:-'unknown'}"
        return 0
    fi
    
    if [[ -n "${LOG_WORKSPACE_NAME:-}" ]]; then
        if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE_NAME" &> /dev/null; then
            log "Deleting Log Analytics workspace: $LOG_WORKSPACE_NAME"
            
            if az monitor log-analytics workspace delete --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE_NAME" --yes --force 2>> "$ERROR_LOG"; then
                log "✅ Log Analytics workspace deleted successfully"
            else
                if [[ "$PARTIAL_CLEANUP" == "true" ]]; then
                    warn "Failed to delete Log Analytics workspace, continuing with partial cleanup"
                else
                    error "Failed to delete Log Analytics workspace"
                    return 1
                fi
            fi
        else
            log "Log Analytics workspace not found or already deleted"
        fi
    else
        log "Log Analytics workspace name not found in configuration"
    fi
}

# Delete resource groups (this will delete all contained resources)
cleanup_resource_groups() {
    log "Cleaning up resource groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would delete resource groups: $RESOURCE_GROUP, ${RESOURCE_GROUP}-target"
        return 0
    fi
    
    local deletion_jobs=()
    
    # Delete target resource group first (may contain migrated resources)
    if az group show --name "${RESOURCE_GROUP}-target" &> /dev/null; then
        log "Deleting target resource group: ${RESOURCE_GROUP}-target (this may take several minutes)"
        
        # Start deletion in background
        az group delete --name "${RESOURCE_GROUP}-target" --yes --no-wait 2>> "$ERROR_LOG" || {
            if [[ "$PARTIAL_CLEANUP" == "true" ]]; then
                warn "Failed to initiate target resource group deletion, continuing"
            else
                error "Failed to initiate target resource group deletion"
                return 1
            fi
        }
        deletion_jobs+=("${RESOURCE_GROUP}-target")
    else
        log "Target resource group not found or already deleted"
    fi
    
    # Delete source resource group
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting source resource group: $RESOURCE_GROUP (this may take several minutes)"
        
        # Start deletion in background
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>> "$ERROR_LOG" || {
            if [[ "$PARTIAL_CLEANUP" == "true" ]]; then
                warn "Failed to initiate source resource group deletion, continuing"
            else
                error "Failed to initiate source resource group deletion"
                return 1
            fi
        }
        deletion_jobs+=("$RESOURCE_GROUP")
    else
        log "Source resource group not found or already deleted"
    fi
    
    # Wait for deletions to complete
    if [[ ${#deletion_jobs[@]} -gt 0 ]]; then
        log "Waiting for resource group deletions to complete..."
        
        for rg in "${deletion_jobs[@]}"; do
            log "Monitoring deletion of resource group: $rg"
            
            local timeout=1800  # 30 minutes timeout
            local elapsed=0
            local interval=30
            
            while [[ $elapsed -lt $timeout ]]; do
                if ! az group show --name "$rg" &> /dev/null; then
                    log "✅ Resource group $rg deleted successfully"
                    break
                fi
                
                sleep $interval
                elapsed=$((elapsed + interval))
                
                if [[ $((elapsed % 300)) -eq 0 ]]; then  # Log every 5 minutes
                    log "Still waiting for resource group $rg deletion... (${elapsed}s elapsed)"
                fi
            done
            
            if [[ $elapsed -ge $timeout ]]; then
                if [[ "$PARTIAL_CLEANUP" == "true" ]]; then
                    warn "Resource group $rg deletion timed out after ${timeout}s, continuing"
                else
                    error "Resource group $rg deletion timed out after ${timeout}s"
                    return 1
                fi
            fi
        done
        
        log "✅ All resource group deletions completed"
    else
        log "No resource groups found to delete"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/migration-workbook.json"
        "${SCRIPT_DIR}/next-steps.md"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "[DRY-RUN] Would delete temporary file: $file"
            else
                rm -f "$file" 2>> "$ERROR_LOG" || warn "Failed to delete temporary file: $file"
                log "Deleted temporary file: $file"
            fi
        fi
    done
    
    # Optionally remove deployment config (ask user)
    if [[ -f "$DEPLOYMENT_ENV" ]] && [[ "$FORCE" != "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        read -p "Delete deployment configuration file ($DEPLOYMENT_ENV)? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f "$DEPLOYMENT_ENV" 2>> "$ERROR_LOG" || warn "Failed to delete deployment configuration"
            log "Deleted deployment configuration file"
        else
            log "Keeping deployment configuration file for reference"
        fi
    elif [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would ask about deleting deployment configuration file"
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    log "Generating cleanup summary..."
    
    local summary_file="${SCRIPT_DIR}/cleanup-summary.txt"
    
    cat > "$summary_file" << EOF
Azure Infrastructure Migration Workflows - Cleanup Summary

Cleanup Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Original Deployment Date: ${DEPLOYMENT_DATE:-'unknown'}

Resources Cleaned Up:
- Source Resource Group: $RESOURCE_GROUP
- Target Resource Group: ${RESOURCE_GROUP}-target
- Move Collection: ${MOVE_COLLECTION_NAME:-'unknown'}
- Maintenance Configuration: ${MAINTENANCE_CONFIG_NAME:-'unknown'}
- Log Analytics Workspace: ${LOG_WORKSPACE_NAME:-'unknown'} $(if [[ "$KEEP_LOGS" == "true" ]]; then echo "(KEPT)"; else echo "(DELETED)"; fi)

Original Configuration:
- Source Region: $SOURCE_REGION
- Target Region: $TARGET_REGION
- Random Suffix: $RANDOM_SUFFIX
- Subscription ID: $SUBSCRIPTION_ID

Cleanup Logs:
- Main Log: $LOG_FILE
- Error Log: $ERROR_LOG

Status: $(if [[ "$DRY_RUN" == "true" ]]; then echo "DRY RUN COMPLETED"; else echo "CLEANUP COMPLETED"; fi)
EOF
    
    log "Cleanup summary saved to: $summary_file"
}

# Main cleanup function
main() {
    log "Starting Azure Infrastructure Migration Workflows cleanup..."
    
    # Initialize logs
    echo "=== Azure Infrastructure Migration Cleanup Log ===" > "$LOG_FILE"
    echo "=== Azure Infrastructure Migration Cleanup Error Log ===" > "$ERROR_LOG"
    
    # Execute cleanup steps
    load_deployment_config
    check_prerequisites
    
    if ! validate_resources; then
        warn "Resource validation found issues, but continuing with cleanup"
    fi
    
    confirm_deletion
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "=== DRY RUN MODE - NO RESOURCES WILL BE DELETED ==="
    fi
    
    # Execute cleanup in proper order (specific resources first, then resource groups)
    if cleanup_resource_mover && cleanup_update_manager; then
        log "Specific resource cleanup completed successfully"
    elif [[ "$PARTIAL_CLEANUP" != "true" ]]; then
        error "Specific resource cleanup failed. Use --partial flag to continue with resource group deletion."
        exit 1
    else
        warn "Specific resource cleanup had errors, continuing with partial cleanup"
    fi
    
    cleanup_log_analytics
    cleanup_resource_groups
    cleanup_temp_files
    generate_cleanup_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "=== DRY RUN COMPLETED SUCCESSFULLY ==="
        log "No resources were actually deleted. Run without --dry-run to perform cleanup."
    else
        log "🎉 Cleanup completed successfully!"
        log ""
        log "All Azure resources have been removed."
        log "Check the cleanup summary for details: ${SCRIPT_DIR}/cleanup-summary.txt"
        
        if [[ "$KEEP_LOGS" == "true" ]]; then
            warn "Remember: Log Analytics workspace was kept and may incur charges"
            warn "Delete it manually when no longer needed"
        fi
        
        log ""
        log "Final verification: Check the Azure portal to confirm all resources are deleted"
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi