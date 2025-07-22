#!/bin/bash

# Azure AI-Powered Migration Assessment - Cleanup Script
# This script removes all resources created by the deployment script
# including Azure Migrate, Azure OpenAI Service, Azure Functions, and Azure Storage

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Enable logging
exec > >(tee -a "destroy_$(date +%Y%m%d_%H%M%S).log")
exec 2>&1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Some resources may still exist."
    exit 1
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/deployment.conf"
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/../deployment-info.json"

# Default values
DEFAULT_RESOURCE_GROUP="rg-migrate-ai-assessment"
DEFAULT_LOCATION="eastus"

# Load configuration from deployment info file if it exists
if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
    log_info "Loading deployment information from $DEPLOYMENT_INFO_FILE"
    
    RESOURCE_GROUP=$(jq -r '.resourceGroup' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
    STORAGE_ACCOUNT=$(jq -r '.storageAccount' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
    FUNCTION_APP=$(jq -r '.functionApp' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
    OPENAI_SERVICE=$(jq -r '.openaiService' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
    MIGRATE_PROJECT=$(jq -r '.migrateProject' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "")
    LOCATION=$(jq -r '.location' "$DEPLOYMENT_INFO_FILE" 2>/dev/null || echo "$DEFAULT_LOCATION")
    
    log_info "Loaded deployment information:"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Storage Account: $STORAGE_ACCOUNT"
    log_info "Function App: $FUNCTION_APP"
    log_info "OpenAI Service: $OPENAI_SERVICE"
    log_info "Migrate Project: $MIGRATE_PROJECT"
    
elif [[ -f "$CONFIG_FILE" ]]; then
    log_info "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
    
    # Set defaults if not in config
    export RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
    export LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
    
    log_warning "Deployment info file not found. Using configuration values."
    log_warning "Resource discovery will be attempted for cleanup."
    
else
    log_warning "No deployment info or configuration file found."
    log_warning "Using default values and attempting resource discovery."
    
    export RESOURCE_GROUP="$DEFAULT_RESOURCE_GROUP"
    export LOCATION="$DEFAULT_LOCATION"
fi

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Please log in to Azure using 'az login' first."
    fi
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. JSON processing will be limited."
    fi
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    log_info "Using subscription: $SUBSCRIPTION_ID"
    
    log_success "Prerequisites check completed"
}

# Function to discover resources if not provided
discover_resources() {
    log_info "Discovering resources to cleanup..."
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP does not exist. Nothing to cleanup."
        return 1
    fi
    
    log_info "Resource group $RESOURCE_GROUP exists. Discovering resources..."
    
    # Discover resources if not already set
    if [[ -z "${STORAGE_ACCOUNT:-}" ]]; then
        log_info "Discovering storage accounts..."
        STORAGE_ACCOUNTS=$(az storage account list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[?starts_with(name, `stamigrate`)].name' \
            --output tsv)
        
        if [[ -n "$STORAGE_ACCOUNTS" ]]; then
            STORAGE_ACCOUNT=$(echo "$STORAGE_ACCOUNTS" | head -n1)
            log_info "Found storage account: $STORAGE_ACCOUNT"
        else
            log_warning "No storage accounts found with pattern 'stamigrate*'"
        fi
    fi
    
    if [[ -z "${FUNCTION_APP:-}" ]]; then
        log_info "Discovering function apps..."
        FUNCTION_APPS=$(az functionapp list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[?starts_with(name, `func-migrate-ai-`)].name' \
            --output tsv)
        
        if [[ -n "$FUNCTION_APPS" ]]; then
            FUNCTION_APP=$(echo "$FUNCTION_APPS" | head -n1)
            log_info "Found function app: $FUNCTION_APP"
        else
            log_warning "No function apps found with pattern 'func-migrate-ai-*'"
        fi
    fi
    
    if [[ -z "${OPENAI_SERVICE:-}" ]]; then
        log_info "Discovering OpenAI services..."
        OPENAI_SERVICES=$(az cognitiveservices account list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[?starts_with(name, `openai-migrate-`)].name' \
            --output tsv)
        
        if [[ -n "$OPENAI_SERVICES" ]]; then
            OPENAI_SERVICE=$(echo "$OPENAI_SERVICES" | head -n1)
            log_info "Found OpenAI service: $OPENAI_SERVICE"
        else
            log_warning "No OpenAI services found with pattern 'openai-migrate-*'"
        fi
    fi
    
    if [[ -z "${MIGRATE_PROJECT:-}" ]]; then
        log_info "Discovering Migrate projects..."
        MIGRATE_PROJECTS=$(az migrate project list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[?starts_with(name, `migrate-project-`)].name' \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$MIGRATE_PROJECTS" ]]; then
            MIGRATE_PROJECT=$(echo "$MIGRATE_PROJECTS" | head -n1)
            log_info "Found Migrate project: $MIGRATE_PROJECT"
        else
            log_warning "No Migrate projects found with pattern 'migrate-project-*'"
        fi
    fi
    
    return 0
}

# Function to prompt for confirmation
confirm_cleanup() {
    log_warning "This will permanently delete the following resources:"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP"
    
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        echo "Storage Account: $STORAGE_ACCOUNT"
    fi
    
    if [[ -n "${FUNCTION_APP:-}" ]]; then
        echo "Function App: $FUNCTION_APP"
    fi
    
    if [[ -n "${OPENAI_SERVICE:-}" ]]; then
        echo "OpenAI Service: $OPENAI_SERVICE"
    fi
    
    if [[ -n "${MIGRATE_PROJECT:-}" ]]; then
        echo "Migrate Project: $MIGRATE_PROJECT"
    fi
    
    echo "=================================="
    echo ""
    
    # Check if running in non-interactive mode
    if [[ "${1:-}" == "--force" || "${CI:-}" == "true" ]]; then
        log_info "Running in non-interactive mode. Proceeding with cleanup."
        return 0
    fi
    
    # Prompt for confirmation
    read -p "Are you sure you want to delete these resources? (yes/no): " -r REPLY
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    # Double confirmation for production environments
    if [[ "${ENVIRONMENT:-}" == "prod" || "${ENVIRONMENT:-}" == "production" ]]; then
        log_warning "This appears to be a production environment!"
        read -p "Type 'DELETE' to confirm deletion of production resources: " -r REPLY
        echo ""
        
        if [[ "$REPLY" != "DELETE" ]]; then
            log_info "Production cleanup cancelled by user."
            exit 0
        fi
    fi
}

# Function to backup important data
backup_data() {
    log_info "Creating backup of important data..."
    
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        # Create backup directory
        BACKUP_DIR="${SCRIPT_DIR}/../backup/$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        # Get storage account key
        STORAGE_KEY=$(az storage account keys list \
            --resource-group "$RESOURCE_GROUP" \
            --account-name "$STORAGE_ACCOUNT" \
            --query '[0].value' \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$STORAGE_KEY" ]]; then
            log_info "Backing up AI insights and assessment data..."
            
            # Backup AI insights
            az storage blob download-batch \
                --account-name "$STORAGE_ACCOUNT" \
                --account-key "$STORAGE_KEY" \
                --source "ai-insights" \
                --destination "$BACKUP_DIR/ai-insights" \
                --pattern "*" 2>/dev/null || log_warning "Failed to backup AI insights"
            
            # Backup assessment data
            az storage blob download-batch \
                --account-name "$STORAGE_ACCOUNT" \
                --account-key "$STORAGE_KEY" \
                --source "assessment-data" \
                --destination "$BACKUP_DIR/assessment-data" \
                --pattern "*" 2>/dev/null || log_warning "Failed to backup assessment data"
            
            # Backup modernization reports
            az storage blob download-batch \
                --account-name "$STORAGE_ACCOUNT" \
                --account-key "$STORAGE_KEY" \
                --source "modernization-reports" \
                --destination "$BACKUP_DIR/modernization-reports" \
                --pattern "*" 2>/dev/null || log_warning "Failed to backup modernization reports"
            
            log_success "Data backed up to: $BACKUP_DIR"
        else
            log_warning "Could not access storage account for backup"
        fi
    fi
}

# Function to delete Function App
delete_function_app() {
    if [[ -n "${FUNCTION_APP:-}" ]]; then
        log_info "Deleting Function App: $FUNCTION_APP"
        
        if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            # Stop function app first
            az functionapp stop \
                --name "$FUNCTION_APP" \
                --resource-group "$RESOURCE_GROUP" \
                --output none 2>/dev/null || log_warning "Failed to stop function app"
            
            # Delete function app
            az functionapp delete \
                --name "$FUNCTION_APP" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none
            
            log_success "Function App deleted: $FUNCTION_APP"
        else
            log_warning "Function App $FUNCTION_APP does not exist"
        fi
    else
        log_info "No Function App to delete"
    fi
}

# Function to delete Azure OpenAI Service
delete_openai_service() {
    if [[ -n "${OPENAI_SERVICE:-}" ]]; then
        log_info "Deleting Azure OpenAI Service: $OPENAI_SERVICE"
        
        if az cognitiveservices account show --name "$OPENAI_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            # Delete model deployments first
            log_info "Deleting model deployments..."
            
            DEPLOYMENTS=$(az cognitiveservices account deployment list \
                --name "$OPENAI_SERVICE" \
                --resource-group "$RESOURCE_GROUP" \
                --query '[].name' \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "$DEPLOYMENTS" ]]; then
                while IFS= read -r deployment; do
                    if [[ -n "$deployment" ]]; then
                        log_info "Deleting deployment: $deployment"
                        az cognitiveservices account deployment delete \
                            --name "$OPENAI_SERVICE" \
                            --resource-group "$RESOURCE_GROUP" \
                            --deployment-name "$deployment" \
                            --yes \
                            --output none 2>/dev/null || log_warning "Failed to delete deployment: $deployment"
                    fi
                done <<< "$DEPLOYMENTS"
            fi
            
            # Delete OpenAI service
            az cognitiveservices account delete \
                --name "$OPENAI_SERVICE" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none
            
            log_success "Azure OpenAI Service deleted: $OPENAI_SERVICE"
        else
            log_warning "Azure OpenAI Service $OPENAI_SERVICE does not exist"
        fi
    else
        log_info "No Azure OpenAI Service to delete"
    fi
}

# Function to delete Azure Migrate Project
delete_migrate_project() {
    if [[ -n "${MIGRATE_PROJECT:-}" ]]; then
        log_info "Deleting Azure Migrate Project: $MIGRATE_PROJECT"
        
        if az migrate project show --name "$MIGRATE_PROJECT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            # Delete migrate project
            az migrate project delete \
                --name "$MIGRATE_PROJECT" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none
            
            log_success "Azure Migrate Project deleted: $MIGRATE_PROJECT"
        else
            log_warning "Azure Migrate Project $MIGRATE_PROJECT does not exist"
        fi
    else
        log_info "No Azure Migrate Project to delete"
    fi
}

# Function to delete Storage Account
delete_storage_account() {
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        log_info "Deleting Storage Account: $STORAGE_ACCOUNT"
        
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            # Delete storage account
            az storage account delete \
                --name "$STORAGE_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none
            
            log_success "Storage Account deleted: $STORAGE_ACCOUNT"
        else
            log_warning "Storage Account $STORAGE_ACCOUNT does not exist"
        fi
    else
        log_info "No Storage Account to delete"
    fi
}

# Function to delete additional resources
delete_additional_resources() {
    log_info "Checking for additional resources to delete..."
    
    # List all resources in the resource group
    RESOURCES=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].{name:name,type:type}' \
        --output json 2>/dev/null || echo "[]")
    
    if [[ "$RESOURCES" != "[]" ]]; then
        log_info "Found additional resources in resource group:"
        echo "$RESOURCES" | jq -r '.[] | "  - \(.name) (\(.type))"' 2>/dev/null || echo "$RESOURCES"
        
        # Delete any remaining resources
        RESOURCE_IDS=$(echo "$RESOURCES" | jq -r '.[].id' 2>/dev/null || echo "")
        
        if [[ -n "$RESOURCE_IDS" ]]; then
            log_info "Deleting remaining resources..."
            
            while IFS= read -r resource_id; do
                if [[ -n "$resource_id" && "$resource_id" != "null" ]]; then
                    log_info "Deleting resource: $resource_id"
                    az resource delete \
                        --ids "$resource_id" \
                        --output none 2>/dev/null || log_warning "Failed to delete resource: $resource_id"
                fi
            done <<< "$RESOURCE_IDS"
        fi
    fi
}

# Function to delete resource group
delete_resource_group() {
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        # Delete resource group and all remaining resources
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none
        
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log_info "Note: Complete deletion may take several minutes"
        
        # Wait for deletion to complete if requested
        if [[ "${1:-}" == "--wait" ]]; then
            log_info "Waiting for resource group deletion to complete..."
            
            while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
                log_info "Still deleting... (checking again in 30 seconds)"
                sleep 30
            done
            
            log_success "Resource group deletion completed"
        fi
    else
        log_warning "Resource group $RESOURCE_GROUP does not exist"
    fi
}

# Function to cleanup deployment files
cleanup_deployment_files() {
    log_info "Cleaning up deployment files..."
    
    # Remove deployment info file
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        rm "$DEPLOYMENT_INFO_FILE"
        log_success "Deployment info file removed"
    fi
    
    # Remove log files older than 7 days
    find "$SCRIPT_DIR" -name "deploy_*.log" -mtime +7 -delete 2>/dev/null || true
    find "$SCRIPT_DIR" -name "destroy_*.log" -mtime +7 -delete 2>/dev/null || true
    
    log_success "Old log files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP still exists (deletion may still be in progress)"
        
        # List remaining resources
        REMAINING_RESOURCES=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[].name' \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$REMAINING_RESOURCES" ]]; then
            log_warning "Remaining resources found:"
            echo "$REMAINING_RESOURCES"
        fi
    else
        log_success "Resource group $RESOURCE_GROUP has been deleted"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "=========================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Cleanup Date: $(date)"
    echo "=========================="
    
    if [[ -d "${SCRIPT_DIR}/../backup" ]]; then
        echo "Backup Location: ${SCRIPT_DIR}/../backup"
    fi
    
    echo ""
    log_info "Cleanup completed. Check the logs for any warnings or errors."
}

# Main cleanup function
main() {
    log_info "Starting Azure AI-Powered Migration Assessment cleanup"
    log_info "Cleanup started at: $(date)"
    
    # Execute cleanup steps
    check_prerequisites
    
    # Skip discovery if running in batch mode
    if [[ "${1:-}" != "--batch" ]]; then
        discover_resources
        confirm_cleanup "$@"
    fi
    
    # Create backup before deletion
    if [[ "${1:-}" != "--no-backup" ]]; then
        backup_data
    fi
    
    # Delete resources in reverse order of creation
    delete_function_app
    delete_openai_service
    delete_migrate_project
    delete_storage_account
    delete_additional_resources
    delete_resource_group "$@"
    
    # Cleanup deployment files
    cleanup_deployment_files
    
    # Verify cleanup
    if [[ "${1:-}" != "--no-verify" ]]; then
        verify_cleanup
    fi
    
    display_cleanup_summary
    
    log_success "Cleanup completed successfully!"
    log_info "Cleanup finished at: $(date)"
}

# Show help
show_help() {
    echo "Azure AI-Powered Migration Assessment - Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force         Skip confirmation prompts"
    echo "  --wait          Wait for resource group deletion to complete"
    echo "  --no-backup     Skip data backup before deletion"
    echo "  --no-verify     Skip verification after cleanup"
    echo "  --batch         Run in batch mode (skip discovery and confirmation)"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive cleanup with prompts"
    echo "  $0 --force           # Cleanup without prompts"
    echo "  $0 --force --wait    # Cleanup and wait for completion"
    echo "  $0 --batch --force   # Fully automated cleanup"
    echo ""
}

# Check if help is requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

# Check if running directly or being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi