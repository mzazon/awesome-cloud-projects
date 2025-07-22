#!/bin/bash

# Azure Data Share and Purview Cross-Tenant Cleanup Script
# This script removes all resources created for cross-tenant data collaboration

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if Azure CLI is installed and logged in
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://aka.ms/InstallAzureCLI"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    log_success "Prerequisites check passed"
}

# Validate environment variables
validate_environment() {
    log_info "Validating environment variables..."
    
    # Check required environment variables
    local required_vars=(
        "PROVIDER_SUBSCRIPTION_ID"
        "CONSUMER_SUBSCRIPTION_ID"
        "LOCATION"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            error_exit "Environment variable $var is required but not set"
        fi
    done
    
    # Validate subscription IDs format (basic UUID format check)
    if [[ ! $PROVIDER_SUBSCRIPTION_ID =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        error_exit "PROVIDER_SUBSCRIPTION_ID must be a valid UUID format"
    fi
    
    if [[ ! $CONSUMER_SUBSCRIPTION_ID =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        error_exit "CONSUMER_SUBSCRIPTION_ID must be a valid UUID format"
    fi
    
    log_success "Environment validation passed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export PROVIDER_RG="${PROVIDER_RG:-rg-datashare-provider}"
    export CONSUMER_RG="${CONSUMER_RG:-rg-datashare-consumer}"
    
    # Generate unique suffix for resource names if not provided
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        log_warning "RANDOM_SUFFIX not provided. Using default suffix 'cleanup'"
        export RANDOM_SUFFIX="cleanup"
    fi
    
    # Set resource names with suffix
    export PROVIDER_STORAGE="${PROVIDER_STORAGE:-stprovider${RANDOM_SUFFIX}}"
    export CONSUMER_STORAGE="${CONSUMER_STORAGE:-stconsumer${RANDOM_SUFFIX}}"
    export PROVIDER_SHARE="${PROVIDER_SHARE:-share-provider-${RANDOM_SUFFIX}}"
    export CONSUMER_SHARE="${CONSUMER_SHARE:-share-consumer-${RANDOM_SUFFIX}}"
    export PROVIDER_PURVIEW="${PROVIDER_PURVIEW:-purview-provider-${RANDOM_SUFFIX}}"
    export CONSUMER_PURVIEW="${CONSUMER_PURVIEW:-purview-consumer-${RANDOM_SUFFIX}}"
    
    # Log the configuration
    log_info "Cleanup configuration:"
    log_info "  Provider Subscription: $PROVIDER_SUBSCRIPTION_ID"
    log_info "  Consumer Subscription: $CONSUMER_SUBSCRIPTION_ID"
    log_info "  Location: $LOCATION"
    log_info "  Provider Resource Group: $PROVIDER_RG"
    log_info "  Consumer Resource Group: $CONSUMER_RG"
    
    log_success "Environment setup completed"
}

# Check if resource group exists
resource_group_exists() {
    local subscription_id=$1
    local resource_group=$2
    
    az account set --subscription "$subscription_id"
    if az group show --name "$resource_group" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Wait for resource group deletion
wait_for_resource_group_deletion() {
    local subscription_id=$1
    local resource_group=$2
    local max_wait=1800  # 30 minutes
    local interval=30
    local elapsed=0
    
    az account set --subscription "$subscription_id"
    
    while [ $elapsed -lt $max_wait ]; do
        if ! az group show --name "$resource_group" &> /dev/null; then
            log_success "Resource group $resource_group has been deleted"
            return 0
        fi
        
        log_info "Waiting for resource group $resource_group to be deleted... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log_warning "Timeout waiting for resource group $resource_group deletion"
    return 1
}

# Delete consumer resources
delete_consumer_resources() {
    log_info "Deleting consumer resources..."
    
    # Switch to consumer subscription
    az account set --subscription "${CONSUMER_SUBSCRIPTION_ID}"
    
    # Check if consumer resource group exists
    if resource_group_exists "${CONSUMER_SUBSCRIPTION_ID}" "${CONSUMER_RG}"; then
        log_info "Consumer resource group $CONSUMER_RG exists, proceeding with deletion"
        
        # List resources in the consumer resource group before deletion
        log_info "Resources in consumer resource group:"
        az resource list --resource-group "${CONSUMER_RG}" --query '[].{Name:name, Type:type}' --output table || true
        
        # Delete consumer resource group
        log_info "Deleting consumer resource group: $CONSUMER_RG"
        az group delete \
            --name "${CONSUMER_RG}" \
            --yes \
            --no-wait
        
        log_success "Consumer resource group deletion initiated"
        
        # Wait for deletion to complete if not in no-wait mode
        if [ "${WAIT_FOR_DELETION:-false}" = "true" ]; then
            wait_for_resource_group_deletion "${CONSUMER_SUBSCRIPTION_ID}" "${CONSUMER_RG}"
        fi
    else
        log_warning "Consumer resource group $CONSUMER_RG does not exist or has already been deleted"
    fi
}

# Delete provider resources
delete_provider_resources() {
    log_info "Deleting provider resources..."
    
    # Switch to provider subscription
    az account set --subscription "${PROVIDER_SUBSCRIPTION_ID}"
    
    # Check if provider resource group exists
    if resource_group_exists "${PROVIDER_SUBSCRIPTION_ID}" "${PROVIDER_RG}"; then
        log_info "Provider resource group $PROVIDER_RG exists, proceeding with deletion"
        
        # List resources in the provider resource group before deletion
        log_info "Resources in provider resource group:"
        az resource list --resource-group "${PROVIDER_RG}" --query '[].{Name:name, Type:type}' --output table || true
        
        # Delete provider resource group
        log_info "Deleting provider resource group: $PROVIDER_RG"
        az group delete \
            --name "${PROVIDER_RG}" \
            --yes \
            --no-wait
        
        log_success "Provider resource group deletion initiated"
        
        # Wait for deletion to complete if not in no-wait mode
        if [ "${WAIT_FOR_DELETION:-false}" = "true" ]; then
            wait_for_resource_group_deletion "${PROVIDER_SUBSCRIPTION_ID}" "${PROVIDER_RG}"
        fi
    else
        log_warning "Provider resource group $PROVIDER_RG does not exist or has already been deleted"
    fi
}

# Check for any remaining resources
check_remaining_resources() {
    log_info "Checking for any remaining resources..."
    
    # Check provider subscription
    az account set --subscription "${PROVIDER_SUBSCRIPTION_ID}"
    local provider_resources=$(az resource list --query "[?resourceGroup=='${PROVIDER_RG}'].{Name:name, Type:type}" --output tsv 2>/dev/null | wc -l)
    
    if [ "$provider_resources" -gt 0 ]; then
        log_warning "Found $provider_resources remaining resources in provider subscription"
        az resource list --query "[?resourceGroup=='${PROVIDER_RG}'].{Name:name, Type:type}" --output table
    else
        log_success "No remaining resources found in provider subscription"
    fi
    
    # Check consumer subscription
    az account set --subscription "${CONSUMER_SUBSCRIPTION_ID}"
    local consumer_resources=$(az resource list --query "[?resourceGroup=='${CONSUMER_RG}'].{Name:name, Type:type}" --output tsv 2>/dev/null | wc -l)
    
    if [ "$consumer_resources" -gt 0 ]; then
        log_warning "Found $consumer_resources remaining resources in consumer subscription"
        az resource list --query "[?resourceGroup=='${CONSUMER_RG}'].{Name:name, Type:type}" --output table
    else
        log_success "No remaining resources found in consumer subscription"
    fi
}

# Clean up cross-tenant access settings
cleanup_cross_tenant_access() {
    log_info "Cross-tenant access cleanup information..."
    
    # Get tenant IDs
    az account set --subscription "${PROVIDER_SUBSCRIPTION_ID}"
    local provider_tenant_id=$(az account show --query tenantId -o tsv)
    
    az account set --subscription "${CONSUMER_SUBSCRIPTION_ID}"
    local consumer_tenant_id=$(az account show --query tenantId -o tsv)
    
    log_warning "Manual cleanup required for cross-tenant access:"
    log_warning "1. Navigate to Azure Portal > Azure AD > External Identities"
    log_warning "2. Go to Cross-tenant access settings"
    log_warning "3. Remove tenant $consumer_tenant_id from provider tenant allowlist"
    log_warning "4. Remove tenant $provider_tenant_id from consumer tenant allowlist"
    log_warning "5. Review and remove any guest users created during testing"
    log_warning ""
    log_warning "Provider Tenant ID: $provider_tenant_id"
    log_warning "Consumer Tenant ID: $consumer_tenant_id"
}

# Validation function
validate_cleanup() {
    log_info "Validating cleanup..."
    
    local cleanup_successful=true
    
    # Check if provider resource group still exists
    if resource_group_exists "${PROVIDER_SUBSCRIPTION_ID}" "${PROVIDER_RG}"; then
        log_warning "Provider resource group $PROVIDER_RG still exists"
        cleanup_successful=false
    fi
    
    # Check if consumer resource group still exists
    if resource_group_exists "${CONSUMER_SUBSCRIPTION_ID}" "${CONSUMER_RG}"; then
        log_warning "Consumer resource group $CONSUMER_RG still exists"
        cleanup_successful=false
    fi
    
    if [ "$cleanup_successful" = true ]; then
        log_success "Cleanup validation passed - all resource groups have been removed"
    else
        log_warning "Cleanup validation found remaining resources - deletion may still be in progress"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Azure Data Share and Purview cleanup..."
    log_warning "This will delete ALL resources created for cross-tenant data collaboration"
    
    # Confirm deletion unless in force mode
    if [ "${FORCE_DELETE:-false}" != "true" ]; then
        log_warning "This action will permanently delete the following resource groups:"
        log_warning "  - Provider RG: $PROVIDER_RG in subscription $PROVIDER_SUBSCRIPTION_ID"
        log_warning "  - Consumer RG: $CONSUMER_RG in subscription $CONSUMER_SUBSCRIPTION_ID"
        log_warning ""
        read -p "Are you sure you want to continue? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Run all cleanup steps
    check_prerequisites
    validate_environment
    setup_environment
    delete_consumer_resources
    delete_provider_resources
    
    # Wait a moment for deletions to initiate
    sleep 10
    
    check_remaining_resources
    cleanup_cross_tenant_access
    
    # Final validation if waiting for deletion
    if [ "${WAIT_FOR_DELETION:-false}" = "true" ]; then
        validate_cleanup
    fi
    
    log_success "Cleanup completed!"
    log_info ""
    log_info "Notes:"
    log_info "- Resource group deletions may continue in the background"
    log_info "- Purview deletion typically takes 10-15 minutes to complete"
    log_info "- Manual cleanup of cross-tenant access settings may be required"
    log_info "- Review Azure AD for any remaining guest users"
    log_info ""
    log_info "To monitor deletion progress, check the Azure portal or use:"
    log_info "  az group show --name $PROVIDER_RG --subscription $PROVIDER_SUBSCRIPTION_ID"
    log_info "  az group show --name $CONSUMER_RG --subscription $CONSUMER_SUBSCRIPTION_ID"
}

# Dry run function
dry_run() {
    log_info "DRY RUN MODE - No resources will be deleted"
    log_info "This would delete the following resources:"
    log_info "  Provider Resource Group: $PROVIDER_RG"
    log_info "  Consumer Resource Group: $CONSUMER_RG"
    log_info "  All contained resources including:"
    log_info "    - Storage accounts"
    log_info "    - Data Share accounts"
    log_info "    - Purview accounts"
    log_info "    - Role assignments"
    log_info "  Location: $LOCATION"
    log_info ""
    log_info "Cross-tenant access settings would need manual cleanup"
}

# Show status function
show_status() {
    log_info "Showing current deployment status..."
    
    # Check provider resources
    az account set --subscription "${PROVIDER_SUBSCRIPTION_ID}"
    if resource_group_exists "${PROVIDER_SUBSCRIPTION_ID}" "${PROVIDER_RG}"; then
        log_info "Provider resource group $PROVIDER_RG exists"
        log_info "Resources in provider resource group:"
        az resource list --resource-group "${PROVIDER_RG}" --query '[].{Name:name, Type:type, State:properties.provisioningState}' --output table
    else
        log_info "Provider resource group $PROVIDER_RG does not exist"
    fi
    
    # Check consumer resources
    az account set --subscription "${CONSUMER_SUBSCRIPTION_ID}"
    if resource_group_exists "${CONSUMER_SUBSCRIPTION_ID}" "${CONSUMER_RG}"; then
        log_info "Consumer resource group $CONSUMER_RG exists"
        log_info "Resources in consumer resource group:"
        az resource list --resource-group "${CONSUMER_RG}" --query '[].{Name:name, Type:type, State:properties.provisioningState}' --output table
    else
        log_info "Consumer resource group $CONSUMER_RG does not exist"
    fi
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -d, --dry-run       Show what would be deleted without actually deleting"
    echo "  -f, --force         Force deletion without confirmation prompt"
    echo "  -w, --wait          Wait for resource deletion to complete"
    echo "  -s, --status        Show current deployment status"
    echo "  -v, --verbose       Enable verbose output"
    echo ""
    echo "Required environment variables:"
    echo "  PROVIDER_SUBSCRIPTION_ID    Azure subscription ID for the data provider"
    echo "  CONSUMER_SUBSCRIPTION_ID    Azure subscription ID for the data consumer"
    echo "  LOCATION                    Azure region for deployment (e.g., eastus)"
    echo ""
    echo "Optional environment variables:"
    echo "  PROVIDER_RG                 Provider resource group name (default: rg-datashare-provider)"
    echo "  CONSUMER_RG                 Consumer resource group name (default: rg-datashare-consumer)"
    echo "  RANDOM_SUFFIX               Suffix used for resource names (should match deployment)"
    echo ""
    echo "Examples:"
    echo "  # Show what would be deleted"
    echo "  $0 --dry-run"
    echo ""
    echo "  # Force deletion without confirmation"
    echo "  $0 --force"
    echo ""
    echo "  # Delete and wait for completion"
    echo "  $0 --wait"
    echo ""
    echo "  # Show current status"
    echo "  $0 --status"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -w|--wait)
            WAIT_FOR_DELETION=true
            shift
            ;;
        -s|--status)
            SHOW_STATUS=true
            shift
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check if required environment variables are set
if [ -z "${PROVIDER_SUBSCRIPTION_ID:-}" ] || [ -z "${CONSUMER_SUBSCRIPTION_ID:-}" ] || [ -z "${LOCATION:-}" ]; then
    log_error "Required environment variables are not set"
    usage
    exit 1
fi

# Execute based on mode
if [ "${SHOW_STATUS:-false}" = "true" ]; then
    setup_environment
    show_status
elif [ "${DRY_RUN:-false}" = "true" ]; then
    setup_environment
    dry_run
else
    main
fi