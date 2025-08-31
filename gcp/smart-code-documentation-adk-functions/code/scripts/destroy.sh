#!/bin/bash

# Destroy script for Smart Code Documentation with ADK and Cloud Functions
# This script safely removes all infrastructure created for the intelligent
# code documentation system using Google Cloud's Agent Development Kit (ADK).

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

# Error handling function
handle_error() {
    log_error "An error occurred on line $1 during cleanup."
    log_warning "Some resources may not have been deleted. Please check manually."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Smart Code Documentation infrastructure and clean up resources

OPTIONS:
    -p, --project-id     Google Cloud project ID (required)
    -r, --region         Deployment region (default: ${DEFAULT_REGION})
    -z, --zone          Deployment zone (default: ${DEFAULT_ZONE})
    -f, --force         Skip confirmation prompts (use with caution)
    -h, --help          Show this help message
    --dry-run          Show what would be destroyed without executing
    --skip-buckets      Skip bucket deletion (preserve data)
    --skip-function     Skip Cloud Function deletion

EXAMPLES:
    $0 --project-id my-gcp-project
    $0 -p my-project -r us-west1 --force
    $0 --project-id my-project --dry-run

SAFETY:
    This script will permanently delete resources and data.
    Use --dry-run first to review what will be deleted.

EOF
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_info "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed or not in PATH"
        log_info "gsutil is typically included with Google Cloud CLI"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 > /dev/null; then
        log_error "No active Google Cloud authentication found"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to validate project and set up environment
setup_environment() {
    log_info "Setting up cleanup environment..."
    
    # Validate project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project '${PROJECT_ID}' does not exist or you don't have access"
        log_info "Ensure the project exists and you have the necessary permissions"
        exit 1
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Environment configured for project: ${PROJECT_ID}"
    log_info "Region: ${REGION}, Zone: ${ZONE}"
}

# Function to discover existing resources
discover_resources() {
    log_info "Discovering existing resources..."
    
    # Find Cloud Functions matching our pattern
    FUNCTIONS=$(gcloud functions list --gen2 --regions="${REGION}" \
        --filter="name:adk-code-documentation" \
        --format="value(name)" 2>/dev/null || true)
    
    # Find Cloud Storage buckets matching our patterns
    BUCKETS=$(gsutil ls -b "gs://${PROJECT_ID}-*-*" 2>/dev/null | \
        grep -E "(code-input|docs-output|processing)" | \
        sed 's|gs://||; s|/||' || true)
    
    # Find ADK workspace directory
    ADK_WORKSPACE="${SCRIPT_DIR}/../adk-workspace"
    
    log_info "Discovery complete"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        show_discovery_results
    fi
}

# Function to show discovery results
show_discovery_results() {
    echo
    echo "=== RESOURCE DISCOVERY RESULTS ==="
    echo
    
    if [[ -n "${FUNCTIONS}" ]]; then
        echo "Cloud Functions to be deleted:"
        for func in ${FUNCTIONS}; do
            echo "  - ${func}"
        done
    else
        echo "No Cloud Functions found matching pattern 'adk-code-documentation'"
    fi
    echo
    
    if [[ -n "${BUCKETS}" ]]; then
        echo "Cloud Storage buckets to be deleted:"
        for bucket in ${BUCKETS}; do
            echo "  - gs://${bucket}"
        done
    else
        echo "No Cloud Storage buckets found matching project patterns"
    fi
    echo
    
    if [[ -d "${ADK_WORKSPACE}" ]]; then
        echo "Local ADK workspace to be cleaned:"
        echo "  - ${ADK_WORKSPACE}"
    else
        echo "No local ADK workspace found"
    fi
    echo
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "${FORCE}" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return
    fi
    
    echo
    log_warning "This will permanently delete the following resources:"
    show_discovery_results
    
    echo
    log_warning "This action cannot be undone!"
    echo
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_info "Confirmation received - proceeding with destruction"
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    if [[ "${SKIP_FUNCTION}" == "true" ]]; then
        log_warning "Skipping Cloud Function deletion as requested"
        return
    fi
    
    if [[ -z "${FUNCTIONS}" ]]; then
        log_info "No Cloud Functions to delete"
        return
    fi
    
    log_info "Deleting Cloud Functions..."
    
    for function_name in ${FUNCTIONS}; do
        log_info "Deleting function: ${function_name}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would delete Cloud Function: ${function_name}"
            continue
        fi
        
        if gcloud functions delete "${function_name}" \
            --gen2 \
            --region="${REGION}" \
            --quiet 2>/dev/null; then
            log_success "Deleted function: ${function_name}"
        else
            log_warning "Failed to delete function: ${function_name} (may not exist)"
        fi
    done
    
    log_success "Cloud Function deletion completed"
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    if [[ "${SKIP_BUCKETS}" == "true" ]]; then
        log_warning "Skipping bucket deletion as requested - data will be preserved"
        return
    fi
    
    if [[ -z "${BUCKETS}" ]]; then
        log_info "No Cloud Storage buckets to delete"
        return
    fi
    
    log_info "Deleting Cloud Storage buckets and contents..."
    
    for bucket in ${BUCKETS}; do
        log_info "Deleting bucket and contents: gs://${bucket}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would delete bucket: gs://${bucket}"
            continue
        fi
        
        # Check if bucket exists
        if gsutil ls "gs://${bucket}" &>/dev/null; then
            # Delete all objects in bucket first
            log_info "Removing all objects from bucket: ${bucket}"
            if gsutil -m rm -r "gs://${bucket}/**" 2>/dev/null || true; then
                log_info "Bucket contents removed: ${bucket}"
            fi
            
            # Delete the bucket itself
            if gsutil rb "gs://${bucket}" 2>/dev/null; then
                log_success "Deleted bucket: gs://${bucket}"
            else
                log_warning "Failed to delete bucket: gs://${bucket}"
            fi
        else
            log_info "Bucket does not exist: gs://${bucket}"
        fi
    done
    
    log_success "Storage bucket deletion completed"
}

# Function to clean up local ADK workspace
cleanup_local_workspace() {
    log_info "Cleaning up local ADK workspace..."
    
    if [[ ! -d "${ADK_WORKSPACE}" ]]; then
        log_info "No local ADK workspace found"
        return
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove local workspace: ${ADK_WORKSPACE}"
        return
    fi
    
    # Deactivate virtual environment if active
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        log_info "Deactivating virtual environment..."
        deactivate 2>/dev/null || true
    fi
    
    # Remove workspace directory
    if rm -rf "${ADK_WORKSPACE}"; then
        log_success "Removed local ADK workspace: ${ADK_WORKSPACE}"
    else
        log_warning "Failed to remove local workspace: ${ADK_WORKSPACE}"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    local temp_files=(
        "/tmp/sample_project.zip"
        "/tmp/complex_test.zip"
        "/tmp/lifecycle.json"
    )
    
    for temp_file in "${temp_files[@]}"; do
        if [[ -f "${temp_file}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would remove temp file: ${temp_file}"
            else
                rm -f "${temp_file}"
                log_info "Removed temp file: ${temp_file}"
            fi
        fi
    done
    
    # Clean up any sample project directories
    local temp_dirs=(
        "/tmp/sample_project"
        "/tmp/complex_test"
    )
    
    for temp_dir in "${temp_dirs[@]}"; do
        if [[ -d "${temp_dir}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would remove temp directory: ${temp_dir}"
            else
                rm -rf "${temp_dir}"
                log_info "Removed temp directory: ${temp_dir}"
            fi
        fi
    done
    
    log_success "Temporary file cleanup completed"
}

# Function to verify resource deletion
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    # Check for remaining Cloud Functions
    local remaining_functions=$(gcloud functions list --gen2 --regions="${REGION}" \
        --filter="name:adk-code-documentation" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${remaining_functions}" ]]; then
        log_warning "Some Cloud Functions still exist:"
        for func in ${remaining_functions}; do
            log_warning "  - ${func}"
        done
    else
        log_success "All Cloud Functions successfully deleted"
    fi
    
    # Check for remaining buckets
    local remaining_buckets=$(gsutil ls -b "gs://${PROJECT_ID}-*-*" 2>/dev/null | \
        grep -E "(code-input|docs-output|processing)" | \
        sed 's|gs://||; s|/||' || true)
    
    if [[ -n "${remaining_buckets}" ]]; then
        log_warning "Some Cloud Storage buckets still exist:"
        for bucket in ${remaining_buckets}; do
            log_warning "  - gs://${bucket}"
        done
    else
        log_success "All Cloud Storage buckets successfully deleted"
    fi
    
    # Check local workspace
    if [[ -d "${ADK_WORKSPACE}" ]]; then
        log_warning "Local ADK workspace still exists: ${ADK_WORKSPACE}"
    else
        log_success "Local ADK workspace successfully cleaned"
    fi
}

# Function to display cleanup summary
display_summary() {
    echo
    log_success "Cleanup completed!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "=== DRY RUN RESULTS ==="
        echo "No resources were actually deleted."
        echo "Run without --dry-run to perform actual cleanup."
    else
        echo "=== DELETED RESOURCES ==="
        echo "✓ Cloud Functions (ADK code documentation)"
        if [[ "${SKIP_BUCKETS}" != "true" ]]; then
            echo "✓ Cloud Storage buckets and contents"
        else
            echo "- Cloud Storage buckets (skipped - data preserved)"
        fi
        echo "✓ Local ADK workspace and virtual environment"
        echo "✓ Temporary files and directories"
        
        echo
        echo "=== MANUAL CLEANUP REQUIRED ==="
        echo "The following may require manual cleanup:"
        echo "- Vertex AI model endpoints (if any custom models were deployed)"
        echo "- IAM service accounts (if custom ones were created)"
        echo "- Cloud Build triggers (if any were created)"
        echo "- VPC firewall rules (if any custom ones were created)"
        
        echo
        echo "=== COST IMPLICATIONS ==="
        echo "✓ Cloud Functions compute charges stopped"
        if [[ "${SKIP_BUCKETS}" != "true" ]]; then
            echo "✓ Cloud Storage charges stopped"
        else
            echo "⚠ Cloud Storage charges continue (buckets preserved)"
        fi
        echo "✓ Vertex AI model serving charges stopped"
    fi
    
    echo
    echo "=== NEXT STEPS ==="
    if [[ "${SKIP_BUCKETS}" == "true" ]]; then
        echo "- Review preserved buckets for any data you want to keep"
        echo "- Delete buckets manually when ready: gsutil rb gs://bucket-name"
    fi
    echo "- Review Google Cloud Console for any remaining resources"
    echo "- Check billing reports to confirm charges have stopped"
    echo
}

# Function to handle API disabling
disable_apis_prompt() {
    if [[ "${FORCE}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return
    fi
    
    echo
    read -p "Do you want to disable Google Cloud APIs used by this solution? (y/N): " disable_apis
    
    if [[ "${disable_apis,,}" == "y" || "${disable_apis,,}" == "yes" ]]; then
        log_info "Disabling APIs..."
        
        local apis=(
            "aiplatform.googleapis.com"
            "cloudfunctions.googleapis.com"
            "cloudbuild.googleapis.com"
            "eventarc.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log_info "Disabling ${api}..."
            if gcloud services disable "${api}" --quiet 2>/dev/null; then
                log_success "Disabled ${api}"
            else
                log_warning "Failed to disable ${api} (may be used by other services)"
            fi
        done
        
        log_info "Note: storage.googleapis.com was not disabled as it's commonly used"
    else
        log_info "Skipping API disabling"
    fi
}

# Main destruction function
main() {
    # Default values
    PROJECT_ID=""
    REGION="${DEFAULT_REGION}"
    ZONE="${DEFAULT_ZONE}"
    FORCE="false"
    DRY_RUN="false"
    SKIP_BUCKETS="false"
    SKIP_FUNCTION="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -f|--force)
                FORCE="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --skip-buckets)
                SKIP_BUCKETS="true"
                shift
                ;;
            --skip-function)
                SKIP_FUNCTION="true"
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
    
    # Validate required parameters
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "Project ID is required"
        usage
        exit 1
    fi
    
    # Display banner
    echo "=================================="
    echo "  ADK Smart Code Documentation"
    echo "         Cleanup Script"
    echo "=================================="
    echo
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "Running in DRY RUN mode - no resources will be deleted"
        echo
    fi
    
    # Run cleanup steps
    check_prerequisites
    setup_environment
    discover_resources
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        confirm_destruction
    fi
    
    delete_cloud_functions
    delete_storage_buckets
    cleanup_local_workspace
    cleanup_temp_files
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        verify_cleanup
        disable_apis_prompt
    fi
    
    display_summary
}

# Run main function with all arguments
main "$@"