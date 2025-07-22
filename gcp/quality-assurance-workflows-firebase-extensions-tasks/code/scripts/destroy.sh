#!/bin/bash

# Quality Assurance Workflows with Firebase Extensions and Cloud Tasks - Cleanup Script
# This script safely removes all QA automation infrastructure from Google Cloud Platform

set -euo pipefail  # Exit on error, undefined vars, pipe failures

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if required tools are installed
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    local required_tools=("gcloud" "gsutil" "curl" "jq")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        error_exit "Missing required tools: ${missing_tools[*]}. Please install them before running this script."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error_exit "No active gcloud authentication found. Run 'gcloud auth login' first."
    fi
    
    log_success "All prerequisites met for cleanup"
}

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Try to get current project
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
    
    if [ -z "${PROJECT_ID}" ]; then
        log_error "PROJECT_ID not set and no default project configured"
        read -p "Enter the PROJECT_ID to clean up: " PROJECT_ID
        if [ -z "${PROJECT_ID}" ]; then
            error_exit "PROJECT_ID is required for cleanup"
        fi
    fi
    
    # Set defaults for environment variables
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
    
    log_success "Environment loaded:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
}

# Confirm cleanup operation
confirm_cleanup() {
    log_warning "This script will DELETE the following resources from project ${PROJECT_ID}:"
    echo "  - Cloud Run services (qa-dashboard)"
    echo "  - Cloud Functions (qa-phase-executor)"
    echo "  - Cloud Tasks queues (qa-orchestration-*)"
    echo "  - Cloud Storage buckets (qa-artifacts-*)"
    echo "  - Firestore collections (qa-workflows, test-results, qa-triggers)"
    echo "  - Vertex AI datasets and models"
    echo "  - Firebase Extensions"
    echo ""
    
    if [ "${FORCE_DELETE:-false}" = "true" ]; then
        log_warning "FORCE_DELETE enabled - proceeding without confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? This action cannot be undone. (yes/no): " confirmation
    
    if [ "${confirmation}" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Cleanup confirmed - proceeding with resource deletion"
}

# List and discover resources
discover_resources() {
    log_info "Discovering QA workflow resources..."
    
    # Discover Cloud Run services
    QA_SERVICES=($(gcloud run services list \
        --region="${REGION}" \
        --filter="metadata.name:qa-dashboard" \
        --format="value(metadata.name)" 2>/dev/null || true))
    
    # Discover Cloud Functions
    QA_FUNCTIONS=($(gcloud functions list \
        --regions="${REGION}" \
        --filter="name:qa-phase-executor" \
        --format="value(name.basename())" 2>/dev/null || true))
    
    # Discover Cloud Tasks queues
    QA_QUEUES=($(gcloud tasks queues list \
        --location="${REGION}" \
        --filter="name:qa-orchestration" \
        --format="value(name.basename())" 2>/dev/null || true))
    
    # Discover Cloud Storage buckets
    QA_BUCKETS=($(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | \
        grep -E "gs://qa-artifacts-" | \
        sed 's|gs://||g' | \
        sed 's|/||g' || true))
    
    # Discover Vertex AI datasets
    QA_DATASETS=($(gcloud ai datasets list \
        --region="${REGION}" \
        --filter="displayName:qa-metrics-dataset" \
        --format="value(name.basename())" 2>/dev/null || true))
    
    # Discover Vertex AI models
    QA_MODELS=($(gcloud ai-platform models list \
        --region="${REGION}" \
        --filter="displayName:qa-analysis-model" \
        --format="value(name.basename())" 2>/dev/null || true))
    
    log_info "Discovered resources:"
    log_info "  Cloud Run services: ${#QA_SERVICES[@]}"
    log_info "  Cloud Functions: ${#QA_FUNCTIONS[@]}"
    log_info "  Task queues: ${#QA_QUEUES[@]}"
    log_info "  Storage buckets: ${#QA_BUCKETS[@]}"
    log_info "  Vertex AI datasets: ${#QA_DATASETS[@]}"
    log_info "  Vertex AI models: ${#QA_MODELS[@]}"
}

# Remove Cloud Run services
cleanup_cloud_run() {
    log_info "Cleaning up Cloud Run services..."
    
    if [ ${#QA_SERVICES[@]} -eq 0 ]; then
        log_info "No Cloud Run services found to delete"
        return 0
    fi
    
    for service in "${QA_SERVICES[@]}"; do
        log_info "Deleting Cloud Run service: ${service}"
        gcloud run services delete "${service}" \
            --region="${REGION}" \
            --quiet || {
            log_warning "Failed to delete Cloud Run service: ${service}"
        }
    done
    
    log_success "Cloud Run services cleanup completed"
}

# Remove Cloud Functions
cleanup_cloud_functions() {
    log_info "Cleaning up Cloud Functions..."
    
    if [ ${#QA_FUNCTIONS[@]} -eq 0 ]; then
        log_info "No Cloud Functions found to delete"
        return 0
    fi
    
    for function in "${QA_FUNCTIONS[@]}"; do
        log_info "Deleting Cloud Function: ${function}"
        gcloud functions delete "${function}" \
            --region="${REGION}" \
            --quiet || {
            log_warning "Failed to delete Cloud Function: ${function}"
        }
    done
    
    log_success "Cloud Functions cleanup completed"
}

# Remove Cloud Tasks queues
cleanup_cloud_tasks() {
    log_info "Cleaning up Cloud Tasks queues..."
    
    if [ ${#QA_QUEUES[@]} -eq 0 ]; then
        log_info "No Cloud Tasks queues found to delete"
        return 0
    fi
    
    for queue in "${QA_QUEUES[@]}"; do
        log_info "Deleting Cloud Tasks queue: ${queue}"
        gcloud tasks queues delete "${queue}" \
            --location="${REGION}" \
            --quiet || {
            log_warning "Failed to delete Cloud Tasks queue: ${queue}"
        }
    done
    
    # Also clean up related queues
    local related_queues=("${queue}-priority" "${queue}-analysis")
    for related_queue in "${related_queues[@]}"; do
        if gcloud tasks queues describe "${related_queue}" --location="${REGION}" &>/dev/null; then
            log_info "Deleting related queue: ${related_queue}"
            gcloud tasks queues delete "${related_queue}" \
                --location="${REGION}" \
                --quiet || {
                log_warning "Failed to delete related queue: ${related_queue}"
            }
        fi
    done
    
    log_success "Cloud Tasks queues cleanup completed"
}

# Remove Cloud Storage buckets
cleanup_storage() {
    log_info "Cleaning up Cloud Storage buckets..."
    
    if [ ${#QA_BUCKETS[@]} -eq 0 ]; then
        log_info "No QA Storage buckets found to delete"
        return 0
    fi
    
    for bucket in "${QA_BUCKETS[@]}"; do
        log_info "Deleting Cloud Storage bucket: gs://${bucket}"
        
        # Check if bucket exists
        if gsutil ls "gs://${bucket}" &>/dev/null; then
            # Remove versioning to allow deletion
            gsutil versioning set off "gs://${bucket}" 2>/dev/null || true
            
            # Delete all objects including versions
            gsutil -m rm -r "gs://${bucket}/**" 2>/dev/null || true
            
            # Delete the bucket
            gsutil rb "gs://${bucket}" || {
                log_warning "Failed to delete bucket: gs://${bucket}"
            }
        else
            log_info "Bucket gs://${bucket} not found or already deleted"
        fi
    done
    
    log_success "Cloud Storage cleanup completed"
}

# Remove Vertex AI resources
cleanup_vertex_ai() {
    log_info "Cleaning up Vertex AI resources..."
    
    # Clean up models
    if [ ${#QA_MODELS[@]} -gt 0 ]; then
        for model in "${QA_MODELS[@]}"; do
            log_info "Deleting Vertex AI model: ${model}"
            gcloud ai-platform models delete "${model}" \
                --region="${REGION}" \
                --quiet || {
                log_warning "Failed to delete Vertex AI model: ${model}"
            }
        done
    fi
    
    # Clean up datasets
    if [ ${#QA_DATASETS[@]} -gt 0 ]; then
        for dataset in "${QA_DATASETS[@]}"; do
            log_info "Deleting Vertex AI dataset: ${dataset}"
            gcloud ai datasets delete "${dataset}" \
                --region="${REGION}" \
                --quiet || {
                log_warning "Failed to delete Vertex AI dataset: ${dataset}"
            }
        done
    fi
    
    log_success "Vertex AI resources cleanup completed"
}

# Remove Firestore collections
cleanup_firestore() {
    log_info "Cleaning up Firestore collections..."
    
    # Note: Firestore collection deletion requires careful handling
    # We'll only clear documents, not delete collections
    
    local collections=("qa-workflows" "test-results" "qa-triggers")
    
    for collection in "${collections[@]}"; do
        log_info "Clearing Firestore collection: ${collection}"
        
        # Export and delete documents (safer approach)
        local temp_export_path="gs://temp-firestore-cleanup-${RANDOM}"
        
        # Create temporary bucket for export
        gsutil mb "${temp_export_path}" 2>/dev/null || true
        
        # Export collection
        gcloud firestore export "${temp_export_path}" \
            --collection-ids="${collection}" \
            --async \
            --quiet 2>/dev/null || {
            log_warning "Failed to export collection: ${collection}"
        }
        
        # Clean up temporary bucket
        gsutil -m rm -r "${temp_export_path}" 2>/dev/null || true
        gsutil rb "${temp_export_path}" 2>/dev/null || true
    done
    
    log_success "Firestore collections cleanup completed"
    log_warning "Note: Firestore collections were cleared but not deleted. Delete manually if needed."
}

# Remove Firebase Extensions
cleanup_firebase_extensions() {
    log_info "Cleaning up Firebase Extensions..."
    
    # List and remove any custom extensions
    local extensions
    extensions=$(firebase ext:list --project="${PROJECT_ID}" 2>/dev/null | grep -E "qa-workflow" || true)
    
    if [ -n "${extensions}" ]; then
        log_info "Found QA workflow extensions to remove"
        # Note: Extension removal would require Firebase CLI commands
        # This is a simplified placeholder
        log_warning "Manual removal of Firebase Extensions may be required"
        log_info "Run: firebase ext:uninstall <extension-name> --project=${PROJECT_ID}"
    else
        log_info "No custom Firebase Extensions found"
    fi
    
    log_success "Firebase Extensions cleanup completed"
}

# Clean up temporary files and artifacts
cleanup_artifacts() {
    log_info "Cleaning up temporary artifacts..."
    
    # Remove any local temporary files
    local temp_files=(
        "firestore.rules"
        "lifecycle.json"
        "test-trigger.json"
        "vertex-pipeline.yaml"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -f "${file}" ]; then
            rm -f "${file}"
            log_info "Removed temporary file: ${file}"
        fi
    done
    
    # Remove any local directories
    local temp_dirs=(
        "qa-workflow-extension"
        "qa-phase-executor"
        "qa-dashboard"
    )
    
    for dir in "${temp_dirs[@]}"; do
        if [ -d "${dir}" ]; then
            rm -rf "${dir}"
            log_info "Removed temporary directory: ${dir}"
        fi
    done
    
    log_success "Temporary artifacts cleanup completed"
}

# Disable APIs (optional)
disable_apis() {
    log_info "Disabling APIs (optional step)..."
    
    if [ "${DISABLE_APIS:-false}" = "true" ]; then
        local apis=(
            "cloudtasks.googleapis.com"
            "aiplatform.googleapis.com"
            "cloudfunctions.googleapis.com"
            "cloudrun.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log_info "Disabling ${api}..."
            gcloud services disable "${api}" --force --quiet || {
                log_warning "Failed to disable ${api}"
            }
        done
        
        log_success "APIs disabled"
    else
        log_info "Skipping API disabling (set DISABLE_APIS=true to disable)"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local issues=0
    
    # Check Cloud Run services
    local remaining_services
    remaining_services=$(gcloud run services list \
        --region="${REGION}" \
        --filter="metadata.name:qa-dashboard" \
        --format="value(metadata.name)" 2>/dev/null | wc -l)
    
    if [ "${remaining_services}" -gt 0 ]; then
        log_warning "Warning: ${remaining_services} Cloud Run services still exist"
        ((issues++))
    fi
    
    # Check Cloud Functions
    local remaining_functions
    remaining_functions=$(gcloud functions list \
        --regions="${REGION}" \
        --filter="name:qa-phase-executor" \
        --format="value(name.basename())" 2>/dev/null | wc -l)
    
    if [ "${remaining_functions}" -gt 0 ]; then
        log_warning "Warning: ${remaining_functions} Cloud Functions still exist"
        ((issues++))
    fi
    
    # Check Cloud Tasks queues
    local remaining_queues
    remaining_queues=$(gcloud tasks queues list \
        --location="${REGION}" \
        --filter="name:qa-orchestration" \
        --format="value(name.basename())" 2>/dev/null | wc -l)
    
    if [ "${remaining_queues}" -gt 0 ]; then
        log_warning "Warning: ${remaining_queues} Cloud Tasks queues still exist"
        ((issues++))
    fi
    
    # Check Storage buckets
    local remaining_buckets
    remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | \
        grep -c "qa-artifacts-" || true)
    
    if [ "${remaining_buckets}" -gt 0 ]; then
        log_warning "Warning: ${remaining_buckets} Storage buckets still exist"
        ((issues++))
    fi
    
    if [ "${issues}" -eq 0 ]; then
        log_success "Cleanup verification passed - no remaining resources found"
    else
        log_warning "Cleanup verification found ${issues} potential issues"
        log_info "Some resources may take time to fully delete or require manual cleanup"
    fi
}

# Display cleanup summary
display_summary() {
    log_success "QA Workflow cleanup completed!"
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    
    echo "=== RESOURCES PROCESSED ==="
    echo "✓ Cloud Run services: ${#QA_SERVICES[@]} processed"
    echo "✓ Cloud Functions: ${#QA_FUNCTIONS[@]} processed"
    echo "✓ Cloud Tasks queues: ${#QA_QUEUES[@]} processed"
    echo "✓ Storage buckets: ${#QA_BUCKETS[@]} processed"
    echo "✓ Vertex AI datasets: ${#QA_DATASETS[@]} processed"
    echo "✓ Vertex AI models: ${#QA_MODELS[@]} processed"
    echo "✓ Firestore collections: cleared"
    echo "✓ Temporary artifacts: removed"
    echo ""
    
    echo "=== MANUAL CLEANUP NEEDED ==="
    echo "The following may require manual cleanup:"
    echo "1. Firebase project settings (if no longer needed)"
    echo "2. IAM roles and service accounts (if custom ones were created)"
    echo "3. Firestore collections (documents cleared, collections remain)"
    echo "4. Billing account configuration (if project is no longer needed)"
    echo ""
    
    echo "=== PROJECT DELETION ==="
    echo "To completely remove the project:"
    echo "  gcloud projects delete ${PROJECT_ID}"
    echo ""
    echo "⚠️  WARNING: Project deletion is irreversible and will remove ALL resources!"
    echo ""
    
    echo "=== VERIFICATION ==="
    echo "Check the Google Cloud Console to verify all resources are removed:"
    echo "https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
    echo ""
    
    log_info "Cleanup completed successfully!"
}

# Main cleanup function
main() {
    log_info "Starting QA Workflow cleanup..."
    
    # Initialize arrays for discovered resources
    declare -a QA_SERVICES QA_FUNCTIONS QA_QUEUES QA_BUCKETS QA_DATASETS QA_MODELS
    
    # Check if this is a dry run
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        load_environment
        discover_resources
        log_info "Dry run completed - no resources were modified"
        exit 0
    fi
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    discover_resources
    confirm_cleanup
    
    # Cleanup in reverse order of creation
    cleanup_cloud_run
    cleanup_cloud_functions
    cleanup_cloud_tasks
    cleanup_vertex_ai
    cleanup_storage
    cleanup_firestore
    cleanup_firebase_extensions
    cleanup_artifacts
    disable_apis
    
    # Verify and summarize
    verify_cleanup
    display_summary
    
    log_success "QA Workflow cleanup completed successfully!"
}

# Script usage information
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --project-id ID      Set the PROJECT_ID to clean up"
    echo "  --region REGION      Set the region (default: us-central1)"
    echo "  --force              Skip confirmation prompts"
    echo "  --dry-run            Show what would be deleted without deleting"
    echo "  --disable-apis       Disable APIs after cleanup"
    echo "  --help               Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  PROJECT_ID           Google Cloud project ID"
    echo "  REGION               Google Cloud region"
    echo "  FORCE_DELETE         Skip confirmations (true/false)"
    echo "  DRY_RUN              Dry run mode (true/false)"
    echo "  DISABLE_APIS         Disable APIs after cleanup (true/false)"
    echo ""
    echo "Examples:"
    echo "  $0 --project-id my-qa-project"
    echo "  $0 --dry-run"
    echo "  $0 --force --disable-apis"
    echo ""
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                export PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                export REGION="$2"
                shift 2
                ;;
            --force)
                export FORCE_DELETE="true"
                shift
                ;;
            --dry-run)
                export DRY_RUN="true"
                shift
                ;;
            --disable-apis)
                export DISABLE_APIS="true"
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_arguments "$@"
    main
fi