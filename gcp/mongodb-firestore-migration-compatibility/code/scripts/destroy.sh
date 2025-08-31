#!/bin/bash

# MongoDB to Firestore Migration with API Compatibility - Cleanup Script
# This script removes all infrastructure components deployed by the migration solution

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/mongodb-firestore-migration-destroy-$(date +%Y%m%d_%H%M%S).log"
FORCE_DELETE=${FORCE_DELETE:-false}
DRY_RUN=${DRY_RUN:-false}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Error handling
error_exit() {
    log ERROR "$1"
    log ERROR "Cleanup failed. Check log file: $LOG_FILE"
    exit 1
}

# Cleanup on script exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log ERROR "Script failed with exit code $exit_code"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Banner
show_banner() {
    echo -e "${RED}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          MongoDB to Firestore Migration Cleanup            ║"
    echo "║                    GCP Recipe Solution                       ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Prerequisites check
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check gcloud version
    local gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null | head -n1)
    log INFO "Found gcloud CLI version: $gcloud_version"
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error_exit "Not authenticated with gcloud. Run: gcloud auth login"
    fi
    
    # Get current project ID
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [ -z "$PROJECT_ID" ]; then
        error_exit "No project configured. Set with: gcloud config set project PROJECT_ID"
    fi
    
    log INFO "✅ Prerequisites check passed"
    log INFO "Current project: $PROJECT_ID"
}

# Confirmation prompt
confirm_deletion() {
    if [ "$FORCE_DELETE" = "true" ]; then
        log WARN "FORCE_DELETE enabled - skipping confirmation"
        return 0
    fi
    
    echo -e "${YELLOW}"
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   • Cloud Functions (migrate-mongodb-collection, mongo-compatibility-api)"
    echo "   • Firestore database and all data"
    echo "   • Secret Manager secrets"
    echo "   • Cloud Build configurations"
    echo "   • Temporary files and configurations"
    echo ""
    echo "   Project: $PROJECT_ID"
    echo -e "${NC}"
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log INFO "Operation cancelled by user"
        exit 0
    fi
    
    log INFO "User confirmed deletion"
}

# Get resource inventory
get_resource_inventory() {
    log INFO "Discovering deployed resources..."
    
    # Cloud Functions
    local functions
    functions=$(gcloud functions list --filter="name:(migrate-mongodb-collection OR mongo-compatibility-api)" \
        --format="value(name)" 2>/dev/null | wc -l)
    log INFO "Found $functions Cloud Functions to delete"
    
    # Secrets
    local secrets
    secrets=$(gcloud secrets list --filter="name:mongodb-connection-string" \
        --format="value(name)" 2>/dev/null | wc -l)
    log INFO "Found $secrets secrets to delete"
    
    # Check if Firestore database exists
    if gcloud firestore databases describe --database="(default)" --quiet &> /dev/null 2>&1; then
        log INFO "Found Firestore database to clean up"
    else
        log INFO "No Firestore database found"
    fi
    
    log INFO "✅ Resource inventory completed"
}

# Delete Cloud Functions
delete_cloud_functions() {
    log INFO "Deleting Cloud Functions..."
    
    local functions=("migrate-mongodb-collection" "mongo-compatibility-api")
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN: Would delete Cloud Functions: ${functions[*]}"
        return 0
    fi
    
    for function_name in "${functions[@]}"; do
        if gcloud functions describe "$function_name" --quiet &> /dev/null; then
            log INFO "Deleting function: $function_name"
            if gcloud functions delete "$function_name" --quiet; then
                log INFO "✅ Deleted function: $function_name"
            else
                log WARN "⚠️  Failed to delete function: $function_name"
            fi
        else
            log INFO "Function $function_name not found, skipping"
        fi
    done
    
    log INFO "✅ Cloud Functions cleanup completed"
}

# Clean up Firestore data
cleanup_firestore_data() {
    log INFO "Cleaning up Firestore data..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN: Would clean up Firestore collections and data"
        return 0
    fi
    
    # Check if Firestore database exists
    if ! gcloud firestore databases describe --database="(default)" --quiet &> /dev/null 2>&1; then
        log INFO "No Firestore database found, skipping data cleanup"
        return 0
    fi
    
    # Clean up test collections created during migration
    local collections=("test_users" "test_collection" "users" "products" "orders")
    
    log INFO "Cleaning up Firestore collections..."
    
    # Create a temporary Python script for cleanup
    local cleanup_script="/tmp/firestore_cleanup_$$.py"
    cat > "$cleanup_script" << 'EOF'
import sys
from google.cloud import firestore

def cleanup_collection(db, collection_name):
    """Delete all documents in a collection"""
    try:
        collection_ref = db.collection(collection_name)
        docs = list(collection_ref.stream())
        
        if not docs:
            print(f"Collection '{collection_name}' is empty or doesn't exist")
            return 0
        
        # Delete documents in batches
        batch_size = 100
        total_deleted = 0
        
        for i in range(0, len(docs), batch_size):
            batch = db.batch()
            batch_docs = docs[i:i + batch_size]
            
            for doc in batch_docs:
                batch.delete(doc.reference)
            
            batch.commit()
            total_deleted += len(batch_docs)
            print(f"Deleted {len(batch_docs)} documents from '{collection_name}'")
        
        print(f"✅ Deleted {total_deleted} total documents from '{collection_name}'")
        return total_deleted
        
    except Exception as e:
        print(f"❌ Error cleaning up collection '{collection_name}': {e}")
        return 0

def main():
    db = firestore.Client()
    collections = sys.argv[1:] if len(sys.argv) > 1 else []
    
    total_deleted = 0
    for collection_name in collections:
        deleted = cleanup_collection(db, collection_name)
        total_deleted += deleted
    
    print(f"\n✅ Total documents deleted: {total_deleted}")

if __name__ == '__main__':
    main()
EOF
    
    # Run the cleanup script
    if command -v python3 &> /dev/null; then
        log INFO "Running Firestore data cleanup..."
        python3 "$cleanup_script" "${collections[@]}" 2>/dev/null || log WARN "Firestore cleanup completed with warnings"
    else
        log WARN "Python3 not found, skipping Firestore data cleanup"
    fi
    
    # Clean up temporary script
    rm -f "$cleanup_script"
    
    log INFO "✅ Firestore data cleanup completed"
}

# Delete Firestore database
delete_firestore_database() {
    log INFO "Checking Firestore database deletion options..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN: Would attempt to delete Firestore database"
        return 0
    fi
    
    # Check if Firestore database exists
    if ! gcloud firestore databases describe --database="(default)" --quiet &> /dev/null 2>&1; then
        log INFO "No Firestore database found to delete"
        return 0
    fi
    
    log WARN "⚠️  Firestore databases cannot be deleted through gcloud CLI"
    log WARN "⚠️  To delete the Firestore database:"
    log WARN "   1. Go to https://console.cloud.google.com/firestore"
    log WARN "   2. Click on Settings"
    log WARN "   3. Select 'Delete database'"
    log WARN "   4. Follow the confirmation prompts"
    log WARN ""
    log WARN "   Note: This action is irreversible and will delete ALL Firestore data"
    
    log INFO "✅ Firestore database deletion information provided"
}

# Delete secrets
delete_secrets() {
    log INFO "Deleting Secret Manager secrets..."
    
    local secrets=("mongodb-connection-string")
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN: Would delete secrets: ${secrets[*]}"
        return 0
    fi
    
    for secret_name in "${secrets[@]}"; do
        if gcloud secrets describe "$secret_name" --quiet &> /dev/null; then
            log INFO "Deleting secret: $secret_name"
            if gcloud secrets delete "$secret_name" --quiet; then
                log INFO "✅ Deleted secret: $secret_name"
            else
                log WARN "⚠️  Failed to delete secret: $secret_name"
            fi
        else
            log INFO "Secret $secret_name not found, skipping"
        fi
    done
    
    log INFO "✅ Secrets cleanup completed"
}

# Clean up temporary files
cleanup_temp_files() {
    log INFO "Cleaning up temporary files..."
    
    local temp_files=(
        "/tmp/mongo-api-url.txt"
        "/tmp/migration-cloudbuild.yaml"
        "/tmp/application-integration.py"
        "/tmp/cloudbuild-*.yaml"
        "/tmp/firestore_cleanup_*.py"
        "/tmp/migration-function-*"
        "/tmp/compatibility-api-*"
    )
    
    if [ "$DRY_RUN" = "true" ]; then
        log INFO "DRY RUN: Would clean up temporary files"
        return 0
    fi
    
    for pattern in "${temp_files[@]}"; do
        if ls $pattern &> /dev/null 2>&1; then
            rm -rf $pattern 2>/dev/null || log WARN "Could not remove: $pattern"
            log INFO "Cleaned up: $pattern"
        fi
    done
    
    log INFO "✅ Temporary files cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log INFO "Verifying resource cleanup..."
    
    local cleanup_complete=true
    
    # Check Cloud Functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --filter="name:(migrate-mongodb-collection OR mongo-compatibility-api)" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [ "$remaining_functions" -eq 0 ]; then
        log INFO "✅ All Cloud Functions removed"
    else
        log WARN "⚠️  $remaining_functions Cloud Functions still exist"
        cleanup_complete=false
    fi
    
    # Check secrets
    local remaining_secrets
    remaining_secrets=$(gcloud secrets list --filter="name:mongodb-connection-string" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [ "$remaining_secrets" -eq 0 ]; then
        log INFO "✅ All secrets removed"
    else
        log WARN "⚠️  $remaining_secrets secrets still exist"
        cleanup_complete=false
    fi
    
    # Check Firestore (informational only)
    if gcloud firestore databases describe --database="(default)" --quiet &> /dev/null 2>&1; then
        log INFO "ℹ️  Firestore database still exists (manual deletion required)"
    else
        log INFO "✅ Firestore database not found"
    fi
    
    if [ "$cleanup_complete" = "true" ]; then
        log INFO "✅ Cleanup verification passed"
    else
        log WARN "⚠️  Some resources may still exist"
    fi
}

# Display cleanup summary
show_summary() {
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    Cleanup Summary                           ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    log INFO "Cleanup process completed!"
    log INFO ""
    log INFO "📋 Cleaned Up Resources:"
    log INFO "  • Cloud Functions deleted"
    log INFO "  • Secret Manager secrets deleted"
    log INFO "  • Firestore data collections cleaned"
    log INFO "  • Temporary files removed"
    log INFO ""
    
    log INFO "⚠️  Manual Actions Required:"
    log INFO "  • Delete Firestore database manually from console"
    log INFO "  • Review and disable APIs if no longer needed:"
    log INFO "    - firestore.googleapis.com"
    log INFO "    - cloudfunctions.googleapis.com"
    log INFO "    - cloudbuild.googleapis.com"
    log INFO "    - secretmanager.googleapis.com"
    log INFO ""
    
    log INFO "💡 Cost Optimization:"
    log INFO "  • Monitor billing to ensure resources are no longer charged"
    log INFO "  • Consider deleting the entire project if it was created specifically for this tutorial"
    log INFO ""
    
    log INFO "📊 Log file: $LOG_FILE"
    
    if [ "$DRY_RUN" = "true" ]; then
        log WARN "This was a DRY RUN - no resources were actually deleted"
    fi
}

# Project deletion option
offer_project_deletion() {
    if [ "$FORCE_DELETE" = "true" ] || [ "$DRY_RUN" = "true" ]; then
        return 0
    fi
    
    echo -e "${YELLOW}"
    echo "🗑️  Would you like to delete the entire project?"
    echo "   This will permanently delete ALL resources in project: $PROJECT_ID"
    echo "   This action cannot be undone!"
    echo -e "${NC}"
    
    read -p "Delete entire project? (type 'DELETE-PROJECT' to confirm): " project_confirmation
    
    if [ "$project_confirmation" = "DELETE-PROJECT" ]; then
        log WARN "User confirmed project deletion"
        log INFO "Deleting project: $PROJECT_ID"
        
        if gcloud projects delete "$PROJECT_ID" --quiet; then
            log INFO "✅ Project deletion initiated: $PROJECT_ID"
            log INFO "Note: Project deletion may take several minutes to complete"
        else
            log ERROR "Failed to delete project: $PROJECT_ID"
        fi
    else
        log INFO "Project deletion cancelled"
    fi
}

# Main execution
main() {
    show_banner
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --project-id)
                PROJECT_ID="$2"
                gcloud config set project "$PROJECT_ID"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --force           Skip confirmation prompts"
                echo "  --dry-run         Show what would be deleted without actually deleting"
                echo "  --project-id ID   Specify GCP project ID"
                echo "  --help            Show this help message"
                exit 0
                ;;
            *)
                log WARN "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    log INFO "Starting cleanup process..."
    log INFO "Log file: $LOG_FILE"
    
    check_prerequisites
    confirm_deletion
    get_resource_inventory
    delete_cloud_functions
    cleanup_firestore_data
    delete_firestore_database
    delete_secrets
    cleanup_temp_files
    verify_cleanup
    show_summary
    offer_project_deletion
    
    log INFO "🎉 MongoDB to Firestore migration cleanup completed!"
}

# Execute main function
main "$@"