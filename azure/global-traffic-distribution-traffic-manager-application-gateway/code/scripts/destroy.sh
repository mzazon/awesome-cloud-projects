#!/bin/bash
# Destroy script for Global Traffic Distribution with Traffic Manager and Application Gateway
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if subscription is set
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    if [ -z "$SUBSCRIPTION_ID" ]; then
        error "No Azure subscription selected. Please set a subscription."
        exit 1
    fi
    
    log "Prerequisites check passed"
    log "Using subscription: $SUBSCRIPTION_ID"
}

# Set environment variables
set_environment() {
    log "Setting environment variables..."
    
    # Resource group names
    export RESOURCE_GROUP_PRIMARY="rg-global-traffic-primary"
    export RESOURCE_GROUP_SECONDARY="rg-global-traffic-secondary"
    export RESOURCE_GROUP_TERTIARY="rg-global-traffic-tertiary"
    
    # Check if resource groups exist
    if ! az group show --name ${RESOURCE_GROUP_PRIMARY} &> /dev/null; then
        warning "Primary resource group ${RESOURCE_GROUP_PRIMARY} not found. Skipping primary region cleanup."
        export SKIP_PRIMARY=true
    else
        export SKIP_PRIMARY=false
    fi
    
    if ! az group show --name ${RESOURCE_GROUP_SECONDARY} &> /dev/null; then
        warning "Secondary resource group ${RESOURCE_GROUP_SECONDARY} not found. Skipping secondary region cleanup."
        export SKIP_SECONDARY=true
    else
        export SKIP_SECONDARY=false
    fi
    
    if ! az group show --name ${RESOURCE_GROUP_TERTIARY} &> /dev/null; then
        warning "Tertiary resource group ${RESOURCE_GROUP_TERTIARY} not found. Skipping tertiary region cleanup."
        export SKIP_TERTIARY=true
    else
        export SKIP_TERTIARY=false
    fi
    
    log "Environment variables set"
}

# Confirm destruction
confirm_destruction() {
    echo ""
    echo "⚠️  WARNING: This will permanently delete all resources in the following resource groups:"
    echo "   - ${RESOURCE_GROUP_PRIMARY}"
    echo "   - ${RESOURCE_GROUP_SECONDARY}"
    echo "   - ${RESOURCE_GROUP_TERTIARY}"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed by user"
}

# Get Traffic Manager profile information
get_traffic_manager_info() {
    log "Getting Traffic Manager profile information..."
    
    if [ "$SKIP_PRIMARY" = false ]; then
        # Try to find Traffic Manager profiles in primary resource group
        TRAFFIC_MANAGER_PROFILES=$(az network traffic-manager profile list \
            --resource-group ${RESOURCE_GROUP_PRIMARY} \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [ -n "$TRAFFIC_MANAGER_PROFILES" ]; then
            export TRAFFIC_MANAGER_PROFILE=$(echo "$TRAFFIC_MANAGER_PROFILES" | head -n1)
            log "Found Traffic Manager profile: $TRAFFIC_MANAGER_PROFILE"
        else
            export TRAFFIC_MANAGER_PROFILE=""
            warning "No Traffic Manager profile found in primary resource group"
        fi
    else
        export TRAFFIC_MANAGER_PROFILE=""
    fi
}

# Get Application Gateway information
get_application_gateway_info() {
    log "Getting Application Gateway information..."
    
    if [ "$SKIP_PRIMARY" = false ]; then
        APP_GATEWAYS_PRIMARY=$(az network application-gateway list \
            --resource-group ${RESOURCE_GROUP_PRIMARY} \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        export APP_GATEWAYS_PRIMARY
    else
        export APP_GATEWAYS_PRIMARY=""
    fi
    
    if [ "$SKIP_SECONDARY" = false ]; then
        APP_GATEWAYS_SECONDARY=$(az network application-gateway list \
            --resource-group ${RESOURCE_GROUP_SECONDARY} \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        export APP_GATEWAYS_SECONDARY
    else
        export APP_GATEWAYS_SECONDARY=""
    fi
    
    if [ "$SKIP_TERTIARY" = false ]; then
        APP_GATEWAYS_TERTIARY=$(az network application-gateway list \
            --resource-group ${RESOURCE_GROUP_TERTIARY} \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        export APP_GATEWAYS_TERTIARY
    else
        export APP_GATEWAYS_TERTIARY=""
    fi
}

# Remove Traffic Manager profile and endpoints
remove_traffic_manager() {
    if [ -n "$TRAFFIC_MANAGER_PROFILE" ]; then
        log "Removing Traffic Manager profile: $TRAFFIC_MANAGER_PROFILE"
        
        # Delete Traffic Manager profile (this removes all endpoints)
        az network traffic-manager profile delete \
            --resource-group ${RESOURCE_GROUP_PRIMARY} \
            --name ${TRAFFIC_MANAGER_PROFILE} \
            --yes
        
        log "Traffic Manager profile and endpoints removed"
    else
        log "No Traffic Manager profile to remove"
    fi
}

# Remove Application Gateways
remove_application_gateways() {
    log "Removing Application Gateways..."
    
    # Remove Application Gateway in primary region
    if [ "$SKIP_PRIMARY" = false ] && [ -n "$APP_GATEWAYS_PRIMARY" ]; then
        for gateway in $APP_GATEWAYS_PRIMARY; do
            log "Removing Application Gateway: $gateway (primary region)"
            az network application-gateway delete \
                --resource-group ${RESOURCE_GROUP_PRIMARY} \
                --name $gateway \
                --no-wait
        done
    fi
    
    # Remove Application Gateway in secondary region
    if [ "$SKIP_SECONDARY" = false ] && [ -n "$APP_GATEWAYS_SECONDARY" ]; then
        for gateway in $APP_GATEWAYS_SECONDARY; do
            log "Removing Application Gateway: $gateway (secondary region)"
            az network application-gateway delete \
                --resource-group ${RESOURCE_GROUP_SECONDARY} \
                --name $gateway \
                --no-wait
        done
    fi
    
    # Remove Application Gateway in tertiary region
    if [ "$SKIP_TERTIARY" = false ] && [ -n "$APP_GATEWAYS_TERTIARY" ]; then
        for gateway in $APP_GATEWAYS_TERTIARY; do
            log "Removing Application Gateway: $gateway (tertiary region)"
            az network application-gateway delete \
                --resource-group ${RESOURCE_GROUP_TERTIARY} \
                --name $gateway \
                --no-wait
        done
    fi
    
    log "Application Gateway deletion initiated (running in background)"
}

# Remove WAF policies
remove_waf_policies() {
    log "Removing Web Application Firewall policies..."
    
    # Remove WAF policies in primary region
    if [ "$SKIP_PRIMARY" = false ]; then
        WAF_POLICIES_PRIMARY=$(az network application-gateway waf-policy list \
            --resource-group ${RESOURCE_GROUP_PRIMARY} \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        for policy in $WAF_POLICIES_PRIMARY; do
            log "Removing WAF policy: $policy (primary region)"
            az network application-gateway waf-policy delete \
                --resource-group ${RESOURCE_GROUP_PRIMARY} \
                --name $policy
        done
    fi
    
    # Remove WAF policies in secondary region
    if [ "$SKIP_SECONDARY" = false ]; then
        WAF_POLICIES_SECONDARY=$(az network application-gateway waf-policy list \
            --resource-group ${RESOURCE_GROUP_SECONDARY} \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        for policy in $WAF_POLICIES_SECONDARY; do
            log "Removing WAF policy: $policy (secondary region)"
            az network application-gateway waf-policy delete \
                --resource-group ${RESOURCE_GROUP_SECONDARY} \
                --name $policy
        done
    fi
    
    # Remove WAF policies in tertiary region
    if [ "$SKIP_TERTIARY" = false ]; then
        WAF_POLICIES_TERTIARY=$(az network application-gateway waf-policy list \
            --resource-group ${RESOURCE_GROUP_TERTIARY} \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        for policy in $WAF_POLICIES_TERTIARY; do
            log "Removing WAF policy: $policy (tertiary region)"
            az network application-gateway waf-policy delete \
                --resource-group ${RESOURCE_GROUP_TERTIARY} \
                --name $policy
        done
    fi
    
    log "WAF policies removed"
}

# Remove VM Scale Sets
remove_vm_scale_sets() {
    log "Removing Virtual Machine Scale Sets..."
    
    # Remove VM Scale Sets in primary region
    if [ "$SKIP_PRIMARY" = false ]; then
        VMSS_PRIMARY=$(az vmss list \
            --resource-group ${RESOURCE_GROUP_PRIMARY} \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        for vmss in $VMSS_PRIMARY; do
            log "Removing VM Scale Set: $vmss (primary region)"
            az vmss delete \
                --resource-group ${RESOURCE_GROUP_PRIMARY} \
                --name $vmss \
                --no-wait
        done
    fi
    
    # Remove VM Scale Sets in secondary region
    if [ "$SKIP_SECONDARY" = false ]; then
        VMSS_SECONDARY=$(az vmss list \
            --resource-group ${RESOURCE_GROUP_SECONDARY} \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        for vmss in $VMSS_SECONDARY; do
            log "Removing VM Scale Set: $vmss (secondary region)"
            az vmss delete \
                --resource-group ${RESOURCE_GROUP_SECONDARY} \
                --name $vmss \
                --no-wait
        done
    fi
    
    # Remove VM Scale Sets in tertiary region
    if [ "$SKIP_TERTIARY" = false ]; then
        VMSS_TERTIARY=$(az vmss list \
            --resource-group ${RESOURCE_GROUP_TERTIARY} \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        for vmss in $VMSS_TERTIARY; do
            log "Removing VM Scale Set: $vmss (tertiary region)"
            az vmss delete \
                --resource-group ${RESOURCE_GROUP_TERTIARY} \
                --name $vmss \
                --no-wait
        done
    fi
    
    log "VM Scale Set deletion initiated (running in background)"
}

# Remove Log Analytics workspace
remove_log_analytics() {
    log "Removing Log Analytics workspace..."
    
    if [ "$SKIP_PRIMARY" = false ]; then
        WORKSPACES=$(az monitor log-analytics workspace list \
            --resource-group ${RESOURCE_GROUP_PRIMARY} \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        for workspace in $WORKSPACES; do
            log "Removing Log Analytics workspace: $workspace"
            az monitor log-analytics workspace delete \
                --resource-group ${RESOURCE_GROUP_PRIMARY} \
                --workspace-name $workspace \
                --force true \
                --yes
        done
    fi
    
    log "Log Analytics workspace removed"
}

# Wait for long-running operations
wait_for_operations() {
    log "Waiting for long-running operations to complete..."
    
    # Wait for Application Gateway deletions
    if [ "$SKIP_PRIMARY" = false ] && [ -n "$APP_GATEWAYS_PRIMARY" ]; then
        for gateway in $APP_GATEWAYS_PRIMARY; do
            log "Waiting for Application Gateway deletion: $gateway (primary region)"
            while az network application-gateway show \
                --resource-group ${RESOURCE_GROUP_PRIMARY} \
                --name $gateway &> /dev/null; do
                sleep 10
            done
        done
    fi
    
    if [ "$SKIP_SECONDARY" = false ] && [ -n "$APP_GATEWAYS_SECONDARY" ]; then
        for gateway in $APP_GATEWAYS_SECONDARY; do
            log "Waiting for Application Gateway deletion: $gateway (secondary region)"
            while az network application-gateway show \
                --resource-group ${RESOURCE_GROUP_SECONDARY} \
                --name $gateway &> /dev/null; do
                sleep 10
            done
        done
    fi
    
    if [ "$SKIP_TERTIARY" = false ] && [ -n "$APP_GATEWAYS_TERTIARY" ]; then
        for gateway in $APP_GATEWAYS_TERTIARY; do
            log "Waiting for Application Gateway deletion: $gateway (tertiary region)"
            while az network application-gateway show \
                --resource-group ${RESOURCE_GROUP_TERTIARY} \
                --name $gateway &> /dev/null; do
                sleep 10
            done
        done
    fi
    
    log "Long-running operations completed"
}

# Remove all resource groups
remove_resource_groups() {
    log "Removing all resource groups..."
    
    # Remove primary resource group
    if [ "$SKIP_PRIMARY" = false ]; then
        log "Removing primary resource group: $RESOURCE_GROUP_PRIMARY"
        az group delete \
            --name ${RESOURCE_GROUP_PRIMARY} \
            --yes \
            --no-wait
    fi
    
    # Remove secondary resource group
    if [ "$SKIP_SECONDARY" = false ]; then
        log "Removing secondary resource group: $RESOURCE_GROUP_SECONDARY"
        az group delete \
            --name ${RESOURCE_GROUP_SECONDARY} \
            --yes \
            --no-wait
    fi
    
    # Remove tertiary resource group
    if [ "$SKIP_TERTIARY" = false ]; then
        log "Removing tertiary resource group: $RESOURCE_GROUP_TERTIARY"
        az group delete \
            --name ${RESOURCE_GROUP_TERTIARY} \
            --yes \
            --no-wait
    fi
    
    log "Resource group deletion initiated (running in background)"
}

# Verify resource group deletion
verify_deletion() {
    log "Verifying resource group deletion..."
    
    # Check if resource groups are deleted
    local max_wait=600  # 10 minutes
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        local groups_remaining=0
        
        if [ "$SKIP_PRIMARY" = false ] && az group show --name ${RESOURCE_GROUP_PRIMARY} &> /dev/null; then
            groups_remaining=$((groups_remaining + 1))
        fi
        
        if [ "$SKIP_SECONDARY" = false ] && az group show --name ${RESOURCE_GROUP_SECONDARY} &> /dev/null; then
            groups_remaining=$((groups_remaining + 1))
        fi
        
        if [ "$SKIP_TERTIARY" = false ] && az group show --name ${RESOURCE_GROUP_TERTIARY} &> /dev/null; then
            groups_remaining=$((groups_remaining + 1))
        fi
        
        if [ $groups_remaining -eq 0 ]; then
            log "All resource groups have been deleted successfully"
            return 0
        fi
        
        log "Waiting for resource groups to be deleted... ($groups_remaining remaining)"
        sleep 30
        wait_time=$((wait_time + 30))
    done
    
    warning "Resource group deletion is taking longer than expected. Check Azure portal for status."
}

# Display destruction summary
display_summary() {
    log "Destruction Summary:"
    echo "===================="
    echo "The following resources have been removed:"
    echo "- Traffic Manager profile and endpoints"
    echo "- Application Gateways in all regions"
    echo "- Web Application Firewall policies"
    echo "- Virtual Machine Scale Sets"
    echo "- Log Analytics workspace"
    echo "- All resource groups and their contents"
    echo "===================="
    echo ""
    echo "All resources for the Global Traffic Distribution solution have been destroyed."
    echo "Note: Some resources may take additional time to be completely removed from Azure."
}

# Main destruction function
main() {
    log "Starting destruction of Global Traffic Distribution solution..."
    
    check_prerequisites
    set_environment
    confirm_destruction
    get_traffic_manager_info
    get_application_gateway_info
    remove_traffic_manager
    remove_waf_policies
    remove_log_analytics
    remove_application_gateways
    remove_vm_scale_sets
    wait_for_operations
    remove_resource_groups
    verify_deletion
    display_summary
    
    log "Destruction completed successfully!"
}

# Error handling
trap 'error "Destruction failed at line $LINENO. Exit code: $?" && exit 1' ERR

# Run main function
main "$@"