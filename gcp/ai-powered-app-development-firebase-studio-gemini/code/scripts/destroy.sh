#!/bin/bash

# AI-Powered App Development with Firebase Studio and Gemini - Cleanup Script
# This script removes all Firebase and Google Cloud resources created by the deployment

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup encountered an error. Check $LOG_FILE for details."
    log_warning "Some resources may still exist and require manual cleanup."
}

trap cleanup_on_error ERR

# Initialize log file
echo "=== Firebase Studio Cleanup Started at $TIMESTAMP ===" > "$LOG_FILE"

log_info "Starting Firebase Studio and Gemini AI cleanup..."

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI is not installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Get project information
get_project_info() {
    log_info "Getting project information..."
    
    # Try to get project from environment variable first
    if [ -z "${PROJECT_ID:-}" ]; then
        # Try to get from gcloud config
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        
        if [ -z "$PROJECT_ID" ]; then
            log_error "PROJECT_ID not set and no default project configured."
            log_info "Please set PROJECT_ID environment variable or configure default project:"
            log_info "  export PROJECT_ID=your-project-id"
            log_info "  OR"
            log_info "  gcloud config set project your-project-id"
            exit 1
        fi
    fi
    
    log_info "Target project: $PROJECT_ID"
    
    # Verify project exists
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Project $PROJECT_ID does not exist or you don't have access."
        exit 1
    fi
    
    # Set project as current
    gcloud config set project "$PROJECT_ID"
    
    log_success "Project information retrieved: $PROJECT_ID"
}

# Confirmation prompt
confirm_deletion() {
    echo ""
    log_warning "⚠️  WARNING: This will permanently delete the following resources:"
    log_warning "   • Firebase project and all data"
    log_warning "   • Firestore database and documents"
    log_warning "   • Secret Manager secrets"
    log_warning "   • All associated Google Cloud resources"
    log_warning "   • Project: $PROJECT_ID"
    echo ""
    log_error "This action is IRREVERSIBLE!"
    echo ""
    
    read -p "Are you sure you want to delete project $PROJECT_ID? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    echo ""
    log_warning "Last chance! Type the project ID to confirm deletion:"
    read -p "Project ID: " -r
    if [[ $REPLY != "$PROJECT_ID" ]]; then
        log_error "Project ID mismatch. Cleanup cancelled."
        exit 1
    fi
    
    log_info "Confirmation received. Proceeding with cleanup..."
}

# List resources before deletion
list_resources() {
    log_info "Listing resources to be deleted..."
    
    # List Firebase resources
    log_info "Firebase/Firestore resources:"
    if gcloud services list --enabled --filter="name:firebase" --project="$PROJECT_ID" &>/dev/null; then
        gcloud firestore databases list --project="$PROJECT_ID" 2>/dev/null || log_info "  No Firestore databases found"
    else
        log_info "  Firebase not enabled"
    fi
    
    # List Secret Manager secrets
    log_info "Secret Manager secrets:"
    gcloud secrets list --project="$PROJECT_ID" 2>/dev/null || log_info "  No secrets found"
    
    # List Cloud Run services
    log_info "Cloud Run services:"
    gcloud run services list --project="$PROJECT_ID" 2>/dev/null || log_info "  No Cloud Run services found"
    
    # List Cloud Build triggers
    log_info "Cloud Build triggers:"
    gcloud builds triggers list --project="$PROJECT_ID" 2>/dev/null || log_info "  No build triggers found"
    
    log_info "Resource listing completed"
}

# Delete Secret Manager secrets
delete_secrets() {
    log_info "Deleting Secret Manager secrets..."
    
    # Delete Gemini API key secret
    if gcloud secrets describe gemini-api-key --project="$PROJECT_ID" &>/dev/null; then
        gcloud secrets delete gemini-api-key \
            --project="$PROJECT_ID" \
            --quiet
        log_success "✅ Deleted secret: gemini-api-key"
    else
        log_info "Secret 'gemini-api-key' not found"
    fi
    
    # Delete any other secrets that might have been created
    local other_secrets=$(gcloud secrets list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$other_secrets" ]; then
        log_warning "Found additional secrets. Deleting..."
        while IFS= read -r secret; do
            if [ -n "$secret" ]; then
                gcloud secrets delete "$secret" \
                    --project="$PROJECT_ID" \
                    --quiet
                log_success "✅ Deleted secret: $secret"
            fi
        done <<< "$other_secrets"
    fi
    
    log_success "Secret Manager cleanup completed"
}

# Delete Cloud Run services
delete_cloud_run_services() {
    log_info "Deleting Cloud Run services..."
    
    local services=$(gcloud run services list --project="$PROJECT_ID" --format="value(metadata.name)" 2>/dev/null || echo "")
    if [ -n "$services" ]; then
        while IFS= read -r service; do
            if [ -n "$service" ]; then
                local region=$(gcloud run services describe "$service" --project="$PROJECT_ID" --format="value(metadata.labels.['cloud.googleapis.com/location'])" 2>/dev/null || echo "us-central1")
                gcloud run services delete "$service" \
                    --region="$region" \
                    --project="$PROJECT_ID" \
                    --quiet
                log_success "✅ Deleted Cloud Run service: $service"
            fi
        done <<< "$services"
    else
        log_info "No Cloud Run services found"
    fi
    
    log_success "Cloud Run services cleanup completed"
}

# Delete Cloud Build triggers
delete_build_triggers() {
    log_info "Deleting Cloud Build triggers..."
    
    local triggers=$(gcloud builds triggers list --project="$PROJECT_ID" --format="value(id)" 2>/dev/null || echo "")
    if [ -n "$triggers" ]; then
        while IFS= read -r trigger; do
            if [ -n "$trigger" ]; then
                gcloud builds triggers delete "$trigger" \
                    --project="$PROJECT_ID" \
                    --quiet
                log_success "✅ Deleted build trigger: $trigger"
            fi
        done <<< "$triggers"
    else
        log_info "No Cloud Build triggers found"
    fi
    
    log_success "Cloud Build triggers cleanup completed"
}

# Delete Firestore indexes (optional - will be deleted with project)
delete_firestore_indexes() {
    log_info "Deleting Firestore indexes..."
    
    # List and delete composite indexes
    local indexes=$(gcloud firestore indexes composite list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$indexes" ]; then
        log_info "Found Firestore indexes to delete..."
        while IFS= read -r index; do
            if [ -n "$index" ]; then
                gcloud firestore indexes composite delete "$index" \
                    --project="$PROJECT_ID" \
                    --quiet
                log_success "✅ Deleted Firestore index: $(basename "$index")"
            fi
        done <<< "$indexes"
    else
        log_info "No Firestore indexes found"
    fi
    
    log_success "Firestore indexes cleanup completed"
}

# Delete Artifact Registry repositories
delete_artifact_registry() {
    log_info "Deleting Artifact Registry repositories..."
    
    local repos=$(gcloud artifacts repositories list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$repos" ]; then
        while IFS= read -r repo; do
            if [ -n "$repo" ]; then
                local repo_name=$(basename "$repo")
                local location=$(echo "$repo" | cut -d'/' -f4)
                gcloud artifacts repositories delete "$repo_name" \
                    --location="$location" \
                    --project="$PROJECT_ID" \
                    --quiet
                log_success "✅ Deleted Artifact Registry repository: $repo_name"
            fi
        done <<< "$repos"
    else
        log_info "No Artifact Registry repositories found"
    fi
    
    log_success "Artifact Registry cleanup completed"
}

# Delete Firebase/Firestore data (warning about data loss)
delete_firebase_data() {
    log_info "Preparing to delete Firebase project data..."
    
    # Note: Individual Firestore documents deletion is not practical via gcloud
    # The entire project deletion will handle this
    log_warning "Firestore data will be deleted with the project"
    log_warning "This includes all documents, collections, and subcollections"
    
    # If Firebase CLI is available and configured, sign out
    if command -v firebase &> /dev/null; then
        log_info "Clearing Firebase CLI project association..."
        firebase use --clear 2>/dev/null || log_info "No Firebase project association found"
    fi
    
    log_success "Firebase data deletion prepared"
}

# Delete the entire Google Cloud project
delete_project() {
    log_info "Deleting Google Cloud project..."
    
    # Final confirmation
    echo ""
    log_error "🚨 FINAL WARNING: About to delete project $PROJECT_ID"
    log_error "This will permanently delete ALL resources in the project!"
    echo ""
    read -p "Type 'DELETE' to proceed: " -r
    if [[ $REPLY != "DELETE" ]]; then
        log_info "Project deletion cancelled."
        exit 0
    fi
    
    # Delete the project
    log_info "Deleting project $PROJECT_ID..."
    gcloud projects delete "$PROJECT_ID" --quiet
    
    log_success "✅ Project deletion initiated: $PROJECT_ID"
    log_info "Project deletion may take several minutes to complete"
    log_info "You can check status with: gcloud projects describe $PROJECT_ID"
}

# Clean up local environment
cleanup_local_environment() {
    log_info "Cleaning up local environment..."
    
    # Clear gcloud configuration if this was the default project
    local current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [ "$current_project" = "$PROJECT_ID" ]; then
        gcloud config unset project
        log_success "✅ Cleared default project configuration"
    fi
    
    # Clean up local files created during deployment
    if [ -f "${SCRIPT_DIR}/firestore.rules" ]; then
        rm -f "${SCRIPT_DIR}/firestore.rules"
        log_success "✅ Removed local firestore.rules file"
    fi
    
    # Clear environment variables
    unset PROJECT_ID REGION APP_NAME RANDOM_SUFFIX FIREBASE_PROJECT 2>/dev/null || true
    
    log_success "Local environment cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check if project still exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        local project_state=$(gcloud projects describe "$PROJECT_ID" --format="value(lifecycleState)" 2>/dev/null || echo "UNKNOWN")
        if [ "$project_state" = "DELETE_REQUESTED" ]; then
            log_warning "Project deletion in progress..."
        else
            log_warning "Project may still exist. Check manually if needed."
        fi
    else
        log_success "✅ Project no longer accessible"
    fi
    
    log_success "Cleanup verification completed"
}

# Display cleanup summary
show_cleanup_summary() {
    log_success "🎉 Firebase Studio cleanup completed!"
    echo ""
    log_info "=== CLEANUP SUMMARY ==="
    log_info "✅ Secret Manager secrets deleted"
    log_info "✅ Cloud Run services deleted"
    log_info "✅ Cloud Build triggers deleted"
    log_info "✅ Firestore indexes deleted"
    log_info "✅ Artifact Registry repositories deleted"
    log_info "✅ Firebase project marked for deletion"
    log_info "✅ Google Cloud project deleted: $PROJECT_ID"
    log_info "✅ Local environment cleaned up"
    echo ""
    log_info "=== IMPORTANT NOTES ==="
    log_warning "• Project deletion may take several minutes to complete"
    log_warning "• All data has been permanently deleted"
    log_warning "• Billing for the project will stop once deletion completes"
    log_warning "• The project ID '$PROJECT_ID' cannot be reused for 30 days"
    echo ""
    log_info "If you need to check deletion status:"
    log_info "  gcloud projects describe $PROJECT_ID"
    echo ""
    log_success "Cleanup completed successfully!"
}

# Selective cleanup mode (if only specific resources need to be deleted)
selective_cleanup() {
    log_info "=== Selective Cleanup Mode ==="
    log_info "Choose what to delete (this will NOT delete the project):"
    echo ""
    echo "1. Secret Manager secrets only"
    echo "2. Cloud Run services only"
    echo "3. Cloud Build triggers only"
    echo "4. Firestore indexes only"
    echo "5. All resources except project"
    echo "6. Exit without deleting anything"
    echo ""
    
    read -p "Enter your choice (1-6): " -r choice
    
    case $choice in
        1)
            delete_secrets
            ;;
        2)
            delete_cloud_run_services
            ;;
        3)
            delete_build_triggers
            ;;
        4)
            delete_firestore_indexes
            ;;
        5)
            delete_secrets
            delete_cloud_run_services
            delete_build_triggers
            delete_firestore_indexes
            delete_artifact_registry
            ;;
        6)
            log_info "Exiting without changes."
            exit 0
            ;;
        *)
            log_error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
    
    log_success "Selective cleanup completed"
}

# Main cleanup flow
main() {
    log_info "=== Firebase Studio Cleanup Script ==="
    
    # Check for selective mode
    if [ "${1:-}" = "--selective" ]; then
        check_prerequisites
        get_project_info
        selective_cleanup
        exit 0
    fi
    
    # Full cleanup mode
    check_prerequisites
    get_project_info
    confirm_deletion
    list_resources
    delete_secrets
    delete_cloud_run_services
    delete_build_triggers
    delete_firestore_indexes
    delete_artifact_registry
    delete_firebase_data
    delete_project
    cleanup_local_environment
    verify_cleanup
    show_cleanup_summary
    
    log_success "🎉 Full cleanup completed successfully!"
    echo "📋 Cleanup log saved to: $LOG_FILE"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --selective    Run in selective cleanup mode (keep project, delete specific resources)"
    echo "  --help        Show this help message"
    echo ""
    echo "ENVIRONMENT VARIABLES:"
    echo "  PROJECT_ID    Google Cloud project ID to delete (required)"
    echo ""
    echo "EXAMPLES:"
    echo "  # Full cleanup (deletes entire project)"
    echo "  export PROJECT_ID=my-firebase-project"
    echo "  $0"
    echo ""
    echo "  # Selective cleanup (keeps project, deletes specific resources)"
    echo "  export PROJECT_ID=my-firebase-project"
    echo "  $0 --selective"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        show_usage
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac