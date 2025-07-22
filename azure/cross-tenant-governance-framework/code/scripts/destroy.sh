#!/bin/bash

# ==============================================================================
# Azure Lighthouse and Automanage Cleanup Script
# ==============================================================================
# This script removes all resources created by the deployment script including
# Lighthouse delegations, Automanage configurations, VMs, and monitoring resources.
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if we're in dry run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            info "Running in dry-run mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            info "Force delete enabled - will skip confirmation prompts"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run     Show what would be deleted without actually deleting"
            echo "  --force       Skip confirmation prompts"
            echo "  -h, --help    Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Function to execute commands with dry run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: $description"
        echo "  Command: $cmd"
        return 0
    fi
    
    info "$description"
    if eval "$cmd"; then
        log "✅ $description completed successfully"
        return 0
    else
        if [ "$ignore_errors" = true ]; then
            warn "⚠️  $description failed but continuing..."
            return 0
        else
            error "❌ Failed to execute: $description"
            return 1
        fi
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$FORCE_DELETE" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    echo -e "${YELLOW}This will delete all resources created by the deployment script.${NC}"
    echo -e "${YELLOW}This action cannot be undone.${NC}"
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [[ ! -f ".deployment_state" ]]; then
        error "Deployment state file not found. Please run this script from the same directory as the deployment."
    fi
    
    # Source the deployment state file
    source .deployment_state
    
    # Verify required variables are set
    local required_vars=(
        "MSP_TENANT_ID"
        "MSP_SUBSCRIPTION_ID"
        "MSP_RESOURCE_GROUP"
        "CUSTOMER_TENANT_ID"
        "CUSTOMER_SUBSCRIPTION_ID"
        "CUSTOMER_RESOURCE_GROUP"
        "LOCATION"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var not found in deployment state"
        fi
    done
    
    log "✅ Deployment state loaded successfully"
    info "MSP Tenant: $MSP_TENANT_ID"
    info "Customer Tenant: $CUSTOMER_TENANT_ID"
    info "MSP Resource Group: $MSP_RESOURCE_GROUP"
    info "Customer Resource Group: $CUSTOMER_RESOURCE_GROUP"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    log "✅ Prerequisites check completed"
}

# Function to remove Automanage assignments
remove_automanage_assignments() {
    log "Removing Automanage configuration assignments..."
    
    # Switch to MSP tenant for cross-tenant management
    execute_cmd "az login --tenant ${MSP_TENANT_ID} --allow-no-subscriptions" "Logging in to MSP tenant"
    execute_cmd "az account set --subscription ${MSP_SUBSCRIPTION_ID}" "Setting MSP subscription context"
    
    # Remove Automanage assignments from customer VMs
    if [[ -n "${VM_NAME:-}" ]]; then
        execute_cmd "az automanage configuration-profile-assignment delete --resource-group ${CUSTOMER_RESOURCE_GROUP} --vm-name ${VM_NAME} --configuration-profile-assignment-name default --subscription ${CUSTOMER_SUBSCRIPTION_ID} --yes" "Removing Automanage assignment from ${VM_NAME}" true
    fi
    
    log "✅ Automanage assignments removed"
}

# Function to remove customer resources
remove_customer_resources() {
    log "Removing customer tenant resources..."
    
    # Switch to customer tenant
    execute_cmd "az login --tenant ${CUSTOMER_TENANT_ID} --allow-no-subscriptions" "Logging in to customer tenant"
    execute_cmd "az account set --subscription ${CUSTOMER_SUBSCRIPTION_ID}" "Setting customer subscription context"
    
    # Check if customer resource group exists
    if [ "$DRY_RUN" = false ]; then
        if ! az group show --name ${CUSTOMER_RESOURCE_GROUP} &> /dev/null; then
            warn "Customer resource group ${CUSTOMER_RESOURCE_GROUP} not found, skipping..."
            return 0
        fi
    fi
    
    # List resources in customer resource group for confirmation
    if [ "$DRY_RUN" = false ]; then
        info "Resources in customer resource group:"
        az resource list --resource-group ${CUSTOMER_RESOURCE_GROUP} --output table || true
    fi
    
    # Delete customer resource group and all resources
    execute_cmd "az group delete --name ${CUSTOMER_RESOURCE_GROUP} --yes --no-wait" "Deleting customer resource group ${CUSTOMER_RESOURCE_GROUP}"
    
    # Wait for deletion to complete (optional, can be skipped for faster cleanup)
    if [ "$DRY_RUN" = false ]; then
        info "Waiting for customer resource group deletion to complete..."
        local timeout=300  # 5 minutes
        local elapsed=0
        
        while az group show --name ${CUSTOMER_RESOURCE_GROUP} &> /dev/null; do
            if [ $elapsed -ge $timeout ]; then
                warn "Timeout waiting for resource group deletion. Continuing with cleanup..."
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
            info "Still waiting for deletion... (${elapsed}s elapsed)"
        done
    fi
    
    log "✅ Customer resources removed"
}

# Function to remove Lighthouse delegation
remove_lighthouse_delegation() {
    log "Removing Lighthouse delegation..."
    
    # Stay in customer tenant context for delegation removal
    execute_cmd "az login --tenant ${CUSTOMER_TENANT_ID} --allow-no-subscriptions" "Ensuring customer tenant context"
    execute_cmd "az account set --subscription ${CUSTOMER_SUBSCRIPTION_ID}" "Setting customer subscription context"
    
    # List current delegations
    if [ "$DRY_RUN" = false ]; then
        info "Current Lighthouse delegations:"
        az managedservices assignment list --output table || true
    fi
    
    # Remove delegation assignments
    if [ "$DRY_RUN" = false ]; then
        local assignment_ids=$(az managedservices assignment list --query "[].name" --output tsv)
        if [[ -n "$assignment_ids" ]]; then
            for assignment_id in $assignment_ids; do
                execute_cmd "az managedservices assignment delete --assignment $assignment_id --subscription ${CUSTOMER_SUBSCRIPTION_ID}" "Removing delegation assignment $assignment_id" true
            done
        else
            info "No Lighthouse delegation assignments found"
        fi
    fi
    
    # Remove specific deployment if deployment name is available
    if [[ -n "${LIGHTHOUSE_DEPLOYMENT_NAME:-}" ]]; then
        execute_cmd "az deployment sub delete --name ${LIGHTHOUSE_DEPLOYMENT_NAME}" "Removing Lighthouse deployment ${LIGHTHOUSE_DEPLOYMENT_NAME}" true
    fi
    
    log "✅ Lighthouse delegation removed"
}

# Function to remove monitoring resources
remove_monitoring_resources() {
    log "Removing monitoring and alerting resources..."
    
    # Switch back to MSP tenant
    execute_cmd "az login --tenant ${MSP_TENANT_ID} --allow-no-subscriptions" "Switching to MSP tenant"
    execute_cmd "az account set --subscription ${MSP_SUBSCRIPTION_ID}" "Setting MSP subscription context"
    
    # Remove alert rules
    if [[ -n "${ALERT_RULE_NAME:-}" ]]; then
        execute_cmd "az monitor metrics alert delete --resource-group ${MSP_RESOURCE_GROUP} --name ${ALERT_RULE_NAME}" "Removing alert rule ${ALERT_RULE_NAME}" true
    fi
    
    # Remove action groups
    if [[ -n "${ACTION_GROUP_NAME:-}" ]]; then
        execute_cmd "az monitor action-group delete --resource-group ${MSP_RESOURCE_GROUP} --name ${ACTION_GROUP_NAME}" "Removing action group ${ACTION_GROUP_NAME}" true
    fi
    
    log "✅ Monitoring resources removed"
}

# Function to remove Automanage configuration
remove_automanage_configuration() {
    log "Removing Automanage configuration profile..."
    
    # Remove Automanage configuration profile
    if [[ -n "${AUTOMANAGE_PROFILE_NAME:-}" ]]; then
        execute_cmd "az automanage configuration-profile delete --resource-group ${MSP_RESOURCE_GROUP} --configuration-profile-name ${AUTOMANAGE_PROFILE_NAME}" "Removing Automanage profile ${AUTOMANAGE_PROFILE_NAME}" true
    fi
    
    log "✅ Automanage configuration removed"
}

# Function to remove MSP resources
remove_msp_resources() {
    log "Removing MSP tenant resources..."
    
    # Check if MSP resource group exists
    if [ "$DRY_RUN" = false ]; then
        if ! az group show --name ${MSP_RESOURCE_GROUP} &> /dev/null; then
            warn "MSP resource group ${MSP_RESOURCE_GROUP} not found, skipping..."
            return 0
        fi
    fi
    
    # List resources in MSP resource group for confirmation
    if [ "$DRY_RUN" = false ]; then
        info "Resources in MSP resource group:"
        az resource list --resource-group ${MSP_RESOURCE_GROUP} --output table || true
    fi
    
    # Delete MSP resource group and all resources
    execute_cmd "az group delete --name ${MSP_RESOURCE_GROUP} --yes --no-wait" "Deleting MSP resource group ${MSP_RESOURCE_GROUP}"
    
    # Wait for deletion to complete (optional)
    if [ "$DRY_RUN" = false ]; then
        info "Waiting for MSP resource group deletion to complete..."
        local timeout=300  # 5 minutes
        local elapsed=0
        
        while az group show --name ${MSP_RESOURCE_GROUP} &> /dev/null; do
            if [ $elapsed -ge $timeout ]; then
                warn "Timeout waiting for resource group deletion. Continuing with cleanup..."
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
            info "Still waiting for deletion... (${elapsed}s elapsed)"
        done
    fi
    
    log "✅ MSP resources removed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        ".deployment_state"
        "lighthouse-delegation.json"
        "lighthouse-parameters.json"
        "automanage-profile.json"
        "deployment-summary.txt"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            execute_cmd "rm -f $file" "Removing $file"
        fi
    done
    
    log "✅ Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    if [ "$DRY_RUN" = true ]; then
        info "Skipping verification in dry-run mode"
        return 0
    fi
    
    local cleanup_success=true
    
    # Check MSP resource group
    execute_cmd "az login --tenant ${MSP_TENANT_ID} --allow-no-subscriptions" "Logging in to MSP tenant"
    execute_cmd "az account set --subscription ${MSP_SUBSCRIPTION_ID}" "Setting MSP subscription context"
    
    if az group show --name ${MSP_RESOURCE_GROUP} &> /dev/null; then
        warn "MSP resource group ${MSP_RESOURCE_GROUP} still exists"
        cleanup_success=false
    fi
    
    # Check customer resource group
    execute_cmd "az login --tenant ${CUSTOMER_TENANT_ID} --allow-no-subscriptions" "Logging in to customer tenant"
    execute_cmd "az account set --subscription ${CUSTOMER_SUBSCRIPTION_ID}" "Setting customer subscription context"
    
    if az group show --name ${CUSTOMER_RESOURCE_GROUP} &> /dev/null; then
        warn "Customer resource group ${CUSTOMER_RESOURCE_GROUP} still exists"
        cleanup_success=false
    fi
    
    # Check Lighthouse delegations
    local delegations=$(az managedservices assignment list --query "length(@)" --output tsv)
    if [[ "$delegations" -gt 0 ]]; then
        warn "Lighthouse delegations still active"
        cleanup_success=false
    fi
    
    if [ "$cleanup_success" = true ]; then
        log "✅ Cleanup verification passed"
    else
        warn "Some resources may still exist. Please check Azure Portal for manual cleanup."
    fi
}

# Function to create cleanup summary
create_cleanup_summary() {
    log "Creating cleanup summary..."
    
    cat > cleanup-summary.txt << EOF
=================================================================
Azure Lighthouse and Automanage Cleanup Summary
=================================================================
Cleanup Date: $(date)
Cleanup Mode: DRY_RUN=${DRY_RUN}, FORCE_DELETE=${FORCE_DELETE}

Resources Removed:
- MSP Resource Group: ${MSP_RESOURCE_GROUP}
- Customer Resource Group: ${CUSTOMER_RESOURCE_GROUP}
- Lighthouse Delegation: Cross-Tenant Resource Governance
- Automanage Configuration: ${AUTOMANAGE_PROFILE_NAME:-N/A}
- Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE:-N/A}
- Monitoring Resources: ${ACTION_GROUP_NAME:-N/A}, ${ALERT_RULE_NAME:-N/A}

Tenant Information:
- MSP Tenant ID: ${MSP_TENANT_ID}
- Customer Tenant ID: ${CUSTOMER_TENANT_ID}

Cleanup Status: $([ "$DRY_RUN" = true ] && echo "DRY RUN COMPLETED" || echo "COMPLETED")

Next Steps:
1. Verify all resources are removed in Azure Portal
2. Check for any remaining costs in billing
3. Remove any Azure AD groups created for MSP team (if applicable)
4. Update documentation and access controls as needed

Note: If running in dry-run mode, no actual resources were deleted.
=================================================================
EOF
    
    log "✅ Cleanup summary created: cleanup-summary.txt"
}

# Main cleanup function
main() {
    log "Starting Azure Lighthouse and Automanage cleanup..."
    
    # Check if running from correct directory
    if [[ ! -f "destroy.sh" ]]; then
        error "Please run this script from the scripts directory"
    fi
    
    # Load deployment state and run cleanup steps
    load_deployment_state
    check_prerequisites
    confirm_deletion
    
    # Remove resources in reverse order of creation
    remove_automanage_assignments
    remove_customer_resources
    remove_lighthouse_delegation
    remove_monitoring_resources
    remove_automanage_configuration
    remove_msp_resources
    cleanup_local_files
    verify_cleanup
    create_cleanup_summary
    
    log "🎉 Cleanup completed successfully!"
    
    if [ "$DRY_RUN" = false ]; then
        info "Cleanup summary saved to: cleanup-summary.txt"
        info "All resources have been removed from both tenants"
    else
        info "This was a dry run. No resources were actually deleted."
        info "Run without --dry-run to perform actual cleanup"
    fi
    
    warn "Please verify in Azure Portal that all resources have been removed"
}

# Trap to handle script interruption
trap 'error "Script interrupted by user"' INT TERM

# Run main function
main "$@"