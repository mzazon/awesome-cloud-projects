#!/bin/bash

# ============================================================================
# GCP Habit Tracker Cleanup Script
# Simple Habit Tracker with Cloud Functions and Firestore
# ============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.env"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] $*" | tee -a "$LOG_FILE"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handler
handle_error() {
    local line_number=$1
    error "Cleanup failed at line $line_number"
    error "Check the log file: $LOG_FILE"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Initialize log file
echo "# GCP Habit Tracker Cleanup Log - $(date)" > "$LOG_FILE"

# ============================================================================
# Load Deployment Information
# ============================================================================

load_deployment_info() {
    info "Loading deployment information..."
    
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        # Source the deployment info file
        set -a  # Automatically export all variables
        source "$DEPLOYMENT_INFO_FILE"
        set +a  # Turn off automatic export
        
        info "Loaded deployment information:"
        info "  Project ID: ${PROJECT_ID:-not set}"
        info "  Region: ${REGION:-not set}"
        info "  Function Name: ${FUNCTION_NAME:-not set}"
    else
        warn "Deployment info file not found: $DEPLOYMENT_INFO_FILE"
        warn "You may need to provide environment variables manually"
    fi
    
    # Allow environment variables to override file values
    if [[ -z "${PROJECT_ID:-}" ]]; then
        error "PROJECT_ID is not set. Please set it as an environment variable or ensure deployment-info.env exists"
        error "Example: PROJECT_ID=your-project-id $0"
        exit 1
    fi
    
    # Set defaults for optional variables
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        warn "FUNCTION_NAME not found, will attempt to discover Cloud Functions in the project"
    fi
}

# ============================================================================
# Prerequisites Check
# ============================================================================

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "gcloud is not authenticated. Please run: gcloud auth login"
        exit 1
    fi
    
    # Verify project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error "Project $PROJECT_ID does not exist or you don't have access to it"
        exit 1
    fi
    
    # Set current project
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    success "Prerequisites check passed"
}

# ============================================================================
# Confirmation Prompt
# ============================================================================

confirm_deletion() {
    local force_mode="${1:-false}"
    
    if [[ "$force_mode" == "true" ]]; then
        warn "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    warn "=========================================="
    warn "WARNING: This will DELETE the following resources:"
    warn "=========================================="
    warn "Project: $PROJECT_ID"
    warn "Region: $REGION"
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        warn "Function: $FUNCTION_NAME"
    else
        warn "Functions: All habit-tracker functions found"
    fi
    
    warn "Firestore Database: (default) - DATA WILL BE LOST"
    warn "=========================================="
    
    echo ""
    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Confirmation received, proceeding with cleanup..."
}

# ============================================================================
# Delete Cloud Functions
# ============================================================================

delete_cloud_functions() {
    info "Deleting Cloud Functions..."
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        # Delete specific function
        info "Deleting function: $FUNCTION_NAME"
        
        if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
            gcloud functions delete "$FUNCTION_NAME" \
                --region="$REGION" \
                --quiet || {
                warn "Failed to delete function $FUNCTION_NAME"
            }
            success "Function $FUNCTION_NAME deleted"
        else
            warn "Function $FUNCTION_NAME not found"
        fi
    else
        # Find and delete all habit-tracker functions
        info "Discovering habit-tracker functions..."
        
        local functions=($(gcloud functions list \
            --regions="$REGION" \
            --filter="name~habit-tracker" \
            --format="value(name)" 2>/dev/null || echo ""))
        
        if [[ ${#functions[@]} -eq 0 ]]; then
            info "No habit-tracker functions found"
        else
            for func in "${functions[@]}"; do
                local func_name=$(basename "$func")
                info "Deleting function: $func_name"
                
                gcloud functions delete "$func_name" \
                    --region="$REGION" \
                    --quiet || {
                    warn "Failed to delete function $func_name"
                }
                success "Function $func_name deleted"
            done
        fi
    fi
    
    success "Cloud Functions cleanup completed"
}

# ============================================================================
# Delete Firestore Data
# ============================================================================

delete_firestore_data() {
    info "Deleting Firestore data..."
    
    # Check if Firestore database exists
    if ! gcloud firestore databases list --format="value(name)" | grep -q "projects/$PROJECT_ID/databases/(default)"; then
        info "No Firestore database found"
        return 0
    fi
    
    warn "Note: Firestore databases cannot be deleted via CLI"
    warn "However, we can delete all documents in the habits collection"
    
    # Try to delete documents in the habits collection
    info "Attempting to delete habit documents..."
    
    # Create a temporary Python script to delete documents
    local temp_script=$(mktemp)
    cat > "$temp_script" << 'EOF'
#!/usr/bin/env python3
import sys
try:
    from google.cloud import firestore
    
    db = firestore.Client()
    collection_ref = db.collection('habits')
    
    # Delete all documents in the collection
    docs = collection_ref.stream()
    deleted_count = 0
    
    for doc in docs:
        doc.reference.delete()
        deleted_count += 1
    
    print(f"Deleted {deleted_count} habit documents")
    
except ImportError:
    print("google-cloud-firestore not available, skipping document deletion")
    sys.exit(0)
except Exception as e:
    print(f"Error deleting documents: {e}")
    sys.exit(1)
EOF
    
    # Run the script
    if python3 "$temp_script" 2>/dev/null; then
        success "Firestore documents deleted successfully"
    else
        warn "Could not delete Firestore documents (this is non-critical)"
    fi
    
    # Clean up temporary script
    rm -f "$temp_script"
    
    warn "To completely delete the Firestore database:"
    warn "1. Go to: https://console.cloud.google.com/firestore/databases?project=$PROJECT_ID"
    warn "2. Click on the database settings"
    warn "3. Delete the database manually"
    
    success "Firestore cleanup completed"
}

# ============================================================================
# Cleanup IAM and Service Accounts
# ============================================================================

cleanup_iam() {
    info "Cleaning up IAM resources..."
    
    # Find and delete service accounts created for Cloud Functions
    local service_accounts=($(gcloud iam service-accounts list \
        --filter="displayName~'Cloud Function'" \
        --format="value(email)" 2>/dev/null || echo ""))
    
    if [[ ${#service_accounts[@]} -eq 0 ]]; then
        info "No Cloud Function service accounts found"
    else
        for sa in "${service_accounts[@]}"; do
            info "Deleting service account: $sa"
            gcloud iam service-accounts delete "$sa" --quiet || {
                warn "Failed to delete service account $sa"
            }
        done
    fi
    
    success "IAM cleanup completed"
}

# ============================================================================
# Optional: Delete Entire Project
# ============================================================================

delete_project() {
    local delete_project_mode="${1:-false}"
    
    if [[ "$delete_project_mode" != "true" ]]; then
        return 0
    fi
    
    warn "=========================================="
    warn "PROJECT DELETION MODE"
    warn "This will DELETE the ENTIRE project: $PROJECT_ID"
    warn "ALL resources in the project will be PERMANENTLY lost!"
    warn "=========================================="
    
    echo ""
    read -p "Are you absolutely sure? Type 'DELETE-PROJECT' to confirm: " project_confirmation
    
    if [[ "$project_confirmation" != "DELETE-PROJECT" ]]; then
        info "Project deletion cancelled"
        return 0
    fi
    
    info "Deleting project: $PROJECT_ID"
    gcloud projects delete "$PROJECT_ID" --quiet || {
        error "Failed to delete project $PROJECT_ID"
        exit 1
    }
    
    success "Project $PROJECT_ID deletion initiated"
    info "Note: Project deletion may take several minutes to complete"
}

# ============================================================================
# Verify Cleanup
# ============================================================================

verify_cleanup() {
    info "Verifying cleanup..."
    
    # Check for remaining Cloud Functions
    local remaining_functions=($(gcloud functions list \
        --regions="$REGION" \
        --filter="name~habit-tracker" \
        --format="value(name)" 2>/dev/null || echo ""))
    
    if [[ ${#remaining_functions[@]} -gt 0 ]]; then
        warn "Some functions may still exist:"
        for func in "${remaining_functions[@]}"; do
            warn "  - $(basename "$func")"
        done
    else
        success "No habit-tracker functions found"
    fi
    
    # Check Firestore database
    if gcloud firestore databases list --format="value(name)" | grep -q "projects/$PROJECT_ID/databases/(default)"; then
        warn "Firestore database still exists (manual deletion required)"
    else
        success "No Firestore database found"
    fi
    
    success "Cleanup verification completed"
}

# ============================================================================
# Cleanup Deployment Files
# ============================================================================

cleanup_deployment_files() {
    info "Cleaning up deployment files..."
    
    local files_to_remove=(
        "$DEPLOYMENT_INFO_FILE"
        "${SCRIPT_DIR}/deploy.log"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info "Removed: $(basename "$file")"
        fi
    done
    
    success "Deployment files cleaned up"
}

# ============================================================================
# Main Cleanup Flow
# ============================================================================

main() {
    local force_mode=false
    local delete_project_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_mode=true
                shift
                ;;
            --delete-project)
                delete_project_mode=true
                shift
                ;;
            --dry-run)
                info "DRY RUN MODE - No resources will be deleted"
                load_deployment_info
                check_prerequisites
                info "Would delete the following resources:"
                info "  Project: $PROJECT_ID"
                info "  Region: $REGION"
                info "  Function: ${FUNCTION_NAME:-all habit-tracker functions}"
                info "  Firestore data in 'habits' collection"
                info "Dry run completed"
                exit 0
                ;;
            --help|-h)
                cat << EOF
GCP Habit Tracker Cleanup Script

Usage: $0 [OPTIONS]

Options:
  --force          Skip confirmation prompts
  --delete-project Delete the entire GCP project
  --dry-run        Show what would be deleted without doing it
  --help, -h       Show this help message

Environment Variables:
  PROJECT_ID    GCP project ID (required)
  REGION        GCP region (default: us-central1)
  FUNCTION_NAME Function name (auto-discovered if not set)

Examples:
  $0                        # Interactive cleanup
  $0 --force               # Skip confirmations
  $0 --delete-project      # Delete entire project
  $0 --dry-run            # Preview cleanup actions
  PROJECT_ID=my-project $0 # Use specific project

Warning: This script will permanently delete resources!
EOF
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                error "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    info "Starting GCP Habit Tracker cleanup..."
    info "Log file: $LOG_FILE"
    
    # Execute cleanup steps
    load_deployment_info
    check_prerequisites
    confirm_deletion "$force_mode"
    delete_cloud_functions
    delete_firestore_data
    cleanup_iam
    delete_project "$delete_project_mode"
    
    if [[ "$delete_project_mode" != "true" ]]; then
        verify_cleanup
        cleanup_deployment_files
    fi
    
    success "=========================================="
    success "Cleanup completed successfully!"
    success "=========================================="
    
    if [[ "$delete_project_mode" == "true" ]]; then
        success "Project deletion initiated: $PROJECT_ID"
        success "Project deletion may take several minutes to complete"
    else
        success "Resources cleaned up in project: $PROJECT_ID"
        success ""
        success "Manual steps still required:"
        success "1. Delete Firestore database at: https://console.cloud.google.com/firestore/databases?project=$PROJECT_ID"
        success "2. Review any remaining resources in the Cloud Console"
        success ""
        success "To delete the entire project, run: $0 --delete-project"
    fi
    
    success "=========================================="
}

# Run main function
main "$@"