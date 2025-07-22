#!/bin/bash

# Destroy Azure Elastic SAN and VMSS Database Solution
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Enable debug mode if DEBUG=1 is set
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x
fi

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI authentication
check_azure_auth() {
    log_info "Checking Azure CLI authentication..."
    if ! az account show >/dev/null 2>&1; then
        log_error "Azure CLI not authenticated. Please run 'az login' first."
        exit 1
    fi
    log_success "Azure CLI authenticated"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check authentication
    check_azure_auth
    
    log_success "Prerequisites check completed"
}

# Function to prompt for confirmation
confirm_destruction() {
    if [[ "${FORCE:-0}" == "1" ]]; then
        log_warning "FORCE mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    log_warning "⚠️  DANGER: This will permanently delete all resources in the resource group: $RESOURCE_GROUP"
    echo ""
    echo "This action cannot be undone and will:"
    echo "- Delete all Azure Elastic SAN volumes and data"
    echo "- Terminate all Virtual Machine Scale Set instances"
    echo "- Remove PostgreSQL Flexible Server and all databases"
    echo "- Delete all networking, monitoring, and associated resources"
    echo ""
    read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction..."
}

# Function to check if resource group exists
check_resource_group_exists() {
    log_info "Checking if resource group exists: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group '$RESOURCE_GROUP' does not exist"
        return 1
    fi
    
    log_info "Resource group exists"
    return 0
}

# Function to discover resources by name patterns
discover_resources() {
    log_info "Discovering resources in resource group: $RESOURCE_GROUP"
    
    # Get all resources in the resource group
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].{name:name,type:type}' -o json)
    
    if [[ -z "$resources" || "$resources" == "[]" ]]; then
        log_warning "No resources found in resource group"
        return 1
    fi
    
    echo "$resources" | jq -r '.[] | "\(.type): \(.name)"' | sort
    return 0
}

# Function to remove monitoring and alerting resources
remove_monitoring_resources() {
    log_info "Removing monitoring and alerting resources..."
    
    # Delete alert rules
    local alert_rules=$(az monitor metrics alert list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$alert_rules" ]]; then
        for rule in $alert_rules; do
            log_info "Deleting alert rule: $rule"
            az monitor metrics alert delete \
                --name "$rule" \
                --resource-group "$RESOURCE_GROUP" || log_warning "Failed to delete alert rule: $rule"
        done
    fi
    
    # Delete action groups
    local action_groups=$(az monitor action-group list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$action_groups" ]]; then
        for group in $action_groups; do
            log_info "Deleting action group: $group"
            az monitor action-group delete \
                --name "$group" \
                --resource-group "$RESOURCE_GROUP" || log_warning "Failed to delete action group: $group"
        done
    fi
    
    # Delete Log Analytics workspaces
    local workspaces=$(az monitor log-analytics workspace list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$workspaces" ]]; then
        for workspace in $workspaces; do
            log_info "Deleting Log Analytics workspace: $workspace"
            az monitor log-analytics workspace delete \
                --resource-group "$RESOURCE_GROUP" \
                --workspace-name "$workspace" \
                --force true || log_warning "Failed to delete workspace: $workspace"
        done
    fi
    
    log_success "Monitoring resources cleanup completed"
}

# Function to remove auto-scaling configuration
remove_auto_scaling() {
    log_info "Removing auto-scaling configuration..."
    
    # Delete autoscale profiles
    local autoscale_profiles=$(az monitor autoscale list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$autoscale_profiles" ]]; then
        for profile in $autoscale_profiles; do
            log_info "Deleting autoscale profile: $profile"
            az monitor autoscale delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$profile" || log_warning "Failed to delete autoscale profile: $profile"
        done
    fi
    
    log_success "Auto-scaling configuration removed"
}

# Function to remove PostgreSQL Flexible Server
remove_postgres_flexible_server() {
    log_info "Removing PostgreSQL Flexible Server..."
    
    # Find PostgreSQL Flexible Servers
    local pg_servers=$(az postgres flexible-server list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$pg_servers" ]]; then
        for server in $pg_servers; do
            log_info "Deleting PostgreSQL Flexible Server: $server"
            az postgres flexible-server delete \
                --name "$server" \
                --resource-group "$RESOURCE_GROUP" \
                --yes || log_warning "Failed to delete PostgreSQL server: $server"
        done
    fi
    
    log_success "PostgreSQL Flexible Server removed"
}

# Function to remove Virtual Machine Scale Set and Load Balancer
remove_vmss_and_lb() {
    log_info "Removing Virtual Machine Scale Set and Load Balancer..."
    
    # Delete VMSS instances
    local vmss_list=$(az vmss list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$vmss_list" ]]; then
        for vmss in $vmss_list; do
            log_info "Deleting VMSS: $vmss"
            az vmss delete \
                --name "$vmss" \
                --resource-group "$RESOURCE_GROUP" || log_warning "Failed to delete VMSS: $vmss"
        done
    fi
    
    # Delete load balancers
    local lb_list=$(az network lb list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$lb_list" ]]; then
        for lb in $lb_list; do
            log_info "Deleting load balancer: $lb"
            az network lb delete \
                --name "$lb" \
                --resource-group "$RESOURCE_GROUP" || log_warning "Failed to delete load balancer: $lb"
        done
    fi
    
    log_success "VMSS and load balancer removed"
}

# Function to remove Elastic SAN and storage resources
remove_elastic_san() {
    log_info "Removing Elastic SAN and storage resources..."
    
    # Check if Elastic SAN extension is installed
    if ! az extension show --name elastic-san >/dev/null 2>&1; then
        log_info "Installing Azure Elastic SAN extension..."
        az extension add --name elastic-san
    fi
    
    # Find Elastic SAN instances
    local esan_list=$(az elastic-san list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$esan_list" ]]; then
        for esan in $esan_list; do
            log_info "Processing Elastic SAN: $esan"
            
            # Delete volumes first
            local volume_groups=$(az elastic-san volume-group list \
                --elastic-san-name "$esan" \
                --resource-group "$RESOURCE_GROUP" \
                --query '[].name' -o tsv 2>/dev/null || echo "")
            
            if [[ -n "$volume_groups" ]]; then
                for vg in $volume_groups; do
                    log_info "Processing volume group: $vg"
                    
                    # Delete all volumes in the volume group
                    local volumes=$(az elastic-san volume list \
                        --elastic-san-name "$esan" \
                        --volume-group-name "$vg" \
                        --resource-group "$RESOURCE_GROUP" \
                        --query '[].name' -o tsv 2>/dev/null || echo "")
                    
                    if [[ -n "$volumes" ]]; then
                        for volume in $volumes; do
                            log_info "Deleting volume: $volume"
                            az elastic-san volume delete \
                                --name "$volume" \
                                --volume-group-name "$vg" \
                                --elastic-san-name "$esan" \
                                --resource-group "$RESOURCE_GROUP" \
                                --yes || log_warning "Failed to delete volume: $volume"
                        done
                    fi
                    
                    # Delete volume group
                    log_info "Deleting volume group: $vg"
                    az elastic-san volume-group delete \
                        --name "$vg" \
                        --elastic-san-name "$esan" \
                        --resource-group "$RESOURCE_GROUP" \
                        --yes || log_warning "Failed to delete volume group: $vg"
                done
            fi
            
            # Delete Elastic SAN
            log_info "Deleting Elastic SAN: $esan"
            az elastic-san delete \
                --name "$esan" \
                --resource-group "$RESOURCE_GROUP" \
                --yes || log_warning "Failed to delete Elastic SAN: $esan"
        done
    fi
    
    log_success "Elastic SAN and storage resources removed"
}

# Function to remove networking resources
remove_networking_resources() {
    log_info "Removing networking resources..."
    
    # Delete public IPs
    local public_ips=$(az network public-ip list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$public_ips" ]]; then
        for ip in $public_ips; do
            log_info "Deleting public IP: $ip"
            az network public-ip delete \
                --name "$ip" \
                --resource-group "$RESOURCE_GROUP" || log_warning "Failed to delete public IP: $ip"
        done
    fi
    
    # Delete network security groups
    local nsgs=$(az network nsg list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$nsgs" ]]; then
        for nsg in $nsgs; do
            log_info "Deleting network security group: $nsg"
            az network nsg delete \
                --name "$nsg" \
                --resource-group "$RESOURCE_GROUP" || log_warning "Failed to delete NSG: $nsg"
        done
    fi
    
    # Delete virtual networks (this will also delete subnets)
    local vnets=$(az network vnet list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$vnets" ]]; then
        for vnet in $vnets; do
            log_info "Deleting virtual network: $vnet"
            az network vnet delete \
                --name "$vnet" \
                --resource-group "$RESOURCE_GROUP" || log_warning "Failed to delete virtual network: $vnet"
        done
    fi
    
    log_success "Networking resources removed"
}

# Function to remove entire resource group
remove_resource_group() {
    log_info "Removing resource group: $RESOURCE_GROUP"
    
    if [[ "${DELETE_RESOURCE_GROUP:-1}" == "1" ]]; then
        log_warning "Deleting entire resource group and all remaining resources..."
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log_info "Note: Deletion may take several minutes to complete"
    else
        log_info "Skipping resource group deletion (DELETE_RESOURCE_GROUP=0)"
    fi
}

# Function to verify resource cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    if [[ "${DELETE_RESOURCE_GROUP:-1}" == "1" ]]; then
        log_info "Checking resource group deletion status..."
        
        # Wait a bit for deletion to start
        sleep 10
        
        # Check if resource group still exists
        if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
            log_warning "Resource group still exists (deletion in progress)"
            log_info "You can check status with: az group show --name $RESOURCE_GROUP"
        else
            log_success "Resource group successfully deleted"
        fi
    else
        # Check remaining resources
        local remaining_resources=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[].name' -o tsv 2>/dev/null || echo "")
        
        if [[ -n "$remaining_resources" ]]; then
            log_warning "Some resources may still exist:"
            echo "$remaining_resources"
        else
            log_success "All resources have been removed"
        fi
    fi
}

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -g, --resource-group    Resource group name (required)"
    echo "  -f, --force             Skip confirmation prompts"
    echo "  --keep-resource-group   Keep the resource group after cleaning up resources"
    echo "  --dry-run              Show what would be deleted without actually deleting"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP         Resource group name"
    echo "  FORCE                  Skip confirmation (set to 1)"
    echo "  DELETE_RESOURCE_GROUP  Delete resource group (set to 0 to keep)"
    echo "  DEBUG                  Enable debug mode (set to 1)"
    echo ""
    echo "Examples:"
    echo "  $0 -g my-resource-group                     # Delete all resources in resource group"
    echo "  $0 -g my-resource-group -f                  # Force deletion without confirmation"
    echo "  $0 -g my-resource-group --keep-resource-group # Keep resource group"
    echo "  DEBUG=1 $0 -g my-resource-group             # Delete with debug logging"
    echo "  $0 -g my-resource-group --dry-run           # Show what would be deleted"
}

# Function to handle cleanup on script exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup failed with exit code: $exit_code"
        log_warning "Some resources may not have been deleted"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=1
            shift
            ;;
        --keep-resource-group)
            DELETE_RESOURCE_GROUP=0
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check if resource group is specified
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
    log_error "Resource group must be specified with -g option or RESOURCE_GROUP environment variable"
    usage
    exit 1
fi

# Set trap for cleanup on exit
trap cleanup_on_exit EXIT

# Main cleanup flow
main() {
    log_info "Starting Azure Elastic SAN and VMSS cleanup..."
    
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        check_prerequisites
        if check_resource_group_exists; then
            log_info "Resources that would be deleted:"
            discover_resources
        fi
        return 0
    fi
    
    check_prerequisites
    
    if ! check_resource_group_exists; then
        log_success "Resource group does not exist - nothing to clean up"
        return 0
    fi
    
    log_info "Found resources to clean up:"
    discover_resources
    
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_monitoring_resources
    remove_auto_scaling
    remove_postgres_flexible_server
    remove_vmss_and_lb
    remove_elastic_san
    remove_networking_resources
    remove_resource_group
    
    verify_cleanup
    
    log_success "Cleanup completed successfully!"
}

# Execute main function
main "$@"