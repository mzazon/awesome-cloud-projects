#!/bin/bash

# =============================================================================
# Azure Orbital Edge-to-Orbit Data Processing - Cleanup Script
# =============================================================================
# This script safely removes all Azure resources created by the deployment
# script for the orbital edge-to-orbit data processing solution.
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Global Variables
# =============================================================================

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file setup
LOG_FILE="./cleanup_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Default confirmation settings
FORCE_DELETE=false
SKIP_CONFIRMATION=false
DELETE_RESOURCE_GROUP=true

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

show_help() {
    cat << EOF
Azure Orbital Edge-to-Orbit Data Processing - Cleanup Script

Usage: $0 [OPTIONS]

Options:
    -f, --force                 Force deletion without confirmation prompts
    -s, --skip-confirmation    Skip individual resource confirmations
    -k, --keep-resource-group  Keep the resource group (delete individual resources only)
    -h, --help                 Show this help message

Examples:
    $0                         # Interactive cleanup with confirmations
    $0 --force                 # Force cleanup without prompts
    $0 --keep-resource-group   # Delete resources but keep the resource group
    $0 --skip-confirmation     # Skip confirmations but show resource details

Environment Variables:
    The script will attempt to load environment variables from .env_deployment
    if it exists, or you can set them manually:
    
    RESOURCE_GROUP             # Resource group name
    AZURE_SUBSCRIPTION_ID      # Azure subscription ID
    IOT_HUB_NAME              # IoT Hub name
    EVENT_GRID_TOPIC          # Event Grid topic name
    STORAGE_ACCOUNT           # Storage account name
    FUNCTION_APP_NAME         # Function app name
    SPACECRAFT_NAME           # Spacecraft name
    AZURE_LOCAL_NAME          # Azure Local cluster name
    LOG_ANALYTICS_NAME        # Log Analytics workspace name

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_DELETE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            -s|--skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -k|--keep-resource-group)
                DELETE_RESOURCE_GROUP=false
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
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if kubectl is installed (for Azure Local cleanup)
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl is not installed. Azure Local cleanup will be limited."
    fi
    
    log_success "Prerequisites check completed"
}

load_environment() {
    log_info "Loading environment variables..."
    
    # Try to load from .env_deployment file
    if [[ -f ".env_deployment" ]]; then
        log_info "Loading environment from .env_deployment file..."
        set -a  # Mark all variables for export
        source .env_deployment
        set +a  # Disable auto-export
        log_success "Environment loaded from .env_deployment"
    else
        log_warning ".env_deployment file not found. Using manual environment variables."
    fi
    
    # Validate required environment variables
    local required_vars=(
        "RESOURCE_GROUP"
        "AZURE_SUBSCRIPTION_ID"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable $var is not set"
            log_error "Please set environment variables manually or ensure .env_deployment file exists"
            exit 1
        fi
    done
    
    log_success "Environment variables validated"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Subscription ID: ${AZURE_SUBSCRIPTION_ID}"
}

confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [[ "$SKIP_CONFIRMATION" == true ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}Are you sure you want to delete the $resource_type: $resource_name? (y/N)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        log_info "Skipping deletion of $resource_type: $resource_name"
        return 1
    fi
}

show_resource_summary() {
    log_info "Resource Summary to be deleted:"
    echo "=================================="
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Resource Group: $RESOURCE_GROUP"
        
        # List all resources in the group
        local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Type:type}" --output table)
        if [[ -n "$resources" ]]; then
            echo "$resources"
        else
            log_info "No resources found in resource group"
        fi
    else
        log_warning "Resource group $RESOURCE_GROUP not found"
    fi
    
    echo "=================================="
}

# =============================================================================
# Cleanup Functions
# =============================================================================

cleanup_scheduled_contacts() {
    log_info "Cleaning up scheduled satellite contacts..."
    
    if [[ -z "${SPACECRAFT_NAME:-}" ]]; then
        log_warning "SPACECRAFT_NAME not set, skipping contact cleanup"
        return 0
    fi
    
    # Cancel any scheduled contacts
    local contacts=$(az orbital contact list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?status=='Scheduled'].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$contacts" ]]; then
        while IFS= read -r contact; do
            if [[ -n "$contact" ]]; then
                log_info "Cancelling contact: $contact"
                az orbital contact delete \
                    --name "$contact" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes 2>/dev/null || log_warning "Failed to cancel contact: $contact"
            fi
        done <<< "$contacts"
        log_success "Scheduled contacts cancelled"
    else
        log_info "No scheduled contacts found"
    fi
}

cleanup_azure_local() {
    log_info "Cleaning up Azure Local resources..."
    
    if [[ -z "${AZURE_LOCAL_NAME:-}" ]]; then
        log_warning "AZURE_LOCAL_NAME not set, skipping Azure Local cleanup"
        return 0
    fi
    
    # Remove Kubernetes workloads if kubectl is available
    if command -v kubectl &> /dev/null && [[ -f ~/.kube/azure-local-config ]]; then
        log_info "Removing Kubernetes workloads..."
        kubectl delete deployment satellite-processor -n orbital \
            --kubeconfig ~/.kube/azure-local-config 2>/dev/null || {
            log_warning "Failed to delete Kubernetes deployment (may not exist)"
        }
        
        kubectl delete namespace orbital \
            --kubeconfig ~/.kube/azure-local-config 2>/dev/null || {
            log_warning "Failed to delete orbital namespace (may not exist)"
        }
    fi
    
    # Disconnect Azure Arc if connected
    if az connectedk8s show --name "${AZURE_LOCAL_NAME}-k8s" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if confirm_deletion "Arc-enabled Kubernetes cluster" "${AZURE_LOCAL_NAME}-k8s"; then
            log_info "Disconnecting Arc-enabled Kubernetes..."
            az connectedk8s delete \
                --name "${AZURE_LOCAL_NAME}-k8s" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || log_warning "Failed to disconnect Arc-enabled Kubernetes"
        fi
    fi
    
    # Remove Azure Local cluster resource
    if az stack-hci cluster show --name "$AZURE_LOCAL_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if confirm_deletion "Azure Local cluster" "$AZURE_LOCAL_NAME"; then
            log_info "Removing Azure Local cluster..."
            az stack-hci cluster delete \
                --name "$AZURE_LOCAL_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || log_warning "Failed to delete Azure Local cluster"
        fi
    fi
    
    log_success "Azure Local cleanup completed"
}

cleanup_function_app() {
    log_info "Cleaning up Function App..."
    
    if [[ -z "${FUNCTION_APP_NAME:-}" ]]; then
        log_warning "FUNCTION_APP_NAME not set, skipping Function App cleanup"
        return 0
    fi
    
    if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if confirm_deletion "Function App" "$FUNCTION_APP_NAME"; then
            log_info "Deleting Function App: $FUNCTION_APP_NAME"
            az functionapp delete \
                --name "$FUNCTION_APP_NAME" \
                --resource-group "$RESOURCE_GROUP" 2>/dev/null || {
                log_warning "Failed to delete Function App: $FUNCTION_APP_NAME"
            }
        fi
    else
        log_info "Function App not found: $FUNCTION_APP_NAME"
    fi
    
    log_success "Function App cleanup completed"
}

cleanup_spacecraft() {
    log_info "Cleaning up spacecraft registration..."
    
    if [[ -z "${SPACECRAFT_NAME:-}" ]]; then
        log_warning "SPACECRAFT_NAME not set, skipping spacecraft cleanup"
        return 0
    fi
    
    if az orbital spacecraft show --name "$SPACECRAFT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if confirm_deletion "Spacecraft" "$SPACECRAFT_NAME"; then
            log_info "Deleting spacecraft: $SPACECRAFT_NAME"
            az orbital spacecraft delete \
                --name "$SPACECRAFT_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || {
                log_warning "Failed to delete spacecraft: $SPACECRAFT_NAME"
            }
        fi
    else
        log_info "Spacecraft not found: $SPACECRAFT_NAME"
    fi
    
    # Delete contact profile
    if az orbital contact-profile show --name "earth-obs-profile" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if confirm_deletion "Contact Profile" "earth-obs-profile"; then
            log_info "Deleting contact profile: earth-obs-profile"
            az orbital contact-profile delete \
                --name "earth-obs-profile" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || {
                log_warning "Failed to delete contact profile: earth-obs-profile"
            }
        fi
    else
        log_info "Contact profile not found: earth-obs-profile"
    fi
    
    log_success "Spacecraft cleanup completed"
}

cleanup_iot_hub() {
    log_info "Cleaning up IoT Hub..."
    
    if [[ -z "${IOT_HUB_NAME:-}" ]]; then
        log_warning "IOT_HUB_NAME not set, skipping IoT Hub cleanup"
        return 0
    fi
    
    if az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if confirm_deletion "IoT Hub" "$IOT_HUB_NAME"; then
            log_info "Deleting IoT Hub: $IOT_HUB_NAME"
            az iot hub delete \
                --name "$IOT_HUB_NAME" \
                --resource-group "$RESOURCE_GROUP" 2>/dev/null || {
                log_warning "Failed to delete IoT Hub: $IOT_HUB_NAME"
            }
        fi
    else
        log_info "IoT Hub not found: $IOT_HUB_NAME"
    fi
    
    log_success "IoT Hub cleanup completed"
}

cleanup_event_grid() {
    log_info "Cleaning up Event Grid resources..."
    
    if [[ -z "${EVENT_GRID_TOPIC:-}" ]]; then
        log_warning "EVENT_GRID_TOPIC not set, skipping Event Grid cleanup"
        return 0
    fi
    
    # Delete Event Grid subscriptions first
    log_info "Deleting Event Grid subscriptions..."
    local subscriptions=$(az eventgrid event-subscription list \
        --source-resource-id "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/topics/$EVENT_GRID_TOPIC" \
        --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$subscriptions" ]]; then
        while IFS= read -r subscription; do
            if [[ -n "$subscription" ]]; then
                log_info "Deleting Event Grid subscription: $subscription"
                az eventgrid event-subscription delete \
                    --name "$subscription" \
                    --source-resource-id "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/topics/$EVENT_GRID_TOPIC" \
                    2>/dev/null || log_warning "Failed to delete subscription: $subscription"
            fi
        done <<< "$subscriptions"
    fi
    
    # Delete Event Grid topic
    if az eventgrid topic show --name "$EVENT_GRID_TOPIC" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if confirm_deletion "Event Grid Topic" "$EVENT_GRID_TOPIC"; then
            log_info "Deleting Event Grid topic: $EVENT_GRID_TOPIC"
            az eventgrid topic delete \
                --name "$EVENT_GRID_TOPIC" \
                --resource-group "$RESOURCE_GROUP" 2>/dev/null || {
                log_warning "Failed to delete Event Grid topic: $EVENT_GRID_TOPIC"
            }
        fi
    else
        log_info "Event Grid topic not found: $EVENT_GRID_TOPIC"
    fi
    
    log_success "Event Grid cleanup completed"
}

cleanup_storage_account() {
    log_info "Cleaning up Storage Account..."
    
    if [[ -z "${STORAGE_ACCOUNT:-}" ]]; then
        log_warning "STORAGE_ACCOUNT not set, skipping Storage Account cleanup"
        return 0
    fi
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if confirm_deletion "Storage Account" "$STORAGE_ACCOUNT"; then
            log_info "Deleting Storage Account: $STORAGE_ACCOUNT"
            az storage account delete \
                --name "$STORAGE_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --yes 2>/dev/null || {
                log_warning "Failed to delete Storage Account: $STORAGE_ACCOUNT"
            }
        fi
    else
        log_info "Storage Account not found: $STORAGE_ACCOUNT"
    fi
    
    log_success "Storage Account cleanup completed"
}

cleanup_monitoring() {
    log_info "Cleaning up monitoring resources..."
    
    if [[ -z "${LOG_ANALYTICS_NAME:-}" ]]; then
        log_warning "LOG_ANALYTICS_NAME not set, skipping monitoring cleanup"
        return 0
    fi
    
    # Delete metric alerts
    log_info "Deleting metric alerts..."
    local alerts=$(az monitor metrics alert list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$alerts" ]]; then
        while IFS= read -r alert; do
            if [[ -n "$alert" ]]; then
                log_info "Deleting metric alert: $alert"
                az monitor metrics alert delete \
                    --name "$alert" \
                    --resource-group "$RESOURCE_GROUP" 2>/dev/null || {
                    log_warning "Failed to delete metric alert: $alert"
                }
            fi
        done <<< "$alerts"
    fi
    
    # Delete Log Analytics workspace
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_NAME" &> /dev/null; then
        if confirm_deletion "Log Analytics Workspace" "$LOG_ANALYTICS_NAME"; then
            log_info "Deleting Log Analytics workspace: $LOG_ANALYTICS_NAME"
            az monitor log-analytics workspace delete \
                --resource-group "$RESOURCE_GROUP" \
                --workspace-name "$LOG_ANALYTICS_NAME" \
                --yes 2>/dev/null || {
                log_warning "Failed to delete Log Analytics workspace: $LOG_ANALYTICS_NAME"
            }
        fi
    else
        log_info "Log Analytics workspace not found: $LOG_ANALYTICS_NAME"
    fi
    
    log_success "Monitoring cleanup completed"
}

cleanup_resource_group() {
    if [[ "$DELETE_RESOURCE_GROUP" != true ]]; then
        log_info "Keeping resource group as requested"
        return 0
    fi
    
    log_info "Cleaning up resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        if confirm_deletion "Resource Group" "$RESOURCE_GROUP"; then
            log_info "Deleting resource group: $RESOURCE_GROUP"
            log_warning "This will delete ALL remaining resources in the group"
            
            if [[ "$FORCE_DELETE" == true ]] || [[ "$SKIP_CONFIRMATION" == true ]]; then
                az group delete --name "$RESOURCE_GROUP" --yes --no-wait
                log_success "Resource group deletion initiated: $RESOURCE_GROUP"
                log_info "Complete deletion may take 15-30 minutes"
            else
                echo -e "${RED}Final confirmation: Type 'DELETE' to proceed with resource group deletion:${NC}"
                read -r final_confirmation
                if [[ "$final_confirmation" == "DELETE" ]]; then
                    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
                    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
                    log_info "Complete deletion may take 15-30 minutes"
                else
                    log_info "Resource group deletion cancelled"
                fi
            fi
        fi
    else
        log_info "Resource group not found: $RESOURCE_GROUP"
    fi
}

cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files=(
        "satellite-processor.yaml"
        "dashboard-config.json"
        "test-telemetry.json"
        ".env_deployment"
    )
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing local file: $file"
            rm -f "$file"
        fi
    done
    
    log_success "Local files cleanup completed"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log_info "Starting Azure Orbital Edge-to-Orbit Data Processing cleanup..."
    log_info "Log file: $LOG_FILE"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Execute cleanup steps
    check_prerequisites
    load_environment
    
    # Show what will be deleted
    show_resource_summary
    
    # Final confirmation if not forcing
    if [[ "$FORCE_DELETE" != true ]]; then
        echo -e "${YELLOW}Do you want to proceed with the cleanup? (y/N)${NC}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup in reverse order of creation
    cleanup_scheduled_contacts
    cleanup_azure_local
    cleanup_function_app
    cleanup_spacecraft
    cleanup_iot_hub
    cleanup_event_grid
    cleanup_storage_account
    cleanup_monitoring
    cleanup_resource_group
    cleanup_local_files
    
    log_success "Cleanup completed successfully!"
    log_info "Check Azure portal to verify all resources have been removed"
    log_info "Cleanup log saved to: $LOG_FILE"
    
    if [[ "$DELETE_RESOURCE_GROUP" == true ]]; then
        log_info "Resource group deletion is running in the background"
        log_info "You can check the status in the Azure portal"
    fi
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi