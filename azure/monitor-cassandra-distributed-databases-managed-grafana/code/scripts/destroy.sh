#!/bin/bash

# Destroy Azure Managed Instance for Apache Cassandra with Azure Managed Grafana Monitoring
# This script safely removes all resources created by the deploy.sh script

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/tmp/cassandra-monitoring-destroy.log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Destruction failed. Check log file: $LOG_FILE"
    exit 1
}

# Prerequisites check function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI first."
    fi
    
    # Check if logged in to Azure
    if ! az account show &>/dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    log_success "Prerequisites check passed"
}

# Function to confirm destruction
confirm_destruction() {
    local resource_group="$1"
    
    echo ""
    log_warn "============================================"
    log_warn "DESTRUCTIVE OPERATION WARNING"
    log_warn "============================================"
    log_warn "This will delete the following resources:"
    log_warn "  - Resource Group: $resource_group"
    log_warn "  - All contained resources (Cassandra, Grafana, VNet, etc.)"
    log_warn "  - All monitoring data and configurations"
    echo ""
    log_warn "This action cannot be undone!"
    echo ""
    
    # Triple confirmation for safety
    local confirm1 confirm2 confirm3
    
    read -p "Type 'yes' to confirm resource deletion: " confirm1
    if [[ "$confirm1" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    read -p "Type 'DELETE' to confirm permanent data loss: " confirm2
    if [[ "$confirm2" != "DELETE" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    read -p "Type the resource group name '$resource_group' to proceed: " confirm3
    if [[ "$confirm3" != "$resource_group" ]]; then
        log_info "Destruction cancelled - resource group name mismatch"
        exit 0
    fi
    
    log_warn "Proceeding with resource destruction in 10 seconds..."
    log_warn "Press Ctrl+C to cancel"
    sleep 10
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    local max_attempts="${4:-30}"
    local attempt=1
    
    log_info "Waiting for $resource_type '$resource_name' deletion..."
    
    while [[ $attempt -le $max_attempts ]]; do
        case "$resource_type" in
            "cassandra-datacenter")
                if ! az managed-cassandra datacenter show \
                    --cluster-name "$CASSANDRA_CLUSTER_NAME" \
                    --data-center-name "$resource_name" \
                    --resource-group "$resource_group" &>/dev/null; then
                    log_success "$resource_type '$resource_name' deleted"
                    return 0
                fi
                ;;
            "cassandra-cluster")
                if ! az managed-cassandra cluster show \
                    --cluster-name "$resource_name" \
                    --resource-group "$resource_group" &>/dev/null; then
                    log_success "$resource_type '$resource_name' deleted"
                    return 0
                fi
                ;;
            "grafana")
                if ! az grafana show \
                    --name "$resource_name" \
                    --resource-group "$resource_group" &>/dev/null; then
                    log_success "$resource_type '$resource_name' deleted"
                    return 0
                fi
                ;;
            "resource-group")
                if ! az group exists --name "$resource_name" 2>/dev/null; then
                    log_success "$resource_type '$resource_name' deleted"
                    return 0
                fi
                ;;
        esac
        
        log_info "Attempt $attempt/$max_attempts: $resource_type still exists, waiting 30 seconds..."
        sleep 30
        ((attempt++))
    done
    
    log_warn "$resource_type '$resource_name' deletion timeout reached"
    return 1
}

# Function to get resource information
get_resource_info() {
    local resource_group="$1"
    
    log_info "Gathering resource information from $resource_group..."
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Try to find Cassandra cluster
    CASSANDRA_CLUSTER_NAME=""
    local clusters
    clusters=$(az managed-cassandra cluster list \
        --resource-group "$resource_group" \
        --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$clusters" ]]; then
        CASSANDRA_CLUSTER_NAME=$(echo "$clusters" | head -n1)
        log_info "Found Cassandra cluster: $CASSANDRA_CLUSTER_NAME"
    else
        log_warn "No Cassandra clusters found in resource group"
    fi
    
    # Try to find Grafana instance
    GRAFANA_NAME=""
    local grafana_instances
    grafana_instances=$(az grafana list \
        --resource-group "$resource_group" \
        --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$grafana_instances" ]]; then
        GRAFANA_NAME=$(echo "$grafana_instances" | head -n1)
        log_info "Found Grafana instance: $GRAFANA_NAME"
    else
        log_warn "No Grafana instances found in resource group"
    fi
    
    # Try to find Log Analytics workspace
    WORKSPACE_NAME=""
    local workspaces
    workspaces=$(az monitor log-analytics workspace list \
        --resource-group "$resource_group" \
        --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$workspaces" ]]; then
        WORKSPACE_NAME=$(echo "$workspaces" | head -n1)
        log_info "Found Log Analytics workspace: $WORKSPACE_NAME"
    else
        log_warn "No Log Analytics workspaces found in resource group"
    fi
}

# Function to delete individual resources with proper error handling
delete_resource_safe() {
    local resource_type="$1"
    local delete_command="$2"
    local resource_name="$3"
    
    log_info "Deleting $resource_type: $resource_name"
    
    if eval "$delete_command" &>/dev/null; then
        log_success "$resource_type deletion initiated: $resource_name"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 3 ]]; then
            # Resource not found (Azure CLI exit code 3)
            log_warn "$resource_type not found: $resource_name"
            return 0
        else
            log_error "Failed to delete $resource_type: $resource_name (exit code: $exit_code)"
            return $exit_code
        fi
    fi
}

# Function to perform selective cleanup
selective_cleanup() {
    local resource_group="$1"
    
    log_info "Starting selective resource cleanup..."
    
    get_resource_info "$resource_group"
    
    # Step 1: Delete monitoring alerts first
    log_info "Step 1: Removing monitoring alerts..."
    
    delete_resource_safe "metric alert" \
        "az monitor metrics alert delete --name 'cassandra-high-cpu' --resource-group '$resource_group' --yes" \
        "cassandra-high-cpu"
    
    delete_resource_safe "action group" \
        "az monitor action-group delete --name 'cassandra-alerts' --resource-group '$resource_group'" \
        "cassandra-alerts"
    
    # Step 2: Delete Grafana instance
    if [[ -n "$GRAFANA_NAME" ]]; then
        log_info "Step 2: Deleting Grafana instance..."
        delete_resource_safe "Grafana instance" \
            "az grafana delete --name '$GRAFANA_NAME' --resource-group '$resource_group' --yes" \
            "$GRAFANA_NAME"
        
        wait_for_deletion "grafana" "$GRAFANA_NAME" "$resource_group" 20
    else
        log_warn "Step 2: No Grafana instance to delete"
    fi
    
    # Step 3: Delete Cassandra data centers first
    if [[ -n "$CASSANDRA_CLUSTER_NAME" ]]; then
        log_info "Step 3: Deleting Cassandra data centers..."
        
        # Get all data centers for the cluster
        local datacenters
        datacenters=$(az managed-cassandra datacenter list \
            --cluster-name "$CASSANDRA_CLUSTER_NAME" \
            --resource-group "$resource_group" \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        for dc in $datacenters; do
            log_info "Deleting data center: $dc"
            delete_resource_safe "Cassandra data center" \
                "az managed-cassandra datacenter delete --cluster-name '$CASSANDRA_CLUSTER_NAME' --data-center-name '$dc' --resource-group '$resource_group' --yes" \
                "$dc"
            
            wait_for_deletion "cassandra-datacenter" "$dc" "$resource_group" 40
        done
    else
        log_warn "Step 3: No Cassandra cluster found"
    fi
    
    # Step 4: Delete Cassandra cluster
    if [[ -n "$CASSANDRA_CLUSTER_NAME" ]]; then
        log_info "Step 4: Deleting Cassandra cluster..."
        delete_resource_safe "Cassandra cluster" \
            "az managed-cassandra cluster delete --cluster-name '$CASSANDRA_CLUSTER_NAME' --resource-group '$resource_group' --yes" \
            "$CASSANDRA_CLUSTER_NAME"
        
        wait_for_deletion "cassandra-cluster" "$CASSANDRA_CLUSTER_NAME" "$resource_group" 40
    else
        log_warn "Step 4: No Cassandra cluster to delete"
    fi
    
    # Step 5: Delete Log Analytics workspace
    if [[ -n "$WORKSPACE_NAME" ]]; then
        log_info "Step 5: Deleting Log Analytics workspace..."
        delete_resource_safe "Log Analytics workspace" \
            "az monitor log-analytics workspace delete --workspace-name '$WORKSPACE_NAME' --resource-group '$resource_group' --yes" \
            "$WORKSPACE_NAME"
    else
        log_warn "Step 5: No Log Analytics workspace to delete"
    fi
    
    # Step 6: Delete virtual networks and other networking resources
    log_info "Step 6: Deleting networking resources..."
    
    local vnets
    vnets=$(az network vnet list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    for vnet in $vnets; do
        delete_resource_safe "Virtual network" \
            "az network vnet delete --name '$vnet' --resource-group '$resource_group'" \
            "$vnet"
    done
    
    log_success "Selective cleanup completed"
}

# Function to prompt for cleanup method
prompt_cleanup_method() {
    local resource_group="$1"
    
    echo ""
    log_info "Choose cleanup method:"
    log_info "1. Quick cleanup (delete entire resource group)"
    log_info "2. Selective cleanup (delete resources individually)"
    log_info "3. Cancel destruction"
    echo ""
    
    local choice
    read -p "Enter your choice (1-3): " choice
    
    case $choice in
        1)
            return 0  # Quick cleanup
            ;;
        2)
            return 1  # Selective cleanup
            ;;
        3)
            log_info "Destruction cancelled by user"
            exit 0
            ;;
        *)
            log_error "Invalid choice. Please enter 1, 2, or 3."
            prompt_cleanup_method "$resource_group"
            ;;
    esac
}

# Main destruction function
main() {
    log_info "Starting Azure Cassandra Monitoring destruction"
    log_info "Log file: $LOG_FILE"
    
    # Check prerequisites
    check_prerequisites
    
    # Configuration with defaults or from environment
    local resource_group="${RESOURCE_GROUP:-}"
    
    # Interactive resource group selection if not provided
    if [[ -z "$resource_group" ]]; then
        echo ""
        log_info "Available resource groups in your subscription:"
        az group list --query "[].name" --output table
        echo ""
        read -p "Enter the resource group name to destroy: " resource_group
        
        if [[ -z "$resource_group" ]]; then
            error_exit "Resource group name is required"
        fi
    fi
    
    # Verify resource group exists
    if ! az group exists --name "$resource_group" 2>/dev/null; then
        error_exit "Resource group '$resource_group' does not exist"
    fi
    
    # Show resource group contents
    log_info "Resources in '$resource_group':"
    az resource list --resource-group "$resource_group" --output table 2>/dev/null || log_warn "Could not list resources"
    
    # Confirm destruction
    confirm_destruction "$resource_group"
    
    # Choose cleanup method (unless FORCE_QUICK is set)
    local use_quick_cleanup=0
    if [[ "${FORCE_QUICK:-}" == "true" ]]; then
        use_quick_cleanup=0
    else
        if prompt_cleanup_method "$resource_group"; then
            use_quick_cleanup=0
        else
            use_quick_cleanup=1
        fi
    fi
    
    if [[ $use_quick_cleanup -eq 0 ]]; then
        # Quick cleanup - delete entire resource group
        log_info "Performing quick cleanup (deleting entire resource group)..."
        
        if az group delete --name "$resource_group" --yes --no-wait; then
            log_success "Resource group deletion initiated: $resource_group"
            log_info "Deletion is running in the background..."
            
            if [[ "${WAIT_FOR_COMPLETION:-}" == "true" ]]; then
                wait_for_deletion "resource-group" "$resource_group" "" 60
            else
                log_info "To monitor deletion progress, run:"
                log_info "  az group show --name '$resource_group'"
            fi
        else
            error_exit "Failed to initiate resource group deletion"
        fi
    else
        # Selective cleanup - delete resources individually
        selective_cleanup "$resource_group"
        
        # Final cleanup - delete resource group if it's empty
        log_info "Checking if resource group is empty..."
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "$resource_group" --query "length([])" --output tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_resources" -eq 0 ]]; then
            log_info "Resource group is empty, deleting it..."
            az group delete --name "$resource_group" --yes --no-wait
            log_success "Empty resource group deletion initiated: $resource_group"
        else
            log_warn "Resource group still contains $remaining_resources resources"
            log_info "Run the script again or manually clean up remaining resources"
        fi
    fi
    
    # Clean up local files
    log_info "Cleaning up local configuration files..."
    rm -f datasource-config.json cassandra-dashboard.json
    log_success "Local files cleaned up"
    
    # Final summary
    log_success "============================================"
    log_success "Destruction process completed!"
    log_success "============================================"
    log_info "Summary:"
    log_info "  Resource Group: $resource_group"
    
    if [[ $use_quick_cleanup -eq 0 ]]; then
        log_info "  Method: Quick cleanup (entire resource group)"
        log_info "  Status: Deletion initiated (running in background)"
        log_info ""
        log_info "Monitor deletion progress with:"
        log_info "  az group show --name '$resource_group'"
    else
        log_info "  Method: Selective cleanup (individual resources)"
        log_info "  Status: Resources deleted individually"
    fi
    
    log_info ""
    log_warn "Please verify in Azure portal that all resources are deleted"
    log_warn "to avoid unexpected charges."
    log_info ""
    log_info "Destruction log saved to: $LOG_FILE"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi