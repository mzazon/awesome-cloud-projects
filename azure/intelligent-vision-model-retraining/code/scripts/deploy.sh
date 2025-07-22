#!/bin/bash

# Azure Intelligent Vision Model Retraining - Deployment Script
# This script deploys the complete MLOps pipeline for automated computer vision model retraining
# using Azure Custom Vision, Logic Apps, Blob Storage, and Monitor services

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")/terraform"
LOG_FILE="/tmp/azure-cv-retraining-deploy-$(date +%Y%m%d-%H%M%S).log"

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
    log "${BLUE}================================================================================================${NC}"
    log "${BLUE}  🤖 Azure Intelligent Vision Model Retraining - Deployment Script${NC}"
    log "${BLUE}================================================================================================${NC}"
    log ""
    log "${BLUE}This script will deploy:${NC}"
    log "${BLUE}  • Azure Custom Vision Training & Prediction services${NC}"
    log "${BLUE}  • Azure Blob Storage with training data containers${NC}"
    log "${BLUE}  • Azure Logic Apps automated retraining workflow${NC}"
    log "${BLUE}  • Azure Monitor with alerts and diagnostics${NC}"
    log "${BLUE}  • Complete MLOps pipeline for computer vision models${NC}"
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
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    info "Azure CLI version: $AZ_VERSION"
    
    # Check Terraform version
    TF_VERSION=$(terraform version -json | jq -r '.terraform_version')
    info "Terraform version: $TF_VERSION"
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "You are not logged in to Azure. Please run 'az login' first"
    fi
    
    # Get current subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    TENANT_ID=$(az account show --query tenantId --output tsv)
    
    info "Current Azure subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    info "Tenant ID: $TENANT_ID"
    
    success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Set default values if not provided
    export TF_VAR_location="${AZURE_LOCATION:-East US}"
    export TF_VAR_environment="${ENVIRONMENT:-dev}"
    export TF_VAR_project_name="${PROJECT_NAME:-cv-retraining}"
    export TF_VAR_notification_email="${NOTIFICATION_EMAIL:-admin@example.com}"
    export TF_VAR_custom_vision_sku="${CUSTOM_VISION_SKU:-S0}"
    export TF_VAR_storage_account_tier="${STORAGE_TIER:-Standard}"
    export TF_VAR_storage_account_replication_type="${STORAGE_REPLICATION:-LRS}"
    export TF_VAR_log_analytics_sku="${LOG_ANALYTICS_SKU:-PerGB2018}"
    export TF_VAR_log_analytics_retention_in_days="${LOG_RETENTION_DAYS:-30}"
    export TF_VAR_enable_application_insights="${ENABLE_APP_INSIGHTS:-false}"
    export TF_VAR_enable_blob_versioning="${ENABLE_BLOB_VERSIONING:-true}"
    export TF_VAR_enable_soft_delete="${ENABLE_SOFT_DELETE:-true}"
    export TF_VAR_logic_app_trigger_frequency="${TRIGGER_FREQUENCY:-Minute}"
    export TF_VAR_logic_app_trigger_interval="${TRIGGER_INTERVAL:-5}"
    export TF_VAR_training_images_max_file_count="${MAX_FILE_COUNT:-10}"
    export TF_VAR_custom_vision_project_type="${PROJECT_TYPE:-Classification}"
    export TF_VAR_custom_vision_classification_type="${CLASSIFICATION_TYPE:-Multiclass}"
    export TF_VAR_alert_evaluation_frequency="${ALERT_FREQUENCY:-PT5M}"
    export TF_VAR_alert_window_size="${ALERT_WINDOW:-PT15M}"
    
    # Additional tags
    export TF_VAR_tags=$(cat << EOF
{
  "Environment": "$TF_VAR_environment",
  "Project": "$TF_VAR_project_name",
  "Purpose": "ml-automation",
  "ManagedBy": "terraform",
  "DeployedBy": "$(whoami)",
  "DeployedOn": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
    
    info "Environment variables configured:"
    info "  • Location: $TF_VAR_location"
    info "  • Environment: $TF_VAR_environment"
    info "  • Project Name: $TF_VAR_project_name"
    info "  • Notification Email: $TF_VAR_notification_email"
    info "  • Custom Vision SKU: $TF_VAR_custom_vision_sku"
    info "  • Storage Tier: $TF_VAR_storage_account_tier"
    info "  • Storage Replication: $TF_VAR_storage_account_replication_type"
    info "  • Log Analytics SKU: $TF_VAR_log_analytics_sku"
    info "  • Log Retention (days): $TF_VAR_log_analytics_retention_in_days"
    info "  • Application Insights: $TF_VAR_enable_application_insights"
    info "  • Blob Versioning: $TF_VAR_enable_blob_versioning"
    info "  • Soft Delete: $TF_VAR_enable_soft_delete"
    info "  • Logic App Trigger: $TF_VAR_logic_app_trigger_frequency every $TF_VAR_logic_app_trigger_interval"
    info "  • Max File Count: $TF_VAR_training_images_max_file_count"
    info "  • Project Type: $TF_VAR_custom_vision_project_type"
    info "  • Classification Type: $TF_VAR_custom_vision_classification_type"
    
    success "Environment variables setup completed"
}

# Validate inputs
validate_inputs() {
    info "Validating inputs..."
    
    # Validate email format
    if [[ ! "$TF_VAR_notification_email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error_exit "Invalid email format: $TF_VAR_notification_email"
    fi
    
    # Validate Custom Vision SKU
    if [[ ! "$TF_VAR_custom_vision_sku" =~ ^(F0|S0)$ ]]; then
        error_exit "Invalid Custom Vision SKU: $TF_VAR_custom_vision_sku (must be F0 or S0)"
    fi
    
    # Validate storage replication type
    if [[ ! "$TF_VAR_storage_account_replication_type" =~ ^(LRS|GRS|RAGRS|ZRS|GZRS|RAGZRS)$ ]]; then
        error_exit "Invalid storage replication type: $TF_VAR_storage_account_replication_type"
    fi
    
    # Validate log retention days
    if [[ ! "$TF_VAR_log_analytics_retention_in_days" =~ ^[0-9]+$ ]] || [ "$TF_VAR_log_analytics_retention_in_days" -lt 30 ] || [ "$TF_VAR_log_analytics_retention_in_days" -gt 730 ]; then
        error_exit "Invalid log retention days: $TF_VAR_log_analytics_retention_in_days (must be between 30 and 730)"
    fi
    
    # Validate trigger interval
    if [[ ! "$TF_VAR_logic_app_trigger_interval" =~ ^[0-9]+$ ]] || [ "$TF_VAR_logic_app_trigger_interval" -lt 1 ] || [ "$TF_VAR_logic_app_trigger_interval" -gt 1000 ]; then
        error_exit "Invalid trigger interval: $TF_VAR_logic_app_trigger_interval (must be between 1 and 1000)"
    fi
    
    # Validate max file count
    if [[ ! "$TF_VAR_training_images_max_file_count" =~ ^[0-9]+$ ]] || [ "$TF_VAR_training_images_max_file_count" -lt 1 ] || [ "$TF_VAR_training_images_max_file_count" -gt 100 ]; then
        error_exit "Invalid max file count: $TF_VAR_training_images_max_file_count (must be between 1 and 100)"
    fi
    
    success "Input validation completed"
}

# Check Azure provider registration
check_azure_providers() {
    info "Checking Azure provider registrations..."
    
    PROVIDERS=(
        "Microsoft.CognitiveServices"
        "Microsoft.Storage"
        "Microsoft.Logic"
        "Microsoft.Web"
        "Microsoft.OperationalInsights"
        "Microsoft.Insights"
    )
    
    for provider in "${PROVIDERS[@]}"; do
        STATUS=$(az provider show --namespace "$provider" --query "registrationState" --output tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$STATUS" != "Registered" ]]; then
            warning "Provider $provider is not registered. Registering..."
            az provider register --namespace "$provider" --wait || error_exit "Failed to register provider $provider"
            success "Provider $provider registered successfully"
        else
            info "Provider $provider is already registered"
        fi
    done
    
    success "Azure provider registration check completed"
}

# Initialize Terraform
initialize_terraform() {
    info "Initializing Terraform..."
    
    cd "$TERRAFORM_DIR" || error_exit "Failed to change to Terraform directory: $TERRAFORM_DIR"
    
    # Initialize Terraform
    terraform init -upgrade || error_exit "Terraform initialization failed"
    
    success "Terraform initialization completed"
}

# Plan Terraform deployment
plan_terraform() {
    info "Planning Terraform deployment..."
    
    # Create Terraform plan
    terraform plan -out=tfplan || error_exit "Terraform planning failed"
    
    # Show plan summary
    terraform show -json tfplan | jq -r '.planned_values.root_module.resources[] | select(.type != null) | "\(.type).\(.name)"' | sort | uniq -c | sort -nr
    
    success "Terraform planning completed"
}

# Apply Terraform deployment
apply_terraform() {
    info "Applying Terraform deployment..."
    
    # Apply Terraform plan
    terraform apply tfplan || error_exit "Terraform apply failed"
    
    success "Terraform deployment completed"
}

# Get deployment outputs
get_outputs() {
    info "Retrieving deployment outputs..."
    
    # Get Terraform outputs
    OUTPUTS_JSON=$(terraform output -json)
    
    # Extract key outputs
    RESOURCE_GROUP_NAME=$(echo "$OUTPUTS_JSON" | jq -r '.resource_group_name.value // empty')
    STORAGE_ACCOUNT_NAME=$(echo "$OUTPUTS_JSON" | jq -r '.storage_account_name.value // empty')
    CUSTOM_VISION_TRAINING_ENDPOINT=$(echo "$OUTPUTS_JSON" | jq -r '.custom_vision_training_endpoint.value // empty')
    CUSTOM_VISION_PREDICTION_ENDPOINT=$(echo "$OUTPUTS_JSON" | jq -r '.custom_vision_prediction_endpoint.value // empty')
    LOGIC_APP_NAME=$(echo "$OUTPUTS_JSON" | jq -r '.logic_app_name.value // empty')
    LOG_ANALYTICS_WORKSPACE_ID=$(echo "$OUTPUTS_JSON" | jq -r '.log_analytics_workspace_id.value // empty')
    CUSTOM_VISION_PROJECT_ID=$(echo "$OUTPUTS_JSON" | jq -r '.custom_vision_project_id.value // empty')
    
    # Display outputs
    log ""
    log "${GREEN}🎉 Deployment completed successfully!${NC}"
    log ""
    log "${BLUE}📋 Deployment Summary:${NC}"
    log "  • Resource Group: $RESOURCE_GROUP_NAME"
    log "  • Storage Account: $STORAGE_ACCOUNT_NAME"
    log "  • Custom Vision Training Endpoint: $CUSTOM_VISION_TRAINING_ENDPOINT"
    log "  • Custom Vision Prediction Endpoint: $CUSTOM_VISION_PREDICTION_ENDPOINT"
    log "  • Logic App: $LOGIC_APP_NAME"
    log "  • Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE_ID"
    log "  • Custom Vision Project ID: $CUSTOM_VISION_PROJECT_ID"
    log ""
    
    success "Deployment outputs retrieved"
}

# Verify deployment
verify_deployment() {
    info "Verifying deployment..."
    
    # Check if resources are accessible
    if [[ -n "$RESOURCE_GROUP_NAME" ]]; then
        az group show --name "$RESOURCE_GROUP_NAME" --query "id" --output tsv > /dev/null || error_exit "Resource group not found: $RESOURCE_GROUP_NAME"
        success "Resource group verified: $RESOURCE_GROUP_NAME"
    fi
    
    if [[ -n "$STORAGE_ACCOUNT_NAME" ]]; then
        az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "id" --output tsv > /dev/null || error_exit "Storage account not found: $STORAGE_ACCOUNT_NAME"
        success "Storage account verified: $STORAGE_ACCOUNT_NAME"
    fi
    
    if [[ -n "$LOGIC_APP_NAME" ]]; then
        az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP_NAME" --query "id" --output tsv > /dev/null || error_exit "Logic App not found: $LOGIC_APP_NAME"
        success "Logic App verified: $LOGIC_APP_NAME"
    fi
    
    success "Deployment verification completed"
}

# Show next steps
show_next_steps() {
    log ""
    log "${BLUE}🚀 Next Steps:${NC}"
    log ""
    log "${YELLOW}1. Upload Training Data:${NC}"
    log "   Upload your training images to the 'training-images' container in the storage account:"
    log "   ${BLUE}az storage blob upload-batch --account-name $STORAGE_ACCOUNT_NAME --destination training-images --source /path/to/your/images${NC}"
    log ""
    log "${YELLOW}2. Monitor Training:${NC}"
    log "   Check the Logic App runs to monitor automatic training:"
    log "   ${BLUE}az logic workflow list-runs --name $LOGIC_APP_NAME --resource-group $RESOURCE_GROUP_NAME${NC}"
    log ""
    log "${YELLOW}3. View Custom Vision Project:${NC}"
    log "   Access your Custom Vision project at:"
    log "   ${BLUE}https://www.customvision.ai/projects/$CUSTOM_VISION_PROJECT_ID${NC}"
    log ""
    log "${YELLOW}4. Monitor Logs:${NC}"
    log "   View training logs in Azure Monitor:"
    log "   ${BLUE}az monitor log-analytics query --workspace $LOG_ANALYTICS_WORKSPACE_ID --analytics-query 'CustomVisionTraining_CL | limit 50'${NC}"
    log ""
    log "${YELLOW}5. Test Predictions:${NC}"
    log "   Once training is complete, test your model using the prediction endpoint:"
    log "   ${BLUE}$CUSTOM_VISION_PREDICTION_ENDPOINT${NC}"
    log ""
    log "${GREEN}📝 Important Notes:${NC}"
    log "  • Ensure you have at least 15 images per tag for successful training"
    log "  • Training is triggered automatically when new images are uploaded"
    log "  • Monitor costs in the Azure portal as Custom Vision and Logic Apps incur charges"
    log "  • The Logic App checks for new images every $TF_VAR_logic_app_trigger_interval $TF_VAR_logic_app_trigger_frequency"
    log ""
    log "${GREEN}🔧 For cleanup, run:${NC}"
    log "  ${BLUE}./scripts/destroy.sh${NC}"
    log ""
}

# Main execution
main() {
    print_banner
    check_prerequisites
    setup_environment
    validate_inputs
    check_azure_providers
    initialize_terraform
    plan_terraform
    
    # Prompt for confirmation
    log ""
    log "${YELLOW}⚠️  Ready to deploy Azure Intelligent Vision Model Retraining infrastructure.${NC}"
    log "${YELLOW}   This will create billable Azure resources.${NC}"
    log ""
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "${YELLOW}Deployment cancelled by user.${NC}"
        exit 0
    fi
    
    apply_terraform
    get_outputs
    verify_deployment
    show_next_steps
    
    log ""
    log "${GREEN}🎉 Azure Intelligent Vision Model Retraining deployment completed successfully!${NC}"
    log "${GREEN}📄 Full deployment log available at: $LOG_FILE${NC}"
    log ""
}

# Handle script interruption
trap 'log "${RED}❌ Script interrupted by user${NC}"; exit 1' INT TERM

# Run main function
main "$@"