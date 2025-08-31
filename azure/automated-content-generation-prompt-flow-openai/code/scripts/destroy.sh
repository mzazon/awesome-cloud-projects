#!/bin/bash

# Destroy script for Automated Content Generation with Prompt Flow and OpenAI
# This script safely removes all infrastructure created by the deploy.sh script
# with proper confirmation, error handling, and comprehensive logging

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    log_info "Some resources may still exist. Please check the Azure portal."
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites check
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
    
    log_success "Prerequisites check completed"
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ ! -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        log_warning "Deployment state file not found. Using environment variables or defaults."
        return 0
    fi
    
    # Source the state file to load variables
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z "$key" ]] && continue
        
        # Export the variable
        export "$key"="$value"
        log_info "Loaded: $key=$value"
    done < "${DEPLOYMENT_STATE_FILE}"
    
    log_success "Deployment state loaded"
}

# Set variables from state or environment
set_variables() {
    log_info "Setting up cleanup variables..."
    
    # Use variables from state file or environment, with fallbacks
    export RESOURCE_GROUP="${RESOURCE_GROUP:-}"
    export LOCATION="${LOCATION:-eastus}"
    export RANDOM_SUFFIX="${RANDOM_SUFFIX:-}"
    
    # If we have a suffix, construct resource names
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        export ML_WORKSPACE_NAME="${ML_WORKSPACE_NAME:-ml-contentgen-${RANDOM_SUFFIX}}"
        export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-storcontentgen${RANDOM_SUFFIX}}"
        export OPENAI_ACCOUNT_NAME="${OPENAI_ACCOUNT_NAME:-aoai-contentgen-${RANDOM_SUFFIX}}"
        export FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-contentgen-${RANDOM_SUFFIX}}"
        export COSMOS_ACCOUNT_NAME="${COSMOS_ACCOUNT_NAME:-cosmos-contentgen-${RANDOM_SUFFIX}}"
    fi
    
    # Validate required variables
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        log_error "RESOURCE_GROUP not set. Please provide it via environment variable or --resource-group flag."
        exit 1
    fi
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        log_info "Random Suffix: ${RANDOM_SUFFIX}"
    fi
}

# Confirm destruction
confirm_destruction() {
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This will permanently delete the following resources:"
    echo "  - Resource Group: ${RESOURCE_GROUP}"
    
    if [[ -n "${ML_WORKSPACE_NAME:-}" ]]; then
        echo "  - ML Workspace: ${ML_WORKSPACE_NAME}"
    fi
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        echo "  - Storage Account: ${STORAGE_ACCOUNT_NAME} (and all data)"
    fi
    if [[ -n "${OPENAI_ACCOUNT_NAME:-}" ]]; then
        echo "  - OpenAI Service: ${OPENAI_ACCOUNT_NAME}"
    fi
    if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
        echo "  - Function App: ${FUNCTION_APP_NAME}"
    fi
    if [[ -n "${COSMOS_ACCOUNT_NAME:-}" ]]; then
        echo "  - Cosmos DB: ${COSMOS_ACCOUNT_NAME} (and all data)"
    fi
    
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
        echo "Type 'DELETE' to confirm destruction:"
        read -r confirmation
        if [[ "$confirmation" != "DELETE" ]]; then
            log_info "Destruction cancelled by user"
            exit 0
        fi
    fi
    
    log_warning "Proceeding with resource destruction..."
}

# Check if resource group exists
check_resource_group() {
    log_info "Checking if resource group exists..."
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group '${RESOURCE_GROUP}' does not exist or is not accessible"
        return 1
    fi
    
    log_info "Resource group '${RESOURCE_GROUP}' found"
    return 0
}

# List resources in the resource group
list_resources() {
    log_info "Listing resources in resource group..."
    
    local resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table 2>/dev/null || echo "")
    
    if [[ -n "$resources" ]]; then
        echo "Resources found in ${RESOURCE_GROUP}:"
        echo "$resources"
        echo ""
    else
        log_info "No resources found in resource group"
    fi
}

# Remove OpenAI model deployments
remove_openai_deployments() {
    if [[ -z "${OPENAI_ACCOUNT_NAME:-}" ]]; then
        log_info "OpenAI account name not set, skipping deployment deletion"
        return 0
    fi
    
    log_info "Removing OpenAI model deployments..."
    
    # Check if OpenAI account exists
    if ! az cognitiveservices account show --name "${OPENAI_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "OpenAI account '${OPENAI_ACCOUNT_NAME}' not found, skipping"
        return 0
    fi
    
    # Remove GPT-4o deployment
    if az cognitiveservices account deployment show \
        --name "${OPENAI_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name gpt-4o-content &> /dev/null; then
        
        log_info "Deleting GPT-4o deployment..."
        az cognitiveservices account deployment delete \
            --name "${OPENAI_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --deployment-name gpt-4o-content \
            --output none
        
        log_success "GPT-4o deployment deleted"
    else
        log_info "GPT-4o deployment not found, skipping"
    fi
    
    # Remove text embedding deployment
    if az cognitiveservices account deployment show \
        --name "${OPENAI_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name text-embedding-ada-002 &> /dev/null; then
        
        log_info "Deleting text embedding deployment..."
        az cognitiveservices account deployment delete \
            --name "${OPENAI_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --deployment-name text-embedding-ada-002 \
            --output none
        
        log_success "Text embedding deployment deleted"
    else
        log_info "Text embedding deployment not found, skipping"
    fi
    
    # Wait for deployments to be fully deleted
    log_info "Waiting for deployments to be fully removed..."
    sleep 30
}

# Remove individual resources (if not deleting entire resource group)
remove_individual_resources() {
    log_info "Removing individual resources..."
    
    # Remove Function App
    if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
        if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_info "Deleting Function App: ${FUNCTION_APP_NAME}"
            az functionapp delete \
                --name "${FUNCTION_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output none
            log_success "Function App deleted: ${FUNCTION_APP_NAME}"
        else
            log_info "Function App '${FUNCTION_APP_NAME}' not found, skipping"
        fi
    fi
    
    # Remove Cosmos DB
    if [[ -n "${COSMOS_ACCOUNT_NAME:-}" ]]; then
        if az cosmosdb show --name "${COSMOS_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_info "Deleting Cosmos DB: ${COSMOS_ACCOUNT_NAME}"
            az cosmosdb delete \
                --name "${COSMOS_ACCOUNT_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            log_success "Cosmos DB deleted: ${COSMOS_ACCOUNT_NAME}"
        else
            log_info "Cosmos DB '${COSMOS_ACCOUNT_NAME}' not found, skipping"
        fi
    fi
    
    # Remove OpenAI Service (after deployments are removed)
    if [[ -n "${OPENAI_ACCOUNT_NAME:-}" ]]; then
        if az cognitiveservices account show --name "${OPENAI_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_info "Deleting OpenAI Service: ${OPENAI_ACCOUNT_NAME}"
            az cognitiveservices account delete \
                --name "${OPENAI_ACCOUNT_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output none
            log_success "OpenAI Service deleted: ${OPENAI_ACCOUNT_NAME}"
        else
            log_info "OpenAI Service '${OPENAI_ACCOUNT_NAME}' not found, skipping"
        fi
    fi
    
    # Remove ML Workspace
    if [[ -n "${ML_WORKSPACE_NAME:-}" ]]; then
        # Check if ML extension is installed
        if ! az extension show --name ml &> /dev/null; then
            log_info "Installing Azure ML CLI extension for cleanup..."
            az extension add --name ml --yes
        fi
        
        if az ml workspace show --name "${ML_WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_info "Deleting ML Workspace: ${ML_WORKSPACE_NAME}"
            az ml workspace delete \
                --name "${ML_WORKSPACE_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            log_success "ML Workspace deleted: ${ML_WORKSPACE_NAME}"
        else
            log_info "ML Workspace '${ML_WORKSPACE_NAME}' not found, skipping"
        fi
    fi
    
    # Remove Storage Account
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_info "Deleting Storage Account: ${STORAGE_ACCOUNT_NAME}"
            az storage account delete \
                --name "${STORAGE_ACCOUNT_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            log_success "Storage Account deleted: ${STORAGE_ACCOUNT_NAME}"
        else
            log_info "Storage Account '${STORAGE_ACCOUNT_NAME}' not found, skipping"
        fi
    fi
}

# Remove resource group and all resources
remove_resource_group() {
    log_info "Deleting resource group and all resources..."
    
    # Remove OpenAI deployments first (they need special handling)
    remove_openai_deployments
    
    # Delete the entire resource group
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        --output none
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Deletion is running in the background and may take several minutes to complete"
}

# Wait for resource group deletion
wait_for_deletion() {
    if [[ "${WAIT_FOR_COMPLETION:-true}" != "true" ]]; then
        log_info "Skipping wait for deletion completion"
        return 0
    fi
    
    log_info "Waiting for resource group deletion to complete..."
    
    local max_attempts=60  # 30 minutes maximum
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            log_success "Resource group '${RESOURCE_GROUP}' has been deleted"
            return 0
        fi
        
        ((attempt++))
        log_info "Waiting... (attempt $attempt/$max_attempts)"
        sleep 30
    done
    
    log_warning "Resource group deletion is taking longer than expected"
    log_info "Check the Azure portal for current status"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment state file
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        rm -f "${DEPLOYMENT_STATE_FILE}"
        log_success "Deployment state file removed"
    fi
    
    # Remove generated directories
    local dirs_to_remove=(
        "${SCRIPT_DIR}/content-generation-flow"
        "${SCRIPT_DIR}/function-app"
    )
    
    for dir in "${dirs_to_remove[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            log_success "Removed directory: $dir"
        fi
    done
    
    # Remove temporary files
    local files_to_remove=(
        "${SCRIPT_DIR}/aoai-connection.yaml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed file: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Display destruction summary
display_summary() {
    log_success "Cleanup completed!"
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo ""
    
    if [[ "${DELETE_RESOURCE_GROUP:-true}" == "true" ]]; then
        echo "✅ Resource group and all resources deleted"
        echo "✅ OpenAI model deployments removed"
        echo "✅ All associated data deleted"
    else
        echo "✅ Individual resources removed"
        echo "✅ OpenAI model deployments removed"
        echo "ℹ️  Resource group preserved"
    fi
    
    echo "✅ Local files cleaned up"
    echo ""
    
    if [[ "${WAIT_FOR_COMPLETION:-true}" == "true" ]]; then
        echo "All cleanup operations completed successfully."
    else
        echo "Cleanup operations initiated. Check Azure portal for final status."
    fi
    
    echo ""
    echo "Note: It may take a few minutes for all resources to be fully removed from the Azure portal."
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Automated Content Generation system"
    
    # Initialize
    check_prerequisites
    load_deployment_state
    set_variables
    confirm_destruction
    
    # Check if resource group exists
    if ! check_resource_group; then
        log_info "Resource group does not exist, cleaning up local files only"
        cleanup_local_files
        log_success "Cleanup completed (no resources to delete)"
        return 0
    fi
    
    # Show what will be deleted
    list_resources
    
    # Perform cleanup
    if [[ "${DELETE_RESOURCE_GROUP:-true}" == "true" ]]; then
        remove_resource_group
        wait_for_deletion
    else
        remove_openai_deployments
        remove_individual_resources
    fi
    
    # Clean up local files
    cleanup_local_files
    
    # Summary
    display_summary
    
    log_success "Cleanup script completed successfully"
}

# Handle script arguments
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
        --preserve-resource-group)
            export DELETE_RESOURCE_GROUP=false
            shift
            ;;
        --no-wait)
            export WAIT_FOR_COMPLETION=false
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force                      Skip confirmation prompts"
            echo "  --resource-group NAME        Target specific resource group"
            echo "  --preserve-resource-group    Delete individual resources but keep resource group"
            echo "  --no-wait                   Don't wait for deletion to complete"
            echo "  --help                      Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  RESOURCE_GROUP              Override resource group name"
            echo "  FORCE_DELETE               Skip confirmation (true/false)"
            echo "  DELETE_RESOURCE_GROUP      Delete entire resource group (true/false)"
            echo "  WAIT_FOR_COMPLETION        Wait for deletion to complete (true/false)"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Interactive cleanup"
            echo "  $0 --force --resource-group my-rg    # Force cleanup specific RG"
            echo "  $0 --preserve-resource-group         # Keep RG, delete resources"
            echo "  $0 --no-wait                         # Don't wait for completion"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main cleanup
main "$@"