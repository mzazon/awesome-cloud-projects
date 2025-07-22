#!/bin/bash

# Azure Multi-Tenant Customer Identity Isolation Cleanup Script
# This script safely removes all resources created by the deployment script
# for the multi-tenant customer identity management system

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_NAME="Multi-Tenant Identity Isolation Cleanup"
LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=${DRY_RUN:-false}
FORCE_DELETE=${FORCE_DELETE:-false}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling function
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Cleanup failed. Check $LOG_FILE for details."
    exit 1
}

# Prerequisites check function
check_prerequisites() {
    log "INFO" "Checking prerequisites for $SCRIPT_NAME..."
    
    # Check Azure CLI installation
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI v2.49.0 or later."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Display current Azure context
    local subscription_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    log "INFO" "Using Azure subscription: $subscription_name ($subscription_id)"
    
    log "INFO" "Prerequisites check completed successfully."
}

# Load environment variables from deployment
load_environment() {
    log "INFO" "Loading environment variables from deployment..."
    
    if [ -f ".deployment_env" ]; then
        source .deployment_env
        log "INFO" "Environment variables loaded from .deployment_env"
        log "INFO" "  Resource Group: $RESOURCE_GROUP"
        log "INFO" "  API Management: $APIM_NAME"
        log "INFO" "  Key Vault: $KEYVAULT_NAME"
        log "INFO" "  Virtual Network: $VNET_NAME"
    else
        log "WARN" "No .deployment_env file found. Using default values or prompting for input."
        
        # Prompt for essential variables if not set
        if [ -z "${RESOURCE_GROUP:-}" ]; then
            read -p "Enter resource group name to delete: " RESOURCE_GROUP
            export RESOURCE_GROUP
        fi
        
        if [ -z "${KEYVAULT_NAME:-}" ]; then
            read -p "Enter Key Vault name (optional, press enter to skip): " KEYVAULT_NAME
            export KEYVAULT_NAME
        fi
        
        if [ -z "${APIM_NAME:-}" ]; then
            read -p "Enter API Management name (optional, press enter to skip): " APIM_NAME
            export APIM_NAME
        fi
        
        # Set default values for optional variables
        export VNET_NAME="${VNET_NAME:-vnet-private-isolation}"
        export LOCATION="${LOCATION:-eastus}"
    fi
}

# Safety confirmation function
confirm_destruction() {
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN MODE: Would delete multi-tenant identity isolation infrastructure"
        return 0
    fi
    
    if [ "$FORCE_DELETE" = "true" ]; then
        log "WARN" "FORCE DELETE MODE: Skipping confirmation prompts"
        return 0
    fi
    
    echo
    log "WARN" "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log "WARN" "This will permanently delete the following resources:"
    echo
    log "WARN" "  🗂️  Resource Group: ${RESOURCE_GROUP:-Not specified}"
    log "WARN" "  🔐 Key Vault: ${KEYVAULT_NAME:-Not specified} (with purge protection)"
    log "WARN" "  🌐 API Management: ${APIM_NAME:-Not specified}"
    log "WARN" "  🔗 Virtual Network: ${VNET_NAME:-Not specified}"
    log "WARN" "  📊 Log Analytics Workspace: law-tenant-isolation"
    log "WARN" "  🔗 Private Endpoints and connections"
    log "WARN" "  🚨 Monitoring alerts and configurations"
    log "WARN" "  📁 Additional resource group: rg-tenant-management"
    echo
    log "WARN" "⚠️  Key Vault has purge protection enabled. Manual purge may be required."
    log "WARN" "⚠️  External ID tenants must be deleted manually via Azure portal."
    echo
    
    read -p "Type 'DELETE' to confirm permanent deletion of all resources: " -r
    echo
    if [[ ! $REPLY == "DELETE" ]]; then
        log "INFO" "Cleanup cancelled by user. Type 'DELETE' exactly to confirm."
        exit 0
    fi
    
    echo
    read -p "Are you absolutely sure? This cannot be undone! (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Cleanup cancelled by user."
        exit 0
    fi
    
    log "INFO" "Destruction confirmed. Beginning cleanup process..."
}

# External ID tenant cleanup guidance
cleanup_external_id_tenants() {
    log "INFO" "Providing guidance for External ID tenant cleanup..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would provide External ID tenant cleanup guidance"
        return 0
    fi
    
    # Create cleanup guidance script
    cat > cleanup-external-id-tenants.md << 'EOF'
# Azure External ID Customer Tenants Cleanup Guide

## Manual Steps Required

The following Azure External ID customer tenants were created during deployment and must be manually deleted:

### Customer Tenants to Delete:
1. **Customer A Identity Tenant** (customer-a-external)
2. **Customer B Identity Tenant** (customer-b-external)

### Cleanup Steps:

#### 1. Delete Customer Tenant Applications
- Navigate to Azure portal for each customer tenant
- Go to Azure AD → App registrations
- Delete all registered applications
- Remove any custom policies or user flows

#### 2. Delete External ID Customer Tenants
- In Azure portal, switch to each customer tenant directory
- Go to Azure Active Directory → Properties
- Click "Delete tenant"
- Follow the deletion wizard
- Complete any required cleanup tasks (remove users, apps, etc.)

#### 3. Verify Complete Removal
- Ensure tenants no longer appear in tenant switcher
- Verify no billing charges for deleted tenants
- Check that all custom domains are released

### Important Notes:
- ⚠️ Tenant deletion is permanent and cannot be undone
- All user data, applications, and configurations will be lost
- Ensure you have backups of any required data before deletion
- Some tenants may require a waiting period before deletion

### Troubleshooting:
If tenant deletion fails, check for:
- Active subscriptions within the tenant
- Undeleted applications or service principals
- Active directory synchronization
- Domain dependencies

For assistance, refer to:
https://learn.microsoft.com/en-us/azure/active-directory/enterprise-users/directory-delete-howto
EOF
    
    log "INFO" "✅ External ID tenant cleanup guidance created: cleanup-external-id-tenants.md"
    log "WARN" "Manual action required: Delete Azure External ID customer tenants via Azure portal"
    log "INFO" "See cleanup-external-id-tenants.md for detailed instructions"
}

# Private endpoints cleanup
cleanup_private_endpoints() {
    log "INFO" "Removing private endpoints..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would delete private endpoints"
        return 0
    fi
    
    local endpoints=("pe-apim-gateway" "pe-keyvault" "pe-arm-management")
    
    for endpoint in "${endpoints[@]}"; do
        if az network private-endpoint show --resource-group "$RESOURCE_GROUP" --name "$endpoint" &> /dev/null; then
            log "INFO" "Deleting private endpoint: $endpoint"
            az network private-endpoint delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$endpoint" \
                --no-wait \
                --output table
            log "INFO" "✅ Private endpoint deletion initiated: $endpoint"
        else
            log "INFO" "Private endpoint not found: $endpoint"
        fi
    done
    
    # Wait a moment for private endpoint deletions to process
    log "INFO" "Waiting for private endpoint deletions to complete..."
    sleep 30
}

# API Management cleanup
cleanup_api_management() {
    log "INFO" "Removing API Management instance..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would delete API Management instance $APIM_NAME"
        return 0
    fi
    
    if [ -n "${APIM_NAME:-}" ] && az apim show --resource-group "$RESOURCE_GROUP" --name "$APIM_NAME" &> /dev/null; then
        log "INFO" "Deleting API Management instance: $APIM_NAME (this may take 15-30 minutes)"
        az apim delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$APIM_NAME" \
            --yes \
            --no-wait \
            --output table
        log "INFO" "✅ API Management deletion initiated: $APIM_NAME"
    else
        log "INFO" "API Management instance not found or not specified"
    fi
}

# Key Vault cleanup with purge protection handling
cleanup_key_vault() {
    log "INFO" "Removing Key Vault with purge protection considerations..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would delete Key Vault $KEYVAULT_NAME"
        return 0
    fi
    
    if [ -n "${KEYVAULT_NAME:-}" ] && az keyvault show --resource-group "$RESOURCE_GROUP" --name "$KEYVAULT_NAME" &> /dev/null; then
        log "INFO" "Deleting Key Vault: $KEYVAULT_NAME"
        
        # First, delete the Key Vault (soft delete)
        az keyvault delete \
            --name "$KEYVAULT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --output table
        
        log "INFO" "✅ Key Vault soft-deleted: $KEYVAULT_NAME"
        log "WARN" "⚠️  Key Vault has purge protection enabled"
        log "WARN" "Manual purge required after 90-day retention period"
        log "WARN" "Or use: az keyvault purge --name $KEYVAULT_NAME --location $LOCATION"
        log "WARN" "Note: Purge protection may prevent immediate purging"
        
        # Create purge script for future use
        cat > purge-keyvault.sh << EOF
#!/bin/bash
# Key Vault purge script - use after retention period or if purge protection is disabled
echo "Attempting to purge Key Vault: $KEYVAULT_NAME"
az keyvault purge --name "$KEYVAULT_NAME" --location "${LOCATION:-eastus}"
echo "Key Vault purge completed"
EOF
        chmod +x purge-keyvault.sh
        log "INFO" "Created purge script: purge-keyvault.sh"
        
    else
        log "INFO" "Key Vault not found or not specified"
    fi
}

# Monitor resources cleanup
cleanup_monitoring() {
    log "INFO" "Removing monitoring and alerting resources..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would delete monitoring resources"
        return 0
    fi
    
    # Delete alert rules first
    if az monitor metrics alert show --resource-group "$RESOURCE_GROUP" --name "tenant-isolation-violation-alert" &> /dev/null; then
        az monitor metrics alert delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "tenant-isolation-violation-alert" \
            --output table
        log "INFO" "✅ Alert rule deleted: tenant-isolation-violation-alert"
    fi
    
    # Delete Log Analytics workspace
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "law-tenant-isolation" &> /dev/null; then
        az monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "law-tenant-isolation" \
            --yes \
            --force \
            --output table
        log "INFO" "✅ Log Analytics workspace deleted: law-tenant-isolation"
    fi
}

# ARM Private Link scope cleanup
cleanup_arm_private_link() {
    log "INFO" "Removing Azure Resource Manager Private Link resources..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would delete ARM Private Link resources"
        return 0
    fi
    
    # Delete private link scope
    if az monitor private-link-scope show --resource-group "rg-tenant-management" --scope-name "pls-arm-management" &> /dev/null; then
        az monitor private-link-scope delete \
            --resource-group "rg-tenant-management" \
            --scope-name "pls-arm-management" \
            --yes \
            --output table
        log "INFO" "✅ ARM private link scope deleted"
    fi
    
    # Delete tenant management resource group
    if az group show --name "rg-tenant-management" &> /dev/null; then
        az group delete \
            --name "rg-tenant-management" \
            --yes \
            --no-wait \
            --output table
        log "INFO" "✅ Tenant management resource group deletion initiated"
    fi
}

# Virtual network cleanup
cleanup_virtual_network() {
    log "INFO" "Removing virtual network and subnets..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would delete virtual network $VNET_NAME"
        return 0
    fi
    
    if [ -n "${VNET_NAME:-}" ] && az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" &> /dev/null; then
        # Note: VNet will be deleted with the resource group, but we can delete it separately if needed
        log "INFO" "Virtual network will be deleted with resource group: $VNET_NAME"
    else
        log "INFO" "Virtual network not found or not specified"
    fi
}

# Main resource group cleanup
cleanup_resource_group() {
    log "INFO" "Removing main resource group..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would delete resource group $RESOURCE_GROUP"
        return 0
    fi
    
    if [ -n "${RESOURCE_GROUP:-}" ] && az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Deleting resource group: $RESOURCE_GROUP (this may take several minutes)"
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output table
        log "INFO" "✅ Resource group deletion initiated: $RESOURCE_GROUP"
    else
        log "WARN" "Resource group not found or not specified: ${RESOURCE_GROUP:-Not set}"
    fi
}

# Cleanup generated files
cleanup_local_files() {
    log "INFO" "Cleaning up generated files..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would clean up local files"
        return 0
    fi
    
    local files_to_remove=(
        ".deployment_env"
        "tenant-isolation-policy.xml"
        "tenant-monitoring-queries.kql"
        "create-customer-tenants.ps1"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "INFO" "✅ Removed file: $file"
        fi
    done
    
    log "INFO" "✅ Local files cleanup completed"
}

# Wait for deletions to complete
wait_for_deletions() {
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would wait for deletions to complete"
        return 0
    fi
    
    log "INFO" "Waiting for resource deletions to complete..."
    log "INFO" "Note: Some resources (API Management, Resource Groups) may take 15-45 minutes to fully delete"
    
    # Check resource group deletion status
    if [ -n "${RESOURCE_GROUP:-}" ]; then
        local wait_count=0
        local max_wait=60  # 10 minutes maximum wait
        
        while az group show --name "$RESOURCE_GROUP" &> /dev/null && [ $wait_count -lt $max_wait ]; do
            log "INFO" "Resource group still exists, waiting... ($((wait_count * 10)) seconds)"
            sleep 10
            wait_count=$((wait_count + 1))
        done
        
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log "WARN" "Resource group deletion in progress (may take additional time): $RESOURCE_GROUP"
        else
            log "INFO" "✅ Resource group deletion completed: $RESOURCE_GROUP"
        fi
    fi
}

# Validation function
validate_cleanup() {
    log "INFO" "Validating cleanup completion..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would validate cleanup"
        return 0
    fi
    
    local cleanup_issues=0
    
    # Check if main resource group still exists
    if [ -n "${RESOURCE_GROUP:-}" ] && az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "WARN" "⚠️  Main resource group still exists (deletion may be in progress): $RESOURCE_GROUP"
        cleanup_issues=$((cleanup_issues + 1))
    else
        log "INFO" "✅ Main resource group deletion verified"
    fi
    
    # Check if tenant management resource group still exists
    if az group show --name "rg-tenant-management" &> /dev/null; then
        log "WARN" "⚠️  Tenant management resource group still exists (deletion may be in progress)"
        cleanup_issues=$((cleanup_issues + 1))
    else
        log "INFO" "✅ Tenant management resource group deletion verified"
    fi
    
    # Check for any remaining Key Vault in soft-deleted state
    if [ -n "${KEYVAULT_NAME:-}" ] && az keyvault list-deleted --query "[?name=='$KEYVAULT_NAME']" -o tsv | grep -q "$KEYVAULT_NAME"; then
        log "INFO" "ℹ️  Key Vault in soft-deleted state (expected due to purge protection): $KEYVAULT_NAME"
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log "INFO" "✅ Cleanup validation completed successfully"
    else
        log "WARN" "⚠️  Cleanup validation found $cleanup_issues potential issues (may be normal for async deletions)"
    fi
    
    return 0
}

# Main cleanup function
main() {
    log "INFO" "Starting $SCRIPT_NAME"
    log "INFO" "Log file: $LOG_FILE"
    
    # Execute cleanup steps
    check_prerequisites
    load_environment
    confirm_destruction
    
    log "INFO" "Beginning infrastructure cleanup..."
    
    # Cleanup in reverse order of creation for safety
    cleanup_external_id_tenants
    cleanup_private_endpoints
    cleanup_monitoring
    cleanup_api_management
    cleanup_key_vault
    cleanup_arm_private_link
    cleanup_virtual_network
    cleanup_resource_group
    
    # Wait for async operations
    wait_for_deletions
    
    # Validate and clean up local files
    validate_cleanup
    cleanup_local_files
    
    # Display completion summary
    log "INFO" "🧹 Multi-tenant customer identity isolation cleanup completed!"
    echo
    log "INFO" "Cleanup Summary:"
    log "INFO" "  ✅ Private endpoints removed"
    log "INFO" "  ✅ API Management deletion initiated"
    log "INFO" "  ✅ Key Vault soft-deleted (purge protection active)"
    log "INFO" "  ✅ Monitoring resources removed"
    log "INFO" "  ✅ ARM Private Link resources removed"
    log "INFO" "  ✅ Resource groups deletion initiated"
    log "INFO" "  ✅ Local files cleaned up"
    echo
    log "WARN" "Manual Actions Still Required:"
    log "WARN" "  🔐 Delete Azure External ID customer tenants via Azure portal"
    log "WARN" "  🗝️  Purge Key Vault after retention period (if desired)"
    echo
    log "INFO" "Reference files created:"
    log "INFO" "  📋 cleanup-external-id-tenants.md - External ID tenant cleanup guide"
    if [ -f "purge-keyvault.sh" ]; then
        log "INFO" "  🗝️  purge-keyvault.sh - Key Vault purge script for later use"
    fi
    echo
    log "INFO" "Cleanup log saved to: $LOG_FILE"
    echo
    log "INFO" "Note: Some resources may take additional time to complete deletion."
    log "INFO" "Monitor the Azure portal to confirm all resources are fully removed."
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi