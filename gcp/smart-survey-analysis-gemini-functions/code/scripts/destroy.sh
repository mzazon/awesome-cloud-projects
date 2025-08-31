#!/bin/bash

##############################################################################
# GCP Smart Survey Analysis with Gemini and Cloud Functions - Cleanup Script
# 
# This script safely removes all infrastructure created for the survey analysis
# solution, including Cloud Functions, Firestore data, and associated resources.
##############################################################################

set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove GCP Smart Survey Analysis infrastructure

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           Deployment region (auto-detected if not provided)
    -n, --function-name NAME      Cloud Function name (auto-detected if not provided)
    -d, --database-name NAME      Firestore database name (auto-detected if not provided)
    --delete-project              Delete the entire GCP project (DESTRUCTIVE)
    --preserve-data               Keep Firestore data, only remove compute resources
    --dry-run                     Show what would be deleted without executing
    --force                       Skip confirmation prompts
    --from-state                  Load configuration from saved deployment state
    -h, --help                    Show this help message

EXAMPLES:
    $0 -p my-survey-project --from-state
    $0 -p my-project -r europe-west1 -n my-analyzer
    $0 --project-id my-project --dry-run
    $0 -p my-project --delete-project --force

SAFETY FEATURES:
    - Confirmation prompts for destructive operations
    - Dry-run mode to preview changes
    - Selective cleanup options
    - Automatic state file cleanup

EOF
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    local state_file="${SCRIPT_DIR}/.deploy_state"
    
    if [[ ! -f "${state_file}" ]]; then
        log_warning "No deployment state file found at ${state_file}"
        return 1
    fi
    
    log_info "Loading deployment state from ${state_file}"
    
    # Source the state file to load variables
    if source "${state_file}"; then
        log_success "Deployment state loaded successfully"
        log_info "Deployment time: ${DEPLOYMENT_TIME:-unknown}"
        return 0
    else
        log_error "Failed to load deployment state file"
        return 1
    fi
}

# Function to validate project
validate_project() {
    local project_id="$1"
    
    log_info "Validating project: ${project_id}"
    
    if ! gcloud projects describe "${project_id}" &> /dev/null; then
        log_error "Project '${project_id}' not found or not accessible"
        exit 1
    fi
    
    log_success "Project validation completed"
}

# Function to list resources to be deleted
list_resources() {
    local project_id="$1"
    local region="$2"
    local function_name="$3"
    local database_name="$4"
    local preserve_data="$5"
    
    log_info "=== RESOURCES TO BE DELETED ==="
    echo
    
    # List Cloud Functions
    log_info "Cloud Functions:"
    if gcloud functions describe "${function_name}" --region="${region}" --project="${project_id}" &> /dev/null; then
        echo "  ✓ ${function_name} (${region})"
    else
        echo "  ✗ ${function_name} (not found)"
    fi
    
    # List Firestore resources
    log_info "Firestore:"
    if [[ "${preserve_data}" == "true" ]]; then
        echo "  ⚠ Database data will be PRESERVED"
    else
        echo "  ✓ All documents in 'survey_analyses' collection"
        if [[ "${database_name}" != "(default)" ]]; then
            echo "  ✓ Database: ${database_name}"
        fi
    fi
    
    # Check for existing data
    if command -v python3 &> /dev/null; then
        local doc_count
        doc_count=$(python3 -c "
import os
from google.cloud import firestore
try:
    os.environ['GOOGLE_CLOUD_PROJECT'] = '${project_id}'
    db = firestore.Client()
    count = len(list(db.collection('survey_analyses').limit(100).stream()))
    print(count)
except Exception:
    print('unknown')
" 2>/dev/null || echo "unknown")
        
        if [[ "${doc_count}" != "unknown" ]] && [[ "${doc_count}" -gt 0 ]]; then
            log_warning "Found ${doc_count} analysis documents that will be deleted"
        fi
    fi
    
    echo
}

# Function to delete Cloud Function
delete_function() {
    local project_id="$1"
    local region="$2"
    local function_name="$3"
    local dry_run="$4"
    
    log_info "Deleting Cloud Function: ${function_name}"
    
    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN: Would delete function ${function_name}"
        return 0
    fi
    
    # Check if function exists
    if ! gcloud functions describe "${function_name}" --region="${region}" --project="${project_id}" &> /dev/null; then
        log_warning "Function ${function_name} not found, skipping"
        return 0
    fi
    
    # Delete the function
    if gcloud functions delete "${function_name}" \
        --region="${region}" \
        --project="${project_id}" \
        --quiet; then
        log_success "Cloud Function deleted: ${function_name}"
    else
        log_error "Failed to delete Cloud Function: ${function_name}"
        return 1
    fi
}

# Function to clear Firestore data
clear_firestore_data() {
    local project_id="$1"
    local preserve_data="$2"
    local dry_run="$3"
    
    if [[ "${preserve_data}" == "true" ]]; then
        log_info "Preserving Firestore data as requested"
        return 0
    fi
    
    log_info "Clearing Firestore data..."
    
    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN: Would delete all documents in 'survey_analyses' collection"
        return 0
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_warning "Python 3 not available, skipping Firestore data cleanup"
        log_info "Manually delete data from the Google Cloud Console if needed"
        return 0
    fi
    
    # Delete all documents in the survey_analyses collection
    local cleanup_result
    cleanup_result=$(python3 -c "
import os
from google.cloud import firestore

try:
    os.environ['GOOGLE_CLOUD_PROJECT'] = '${project_id}'
    db = firestore.Client()
    
    # Get all documents
    docs = list(db.collection('survey_analyses').stream())
    
    if not docs:
        print('no_documents')
    else:
        # Delete documents in batches
        batch_size = 500
        deleted_count = 0
        
        for i in range(0, len(docs), batch_size):
            batch = db.batch()
            batch_docs = docs[i:i + batch_size]
            
            for doc in batch_docs:
                batch.delete(doc.reference)
            
            batch.commit()
            deleted_count += len(batch_docs)
        
        print(f'deleted_{deleted_count}')
        
except Exception as e:
    print(f'error_{str(e)}')
" 2>/dev/null)
    
    case "${cleanup_result}" in
        no_documents)
            log_info "No documents found in survey_analyses collection"
            ;;
        deleted_*)
            local count="${cleanup_result#deleted_}"
            log_success "Deleted ${count} documents from Firestore"
            ;;
        error_*)
            local error="${cleanup_result#error_}"
            log_error "Failed to clear Firestore data: ${error}"
            return 1
            ;;
        *)
            log_warning "Unknown result from Firestore cleanup: ${cleanup_result}"
            ;;
    esac
}

# Function to delete Firestore database
delete_firestore_database() {
    local project_id="$1"
    local database_name="$2"
    local preserve_data="$3"
    local dry_run="$4"
    
    # Skip database deletion for default database or if preserving data
    if [[ "${database_name}" == "(default)" ]] || [[ "${preserve_data}" == "true" ]]; then
        log_info "Skipping database deletion (default database or data preservation requested)"
        return 0
    fi
    
    log_info "Deleting Firestore database: ${database_name}"
    
    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN: Would delete database ${database_name}"
        return 0
    fi
    
    # Check if database exists
    if ! gcloud firestore databases describe "${database_name}" --project="${project_id}" &> /dev/null; then
        log_warning "Database ${database_name} not found, skipping"
        return 0
    fi
    
    # Note: Firestore database deletion is not supported via gcloud CLI
    # The database would need to be deleted manually from the console
    log_warning "Firestore database deletion must be done manually from the Google Cloud Console"
    log_info "Navigate to: https://console.cloud.google.com/firestore/databases?project=${project_id}"
}

# Function to delete entire project
delete_project() {
    local project_id="$1"
    local dry_run="$2"
    local force="$3"
    
    log_warning "DESTRUCTIVE OPERATION: Deleting entire project ${project_id}"
    
    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN: Would delete entire project ${project_id}"
        return 0
    fi
    
    if [[ "${force}" != "true" ]]; then
        echo
        log_warning "This will permanently delete the entire project and ALL its resources!"
        echo -n "Type the project ID '${project_id}' to confirm: "
        read -r confirmation
        if [[ "${confirmation}" != "${project_id}" ]]; then
            log_info "Project deletion cancelled"
            return 0
        fi
    fi
    
    # Delete the project
    if gcloud projects delete "${project_id}" --quiet; then
        log_success "Project deleted: ${project_id}"
        log_info "Project deletion may take several minutes to complete"
    else
        log_error "Failed to delete project: ${project_id}"
        return 1
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    local dry_run="$1"
    
    log_info "Cleaning up local files..."
    
    local state_file="${SCRIPT_DIR}/.deploy_state"
    
    if [[ "${dry_run}" == "true" ]]; then
        if [[ -f "${state_file}" ]]; then
            log_info "DRY RUN: Would delete deployment state file"
        fi
        return 0
    fi
    
    if [[ -f "${state_file}" ]]; then
        rm -f "${state_file}"
        log_success "Deployment state file removed"
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    local project_id="$1"
    local deleted_resources="$2"
    local preserve_data="$3"
    
    echo
    log_success "=== CLEANUP COMPLETED ==="
    echo
    echo "Project ID: ${project_id}"
    echo "Resources removed: ${deleted_resources}"
    
    if [[ "${preserve_data}" == "true" ]]; then
        echo "Data preservation: Firestore data was preserved"
    fi
    
    echo
    echo "Cleanup verification:"
    echo "- Check Google Cloud Console to confirm resource removal"
    echo "- Verify billing to ensure no unexpected charges"
    echo
}

# Main cleanup function
main() {
    local project_id=""
    local region=""
    local function_name=""
    local database_name=""
    local delete_project_flag="false"
    local preserve_data="false"
    local dry_run="false"
    local force="false"
    local from_state="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                project_id="$2"
                shift 2
                ;;
            -r|--region)
                region="$2"
                shift 2
                ;;
            -n|--function-name)
                function_name="$2"
                shift 2
                ;;
            -d|--database-name)
                database_name="$2"
                shift 2
                ;;
            --delete-project)
                delete_project_flag="true"
                shift
                ;;
            --preserve-data)
                preserve_data="true"
                shift
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --force)
                force="true"
                shift
                ;;
            --from-state)
                from_state="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Load from state file if requested
    if [[ "${from_state}" == "true" ]]; then
        if load_deployment_state; then
            # Override with loaded values if not provided
            project_id="${project_id:-${PROJECT_ID}}"
            region="${region:-${REGION}}"
            function_name="${function_name:-${FUNCTION_NAME}}"
            database_name="${database_name:-${DATABASE_NAME}}"
        else
            log_error "Cannot load deployment state. Provide parameters manually."
            exit 1
        fi
    fi
    
    # Validate required parameters
    if [[ -z "${project_id}" ]]; then
        log_error "Project ID is required"
        usage
        exit 1
    fi
    
    # Set defaults if not provided
    region="${region:-us-central1}"
    database_name="${database_name:-survey-db}"
    
    # If function name not provided, try to find it
    if [[ -z "${function_name}" ]]; then
        log_info "Searching for Cloud Functions in project..."
        local functions
        functions=$(gcloud functions list --project="${project_id}" --filter="name:survey-analyzer" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${functions}" ]]; then
            function_name=$(echo "${functions}" | head -n1 | sed 's|.*/||')
            log_info "Found function: ${function_name}"
        else
            log_warning "No survey analyzer functions found. Some cleanup may be skipped."
            function_name="survey-analyzer-unknown"
        fi
    fi
    
    # Display configuration
    log_info "=== CLEANUP CONFIGURATION ==="
    echo "Project ID:       ${project_id}"
    echo "Region:           ${region}"
    echo "Function Name:    ${function_name}"
    echo "Database Name:    ${database_name}"
    echo "Delete Project:   ${delete_project_flag}"
    echo "Preserve Data:    ${preserve_data}"
    echo "Dry Run:          ${dry_run}"
    echo "Force:            ${force}"
    echo
    
    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Start cleanup process
    check_prerequisites
    validate_project "${project_id}"
    
    # Set project context
    gcloud config set project "${project_id}" &>/dev/null
    
    # List resources to be deleted
    list_resources "${project_id}" "${region}" "${function_name}" "${database_name}" "${preserve_data}"
    
    # Confirm cleanup unless force flag is set
    if [[ "${force}" != "true" ]] && [[ "${dry_run}" != "true" ]]; then
        echo -n "Do you want to proceed with the cleanup? (y/N): "
        read -r confirmation
        if [[ ! "${confirmation}" =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup
    log_info "Starting cleanup..."
    
    local deleted_resources=""
    
    # Handle project deletion (this deletes everything)
    if [[ "${delete_project_flag}" == "true" ]]; then
        delete_project "${project_id}" "${dry_run}" "${force}"
        deleted_resources="entire project"
    else
        # Individual resource cleanup
        if delete_function "${project_id}" "${region}" "${function_name}" "${dry_run}"; then
            deleted_resources="${deleted_resources}function "
        fi
        
        if clear_firestore_data "${project_id}" "${preserve_data}" "${dry_run}"; then
            if [[ "${preserve_data}" != "true" ]]; then
                deleted_resources="${deleted_resources}data "
            fi
        fi
        
        delete_firestore_database "${project_id}" "${database_name}" "${preserve_data}" "${dry_run}"
    fi
    
    # Cleanup local files
    cleanup_local_files "${dry_run}"
    
    if [[ "${dry_run}" != "true" ]]; then
        show_cleanup_summary "${project_id}" "${deleted_resources:-none}" "${preserve_data}"
    else
        log_info "DRY RUN completed - no resources were actually deleted"
    fi
}

# Execute main function with all arguments
main "$@"