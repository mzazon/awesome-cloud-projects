#!/bin/bash

# =============================================================================
# Destroy Script for Smart Email Template Generation with Gemini and Firestore
# 
# This script safely removes all infrastructure created by the deploy script
# for the AI-powered email template generation system.
#
# Resources removed:
# - Cloud Function (2nd gen)
# - Firestore Database
# - Local function directory and files
# - Environment variables and temporary files
#
# Note: APIs are not disabled by default to avoid affecting other resources
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if user is authenticated with gcloud
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        log_error "No active gcloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
}

# Function to load deployment info
load_deployment_info() {
    if [[ -f .deployment_info ]]; then
        log_info "Loading deployment information from .deployment_info"
        source .deployment_info
        
        # Validate required variables
        local required_vars=("PROJECT_ID" "REGION" "FUNCTION_NAME" "DATABASE_ID")
        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                log_error "Required variable $var not found in deployment info"
                return 1
            fi
        done
        
        log_info "Loaded deployment configuration:"
        log_info "  Project ID: $PROJECT_ID"
        log_info "  Region: $REGION"
        log_info "  Function Name: $FUNCTION_NAME"
        log_info "  Database ID: $DATABASE_ID"
        
        return 0
    else
        return 1
    fi
}

# Function to prompt for manual configuration if deployment info is not found
prompt_manual_config() {
    log_warning "Deployment info file not found. Please provide configuration manually."
    echo
    
    # Get current project from gcloud if possible
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [[ -n "$current_project" ]]; then
        read -p "Project ID [$current_project]: " PROJECT_ID
        PROJECT_ID=${PROJECT_ID:-$current_project}
    else
        read -p "Project ID: " PROJECT_ID
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "Project ID is required"
            exit 1
        fi
    fi
    
    read -p "Region [us-central1]: " REGION
    REGION=${REGION:-us-central1}
    
    read -p "Function Name: " FUNCTION_NAME
    if [[ -z "$FUNCTION_NAME" ]]; then
        log_error "Function Name is required"
        exit 1
    fi
    
    read -p "Database ID: " DATABASE_ID
    if [[ -z "$DATABASE_ID" ]]; then
        log_error "Database ID is required"
        exit 1
    fi
    
    # Set optional variables
    FUNCTION_DIR="${FUNCTION_DIR:-./email-template-function}"
    
    log_info "Manual configuration:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Function Name: $FUNCTION_NAME"
    log_info "  Database ID: $DATABASE_ID"
}

# Function to confirm destruction
confirm_destruction() {
    local project_id=$1
    local function_name=$2
    local database_id=$3
    
    echo
    log_warning "==============================================="
    log_warning "           DESTRUCTIVE OPERATION"
    log_warning "==============================================="
    log_warning "This will permanently delete the following resources:"
    log_warning "  • Cloud Function: $function_name"
    log_warning "  • Firestore Database: $database_id"
    log_warning "  • All data stored in the database"
    log_warning "  • Local function directory and files"
    log_warning ""
    log_warning "Project: $project_id"
    log_warning "==============================================="
    echo
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    echo
    log_warning "Final confirmation: Type 'DELETE' to proceed with destruction:"
    read -p "> " final_confirm
    if [[ "$final_confirm" != "DELETE" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Function to delete Cloud Function
delete_cloud_function() {
    local function_name=$1
    local region=$2
    local project_id=$3
    
    log_info "Checking if Cloud Function exists: $function_name"
    
    # Check if function exists
    if ! gcloud functions describe "$function_name" \
        --gen2 \
        --region="$region" \
        --project="$project_id" >/dev/null 2>&1; then
        log_warning "Cloud Function $function_name not found or already deleted"
        return 0
    fi
    
    log_info "Deleting Cloud Function: $function_name"
    
    # Delete the function
    gcloud functions delete "$function_name" \
        --gen2 \
        --region="$region" \
        --project="$project_id" \
        --quiet
    
    # Wait for deletion to complete
    log_info "Waiting for function deletion to complete..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ! gcloud functions describe "$function_name" \
            --gen2 \
            --region="$region" \
            --project="$project_id" >/dev/null 2>&1; then
            log_success "Cloud Function deleted successfully"
            break
        fi
        log_info "Attempt $attempt/$max_attempts: Waiting for function deletion..."
        sleep 5
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_warning "Timeout waiting for function deletion, but continuing..."
    fi
}

# Function to delete Firestore database
delete_firestore_database() {
    local database_id=$1
    local project_id=$2
    
    log_info "Checking if Firestore database exists: $database_id"
    
    # Check if database exists
    if ! gcloud firestore databases describe "$database_id" \
        --project="$project_id" >/dev/null 2>&1; then
        log_warning "Firestore database $database_id not found or already deleted"
        return 0
    fi
    
    log_warning "Deleting Firestore database: $database_id"
    log_warning "This will permanently delete all data in the database!"
    
    # Delete the database
    gcloud firestore databases delete "$database_id" \
        --project="$project_id" \
        --quiet
    
    log_success "Firestore database deletion initiated: $database_id"
    log_info "Note: Database deletion may take several minutes to complete"
}

# Function to clean up local files
cleanup_local_files() {
    local function_dir=$1
    
    log_info "Cleaning up local files and directories..."
    
    # Remove function directory if it exists
    if [[ -d "$function_dir" ]]; then
        log_info "Removing function directory: $function_dir"
        rm -rf "$function_dir"
        log_success "Function directory removed"
    else
        log_warning "Function directory not found: $function_dir"
    fi
    
    # Remove temporary files
    local temp_files=(
        "/tmp/init_firestore_data.py"
        "/tmp/function_url.txt"
        ".deployment_info"
        "init_firestore_data.py"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing temporary file: $file"
            rm -f "$file"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to clear environment variables
clear_environment_variables() {
    log_info "Clearing environment variables..."
    
    local env_vars=(
        "PROJECT_ID"
        "REGION"
        "ZONE"
        "FUNCTION_NAME"
        "DATABASE_ID"
        "FUNCTION_URL"
        "FUNCTION_DIR"
        "RANDOM_SUFFIX"
    )
    
    for var in "${env_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            unset "$var"
            log_info "Cleared: $var"
        fi
    done
    
    log_success "Environment variables cleared"
}

# Function to offer API disabling (optional)
offer_api_disabling() {
    local project_id=$1
    
    echo
    log_info "Optional: Disable APIs to prevent future charges"
    log_warning "WARNING: This will disable APIs for the entire project!"
    log_warning "Only proceed if you're not using these APIs elsewhere in the project:"
    log_warning "  • Cloud Functions API"
    log_warning "  • Firestore API"
    log_warning "  • Vertex AI API"
    log_warning "  • Cloud Build API"
    echo
    
    read -p "Do you want to disable APIs? (yes/no) [no]: " disable_apis
    disable_apis=${disable_apis:-no}
    
    if [[ "$disable_apis" == "yes" ]]; then
        log_info "Disabling APIs..."
        
        local apis=(
            "cloudfunctions.googleapis.com"
            "firestore.googleapis.com"
            "aiplatform.googleapis.com"
            "cloudbuild.googleapis.com"
            "artifactregistry.googleapis.com"
            "run.googleapis.com"
            "eventarc.googleapis.com"
            "pubsub.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log_info "Disabling $api..."
            if gcloud services disable "$api" --project="$project_id" --force --quiet 2>/dev/null; then
                log_success "Disabled: $api"
            else
                log_warning "Failed to disable or already disabled: $api"
            fi
        done
        
        log_success "API disabling completed"
    else
        log_info "APIs left enabled"
    fi
}

# Function to display destruction summary
display_destruction_summary() {
    local project_id=$1
    local function_name=$2
    local database_id=$3
    
    echo
    log_success "=== DESTRUCTION COMPLETED ==="
    echo
    log_success "Successfully removed the following resources:"
    log_success "  ✓ Cloud Function: $function_name"
    log_success "  ✓ Firestore Database: $database_id"
    log_success "  ✓ Local files and directories"
    log_success "  ✓ Environment variables"
    echo
    log_info "Project: $project_id"
    echo
    log_info "All resources have been cleaned up to avoid future charges."
    
    # Check if there are any remaining functions or databases
    log_info "Checking for any remaining Cloud Functions..."
    local remaining_functions
    remaining_functions=$(gcloud functions list --project="$project_id" --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ "$remaining_functions" -gt 0 ]]; then
        log_warning "Note: $remaining_functions other Cloud Functions still exist in this project"
    fi
    
    log_info "Checking for any remaining Firestore databases..."
    local remaining_databases
    remaining_databases=$(gcloud firestore databases list --project="$project_id" --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ "$remaining_databases" -gt 0 ]]; then
        log_warning "Note: $remaining_databases other Firestore databases still exist in this project"
    fi
}

# Function to handle errors during destruction
handle_destruction_error() {
    local error_message=$1
    local resource=$2
    
    log_error "Failed to destroy $resource: $error_message"
    log_warning "You may need to manually clean up this resource in the Google Cloud Console"
    log_warning "Console URL: https://console.cloud.google.com"
}

# Main destruction function
main() {
    log_info "Starting destruction of Smart Email Template Generation system..."
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) not found. Please install it first."
        exit 1
    fi
    
    check_gcloud_auth
    
    # Load deployment configuration
    if ! load_deployment_info; then
        log_warning "Could not load deployment info automatically"
        prompt_manual_config
    fi
    
    # Set gcloud project
    gcloud config set project "$PROJECT_ID"
    
    # Confirm destruction
    confirm_destruction "$PROJECT_ID" "$FUNCTION_NAME" "$DATABASE_ID"
    
    # Start destruction process
    log_info "Beginning resource destruction..."
    
    # Delete Cloud Function
    if ! delete_cloud_function "$FUNCTION_NAME" "$REGION" "$PROJECT_ID"; then
        handle_destruction_error "Cloud Function deletion failed" "Cloud Function"
    fi
    
    # Delete Firestore database
    if ! delete_firestore_database "$DATABASE_ID" "$PROJECT_ID"; then
        handle_destruction_error "Firestore database deletion failed" "Firestore Database"
    fi
    
    # Clean up local files
    cleanup_local_files "${FUNCTION_DIR:-./email-template-function}"
    
    # Clear environment variables
    clear_environment_variables
    
    # Offer to disable APIs
    offer_api_disabling "$PROJECT_ID"
    
    # Display summary
    display_destruction_summary "$PROJECT_ID" "$FUNCTION_NAME" "$DATABASE_ID"
    
    log_success "Destruction completed successfully!"
}

# Error handling
trap 'log_error "Script interrupted. Some resources may not have been cleaned up."' INT TERM

# Run main function
main "$@"