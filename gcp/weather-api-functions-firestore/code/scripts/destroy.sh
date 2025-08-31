#!/bin/bash

# Weather API with Cloud Functions and Firestore - Destruction Script
# This script safely removes all resources created for the weather API solution
# including Cloud Functions, Firestore data, and optionally the entire project

set -euo pipefail

# Color codes for output formatting
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate gcloud authentication
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found"
        log_info "Please run: gcloud auth login"
        return 1
    fi
    return 0
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Please install it from: https://cloud.google.com/sdk/docs/install"
        return 1
    fi
    
    # Check authentication
    if ! check_gcloud_auth; then
        return 1
    fi
    
    log_success "Prerequisites check passed"
    return 0
}

# Function to confirm destructive actions
confirm_action() {
    local message="$1"
    local force="$2"
    
    if [[ "${force}" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo -e "${YELLOW}[CONFIRM]${NC} ${message}"
    echo -n "Type 'yes' to confirm: "
    read -r response
    
    if [[ "${response}" != "yes" ]]; then
        log_info "Operation cancelled by user"
        return 1
    fi
    
    return 0
}

# Function to check if project exists
project_exists() {
    local project_id="$1"
    
    if gcloud projects describe "${project_id}" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to check if function exists
function_exists() {
    local function_name="$1"
    local region="$2"
    local project_id="$3"
    
    if gcloud functions describe "${function_name}" \
        --region="${region}" \
        --project="${project_id}" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to check if Firestore database exists
firestore_exists() {
    local project_id="$1"
    
    if gcloud firestore databases describe \
        --database="(default)" \
        --project="${project_id}" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to delete Cloud Function
delete_function() {
    local function_name="$1"
    local region="$2"
    local project_id="$3"
    local force="$4"
    
    log_info "Checking for Cloud Function ${function_name}..."
    
    if ! function_exists "${function_name}" "${region}" "${project_id}"; then
        log_info "Cloud Function ${function_name} does not exist - skipping"
        return 0
    fi
    
    if ! confirm_action "Delete Cloud Function ${function_name}?" "${force}"; then
        log_info "Skipping Cloud Function deletion"
        return 0
    fi
    
    log_info "Deleting Cloud Function ${function_name}..."
    if gcloud functions delete "${function_name}" \
        --region="${region}" \
        --project="${project_id}" \
        --quiet; then
        log_success "Cloud Function ${function_name} deleted successfully"
    else
        log_error "Failed to delete Cloud Function ${function_name}"
        return 1
    fi
    
    return 0
}

# Function to clear Firestore data
clear_firestore_data() {
    local project_id="$1"
    local force="$2"
    
    log_info "Checking for Firestore database..."
    
    if ! firestore_exists "${project_id}"; then
        log_info "Firestore database does not exist - skipping"
        return 0
    fi
    
    if ! confirm_action "Clear all Firestore data? This will delete the weather_cache collection and all documents." "${force}"; then
        log_info "Skipping Firestore data clearing"
        return 0
    fi
    
    log_info "Clearing Firestore weather_cache collection..."
    
    # Use gcloud firestore delete command to remove the collection
    # Note: This is a recursive delete that removes all documents in the collection
    if gcloud firestore export gs://${project_id}-temp-firestore-backup \
        --collection-ids=weather_cache \
        --project="${project_id}" \
        --async >/dev/null 2>&1 || true; then
        
        # Delete the collection documents (this is a workaround as there's no direct collection delete)
        log_info "Attempting to clear weather_cache collection documents..."
        
        # Create a small script to delete documents
        local delete_script
        delete_script=$(mktemp)
        cat > "${delete_script}" << 'EOF'
from google.cloud import firestore
import sys

try:
    db = firestore.Client()
    collection_ref = db.collection('weather_cache')
    
    # Get all documents
    docs = collection_ref.stream()
    
    # Delete documents in batches
    batch = db.batch()
    count = 0
    
    for doc in docs:
        batch.delete(doc.reference)
        count += 1
        
        # Commit batch every 500 operations
        if count % 500 == 0:
            batch.commit()
            batch = db.batch()
    
    # Commit any remaining operations
    if count % 500 != 0:
        batch.commit()
    
    print(f"Deleted {count} documents from weather_cache collection")
    
except Exception as e:
    print(f"Error deleting Firestore documents: {e}")
    sys.exit(1)
EOF
        
        # Run the deletion script if Python is available
        if command_exists python3 && python3 -c "import google.cloud.firestore" 2>/dev/null; then
            log_info "Deleting Firestore documents using Python client..."
            if GOOGLE_CLOUD_PROJECT="${project_id}" python3 "${delete_script}"; then
                log_success "Firestore weather_cache collection cleared"
            else
                log_warning "Failed to clear Firestore documents using Python client"
            fi
        else
            log_warning "Python3 or Firestore client library not available - documents may remain"
            log_info "You can manually delete documents from the Firebase Console"
        fi
        
        # Clean up temporary script
        rm -f "${delete_script}"
    else
        log_warning "Could not clear Firestore data - continuing with other cleanup"
    fi
    
    return 0
}

# Function to delete Firestore database
delete_firestore_database() {
    local project_id="$1"
    local force="$2"
    
    log_info "Checking for Firestore database..."
    
    if ! firestore_exists "${project_id}"; then
        log_info "Firestore database does not exist - skipping"
        return 0
    fi
    
    if ! confirm_action "Delete entire Firestore database? This will permanently remove ALL data in the database." "${force}"; then
        log_info "Skipping Firestore database deletion"
        return 0
    fi
    
    log_info "Deleting Firestore database..."
    if gcloud firestore databases delete \
        --database="(default)" \
        --project="${project_id}" \
        --quiet; then
        log_success "Firestore database deleted successfully"
    else
        log_error "Failed to delete Firestore database"
        return 1
    fi
    
    return 0
}

# Function to delete the entire project
delete_project() {
    local project_id="$1"
    local force="$2"
    
    if ! confirm_action "Delete entire project ${project_id}? This will permanently remove ALL resources in the project." "${force}"; then
        log_info "Skipping project deletion"
        return 0
    fi
    
    log_info "Deleting project ${project_id}..."
    if gcloud projects delete "${project_id}" --quiet; then
        log_success "Project ${project_id} deletion initiated"
        log_info "Note: Project deletion may take several minutes to complete"
    else
        log_error "Failed to delete project ${project_id}"
        return 1
    fi
    
    return 0
}

# Function to clean up temporary resources (storage buckets created during function deployment)
cleanup_temp_resources() {
    local project_id="$1"
    local force="$2"
    
    log_info "Checking for temporary Cloud Build storage buckets..."
    
    # List Cloud Build buckets (these are created automatically during function deployment)
    local buckets
    buckets=$(gsutil ls -p "${project_id}" 2>/dev/null | grep "gs://.*_cloudbuild" || echo "")
    
    if [[ -n "${buckets}" ]]; then
        log_info "Found Cloud Build storage buckets"
        
        if confirm_action "Delete temporary Cloud Build storage buckets?" "${force}"; then
            for bucket in ${buckets}; do
                log_info "Deleting bucket ${bucket}..."
                if gsutil rm -r "${bucket}" 2>/dev/null; then
                    log_success "Deleted bucket ${bucket}"
                else
                    log_warning "Failed to delete bucket ${bucket} (may not exist or already deleted)"
                fi
            done
        else
            log_info "Skipping temporary bucket cleanup"
        fi
    else
        log_info "No temporary Cloud Build buckets found"
    fi
    
    return 0
}

# Function to display current resources before deletion
display_resources() {
    local project_id="$1"
    local region="$2"
    local function_name="$3"
    
    log_info "=== CURRENT RESOURCES IN PROJECT ${project_id} ==="
    
    # Check for Cloud Functions
    log_info "Cloud Functions:"
    if function_exists "${function_name}" "${region}" "${project_id}"; then
        echo "  ✓ ${function_name} (${region})"
    else
        echo "  - No matching Cloud Functions found"
    fi
    
    # Check for Firestore
    log_info "Firestore Database:"
    if firestore_exists "${project_id}"; then
        echo "  ✓ Default Firestore database exists"
        
        # Try to count documents in weather_cache collection if possible
        if command_exists python3 && python3 -c "import google.cloud.firestore" 2>/dev/null; then
            local doc_count
            doc_count=$(GOOGLE_CLOUD_PROJECT="${project_id}" python3 -c "
from google.cloud import firestore
try:
    db = firestore.Client()
    collection_ref = db.collection('weather_cache')
    docs = list(collection_ref.stream())
    print(len(docs))
except:
    print('unknown')
" 2>/dev/null || echo "unknown")
            echo "  - weather_cache collection: ${doc_count} documents"
        else
            echo "  - weather_cache collection: status unknown (Python client not available)"
        fi
    else
        echo "  - No Firestore database found"
    fi
    
    # Check for storage buckets
    log_info "Storage Buckets:"
    local bucket_count
    bucket_count=$(gsutil ls -p "${project_id}" 2>/dev/null | wc -l || echo "0")
    echo "  - Total buckets: ${bucket_count}"
    
    echo
}

# Function to display deletion summary
display_summary() {
    local project_id="$1"
    local delete_project="$2"
    
    echo
    log_success "=== CLEANUP SUMMARY ==="
    echo -e "${GREEN}Project ID:${NC} ${project_id}"
    
    if [[ "${delete_project}" == "true" ]]; then
        echo -e "${GREEN}Action:${NC} Entire project deleted"
        echo
        log_info "The project ${project_id} has been scheduled for deletion."
        log_info "It may take several minutes for the deletion to complete."
        log_info "You can check the status in the Cloud Console."
    else
        echo -e "${GREEN}Action:${NC} Individual resources cleaned up"
        echo
        log_info "Individual resources have been cleaned up."
        log_info "The project ${project_id} remains active."
        log_info "You may want to disable APIs to avoid any ongoing charges:"
        echo "  gcloud services disable cloudfunctions.googleapis.com --project=${project_id}"
        echo "  gcloud services disable firestore.googleapis.com --project=${project_id}"
    fi
    echo
}

# Main destruction function
main() {
    log_info "Starting Weather API resource cleanup..."
    
    # Set default values
    local project_id="${PROJECT_ID:-}"
    local region="${REGION:-us-central1}"
    local function_name="${FUNCTION_NAME:-weather-api}"
    local delete_project="false"
    local force="false"
    local clear_data_only="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                project_id="$2"
                shift 2
                ;;
            --region)
                region="$2"
                shift 2
                ;;
            --function-name)
                function_name="$2"
                shift 2
                ;;
            --delete-project)
                delete_project="true"
                shift
                ;;
            --clear-data-only)
                clear_data_only="true"
                shift
                ;;
            --force)
                force="true"
                shift
                ;;
            --dry-run)
                log_info "Dry run mode - would clean up resources with the following configuration:"
                echo "  Project ID: ${project_id:-<from gcloud config>}"
                echo "  Region: ${region}"
                echo "  Function Name: ${function_name}"
                echo "  Delete Project: ${delete_project}"
                echo "  Clear Data Only: ${clear_data_only}"
                echo "  Force Mode: ${force}"
                exit 0
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --project-id PROJECT_ID    GCP project ID (default: from gcloud config)"
                echo "  --region REGION            GCP region (default: us-central1)"
                echo "  --function-name NAME       Function name to delete (default: weather-api)"
                echo "  --delete-project           Delete the entire project (WARNING: destroys ALL resources)"
                echo "  --clear-data-only          Only clear Firestore data, keep other resources"
                echo "  --force                    Skip confirmation prompts (dangerous!)"
                echo "  --dry-run                  Show what would be deleted without actually deleting"
                echo "  -h, --help                 Show this help message"
                echo
                echo "Examples:"
                echo "  $0                                    # Interactive cleanup of individual resources"
                echo "  $0 --project-id my-project          # Cleanup specific project"
                echo "  $0 --delete-project --force         # Delete entire project without prompts"
                echo "  $0 --clear-data-only                # Only clear Firestore cache data"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Get project ID from gcloud config if not provided
    if [[ -z "${project_id}" ]]; then
        project_id=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${project_id}" ]]; then
            log_error "No project ID specified and no default project set in gcloud config"
            log_info "Use --project-id or set default with: gcloud config set project PROJECT_ID"
            exit 1
        fi
        log_info "Using project ID from gcloud config: ${project_id}"
    fi
    
    # Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    
    # Check if project exists
    if ! project_exists "${project_id}"; then
        log_error "Project ${project_id} does not exist or you don't have access"
        exit 1
    fi
    
    # Set project configuration
    gcloud config set project "${project_id}"
    
    # Display current resources
    display_resources "${project_id}" "${region}" "${function_name}"
    
    # Execute cleanup based on options
    if [[ "${delete_project}" == "true" ]]; then
        # Delete entire project
        log_warning "WARNING: This will delete the ENTIRE project and ALL resources within it!"
        if delete_project "${project_id}" "${force}"; then
            display_summary "${project_id}" "true"
            log_success "Project deletion initiated successfully!"
            exit 0
        else
            log_error "Project deletion failed"
            exit 1
        fi
        
    elif [[ "${clear_data_only}" == "true" ]]; then
        # Only clear Firestore data
        if clear_firestore_data "${project_id}" "${force}"; then
            log_success "Firestore data cleared successfully!"
            exit 0
        else
            log_error "Failed to clear Firestore data"
            exit 1
        fi
        
    else
        # Individual resource cleanup
        local cleanup_success=true
        
        # Delete Cloud Function
        if ! delete_function "${function_name}" "${region}" "${project_id}" "${force}"; then
            cleanup_success=false
        fi
        
        # Clear Firestore data (but keep database)
        if ! clear_firestore_data "${project_id}" "${force}"; then
            cleanup_success=false
        fi
        
        # Clean up temporary resources
        if ! cleanup_temp_resources "${project_id}" "${force}"; then
            log_warning "Failed to clean up some temporary resources"
        fi
        
        # Optionally delete Firestore database
        if confirm_action "Also delete the entire Firestore database?" "${force}"; then
            if ! delete_firestore_database "${project_id}" "${force}"; then
                cleanup_success=false
            fi
        fi
        
        if [[ "${cleanup_success}" == "true" ]]; then
            display_summary "${project_id}" "false"
            log_success "Resource cleanup completed successfully!"
        else
            log_error "Some cleanup operations failed"
            exit 1
        fi
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi