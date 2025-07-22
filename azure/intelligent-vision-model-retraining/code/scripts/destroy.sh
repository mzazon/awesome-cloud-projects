#!/bin/bash

# Azure Intelligent Vision Model Retraining - Cleanup Script
# This script safely destroys all Azure resources created by the deployment script
# including Custom Vision services, Logic Apps, Blob Storage, and Monitor resources

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")/terraform"
LOG_FILE="/tmp/azure-cv-retraining-destroy-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    log "${RED}❌ Error: $1${NC}"
    log "${YELLOW}📋 Check the log file for details: $LOG_FILE${NC}"
    exit 1
}

# Success function
success() {
    log "${GREEN}✅ $1${NC}"
}

# Info function
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Warning function
warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Print banner
print_banner() {
    log ""
    log "${RED}================================================================================================${NC}"
    log "${RED}  🗑️  Azure Intelligent Vision Model Retraining - Cleanup Script${NC}"
    log "${RED}================================================================================================${NC}"
    log ""
    log "${RED}This script will destroy:${NC}"
    log "${RED}  • Azure Custom Vision Training & Prediction services${NC}"
    log "${RED}  • Azure Blob Storage and all training data${NC}"
    log "${RED}  • Azure Logic Apps automated retraining workflow${NC}"
    log "${RED}  • Azure Monitor alerts and diagnostics${NC}"
    log "${RED}  • All associated resources and data${NC}"
    log ""
    log "${YELLOW}⚠️  WARNING: This action cannot be undone!${NC}"
    log "${YELLOW}⚠️  All training data, models, and configurations will be permanently deleted!${NC}"
    log ""
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        error_exit "Terraform is not installed. Please install it from https://www.terraform.io/downloads.html"
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install it for JSON processing"
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "You are not logged in to Azure. Please run 'az login' first"
    fi
    
    # Check if Terraform directory exists
    if [[ ! -d "$TERRAFORM_DIR" ]]; then
        error_exit "Terraform directory not found: $TERRAFORM_DIR"
    fi
    
    # Check if Terraform has been initialized
    if [[ ! -f "$TERRAFORM_DIR/.terraform.lock.hcl" ]]; then
        error_exit "Terraform has not been initialized. Please run 'terraform init' first or use the deploy script"
    fi
    
    success "Prerequisites check completed"
}

# Get current deployment info
get_deployment_info() {
    info "Getting current deployment information..."
    
    cd "$TERRAFORM_DIR" || error_exit "Failed to change to Terraform directory: $TERRAFORM_DIR"
    
    # Check if Terraform state exists
    if ! terraform state list &> /dev/null; then
        warning "No Terraform state found. Either resources were never deployed or state is missing."
        return 1
    fi
    
    # Get current outputs if available
    if terraform output -json &> /dev/null; then
        OUTPUTS_JSON=$(terraform output -json)
        RESOURCE_GROUP_NAME=$(echo "$OUTPUTS_JSON" | jq -r '.resource_group_name.value // empty')
        STORAGE_ACCOUNT_NAME=$(echo "$OUTPUTS_JSON" | jq -r '.storage_account_name.value // empty')
        LOGIC_APP_NAME=$(echo "$OUTPUTS_JSON" | jq -r '.logic_app_name.value // empty')
        CUSTOM_VISION_TRAINING_NAME=$(echo "$OUTPUTS_JSON" | jq -r '.custom_vision_training_name.value // empty')
        CUSTOM_VISION_PREDICTION_NAME=$(echo "$OUTPUTS_JSON" | jq -r '.custom_vision_prediction_name.value // empty')
        LOG_ANALYTICS_WORKSPACE_NAME=$(echo "$OUTPUTS_JSON" | jq -r '.log_analytics_workspace_name.value // empty')
        
        log ""
        log "${BLUE}📋 Current Deployment Information:${NC}"
        log "  • Resource Group: ${RESOURCE_GROUP_NAME:-Not found}"
        log "  • Storage Account: ${STORAGE_ACCOUNT_NAME:-Not found}"
        log "  • Logic App: ${LOGIC_APP_NAME:-Not found}"
        log "  • Custom Vision Training: ${CUSTOM_VISION_TRAINING_NAME:-Not found}"
        log "  • Custom Vision Prediction: ${CUSTOM_VISION_PREDICTION_NAME:-Not found}"
        log "  • Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE_NAME:-Not found}"
        log ""
    else
        warning "Unable to retrieve deployment outputs. Proceeding with state-based cleanup."
    fi
    
    success "Deployment information retrieved"
    return 0
}

# Backup important data
backup_data() {
    info "Creating backup of important data before cleanup..."
    
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]] && [[ -n "${RESOURCE_GROUP_NAME:-}" ]]; then
        # Create backup directory
        BACKUP_DIR="/tmp/cv-retraining-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        # Get storage account key
        STORAGE_KEY=$(az storage account keys list \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --account-name "$STORAGE_ACCOUNT_NAME" \
            --query '[0].value' --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$STORAGE_KEY" ]]; then
            # Backup project configuration
            az storage blob download \
                --account-name "$STORAGE_ACCOUNT_NAME" \
                --account-key "$STORAGE_KEY" \
                --container-name "model-artifacts" \
                --name "project-config.json" \
                --file "$BACKUP_DIR/project-config.json" \
                2>/dev/null && success "Project configuration backed up to $BACKUP_DIR/project-config.json"
            
            # List training images for reference
            az storage blob list \
                --account-name "$STORAGE_ACCOUNT_NAME" \
                --account-key "$STORAGE_KEY" \
                --container-name "training-images" \
                --output table > "$BACKUP_DIR/training-images-list.txt" \
                2>/dev/null && success "Training images list backed up to $BACKUP_DIR/training-images-list.txt"
            
            # List processed images for reference
            az storage blob list \
                --account-name "$STORAGE_ACCOUNT_NAME" \
                --account-key "$STORAGE_KEY" \
                --container-name "processed-images" \
                --output table > "$BACKUP_DIR/processed-images-list.txt" \
                2>/dev/null && success "Processed images list backed up to $BACKUP_DIR/processed-images-list.txt"
        fi
        
        # Backup Terraform state
        if [[ -f "$TERRAFORM_DIR/terraform.tfstate" ]]; then
            cp "$TERRAFORM_DIR/terraform.tfstate" "$BACKUP_DIR/terraform.tfstate.backup"
            success "Terraform state backed up to $BACKUP_DIR/terraform.tfstate.backup"
        fi
        
        # Backup Terraform variables
        if [[ -f "$TERRAFORM_DIR/terraform.tfvars" ]]; then
            cp "$TERRAFORM_DIR/terraform.tfvars" "$BACKUP_DIR/terraform.tfvars.backup"
            success "Terraform variables backed up to $BACKUP_DIR/terraform.tfvars.backup"
        fi
        
        log ""
        log "${GREEN}📦 Backup completed: $BACKUP_DIR${NC}"
        log "${YELLOW}💡 Keep this backup if you need to reference the configuration later${NC}"
        log ""
    else
        warning "Unable to create backup - storage account information not available"
    fi
}

# Stop active processes
stop_active_processes() {
    info "Stopping active processes..."
    
    if [[ -n "${LOGIC_APP_NAME:-}" ]] && [[ -n "${RESOURCE_GROUP_NAME:-}" ]]; then
        # Check if Logic App exists and is running
        if az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" &> /dev/null; then
            # Get current state
            LOGIC_APP_STATE=$(az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "state" --output tsv)
            
            if [[ "$LOGIC_APP_STATE" == "Enabled" ]]; then
                warning "Logic App is currently enabled. Disabling to stop new executions..."
                az logic workflow update --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --state "Disabled" || warning "Failed to disable Logic App"
                success "Logic App disabled"
                
                # Wait for any running executions to complete
                info "Waiting for running executions to complete..."
                sleep 10
                
                # Check for running executions
                RUNNING_EXECUTIONS=$(az logic workflow list-runs --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "value[?status=='Running'] | length(@)" --output tsv 2>/dev/null || echo "0")
                
                if [[ "$RUNNING_EXECUTIONS" -gt 0 ]]; then
                    warning "$RUNNING_EXECUTIONS executions are still running. They will be terminated during cleanup."
                    sleep 5
                fi
            fi
        fi
    fi
    
    success "Active processes stopped"
}

# Plan Terraform destroy
plan_destroy() {
    info "Planning Terraform destroy..."
    
    # Create destroy plan
    terraform plan -destroy -out=destroy-plan || error_exit "Terraform destroy planning failed"
    
    # Show destroy plan summary
    info "Resources to be destroyed:"
    terraform show -json destroy-plan | jq -r '.planned_values.root_module.resources[] | select(.type != null) | "\(.type).\(.name)"' | sort | uniq -c | sort -nr
    
    success "Terraform destroy planning completed"
}

# Execute Terraform destroy
execute_destroy() {
    info "Executing Terraform destroy..."
    
    # Apply destroy plan
    terraform apply destroy-plan || error_exit "Terraform destroy failed"
    
    success "Terraform destroy completed"
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove Terraform files
    if [[ -f "$TERRAFORM_DIR/tfplan" ]]; then
        rm "$TERRAFORM_DIR/tfplan"
        success "Terraform plan file removed"
    fi
    
    if [[ -f "$TERRAFORM_DIR/destroy-plan" ]]; then
        rm "$TERRAFORM_DIR/destroy-plan"
        success "Terraform destroy plan file removed"
    fi
    
    # Optionally remove Terraform state (ask user)
    if [[ -f "$TERRAFORM_DIR/terraform.tfstate" ]]; then
        read -p "Remove Terraform state file? This will make future deployments create new state. (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm "$TERRAFORM_DIR/terraform.tfstate"
            if [[ -f "$TERRAFORM_DIR/terraform.tfstate.backup" ]]; then
                rm "$TERRAFORM_DIR/terraform.tfstate.backup"
            fi
            success "Terraform state files removed"
        else
            info "Terraform state files preserved"
        fi
    fi
    
    success "Local files cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    info "Verifying cleanup..."
    
    if [[ -n "${RESOURCE_GROUP_NAME:-}" ]]; then
        # Check if resource group still exists
        if az group show --name "$RESOURCE_GROUP_NAME" &> /dev/null; then
            warning "Resource group still exists: $RESOURCE_GROUP_NAME"
            
            # List remaining resources
            REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP_NAME" --query "length(@)" --output tsv 2>/dev/null || echo "0")
            
            if [[ "$REMAINING_RESOURCES" -gt 0 ]]; then
                warning "$REMAINING_RESOURCES resources still exist in the resource group"
                az resource list --resource-group "$RESOURCE_GROUP_NAME" --output table
                
                # Ask if user wants to force delete the resource group
                read -p "Force delete the resource group and all remaining resources? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    warning "Force deleting resource group..."
                    az group delete --name "$RESOURCE_GROUP_NAME" --yes --no-wait
                    success "Resource group deletion initiated"
                fi
            else
                # Empty resource group, safe to delete
                az group delete --name "$RESOURCE_GROUP_NAME" --yes --no-wait
                success "Empty resource group deleted"
            fi
        else
            success "Resource group successfully deleted: $RESOURCE_GROUP_NAME"
        fi
    fi
    
    success "Cleanup verification completed"
}

# Show cleanup summary
show_cleanup_summary() {
    log ""
    log "${GREEN}🎉 Cleanup completed successfully!${NC}"
    log ""
    log "${BLUE}📋 Cleanup Summary:${NC}"
    log "  • All Azure resources have been destroyed"
    log "  • Custom Vision services and models deleted"
    log "  • Storage accounts and training data removed"
    log "  • Logic Apps workflows terminated"
    log "  • Monitor alerts and diagnostics removed"
    log "  • Resource group cleaned up"
    log ""
    
    if [[ -n "${BACKUP_DIR:-}" ]]; then
        log "${YELLOW}📦 Backup Location:${NC}"
        log "  • Configuration backup: $BACKUP_DIR"
        log "  • Keep this backup for reference if needed"
        log ""
    fi
    
    log "${GREEN}💰 Cost Impact:${NC}"
    log "  • All billable resources have been removed"
    log "  • No ongoing charges for this deployment"
    log "  • Check Azure billing for any remaining charges"
    log ""
    
    log "${BLUE}🔄 To redeploy:${NC}"
    log "  • Run ./scripts/deploy.sh again"
    log "  • Restore configuration from backup if needed"
    log "  • Upload training data to new storage account"
    log ""
}

# Main execution
main() {
    print_banner
    
    # Get confirmation before proceeding
    read -p "Are you sure you want to destroy all resources? Type 'yes' to confirm: " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        log "${YELLOW}Cleanup cancelled by user.${NC}"
        exit 0
    fi
    
    # Additional confirmation for safety
    read -p "This will permanently delete all training data and models. Type 'DELETE' to confirm: " -r
    echo
    if [[ ! $REPLY == "DELETE" ]]; then
        log "${YELLOW}Cleanup cancelled by user.${NC}"
        exit 0
    fi
    
    check_prerequisites
    
    # Get deployment info (don't exit if it fails)
    get_deployment_info || true
    
    backup_data
    stop_active_processes
    plan_destroy
    
    # Final confirmation
    log ""
    log "${RED}⚠️  FINAL WARNING: About to destroy all resources!${NC}"
    log "${RED}⚠️  This action cannot be undone!${NC}"
    log ""
    read -p "Proceed with destruction? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "${YELLOW}Cleanup cancelled by user.${NC}"
        exit 0
    fi
    
    execute_destroy
    cleanup_local_files
    verify_cleanup
    show_cleanup_summary
    
    log ""
    log "${GREEN}🗑️  Azure Intelligent Vision Model Retraining cleanup completed successfully!${NC}"
    log "${GREEN}📄 Full cleanup log available at: $LOG_FILE${NC}"
    log ""
}

# Handle script interruption
trap 'log "${RED}❌ Script interrupted by user${NC}"; exit 1' INT TERM

# Run main function
main "$@"