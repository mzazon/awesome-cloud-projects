#!/bin/bash

# =============================================================================
# Azure Enterprise Data Validation Workflow Cleanup Script
# =============================================================================
# This script safely removes all Azure infrastructure created for the
# enterprise-grade data validation workflows solution.
#
# Recipe: Orchestrating Enterprise-Grade Data Validation Workflows
# Services: Azure Dataverse, Azure AI Document Intelligence, Logic Apps, Power Apps
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION AND VARIABLES
# =============================================================================

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy_${TIMESTAMP}.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration
readonly REQUIRED_CLI_VERSION="2.50.0"

# =============================================================================
# LOGGING AND UTILITY FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}❌ $*${NC}" | tee -a "$LOG_FILE"
}

fatal() {
    error "$*"
    exit 1
}

# =============================================================================
# USER CONFIRMATION FUNCTIONS
# =============================================================================

confirm_destruction() {
    local resource_group="$1"
    
    echo ""
    warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo "=========================================="
    echo "This script will permanently delete:"
    echo "  • Resource Group: $resource_group"
    echo "  • All contained Azure resources"
    echo "  • All data stored in these resources"
    echo "=========================================="
    echo ""
    
    # List resources that will be deleted
    if az group exists --name "$resource_group" 2>/dev/null; then
        info "Resources to be deleted:"
        az resource list --resource-group "$resource_group" --query "[].{Name:name,Type:type}" --output table 2>/dev/null || true
        echo ""
    fi
    
    # Multiple confirmation prompts
    read -p "Are you sure you want to delete resource group '$resource_group'? (yes/no): " confirm1
    if [[ "$confirm1" != "yes" ]]; then
        info "Cleanup cancelled by user."
        exit 0
    fi
    
    read -p "This action cannot be undone. Type 'DELETE' to confirm: " confirm2
    if [[ "$confirm2" != "DELETE" ]]; then
        info "Cleanup cancelled by user."
        exit 0
    fi
    
    warning "Final confirmation: delete '$resource_group' in 10 seconds..."
    sleep 5
    warning "Deletion will proceed in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
    
    success "User confirmed destruction of resource group: $resource_group"
}

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        fatal "Azure CLI is not installed. Please install Azure CLI v${REQUIRED_CLI_VERSION} or later."
    fi
    
    # Check Azure CLI version
    local cli_version
    cli_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    if [[ "$(printf '%s\n' "$REQUIRED_CLI_VERSION" "$cli_version" | sort -V | head -n1)" != "$REQUIRED_CLI_VERSION" ]]; then
        fatal "Azure CLI version $REQUIRED_CLI_VERSION or later is required. Current version: $cli_version"
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &>/dev/null; then
        fatal "Please log in to Azure using 'az login' before running this script."
    fi
    
    success "Prerequisites check completed"
}

# =============================================================================
# RESOURCE GROUP DETECTION
# =============================================================================

detect_resource_groups() {
    info "Detecting document validation resource groups..."
    
    # Look for resource groups with the naming pattern
    local resource_groups
    resource_groups=$(az group list --query "[?starts_with(name, 'rg-doc-validation-')].name" --output tsv 2>/dev/null || true)
    
    if [[ -z "$resource_groups" ]]; then
        warning "No document validation resource groups found with pattern 'rg-doc-validation-*'"
        
        # Allow user to specify custom resource group
        read -p "Enter resource group name to delete (or 'exit' to quit): " custom_rg
        if [[ "$custom_rg" == "exit" || -z "$custom_rg" ]]; then
            info "Cleanup cancelled by user."
            exit 0
        fi
        
        if ! az group exists --name "$custom_rg" 2>/dev/null; then
            fatal "Resource group '$custom_rg' does not exist."
        fi
        
        echo "$custom_rg"
    else
        echo "$resource_groups"
    fi
}

# =============================================================================
# INDIVIDUAL RESOURCE CLEANUP FUNCTIONS
# =============================================================================

cleanup_alert_rules() {
    local resource_group="$1"
    
    info "Cleaning up alert rules in resource group: $resource_group"
    
    # Get all alert rules in the resource group
    local alert_rules
    alert_rules=$(az monitor metrics alert list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || true)
    
    if [[ -n "$alert_rules" ]]; then
        while IFS= read -r alert_name; do
            if [[ -n "$alert_name" ]]; then
                info "Deleting alert rule: $alert_name"
                az monitor metrics alert delete \
                    --name "$alert_name" \
                    --resource-group "$resource_group" \
                    --output none 2>/dev/null || warning "Failed to delete alert rule: $alert_name"
            fi
        done <<< "$alert_rules"
        success "Alert rules cleanup completed"
    else
        info "No alert rules found to delete"
    fi
}

cleanup_logic_apps() {
    local resource_group="$1"
    
    info "Cleaning up Logic Apps in resource group: $resource_group"
    
    # Get all Logic Apps in the resource group
    local logic_apps
    logic_apps=$(az logic workflow list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || true)
    
    if [[ -n "$logic_apps" ]]; then
        while IFS= read -r logic_app_name; do
            if [[ -n "$logic_app_name" ]]; then
                info "Deleting Logic App: $logic_app_name"
                az logic workflow delete \
                    --name "$logic_app_name" \
                    --resource-group "$resource_group" \
                    --yes \
                    --output none 2>/dev/null || warning "Failed to delete Logic App: $logic_app_name"
            fi
        done <<< "$logic_apps"
        success "Logic Apps cleanup completed"
    else
        info "No Logic Apps found to delete"
    fi
}

cleanup_cognitive_services() {
    local resource_group="$1"
    
    info "Cleaning up Cognitive Services in resource group: $resource_group"
    
    # Get all Cognitive Services accounts in the resource group
    local cognitive_accounts
    cognitive_accounts=$(az cognitiveservices account list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || true)
    
    if [[ -n "$cognitive_accounts" ]]; then
        while IFS= read -r account_name; do
            if [[ -n "$account_name" ]]; then
                info "Deleting Cognitive Services account: $account_name"
                az cognitiveservices account delete \
                    --name "$account_name" \
                    --resource-group "$resource_group" \
                    --output none 2>/dev/null || warning "Failed to delete Cognitive Services account: $account_name"
            fi
        done <<< "$cognitive_accounts"
        success "Cognitive Services cleanup completed"
    else
        info "No Cognitive Services accounts found to delete"
    fi
}

cleanup_key_vaults() {
    local resource_group="$1"
    
    info "Cleaning up Key Vaults in resource group: $resource_group"
    
    # Get all Key Vaults in the resource group
    local key_vaults
    key_vaults=$(az keyvault list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || true)
    
    if [[ -n "$key_vaults" ]]; then
        while IFS= read -r vault_name; do
            if [[ -n "$vault_name" ]]; then
                info "Deleting Key Vault: $vault_name"
                # Key Vaults require purge protection to be disabled first
                az keyvault delete \
                    --name "$vault_name" \
                    --resource-group "$resource_group" \
                    --output none 2>/dev/null || warning "Failed to delete Key Vault: $vault_name"
                
                # Purge the Key Vault to completely remove it
                info "Purging Key Vault: $vault_name"
                az keyvault purge \
                    --name "$vault_name" \
                    --location "$LOCATION" \
                    --output none 2>/dev/null || warning "Failed to purge Key Vault: $vault_name"
            fi
        done <<< "$key_vaults"
        success "Key Vaults cleanup completed"
    else
        info "No Key Vaults found to delete"
    fi
}

cleanup_storage_accounts() {
    local resource_group="$1"
    
    info "Cleaning up Storage Accounts in resource group: $resource_group"
    
    # Get all Storage Accounts in the resource group
    local storage_accounts
    storage_accounts=$(az storage account list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || true)
    
    if [[ -n "$storage_accounts" ]]; then
        while IFS= read -r storage_name; do
            if [[ -n "$storage_name" ]]; then
                info "Deleting Storage Account: $storage_name"
                az storage account delete \
                    --name "$storage_name" \
                    --resource-group "$resource_group" \
                    --yes \
                    --output none 2>/dev/null || warning "Failed to delete Storage Account: $storage_name"
            fi
        done <<< "$storage_accounts"
        success "Storage Accounts cleanup completed"
    else
        info "No Storage Accounts found to delete"
    fi
}

cleanup_monitoring_resources() {
    local resource_group="$1"
    
    info "Cleaning up monitoring resources in resource group: $resource_group"
    
    # Application Insights
    local app_insights
    app_insights=$(az monitor app-insights component list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || true)
    
    if [[ -n "$app_insights" ]]; then
        while IFS= read -r app_name; do
            if [[ -n "$app_name" ]]; then
                info "Deleting Application Insights: $app_name"
                az monitor app-insights component delete \
                    --app "$app_name" \
                    --resource-group "$resource_group" \
                    --output none 2>/dev/null || warning "Failed to delete Application Insights: $app_name"
            fi
        done <<< "$app_insights"
    fi
    
    # Log Analytics Workspaces
    local workspaces
    workspaces=$(az monitor log-analytics workspace list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || true)
    
    if [[ -n "$workspaces" ]]; then
        while IFS= read -r workspace_name; do
            if [[ -n "$workspace_name" ]]; then
                info "Deleting Log Analytics Workspace: $workspace_name"
                az monitor log-analytics workspace delete \
                    --resource-group "$resource_group" \
                    --workspace-name "$workspace_name" \
                    --yes \
                    --force true \
                    --output none 2>/dev/null || warning "Failed to delete Log Analytics Workspace: $workspace_name"
            fi
        done <<< "$workspaces"
    fi
    
    success "Monitoring resources cleanup completed"
}

# =============================================================================
# MAIN CLEANUP FUNCTIONS
# =============================================================================

cleanup_individual_resources() {
    local resource_group="$1"
    
    info "Performing individual resource cleanup before resource group deletion..."
    
    # Get location from resource group for Key Vault purging
    export LOCATION=$(az group show --name "$resource_group" --query location --output tsv 2>/dev/null || echo "eastus")
    
    # Clean up resources in dependency order (reverse of creation)
    cleanup_alert_rules "$resource_group"
    cleanup_monitoring_resources "$resource_group"
    cleanup_logic_apps "$resource_group"
    cleanup_key_vaults "$resource_group"
    cleanup_cognitive_services "$resource_group"
    cleanup_storage_accounts "$resource_group"
    
    success "Individual resource cleanup completed"
}

delete_resource_group() {
    local resource_group="$1"
    
    info "Deleting resource group: $resource_group"
    
    # Check if resource group exists
    if ! az group exists --name "$resource_group" 2>/dev/null; then
        warning "Resource group '$resource_group' does not exist or has already been deleted."
        return 0
    fi
    
    # Delete the resource group
    info "Initiating resource group deletion (this may take several minutes)..."
    az group delete \
        --name "$resource_group" \
        --yes \
        --no-wait \
        --output none
    
    # Wait for deletion to complete with progress updates
    local wait_count=0
    local max_wait=120  # 10 minutes maximum wait
    
    while az group exists --name "$resource_group" 2>/dev/null && [[ $wait_count -lt $max_wait ]]; do
        info "Waiting for resource group deletion to complete... ($((wait_count * 5)) seconds elapsed)"
        sleep 5
        ((wait_count++))
    done
    
    if az group exists --name "$resource_group" 2>/dev/null; then
        warning "Resource group deletion is taking longer than expected."
        warning "The deletion is still in progress. Check Azure portal for status."
        info "Resource group: $resource_group"
    else
        success "Resource group deleted successfully: $resource_group"
    fi
}

# =============================================================================
# CLEANUP CONFIGURATION FILES
# =============================================================================

cleanup_local_files() {
    info "Cleaning up local configuration files..."
    
    # Remove validation configuration files if they exist
    local config_files=(
        "${SCRIPT_DIR}/validation-rules.json"
        "${SCRIPT_DIR}/powerapp-config.json"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            info "Removing configuration file: $(basename "$config_file")"
            rm -f "$config_file" || warning "Failed to remove: $config_file"
        fi
    done
    
    # Remove old log files (keep last 5)
    info "Cleaning up old log files..."
    find "$SCRIPT_DIR" -name "deploy_*.log" -type f -exec ls -t {} + | tail -n +6 | xargs rm -f 2>/dev/null || true
    find "$SCRIPT_DIR" -name "destroy_*.log" -type f -exec ls -t {} + | tail -n +6 | xargs rm -f 2>/dev/null || true
    
    success "Local cleanup completed"
}

# =============================================================================
# POWER PLATFORM CLEANUP GUIDANCE
# =============================================================================

display_power_platform_cleanup() {
    info "Power Platform Cleanup Guidance"
    echo "=========================================" | tee -a "$LOG_FILE"
    warning "Manual cleanup required for Power Platform resources:" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "1. Power Platform Environment:" | tee -a "$LOG_FILE"
    echo "   • Go to: https://admin.powerplatform.microsoft.com/environments" | tee -a "$LOG_FILE"
    echo "   • Delete environment: DocValidationProd (or your custom environment)" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "2. Dataverse Custom Tables:" | tee -a "$LOG_FILE"
    echo "   • Access: Power Platform Admin Center > Environments > [Environment] > Settings" | tee -a "$LOG_FILE"
    echo "   • Remove custom tables and business rules created for document validation" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "3. Power Apps Applications:" | tee -a "$LOG_FILE"
    echo "   • Go to: https://make.powerapps.com" | tee -a "$LOG_FILE"
    echo "   • Delete the Document Validation App and any related Power Apps" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "4. SharePoint Connections:" | tee -a "$LOG_FILE"
    echo "   • Remove any SharePoint document libraries configured for document processing" | tee -a "$LOG_FILE"
    echo "   • Clean up SharePoint permissions and workflow configurations" | tee -a "$LOG_FILE"
    echo "=========================================" | tee -a "$LOG_FILE"
}

# =============================================================================
# CLEANUP SUMMARY
# =============================================================================

display_cleanup_summary() {
    local resource_groups="$1"
    
    info "Cleanup Summary"
    echo "===========================================" | tee -a "$LOG_FILE"
    echo "Cleaned up resource groups:" | tee -a "$LOG_FILE"
    while IFS= read -r rg; do
        if [[ -n "$rg" ]]; then
            echo "  ✅ $rg" | tee -a "$LOG_FILE"
        fi
    done <<< "$resource_groups"
    echo "" | tee -a "$LOG_FILE"
    echo "Cleanup completed at: $(date)" | tee -a "$LOG_FILE"
    echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "===========================================" | tee -a "$LOG_FILE"
}

# =============================================================================
# MAIN CLEANUP FUNCTION
# =============================================================================

main() {
    echo "=========================================="
    echo "Azure Enterprise Data Validation Workflow"
    echo "Cleanup Script v1.0"
    echo "=========================================="
    echo ""
    
    # Check for dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        info "Running in dry-run mode. No resources will be deleted."
        export DRY_RUN=true
    fi
    
    # Initialize log file
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    # Execute cleanup steps
    check_prerequisites
    
    # Detect resource groups to clean up
    local resource_groups
    resource_groups=$(detect_resource_groups)
    
    if [[ -z "$resource_groups" ]]; then
        info "No resource groups found to clean up."
        exit 0
    fi
    
    # Process each resource group
    while IFS= read -r resource_group; do
        if [[ -n "$resource_group" ]]; then
            info "Processing resource group: $resource_group"
            
            # Skip confirmation in dry-run mode
            if [[ "${DRY_RUN:-}" != "true" ]]; then
                confirm_destruction "$resource_group"
                cleanup_individual_resources "$resource_group"
                delete_resource_group "$resource_group"
            else
                info "DRY RUN: Would delete resource group: $resource_group"
            fi
        fi
    done <<< "$resource_groups"
    
    # Clean up local files
    if [[ "${DRY_RUN:-}" != "true" ]]; then
        cleanup_local_files
    else
        info "DRY RUN: Would clean up local configuration files"
    fi
    
    # Display Power Platform cleanup guidance
    display_power_platform_cleanup
    
    # Display summary
    display_cleanup_summary "$resource_groups"
    
    success "Cleanup completed successfully!"
    success "Log file saved to: $LOG_FILE"
    
    warning "Don't forget to manually clean up Power Platform resources as shown above."
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Handle script interruption
trap 'error "Script interrupted. Check log file: $LOG_FILE"; exit 1' INT TERM

# Execute main function with all arguments
main "$@"