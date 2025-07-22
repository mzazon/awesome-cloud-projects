#!/bin/bash

#==============================================================================
# Azure Elastic SAN and VMSS Database Infrastructure Cleanup Script
# This script safely removes all resources created by the deployment
#==============================================================================

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
SKIP_CONFIRMATION=false
DELETE_RESOURCE_GROUP=false
FORCE_DELETE=false

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}$1${NC}"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup Azure Elastic SAN and VMSS database infrastructure resources.

OPTIONS:
    -g, --resource-group    Resource group name (required)
    -s, --subscription      Azure subscription ID
    -y, --yes               Skip confirmation prompts
    -r, --delete-rg         Delete the entire resource group
    -f, --force             Force delete without additional confirmations
    -h, --help              Show this help message

EXAMPLES:
    $0 -g rg-elastic-san-demo
    $0 -g rg-elastic-san-demo -r  # Delete entire resource group
    $0 -g rg-elastic-san-demo -y  # Skip confirmation
    $0 -g rg-elastic-san-demo -f  # Force delete

WARNING: This script will permanently delete resources. Use with caution.

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    print_status "Prerequisites check completed."
}

# Function to set Azure subscription
set_subscription() {
    if [ -n "$SUBSCRIPTION_ID" ]; then
        print_status "Setting subscription to: $SUBSCRIPTION_ID"
        az account set --subscription "$SUBSCRIPTION_ID"
    fi
    
    # Show current subscription
    CURRENT_SUB=$(az account show --query "name" --output tsv)
    print_status "Current subscription: $CURRENT_SUB"
}

# Function to list resources in the resource group
list_resources() {
    print_header "Resources in Resource Group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        az resource list --resource-group "$RESOURCE_GROUP" --output table
    else
        print_error "Resource group '$RESOURCE_GROUP' not found."
        exit 1
    fi
}

# Function to delete specific resources in order
delete_resources_individually() {
    print_header "Deleting Resources Individually..."
    
    # Get all resources in the resource group
    RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Type:type,Id:id}" --output tsv)
    
    if [ -z "$RESOURCES" ]; then
        print_status "No resources found in resource group."
        return
    fi
    
    # Delete resources in specific order to handle dependencies
    
    # 1. Delete metric alerts first
    print_status "Deleting metric alerts..."
    az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Insights/metricAlerts" --query "[].name" --output tsv | \
    while IFS= read -r alert_name; do
        if [ -n "$alert_name" ]; then
            print_status "Deleting metric alert: $alert_name"
            az monitor metrics alert delete --name "$alert_name" --resource-group "$RESOURCE_GROUP" || true
        fi
    done
    
    # 2. Delete autoscale settings
    print_status "Deleting autoscale settings..."
    az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Insights/autoscalesettings" --query "[].name" --output tsv | \
    while IFS= read -r autoscale_name; do
        if [ -n "$autoscale_name" ]; then
            print_status "Deleting autoscale setting: $autoscale_name"
            az monitor autoscale delete --name "$autoscale_name" --resource-group "$RESOURCE_GROUP" || true
        fi
    done
    
    # 3. Delete Virtual Machine Scale Set
    print_status "Deleting Virtual Machine Scale Sets..."
    az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Compute/virtualMachineScaleSets" --query "[].name" --output tsv | \
    while IFS= read -r vmss_name; do
        if [ -n "$vmss_name" ]; then
            print_status "Deleting VMSS: $vmss_name"
            az vmss delete --name "$vmss_name" --resource-group "$RESOURCE_GROUP" || true
        fi
    done
    
    # 4. Delete Load Balancer
    print_status "Deleting Load Balancers..."
    az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Network/loadBalancers" --query "[].name" --output tsv | \
    while IFS= read -r lb_name; do
        if [ -n "$lb_name" ]; then
            print_status "Deleting Load Balancer: $lb_name"
            az network lb delete --name "$lb_name" --resource-group "$RESOURCE_GROUP" || true
        fi
    done
    
    # 5. Delete Public IP addresses
    print_status "Deleting Public IP addresses..."
    az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Network/publicIPAddresses" --query "[].name" --output tsv | \
    while IFS= read -r pip_name; do
        if [ -n "$pip_name" ]; then
            print_status "Deleting Public IP: $pip_name"
            az network public-ip delete --name "$pip_name" --resource-group "$RESOURCE_GROUP" || true
        fi
    done
    
    # 6. Delete PostgreSQL Flexible Server
    print_status "Deleting PostgreSQL Flexible Servers..."
    az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.DBforPostgreSQL/flexibleServers" --query "[].name" --output tsv | \
    while IFS= read -r postgres_name; do
        if [ -n "$postgres_name" ]; then
            print_status "Deleting PostgreSQL Flexible Server: $postgres_name"
            az postgres flexible-server delete --name "$postgres_name" --resource-group "$RESOURCE_GROUP" --yes || true
        fi
    done
    
    # 7. Delete Elastic SAN volumes
    print_status "Deleting Elastic SAN volumes..."
    az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.ElasticSan/elasticSans" --query "[].name" --output tsv | \
    while IFS= read -r esan_name; do
        if [ -n "$esan_name" ]; then
            # Delete volumes in volume groups
            az elastic-san volume-group list --elastic-san-name "$esan_name" --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv | \
            while IFS= read -r vg_name; do
                if [ -n "$vg_name" ]; then
                    az elastic-san volume list --elastic-san-name "$esan_name" --volume-group-name "$vg_name" --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv | \
                    while IFS= read -r volume_name; do
                        if [ -n "$volume_name" ]; then
                            print_status "Deleting Elastic SAN volume: $volume_name"
                            az elastic-san volume delete --name "$volume_name" --volume-group-name "$vg_name" --elastic-san-name "$esan_name" --resource-group "$RESOURCE_GROUP" --yes || true
                        fi
                    done
                    
                    # Delete volume group
                    print_status "Deleting Elastic SAN volume group: $vg_name"
                    az elastic-san volume-group delete --name "$vg_name" --elastic-san-name "$esan_name" --resource-group "$RESOURCE_GROUP" --yes || true
                fi
            done
            
            # Delete Elastic SAN
            print_status "Deleting Elastic SAN: $esan_name"
            az elastic-san delete --name "$esan_name" --resource-group "$RESOURCE_GROUP" --yes || true
        fi
    done
    
    # 8. Delete Virtual Network
    print_status "Deleting Virtual Networks..."
    az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Network/virtualNetworks" --query "[].name" --output tsv | \
    while IFS= read -r vnet_name; do
        if [ -n "$vnet_name" ]; then
            print_status "Deleting Virtual Network: $vnet_name"
            az network vnet delete --name "$vnet_name" --resource-group "$RESOURCE_GROUP" || true
        fi
    done
    
    # 9. Delete Network Security Groups
    print_status "Deleting Network Security Groups..."
    az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Network/networkSecurityGroups" --query "[].name" --output tsv | \
    while IFS= read -r nsg_name; do
        if [ -n "$nsg_name" ]; then
            print_status "Deleting Network Security Group: $nsg_name"
            az network nsg delete --name "$nsg_name" --resource-group "$RESOURCE_GROUP" || true
        fi
    done
    
    # 10. Delete Action Groups
    print_status "Deleting Action Groups..."
    az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Insights/actionGroups" --query "[].name" --output tsv | \
    while IFS= read -r ag_name; do
        if [ -n "$ag_name" ]; then
            print_status "Deleting Action Group: $ag_name"
            az monitor action-group delete --name "$ag_name" --resource-group "$RESOURCE_GROUP" || true
        fi
    done
    
    # 11. Delete Log Analytics Workspace
    print_status "Deleting Log Analytics Workspaces..."
    az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.OperationalInsights/workspaces" --query "[].name" --output tsv | \
    while IFS= read -r law_name; do
        if [ -n "$law_name" ]; then
            print_status "Deleting Log Analytics Workspace: $law_name"
            az monitor log-analytics workspace delete --workspace-name "$law_name" --resource-group "$RESOURCE_GROUP" --force true || true
        fi
    done
    
    # 12. Delete any remaining resources
    print_status "Deleting any remaining resources..."
    sleep 30  # Wait for dependencies to clear
    
    REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Type:type}" --output tsv)
    if [ -n "$REMAINING_RESOURCES" ]; then
        print_warning "Found remaining resources:"
        echo "$REMAINING_RESOURCES"
        
        if [ "$FORCE_DELETE" = true ]; then
            print_status "Force deleting remaining resources..."
            az resource list --resource-group "$RESOURCE_GROUP" --query "[].id" --output tsv | \
            while IFS= read -r resource_id; do
                if [ -n "$resource_id" ]; then
                    print_status "Force deleting resource: $resource_id"
                    az resource delete --ids "$resource_id" || true
                fi
            done
        fi
    fi
}

# Function to delete the entire resource group
delete_resource_group() {
    print_header "Deleting Resource Group: $RESOURCE_GROUP"
    
    if [ "$SKIP_CONFIRMATION" = false ] && [ "$FORCE_DELETE" = false ]; then
        print_warning "This will permanently delete the entire resource group and all resources within it."
        read -p "Are you absolutely sure you want to delete the resource group '$RESOURCE_GROUP'? (type 'DELETE' to confirm): " -r
        echo
        if [[ "$REPLY" != "DELETE" ]]; then
            print_status "Resource group deletion cancelled."
            exit 0
        fi
    fi
    
    print_status "Deleting resource group: $RESOURCE_GROUP"
    if az group delete --name "$RESOURCE_GROUP" --yes --no-wait; then
        print_status "Resource group deletion initiated. This may take several minutes to complete."
        print_status "You can check the status with: az group show --name $RESOURCE_GROUP"
    else
        print_error "Failed to delete resource group."
        exit 1
    fi
}

# Function to verify cleanup
verify_cleanup() {
    print_header "Verifying Cleanup..."
    
    if [ "$DELETE_RESOURCE_GROUP" = true ]; then
        # Check if resource group still exists
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            print_warning "Resource group still exists. Deletion may still be in progress."
        else
            print_status "Resource group successfully deleted."
        fi
    else
        # Check remaining resources
        REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --output table)
        if [ -n "$REMAINING_RESOURCES" ]; then
            print_warning "Some resources may still exist:"
            echo "$REMAINING_RESOURCES"
        else
            print_status "All resources have been successfully deleted."
        fi
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -r|--delete-rg)
            DELETE_RESOURCE_GROUP=true
            shift
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$RESOURCE_GROUP" ]; then
    print_error "Resource group is required. Use -g or --resource-group."
    show_usage
    exit 1
fi

# Main execution
main() {
    print_header "Azure Elastic SAN and VMSS Database Infrastructure Cleanup"
    echo ""
    
    print_status "Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Delete Resource Group: $DELETE_RESOURCE_GROUP"
    echo "  Force Delete: $FORCE_DELETE"
    echo "  Skip Confirmation: $SKIP_CONFIRMATION"
    echo ""
    
    # Warning message
    print_warning "This script will permanently delete Azure resources."
    print_warning "Deleted resources cannot be recovered."
    echo ""
    
    # Confirmation prompt
    if [ "$SKIP_CONFIRMATION" = false ]; then
        read -p "Do you want to continue with the cleanup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Cleanup cancelled."
            exit 0
        fi
    fi
    
    # Execute cleanup steps
    check_prerequisites
    set_subscription
    list_resources
    
    if [ "$DELETE_RESOURCE_GROUP" = true ]; then
        delete_resource_group
    else
        delete_resources_individually
    fi
    
    verify_cleanup
    
    print_status "Cleanup completed."
}

# Run main function
main