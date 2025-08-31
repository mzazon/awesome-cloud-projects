#!/bin/bash

###################################################################################
# Destroy Script for Intelligent Model Selection with Model Router and Event Grid
# Recipe: intelligent-model-selection-router-event-grid
# Provider: Azure
# Description: Safely removes all resources created for the AI orchestration system
###################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CONFIG_FILE="${SCRIPT_DIR}/deployment.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line $line_number with exit code $exit_code"
    log_error "Check the log file: $LOG_FILE"
    exit $exit_code
}

trap 'handle_error $LINENO' ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load deployment configuration
load_deployment_config() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warning "Deployment configuration file not found: $CONFIG_FILE"
        log_info "Will attempt to discover resources using user input..."
        
        # Prompt for resource group name
        echo -n "Enter the resource group name to delete: "
        read -r RESOURCE_GROUP
        
        if [[ -z "$RESOURCE_GROUP" ]]; then
            log_error "Resource group name is required"
            exit 1
        fi
        
        # Verify resource group exists
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_error "Resource group '$RESOURCE_GROUP' not found"
            exit 1
        fi
        
        export RESOURCE_GROUP
        return
    fi
    
    # Source the configuration file
    set -a  # Automatically export all variables
    source "$CONFIG_FILE"
    set +a
    
    log_success "Deployment configuration loaded"
    log_info "Resource Group: ${RESOURCE_GROUP:-Not set}"
    log_info "Location: ${LOCATION:-Not set}"
    log_info "Random Suffix: ${RANDOM_SUFFIX:-Not set}"
}

# Confirm destruction
confirm_destruction() {
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    log_warning "This will permanently delete the following resources:"
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_warning "  • Resource Group: $RESOURCE_GROUP"
        
        # List resources in the group
        log_info "Resources to be deleted:"
        if az resource list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null; then
            :  # Table output already printed
        else
            log_warning "Unable to list resources in resource group"
        fi
    fi
    
    echo
    log_warning "This action cannot be undone!"
    echo
    
    # Interactive confirmation unless --force flag is used
    if [[ "${1:-}" != "--force" ]]; then
        echo -n "Type 'DELETE' to confirm destruction: "
        read -r confirmation
        
        if [[ "$confirmation" != "DELETE" ]]; then
            log_info "Destruction cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Destruction confirmed. Proceeding..."
}

# Stop Function App to prevent new requests
stop_function_app() {
    if [[ -n "${FUNCTION_APP:-}" ]]; then
        log_info "Stopping Function App: $FUNCTION_APP"
        
        if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az functionapp stop \
                --name "$FUNCTION_APP" \
                --resource-group "$RESOURCE_GROUP" \
                --output none 2>/dev/null || log_warning "Failed to stop Function App"
            
            log_success "Function App stopped"
        else
            log_warning "Function App not found: $FUNCTION_APP"
        fi
    fi
}

# Remove Event Grid subscriptions
remove_event_grid_subscriptions() {
    if [[ -n "${EVENT_GRID_TOPIC:-}" && -n "${SUBSCRIPTION_ID:-}" ]]; then
        log_info "Removing Event Grid subscriptions..."
        
        local topic_resource_id="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/topics/$EVENT_GRID_TOPIC"
        
        # List and delete all subscriptions for the topic
        local subscriptions
        subscriptions=$(az eventgrid event-subscription list \
            --source-resource-id "$topic_resource_id" \
            --query "[].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$subscriptions" ]]; then
            while IFS= read -r subscription_name; do
                if [[ -n "$subscription_name" ]]; then
                    log_info "Deleting Event Grid subscription: $subscription_name"
                    az eventgrid event-subscription delete \
                        --name "$subscription_name" \
                        --source-resource-id "$topic_resource_id" \
                        --output none 2>/dev/null || log_warning "Failed to delete subscription: $subscription_name"
                fi
            done <<< "$subscriptions"
            
            log_success "Event Grid subscriptions removed"
        else
            log_info "No Event Grid subscriptions found"
        fi
    fi
}

# Remove AI model deployments
remove_ai_deployments() {
    if [[ -n "${AI_FOUNDRY_RESOURCE:-}" ]]; then
        log_info "Removing AI model deployments..."
        
        if az cognitiveservices account show --name "$AI_FOUNDRY_RESOURCE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            # List and delete all deployments
            local deployments
            deployments=$(az cognitiveservices account deployment list \
                --name "$AI_FOUNDRY_RESOURCE" \
                --resource-group "$RESOURCE_GROUP" \
                --query "[].name" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "$deployments" ]]; then
                while IFS= read -r deployment_name; do
                    if [[ -n "$deployment_name" ]]; then
                        log_info "Deleting AI deployment: $deployment_name"
                        az cognitiveservices account deployment delete \
                            --name "$AI_FOUNDRY_RESOURCE" \
                            --resource-group "$RESOURCE_GROUP" \
                            --deployment-name "$deployment_name" \
                            --output none 2>/dev/null || log_warning "Failed to delete deployment: $deployment_name"
                    fi
                done <<< "$deployments"
                
                log_success "AI model deployments removed"
            else
                log_info "No AI model deployments found"
            fi
        else
            log_warning "AI Foundry resource not found: $AI_FOUNDRY_RESOURCE"
        fi
    fi
}

# Wait for deployments to be fully deleted
wait_for_deployment_deletion() {
    if [[ -n "${AI_FOUNDRY_RESOURCE:-}" ]]; then
        log_info "Waiting for AI deployments to be fully deleted..."
        
        local max_attempts=30
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            local deployment_count
            deployment_count=$(az cognitiveservices account deployment list \
                --name "$AI_FOUNDRY_RESOURCE" \
                --resource-group "$RESOURCE_GROUP" \
                --query "length([*])" \
                --output tsv 2>/dev/null || echo "0")
            
            if [[ "$deployment_count" -eq 0 ]]; then
                log_success "All AI deployments have been deleted"
                break
            fi
            
            log_info "Waiting for deployments to be deleted (attempt $attempt/$max_attempts)..."
            sleep 10
            ((attempt++))
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            log_warning "Timeout waiting for AI deployments to be deleted"
        fi
    fi
}

# Remove individual resources (fallback if resource group deletion fails)
remove_individual_resources() {
    log_info "Removing individual resources as fallback..."
    
    # Remove Function App
    if [[ -n "${FUNCTION_APP:-}" ]]; then
        log_info "Deleting Function App: $FUNCTION_APP"
        az functionapp delete \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --output none 2>/dev/null || log_warning "Failed to delete Function App"
    fi
    
    # Remove Event Grid Topic
    if [[ -n "${EVENT_GRID_TOPIC:-}" ]]; then
        log_info "Deleting Event Grid Topic: $EVENT_GRID_TOPIC"
        az eventgrid topic delete \
            --name "$EVENT_GRID_TOPIC" \
            --resource-group "$RESOURCE_GROUP" \
            --output none 2>/dev/null || log_warning "Failed to delete Event Grid Topic"
    fi
    
    # Remove AI Foundry Resource
    if [[ -n "${AI_FOUNDRY_RESOURCE:-}" ]]; then
        log_info "Deleting AI Foundry Resource: $AI_FOUNDRY_RESOURCE"
        az cognitiveservices account delete \
            --name "$AI_FOUNDRY_RESOURCE" \
            --resource-group "$RESOURCE_GROUP" \
            --output none 2>/dev/null || log_warning "Failed to delete AI Foundry Resource"
    fi
    
    # Remove Application Insights
    if [[ -n "${APP_INSIGHTS:-}" ]]; then
        log_info "Deleting Application Insights: $APP_INSIGHTS"
        az monitor app-insights component delete \
            --app "$APP_INSIGHTS" \
            --resource-group "$RESOURCE_GROUP" \
            --output none 2>/dev/null || log_warning "Failed to delete Application Insights"
    fi
    
    # Remove Storage Account
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        log_info "Deleting Storage Account: $STORAGE_ACCOUNT"
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none 2>/dev/null || log_warning "Failed to delete Storage Account"
    fi
    
    log_success "Individual resource deletion completed"
}

# Remove resource group and all resources
remove_resource_group() {
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_info "Deleting resource group: $RESOURCE_GROUP"
        
        # Check if resource group exists
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_warning "Resource group '$RESOURCE_GROUP' not found"
            return
        fi
        
        # Attempt to delete the entire resource group
        if az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none 2>/dev/null; then
            
            log_success "Resource group deletion initiated: $RESOURCE_GROUP"
            log_info "Deletion is running in the background and may take several minutes to complete"
            
            # Optionally wait for deletion to complete
            if [[ "${WAIT_FOR_COMPLETION:-}" == "true" ]]; then
                log_info "Waiting for resource group deletion to complete..."
                
                local max_attempts=60
                local attempt=1
                
                while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
                    if [[ $attempt -ge $max_attempts ]]; then
                        log_warning "Resource group deletion is still in progress after waiting"
                        break
                    fi
                    
                    log_info "Waiting for resource group deletion (attempt $attempt/$max_attempts)..."
                    sleep 30
                    ((attempt++))
                done
                
                if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
                    log_success "Resource group has been completely deleted"
                fi
            fi
        else
            log_error "Failed to initiate resource group deletion"
            log_info "Attempting to delete individual resources..."
            remove_individual_resources
        fi
    else
        log_error "Resource group name not found in configuration"
        exit 1
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove temporary files
    local files_to_remove=(
        "${SCRIPT_DIR}/function_code"
        "${SCRIPT_DIR}/function.zip"
        "${SCRIPT_DIR}/deployment.env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            rm -rf "$file" 2>/dev/null || log_warning "Failed to remove: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Verify destruction
verify_destruction() {
    log_info "Verifying resource destruction..."
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_warning "Resource group still exists (deletion may be in progress): $RESOURCE_GROUP"
            log_info "Check Azure portal for deletion status"
        else
            log_success "Resource group has been deleted: $RESOURCE_GROUP"
        fi
    fi
    
    log_success "Destruction verification completed"
}

# Generate destruction report
generate_report() {
    local report_file="${SCRIPT_DIR}/destruction_report.txt"
    
    cat > "$report_file" << EOF
=== DESTRUCTION REPORT ===
Generated: $(date)
Script: $(basename "$0")

Resources Destroyed:
$(if [[ -n "${RESOURCE_GROUP:-}" ]]; then echo "- Resource Group: $RESOURCE_GROUP"; fi)
$(if [[ -n "${FUNCTION_APP:-}" ]]; then echo "- Function App: $FUNCTION_APP"; fi)
$(if [[ -n "${EVENT_GRID_TOPIC:-}" ]]; then echo "- Event Grid Topic: $EVENT_GRID_TOPIC"; fi)
$(if [[ -n "${AI_FOUNDRY_RESOURCE:-}" ]]; then echo "- AI Foundry Resource: $AI_FOUNDRY_RESOURCE"; fi)
$(if [[ -n "${APP_INSIGHTS:-}" ]]; then echo "- Application Insights: $APP_INSIGHTS"; fi)
$(if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then echo "- Storage Account: $STORAGE_ACCOUNT"; fi)

Status: Completed
Log File: $LOG_FILE

Note: Resource group deletion may continue in the background.
Check the Azure portal to confirm complete removal.
EOF
    
    log_success "Destruction report generated: $report_file"
}

# Main destruction function
main() {
    local force_flag="${1:-}"
    
    log_info "Starting destruction of Intelligent Model Selection with Model Router and Event Grid"
    log_info "Script started at: $(date)"
    
    check_prerequisites
    load_deployment_config
    confirm_destruction "$force_flag"
    
    # Graceful shutdown sequence
    stop_function_app
    remove_event_grid_subscriptions
    remove_ai_deployments
    wait_for_deployment_deletion
    
    # Complete resource removal
    remove_resource_group
    
    # Cleanup and verification
    cleanup_local_files
    verify_destruction
    generate_report
    
    log_success "=== DESTRUCTION COMPLETED ==="
    log_info "All resources have been scheduled for deletion"
    log_info "Resource group deletion may take several minutes to complete"
    log_info "Check the Azure portal to confirm complete removal"
    log_info "Log file: $LOG_FILE"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--force] [--wait] [--help]"
        echo ""
        echo "Destroy Intelligent Model Selection with Model Router and Event Grid"
        echo ""
        echo "Options:"
        echo "  --force    Skip confirmation prompts"
        echo "  --wait     Wait for resource group deletion to complete"
        echo "  --help     Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0                    # Interactive destruction with confirmations"
        echo "  $0 --force           # Force destruction without confirmations"
        echo "  $0 --wait            # Wait for complete resource deletion"
        echo "  WAIT_FOR_COMPLETION=true $0 --force  # Force and wait"
        exit 0
        ;;
    --wait)
        export WAIT_FOR_COMPLETION=true
        main
        ;;
    --force)
        main --force
        ;;
    *)
        main "$@"
        ;;
esac