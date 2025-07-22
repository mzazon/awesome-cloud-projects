#!/bin/bash

# Intelligent Retail Inventory Optimization Cleanup Script
# This script safely removes all Google Cloud Platform infrastructure created
# for the intelligent retail inventory optimization system

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Trap for cleanup on script exit
trap cleanup_on_exit EXIT

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup failed! Check ${LOG_FILE} for details."
        log_warning "Some resources may still exist and incur charges"
    fi
    return $exit_code
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

log_step() {
    echo -e "\n${BLUE}=== $* ===${NC}" | tee -a "${LOG_FILE}"
}

# Load deployment state
load_state() {
    if [[ -f "${STATE_FILE}" ]]; then
        source "${STATE_FILE}"
        return 0
    else
        log_error "Deployment state file not found: ${STATE_FILE}"
        log_info "Cannot proceed with cleanup without state information"
        return 1
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating Prerequisites"
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available"
        exit 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not available"
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Parse command line arguments
parse_arguments() {
    local force=false
    local interactive=true
    local dry_run=false
    local project_id=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force=true
                interactive=false
                shift
                ;;
            --yes|-y)
                interactive=false
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --project)
                project_id="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Export configuration
    export FORCE_CLEANUP="${force}"
    export INTERACTIVE_MODE="${interactive}"
    export DRY_RUN="${dry_run}"
    export OVERRIDE_PROJECT_ID="${project_id}"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove all Google Cloud Platform resources created for intelligent retail inventory optimization.

Options:
    --force                   Force cleanup without confirmation prompts
    --yes, -y                Skip confirmation prompts (but show warnings)
    --dry-run                Show what would be deleted without making changes
    --project PROJECT_ID      Override project ID from state file
    --help, -h               Show this help message

Examples:
    $0                       # Interactive cleanup with confirmations
    $0 --yes                 # Automatic cleanup with warnings
    $0 --force               # Force cleanup without any prompts
    $0 --dry-run             # Preview what would be deleted
    $0 --project my-project  # Cleanup specific project

⚠️  WARNING: This operation is irreversible and will delete ALL resources!
EOF
}

# Confirm destructive operation
confirm_cleanup() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
        return 0
    fi
    
    if [[ "${INTERACTIVE_MODE}" == "false" ]]; then
        if [[ "${FORCE_CLEANUP}" == "true" ]]; then
            log_warning "Force cleanup mode - proceeding without confirmation"
        else
            log_warning "Non-interactive mode - proceeding with cleanup"
        fi
        return 0
    fi
    
    echo -e "\n${RED}⚠️  WARNING: DESTRUCTIVE OPERATION${NC}"
    echo -e "${YELLOW}This will permanently delete ALL resources created for the retail inventory optimization system:${NC}"
    echo ""
    echo "  🗄️  BigQuery dataset: ${DATASET_NAME:-"Unknown"}"
    echo "  🪣  Cloud Storage bucket: ${BUCKET_NAME:-"Unknown"}"
    echo "  🚀  Cloud Run services: ${ANALYTICS_SERVICE_NAME:-"Unknown"}, ${OPTIMIZER_SERVICE_NAME:-"Unknown"}"
    echo "  🖼️  Container images in Container Registry"
    echo "  👤  Service account: ${SERVICE_ACCOUNT:-"Unknown"}"
    echo "  📊  All data, models, and optimization results"
    echo ""
    echo -e "${RED}This operation cannot be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Please type the project ID to confirm: ${PROJECT_ID}: " -r
    if [[ $REPLY != "${PROJECT_ID}" ]]; then
        log_error "Project ID mismatch. Cleanup cancelled for safety."
        exit 1
    fi
    
    log_warning "Proceeding with cleanup in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
}

# Set up environment from state
setup_environment() {
    log_step "Loading Environment Configuration"
    
    # Load from state file or command line override
    if [[ -n "${OVERRIDE_PROJECT_ID:-}" ]]; then
        export PROJECT_ID="${OVERRIDE_PROJECT_ID}"
        log_info "Using override project ID: ${PROJECT_ID}"
    elif [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID not found in state file and not provided via --project"
        exit 1
    fi
    
    # Set default project
    gcloud config set project "${PROJECT_ID}" 2>/dev/null || true
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION:-"Unknown"}"
    log_info "Dataset: ${DATASET_NAME:-"Unknown"}"
    log_info "Bucket: ${BUCKET_NAME:-"Unknown"}"
    
    log_success "Environment configuration loaded"
}

# Delete Cloud Run services
cleanup_cloud_run() {
    log_step "Removing Cloud Run Services"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would delete Cloud Run services"
        return 0
    fi
    
    local services=()
    
    # Check if analytics service exists
    if [[ -n "${ANALYTICS_SERVICE_NAME:-}" ]] && [[ -n "${REGION:-}" ]]; then
        if gcloud run services describe "${ANALYTICS_SERVICE_NAME}" --region="${REGION}" &>/dev/null; then
            services+=("${ANALYTICS_SERVICE_NAME}")
        fi
    fi
    
    # Check if optimizer service exists
    if [[ -n "${OPTIMIZER_SERVICE_NAME:-}" ]] && [[ -n "${REGION:-}" ]]; then
        if gcloud run services describe "${OPTIMIZER_SERVICE_NAME}" --region="${REGION}" &>/dev/null; then
            services+=("${OPTIMIZER_SERVICE_NAME}")
        fi
    fi
    
    # Delete services
    for service in "${services[@]}"; do
        log_info "Deleting Cloud Run service: ${service}"
        if gcloud run services delete "${service}" \
            --region="${REGION}" \
            --quiet; then
            log_success "Deleted Cloud Run service: ${service}"
        else
            log_warning "Failed to delete Cloud Run service: ${service}"
        fi
    done
    
    if [[ ${#services[@]} -eq 0 ]]; then
        log_info "No Cloud Run services found to delete"
    fi
}

# Delete container images
cleanup_container_images() {
    log_step "Removing Container Images"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would delete container images"
        return 0
    fi
    
    local images=()
    
    # Check for analytics service image
    if [[ -n "${ANALYTICS_SERVICE_NAME:-}" ]]; then
        local image_path="gcr.io/${PROJECT_ID}/${ANALYTICS_SERVICE_NAME}"
        if gcloud container images list --repository="gcr.io/${PROJECT_ID}" --filter="name:${image_path}" --format="value(name)" | head -n1 &>/dev/null; then
            images+=("${image_path}")
        fi
    fi
    
    # Check for optimizer service image
    if [[ -n "${OPTIMIZER_SERVICE_NAME:-}" ]]; then
        local image_path="gcr.io/${PROJECT_ID}/${OPTIMIZER_SERVICE_NAME}"
        if gcloud container images list --repository="gcr.io/${PROJECT_ID}" --filter="name:${image_path}" --format="value(name)" | head -n1 &>/dev/null; then
            images+=("${image_path}")
        fi
    fi
    
    # Delete images
    for image in "${images[@]}"; do
        log_info "Deleting container image: ${image}"
        if gcloud container images delete "${image}:latest" \
            --quiet --force-delete-tags; then
            log_success "Deleted container image: ${image}"
        else
            log_warning "Failed to delete container image: ${image}"
        fi
    done
    
    if [[ ${#images[@]} -eq 0 ]]; then
        log_info "No container images found to delete"
    fi
}

# Delete BigQuery resources
cleanup_bigquery() {
    log_step "Removing BigQuery Resources"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would delete BigQuery dataset: ${DATASET_NAME:-"Unknown"}"
        return 0
    fi
    
    if [[ -z "${DATASET_NAME:-}" ]]; then
        log_warning "Dataset name not found in state, skipping BigQuery cleanup"
        return 0
    fi
    
    # Check if dataset exists
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log_info "Deleting BigQuery dataset: ${DATASET_NAME}"
        log_info "This includes all tables and ML models in the dataset"
        
        if bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}"; then
            log_success "Deleted BigQuery dataset: ${DATASET_NAME}"
        else
            log_error "Failed to delete BigQuery dataset: ${DATASET_NAME}"
        fi
    else
        log_info "BigQuery dataset ${DATASET_NAME} not found (may already be deleted)"
    fi
}

# Delete Cloud Storage bucket
cleanup_storage() {
    log_step "Removing Cloud Storage Resources"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would delete Cloud Storage bucket: ${BUCKET_NAME:-"Unknown"}"
        return 0
    fi
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_warning "Bucket name not found in state, skipping storage cleanup"
        return 0
    fi
    
    # Check if bucket exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_info "Deleting Cloud Storage bucket: ${BUCKET_NAME}"
        log_info "This includes all objects, versions, and metadata"
        
        # Remove all objects including versions
        if gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true; then
            log_info "Removed all objects from bucket"
        fi
        
        # Remove the bucket
        if gsutil rb "gs://${BUCKET_NAME}"; then
            log_success "Deleted Cloud Storage bucket: ${BUCKET_NAME}"
        else
            log_error "Failed to delete Cloud Storage bucket: ${BUCKET_NAME}"
        fi
    else
        log_info "Cloud Storage bucket ${BUCKET_NAME} not found (may already be deleted)"
    fi
}

# Remove service account and IAM bindings
cleanup_iam() {
    log_step "Removing IAM Resources"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would remove service account and IAM bindings"
        return 0
    fi
    
    if [[ -z "${SERVICE_ACCOUNT:-}" ]]; then
        log_warning "Service account not found in state, skipping IAM cleanup"
        return 0
    fi
    
    # Define roles that were granted
    local roles=(
        "roles/bigquery.admin"
        "roles/aiplatform.user"
        "roles/optimization.admin"
        "roles/fleetengine.admin"
        "roles/storage.admin"
        "roles/run.admin"
        "roles/monitoring.editor"
        "roles/cloudbuild.builds.editor"
    )
    
    # Remove IAM policy bindings
    log_info "Removing IAM policy bindings..."
    for role in "${roles[@]}"; do
        log_info "Removing role: ${role}"
        gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SERVICE_ACCOUNT}" \
            --role="${role}" \
            --quiet &>/dev/null || log_warning "Failed to remove role ${role}"
    done
    
    # Delete service account
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT}" &>/dev/null; then
        log_info "Deleting service account: ${SERVICE_ACCOUNT}"
        if gcloud iam service-accounts delete "${SERVICE_ACCOUNT}" \
            --quiet; then
            log_success "Deleted service account: ${SERVICE_ACCOUNT}"
        else
            log_error "Failed to delete service account: ${SERVICE_ACCOUNT}"
        fi
    else
        log_info "Service account ${SERVICE_ACCOUNT} not found (may already be deleted)"
    fi
}

# Clean up any remaining artifacts
cleanup_artifacts() {
    log_step "Cleaning Up Remaining Artifacts"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would clean up remaining artifacts"
        return 0
    fi
    
    # Clean up any Cloud Build images
    log_info "Checking for Cloud Build artifacts..."
    local build_images
    build_images=$(gcloud container images list --repository="gcr.io/${PROJECT_ID}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${build_images}" ]]; then
        log_info "Found Cloud Build images, cleaning up..."
        echo "${build_images}" | while read -r image; do
            if [[ -n "${image}" ]]; then
                log_info "Deleting image: ${image}"
                gcloud container images delete "${image}" --quiet --force-delete-tags &>/dev/null || true
            fi
        done
    fi
    
    # Check for any Cloud Functions (in case any were created)
    log_info "Checking for Cloud Functions..."
    local functions
    functions=$(gcloud functions list --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${functions}" ]]; then
        log_warning "Found Cloud Functions that may be related to this deployment:"
        echo "${functions}"
        log_info "Please review and delete manually if needed"
    fi
    
    log_success "Artifact cleanup completed"
}

# Validate cleanup completion
validate_cleanup() {
    log_step "Validating Cleanup"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Cleanup validation skipped in dry-run mode"
        return 0
    fi
    
    local remaining_resources=0
    
    # Check BigQuery dataset
    if [[ -n "${DATASET_NAME:-}" ]]; then
        if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
            log_warning "BigQuery dataset still exists: ${DATASET_NAME}"
            ((remaining_resources++))
        else
            log_success "BigQuery dataset successfully removed"
        fi
    fi
    
    # Check Cloud Storage bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
            log_warning "Cloud Storage bucket still exists: ${BUCKET_NAME}"
            ((remaining_resources++))
        else
            log_success "Cloud Storage bucket successfully removed"
        fi
    fi
    
    # Check Cloud Run services
    if [[ -n "${ANALYTICS_SERVICE_NAME:-}" ]] && [[ -n "${REGION:-}" ]]; then
        if gcloud run services describe "${ANALYTICS_SERVICE_NAME}" --region="${REGION}" &>/dev/null; then
            log_warning "Analytics service still exists: ${ANALYTICS_SERVICE_NAME}"
            ((remaining_resources++))
        else
            log_success "Analytics service successfully removed"
        fi
    fi
    
    if [[ -n "${OPTIMIZER_SERVICE_NAME:-}" ]] && [[ -n "${REGION:-}" ]]; then
        if gcloud run services describe "${OPTIMIZER_SERVICE_NAME}" --region="${REGION}" &>/dev/null; then
            log_warning "Optimizer service still exists: ${OPTIMIZER_SERVICE_NAME}"
            ((remaining_resources++))
        else
            log_success "Optimizer service successfully removed"
        fi
    fi
    
    # Check service account
    if [[ -n "${SERVICE_ACCOUNT:-}" ]]; then
        if gcloud iam service-accounts describe "${SERVICE_ACCOUNT}" &>/dev/null; then
            log_warning "Service account still exists: ${SERVICE_ACCOUNT}"
            ((remaining_resources++))
        else
            log_success "Service account successfully removed"
        fi
    fi
    
    if [[ ${remaining_resources} -eq 0 ]]; then
        log_success "All resources successfully removed"
        return 0
    else
        log_warning "${remaining_resources} resource(s) may still exist"
        return 1
    fi
}

# Optional: Delete the entire project
cleanup_project() {
    if [[ "${INTERACTIVE_MODE}" == "false" ]] && [[ "${FORCE_CLEANUP}" != "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}Optional: Delete entire project${NC}"
    echo "The project ${PROJECT_ID} was created specifically for this deployment."
    echo "You can optionally delete the entire project to ensure complete cleanup."
    echo ""
    
    if [[ "${INTERACTIVE_MODE}" == "true" ]]; then
        read -p "Delete the entire project ${PROJECT_ID}? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Keeping project ${PROJECT_ID}"
            return 0
        fi
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would delete project: ${PROJECT_ID}"
        return 0
    fi
    
    log_warning "Deleting entire project: ${PROJECT_ID}"
    log_info "This may take several minutes..."
    
    if gcloud projects delete "${PROJECT_ID}" --quiet; then
        log_success "Project ${PROJECT_ID} deleted successfully"
    else
        log_error "Failed to delete project ${PROJECT_ID}"
        log_info "You may need to delete it manually from the Cloud Console"
    fi
}

# Clean up local state files
cleanup_local_files() {
    log_step "Cleaning Up Local Files"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would clean up local state files"
        return 0
    fi
    
    # Clean up state file
    if [[ -f "${STATE_FILE}" ]]; then
        log_info "Removing deployment state file: ${STATE_FILE}"
        rm -f "${STATE_FILE}"
    fi
    
    # Clean up any temporary files
    local temp_files=(
        "/tmp/demand_training_data.csv"
        "/tmp/lifecycle.json"
        "/tmp/retail-inventory-services"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -e "${file}" ]]; then
            log_info "Removing temporary file/directory: ${file}"
            rm -rf "${file}"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Display cleanup summary
show_cleanup_summary() {
    log_step "Cleanup Summary"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        cat << EOF

🔍 DRY RUN COMPLETED

The following resources would be deleted:
   📊 BigQuery dataset: ${DATASET_NAME:-"Unknown"}
   🪣  Cloud Storage bucket: ${BUCKET_NAME:-"Unknown"}
   🚀 Cloud Run services: ${ANALYTICS_SERVICE_NAME:-"Unknown"}, ${OPTIMIZER_SERVICE_NAME:-"Unknown"}
   🖼️  Container images in Container Registry
   👤 Service account: ${SERVICE_ACCOUNT:-"Unknown"}
   📁 Local state files

To perform actual cleanup, run: $0

EOF
        return 0
    fi
    
    cat << EOF

🧹 Intelligent Retail Inventory Optimization cleanup completed!

📋 Resources Removed:
   Project ID: ${PROJECT_ID}
   Region: ${REGION:-"N/A"}
   
✅ Cleanup Actions Performed:
   🚀 Deleted Cloud Run services
   🖼️  Removed container images
   📊 Deleted BigQuery dataset and ML models
   🪣  Removed Cloud Storage bucket and contents
   👤 Deleted service account and IAM bindings
   🧽 Cleaned up remaining artifacts
   📁 Removed local state files

💰 Cost Savings:
   All billable resources have been removed
   No further charges should be incurred for this deployment

📖 Logs:
   Cleanup log: ${LOG_FILE}

EOF
}

# Main cleanup function
main() {
    log_info "Starting intelligent retail inventory optimization cleanup"
    log_info "Script version: 1.0"
    log_info "Timestamp: $(date)"
    
    # Initialize log file
    echo "=== Intelligent Retail Inventory Optimization Cleanup Log ===" > "${LOG_FILE}"
    echo "Started: $(date)" >> "${LOG_FILE}"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate prerequisites
    validate_prerequisites
    
    # Load deployment state
    if ! load_state; then
        exit 1
    fi
    
    # Set up environment
    setup_environment
    
    # Confirm destructive operation
    confirm_cleanup
    
    # Execute cleanup steps
    cleanup_cloud_run
    cleanup_container_images
    cleanup_bigquery
    cleanup_storage
    cleanup_iam
    cleanup_artifacts
    validate_cleanup
    cleanup_project
    cleanup_local_files
    show_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi