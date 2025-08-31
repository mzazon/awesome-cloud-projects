#!/bin/bash

# Destroy script for URL Shortener with Cloud Functions and Firestore
# This script safely removes all resources created by the deployment script

set -euo pipefail

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
cleanup_on_error() {
    log_error "Cleanup failed. Some resources may still exist."
    log_info "Please check the Google Cloud Console to manually remove any remaining resources."
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Get environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get current project or prompt user
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [[ -z "${PROJECT_ID:-}" ]]; then
        if [[ -n "$CURRENT_PROJECT" ]]; then
            read -p "Enter Google Cloud Project ID to clean up [$CURRENT_PROJECT]: " PROJECT_ID
            PROJECT_ID="${PROJECT_ID:-$CURRENT_PROJECT}"
        else
            read -p "Enter Google Cloud Project ID to clean up: " PROJECT_ID
        fi
    fi
    
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required for cleanup"
        exit 1
    fi
    
    export PROJECT_ID
    export REGION="${REGION:-us-central1}"
    export FUNCTION_NAME="${FUNCTION_NAME:-url-shortener}"
    
    # Set the project as active
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set functions/region "$REGION"
    
    log_success "Environment configured - Project: $PROJECT_ID, Region: $REGION"
}

# Confirm destruction
confirm_destruction() {
    echo "=============================================="
    log_warning "DESTRUCTIVE OPERATION WARNING"
    echo "=============================================="
    echo "This script will permanently delete the following resources:"
    echo "• Cloud Function: $FUNCTION_NAME"
    echo "• Firestore database data (if selected)"
    echo "• Project: $PROJECT_ID (if selected)"
    echo ""
    echo "Deletion options:"
    echo "1. Delete function only (recommended)"
    echo "2. Delete function and Firestore data"
    echo "3. Delete entire project (including billing)"
    echo "4. Cancel"
    echo ""
    
    while true; do
        read -p "Select an option [1-4]: " choice
        case $choice in
            1)
                export DELETE_FUNCTION=true
                export DELETE_FIRESTORE=false
                export DELETE_PROJECT=false
                break
                ;;
            2)
                export DELETE_FUNCTION=true
                export DELETE_FIRESTORE=true
                export DELETE_PROJECT=false
                break
                ;;
            3)
                export DELETE_FUNCTION=true
                export DELETE_FIRESTORE=true
                export DELETE_PROJECT=true
                break
                ;;
            4)
                log_info "Cleanup cancelled by user"
                exit 0
                ;;
            *)
                log_error "Invalid option. Please select 1-4."
                ;;
        esac
    done
    
    # Final confirmation for destructive operations
    if [[ "$DELETE_FIRESTORE" == "true" ]] || [[ "$DELETE_PROJECT" == "true" ]]; then
        echo ""
        log_warning "WARNING: This action cannot be undone!"
        read -p "Type 'yes' to confirm destruction: " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Starting cleanup process..."
}

# Check if resources exist
check_resources() {
    log_info "Checking existing resources..."
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Project $PROJECT_ID does not exist or you don't have access to it"
        exit 1
    fi
    
    # Check if Cloud Functions API is enabled
    if gcloud services list --enabled --filter="name:cloudfunctions.googleapis.com" --format="value(name)" | grep -q cloudfunctions; then
        export FUNCTIONS_ENABLED=true
        # Check if function exists
        if gcloud functions describe "$FUNCTION_NAME" &>/dev/null; then
            export FUNCTION_EXISTS=true
            log_info "Found Cloud Function: $FUNCTION_NAME"
        else
            export FUNCTION_EXISTS=false
            log_info "Cloud Function $FUNCTION_NAME not found"
        fi
    else
        export FUNCTIONS_ENABLED=false
        export FUNCTION_EXISTS=false
        log_info "Cloud Functions API is not enabled"
    fi
    
    # Check if Firestore exists
    if gcloud services list --enabled --filter="name:firestore.googleapis.com" --format="value(name)" | grep -q firestore; then
        if gcloud firestore databases describe --database="(default)" &>/dev/null; then
            export FIRESTORE_EXISTS=true
            log_info "Found Firestore database"
        else
            export FIRESTORE_EXISTS=false
            log_info "Firestore database not found"
        fi
    else
        export FIRESTORE_EXISTS=false
        log_info "Firestore API is not enabled"
    fi
    
    log_success "Resource check completed"
}

# Delete Cloud Function
delete_function() {
    if [[ "$DELETE_FUNCTION" == "true" ]] && [[ "$FUNCTION_EXISTS" == "true" ]]; then
        log_info "Deleting Cloud Function: $FUNCTION_NAME..."
        
        gcloud functions delete "$FUNCTION_NAME" \
            --region="$REGION" \
            --quiet
        
        log_success "Cloud Function deleted successfully"
    else
        log_info "Skipping Cloud Function deletion"
    fi
}

# Delete Firestore data
delete_firestore_data() {
    if [[ "$DELETE_FIRESTORE" == "true" ]] && [[ "$FIRESTORE_EXISTS" == "true" ]]; then
        log_warning "Deleting Firestore data..."
        log_info "Note: Individual document deletion requires manual action or scripting"
        
        echo ""
        echo "Firestore cleanup options:"
        echo "1. Delete specific collection data (url-mappings)"
        echo "2. Delete entire Firestore database"
        echo "3. Skip Firestore cleanup"
        
        while true; do
            read -p "Select Firestore cleanup option [1-3]: " fs_choice
            case $fs_choice in
                1)
                    log_info "To delete the url-mappings collection data:"
                    echo "Visit: https://console.firebase.google.com/project/$PROJECT_ID/firestore"
                    echo "1. Navigate to the 'url-mappings' collection"
                    echo "2. Select all documents and delete them"
                    echo "3. Delete the collection itself"
                    read -p "Press Enter after manual cleanup is complete..."
                    break
                    ;;
                2)
                    log_warning "Deleting entire Firestore database..."
                    if gcloud firestore databases delete --database="(default)" --quiet; then
                        log_success "Firestore database deleted successfully"
                    else
                        log_error "Failed to delete Firestore database"
                    fi
                    break
                    ;;
                3)
                    log_info "Skipping Firestore cleanup"
                    break
                    ;;
                *)
                    log_error "Invalid option. Please select 1-3."
                    ;;
            esac
        done
    else
        log_info "Skipping Firestore cleanup"
    fi
}

# Delete entire project
delete_project() {
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        log_warning "Deleting entire project: $PROJECT_ID..."
        
        # Final confirmation for project deletion
        echo ""
        log_warning "PROJECT DELETION WARNING"
        echo "This will permanently delete the project '$PROJECT_ID' and ALL its resources."
        echo "This action cannot be undone and will immediately stop all billing."
        echo ""
        read -p "Type the project ID to confirm deletion: " confirm_project
        
        if [[ "$confirm_project" == "$PROJECT_ID" ]]; then
            log_info "Deleting project $PROJECT_ID..."
            
            if gcloud projects delete "$PROJECT_ID" --quiet; then
                log_success "Project deleted successfully"
                log_info "Project deletion may take several minutes to complete"
                echo ""
                log_info "Cleanup completed. Project $PROJECT_ID has been scheduled for deletion."
                return 0
            else
                log_error "Failed to delete project"
                return 1
            fi
        else
            log_error "Project ID mismatch. Skipping project deletion for safety."
            return 1
        fi
    else
        log_info "Skipping project deletion"
    fi
}

# Verify cleanup
verify_cleanup() {
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        # Skip verification if project was deleted
        return 0
    fi
    
    log_info "Verifying cleanup..."
    
    # Check if function was deleted
    if [[ "$DELETE_FUNCTION" == "true" ]]; then
        if gcloud functions describe "$FUNCTION_NAME" &>/dev/null; then
            log_error "Cloud Function still exists"
        else
            log_success "Cloud Function deletion verified"
        fi
    fi
    
    # Provide cleanup verification instructions
    echo ""
    log_info "Cleanup verification checklist:"
    echo "1. Cloud Functions: https://console.cloud.google.com/functions/list?project=$PROJECT_ID"
    echo "2. Firestore: https://console.firebase.google.com/project/$PROJECT_ID/firestore"
    echo "3. Billing: https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT_ID"
    
    log_success "Verification completed"
}

# Display cleanup summary
display_summary() {
    echo ""
    echo "=============================================="
    log_success "CLEANUP SUMMARY"
    echo "=============================================="
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "✅ Project scheduled for deletion: $PROJECT_ID"
        echo "✅ All resources will be removed automatically"
    else
        echo "Project: $PROJECT_ID"
        
        if [[ "$DELETE_FUNCTION" == "true" ]]; then
            echo "✅ Cloud Function removed: $FUNCTION_NAME"
        else
            echo "ℹ️  Cloud Function retained: $FUNCTION_NAME"
        fi
        
        if [[ "$DELETE_FIRESTORE" == "true" ]]; then
            echo "✅ Firestore data cleanup initiated"
        else
            echo "ℹ️  Firestore data retained"
        fi
    fi
    
    echo ""
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        log_info "Remaining resources may incur charges. Review the Google Cloud Console to ensure complete cleanup."
        log_info "Project: https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
    fi
    
    echo ""
    log_success "Cleanup process completed!"
}

# Main cleanup flow
main() {
    log_info "Starting URL Shortener cleanup..."
    echo "=============================================="
    
    check_prerequisites
    setup_environment
    confirm_destruction
    check_resources
    delete_function
    delete_firestore_data
    delete_project
    verify_cleanup
    display_summary
}

# Run main function
main "$@"