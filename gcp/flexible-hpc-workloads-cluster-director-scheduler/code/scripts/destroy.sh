#!/bin/bash

# Flexible HPC Workloads with Cluster Toolkit and Dynamic Scheduler - Cleanup Script
# This script safely removes all resources created by the HPC cluster deployment
# including compute instances, storage, batch jobs, and monitoring configurations.

set -euo pipefail

# Enable colored output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/hpc-config.env"

# Default values
DRY_RUN=false
SKIP_CONFIRMATION=false
DEBUG=false
FORCE_DELETE=false

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

log_debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        log "${YELLOW}[DEBUG]${NC} $*"
    fi
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code ${exit_code}"
    log_info "Check ${LOG_FILE} for detailed error information"
    log_warning "Some resources may still exist and require manual cleanup"
    exit ${exit_code}
}

trap cleanup_on_error ERR

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup Flexible HPC Workloads infrastructure and resources

OPTIONS:
    -d, --dry-run                   Show what would be deleted without making changes
    -y, --yes                       Skip confirmation prompts
    -f, --force                     Force deletion even if errors occur
    --debug                         Enable debug logging
    -h, --help                      Show this help message

EXAMPLES:
    $0                              # Interactive cleanup
    $0 --dry-run                    # Preview what would be deleted
    $0 --yes                        # Skip confirmations
    $0 --force --yes                # Force cleanup without prompts

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            --debug)
                DEBUG=true
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
}

# Load configuration from deployment
load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        log_error "Cannot determine what resources to clean up"
        log_error "Please run this script from the same directory as deploy.sh"
        exit 1
    fi
    
    # Source the configuration file
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
    
    # Validate required variables
    local required_vars=(
        "PROJECT_ID"
        "REGION"
        "ZONE"
        "CLUSTER_NAME"
        "STORAGE_BUCKET"
        "RANDOM_SUFFIX"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required configuration variable ${var} is not set"
            exit 1
        fi
    done
    
    log_success "Configuration loaded:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Zone: ${ZONE}"
    log_info "  Cluster Name: ${CLUSTER_NAME}"
    log_info "  Storage Bucket: ${STORAGE_BUCKET}"
}

# Validation functions
validate_prerequisites() {
    log_info "Validating prerequisites for cleanup..."
    
    # Check if gcloud is available
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Set project context
    if ! gcloud config set project "${PROJECT_ID}" --quiet; then
        log_error "Failed to set project context to ${PROJECT_ID}"
        exit 1
    fi
    
    # Verify project access
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Cannot access project '${PROJECT_ID}'"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Cleanup plan display
show_cleanup_plan() {
    log_info "Cleanup Plan for HPC Cluster:"
    echo ""
    echo "  📋 Project: ${PROJECT_ID}"
    echo "  🌍 Region: ${REGION}"
    echo "  📍 Zone: ${ZONE}"
    echo ""
    echo "  🗑️  Resources to be removed:"
    echo "    • Cloud Batch jobs and queues"
    echo "    • GPU reservations (if any)"
    echo "    • HPC Cluster infrastructure: ${CLUSTER_NAME}"
    echo "    • Compute Engine instances (hpc-worker*, gpu-worker*)"
    echo "    • Storage bucket: gs://${STORAGE_BUCKET}"
    echo "    • Monitoring dashboards"
    echo "    • Budget alerts"
    echo "    • Configuration and temporary files"
    echo ""
    echo "  ⚠️  Warning: This action is irreversible!"
    echo "    • All data in the storage bucket will be permanently deleted"
    echo "    • Running workloads will be terminated"
    echo "    • Monitoring data will be lost"
    echo ""
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
        return
    fi
    
    if [[ "${SKIP_CONFIRMATION}" == "false" ]]; then
        echo -n "Are you sure you want to delete all HPC cluster resources? (y/N): "
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
        
        echo -n "This will permanently delete all data. Type 'DELETE' to confirm: "
        read -r confirmation
        if [[ "${confirmation}" != "DELETE" ]]; then
            log_info "Cleanup cancelled - confirmation not received"
            exit 0
        fi
    fi
}

# Cleanup functions with error handling
safe_delete() {
    local description="$1"
    local command="$2"
    
    log_info "Deleting ${description}..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would execute: ${command}"
        return 0
    fi
    
    if eval "${command}"; then
        log_success "✅ ${description} deleted successfully"
        return 0
    else
        local exit_code=$?
        if [[ "${FORCE_DELETE}" == "true" ]]; then
            log_warning "⚠️ Failed to delete ${description} (continuing due to --force)"
            return 0
        else
            log_error "❌ Failed to delete ${description}"
            return ${exit_code}
        fi
    fi
}

# Resource cleanup functions
cleanup_batch_jobs() {
    log_info "Cleaning up Cloud Batch jobs..."
    
    # Get list of batch jobs
    local jobs
    jobs=$(gcloud batch jobs list --location="${REGION}" \
        --filter="name~${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -z "${jobs}" ]]; then
        log_info "No batch jobs found to clean up"
        return
    fi
    
    # Delete each job
    while IFS= read -r job; do
        if [[ -n "${job}" ]]; then
            safe_delete "batch job ${job}" \
                "gcloud batch jobs delete '${job}' --location='${REGION}' --quiet"
        fi
    done <<< "${jobs}"
}

cleanup_gpu_reservations() {
    log_info "Cleaning up GPU reservations..."
    
    # Get list of reservations
    local reservations
    reservations=$(gcloud compute reservations list \
        --filter="name~hpc-gpu-reservation" \
        --format="value(name,zone)" 2>/dev/null || echo "")
    
    if [[ -z "${reservations}" ]]; then
        log_info "No GPU reservations found to clean up"
        return
    fi
    
    # Delete each reservation
    while IFS=$'\t' read -r name zone; do
        if [[ -n "${name}" && -n "${zone}" ]]; then
            safe_delete "GPU reservation ${name}" \
                "gcloud compute reservations delete '${name}' --zone='${zone}' --quiet"
        fi
    done <<< "${reservations}"
}

cleanup_cluster_infrastructure() {
    log_info "Cleaning up HPC cluster infrastructure..."
    
    # Check if Terraform deployment directory exists
    local terraform_dir="${SCRIPT_DIR}/../../${CLUSTER_NAME}"
    
    if [[ -d "${terraform_dir}" ]]; then
        log_info "Found Terraform deployment directory: ${terraform_dir}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "Would destroy Terraform infrastructure in ${terraform_dir}"
            return
        fi
        
        # Destroy with Terraform
        cd "${terraform_dir}" || {
            log_warning "Cannot change to Terraform directory: ${terraform_dir}"
            return 1
        }
        
        if terraform destroy -var="project_id=${PROJECT_ID}" -auto-approve; then
            log_success "Terraform infrastructure destroyed"
            
            # Clean up deployment directory
            cd "${SCRIPT_DIR}" || exit 1
            rm -rf "${terraform_dir}"
            log_success "Terraform deployment directory removed"
        else
            log_error "Terraform destroy failed"
            cd "${SCRIPT_DIR}" || exit 1
            return 1
        fi
    else
        log_warning "Terraform deployment directory not found: ${terraform_dir}"
        log_info "Attempting manual cleanup of compute instances..."
        
        # Manual cleanup of compute instances
        local instances
        instances=$(gcloud compute instances list \
            --filter="name~(hpc-worker|gpu-worker)" \
            --format="value(name,zone)" 2>/dev/null || echo "")
        
        if [[ -n "${instances}" ]]; then
            while IFS=$'\t' read -r name zone; do
                if [[ -n "${name}" && -n "${zone}" ]]; then
                    safe_delete "compute instance ${name}" \
                        "gcloud compute instances delete '${name}' --zone='${zone}' --quiet"
                fi
            done <<< "${instances}"
        fi
    fi
}

cleanup_storage() {
    log_info "Cleaning up storage resources..."
    
    # Check if bucket exists
    if gsutil ls "gs://${STORAGE_BUCKET}" &>/dev/null; then
        safe_delete "storage bucket gs://${STORAGE_BUCKET}" \
            "gsutil -m rm -r 'gs://${STORAGE_BUCKET}'"
    else
        log_info "Storage bucket gs://${STORAGE_BUCKET} not found or already deleted"
    fi
}

cleanup_monitoring() {
    log_info "Cleaning up monitoring resources..."
    
    # Get monitoring dashboards
    local dashboards
    dashboards=$(gcloud monitoring dashboards list \
        --filter="displayName~'HPC Cluster Monitoring - ${CLUSTER_NAME}'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${dashboards}" ]]; then
        while IFS= read -r dashboard; do
            if [[ -n "${dashboard}" ]]; then
                safe_delete "monitoring dashboard" \
                    "gcloud monitoring dashboards delete '${dashboard}' --quiet"
            fi
        done <<< "${dashboards}"
    else
        log_info "No monitoring dashboards found to clean up"
    fi
}

cleanup_budget_alerts() {
    log_info "Cleaning up budget alerts..."
    
    # Get billing account
    local billing_account
    billing_account=$(gcloud beta billing projects describe "${PROJECT_ID}" \
        --format="value(billingAccountName)" 2>/dev/null | cut -d'/' -f2 || echo "")
    
    if [[ -n "${billing_account}" ]]; then
        # Get budget alerts
        local budgets
        budgets=$(gcloud alpha billing budgets list \
            --billing-account="${billing_account}" \
            --filter="displayName~'HPC Cluster Budget Alert - ${CLUSTER_NAME}'" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${budgets}" ]]; then
            while IFS= read -r budget; do
                if [[ -n "${budget}" ]]; then
                    safe_delete "budget alert" \
                        "gcloud alpha billing budgets delete '${budget}' --billing-account='${billing_account}' --quiet"
                fi
            done <<< "${budgets}"
        else
            log_info "No budget alerts found to clean up"
        fi
    else
        log_warning "Cannot determine billing account for budget cleanup"
    fi
}

cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    local files_to_clean=(
        "${SCRIPT_DIR}/hpc-blueprint.yaml"
        "${SCRIPT_DIR}/lifecycle.json"
        "${SCRIPT_DIR}/batch-job-config.json"
        "${SCRIPT_DIR}/hpc-monitoring.json"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -f "${file}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "Would remove file: ${file}"
            else
                rm -f "${file}"
                log_success "Removed file: ${file}"
            fi
        fi
    done
    
    # Keep config file for reference but rename it
    if [[ -f "${CONFIG_FILE}" && "${DRY_RUN}" == "false" ]]; then
        local backup_config="${CONFIG_FILE}.deleted-$(date +%Y%m%d-%H%M%S)"
        mv "${CONFIG_FILE}" "${backup_config}"
        log_info "Configuration backed up to: ${backup_config}"
    fi
}

verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Would verify all resources are deleted"
        return
    fi
    
    local verification_passed=true
    
    # Check storage bucket
    if gsutil ls "gs://${STORAGE_BUCKET}" &>/dev/null; then
        log_warning "⚠️ Storage bucket still exists: gs://${STORAGE_BUCKET}"
        verification_passed=false
    else
        log_success "✅ Storage bucket cleanup verified"
    fi
    
    # Check compute instances
    local instance_count
    instance_count=$(gcloud compute instances list \
        --filter="name~(hpc-worker|gpu-worker)" \
        --format="value(name)" | wc -l)
    
    if [[ "${instance_count}" -eq 0 ]]; then
        log_success "✅ Compute instances cleanup verified"
    else
        log_warning "⚠️ ${instance_count} compute instances still exist"
        verification_passed=false
    fi
    
    # Check batch jobs
    local job_count
    job_count=$(gcloud batch jobs list --location="${REGION}" \
        --filter="name~${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null | wc -l || echo "0")
    
    if [[ "${job_count}" -eq 0 ]]; then
        log_success "✅ Batch jobs cleanup verified"
    else
        log_warning "⚠️ ${job_count} batch jobs still exist"
        verification_passed=false
    fi
    
    if [[ "${verification_passed}" == "true" ]]; then
        log_success "✅ All resources successfully cleaned up"
    else
        log_warning "⚠️ Some resources may still exist - check Google Cloud Console"
    fi
}

display_cleanup_summary() {
    log_info "Cleanup completed! 🧹"
    echo ""
    echo "📋 Cleanup Summary:"
    echo "  Project: ${PROJECT_ID}"
    echo "  Cluster: ${CLUSTER_NAME}"
    echo "  Region: ${REGION}"
    echo ""
    echo "✅ Resources cleaned up:"
    echo "  • Cloud Batch jobs and queues"
    echo "  • GPU reservations"
    echo "  • HPC cluster infrastructure"
    echo "  • Compute instances"
    echo "  • Storage bucket and data"
    echo "  • Monitoring dashboards"
    echo "  • Budget alerts"
    echo "  • Local configuration files"
    echo ""
    echo "💡 Final steps:"
    echo "  1. Check Google Cloud Console to verify all resources are removed"
    echo "  2. Review any remaining charges in billing"
    echo "  3. Consider disabling unused APIs if no longer needed"
    echo ""
    echo "📋 Logs available at: ${LOG_FILE}"
    
    if [[ -f "${CONFIG_FILE}.deleted-$(date +%Y%m%d)" ]]; then
        echo "📝 Configuration backup available for reference"
    fi
}

# Main execution
main() {
    log_info "Starting HPC Cluster cleanup..."
    log_info "Log file: ${LOG_FILE}"
    
    parse_args "$@"
    load_configuration
    validate_prerequisites
    show_cleanup_plan
    
    # Execute cleanup in dependency order
    cleanup_batch_jobs
    cleanup_gpu_reservations
    cleanup_cluster_infrastructure
    cleanup_storage
    cleanup_monitoring
    cleanup_budget_alerts
    cleanup_local_files
    
    verify_cleanup
    display_cleanup_summary
    
    log_success "HPC Cluster cleanup completed successfully!"
}

# Execute main function with all arguments
main "$@"