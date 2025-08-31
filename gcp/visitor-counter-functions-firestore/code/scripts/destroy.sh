#!/bin/bash

# Visitor Counter with Cloud Functions and Firestore - Cleanup Script
# This script removes all resources created by the deployment script
# 
# Requirements:
# - Google Cloud SDK (gcloud) installed and configured
# - Appropriate GCP permissions for Cloud Functions, Firestore, and IAM
# 
# Usage: ./destroy.sh [PROJECT_ID] [REGION]

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FUNCTION_DIR="${SCRIPT_DIR}/../function"
readonly DEFAULT_REGION="us-central1"
readonly FUNCTION_NAME="visit-counter"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Help function
show_help() {
    cat << EOF
Visitor Counter Cleanup Script

USAGE:
    $0 [PROJECT_ID] [REGION]

ARGUMENTS:
    PROJECT_ID  Google Cloud Project ID (optional, will use current gcloud config)
    REGION      GCP region where resources were deployed (default: ${DEFAULT_REGION})

EXAMPLES:
    $0                                    # Use current gcloud project and default region
    $0 my-project-123                     # Use specific project
    $0 my-project-123 us-east1           # Use specific project and region

WARNINGS:
    - This will permanently delete the Cloud Function
    - Firestore data will be deleted (if you choose to delete the database)
    - This action cannot be undone

WHAT GETS DELETED:
    - Cloud Function: $FUNCTION_NAME
    - Firestore data (optional)
    - Local function source code (optional)

For more information, see the README.md file.
EOF
}

# Confirm deletion with user
confirm_deletion() {
    local project_id="$1"
    local region="$2"
    
    echo
    echo "=============================================="
    echo "  RESOURCE DELETION CONFIRMATION"
    echo "=============================================="
    echo
    echo "This will delete the following resources:"
    echo "  • Cloud Function: $FUNCTION_NAME"
    echo "  • Region: $region"
    echo "  • Project: $project_id"
    echo
    log_warning "This action cannot be undone!"
    echo
    echo -n "Are you sure you want to proceed? (y/N): "
    read -r confirmation
    
    if [ "$confirmation" != "y" ] && [ "$confirmation" != "Y" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed deletion. Proceeding with cleanup..."
}

# Setup and validate project
setup_project() {
    local project_id="$1"
    
    if [ -z "$project_id" ]; then
        log_info "No project ID provided. Using current gcloud configuration..."
        project_id=$(gcloud config get-value project 2>/dev/null || echo "")
        
        if [ -z "$project_id" ]; then
            log_error "No project configured in gcloud"
            log_error "Please run 'gcloud config set project YOUR_PROJECT_ID' or provide project ID as argument"
            exit 1
        fi
    fi
    
    # Validate project exists and is accessible
    log_info "Validating project: $project_id"
    if ! gcloud projects describe "$project_id" &>/dev/null; then
        log_error "Project '$project_id' does not exist or is not accessible"
        log_error "Please check your project ID and permissions"
        exit 1
    fi
    
    # Set the project
    gcloud config set project "$project_id"
    
    export PROJECT_ID="$project_id"
    log_success "Project set to: $PROJECT_ID"
}

# Check if function exists
check_function_exists() {
    local region="$1"
    
    log_info "Checking if Cloud Function exists..."
    
    if gcloud functions describe "$FUNCTION_NAME" --region="$region" &>/dev/null; then
        log_info "Cloud Function '$FUNCTION_NAME' found in region '$region'"
        return 0
    else
        log_warning "Cloud Function '$FUNCTION_NAME' not found in region '$region'"
        return 1
    fi
}

# Delete Cloud Function
delete_function() {
    local region="$1"
    
    log_info "Deleting Cloud Function: $FUNCTION_NAME"
    
    if gcloud functions delete "$FUNCTION_NAME" \
        --region="$region" \
        --quiet; then
        
        log_success "Cloud Function deleted successfully"
    else
        log_error "Failed to delete Cloud Function"
        log_warning "The function may not exist or you may not have permissions"
    fi
}

# Check Firestore database and data
check_firestore_data() {
    log_info "Checking Firestore data..."
    
    # Check if Firestore database exists
    local db_count
    db_count=$(gcloud firestore databases list --format="value(name)" 2>/dev/null | wc -l)
    
    if [ "$db_count" -eq 0 ]; then
        log_info "No Firestore database found"
        return 1
    fi
    
    # Check if counters collection has documents
    local doc_count
    doc_count=$(gcloud firestore documents list \
        --collection-path=counters \
        --format="value(name)" 2>/dev/null | wc -l) || doc_count=0
    
    if [ "$doc_count" -gt 0 ]; then
        log_info "Found $doc_count document(s) in the 'counters' collection"
        return 0
    else
        log_info "No documents found in the 'counters' collection"
        return 1
    fi
}

# Delete Firestore data
delete_firestore_data() {
    log_info "Deleting Firestore data..."
    
    # List all documents in the counters collection
    local documents
    documents=$(gcloud firestore documents list \
        --collection-path=counters \
        --format="value(name)" 2>/dev/null) || documents=""
    
    if [ -n "$documents" ]; then
        log_info "Deleting documents from 'counters' collection..."
        
        # Delete each document
        local deleted_count=0
        while IFS= read -r doc_path; do
            if [ -n "$doc_path" ]; then
                if gcloud firestore documents delete "$doc_path" --quiet; then
                    ((deleted_count++))
                    log_info "Deleted: $(basename "$doc_path")"
                else
                    log_warning "Failed to delete: $(basename "$doc_path")"
                fi
            fi
        done <<< "$documents"
        
        log_success "Deleted $deleted_count document(s) from Firestore"
    else
        log_info "No documents found to delete"
    fi
}

# Handle Firestore database deletion
handle_firestore_database() {
    log_info "Checking Firestore database..."
    
    local db_count
    db_count=$(gcloud firestore databases list --format="value(name)" 2>/dev/null | wc -l)
    
    if [ "$db_count" -eq 0 ]; then
        log_info "No Firestore database found to delete"
        return
    fi
    
    echo
    log_warning "Firestore database detected"
    echo "The Firestore database contains the visitor counter data."
    echo "Deleting the database will remove ALL Firestore data in this project."
    echo
    echo "Options:"
    echo "  1. Delete only visitor counter data (keep database)"
    echo "  2. Delete entire Firestore database (WARNING: removes ALL data)"
    echo "  3. Skip Firestore cleanup"
    echo
    echo -n "Choose option (1/2/3): "
    read -r firestore_choice
    
    case "$firestore_choice" in
        1)
            log_info "Deleting only visitor counter data..."
            delete_firestore_data
            ;;
        2)
            echo
            log_warning "You are about to delete the ENTIRE Firestore database!"
            log_warning "This will remove ALL Firestore data in project: $PROJECT_ID"
            echo -n "Type 'DELETE' to confirm: "
            read -r confirm_db_delete
            
            if [ "$confirm_db_delete" = "DELETE" ]; then
                log_info "Deleting Firestore database..."
                if gcloud firestore databases delete \
                    --database="(default)" \
                    --quiet; then
                    log_success "Firestore database deleted"
                else
                    log_error "Failed to delete Firestore database"
                fi
            else
                log_info "Database deletion cancelled"
            fi
            ;;
        3)
            log_info "Skipping Firestore cleanup"
            ;;
        *)
            log_warning "Invalid choice. Skipping Firestore cleanup"
            ;;
    esac
}

# Clean up local files
cleanup_local_files() {
    log_info "Checking local files..."
    
    local files_to_check=(
        "${SCRIPT_DIR}/../function_url.txt"
        "$FUNCTION_DIR"
    )
    
    local files_exist=false
    
    for file_path in "${files_to_check[@]}"; do
        if [ -e "$file_path" ]; then
            files_exist=true
            break
        fi
    done
    
    if [ "$files_exist" = false ]; then
        log_info "No local files found to clean up"
        return
    fi
    
    echo
    echo "Local files found:"
    for file_path in "${files_to_check[@]}"; do
        if [ -e "$file_path" ]; then
            if [ -d "$file_path" ]; then
                echo "  • Directory: $file_path"
            else
                echo "  • File: $file_path"
            fi
        fi
    done
    
    echo
    echo -n "Delete local files? (y/n): "
    read -r delete_local
    
    if [ "$delete_local" = "y" ] || [ "$delete_local" = "Y" ]; then
        for file_path in "${files_to_check[@]}"; do
            if [ -e "$file_path" ]; then
                if rm -rf "$file_path"; then
                    log_success "Deleted: $file_path"
                else
                    log_warning "Failed to delete: $file_path"
                fi
            fi
        done
    else
        log_info "Local files preserved"
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    local region="$1"
    
    cat << EOF

${GREEN}Cleanup Summary${NC}

The following actions were performed:
• Checked project: $PROJECT_ID
• Checked region: $region
• Processed Cloud Function: $FUNCTION_NAME
• Handled Firestore data cleanup
• Processed local files

${BLUE}What to do next:${NC}
1. Verify resources are deleted in the Google Cloud Console
2. Check your billing to ensure no ongoing charges
3. If you disabled APIs during cleanup, they may need to be re-enabled for other projects

${BLUE}Cost Information:${NC}
• Deleted resources will stop incurring charges immediately
• Some services may have minimal charges for the current billing period
• Check the Google Cloud Console billing section for details

${YELLOW}Note:${NC} If you need to redeploy, run './deploy.sh' from this directory.

EOF
}

# Verify cleanup completion
verify_cleanup() {
    local region="$1"
    
    log_info "Verifying cleanup completion..."
    
    # Check if function still exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$region" &>/dev/null; then
        log_warning "Cloud Function still exists (may take a few minutes to fully delete)"
    else
        log_success "Cloud Function successfully removed"
    fi
    
    # Check local files
    if [ -f "${SCRIPT_DIR}/../function_url.txt" ]; then
        log_info "Function URL file still exists locally"
    fi
    
    if [ -d "$FUNCTION_DIR" ]; then
        log_info "Function source directory still exists locally"
    fi
}

# Main cleanup function
main() {
    local project_id="$1"
    local region="${2:-$DEFAULT_REGION}"
    
    # Show help if requested
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_help
        exit 0
    fi
    
    echo "=============================================="
    echo "  Visitor Counter Cleanup Script"
    echo "=============================================="
    echo
    
    # Setup project
    setup_project "$project_id"
    
    export REGION="$region"
    log_info "Using region: $REGION"
    
    # Confirm deletion
    confirm_deletion "$PROJECT_ID" "$region"
    
    echo
    log_info "Starting cleanup process..."
    
    # Delete Cloud Function if it exists
    if check_function_exists "$region"; then
        delete_function "$region"
    fi
    
    # Handle Firestore data
    handle_firestore_database
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup "$region"
    
    echo
    echo "=============================================="
    show_cleanup_summary "$region"
    echo "=============================================="
    
    log_success "Cleanup completed!"
}

# Run main function with all arguments
main "$@"