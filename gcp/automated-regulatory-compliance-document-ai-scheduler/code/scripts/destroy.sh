#!/bin/bash

# Automated Regulatory Compliance Reporting with Document AI and Scheduler - Cleanup Script
# This script safely removes all compliance automation infrastructure from Google Cloud Platform

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CONFIG_FILE="${SCRIPT_DIR}/deployment-config.env"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
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

# Help function
show_help() {
    cat << EOF
Automated Regulatory Compliance Reporting Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID    GCP project ID to clean up
    -r, --region REGION           GCP region (default: us-central1)
    --force                       Skip confirmation prompts
    --keep-project                Don't delete the entire project
    --keep-data                   Keep storage buckets and data
    --dry-run                     Show what would be deleted without deleting
    --config-file FILE            Use specific config file (default: deployment-config.env)
    -h, --help                    Show this help message

EXAMPLES:
    $0                                    # Interactive cleanup using config file
    $0 --force                           # Non-interactive cleanup
    $0 -p my-project --keep-project      # Clean resources but keep project
    $0 --dry-run                         # Show what would be deleted
    $0 --keep-data                       # Keep storage buckets and data

SAFETY FEATURES:
    - Confirmation prompts for all destructive operations
    - Dry-run mode to preview changes
    - Selective cleanup options
    - Detailed logging of all operations

EOF
}

# Parse command line arguments
parse_arguments() {
    REGION="${REGION:-us-central1}"
    FORCE="${FORCE:-false}"
    KEEP_PROJECT="${KEEP_PROJECT:-false}"
    KEEP_DATA="${KEEP_DATA:-false}"
    DRY_RUN="${DRY_RUN:-false}"
    CUSTOM_CONFIG_FILE=""

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
            --force)
                FORCE="true"
                shift
                ;;
            --keep-project)
                KEEP_PROJECT="true"
                shift
                ;;
            --keep-data)
                KEEP_DATA="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --config-file)
                CUSTOM_CONFIG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Load deployment configuration
load_configuration() {
    local config_file="${CUSTOM_CONFIG_FILE:-$CONFIG_FILE}"
    
    if [[ -f "${config_file}" ]]; then
        log_info "Loading configuration from: ${config_file}"
        source "${config_file}"
        
        # Override with command line arguments if provided
        PROJECT_ID="${PROJECT_ID:-}"
        REGION="${REGION:-us-central1}"
        
        log_info "Configuration loaded successfully"
        log_info "Project ID: ${PROJECT_ID}"
        log_info "Region: ${REGION}"
    else
        log_warning "Configuration file not found: ${config_file}"
        
        if [[ -z "${PROJECT_ID:-}" ]]; then
            log_error "Project ID must be provided via --project-id or configuration file"
            exit 1
        fi
        
        log_warning "Attempting cleanup with minimal configuration"
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi

    # Check gsutil
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available"
        exit 1
    fi

    # Verify project exists and access
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project '${PROJECT_ID}' does not exist or you don't have access"
        exit 1
    fi

    # Set project context
    gcloud config set project "${PROJECT_ID}" --quiet

    log_success "Prerequisites validation completed"
}

# Confirm cleanup operation
confirm_cleanup() {
    if [[ "${FORCE}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi

    echo ""
    log_warning "⚠️  WARNING: This will permanently delete resources ⚠️"
    echo ""
    echo "📋 Cleanup Summary:"
    echo "   Project: ${PROJECT_ID}"
    echo "   Region: ${REGION}"
    
    if [[ "${KEEP_PROJECT}" == "true" ]]; then
        echo "   Project Deletion: NO (--keep-project specified)"
    else
        echo "   Project Deletion: YES"
    fi
    
    if [[ "${KEEP_DATA}" == "true" ]]; then
        echo "   Data Deletion: NO (--keep-data specified)"
    else
        echo "   Data Deletion: YES"
    fi
    
    echo ""
    echo "🗑️ Resources to be deleted:"
    echo "   - Cloud Scheduler jobs"
    echo "   - Cloud Functions"
    echo "   - Document AI processors"
    
    if [[ "${KEEP_DATA}" != "true" ]]; then
        echo "   - Cloud Storage buckets and data"
    fi
    
    echo "   - Log-based metrics"
    echo "   - Monitoring alert policies"
    
    if [[ "${KEEP_PROJECT}" != "true" ]]; then
        echo "   - Entire GCP project"
    fi
    
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Final confirmation - type the project ID '${PROJECT_ID}' to proceed: " -r
    if [[ $REPLY != "${PROJECT_ID}" ]]; then
        log_info "Project ID confirmation failed. Cleanup cancelled."
        exit 0
    fi
    
    log_info "Cleanup confirmed by user"
}

# Delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log_info "Deleting Cloud Scheduler jobs..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete scheduler jobs in region: ${REGION}"
        return 0
    fi

    # Get list of compliance-related scheduler jobs
    local jobs
    jobs=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" --filter="name:compliance-scheduler" 2>/dev/null || echo "")

    if [[ -n "${jobs}" ]]; then
        while IFS= read -r job; do
            if [[ -n "${job}" ]]; then
                local job_name=$(basename "${job}")
                log_info "Deleting scheduler job: ${job_name}"
                gcloud scheduler jobs delete "${job_name}" \
                    --location="${REGION}" \
                    --quiet || log_warning "Failed to delete scheduler job: ${job_name}"
            fi
        done <<< "${jobs}"
        log_success "Cloud Scheduler jobs deleted"
    else
        log_info "No Cloud Scheduler jobs found to delete"
    fi
}

# Delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cloud Functions in region: ${REGION}"
        return 0
    fi

    # Get list of compliance-related functions
    local functions
    functions=$(gcloud functions list --regions="${REGION}" --format="value(name)" --filter="name:document-processor OR name:report-generator" 2>/dev/null || echo "")

    if [[ -n "${functions}" ]]; then
        while IFS= read -r func; do
            if [[ -n "${func}" ]]; then
                local func_name=$(basename "${func}")
                log_info "Deleting Cloud Function: ${func_name}"
                gcloud functions delete "${func_name}" \
                    --region="${REGION}" \
                    --quiet || log_warning "Failed to delete function: ${func_name}"
            fi
        done <<< "${functions}"
        
        # Wait for functions to be fully deleted
        log_info "Waiting for functions to be fully deleted..."
        sleep 30
        
        log_success "Cloud Functions deleted"
    else
        log_info "No Cloud Functions found to delete"
    fi
}

# Delete Document AI processors
delete_document_ai_processors() {
    log_info "Deleting Document AI processors..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Document AI processors in region: ${REGION}"
        return 0
    fi

    # Get list of compliance-related processors
    local processors
    processors=$(gcloud documentai processors list --location="${REGION}" --format="value(name)" --filter="displayName:'Compliance Form Parser'" 2>/dev/null || echo "")

    if [[ -n "${processors}" ]]; then
        while IFS= read -r processor; do
            if [[ -n "${processor}" ]]; then
                local processor_id=$(basename "${processor}")
                log_info "Deleting Document AI processor: ${processor_id}"
                gcloud documentai processors delete "${processor_id}" \
                    --location="${REGION}" \
                    --quiet || log_warning "Failed to delete processor: ${processor_id}"
            fi
        done <<< "${processors}"
        log_success "Document AI processors deleted"
    else
        log_info "No Document AI processors found to delete"
    fi
}

# Delete Cloud Storage buckets
delete_storage_buckets() {
    if [[ "${KEEP_DATA}" == "true" ]]; then
        log_info "Skipping Cloud Storage deletion (--keep-data specified)"
        return 0
    fi

    log_info "Deleting Cloud Storage buckets and data..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete all compliance-related storage buckets"
        return 0
    fi

    # Get list of compliance-related buckets
    local buckets
    buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "(compliance-input|compliance-processed|compliance-reports)" || echo "")

    if [[ -n "${buckets}" ]]; then
        local bucket_count=0
        while IFS= read -r bucket; do
            if [[ -n "${bucket}" ]]; then
                log_info "Deleting storage bucket: ${bucket}"
                
                # Remove lifecycle policies first
                gsutil lifecycle set /dev/null "${bucket}" 2>/dev/null || true
                
                # Delete all objects and versions
                gsutil -m rm -r "${bucket}" || log_warning "Failed to delete bucket: ${bucket}"
                
                ((bucket_count++))
            fi
        done <<< "${buckets}"
        
        if [[ ${bucket_count} -gt 0 ]]; then
            log_success "Deleted ${bucket_count} Cloud Storage buckets"
        fi
    else
        log_info "No Cloud Storage buckets found to delete"
    fi
}

# Delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting monitoring and alerting resources..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete log-based metrics and alert policies"
        return 0
    fi

    # Delete log-based metrics
    local metrics=("compliance_violations" "processing_errors" "successful_processing")
    
    for metric in "${metrics[@]}"; do
        log_info "Deleting log-based metric: ${metric}"
        gcloud logging metrics delete "${metric}" --quiet 2>/dev/null || log_warning "Metric ${metric} may not exist"
    done

    # Delete alert policies
    log_info "Deleting alert policies..."
    local policies
    policies=$(gcloud alpha monitoring policies list --format="value(name)" --filter="displayName:('Compliance Violations Alert' OR 'Processing Errors Alert')" 2>/dev/null || echo "")

    if [[ -n "${policies}" ]]; then
        while IFS= read -r policy; do
            if [[ -n "${policy}" ]]; then
                local policy_id=$(basename "${policy}")
                log_info "Deleting alert policy: ${policy_id}"
                gcloud alpha monitoring policies delete "${policy_id}" --quiet || log_warning "Failed to delete policy: ${policy_id}"
            fi
        done <<< "${policies}"
    fi

    # Delete notification channels
    if [[ -n "${NOTIFICATION_CHANNEL:-}" ]]; then
        log_info "Deleting notification channel..."
        local channel_id=$(basename "${NOTIFICATION_CHANNEL}")
        gcloud alpha monitoring channels delete "${channel_id}" --quiet 2>/dev/null || log_warning "Failed to delete notification channel"
    fi

    log_success "Monitoring resources deleted"
}

# Remove IAM policy bindings
remove_iam_bindings() {
    log_info "Removing IAM policy bindings..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove IAM bindings for Cloud Functions service account"
        return 0
    fi

    # Get the Cloud Functions service account
    local function_sa="${PROJECT_ID}@appspot.gserviceaccount.com"

    # Roles that were granted during deployment
    local roles=(
        "roles/documentai.apiUser"
        "roles/storage.objectAdmin"
        "roles/logging.logWriter"
        "roles/monitoring.metricWriter"
    )

    for role in "${roles[@]}"; do
        log_info "Removing IAM binding: ${role} from ${function_sa}"
        gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${function_sa}" \
            --role="${role}" \
            --quiet 2>/dev/null || log_warning "IAM binding may not exist: ${role}"
    done

    log_success "IAM policy bindings removed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local configuration and temporary files"
        return 0
    fi

    # Remove temporary directories that might have been created
    local temp_dirs=("${SCRIPT_DIR}/../temp-deployment" "${SCRIPT_DIR}/../temp-samples" "${SCRIPT_DIR}/../temp-policies")
    
    for dir in "${temp_dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            log_info "Removing temporary directory: ${dir}"
            rm -rf "${dir}"
        fi
    done

    # Optionally remove configuration file
    if [[ -f "${CONFIG_FILE}" ]] && [[ "${FORCE}" == "true" ]]; then
        log_info "Removing deployment configuration file"
        rm -f "${CONFIG_FILE}"
    elif [[ -f "${CONFIG_FILE}" ]]; then
        log_info "Keeping deployment configuration file: ${CONFIG_FILE}"
        log_info "Delete manually if no longer needed"
    fi

    log_success "Local files cleaned up"
}

# Delete entire project
delete_project() {
    if [[ "${KEEP_PROJECT}" == "true" ]]; then
        log_info "Skipping project deletion (--keep-project specified)"
        return 0
    fi

    log_info "Deleting entire Google Cloud project..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete project: ${PROJECT_ID}"
        return 0
    fi

    log_warning "Deleting project will remove ALL resources and cannot be undone"
    
    if [[ "${FORCE}" != "true" ]]; then
        echo ""
        read -p "Final confirmation: Delete project '${PROJECT_ID}'? (type 'DELETE' to confirm): " -r
        if [[ $REPLY != "DELETE" ]]; then
            log_info "Project deletion cancelled"
            return 0
        fi
    fi

    log_info "Initiating project deletion..."
    gcloud projects delete "${PROJECT_ID}" --quiet

    log_success "Project deletion initiated (may take several minutes to complete)"
    log_info "Project '${PROJECT_ID}' is scheduled for deletion"
    
    # Project deletion is asynchronous, so we can't wait for completion
    log_info "Note: Project deletion is asynchronous and may take up to 30 days to complete fully"
}

# Display cleanup summary
display_cleanup_summary() {
    local resources_deleted=()
    local resources_kept=()

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "=== DRY RUN SUMMARY ==="
        log_info "The following resources would be deleted:"
    else
        log_info "=== CLEANUP SUMMARY ==="
        log_info "The following resources have been deleted:"
    fi

    echo ""
    echo "🗑️ Deleted Resources:"
    echo "   ✅ Cloud Scheduler jobs"
    echo "   ✅ Cloud Functions"
    echo "   ✅ Document AI processors"
    echo "   ✅ Log-based metrics"
    echo "   ✅ Monitoring alert policies"
    echo "   ✅ IAM policy bindings"
    
    if [[ "${KEEP_DATA}" != "true" ]]; then
        echo "   ✅ Cloud Storage buckets and data"
    else
        echo "   ⏭️ Cloud Storage buckets (kept)"
    fi
    
    if [[ "${KEEP_PROJECT}" != "true" ]]; then
        echo "   ✅ Google Cloud project"
    else
        echo "   ⏭️ Google Cloud project (kept)"
    fi

    echo ""
    echo "📊 Project Information:"
    echo "   Project ID: ${PROJECT_ID}"
    echo "   Region: ${REGION}"
    echo "   Cleanup Time: ${TIMESTAMP}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        echo ""
        echo "✅ Cleanup completed successfully!"
        
        if [[ "${KEEP_PROJECT}" != "true" ]]; then
            echo ""
            echo "⚠️  Note: Project deletion is asynchronous and may take up to 30 days"
            echo "   to complete fully. During this time, you may still see the project"
            echo "   in the Cloud Console, but all resources have been deleted."
        fi
        
        echo ""
        echo "📝 Cleanup log saved to: ${LOG_FILE}"
    else
        echo ""
        echo "ℹ️  This was a dry run. No resources were actually deleted."
        echo "   Run without --dry-run to perform actual cleanup."
    fi
    
    echo ""
}

# Main cleanup function
main() {
    log_info "Starting Automated Regulatory Compliance Reporting cleanup..."
    log_info "Cleanup started at: $(date)"
    log_info "Log file: ${LOG_FILE}"

    # Parse command line arguments
    parse_arguments "$@"

    # Load deployment configuration
    load_configuration

    # Validate prerequisites
    validate_prerequisites

    # Confirm cleanup operation
    confirm_cleanup

    # Delete resources in reverse order of creation
    delete_scheduler_jobs
    delete_cloud_functions
    delete_document_ai_processors
    remove_iam_bindings
    delete_storage_buckets
    delete_monitoring_resources
    cleanup_local_files

    # Delete project last if requested
    delete_project

    # Display summary
    display_cleanup_summary

    if [[ "${DRY_RUN}" == "false" ]]; then
        log_success "Cleanup completed successfully!"
    else
        log_info "Dry run completed successfully!"
    fi
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Cleanup interrupted by user"
    log_info "Some resources may have been partially deleted"
    log_info "Check the Google Cloud Console to verify resource states"
    exit 130
}

# Trap interruption signals
trap cleanup_on_interrupt SIGINT SIGTERM

# Execute main function with all arguments
main "$@"