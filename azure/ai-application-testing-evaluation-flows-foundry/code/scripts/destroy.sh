#!/bin/bash

# Destroy script for AI Application Testing with Evaluation Flows and AI Foundry
# This script removes all Azure resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script metadata
SCRIPT_NAME="destroy.sh"
SCRIPT_VERSION="1.0"
RECIPE_NAME="ai-application-testing-evaluation-flows-foundry"

# Logging configuration
LOG_FILE="/tmp/${RECIPE_NAME}_destroy_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Error handler
error_handler() {
    local line_number=$1
    log_error "Script failed at line $line_number. Check $LOG_FILE for details."
    log_error "Some resources may not have been deleted completely."
    log_error "Please check Azure portal and delete remaining resources manually."
    exit 1
}

trap 'error_handler $LINENO' ERR

# Display script header
echo "=========================================="
echo "Azure AI Testing Recipe Cleanup Script"
echo "Recipe: $RECIPE_NAME"
echo "Version: $SCRIPT_VERSION"
echo "Log file: $LOG_FILE"
echo "=========================================="

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Try to load environment variables from saved file
    if [[ -f "/tmp/${RECIPE_NAME}_env.sh" ]]; then
        log_info "Loading saved environment variables from /tmp/${RECIPE_NAME}_env.sh"
        source "/tmp/${RECIPE_NAME}_env.sh"
        log_success "Environment variables loaded from saved file"
    else
        log_warning "Saved environment file not found. You'll need to provide resource details manually."
        prompt_for_resources
    fi
    
    # Validate required variables are set
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_error "RESOURCE_GROUP not set. Cannot proceed with cleanup."
        exit 1
    fi
    
    log_info "Environment variables:"
    log_info "  RESOURCE_GROUP: ${RESOURCE_GROUP}"
    log_info "  AI_SERVICES_NAME: ${AI_SERVICES_NAME:-not set}"
    log_info "  STORAGE_ACCOUNT: ${STORAGE_ACCOUNT:-not set}"
    log_info "  MODEL_DEPLOYMENT_NAME: ${MODEL_DEPLOYMENT_NAME:-not set}"
}

# Function to prompt for resource details if environment file not found
prompt_for_resources() {
    log_info "Please provide the resource details to clean up:"
    
    # Resource Group (required)
    while [[ -z "${RESOURCE_GROUP:-}" ]]; do
        read -p "Enter the Resource Group name (required): " RESOURCE_GROUP
        if [[ -z "$RESOURCE_GROUP" ]]; then
            log_warning "Resource Group name is required for cleanup."
        fi
    done
    
    # Optional: AI Services name
    read -p "Enter the AI Services name (optional, leave blank to skip): " AI_SERVICES_NAME
    
    # Optional: Storage Account name
    read -p "Enter the Storage Account name (optional, leave blank to skip): " STORAGE_ACCOUNT
    
    # Optional: Model deployment name
    read -p "Enter the Model Deployment name (optional, leave blank to skip): " MODEL_DEPLOYMENT_NAME
    
    export RESOURCE_GROUP
    export AI_SERVICES_NAME
    export STORAGE_ACCOUNT
    export MODEL_DEPLOYMENT_NAME
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "⚠️  WARNING: This will permanently delete the following resources:"
    echo ""
    echo "  🗂️  Resource Group: ${RESOURCE_GROUP}"
    
    if [[ -n "${AI_SERVICES_NAME:-}" ]]; then
        echo "  🤖 AI Services: ${AI_SERVICES_NAME}"
    fi
    
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        echo "  🗃️  Storage Account: ${STORAGE_ACCOUNT}"
    fi
    
    if [[ -n "${MODEL_DEPLOYMENT_NAME:-}" ]]; then
        echo "  🎯 Model Deployment: ${MODEL_DEPLOYMENT_NAME}"
    fi
    
    echo ""
    echo "  📁 Local files and directories created by deployment"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    
    # Confirmation prompt
    local confirmation=""
    while [[ "$confirmation" != "yes" && "$confirmation" != "no" ]]; do
        read -p "Do you want to proceed with the deletion? (yes/no): " confirmation
        confirmation=$(echo "$confirmation" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$confirmation" == "no" || "$confirmation" == "n" ]]; then
            log_info "Cleanup cancelled by user."
            exit 0
        elif [[ "$confirmation" != "yes" && "$confirmation" != "y" ]]; then
            log_warning "Please enter 'yes' or 'no'"
        fi
    done
    
    log_info "User confirmed destruction. Proceeding with cleanup..."
}

# Function to check if resource group exists
check_resource_group() {
    log_info "Checking if resource group exists: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_info "Resource group found: $RESOURCE_GROUP"
        return 0
    else
        log_warning "Resource group not found: $RESOURCE_GROUP"
        log_warning "The resource group may have already been deleted or never existed."
        return 1
    fi
}

# Function to delete individual resources (for more controlled cleanup)
delete_individual_resources() {
    log_info "Starting individual resource cleanup..."
    
    if [[ -n "${AI_SERVICES_NAME:-}" ]]; then
        delete_ai_services
    fi
    
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        delete_storage_account
    fi
}

# Function to delete AI Services and model deployments
delete_ai_services() {
    log_info "Deleting AI Services resource: $AI_SERVICES_NAME"
    
    # Check if AI Services exists
    if az cognitiveservices account show \
        --name "$AI_SERVICES_NAME" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        
        # Delete model deployment first if specified
        if [[ -n "${MODEL_DEPLOYMENT_NAME:-}" ]]; then
            log_info "Deleting model deployment: $MODEL_DEPLOYMENT_NAME"
            
            if az cognitiveservices account deployment show \
                --name "$AI_SERVICES_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --deployment-name "$MODEL_DEPLOYMENT_NAME" &> /dev/null; then
                
                az cognitiveservices account deployment delete \
                    --name "$AI_SERVICES_NAME" \
                    --resource-group "$RESOURCE_GROUP" \
                    --deployment-name "$MODEL_DEPLOYMENT_NAME" \
                    --output table
                
                log_success "Model deployment deleted: $MODEL_DEPLOYMENT_NAME"
            else
                log_warning "Model deployment not found: $MODEL_DEPLOYMENT_NAME"
            fi
        fi
        
        # Delete AI Services account
        az cognitiveservices account delete \
            --name "$AI_SERVICES_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --output table
        
        log_success "AI Services resource deleted: $AI_SERVICES_NAME"
    else
        log_warning "AI Services resource not found: $AI_SERVICES_NAME"
    fi
}

# Function to delete storage account
delete_storage_account() {
    log_info "Deleting storage account: $STORAGE_ACCOUNT"
    
    # Check if storage account exists
    if az storage account show \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output table
        
        log_success "Storage account deleted: $STORAGE_ACCOUNT"
    else
        log_warning "Storage account not found: $STORAGE_ACCOUNT"
    fi
}

# Function to delete the entire resource group
delete_resource_group() {
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output table
    
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log_info "Note: Resource group deletion is running in the background and may take several minutes to complete."
}

# Function to wait for resource group deletion (optional)
wait_for_resource_group_deletion() {
    local wait_for_completion=""
    read -p "Do you want to wait for resource group deletion to complete? (yes/no): " wait_for_completion
    wait_for_completion=$(echo "$wait_for_completion" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$wait_for_completion" == "yes" || "$wait_for_completion" == "y" ]]; then
        log_info "Waiting for resource group deletion to complete..."
        
        local max_attempts=60  # 30 minutes (30 seconds * 60)
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
                log_success "Resource group deletion completed: $RESOURCE_GROUP"
                return 0
            fi
            
            log_info "Attempt $attempt/$max_attempts: Resource group still exists, waiting..."
            sleep 30
            ((attempt++))
        done
        
        log_warning "Resource group deletion is taking longer than expected."
        log_warning "Please check Azure portal to monitor deletion progress."
    else
        log_info "Skipping wait for resource group deletion."
        log_info "You can monitor deletion progress in the Azure portal."
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files and directories..."
    
    local items_to_clean=(
        "evaluation_flow"
        ".azuredevops"
        "run_evaluation.py"
        "check_quality_gates.py"
        "/tmp/test_data.jsonl"
        "/tmp/${RECIPE_NAME}_env.sh"
    )
    
    for item in "${items_to_clean[@]}"; do
        if [[ -f "$item" || -d "$item" ]]; then
            log_info "Removing: $item"
            rm -rf "$item"
            log_success "Removed: $item"
        else
            log_info "Item not found (may have been already removed): $item"
        fi
    done
    
    # Clean up any generated result files
    for file in results.json evaluation_results.json test_results.json sample_results.json; do
        if [[ -f "$file" ]]; then
            log_info "Removing result file: $file"
            rm -f "$file"
            log_success "Removed: $file"
        fi
    done
    
    log_success "Local file cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group still exists: $RESOURCE_GROUP"
        log_warning "Deletion may still be in progress. Check Azure portal for status."
    else
        log_success "Resource group confirmed deleted: $RESOURCE_GROUP"
    fi
    
    # Check local files
    local remaining_files=()
    local items_to_check=(
        "evaluation_flow"
        ".azuredevops"
        "run_evaluation.py"
        "check_quality_gates.py"
    )
    
    for item in "${items_to_check[@]}"; do
        if [[ -f "$item" || -d "$item" ]]; then
            remaining_files+=("$item")
        fi
    done
    
    if [[ ${#remaining_files[@]} -eq 0 ]]; then
        log_success "All local files and directories cleaned up"
    else
        log_warning "Some local files/directories remain:"
        for file in "${remaining_files[@]}"; do
            log_warning "  - $file"
        done
    fi
    
    log_success "Cleanup verification completed"
}

# Function to display cleanup summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "🧹 CLEANUP COMPLETED!"
    echo "=========================================="
    echo ""
    echo "✅ Actions Performed:"
    echo "  • Resource group deletion initiated: ${RESOURCE_GROUP}"
    
    if [[ -n "${AI_SERVICES_NAME:-}" ]]; then
        echo "  • AI Services resource deleted: ${AI_SERVICES_NAME}"
    fi
    
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        echo "  • Storage account deleted: ${STORAGE_ACCOUNT}"
    fi
    
    if [[ -n "${MODEL_DEPLOYMENT_NAME:-}" ]]; then
        echo "  • Model deployment deleted: ${MODEL_DEPLOYMENT_NAME}"
    fi
    
    echo "  • Local files and directories cleaned up"
    echo ""
    echo "📋 Next Steps:"
    echo "  • Monitor Azure portal to confirm resource deletion completion"
    echo "  • Check your Azure bill to ensure charges have stopped"
    echo "  • Remove any service connections from Azure DevOps if configured"
    echo ""
    echo "⚠️  Important Notes:"
    echo "  • Resource group deletion runs asynchronously and may take time"
    echo "  • Some resources may have soft-delete enabled (check Azure portal)"
    echo "  • Cognitive Services may retain data for 30 days after deletion"
    echo ""
    echo "📜 Log file: $LOG_FILE"
    echo "=========================================="
}

# Function to provide recovery information
provide_recovery_info() {
    log_info "Recovery Information:"
    echo ""
    echo "If you need to recover or recreate resources:"
    echo "  1. Run the deploy.sh script again"
    echo "  2. All resources will be created with new names"
    echo "  3. Update any external references (Azure DevOps, etc.)"
    echo ""
    echo "If cleanup failed and resources remain:"
    echo "  1. Check Azure portal: https://portal.azure.com"
    echo "  2. Navigate to Resource Groups"
    echo "  3. Manually delete remaining resources"
    echo "  4. Check Cognitive Services soft-delete if applicable"
    echo ""
}

# Main execution
main() {
    log_info "Starting cleanup of AI Application Testing with Evaluation Flows resources"
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    if check_resource_group; then
        # Option 1: Delete individual resources first (more controlled)
        delete_individual_resources
        
        # Option 2: Delete entire resource group (faster but less granular)
        delete_resource_group
        
        # Optionally wait for completion
        wait_for_resource_group_deletion
    else
        log_warning "Resource group not found, skipping Azure resource cleanup"
    fi
    
    # Always clean up local files
    cleanup_local_files
    
    verify_cleanup
    display_summary
    provide_recovery_info
    
    log_success "Cleanup process completed!"
    log_info "Thank you for using the AI Application Testing recipe!"
}

# Handle script interruption gracefully
cleanup_on_exit() {
    log_warning "Script interrupted by user"
    log_info "Partial cleanup may have occurred"
    log_info "Check Azure portal to verify resource status"
    exit 130
}

trap cleanup_on_exit SIGINT SIGTERM

# Execute main function
main "$@"