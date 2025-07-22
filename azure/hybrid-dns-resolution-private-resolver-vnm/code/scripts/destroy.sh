#!/bin/bash

# Destroy Azure Hybrid DNS Resolution Infrastructure
# This script safely removes all resources created by the deploy.sh script

set -euo pipefail

# Color codes for output
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Banner
echo "=========================================="
echo "Azure Hybrid DNS Resolution Cleanup"
echo "DNS Private Resolver + Virtual Network Manager"
echo "=========================================="
echo

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please log in to Azure using 'az login'"
    fi
    
    success "Prerequisites check completed"
}

# Function to prompt for confirmation
confirm_destruction() {
    local resource_group="$1"
    
    echo
    warning "This will DELETE ALL resources in the following resource group:"
    echo "  Resource Group: $resource_group"
    echo
    warning "This action is IRREVERSIBLE and will:"
    echo "  - Remove DNS Private Resolver and all endpoints"
    echo "  - Delete Virtual Network Manager and configurations" 
    echo "  - Remove all virtual networks and subnets"
    echo "  - Delete private DNS zones and records"
    echo "  - Remove storage accounts and private endpoints"
    echo "  - Delete the entire resource group"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    echo
}

# Function to get resource group from deployment info or user input
get_resource_group() {
    local resource_group=""
    
    # Try to find deployment info file
    local info_file=$(ls deployment-info-*.txt 2>/dev/null | head -1 || echo "")
    
    if [[ -n "$info_file" && -f "$info_file" ]]; then
        log "Found deployment info file: $info_file"
        resource_group=$(grep "Resource Group:" "$info_file" | cut -d' ' -f3)
        if [[ -n "$resource_group" ]]; then
            log "Resource group from deployment info: $resource_group"
            echo "$resource_group"
            return 0
        fi
    fi
    
    # If no deployment info found, prompt user
    echo "No deployment info file found."
    echo "Please provide the resource group name to delete."
    echo "Resource groups matching pattern 'rg-hybrid-dns-*':"
    az group list --query "[?starts_with(name, 'rg-hybrid-dns-')].name" -o table 2>/dev/null || true
    echo
    
    read -p "Enter resource group name: " -r resource_group
    if [[ -z "$resource_group" ]]; then
        error "Resource group name cannot be empty"
    fi
    
    echo "$resource_group"
}

# Function to verify resource group exists
verify_resource_group() {
    local resource_group="$1"
    
    log "Verifying resource group exists: $resource_group"
    
    if ! az group show --name "$resource_group" &>/dev/null; then
        error "Resource group '$resource_group' does not exist or you don't have access to it"
    fi
    
    success "Resource group verified: $resource_group"
}

# Function to list resources that will be deleted
list_resources() {
    local resource_group="$1"
    
    log "Listing resources in resource group: $resource_group"
    echo
    
    local resource_count=$(az resource list --resource-group "$resource_group" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    
    if [[ "$resource_count" -eq 0 ]]; then
        warning "No resources found in resource group: $resource_group"
        return 0
    fi
    
    echo "Resources to be deleted ($resource_count total):"
    az resource list --resource-group "$resource_group" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table 2>/dev/null || warning "Could not list resources"
    echo
}

# Function to remove Virtual Network Manager configurations first
remove_network_manager_configs() {
    local resource_group="$1"
    
    log "Checking for Virtual Network Manager configurations..."
    
    # Get network managers in the resource group
    local network_managers=$(az network manager list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$network_managers" ]]; then
        log "No Virtual Network Managers found"
        return 0
    fi
    
    for nm in $network_managers; do
        log "Processing Virtual Network Manager: $nm"
        
        # Get active connectivity configurations
        local location=$(az network manager show --resource-group "$resource_group" --name "$nm" --query "location" -o tsv 2>/dev/null || echo "eastus")
        
        log "Checking for active connectivity configurations..."
        local active_configs=$(az network manager list-active-connectivity-config \
            --resource-group "$resource_group" \
            --network-manager-name "$nm" \
            --regions "$location" \
            --query "[].id" -o tsv 2>/dev/null || echo "")
        
        if [[ -n "$active_configs" ]]; then
            log "Removing active connectivity configurations..."
            
            # Get connectivity configuration names
            local config_ids=$(az network manager connect-config list \
                --resource-group "$resource_group" \
                --network-manager-name "$nm" \
                --query "[].id" -o tsv 2>/dev/null || echo "")
            
            if [[ -n "$config_ids" ]]; then
                for config_id in $config_ids; do
                    log "Removing connectivity configuration: $config_id"
                    az network manager post-commit \
                        --resource-group "$resource_group" \
                        --network-manager-name "$nm" \
                        --commit-type "Connectivity" \
                        --configuration-ids "$config_id" \
                        --target-locations "$location" \
                        --is-removal true \
                        --output table 2>/dev/null || warning "Failed to remove configuration: $config_id"
                done
                
                # Wait for configurations to be removed
                log "Waiting for configurations to be removed..."
                sleep 60
            fi
        fi
    done
    
    success "Virtual Network Manager configurations processed"
}

# Function to remove DNS Private Resolver components
remove_dns_resolver_components() {
    local resource_group="$1"
    
    log "Checking for DNS Private Resolver components..."
    
    # Get DNS resolvers in the resource group
    local dns_resolvers=$(az dns-resolver list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "$dns_resolvers" ]]; then
        log "No DNS Private Resolvers found"
        return 0
    fi
    
    for resolver in $dns_resolvers; do
        log "Processing DNS Private Resolver: $resolver"
        
        # Remove forwarding rulesets first (they depend on endpoints)
        log "Checking for DNS forwarding rulesets..."
        local rulesets=$(az dns-resolver forwarding-ruleset list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
        
        for ruleset in $rulesets; do
            log "Removing DNS forwarding ruleset: $ruleset"
            az dns-resolver forwarding-ruleset delete \
                --name "$ruleset" \
                --resource-group "$resource_group" \
                --yes \
                --output table 2>/dev/null || warning "Failed to remove ruleset: $ruleset"
        done
        
        # Remove the DNS resolver (this will remove endpoints automatically)
        log "Removing DNS Private Resolver: $resolver"
        az dns-resolver delete \
            --name "$resolver" \
            --resource-group "$resource_group" \
            --yes \
            --output table 2>/dev/null || warning "Failed to remove DNS resolver: $resolver"
    done
    
    success "DNS Private Resolver components processed"
}

# Function to handle specific resource types that may need special handling
handle_special_resources() {
    local resource_group="$1"
    
    log "Handling special resources that may need explicit deletion..."
    
    # Remove private endpoints first (they may block other deletions)
    log "Checking for private endpoints..."
    local private_endpoints=$(az network private-endpoint list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    for pe in $private_endpoints; do
        log "Removing private endpoint: $pe"
        az network private-endpoint delete \
            --name "$pe" \
            --resource-group "$resource_group" \
            --output table 2>/dev/null || warning "Failed to remove private endpoint: $pe"
    done
    
    # Remove private DNS zones
    log "Checking for private DNS zones..."
    local private_zones=$(az network private-dns zone list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    for zone in $private_zones; do
        log "Removing private DNS zone: $zone"
        az network private-dns zone delete \
            --name "$zone" \
            --resource-group "$resource_group" \
            --yes \
            --output table 2>/dev/null || warning "Failed to remove private DNS zone: $zone"
    done
    
    success "Special resources processed"
}

# Function to perform the main resource group deletion
delete_resource_group() {
    local resource_group="$1"
    
    log "Starting resource group deletion: $resource_group"
    warning "This may take several minutes to complete..."
    
    # Use --no-wait for asynchronous deletion, then monitor
    az group delete \
        --name "$resource_group" \
        --yes \
        --no-wait
    
    success "Resource group deletion initiated: $resource_group"
    log "Deletion is running asynchronously in the background"
    
    # Optional: Monitor deletion progress
    log "Monitoring deletion progress (this may take 5-15 minutes)..."
    local max_attempts=45  # 15 minutes with 20-second intervals
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if ! az group show --name "$resource_group" &>/dev/null; then
            success "Resource group has been successfully deleted!"
            return 0
        fi
        
        echo -n "."
        sleep 20
        ((attempt++))
    done
    
    warning "Resource group deletion is still in progress"
    warning "You can check status with: az group show --name $resource_group"
}

# Function to clean up deployment info files
cleanup_deployment_files() {
    log "Cleaning up deployment information files..."
    
    local info_files=$(ls deployment-info-*.txt 2>/dev/null || echo "")
    
    if [[ -n "$info_files" ]]; then
        for file in $info_files; do
            log "Removing deployment info file: $file"
            rm -f "$file"
        done
        success "Deployment info files cleaned up"
    else
        log "No deployment info files found"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    local resource_group="$1"
    
    log "Verifying cleanup completion..."
    
    if az group show --name "$resource_group" &>/dev/null; then
        warning "Resource group still exists: $resource_group"
        warning "Deletion may still be in progress. Check Azure portal for status."
        return 1
    else
        success "Resource group has been completely removed: $resource_group"
        return 0
    fi
}

# Main execution function
main() {
    local resource_group
    local force_delete=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group|-g)
                resource_group="$2"
                shift 2
                ;;
            --force|-f)
                force_delete=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  -g, --resource-group NAME    Specify resource group to delete"
                echo "  -f, --force                  Skip confirmation prompts"
                echo "  -h, --help                   Show this help message"
                echo
                echo "If no resource group is specified, the script will try to find"
                echo "deployment info files or prompt for input."
                exit 0
                ;;
            *)
                error "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
    
    log "Starting Azure Hybrid DNS Resolution cleanup..."
    
    check_prerequisites
    
    # Get resource group if not provided
    if [[ -z "${resource_group:-}" ]]; then
        resource_group=$(get_resource_group)
    fi
    
    verify_resource_group "$resource_group"
    list_resources "$resource_group"
    
    # Confirm destruction unless force flag is used
    if [[ "$force_delete" != true ]]; then
        confirm_destruction "$resource_group"
    fi
    
    # Perform cleanup in proper order
    remove_network_manager_configs "$resource_group"
    remove_dns_resolver_components "$resource_group"
    handle_special_resources "$resource_group"
    delete_resource_group "$resource_group"
    cleanup_deployment_files
    
    echo
    echo "=========================================="
    success "Azure Hybrid DNS Resolution cleanup completed!"
    echo "=========================================="
    echo
    
    if verify_cleanup "$resource_group"; then
        echo "All resources have been successfully removed."
        echo "The cleanup process is complete."
    else
        echo "Cleanup initiated successfully."
        echo "You can monitor the progress in the Azure portal."
        echo "To check status: az group show --name $resource_group"
    fi
    echo
}

# Run main function with all arguments
main "$@"