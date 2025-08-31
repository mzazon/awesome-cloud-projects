#!/bin/bash

# Currency Converter API with Cloud Functions - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
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

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Command '$1' not found. Please install it before running this script."
        exit 1
    fi
}

# Function to prompt for user confirmation
confirm_action() {
    local message=$1
    local response
    
    read -p "$message (y/N): " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local additional_flags=${3:-}
    
    gcloud "$resource_type" describe "$resource_name" $additional_flags &>/dev/null
}

# Function to load deployment information
load_deployment_info() {
    if [[ -f ".deployment_info" ]]; then
        log_info "Loading deployment information from .deployment_info"
        source .deployment_info
        return 0
    else
        log_warning "No .deployment_info file found. You'll need to provide resource names manually."
        return 1
    fi
}

# Function to prompt for resource information
prompt_for_resources() {
    log_info "Please provide the following information for cleanup:"
    
    # Project ID
    if [[ -z "${PROJECT_ID:-}" ]]; then
        read -p "Project ID: " PROJECT_ID
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "Project ID is required"
            exit 1
        fi
    fi
    
    # Region
    if [[ -z "${REGION:-}" ]]; then
        read -p "Region (default: us-central1): " REGION
        REGION=${REGION:-"us-central1"}
    fi
    
    # Function name
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        read -p "Function name (default: currency-converter): " FUNCTION_NAME
        FUNCTION_NAME=${FUNCTION_NAME:-"currency-converter"}
    fi
    
    # Secret name
    if [[ -z "${SECRET_NAME:-}" ]]; then
        log_info "Listing existing secrets to help you choose:"
        gcloud secrets list --format="table(name)" --filter="name~exchange-api-key" || true
        read -p "Secret name: " SECRET_NAME
        if [[ -z "$SECRET_NAME" ]]; then
            log_warning "No secret name provided. Skipping secret deletion."
        fi
    fi
    
    export PROJECT_ID REGION FUNCTION_NAME SECRET_NAME
}

# Function to delete Cloud Function
delete_function() {
    local function_name=$1
    local region=$2
    
    log_info "Checking if function '$function_name' exists in region '$region'..."
    
    if resource_exists "functions" "$function_name" "--region=$region"; then
        log_info "Deleting Cloud Function: $function_name"
        
        if gcloud functions delete "$function_name" \
            --region="$region" \
            --quiet; then
            log_success "Function '$function_name' deleted successfully"
            return 0
        else
            log_error "Failed to delete function '$function_name'"
            return 1
        fi
    else
        log_warning "Function '$function_name' not found in region '$region'"
        return 0
    fi
}

# Function to delete Secret Manager secret
delete_secret() {
    local secret_name=$1
    
    if [[ -z "$secret_name" ]]; then
        log_warning "No secret name provided. Skipping secret deletion."
        return 0
    fi
    
    log_info "Checking if secret '$secret_name' exists..."
    
    if resource_exists "secrets" "$secret_name"; then
        log_info "Deleting Secret Manager secret: $secret_name"
        
        if gcloud secrets delete "$secret_name" --quiet; then
            log_success "Secret '$secret_name' deleted successfully"
            return 0
        else
            log_error "Failed to delete secret '$secret_name'"
            return 1
        fi
    else
        log_warning "Secret '$secret_name' not found"
        return 0
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(".deployment_info")
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if rm "$file"; then
                log_success "Removed local file: $file"
            else
                log_warning "Failed to remove local file: $file"
            fi
        fi
    done
}

# Function to list remaining resources (for verification)
list_remaining_resources() {
    log_info "Checking for any remaining resources..."
    
    # List any remaining functions
    log_info "Remaining Cloud Functions:"
    gcloud functions list --regions="$REGION" --format="table(name,status,trigger.httpsTrigger.url)" || log_warning "Could not list functions"
    
    # List any remaining secrets
    log_info "Remaining secrets (with 'exchange-api-key' in name):"
    gcloud secrets list --format="table(name,createTime)" --filter="name~exchange-api-key" || log_warning "Could not list secrets"
}

# Main cleanup function
cleanup_currency_converter() {
    log_info "Starting Currency Converter API cleanup..."
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    check_command "gcloud"
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &>/dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Try to load deployment information or prompt for it
    if ! load_deployment_info; then
        prompt_for_resources
    fi
    
    log_info "Cleanup configuration:"
    log_info "  Project ID: ${PROJECT_ID:-'Not set'}"
    log_info "  Region: ${REGION:-'Not set'}"
    log_info "  Function Name: ${FUNCTION_NAME:-'Not set'}"
    log_info "  Secret Name: ${SECRET_NAME:-'Not set'}"
    
    # Set gcloud project
    if [[ -n "${PROJECT_ID:-}" ]]; then
        log_info "Setting gcloud project..."
        gcloud config set project "$PROJECT_ID" || {
            log_error "Failed to set project. Make sure the project exists and you have access."
            exit 1
        }
    fi
    
    # Confirm cleanup
    echo
    log_warning "This will permanently delete the following resources:"
    log_warning "  - Cloud Function: ${FUNCTION_NAME:-'Not specified'}"
    log_warning "  - Secret Manager Secret: ${SECRET_NAME:-'Not specified'}"
    log_warning "  - Local deployment files"
    echo
    
    if ! confirm_action "Are you sure you want to proceed with cleanup?"; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    # Track cleanup results
    local cleanup_errors=0
    
    # Delete Cloud Function
    if [[ -n "${FUNCTION_NAME:-}" ]] && [[ -n "${REGION:-}" ]]; then
        if ! delete_function "$FUNCTION_NAME" "$REGION"; then
            ((cleanup_errors++))
        fi
    else
        log_warning "Function name or region not specified. Skipping function deletion."
    fi
    
    # Delete Secret Manager secret
    if ! delete_secret "${SECRET_NAME:-}"; then
        ((cleanup_errors++))
    fi
    
    # Clean up local files
    cleanup_local_files
    
    # List remaining resources for verification
    echo
    list_remaining_resources
    
    # Display cleanup summary
    echo
    if [[ $cleanup_errors -eq 0 ]]; then
        log_success "=== CLEANUP COMPLETE ==="
        log_success "All resources have been successfully removed."
    else
        log_warning "=== CLEANUP COMPLETED WITH ERRORS ==="
        log_warning "$cleanup_errors error(s) occurred during cleanup."
        log_info "Please check the output above and manually remove any remaining resources."
    fi
    
    # Final recommendations
    echo
    log_info "Additional cleanup recommendations:"
    log_info "  - Check Cloud Functions logs if you need them for debugging"
    log_info "  - Review your project for any other related resources"
    log_info "  - Consider disabling unused APIs if they're no longer needed:"
    log_info "    - Cloud Functions API"
    log_info "    - Secret Manager API"
    log_info "    - Cloud Build API"
    
    return $cleanup_errors
}

# Function to show help
show_help() {
    echo "Currency Converter API Cleanup Script"
    echo "======================================"
    echo
    echo "This script removes all resources created by the deployment script."
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -f, --force             Skip confirmation prompts (use with caution)"
    echo "  --project PROJECT_ID    Specify project ID instead of using .deployment_info"
    echo "  --region REGION         Specify region (default: us-central1)"
    echo "  --function FUNCTION     Specify function name (default: currency-converter)"
    echo "  --secret SECRET         Specify secret name"
    echo
    echo "Examples:"
    echo "  $0                      # Interactive cleanup using .deployment_info"
    echo "  $0 --force              # Non-interactive cleanup"
    echo "  $0 --project my-project --function my-converter"
    echo
    echo "The script will attempt to load resource information from .deployment_info"
    echo "If this file is not found, you will be prompted to enter the information manually."
}

# Parse command line arguments
parse_arguments() {
    local force_cleanup=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force)
                force_cleanup=true
                shift
                ;;
            --project)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --function)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            --secret)
                SECRET_NAME="$2"
                shift 2
                ;;
            *)
                log_error "Unknown argument: $1"
                echo "Use -h or --help for usage information."
                exit 1
                ;;
        esac
    done
    
    # Override confirmation function if force flag is set
    if [[ "$force_cleanup" == "true" ]]; then
        confirm_action() {
            log_info "Force mode enabled. Proceeding with: $1"
            return 0
        }
    fi
}

# Main execution
main() {
    log_info "Currency Converter API Cleanup Script"
    log_info "====================================="
    
    parse_arguments "$@"
    cleanup_currency_converter
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "Cleanup completed successfully!"
    else
        log_error "Cleanup completed with errors. Exit code: $exit_code"
    fi
    
    exit $exit_code
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi