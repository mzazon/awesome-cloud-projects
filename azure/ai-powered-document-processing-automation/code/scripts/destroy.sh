#!/bin/bash

# Destroy script for Orchestrating Intelligent Business Process Automation 
# with Azure OpenAI Assistants and Azure Container Apps Jobs
# 
# This script safely removes all resources created for the intelligent business
# process automation solution

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$ERROR_LOG" >&2
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling (non-fatal for cleanup script)
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_warning "Non-fatal error occurred at line $line_number (exit code: $exit_code)"
    log_warning "Continuing with cleanup process..."
}

trap 'handle_error $? $LINENO' ERR

# Load environment variables
load_environment() {
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        log_info "Loading environment variables from .env file..."
        # shellcheck source=/dev/null
        source "${SCRIPT_DIR}/.env"
        log_success "Environment variables loaded"
    else
        log_warning ".env file not found. Using default values or prompting for input."
        
        # Prompt for resource group if not set
        if [[ -z "${RESOURCE_GROUP:-}" ]]; then
            echo -n "Enter resource group name: "
            read -r RESOURCE_GROUP
            export RESOURCE_GROUP
        fi
        
        # Set other variables if available
        export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv 2>/dev/null || echo '')}"
    fi
}

# Prerequisites checking
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if resource group exists
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_warning "Resource group '$RESOURCE_GROUP' not found. May have been already deleted."
            return 0
        fi
    else
        log_error "Resource group name not specified. Cannot proceed."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Confirmation prompt
confirm_deletion() {
    echo -e "${RED}⚠️  WARNING: This will permanently delete all resources!${NC}"
    echo -e "${YELLOW}Resources to be deleted:${NC}"
    echo "  • Resource Group: ${RESOURCE_GROUP:-'Not specified'}"
    echo "  • All contained resources including:"
    echo "    - Azure OpenAI Service and models"
    echo "    - Service Bus namespace, queues, and topics"
    echo "    - Container Apps environment and jobs"
    echo "    - Container Registry and images"
    echo "    - Log Analytics workspace and monitoring"
    echo ""
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log_warning "Force delete enabled. Skipping confirmation."
        return 0
    fi
    
    echo -n "Are you sure you want to proceed? (type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "User confirmed deletion. Proceeding with cleanup..."
}

# Remove Container Apps Jobs
cleanup_container_jobs() {
    log_info "Removing Container Apps Jobs..."
    
    if [[ -z "${CONTAINER_ENV:-}" ]]; then
        log_warning "Container environment name not available. Skipping Container Apps cleanup."
        return 0
    fi
    
    # List and delete Container Apps Jobs
    local jobs
    jobs=$(az containerapp job list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$jobs" ]]; then
        for job in $jobs; do
            log_info "Deleting Container Apps Job: $job"
            az containerapp job delete \
                --name "$job" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none 2>/dev/null || log_warning "Failed to delete job: $job"
        done
        log_success "Container Apps Jobs cleanup completed"
    else
        log_info "No Container Apps Jobs found to delete"
    fi
    
    # Delete Container Apps environment
    if [[ -n "$CONTAINER_ENV" ]]; then
        log_info "Deleting Container Apps environment: $CONTAINER_ENV"
        az containerapp env delete \
            --name "$CONTAINER_ENV" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none 2>/dev/null || log_warning "Failed to delete Container Apps environment"
        
        log_success "Container Apps environment deleted"
    fi
}

# Remove Service Bus resources
cleanup_service_bus() {
    log_info "Removing Service Bus resources..."
    
    if [[ -z "${SERVICEBUS_NAMESPACE:-}" ]]; then
        log_warning "Service Bus namespace name not available. Skipping Service Bus cleanup."
        return 0
    fi
    
    # Delete Service Bus namespace (this removes all contained resources)
    log_info "Deleting Service Bus namespace: $SERVICEBUS_NAMESPACE"
    az servicebus namespace delete \
        --name "$SERVICEBUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --output none 2>/dev/null || log_warning "Failed to delete Service Bus namespace"
    
    log_success "Service Bus resources deleted"
}

# Remove Azure OpenAI resources
cleanup_openai_service() {
    log_info "Removing Azure OpenAI Service..."
    
    if [[ -z "${OPENAI_ACCOUNT_NAME:-}" ]]; then
        log_warning "OpenAI account name not available. Skipping OpenAI cleanup."
        return 0
    fi
    
    # Delete OpenAI Assistant (if ID is available)
    if [[ -f "${SCRIPT_DIR}/assistant_id.txt" ]]; then
        local assistant_id
        assistant_id=$(cat "${SCRIPT_DIR}/assistant_id.txt")
        
        if [[ -n "$assistant_id" && -n "${OPENAI_ENDPOINT:-}" && -n "${OPENAI_KEY:-}" ]]; then
            log_info "Attempting to delete OpenAI Assistant: $assistant_id"
            curl -X DELETE \
                "${OPENAI_ENDPOINT}/openai/assistants/${assistant_id}?api-version=2024-02-15-preview" \
                -H "api-key: ${OPENAI_KEY}" \
                --silent || log_warning "Failed to delete OpenAI Assistant"
        fi
        
        # Remove assistant ID file
        rm -f "${SCRIPT_DIR}/assistant_id.txt"
    fi
    
    # Delete Azure OpenAI account
    log_info "Deleting Azure OpenAI account: $OPENAI_ACCOUNT_NAME"
    az cognitiveservices account delete \
        --name "$OPENAI_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output none 2>/dev/null || log_warning "Failed to delete OpenAI account"
    
    log_success "Azure OpenAI Service deleted"
}

# Remove Container Registry
cleanup_container_registry() {
    log_info "Removing Container Registry..."
    
    if [[ -z "${CONTAINER_REGISTRY:-}" ]]; then
        log_warning "Container Registry name not available. Skipping ACR cleanup."
        return 0
    fi
    
    log_info "Deleting Container Registry: $CONTAINER_REGISTRY"
    az acr delete \
        --name "$CONTAINER_REGISTRY" \
        --resource-group "$RESOURCE_GROUP" \
        --yes \
        --output none 2>/dev/null || log_warning "Failed to delete Container Registry"
    
    log_success "Container Registry deleted"
}

# Remove monitoring resources
cleanup_monitoring() {
    log_info "Removing monitoring resources..."
    
    # Delete Application Insights
    if [[ -n "${OPENAI_ACCOUNT_NAME:-}" ]]; then
        local app_insights_name="${OPENAI_ACCOUNT_NAME}-insights"
        log_info "Deleting Application Insights: $app_insights_name"
        az monitor app-insights component delete \
            --app "$app_insights_name" \
            --resource-group "$RESOURCE_GROUP" \
            --output none 2>/dev/null || log_warning "Failed to delete Application Insights"
    fi
    
    # Delete metric alerts
    local alerts
    alerts=$(az monitor metrics alert list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$alerts" ]]; then
        for alert in $alerts; do
            log_info "Deleting metric alert: $alert"
            az monitor metrics alert delete \
                --name "$alert" \
                --resource-group "$RESOURCE_GROUP" \
                --output none 2>/dev/null || log_warning "Failed to delete alert: $alert"
        done
    fi
    
    # Delete Log Analytics workspace
    if [[ -n "${LOG_ANALYTICS_WORKSPACE:-}" ]]; then
        log_info "Deleting Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
        az monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --force true \
            --yes \
            --output none 2>/dev/null || log_warning "Failed to delete Log Analytics workspace"
    fi
    
    log_success "Monitoring resources cleanup completed"
}

# Remove resource group (final cleanup)
cleanup_resource_group() {
    log_info "Performing final resource group cleanup..."
    
    # Check if resource group still exists and has remaining resources
    local remaining_resources
    remaining_resources=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "length(@)" \
        --output tsv 2>/dev/null || echo "0")
    
    if [[ "$remaining_resources" -gt 0 ]]; then
        log_warning "Found $remaining_resources remaining resources in resource group"
        log_info "Listing remaining resources:"
        az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].{Name:name, Type:type}" \
            --output table 2>/dev/null || true
    fi
    
    # Delete resource group and all remaining resources
    log_info "Deleting resource group: $RESOURCE_GROUP"
    echo -e "${YELLOW}This may take several minutes...${NC}"
    
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none 2>/dev/null || log_warning "Failed to initiate resource group deletion"
    
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log_info "Note: Complete deletion may take several minutes to complete in the background"
}

# Cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        rm -f "${SCRIPT_DIR}/.env"
        log_success "Environment file removed"
    fi
    
    # Remove assistant creation script
    if [[ -f "${SCRIPT_DIR}/create_assistant.py" ]]; then
        rm -f "${SCRIPT_DIR}/create_assistant.py"
        log_success "Assistant creation script removed"
    fi
    
    # Remove assistant ID file
    if [[ -f "${SCRIPT_DIR}/assistant_id.txt" ]]; then
        rm -f "${SCRIPT_DIR}/assistant_id.txt"
        log_success "Assistant ID file removed"
    fi
    
    log_success "Local files cleanup completed"
}

# Verification function
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group still exists. Deletion may be in progress."
        
        # List any remaining resources
        local remaining_count
        remaining_count=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "length(@)" \
            --output tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_count" -gt 0 ]]; then
            log_warning "$remaining_count resources still remain in the resource group"
            log_info "This is normal as deletion operations may take time to complete"
        fi
    else
        log_success "Resource group has been successfully deleted"
    fi
    
    # Check for any remaining local files
    local local_files=(".env" "create_assistant.py" "assistant_id.txt")
    local remaining_files=()
    
    for file in "${local_files[@]}"; do
        if [[ -f "${SCRIPT_DIR}/$file" ]]; then
            remaining_files+=("$file")
        fi
    done
    
    if [[ ${#remaining_files[@]} -eq 0 ]]; then
        log_success "All local files cleaned up successfully"
    else
        log_warning "Some local files remain: ${remaining_files[*]}"
    fi
}

# Main cleanup function
main() {
    echo -e "${BLUE}🧹 Starting cleanup of Intelligent Business Process Automation${NC}"
    echo "============================================================================="
    
    # Initialize log files
    > "$LOG_FILE"
    > "$ERROR_LOG"
    
    log_info "Cleanup started at $(date)"
    
    # Execute cleanup steps
    load_environment
    check_prerequisites
    confirm_deletion
    
    # Remove resources in reverse order of creation
    cleanup_container_jobs
    cleanup_service_bus
    cleanup_openai_service
    cleanup_container_registry
    cleanup_monitoring
    cleanup_resource_group
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    echo "============================================================================="
    log_success "Cleanup process completed!"
    echo -e "${GREEN}✅ All resources have been scheduled for deletion${NC}"
    echo ""
    echo -e "${BLUE}📋 Cleanup Summary:${NC}"
    echo "  • Resource Group: $RESOURCE_GROUP (deletion initiated)"
    echo "  • Local files cleaned up"
    echo ""
    echo -e "${BLUE}📊 View cleanup logs at: $LOG_FILE${NC}"
    echo ""
    echo -e "${YELLOW}ℹ️  Note: Azure resource deletion may take several minutes to complete.${NC}"
    echo -e "${YELLOW}   You can check the Azure portal to confirm all resources are removed.${NC}"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DELETE="true"
            log_info "Force delete mode enabled"
            shift
            ;;
        --resource-group)
            export RESOURCE_GROUP="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force                Skip confirmation prompt"
            echo "  --resource-group NAME  Specify resource group name"
            echo "  --help                 Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Interactive cleanup"
            echo "  $0 --force                           # Skip confirmation"
            echo "  $0 --resource-group my-rg            # Specify resource group"
            echo "  $0 --force --resource-group my-rg    # Force delete specific group"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"