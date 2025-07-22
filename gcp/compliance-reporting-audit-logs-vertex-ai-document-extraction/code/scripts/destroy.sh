#!/bin/bash

# Compliance Reporting with Cloud Audit Logs and Vertex AI Document Extraction - Destroy Script
# This script removes all compliance reporting infrastructure from Google Cloud Platform

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CLEANUP_FILE="${SCRIPT_DIR}/cleanup_resources.txt"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
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

# Error handling function
cleanup_on_error() {
    log_error "Script failed. Check ${LOG_FILE} for details."
    log_error "Some resources may still exist and require manual cleanup."
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Compliance Reporting Infrastructure Destruction Script

Usage: $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -h, --help                    Show this help message
    --force                       Skip confirmation prompts (use with caution)
    --dry-run                     Show what would be destroyed without executing
    --keep-data                   Preserve data in storage buckets

EXAMPLES:
    $0 --project-id my-project
    $0 --project-id my-project --force
    $0 --project-id my-project --dry-run

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --keep-data)
                KEEP_DATA=true
                shift
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

    # Set defaults
    FORCE=${FORCE:-false}
    DRY_RUN=${DRY_RUN:-false}
    KEEP_DATA=${KEEP_DATA:-false}

    # Validate required parameters
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required. Use --project-id option."
        show_help
        exit 1
    fi
}

# Load environment variables from cleanup file
load_environment() {
    log_info "Loading environment variables..."

    if [[ -f "${CLEANUP_FILE}" ]]; then
        # Source the cleanup file to load variables
        source "${CLEANUP_FILE}"
        log_success "Environment variables loaded from ${CLEANUP_FILE}"
    else
        log_warning "Cleanup file not found. Using interactive mode to gather resource names."
        gather_resource_names_interactively
    fi

    # Validate required variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID not found in cleanup file or arguments"
        exit 1
    fi

    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION:-not-set}"
}

# Gather resource names interactively if cleanup file is missing
gather_resource_names_interactively() {
    log_warning "Interactive mode: Please provide resource information"
    
    read -p "Enter region (default: us-central1): " input_region
    REGION=${input_region:-"us-central1"}
    
    read -p "Enter random suffix used during deployment: " RANDOM_SUFFIX
    
    if [[ -z "${RANDOM_SUFFIX}" ]]; then
        log_error "Random suffix is required for resource identification"
        exit 1
    fi

    # Set resource names based on suffix
    AUDIT_BUCKET="audit-logs-${RANDOM_SUFFIX}"
    COMPLIANCE_BUCKET="compliance-docs-${RANDOM_SUFFIX}"
    PROCESSOR_NAME="compliance-processor-${RANDOM_SUFFIX}"
    SCHEDULER_JOB="compliance-report-${RANDOM_SUFFIX}"
    ZONE="${REGION}-a"
    
    log_info "Using resource suffix: ${RANDOM_SUFFIX}"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "${FORCE}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi

    cat << EOF

⚠️  WARNING: DESTRUCTIVE OPERATION ⚠️

This will permanently delete the following resources:
- Cloud Storage buckets and all contents
- Document AI processors
- Cloud Functions
- Cloud Scheduler jobs
- Log-based metrics
- Audit log sinks

Project: ${PROJECT_ID}
Resources with suffix: ${RANDOM_SUFFIX:-unknown}

EOF

    if [[ "${KEEP_DATA}" == "true" ]]; then
        log_warning "Data preservation mode: Storage bucket contents will be preserved"
    else
        log_warning "ALL DATA WILL BE PERMANENTLY DELETED"
    fi

    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation

    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
}

# Configure Google Cloud project
configure_project() {
    log_info "Configuring Google Cloud project..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would set project to: ${PROJECT_ID}"
        return 0
    fi

    gcloud config set project "${PROJECT_ID}"
    
    if [[ -n "${REGION:-}" ]]; then
        gcloud config set compute/region "${REGION}"
        gcloud config set compute/zone "${ZONE}"
    fi

    log_success "Project configuration completed"
}

# Remove Cloud Scheduler jobs
remove_scheduler_jobs() {
    log_info "Removing Cloud Scheduler jobs..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete scheduler jobs"
        return 0
    fi

    # Delete weekly reporting job
    if [[ -n "${SCHEDULER_JOB:-}" ]]; then
        gcloud scheduler jobs delete "${SCHEDULER_JOB}" --quiet || {
            log_warning "Failed to delete scheduler job: ${SCHEDULER_JOB}"
        }
    fi

    # Delete daily analytics job
    gcloud scheduler jobs delete compliance-analytics-daily --quiet || {
        log_warning "Failed to delete analytics scheduler job"
    }

    # List and delete any remaining jobs with the suffix
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local remaining_jobs
        remaining_jobs=$(gcloud scheduler jobs list --filter="name:${RANDOM_SUFFIX}" --format="value(name)" 2>/dev/null || echo "")
        
        for job in ${remaining_jobs}; do
            log_info "Deleting additional scheduler job: ${job}"
            gcloud scheduler jobs delete "${job}" --quiet || {
                log_warning "Failed to delete job: ${job}"
            }
        done
    fi

    log_success "Cloud Scheduler jobs removed"
}

# Remove Cloud Functions
remove_functions() {
    log_info "Removing Cloud Functions..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cloud Functions"
        return 0
    fi

    local functions=(
        "compliance-processor"
        "compliance-report-generator"
        "compliance-log-analytics"
    )

    for func in "${functions[@]}"; do
        log_info "Deleting function: ${func}"
        gcloud functions delete "${func}" --quiet || {
            log_warning "Failed to delete function: ${func}"
        }
    done

    # List and delete any remaining functions with the suffix
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local remaining_functions
        remaining_functions=$(gcloud functions list --filter="name:${RANDOM_SUFFIX}" --format="value(name)" 2>/dev/null || echo "")
        
        for func in ${remaining_functions}; do
            log_info "Deleting additional function: ${func}"
            gcloud functions delete "${func}" --quiet || {
                log_warning "Failed to delete function: ${func}"
            }
        done
    fi

    log_success "Cloud Functions removed"
}

# Remove Document AI processors
remove_document_ai() {
    log_info "Removing Document AI processors..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Document AI processors"
        return 0
    fi

    # Delete specific processor if ID is known
    if [[ -n "${PROCESSOR_ID:-}" ]] && [[ -n "${REGION:-}" ]]; then
        log_info "Deleting processor: ${PROCESSOR_ID}"
        gcloud alpha documentai processors delete \
            "projects/${PROJECT_ID}/locations/${REGION}/processors/${PROCESSOR_ID}" \
            --quiet || {
            log_warning "Failed to delete processor: ${PROCESSOR_ID}"
        }
    fi

    # Find and delete processors by name pattern
    if [[ -n "${PROCESSOR_NAME:-}" ]] && [[ -n "${REGION:-}" ]]; then
        local processors
        processors=$(gcloud alpha documentai processors list \
            --location="${REGION}" \
            --filter="displayName:${PROCESSOR_NAME}" \
            --format="value(name)" 2>/dev/null || echo "")
        
        for processor in ${processors}; do
            log_info "Deleting processor: ${processor}"
            gcloud alpha documentai processors delete "${processor}" --quiet || {
                log_warning "Failed to delete processor: ${processor}"
            }
        done

        # Also delete contract processor
        local contract_processors
        contract_processors=$(gcloud alpha documentai processors list \
            --location="${REGION}" \
            --filter="displayName:contract-${PROCESSOR_NAME}" \
            --format="value(name)" 2>/dev/null || echo "")
        
        for processor in ${contract_processors}; do
            log_info "Deleting contract processor: ${processor}"
            gcloud alpha documentai processors delete "${processor}" --quiet || {
                log_warning "Failed to delete contract processor: ${processor}"
            }
        done
    fi

    log_success "Document AI processors removed"
}

# Remove storage buckets
remove_storage() {
    log_info "Removing Cloud Storage buckets..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete storage buckets: ${AUDIT_BUCKET:-unknown}, ${COMPLIANCE_BUCKET:-unknown}"
        return 0
    fi

    # Remove audit logs bucket
    if [[ -n "${AUDIT_BUCKET:-}" ]]; then
        if [[ "${KEEP_DATA}" == "true" ]]; then
            log_warning "Preserving data in bucket: ${AUDIT_BUCKET}"
        else
            log_info "Deleting bucket and contents: ${AUDIT_BUCKET}"
            gsutil -m rm -r "gs://${AUDIT_BUCKET}" || {
                log_warning "Failed to delete audit bucket: ${AUDIT_BUCKET}"
            }
        fi
    fi

    # Remove compliance documents bucket
    if [[ -n "${COMPLIANCE_BUCKET:-}" ]]; then
        if [[ "${KEEP_DATA}" == "true" ]]; then
            log_warning "Preserving data in bucket: ${COMPLIANCE_BUCKET}"
        else
            log_info "Deleting bucket and contents: ${COMPLIANCE_BUCKET}"
            gsutil -m rm -r "gs://${COMPLIANCE_BUCKET}" || {
                log_warning "Failed to delete compliance bucket: ${COMPLIANCE_BUCKET}"
            }
        fi
    fi

    # Find and delete additional buckets with the suffix
    if [[ -n "${RANDOM_SUFFIX:-}" ]] && [[ "${KEEP_DATA}" != "true" ]]; then
        local remaining_buckets
        remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "${RANDOM_SUFFIX}" || echo "")
        
        for bucket in ${remaining_buckets}; do
            log_info "Deleting additional bucket: ${bucket}"
            gsutil -m rm -r "${bucket}" || {
                log_warning "Failed to delete bucket: ${bucket}"
            }
        done
    fi

    log_success "Storage buckets processed"
}

# Remove monitoring and logging configuration
remove_monitoring() {
    log_info "Removing monitoring and logging configuration..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete monitoring metrics and audit log sink"
        return 0
    fi

    # Delete log-based metrics
    gcloud logging metrics delete compliance_violations --quiet || {
        log_warning "Failed to delete metric: compliance_violations"
    }

    gcloud logging metrics delete document_processing_success --quiet || {
        log_warning "Failed to delete metric: document_processing_success"
    }

    # Delete audit log sink
    gcloud logging sinks delete compliance-audit-sink --quiet || {
        log_warning "Failed to delete audit log sink: compliance-audit-sink"
    }

    # Find and delete additional metrics with the suffix
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local remaining_metrics
        remaining_metrics=$(gcloud logging metrics list --filter="name:${RANDOM_SUFFIX}" --format="value(name)" 2>/dev/null || echo "")
        
        for metric in ${remaining_metrics}; do
            log_info "Deleting additional metric: ${metric}"
            gcloud logging metrics delete "${metric}" --quiet || {
                log_warning "Failed to delete metric: ${metric}"
            }
        done
    fi

    log_success "Monitoring and logging configuration removed"
}

# Reset IAM policy (optional)
reset_iam_policy() {
    log_info "Checking IAM policy reset..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would check for IAM policy reset"
        return 0
    fi

    # Check if audit-policy.yaml exists in current directory
    if [[ -f "audit-policy.yaml" ]]; then
        log_warning "Found audit-policy.yaml. Consider resetting IAM policy if it was modified."
        if [[ "${FORCE}" != "true" ]]; then
            read -p "Reset IAM audit policy to default? (y/N): " reset_policy
            if [[ "${reset_policy}" == "y" || "${reset_policy}" == "Y" ]]; then
                # This is a placeholder - actual policy reset requires original policy backup
                log_warning "IAM policy reset requires manual intervention with original policy backup"
            fi
        fi
    fi

    log_success "IAM policy check completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi

    local files_to_remove=(
        "audit-policy.yaml"
        "lifecycle.json"
        "compliance-policy.txt"
        "sample-contract.txt"
    )

    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            log_info "Removing local file: ${file}"
            rm -f "${file}"
        fi
    done

    # Optionally remove cleanup file
    if [[ "${FORCE}" == "true" ]]; then
        log_info "Removing cleanup file: ${CLEANUP_FILE}"
        rm -f "${CLEANUP_FILE}"
    fi

    log_success "Local files cleaned up"
}

# Verify resource deletion
verify_deletion() {
    log_info "Verifying resource deletion..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would verify resource deletion"
        return 0
    fi

    local verification_failed=false

    # Check if buckets still exist
    if [[ -n "${AUDIT_BUCKET:-}" ]] && [[ "${KEEP_DATA}" != "true" ]]; then
        if gsutil ls "gs://${AUDIT_BUCKET}" &>/dev/null; then
            log_warning "Audit bucket still exists: ${AUDIT_BUCKET}"
            verification_failed=true
        fi
    fi

    if [[ -n "${COMPLIANCE_BUCKET:-}" ]] && [[ "${KEEP_DATA}" != "true" ]]; then
        if gsutil ls "gs://${COMPLIANCE_BUCKET}" &>/dev/null; then
            log_warning "Compliance bucket still exists: ${COMPLIANCE_BUCKET}"
            verification_failed=true
        fi
    fi

    # Check if functions still exist
    local remaining_functions
    remaining_functions=$(gcloud functions list --format="value(name)" 2>/dev/null | grep -E "(compliance-processor|compliance-report-generator|compliance-log-analytics)" || echo "")
    
    if [[ -n "${remaining_functions}" ]]; then
        log_warning "Some functions still exist: ${remaining_functions}"
        verification_failed=true
    fi

    # Check if scheduler jobs still exist
    local remaining_jobs
    remaining_jobs=$(gcloud scheduler jobs list --format="value(name)" 2>/dev/null | grep -E "(${SCHEDULER_JOB:-}|compliance-analytics-daily)" || echo "")
    
    if [[ -n "${remaining_jobs}" ]]; then
        log_warning "Some scheduler jobs still exist: ${remaining_jobs}"
        verification_failed=true
    fi

    if [[ "${verification_failed}" == "true" ]]; then
        log_warning "Some resources may not have been fully deleted. Manual cleanup may be required."
    else
        log_success "All resources successfully removed"
    fi
}

# Display destruction summary
show_summary() {
    log_info "Destruction Summary"
    cat << EOF

🧹 Compliance Reporting Infrastructure Destruction Completed

📋 DESTRUCTION DETAILS:
   Project ID: ${PROJECT_ID}
   Region: ${REGION:-not-set}
   Resource Suffix: ${RANDOM_SUFFIX:-unknown}
   Data Preserved: ${KEEP_DATA}

🗑️  REMOVED RESOURCES:
   • Cloud Scheduler Jobs
   • Cloud Functions  
   • Document AI Processors
   • Log-based Metrics
   • Audit Log Sinks
$(if [[ "${KEEP_DATA}" != "true" ]]; then
    echo "   • Cloud Storage Buckets and Contents"
else
    echo "   • Cloud Storage Buckets (contents preserved)"
fi)

📝 LOGS:
   Destruction log: ${LOG_FILE}

$(if [[ "${KEEP_DATA}" == "true" ]]; then
    cat << KEEP_DATA_EOF

💾 DATA PRESERVATION:
   The following buckets were preserved with their contents:
   • gs://${AUDIT_BUCKET:-unknown}
   • gs://${COMPLIANCE_BUCKET:-unknown}
   
   To remove these manually, run:
   gsutil -m rm -r gs://${AUDIT_BUCKET:-BUCKET_NAME}
   gsutil -m rm -r gs://${COMPLIANCE_BUCKET:-BUCKET_NAME}

KEEP_DATA_EOF
fi)

⚠️  IMPORTANT NOTES:
   • Some resources may take a few minutes to be fully deleted
   • Check the Google Cloud Console to verify complete removal
   • Billing charges should stop within 24 hours of resource deletion
   • Consider disabling APIs if no longer needed

EOF
}

# Main destruction function
main() {
    log_info "Starting Compliance Reporting Infrastructure Destruction"
    log_info "Script started at $(date)"

    parse_args "$@"
    load_environment
    confirm_destruction
    configure_project
    remove_scheduler_jobs
    remove_functions
    remove_document_ai
    remove_storage
    remove_monitoring
    reset_iam_policy
    cleanup_local_files
    verify_deletion
    show_summary

    log_success "Destruction completed!"
    log_info "Total destruction time: $((SECONDS / 60)) minutes and $((SECONDS % 60)) seconds"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi