#!/bin/bash

###################################################################################
# Azure Voice Recording Analysis Cleanup Script
# 
# This script safely removes all Azure resources created by the deployment script
# with proper confirmation prompts and comprehensive cleanup validation.
###################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

###################################################################################
# Utility Functions
###################################################################################

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$message [Y/n]: " -r response
            response=${response:-y}
        else
            read -p "$message [y/N]: " -r response
            response=${response:-n}
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local check_command="$3"
    local max_attempts=60
    local attempt=1
    
    log_info "Waiting for $resource_type '$resource_name' to be deleted..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if ! eval "$check_command" &> /dev/null; then
            log_success "$resource_type '$resource_name' deleted successfully"
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_warning "$resource_type '$resource_name' deletion timed out"
            return 1
        fi
        
        if [[ $((attempt % 10)) -eq 0 ]]; then
            log_info "Still waiting for $resource_type deletion... (${attempt}/${max_attempts})"
        fi
        
        sleep 10
        ((attempt++))
    done
}

###################################################################################
# Prerequisites Check
###################################################################################

check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if deployment state file exists
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        log_error "Deployment state file not found: $DEPLOYMENT_STATE_FILE"
        log_error "Cannot proceed with cleanup without deployment information."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

###################################################################################
# Load Deployment State
###################################################################################

load_deployment_state() {
    log_info "Loading deployment state..."
    
    # Source the deployment state file
    source "$DEPLOYMENT_STATE_FILE"
    
    # Validate required variables
    local required_vars=("RESOURCE_GROUP" "STORAGE_ACCOUNT" "SPEECH_SERVICE" "FUNCTION_APP" "LOCATION")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required variables in deployment state: ${missing_vars[*]}"
        exit 1
    fi
    
    log_info "Loaded deployment state:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Storage Account: $STORAGE_ACCOUNT"
    log_info "  Speech Service: $SPEECH_SERVICE"
    log_info "  Function App: $FUNCTION_APP"
    log_info "  Deployment Time: ${DEPLOYMENT_TIMESTAMP:-unknown}"
    
    log_success "Deployment state loaded successfully"
}

###################################################################################
# Resource Inventory
###################################################################################

inventory_resources() {
    log_info "Inventorying resources to be deleted..."
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' not found"
        return 1
    fi
    
    # Get list of all resources in the resource group
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null || echo "")
    
    if [[ -n "$resources" ]]; then
        log_info "Resources found in '$RESOURCE_GROUP':"
        echo "$resources" | tail -n +3  # Skip header lines
        echo ""
        
        # Count resources
        local resource_count
        resource_count=$(echo "$resources" | tail -n +3 | wc -l)
        log_info "Total resources to be deleted: $resource_count"
    else
        log_warning "No resources found in resource group '$RESOURCE_GROUP'"
    fi
    
    return 0
}

###################################################################################
# Data Backup Warning
###################################################################################

warn_about_data_loss() {
    log_warning "🚨 IMPORTANT DATA LOSS WARNING 🚨"
    log_warning ""
    log_warning "This operation will permanently delete:"
    log_warning "  • All audio files in blob storage containers"
    log_warning "  • All generated transcripts"
    log_warning "  • Azure AI Speech service configuration"
    log_warning "  • Azure Functions code and logs"
    log_warning "  • All associated resource configurations"
    log_warning ""
    log_warning "💾 If you need to preserve any data, please back it up now:"
    log_warning ""
    log_warning "  1. Download audio files from 'audio-input' container"
    log_warning "  2. Download transcripts from 'transcripts' container"
    log_warning "  3. Export any Function App logs or configuration"
    log_warning ""
    
    if ! confirm_action "Have you backed up any data you want to keep?"; then
        log_info "Cleanup cancelled by user. Please backup your data first."
        exit 0
    fi
}

###################################################################################
# Individual Resource Cleanup
###################################################################################

cleanup_function_app() {
    log_info "Cleaning up Function App: $FUNCTION_APP"
    
    # Check if Function App exists
    if ! az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Function App '$FUNCTION_APP' not found"
        return 0
    fi
    
    # Stop the Function App first
    log_info "Stopping Function App..."
    az functionapp stop --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" || true
    
    # Delete the Function App
    log_info "Deleting Function App..."
    az functionapp delete \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" || {
        log_error "Failed to delete Function App '$FUNCTION_APP'"
        return 1
    }
    
    # Wait for deletion to complete
    wait_for_deletion "Function App" "$FUNCTION_APP" \
        "az functionapp show --name '$FUNCTION_APP' --resource-group '$RESOURCE_GROUP'"
    
    log_success "Function App cleanup completed"
}

cleanup_speech_service() {
    log_info "Cleaning up Speech Service: $SPEECH_SERVICE"
    
    # Check if Speech service exists
    if ! az cognitiveservices account show --name "$SPEECH_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Speech Service '$SPEECH_SERVICE' not found"
        return 0
    fi
    
    # Delete the Speech service
    log_info "Deleting Speech Service..."
    az cognitiveservices account delete \
        --name "$SPEECH_SERVICE" \
        --resource-group "$RESOURCE_GROUP" || {
        log_error "Failed to delete Speech Service '$SPEECH_SERVICE'"
        return 1
    }
    
    # Wait for deletion to complete
    wait_for_deletion "Speech Service" "$SPEECH_SERVICE" \
        "az cognitiveservices account show --name '$SPEECH_SERVICE' --resource-group '$RESOURCE_GROUP'"
    
    log_success "Speech Service cleanup completed"
}

cleanup_storage_account() {
    log_info "Cleaning up Storage Account: $STORAGE_ACCOUNT"
    
    # Check if Storage Account exists
    if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Storage Account '$STORAGE_ACCOUNT' not found"
        return 0
    fi
    
    # List and warn about data in containers
    local storage_connection
    storage_connection=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$storage_connection" ]]; then
        log_info "Checking storage containers for data..."
        
        # Check audio-input container
        local audio_count
        audio_count=$(az storage blob list \
            --container-name "audio-input" \
            --connection-string "$storage_connection" \
            --query "length(@)" --output tsv 2>/dev/null || echo "0")
        
        # Check transcripts container
        local transcript_count
        transcript_count=$(az storage blob list \
            --container-name "transcripts" \
            --connection-string "$storage_connection" \
            --query "length(@)" --output tsv 2>/dev/null || echo "0")
        
        if [[ "$audio_count" -gt 0 || "$transcript_count" -gt 0 ]]; then
            log_warning "Found data in storage containers:"
            log_warning "  Audio files: $audio_count"
            log_warning "  Transcripts: $transcript_count"
        fi
    fi
    
    # Delete the Storage Account
    log_info "Deleting Storage Account..."
    az storage account delete \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --yes || {
        log_error "Failed to delete Storage Account '$STORAGE_ACCOUNT'"
        return 1
    }
    
    # Wait for deletion to complete
    wait_for_deletion "Storage Account" "$STORAGE_ACCOUNT" \
        "az storage account show --name '$STORAGE_ACCOUNT' --resource-group '$RESOURCE_GROUP'"
    
    log_success "Storage Account cleanup completed"
}

###################################################################################
# Resource Group Cleanup
###################################################################################

cleanup_resource_group() {
    log_info "Cleaning up Resource Group: $RESOURCE_GROUP"
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' not found"
        return 0
    fi
    
    # Final confirmation for resource group deletion
    log_warning "⚠️  FINAL CONFIRMATION REQUIRED ⚠️"
    log_warning "About to delete resource group '$RESOURCE_GROUP' and ALL remaining resources."
    
    if ! confirm_action "Are you absolutely sure you want to proceed?"; then
        log_info "Resource group deletion cancelled by user."
        return 1
    fi
    
    # Delete the resource group and all remaining resources
    log_info "Deleting resource group and all remaining resources..."
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait || {
        log_error "Failed to initiate resource group deletion"
        return 1
    }
    
    log_info "Resource group deletion initiated (running in background)"
    log_info "You can check status with: az group show --name '$RESOURCE_GROUP'"
    
    # Wait for resource group deletion
    wait_for_deletion "Resource Group" "$RESOURCE_GROUP" \
        "az group show --name '$RESOURCE_GROUP'"
    
    log_success "Resource group cleanup completed"
}

###################################################################################
# Cleanup State Files
###################################################################################

cleanup_local_files() {
    log_info "Cleaning up local state files..."
    
    # Remove deployment state file
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
        log_success "Removed deployment state file"
    fi
    
    # Clean up any temporary files
    local temp_files=("${SCRIPT_DIR}/.func_temp" "${SCRIPT_DIR}/function-*.zip")
    for pattern in "${temp_files[@]}"; do
        # Use shell expansion safely
        for file in $pattern; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                log_info "Removed temporary file: $(basename "$file")"
            fi
        done 2>/dev/null || true
    done
    
    log_success "Local cleanup completed"
}

###################################################################################
# Cost Verification
###################################################################################

verify_cost_cleanup() {
    log_info "Verifying cost cleanup..."
    
    # Check for any remaining billable resources
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    
    # Look for resources that might still be billing
    local remaining_resources
    remaining_resources=$(az resource list \
        --query "[?resourceGroup=='$RESOURCE_GROUP']" \
        --output table 2>/dev/null || echo "")
    
    if [[ -n "$remaining_resources" && $(echo "$remaining_resources" | wc -l) -gt 2 ]]; then
        log_warning "Some resources may still exist in subscription:"
        echo "$remaining_resources"
        log_warning "Please verify these are cleaned up to avoid ongoing charges."
    else
        log_success "No remaining resources found in resource group"
    fi
    
    # Provide cost monitoring advice
    log_info "💰 Cost Monitoring Recommendations:"
    log_info "  1. Check your Azure Cost Management dashboard in 24-48 hours"
    log_info "  2. Verify no charges appear for deleted resources"
    log_info "  3. Set up billing alerts for your subscription"
    log_info "  4. Review: https://portal.azure.com/#blade/Microsoft_Azure_CostManagement/Menu/overview"
}

###################################################################################
# Main Cleanup Function
###################################################################################

main() {
    log_info "Starting Azure Voice Recording Analysis cleanup..."
    log_info "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    
    # Handle script arguments
    local force_cleanup=false
    local skip_confirmations=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_cleanup=true
                shift
                ;;
            --yes)
                skip_confirmations=true
                shift
                ;;
            --help)
                echo "Usage: $0 [--force] [--yes]"
                echo "  --force    Skip resource inventory and proceed directly"
                echo "  --yes      Skip all confirmation prompts (dangerous!)"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    check_prerequisites
    load_deployment_state
    
    # Skip inventory and warnings if force flag is used
    if [[ "$force_cleanup" == "false" ]]; then
        if ! inventory_resources; then
            log_info "No resources found to clean up."
            cleanup_local_files
            exit 0
        fi
        
        if [[ "$skip_confirmations" == "false" ]]; then
            warn_about_data_loss
            
            # Final go/no-go confirmation
            if ! confirm_action "Proceed with complete resource cleanup?"; then
                log_info "Cleanup cancelled by user."
                exit 0
            fi
        fi
    fi
    
    # Perform cleanup in reverse order of creation
    log_info "🧹 Starting resource cleanup process..."
    
    # Individual resource cleanup (more controlled)
    cleanup_function_app || log_warning "Function App cleanup encountered issues"
    cleanup_speech_service || log_warning "Speech Service cleanup encountered issues"
    cleanup_storage_account || log_warning "Storage Account cleanup encountered issues"
    
    # Final resource group cleanup
    cleanup_resource_group || log_warning "Resource Group cleanup encountered issues"
    
    # Clean up local state
    cleanup_local_files
    
    # Verify cost cleanup
    verify_cost_cleanup
    
    log_success "🎉 Cleanup completed successfully!"
    log_info ""
    log_info "📋 Cleanup Summary:"
    log_info "  ✅ Resource Group: $RESOURCE_GROUP (deleted)"
    log_info "  ✅ Function App: $FUNCTION_APP (deleted)"
    log_info "  ✅ Speech Service: $SPEECH_SERVICE (deleted)"
    log_info "  ✅ Storage Account: $STORAGE_ACCOUNT (deleted)"
    log_info "  ✅ Local state files (cleaned)"
    log_info ""
    log_info "💡 Next Steps:"
    log_info "  1. Monitor your Azure billing for 24-48 hours"
    log_info "  2. Verify no unexpected charges appear"
    log_info "  3. Consider setting up billing alerts"
    log_info ""
    log_info "📝 Full cleanup log available at: $LOG_FILE"
    log_success "All Azure resources have been successfully removed! 🧹✨"
}

# Handle script interruption
cleanup_script_interrupt() {
    log_warning "Script interrupted. Cleanup may be incomplete."
    log_warning "You may need to manually verify resource deletion in Azure Portal."
    exit 130
}

trap cleanup_script_interrupt SIGINT SIGTERM

# Run main function
main "$@"