#!/bin/bash

# =============================================================================
# Azure Fraud Detection Cleanup Script
# Recipe: Implementing Intelligent Financial Fraud Detection with Azure AI 
#         Metrics Advisor and Azure AI Immersive Reader
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deploy-config"

# =============================================================================
# Logging Functions
# =============================================================================

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

# =============================================================================
# Utility Functions
# =============================================================================

print_banner() {
    echo -e "${RED}"
    echo "=============================================================="
    echo "Azure Fraud Detection Cleanup Script"
    echo "=============================================================="
    echo -e "${NC}"
}

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group GROUP  Resource group name to delete"
    echo "  -f, --force                 Force deletion without confirmation"
    echo "  --dry-run                   Show what would be deleted without removing resources"
    echo "  --keep-rg                   Keep resource group (delete resources only)"
    echo "  --config-file FILE          Path to deployment config file"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                          # Delete using saved config"
    echo "  $0 -g rg-fraud-detection-abc123  # Delete specific resource group"
    echo "  $0 --dry-run               # Preview deletion without removing resources"
    echo "  $0 --keep-rg               # Delete resources but keep resource group"
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
        log_info "Configuration loaded successfully"
    else
        log_warning "No configuration file found at $CONFIG_FILE"
        if [[ -z "$RESOURCE_GROUP" ]]; then
            log_error "No resource group specified and no config file found"
            echo "Please specify resource group with -g option or ensure config file exists"
            exit 1
        fi
    fi
}

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
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
    
    # Check if resource group exists
    if [[ "$DRY_RUN" != "true" ]] && ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group '$RESOURCE_GROUP' does not exist"
        exit 1
    fi
    
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    log_info "Using subscription: $subscription_name ($subscription_id)"
    
    log_success "Prerequisites validated"
}

# =============================================================================
# Resource Listing Functions
# =============================================================================

list_resources() {
    log_info "Listing resources in resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would list resources in: $RESOURCE_GROUP"
        return 0
    fi
    
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].{Name:name, Type:type, Location:location}' --output table)
    if [[ -n "$resources" ]]; then
        echo "$resources"
        log_info "Found $(echo "$resources" | wc -l) resources (including header)"
    else
        log_info "No resources found in resource group"
    fi
}

# =============================================================================
# Resource Deletion Functions
# =============================================================================

delete_monitoring_resources() {
    log_info "Deleting monitoring resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete monitoring resources"
        return 0
    fi
    
    # Delete alert rules
    local alert_rules=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    if [[ -n "$alert_rules" ]]; then
        for rule in $alert_rules; do
            log_info "Deleting alert rule: $rule"
            az monitor metrics alert delete --name "$rule" --resource-group "$RESOURCE_GROUP" --output none
            log_success "Alert rule deleted: $rule"
        done
    else
        log_info "No alert rules found to delete"
    fi
    
    # Delete Log Analytics workspaces
    local workspaces=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    if [[ -n "$workspaces" ]]; then
        for workspace in $workspaces; do
            log_info "Deleting Log Analytics workspace: $workspace"
            az monitor log-analytics workspace delete --workspace-name "$workspace" --resource-group "$RESOURCE_GROUP" --yes --output none
            log_success "Log Analytics workspace deleted: $workspace"
        done
    else
        log_info "No Log Analytics workspaces found to delete"
    fi
}

delete_logic_apps() {
    log_info "Deleting Logic Apps..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Logic Apps"
        return 0
    fi
    
    local logic_apps=$(az logic workflow list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    if [[ -n "$logic_apps" ]]; then
        for app in $logic_apps; do
            log_info "Deleting Logic App: $app"
            az logic workflow delete --name "$app" --resource-group "$RESOURCE_GROUP" --yes --output none
            log_success "Logic App deleted: $app"
        done
    else
        log_info "No Logic Apps found to delete"
    fi
}

delete_cognitive_services() {
    log_info "Deleting Cognitive Services..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cognitive Services"
        return 0
    fi
    
    local cognitive_services=$(az cognitiveservices account list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    if [[ -n "$cognitive_services" ]]; then
        for service in $cognitive_services; do
            log_info "Deleting Cognitive Service: $service"
            az cognitiveservices account delete --name "$service" --resource-group "$RESOURCE_GROUP" --output none
            log_success "Cognitive Service deleted: $service"
        done
    else
        log_info "No Cognitive Services found to delete"
    fi
}

delete_storage_accounts() {
    log_info "Deleting Storage Accounts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Storage Accounts"
        return 0
    fi
    
    local storage_accounts=$(az storage account list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
    if [[ -n "$storage_accounts" ]]; then
        for account in $storage_accounts; do
            log_info "Deleting Storage Account: $account"
            az storage account delete --name "$account" --resource-group "$RESOURCE_GROUP" --yes --output none
            log_success "Storage Account deleted: $account"
        done
    else
        log_info "No Storage Accounts found to delete"
    fi
}

delete_resource_group() {
    if [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        log_info "Keeping resource group as requested"
        return 0
    fi
    
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait --output none
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log_info "Note: Resource group deletion may take several minutes to complete"
}

# =============================================================================
# Verification Functions
# =============================================================================

verify_deletion() {
    log_info "Verifying resource deletion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify deletion"
        return 0
    fi
    
    # Check if resource group still exists
    if [[ "$KEEP_RESOURCE_GROUP" != "true" ]]; then
        # Wait a moment for deletion to propagate
        sleep 10
        
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_info "Resource group still exists (deletion in progress)"
        else
            log_success "Resource group successfully deleted"
        fi
    else
        # Check if resources still exist in the group
        local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv)
        if [[ -n "$remaining_resources" ]]; then
            log_warning "Some resources may still exist in the resource group:"
            echo "$remaining_resources"
        else
            log_success "All resources successfully deleted from resource group"
        fi
    fi
}

# =============================================================================
# Main Functions
# =============================================================================

confirm_deletion() {
    if [[ "$FORCE_DELETION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${RED}WARNING: This will delete the following resources:${NC}"
    echo ""
    list_resources
    echo ""
    
    if [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
        echo -e "${YELLOW}Resource group will be PRESERVED${NC}"
    else
        echo -e "${RED}Resource group will be DELETED: $RESOURCE_GROUP${NC}"
    fi
    
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " -r
    echo ""
    
    if [[ "$REPLY" != "DELETE" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_info "Deletion confirmed by user"
}

cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    # Remove configuration file
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        log_success "Configuration file removed: $CONFIG_FILE"
    fi
    
    # Remove .env file if it exists
    local env_file="${SCRIPT_DIR}/.env"
    if [[ -f "$env_file" ]]; then
        rm -f "$env_file"
        log_success "Environment file removed: $env_file"
    fi
    
    log_success "Local cleanup completed"
}

print_deletion_summary() {
    echo ""
    echo -e "${GREEN}=============================================================="
    echo "Deletion Summary"
    echo -e "==============================================================${NC}"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE - No resources were actually deleted${NC}"
    else
        echo "Resource Group: $RESOURCE_GROUP"
        echo ""
        echo "Deleted Resources:"
        echo "  🗑️  Monitoring Resources (Alert Rules, Log Analytics)"
        echo "  🗑️  Logic Apps"
        echo "  🗑️  Cognitive Services (Metrics Advisor, Immersive Reader)"
        echo "  🗑️  Storage Accounts"
        
        if [[ "$KEEP_RESOURCE_GROUP" == "true" ]]; then
            echo "  ✅  Resource Group (Preserved)"
        else
            echo "  🗑️  Resource Group (Deletion in progress)"
        fi
        
        echo ""
        echo "Cleanup log: $LOG_FILE"
        echo ""
        echo -e "${GREEN}Cleanup completed successfully!${NC}"
        
        if [[ "$KEEP_RESOURCE_GROUP" != "true" ]]; then
            echo ""
            echo -e "${YELLOW}Note: Resource group deletion may take several minutes to complete${NC}"
            echo "You can check the status with: az group show --name $RESOURCE_GROUP"
        fi
    fi
}

main() {
    # Initialize logging
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    print_banner
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DELETION="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --keep-rg)
                KEEP_RESOURCE_GROUP="true"
                shift
                ;;
            --config-file)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Set default values
    FORCE_DELETION="${FORCE_DELETION:-false}"
    DRY_RUN="${DRY_RUN:-false}"
    KEEP_RESOURCE_GROUP="${KEEP_RESOURCE_GROUP:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in dry-run mode - no resources will be deleted"
    fi
    
    # Load configuration
    load_config
    
    # Validate prerequisites
    validate_prerequisites
    
    # Confirm deletion
    confirm_deletion
    
    # Execute deletion
    log_info "Starting deletion process..."
    
    # Delete resources in reverse order of creation
    delete_monitoring_resources
    delete_logic_apps
    delete_cognitive_services
    delete_storage_accounts
    
    # Delete resource group last (if requested)
    delete_resource_group
    
    # Wait for resources to be deleted
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Waiting for resources to be deleted..."
        sleep 15
        verify_deletion
        cleanup_local_files
    fi
    
    print_deletion_summary
}

# =============================================================================
# Error Handling
# =============================================================================

cleanup_on_error() {
    log_error "Cleanup failed. Check $LOG_FILE for details."
    echo ""
    echo "Some resources may still exist. You can:"
    echo "  - Re-run this script to retry deletion"
    echo "  - Manually delete resources via Azure Portal"
    echo "  - Use 'az group delete --name $RESOURCE_GROUP' to force delete the entire group"
    exit 1
}

trap cleanup_on_error ERR

# =============================================================================
# Script Execution
# =============================================================================

main "$@"