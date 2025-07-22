#!/bin/bash

# Hybrid PostgreSQL Database Replication with Azure Arc and Cloud Database
# Cleanup/Destroy Script
# 
# This script safely removes all resources created by the deployment script including:
# - Azure Data Factory and pipelines
# - Azure Event Grid topics
# - Azure Database for PostgreSQL Flexible Server
# - Arc-enabled PostgreSQL instance
# - Azure Arc Data Controller
# - Azure resource group and all contained resources

set -euo pipefail

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
        INFO)
            echo -e "${BLUE}[INFO]${NC} ${timestamp} - $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${timestamp} - $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - $message"
            ;;
    esac
    
    # Also log to file
    echo "[$level] $timestamp - $message" >> "cleanup_$(date +%Y%m%d_%H%M%S).log"
}

# Error handling
error_exit() {
    log ERROR "$1"
    exit 1
}

# Confirmation prompt
confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}WARNING: This will permanently delete $resource_type: $resource_name${NC}"
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log INFO "Deletion cancelled by user"
        return 1
    fi
    return 0
}

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites for cleanup..."
    
    # Check required tools
    local required_tools=("az" "kubectl" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "Required tool '$tool' is not installed or not in PATH"
        fi
    done
    
    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        error_exit "Please login to Azure CLI using 'az login'"
    fi
    
    log SUCCESS "Prerequisites check completed"
}

# Load environment variables
load_environment() {
    log INFO "Loading environment variables..."
    
    # Try to load from environment or use defaults
    export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    export RESOURCE_GROUP="${RESOURCE_GROUP:-}"
    export LOCATION="${LOCATION:-eastus}"
    export ARC_DC_NAME="${ARC_DC_NAME:-arc-dc-postgres}"
    export K8S_NAMESPACE="${K8S_NAMESPACE:-arc-data}"
    export POSTGRES_NAME="${POSTGRES_NAME:-postgres-hybrid}"
    export AZURE_PG_NAME="${AZURE_PG_NAME:-}"
    export ADF_NAME="${ADF_NAME:-}"
    export EVENTGRID_TOPIC="${EVENTGRID_TOPIC:-}"
    export WORKSPACE_NAME="${WORKSPACE_NAME:-}"
    
    # If resource group is not set, try to discover it
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log INFO "Resource group not specified. Searching for hybrid PostgreSQL resources..."
        
        # Try to find resource group by looking for Arc data controller
        local found_rg
        found_rg=$(az arcdata dc list --query "[?contains(name, 'arc-dc-postgres')].resourceGroup" -o tsv | head -n1)
        
        if [[ -n "$found_rg" ]]; then
            export RESOURCE_GROUP="$found_rg"
            log INFO "Found resource group: $RESOURCE_GROUP"
        else
            # Try to find by PostgreSQL flexible server
            found_rg=$(az postgres flexible-server list --query "[?contains(name, 'azpg-hybrid')].resourceGroup" -o tsv | head -n1)
            
            if [[ -n "$found_rg" ]]; then
                export RESOURCE_GROUP="$found_rg"
                log INFO "Found resource group: $RESOURCE_GROUP"
            else
                error_exit "Could not automatically discover resource group. Please set RESOURCE_GROUP environment variable."
            fi
        fi
    fi
    
    # Discover resource names if not provided
    if [[ -z "$AZURE_PG_NAME" ]]; then
        AZURE_PG_NAME=$(az postgres flexible-server list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'azpg-hybrid')].name" -o tsv | head -n1)
    fi
    
    if [[ -z "$ADF_NAME" ]]; then
        ADF_NAME=$(az datafactory list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'adf-hybrid')].name" -o tsv | head -n1)
    fi
    
    if [[ -z "$EVENTGRID_TOPIC" ]]; then
        EVENTGRID_TOPIC=$(az eventgrid topic list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'eg-topic')].name" -o tsv | head -n1)
    fi
    
    if [[ -z "$WORKSPACE_NAME" ]]; then
        WORKSPACE_NAME=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'law-hybrid-postgres')].name" -o tsv | head -n1)
    fi
    
    log INFO "Environment variables loaded:"
    log INFO "  Resource Group: $RESOURCE_GROUP"
    log INFO "  Azure PostgreSQL: ${AZURE_PG_NAME:-'not found'}"
    log INFO "  Data Factory: ${ADF_NAME:-'not found'}"
    log INFO "  Event Grid Topic: ${EVENTGRID_TOPIC:-'not found'}"
    log INFO "  Log Analytics Workspace: ${WORKSPACE_NAME:-'not found'}"
}

# Stop and remove Data Factory triggers and pipelines
cleanup_data_factory() {
    if [[ -z "$ADF_NAME" ]]; then
        log WARN "Data Factory name not found, skipping cleanup"
        return 0
    fi
    
    log INFO "Cleaning up Data Factory resources..."
    
    # Check if Data Factory exists
    if ! az datafactory show --name "$ADF_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Data Factory '$ADF_NAME' not found, skipping"
        return 0
    fi
    
    if confirm_deletion "Data Factory" "$ADF_NAME"; then
        # Stop all triggers first
        log INFO "Stopping Data Factory triggers..."
        local triggers
        triggers=$(az datafactory trigger list --factory-name "$ADF_NAME" --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || true)
        
        if [[ -n "$triggers" ]]; then
            while IFS= read -r trigger; do
                if [[ -n "$trigger" ]]; then
                    log INFO "Stopping trigger: $trigger"
                    az datafactory trigger stop \
                        --factory-name "$ADF_NAME" \
                        --resource-group "$RESOURCE_GROUP" \
                        --name "$trigger" 2>/dev/null || true
                fi
            done <<< "$triggers"
        fi
        
        # Delete Data Factory
        log INFO "Deleting Data Factory '$ADF_NAME'..."
        if az datafactory delete \
            --name "$ADF_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes 2>/dev/null; then
            log SUCCESS "Data Factory '$ADF_NAME' deleted"
        else
            log WARN "Failed to delete Data Factory '$ADF_NAME'"
        fi
    fi
}

# Remove Event Grid topic
cleanup_event_grid() {
    if [[ -z "$EVENTGRID_TOPIC" ]]; then
        log WARN "Event Grid topic name not found, skipping cleanup"
        return 0
    fi
    
    log INFO "Cleaning up Event Grid resources..."
    
    # Check if Event Grid topic exists
    if ! az eventgrid topic show --name "$EVENTGRID_TOPIC" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Event Grid topic '$EVENTGRID_TOPIC' not found, skipping"
        return 0
    fi
    
    if confirm_deletion "Event Grid topic" "$EVENTGRID_TOPIC"; then
        log INFO "Deleting Event Grid topic '$EVENTGRID_TOPIC'..."
        if az eventgrid topic delete \
            --name "$EVENTGRID_TOPIC" \
            --resource-group "$RESOURCE_GROUP" \
            --yes 2>/dev/null; then
            log SUCCESS "Event Grid topic '$EVENTGRID_TOPIC' deleted"
        else
            log WARN "Failed to delete Event Grid topic '$EVENTGRID_TOPIC'"
        fi
    fi
}

# Remove Azure Database for PostgreSQL
cleanup_azure_postgresql() {
    if [[ -z "$AZURE_PG_NAME" ]]; then
        log WARN "Azure PostgreSQL name not found, skipping cleanup"
        return 0
    fi
    
    log INFO "Cleaning up Azure Database for PostgreSQL..."
    
    # Check if PostgreSQL server exists
    if ! az postgres flexible-server show --name "$AZURE_PG_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Azure PostgreSQL '$AZURE_PG_NAME' not found, skipping"
        return 0
    fi
    
    if confirm_deletion "Azure PostgreSQL Flexible Server" "$AZURE_PG_NAME"; then
        log INFO "Deleting Azure PostgreSQL '$AZURE_PG_NAME' (this may take 5-10 minutes)..."
        if az postgres flexible-server delete \
            --name "$AZURE_PG_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes 2>/dev/null; then
            log SUCCESS "Azure PostgreSQL '$AZURE_PG_NAME' deleted"
        else
            log WARN "Failed to delete Azure PostgreSQL '$AZURE_PG_NAME'"
        fi
    fi
}

# Remove Arc-enabled PostgreSQL
cleanup_arc_postgresql() {
    log INFO "Cleaning up Arc-enabled PostgreSQL..."
    
    # Check if kubectl context is available
    if ! kubectl cluster-info &> /dev/null; then
        log WARN "kubectl not configured, skipping Arc PostgreSQL cleanup"
        return 0
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace "$K8S_NAMESPACE" &> /dev/null; then
        log WARN "Kubernetes namespace '$K8S_NAMESPACE' not found, skipping"
        return 0
    fi
    
    # Check if PostgreSQL instance exists
    if ! kubectl get postgresql "$POSTGRES_NAME" -n "$K8S_NAMESPACE" &> /dev/null; then
        log WARN "Arc PostgreSQL '$POSTGRES_NAME' not found, skipping"
        return 0
    fi
    
    if confirm_deletion "Arc-enabled PostgreSQL" "$POSTGRES_NAME"; then
        log INFO "Deleting Arc PostgreSQL '$POSTGRES_NAME'..."
        if kubectl delete postgresql "$POSTGRES_NAME" -n "$K8S_NAMESPACE" --timeout=300s 2>/dev/null; then
            log SUCCESS "Arc PostgreSQL '$POSTGRES_NAME' deleted"
        else
            log WARN "Failed to delete Arc PostgreSQL '$POSTGRES_NAME'"
        fi
    fi
}

# Remove Arc Data Controller
cleanup_arc_data_controller() {
    log INFO "Cleaning up Azure Arc Data Controller..."
    
    # Check if kubectl context is available
    if ! kubectl cluster-info &> /dev/null; then
        log WARN "kubectl not configured, skipping Arc Data Controller cleanup"
        return 0
    fi
    
    # Check if data controller exists in Azure
    if ! az arcdata dc show --name "$ARC_DC_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Arc Data Controller '$ARC_DC_NAME' not found in Azure, checking Kubernetes..."
        
        # Check if namespace exists in Kubernetes
        if kubectl get namespace "$K8S_NAMESPACE" &> /dev/null; then
            if confirm_deletion "Kubernetes namespace" "$K8S_NAMESPACE"; then
                log INFO "Deleting Kubernetes namespace '$K8S_NAMESPACE'..."
                kubectl delete namespace "$K8S_NAMESPACE" --timeout=300s 2>/dev/null || true
                log SUCCESS "Kubernetes namespace '$K8S_NAMESPACE' deleted"
            fi
        fi
        return 0
    fi
    
    if confirm_deletion "Arc Data Controller" "$ARC_DC_NAME"; then
        log INFO "Deleting Arc Data Controller '$ARC_DC_NAME' (this may take 10-15 minutes)..."
        
        # First try to delete via Azure CLI
        if az arcdata dc delete \
            --name "$ARC_DC_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --namespace "$K8S_NAMESPACE" \
            --force \
            --yes 2>/dev/null; then
            log SUCCESS "Arc Data Controller '$ARC_DC_NAME' deleted via Azure CLI"
        else
            log WARN "Failed to delete Arc Data Controller via Azure CLI, trying Kubernetes cleanup..."
            
            # Fallback to Kubernetes cleanup
            if kubectl get namespace "$K8S_NAMESPACE" &> /dev/null; then
                log INFO "Deleting Kubernetes namespace '$K8S_NAMESPACE'..."
                kubectl delete namespace "$K8S_NAMESPACE" --timeout=600s 2>/dev/null || true
                log SUCCESS "Kubernetes namespace '$K8S_NAMESPACE' deleted"
            fi
        fi
    fi
}

# Remove monitoring resources
cleanup_monitoring() {
    if [[ -z "$WORKSPACE_NAME" ]]; then
        log WARN "Log Analytics workspace name not found, skipping cleanup"
        return 0
    fi
    
    log INFO "Cleaning up monitoring resources..."
    
    # Check if workspace exists
    if ! az monitor log-analytics workspace show --workspace-name "$WORKSPACE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Log Analytics workspace '$WORKSPACE_NAME' not found, skipping"
        return 0
    fi
    
    if confirm_deletion "Log Analytics workspace" "$WORKSPACE_NAME"; then
        # Remove alerts first
        log INFO "Removing monitoring alerts..."
        local alerts
        alerts=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || true)
        
        if [[ -n "$alerts" ]]; then
            while IFS= read -r alert; do
                if [[ -n "$alert" ]]; then
                    log INFO "Deleting alert: $alert"
                    az monitor metrics alert delete \
                        --name "$alert" \
                        --resource-group "$RESOURCE_GROUP" 2>/dev/null || true
                fi
            done <<< "$alerts"
        fi
        
        # Delete Log Analytics workspace
        log INFO "Deleting Log Analytics workspace '$WORKSPACE_NAME'..."
        if az monitor log-analytics workspace delete \
            --workspace-name "$WORKSPACE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes 2>/dev/null; then
            log SUCCESS "Log Analytics workspace '$WORKSPACE_NAME' deleted"
        else
            log WARN "Failed to delete Log Analytics workspace '$WORKSPACE_NAME'"
        fi
    fi
}

# Remove service principals
cleanup_service_principals() {
    log INFO "Cleaning up service principals..."
    
    # Find service principals created for Arc data controller
    local sp_list
    sp_list=$(az ad sp list --display-name "sp-arc-dc-*" --query "[].appId" -o tsv 2>/dev/null || true)
    
    if [[ -n "$sp_list" ]]; then
        while IFS= read -r sp_id; do
            if [[ -n "$sp_id" ]]; then
                if confirm_deletion "Service Principal" "$sp_id"; then
                    log INFO "Deleting service principal: $sp_id"
                    az ad sp delete --id "$sp_id" 2>/dev/null || true
                    log SUCCESS "Service principal '$sp_id' deleted"
                fi
            fi
        done <<< "$sp_list"
    else
        log INFO "No Arc-related service principals found"
    fi
}

# Final resource group cleanup
cleanup_resource_group() {
    log INFO "Checking remaining resources in resource group..."
    
    # List remaining resources
    local remaining_resources
    remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || true)
    
    if [[ -n "$remaining_resources" ]]; then
        log WARN "The following resources still exist in resource group '$RESOURCE_GROUP':"
        while IFS= read -r resource; do
            if [[ -n "$resource" ]]; then
                log WARN "  - $resource"
            fi
        done <<< "$remaining_resources"
        
        echo
        if confirm_deletion "entire resource group (including all remaining resources)" "$RESOURCE_GROUP"; then
            log INFO "Deleting resource group '$RESOURCE_GROUP' and all remaining resources..."
            if az group delete \
                --name "$RESOURCE_GROUP" \
                --yes \
                --no-wait 2>/dev/null; then
                log SUCCESS "Resource group '$RESOURCE_GROUP' deletion initiated (running in background)"
                log INFO "You can check deletion status with: az group show --name $RESOURCE_GROUP"
            else
                log WARN "Failed to delete resource group '$RESOURCE_GROUP'"
            fi
        fi
    else
        log INFO "No resources found in resource group '$RESOURCE_GROUP'"
        
        if confirm_deletion "empty resource group" "$RESOURCE_GROUP"; then
            log INFO "Deleting empty resource group '$RESOURCE_GROUP'..."
            if az group delete \
                --name "$RESOURCE_GROUP" \
                --yes \
                --no-wait 2>/dev/null; then
                log SUCCESS "Empty resource group '$RESOURCE_GROUP' deleted"
            else
                log WARN "Failed to delete resource group '$RESOURCE_GROUP'"
            fi
        fi
    fi
}

# Print cleanup summary
print_summary() {
    log SUCCESS "Cleanup process completed!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo
    echo "Components processed:"
    echo "  ✓ Data Factory pipelines and triggers"
    echo "  ✓ Event Grid topics"
    echo "  ✓ Azure Database for PostgreSQL"
    echo "  ✓ Arc-enabled PostgreSQL instances"
    echo "  ✓ Azure Arc Data Controller"
    echo "  ✓ Monitoring and alerting resources"
    echo "  ✓ Service principals"
    echo "  ✓ Resource group evaluation"
    echo
    echo "Notes:"
    echo "- Some deletions may continue in the background"
    echo "- Check Azure portal to verify all resources are removed"
    echo "- Kubernetes cluster itself was not modified"
    echo "=========================="
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --force                 Skip confirmation prompts"
    echo "  --resource-group NAME   Specify resource group name"
    echo "  --help                  Show this help message"
    echo
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP         Azure resource group name"
    echo "  ARC_DC_NAME           Arc Data Controller name"
    echo "  K8S_NAMESPACE         Kubernetes namespace"
    echo "  POSTGRES_NAME         Arc PostgreSQL instance name"
    echo "  AZURE_PG_NAME         Azure PostgreSQL server name"
    echo "  ADF_NAME              Data Factory name"
    echo "  EVENTGRID_TOPIC       Event Grid topic name"
    echo "  WORKSPACE_NAME        Log Analytics workspace name"
    echo
    echo "Examples:"
    echo "  $0"
    echo "  $0 --force"
    echo "  $0 --resource-group rg-hybrid-postgres-abc123"
    echo "  RESOURCE_GROUP=my-rg $0 --force"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_DELETE=true
                shift
                ;;
            --resource-group)
                export RESOURCE_GROUP="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main cleanup function
main() {
    parse_arguments "$@"
    
    log INFO "Starting hybrid PostgreSQL replication cleanup..."
    log INFO "Cleanup log will be saved to: cleanup_$(date +%Y%m%d_%H%M%S).log"
    
    if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
        echo -e "${YELLOW}WARNING: This will delete Azure resources and may incur costs if not completed properly.${NC}"
        echo "You can set FORCE_DELETE=true or use --force to skip all confirmations."
        echo
    fi
    
    check_prerequisites
    load_environment
    
    # Cleanup in reverse order of creation
    cleanup_data_factory
    cleanup_event_grid
    cleanup_azure_postgresql
    cleanup_arc_postgresql
    cleanup_arc_data_controller
    cleanup_monitoring
    cleanup_service_principals
    cleanup_resource_group
    
    print_summary
    
    log SUCCESS "Cleanup completed successfully at $(date)"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi