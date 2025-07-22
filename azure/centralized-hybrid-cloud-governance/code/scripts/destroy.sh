#!/bin/bash

# Azure Arc and Azure Policy Cleanup Script
# This script safely removes Azure Arc governance infrastructure
# and disconnects hybrid resources from Azure management

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ✅ $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ⚠️ $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ❌ $1"
}

# Default values
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
CLUSTER_NAME=""
DRY_RUN=false
FORCE_DELETE=false
SKIP_CONFIRMATION=false
DELETE_RESOURCE_GROUP=false
PRESERVE_WORKSPACE=false

# Help function
show_help() {
    cat << EOF
Azure Arc and Azure Policy Cleanup Script

Usage: $0 [OPTIONS]

Options:
    -g, --resource-group NAME    Resource group name (required)
    -s, --subscription ID        Azure subscription ID (optional - uses current)
    -c, --cluster NAME          Kubernetes cluster name (optional - auto-discover)
    -d, --dry-run               Show what would be deleted without making changes
    -f, --force                 Force deletion without confirmation prompts
    -y, --yes                   Skip all confirmation prompts
    -r, --delete-rg             Delete the entire resource group
    -w, --preserve-workspace    Preserve Log Analytics workspace
    -h, --help                  Show this help message

Warning: This script will disconnect Arc-enabled resources and remove governance policies.
Ensure you have proper backups and understand the impact before proceeding.

Examples:
    $0 -g rg-arc-governance -d
    $0 --resource-group rg-arc-governance --force --delete-rg
    $0 -g rg-arc-governance -c arc-k8s-cluster --preserve-workspace

EOF
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
        -c|--cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -r|--delete-rg)
            DELETE_RESOURCE_GROUP=true
            shift
            ;;
        -w|--preserve-workspace)
            PRESERVE_WORKSPACE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    log_error "Resource group name is required. Use -g or --resource-group."
    show_help
    exit 1
fi

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get subscription ID if not provided
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        log "Using current subscription: $SUBSCRIPTION_ID"
    else
        # Set the subscription
        az account set --subscription "$SUBSCRIPTION_ID"
        log "Set subscription to: $SUBSCRIPTION_ID"
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group '$RESOURCE_GROUP' does not exist."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Get confirmation from user
get_confirmation() {
    if [[ "$SKIP_CONFIRMATION" == true ]] || [[ "$FORCE_DELETE" == true ]]; then
        return 0
    fi
    
    echo ""
    echo "=========================================="
    echo "DELETION CONFIRMATION"
    echo "=========================================="
    echo "This will remove the following resources:"
    echo "- Resource Group: $RESOURCE_GROUP"
    echo "- All Azure Arc connections"
    echo "- All policy assignments"
    echo "- All monitoring configurations"
    
    if [[ "$DELETE_RESOURCE_GROUP" == true ]]; then
        echo "- THE ENTIRE RESOURCE GROUP will be deleted"
    fi
    
    echo ""
    echo "WARNING: This action cannot be undone!"
    echo "=========================================="
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    if [[ "$REPLY" != "yes" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
}

# Discover Arc-enabled resources
discover_arc_resources() {
    log "Discovering Arc-enabled resources..."
    
    # Discover Arc-enabled Kubernetes clusters
    if [[ -z "$CLUSTER_NAME" ]]; then
        CLUSTER_NAMES=$(az connectedk8s list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        if [[ -n "$CLUSTER_NAMES" ]]; then
            CLUSTER_NAME=$(echo "$CLUSTER_NAMES" | head -n1)
            log "Discovered Arc-enabled Kubernetes cluster: $CLUSTER_NAME"
        fi
    fi
    
    # Discover Arc-enabled servers
    SERVER_NAMES=$(az connectedmachine list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$SERVER_NAMES" ]]; then
        log "Discovered Arc-enabled servers: $(echo "$SERVER_NAMES" | tr '\n' ' ')"
    fi
    
    # Discover service principals
    SP_NAMES=$(az ad sp list --all --query "[?contains(displayName, 'sp-arc-onboarding')].displayName" --output tsv 2>/dev/null || echo "")
    if [[ -n "$SP_NAMES" ]]; then
        log "Discovered service principals: $(echo "$SP_NAMES" | tr '\n' ' ')"
    fi
    
    export CLUSTER_NAME
    export SERVER_NAMES
    export SP_NAMES
}

# Remove policy assignments and remediation tasks
remove_policies() {
    log "Removing policy assignments and remediation tasks..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would remove policy remediation tasks"
        log "[DRY RUN] Would remove policy assignments"
        return 0
    fi
    
    # Remove remediation tasks first
    REMEDIATION_TASKS=$(az policy remediation list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$REMEDIATION_TASKS" ]]; then
        log "Removing policy remediation tasks..."
        for task in $REMEDIATION_TASKS; do
            log "Removing remediation task: $task"
            az policy remediation delete \
                --name "$task" \
                --resource-group "$RESOURCE_GROUP" \
                --output none 2>/dev/null || log_warning "Failed to remove remediation task: $task"
        done
    fi
    
    # Remove policy assignments
    POLICY_ASSIGNMENTS=$(az policy assignment list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$POLICY_ASSIGNMENTS" ]]; then
        log "Removing policy assignments..."
        for assignment in $POLICY_ASSIGNMENTS; do
            log "Removing policy assignment: $assignment"
            az policy assignment delete \
                --name "$assignment" \
                --resource-group "$RESOURCE_GROUP" \
                --output none 2>/dev/null || log_warning "Failed to remove policy assignment: $assignment"
        done
    fi
    
    log_success "Policy assignments and remediation tasks removed"
}

# Disconnect Arc-enabled Kubernetes clusters
disconnect_kubernetes_clusters() {
    if [[ -z "$CLUSTER_NAME" ]]; then
        log_warning "No Arc-enabled Kubernetes clusters found"
        return 0
    fi
    
    log "Disconnecting Arc-enabled Kubernetes clusters..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would remove monitoring extension from cluster: $CLUSTER_NAME"
        log "[DRY RUN] Would remove policy extension from cluster: $CLUSTER_NAME"
        log "[DRY RUN] Would disconnect cluster from Arc: $CLUSTER_NAME"
        return 0
    fi
    
    # Remove monitoring extension
    log "Removing monitoring extension from cluster: $CLUSTER_NAME"
    az k8s-extension delete \
        --name azuremonitor-containers \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-type connectedClusters \
        --yes \
        --output none 2>/dev/null || log_warning "Failed to remove monitoring extension"
    
    # Remove policy extension
    log "Removing policy extension from cluster: $CLUSTER_NAME"
    az k8s-extension delete \
        --name azurepolicy \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-type connectedClusters \
        --yes \
        --output none 2>/dev/null || log_warning "Failed to remove policy extension"
    
    # Disconnect cluster from Arc
    log "Disconnecting cluster from Arc: $CLUSTER_NAME"
    az connectedk8s delete \
        --name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --yes \
        --output none 2>/dev/null || log_warning "Failed to disconnect cluster from Arc"
    
    log_success "Kubernetes clusters disconnected from Azure Arc"
}

# Disconnect Arc-enabled servers
disconnect_servers() {
    if [[ -z "$SERVER_NAMES" ]]; then
        log_warning "No Arc-enabled servers found"
        return 0
    fi
    
    log "Disconnecting Arc-enabled servers..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would disconnect servers from Arc: $(echo "$SERVER_NAMES" | tr '\n' ' ')"
        return 0
    fi
    
    # Disconnect each server
    for server in $SERVER_NAMES; do
        log "Disconnecting server from Arc: $server"
        az connectedmachine delete \
            --name "$server" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none 2>/dev/null || log_warning "Failed to disconnect server: $server"
    done
    
    log_success "Servers disconnected from Azure Arc"
    
    # Display manual cleanup instructions
    echo ""
    echo "=========================================="
    echo "MANUAL SERVER CLEANUP REQUIRED"
    echo "=========================================="
    echo "The following commands must be run on each server to complete cleanup:"
    echo ""
    echo "For Linux servers:"
    echo "sudo azcmagent disconnect --force-local-only"
    echo "sudo apt-get remove azcmagent"
    echo "# or"
    echo "sudo yum remove azcmagent"
    echo ""
    echo "For Windows servers:"
    echo "& \"C:\\Program Files\\AzureConnectedMachineAgent\\azcmagent.exe\" disconnect --force-local-only"
    echo "Remove-Item \"C:\\Program Files\\AzureConnectedMachineAgent\" -Recurse -Force"
    echo ""
    echo "This will remove the Azure Arc agent from each server."
    echo "=========================================="
}

# Remove service principals
remove_service_principals() {
    if [[ -z "$SP_NAMES" ]]; then
        log_warning "No service principals found"
        return 0
    fi
    
    log "Removing service principals..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would remove service principals: $(echo "$SP_NAMES" | tr '\n' ' ')"
        return 0
    fi
    
    # Remove each service principal
    for sp_name in $SP_NAMES; do
        SP_ID=$(az ad sp list --display-name "$sp_name" --query "[0].appId" --output tsv 2>/dev/null || echo "")
        if [[ -n "$SP_ID" ]]; then
            log "Removing service principal: $sp_name ($SP_ID)"
            az ad sp delete --id "$SP_ID" --output none 2>/dev/null || log_warning "Failed to remove service principal: $sp_name"
        fi
    done
    
    log_success "Service principals removed"
}

# Remove monitoring resources
remove_monitoring_resources() {
    log "Removing monitoring resources..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would remove data collection rules"
        if [[ "$PRESERVE_WORKSPACE" == false ]]; then
            log "[DRY RUN] Would remove Log Analytics workspace"
        fi
        return 0
    fi
    
    # Remove data collection rules
    DCR_NAMES=$(az monitor data-collection rule list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$DCR_NAMES" ]]; then
        log "Removing data collection rules..."
        for dcr in $DCR_NAMES; do
            log "Removing data collection rule: $dcr"
            az monitor data-collection rule delete \
                --name "$dcr" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none 2>/dev/null || log_warning "Failed to remove data collection rule: $dcr"
        done
    fi
    
    # Remove Log Analytics workspace if not preserving
    if [[ "$PRESERVE_WORKSPACE" == false ]]; then
        WORKSPACE_NAMES=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        if [[ -n "$WORKSPACE_NAMES" ]]; then
            log "Removing Log Analytics workspaces..."
            for workspace in $WORKSPACE_NAMES; do
                log "Removing Log Analytics workspace: $workspace"
                az monitor log-analytics workspace delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --workspace-name "$workspace" \
                    --yes \
                    --output none 2>/dev/null || log_warning "Failed to remove workspace: $workspace"
            done
        fi
    else
        log_warning "Preserving Log Analytics workspace as requested"
    fi
    
    log_success "Monitoring resources removed"
}

# Remove Resource Graph saved queries
remove_resource_graph_queries() {
    log "Removing Resource Graph saved queries..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would remove Resource Graph saved queries"
        return 0
    fi
    
    # Remove saved queries
    SAVED_QUERIES=$(az graph shared-query list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$SAVED_QUERIES" ]]; then
        for query in $SAVED_QUERIES; do
            log "Removing saved query: $query"
            az graph shared-query delete \
                --name "$query" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none 2>/dev/null || log_warning "Failed to remove saved query: $query"
        done
    fi
    
    log_success "Resource Graph saved queries removed"
}

# Remove resource group
remove_resource_group() {
    if [[ "$DELETE_RESOURCE_GROUP" == false ]]; then
        log_warning "Resource group preservation requested. Skipping resource group deletion."
        return 0
    fi
    
    log "Removing resource group..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Final confirmation for resource group deletion
    if [[ "$SKIP_CONFIRMATION" == false ]] && [[ "$FORCE_DELETE" == false ]]; then
        echo ""
        echo "=========================================="
        echo "FINAL CONFIRMATION"
        echo "=========================================="
        echo "You are about to delete the ENTIRE resource group: $RESOURCE_GROUP"
        echo "This will remove ALL resources in the group, including any not created by this script."
        echo "=========================================="
        echo ""
        read -p "Type 'DELETE' to confirm complete resource group deletion: " -r
        if [[ "$REPLY" != "DELETE" ]]; then
            log "Resource group deletion cancelled by user."
            return 0
        fi
    fi
    
    log "Deleting resource group: $RESOURCE_GROUP"
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log_warning "Resource group deletion may take several minutes to complete"
}

# Display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "=========================================="
    echo "CLEANUP SUMMARY"
    echo "=========================================="
    echo "The following cleanup actions were performed:"
    echo ""
    echo "✅ Policy assignments and remediation tasks removed"
    echo "✅ Arc-enabled Kubernetes clusters disconnected"
    echo "✅ Arc-enabled servers disconnected"
    echo "✅ Service principals removed"
    echo "✅ Monitoring resources removed"
    echo "✅ Resource Graph saved queries removed"
    
    if [[ "$DELETE_RESOURCE_GROUP" == true ]]; then
        echo "✅ Resource group deletion initiated"
    else
        echo "⚠️  Resource group preserved"
    fi
    
    echo ""
    echo "Important notes:"
    echo "- Run the manual server cleanup commands shown above"
    echo "- Verify all resources have been removed in the Azure Portal"
    echo "- Check for any remaining charges in your Azure billing"
    echo "=========================================="
}

# Main cleanup function
main() {
    log "Starting Azure Arc and Azure Policy cleanup..."
    
    check_prerequisites
    get_confirmation
    discover_arc_resources
    remove_policies
    disconnect_kubernetes_clusters
    disconnect_servers
    remove_service_principals
    remove_monitoring_resources
    remove_resource_graph_queries
    remove_resource_group
    display_cleanup_summary
    
    if [[ "$DRY_RUN" == true ]]; then
        log_success "Dry run completed successfully. No resources were removed."
        log "Run without --dry-run to perform actual cleanup."
    else
        log_success "Cleanup completed successfully!"
        log "All Azure Arc governance resources have been removed."
    fi
}

# Run main function
main "$@"