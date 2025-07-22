#!/bin/bash

# Destroy script for Resource Governance with Policy Simulator and Resource Manager
# This script safely removes all resources created by the governance deployment

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
    log_error "Script failed at line $1. Exit code: $2"
    log_error "Check the logs above for details."
    exit 1
}

# Set up error handling
trap 'handle_error ${LINENO} $?' ERR

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destruction.log"
DRY_RUN=false
FORCE=false
SKIP_CONFIRMATION=false

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Resource Governance infrastructure on GCP

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be destroyed without making changes
    -f, --force         Skip all confirmation prompts
    -y, --yes           Skip main confirmation prompt
    -v, --verbose       Enable verbose logging
    -e, --env-file      Specify custom environment file path (default: .deployment_env)

EXAMPLES:
    $0                          # Interactive destruction with confirmations
    $0 --dry-run               # Show what would be destroyed
    $0 --force                 # Destroy everything without prompts
    $0 --yes --verbose         # Skip main prompt but confirm individual resources

SAFETY:
    This script will permanently delete cloud resources and data.
    Use --dry-run first to review what will be destroyed.
    Backup any important data before running this script.

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -e|--env-file)
                ENV_FILE="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Load environment variables from deployment
load_environment() {
    local env_file="${ENV_FILE:-${SCRIPT_DIR}/.deployment_env}"
    
    if [[ -f "$env_file" ]]; then
        log_info "Loading environment from: $env_file"
        # shellcheck source=/dev/null
        source "$env_file"
        
        # Validate required variables
        local required_vars=("PROJECT_ID" "REGION")
        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                log_error "Required environment variable $var is not set"
                exit 1
            fi
        done
        
        log_info "Environment loaded successfully"
        log_info "  PROJECT_ID: ${PROJECT_ID}"
        log_info "  REGION: ${REGION}"
        log_info "  ORGANIZATION_ID: ${ORGANIZATION_ID:-'(not set)'}"
        log_info "  FUNCTION_NAME: ${FUNCTION_NAME:-'(not set)'}"
        log_info "  BUCKET_NAME: ${BUCKET_NAME:-'(not set)'}"
        log_info "  TOPIC_NAME: ${TOPIC_NAME:-'(not set)'}"
    else
        log_warning "Environment file not found: $env_file"
        log_info "You can specify environment variables manually or use --env-file option"
        
        # Prompt for required variables
        read -p "Enter PROJECT_ID: " PROJECT_ID
        read -p "Enter REGION (default: us-central1): " REGION
        REGION="${REGION:-us-central1}"
        read -p "Enter ORGANIZATION_ID (optional): " ORGANIZATION_ID
        
        export PROJECT_ID REGION ORGANIZATION_ID
    fi
}

# Confirm destruction
confirm_destruction() {
    if $SKIP_CONFIRMATION; then
        log_info "Skipping confirmation (--yes or --force flag used)"
        return
    fi
    
    log_warning "WARNING: This will permanently delete the following resources:"
    log_warning "  - Project: ${PROJECT_ID}"
    log_warning "  - Cloud Functions: ${FUNCTION_NAME:-'governance-automation-*'}"
    log_warning "  - Storage Bucket: ${BUCKET_NAME:-'governance-reports-*'}"
    log_warning "  - Pub/Sub Topic: ${TOPIC_NAME:-'governance-events-*'}"
    log_warning "  - Service Accounts: policy-simulator-sa, billing-governance-sa"
    log_warning "  - Cloud Scheduler Jobs: governance-audit-job, cost-monitoring-job"
    if [[ -n "${ORGANIZATION_ID:-}" ]]; then
        log_warning "  - Organization Policies and Constraints"
    fi
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed"
        exit 1
    fi

    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "You are not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi

    # Set the project context
    if [[ -n "${PROJECT_ID}" ]]; then
        gcloud config set project "${PROJECT_ID}" 2>/dev/null || true
    fi

    log_success "Prerequisites check completed"
}

# Remove Cloud Scheduler jobs
remove_scheduler_jobs() {
    log_info "Removing Cloud Scheduler jobs..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would remove Cloud Scheduler jobs"
        return
    fi

    local jobs=("governance-audit-job" "cost-monitoring-job")
    
    for job in "${jobs[@]}"; do
        if gcloud scheduler jobs describe "$job" --location="${REGION}" &>/dev/null; then
            log_info "Removing scheduler job: $job"
            if $FORCE || ask_confirmation "Remove scheduler job $job?"; then
                gcloud scheduler jobs delete "$job" --location="${REGION}" --quiet
                log_success "Removed scheduler job: $job"
            else
                log_warning "Skipped scheduler job: $job"
            fi
        else
            log_info "Scheduler job not found: $job"
        fi
    done
}

# Remove Cloud Function
remove_cloud_function() {
    log_info "Removing Cloud Function..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would remove Cloud Function: ${FUNCTION_NAME:-'governance-automation-*'}"
        return
    fi

    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
            log_info "Removing Cloud Function: ${FUNCTION_NAME}"
            if $FORCE || ask_confirmation "Remove Cloud Function ${FUNCTION_NAME}?"; then
                gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet
                log_success "Removed Cloud Function: ${FUNCTION_NAME}"
            else
                log_warning "Skipped Cloud Function: ${FUNCTION_NAME}"
            fi
        else
            log_info "Cloud Function not found: ${FUNCTION_NAME}"
        fi
    else
        # Try to find functions by pattern
        log_info "Searching for governance automation functions..."
        local functions
        functions=$(gcloud functions list --region="${REGION}" --filter="name:governance-automation" --format="value(name)" 2>/dev/null || true)
        
        if [[ -n "$functions" ]]; then
            while IFS= read -r function_name; do
                if [[ -n "$function_name" ]]; then
                    log_info "Found function: $function_name"
                    if $FORCE || ask_confirmation "Remove Cloud Function $function_name?"; then
                        gcloud functions delete "$function_name" --region="${REGION}" --quiet
                        log_success "Removed Cloud Function: $function_name"
                    else
                        log_warning "Skipped Cloud Function: $function_name"
                    fi
                fi
            done <<< "$functions"
        else
            log_info "No governance automation functions found"
        fi
    fi
}

# Remove Pub/Sub topic
remove_pubsub_topic() {
    log_info "Removing Pub/Sub topic..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would remove Pub/Sub topic: ${TOPIC_NAME:-'governance-events-*'}"
        return
    fi

    if [[ -n "${TOPIC_NAME:-}" ]]; then
        if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
            log_info "Removing Pub/Sub topic: ${TOPIC_NAME}"
            if $FORCE || ask_confirmation "Remove Pub/Sub topic ${TOPIC_NAME}?"; then
                gcloud pubsub topics delete "${TOPIC_NAME}" --quiet
                log_success "Removed Pub/Sub topic: ${TOPIC_NAME}"
            else
                log_warning "Skipped Pub/Sub topic: ${TOPIC_NAME}"
            fi
        else
            log_info "Pub/Sub topic not found: ${TOPIC_NAME}"
        fi
    else
        # Try to find topics by pattern
        log_info "Searching for governance event topics..."
        local topics
        topics=$(gcloud pubsub topics list --filter="name:governance-events" --format="value(name)" 2>/dev/null || true)
        
        if [[ -n "$topics" ]]; then
            while IFS= read -r topic_name; do
                if [[ -n "$topic_name" ]]; then
                    local topic_short_name="${topic_name##*/}"
                    log_info "Found topic: $topic_short_name"
                    if $FORCE || ask_confirmation "Remove Pub/Sub topic $topic_short_name?"; then
                        gcloud pubsub topics delete "$topic_short_name" --quiet
                        log_success "Removed Pub/Sub topic: $topic_short_name"
                    else
                        log_warning "Skipped Pub/Sub topic: $topic_short_name"
                    fi
                fi
            done <<< "$topics"
        else
            log_info "No governance event topics found"
        fi
    fi
}

# Remove storage bucket
remove_storage_bucket() {
    log_info "Removing storage bucket..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would remove storage bucket: gs://${BUCKET_NAME:-'governance-reports-*'}"
        return
    fi

    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            log_info "Removing storage bucket: gs://${BUCKET_NAME}"
            if $FORCE || ask_confirmation "Remove storage bucket gs://${BUCKET_NAME} and all its contents?"; then
                # Remove all objects first, then the bucket
                gsutil -m rm -r "gs://${BUCKET_NAME}/*" 2>/dev/null || true
                gsutil rb "gs://${BUCKET_NAME}"
                log_success "Removed storage bucket: gs://${BUCKET_NAME}"
            else
                log_warning "Skipped storage bucket: gs://${BUCKET_NAME}"
            fi
        else
            log_info "Storage bucket not found: gs://${BUCKET_NAME}"
        fi
    else
        # Try to find buckets by pattern
        log_info "Searching for governance report buckets..."
        local buckets
        buckets=$(gsutil ls -b gs://governance-reports-* 2>/dev/null | sed 's|gs://||' | sed 's|/||' || true)
        
        if [[ -n "$buckets" ]]; then
            while IFS= read -r bucket_name; do
                if [[ -n "$bucket_name" ]]; then
                    log_info "Found bucket: $bucket_name"
                    if $FORCE || ask_confirmation "Remove storage bucket gs://$bucket_name and all its contents?"; then
                        gsutil -m rm -r "gs://${bucket_name}/*" 2>/dev/null || true
                        gsutil rb "gs://${bucket_name}"
                        log_success "Removed storage bucket: gs://$bucket_name"
                    else
                        log_warning "Skipped storage bucket: gs://$bucket_name"
                    fi
                fi
            done <<< "$buckets"
        else
            log_info "No governance report buckets found"
        fi
    fi
}

# Remove service accounts
remove_service_accounts() {
    log_info "Removing service accounts..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would remove service accounts"
        return
    fi

    local service_accounts=("policy-simulator-sa" "billing-governance-sa")
    
    for sa in "${service_accounts[@]}"; do
        local sa_email="${sa}@${PROJECT_ID}.iam.gserviceaccount.com"
        
        if gcloud iam service-accounts describe "$sa_email" &>/dev/null; then
            log_info "Removing service account: $sa_email"
            if $FORCE || ask_confirmation "Remove service account $sa_email?"; then
                # Remove IAM policy bindings first
                if [[ -n "${ORGANIZATION_ID:-}" ]]; then
                    log_info "Removing organization-level IAM bindings for $sa_email"
                    local roles=("roles/policysimulator.admin" "roles/iam.securityReviewer" "roles/billing.viewer")
                    for role in "${roles[@]}"; do
                        gcloud organizations remove-iam-policy-binding "${ORGANIZATION_ID}" \
                            --member="serviceAccount:$sa_email" \
                            --role="$role" \
                            --quiet 2>/dev/null || true
                    done
                fi
                
                # Remove project-level IAM bindings
                log_info "Removing project-level IAM bindings for $sa_email"
                local project_roles=("roles/iam.securityReviewer" "roles/billing.viewer")
                for role in "${project_roles[@]}"; do
                    gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                        --member="serviceAccount:$sa_email" \
                        --role="$role" \
                        --quiet 2>/dev/null || true
                done
                
                # Delete the service account
                gcloud iam service-accounts delete "$sa_email" --quiet
                log_success "Removed service account: $sa_email"
            else
                log_warning "Skipped service account: $sa_email"
            fi
        else
            log_info "Service account not found: $sa_email"
        fi
    done
}

# Remove organization policies and constraints
remove_organization_policies() {
    log_info "Removing organization policies and constraints..."

    if [[ -z "${ORGANIZATION_ID:-}" ]]; then
        log_warning "Organization ID not set. Skipping organization policies."
        return
    fi

    if $DRY_RUN; then
        log_info "[DRY RUN] Would remove organization policies and constraints"
        return
    fi

    local constraints=(
        "custom.validateResourceLabels"
        "custom.restrictComputeLocations"
    )

    local policies=(
        "iam.managed.requireResourceLabels"
    )

    # Remove policies first
    for policy in "${policies[@]}"; do
        log_info "Checking organization policy: $policy"
        if gcloud org-policies describe "$policy" --organization="${ORGANIZATION_ID}" &>/dev/null; then
            if $FORCE || ask_confirmation "Remove organization policy $policy?"; then
                gcloud org-policies delete "$policy" --organization="${ORGANIZATION_ID}" --quiet
                log_success "Removed organization policy: $policy"
            else
                log_warning "Skipped organization policy: $policy"
            fi
        else
            log_info "Organization policy not found: $policy"
        fi
    done

    # Remove custom constraints
    for constraint in "${constraints[@]}"; do
        log_info "Checking custom constraint: $constraint"
        if gcloud org-policies describe-custom-constraint "$constraint" --organization="${ORGANIZATION_ID}" &>/dev/null; then
            if $FORCE || ask_confirmation "Remove custom constraint $constraint?"; then
                gcloud org-policies delete-custom-constraint "$constraint" --organization="${ORGANIZATION_ID}" --quiet
                log_success "Removed custom constraint: $constraint"
            else
                log_warning "Skipped custom constraint: $constraint"
            fi
        else
            log_info "Custom constraint not found: $constraint"
        fi
    done
}

# Remove project (optional)
remove_project() {
    log_info "Project removal option..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would offer to remove project: ${PROJECT_ID}"
        return
    fi

    if ! $FORCE; then
        log_warning "Project deletion will permanently remove ALL resources in the project: ${PROJECT_ID}"
        echo "This includes any resources not created by this governance system."
        echo "Consider removing individual resources instead if this project contains other important resources."
        echo
        read -p "Do you want to delete the entire project ${PROJECT_ID}? (type 'DELETE' to confirm): " project_confirmation
        
        if [[ "$project_confirmation" == "DELETE" ]]; then
            log_info "Deleting project: ${PROJECT_ID}"
            gcloud projects delete "${PROJECT_ID}" --quiet
            log_success "Project deleted: ${PROJECT_ID}"
        else
            log_info "Skipped project deletion"
        fi
    else
        log_warning "Force mode enabled - skipping project deletion for safety"
        log_info "To delete the project, run: gcloud projects delete ${PROJECT_ID}"
    fi
}

# Helper function for confirmation prompts
ask_confirmation() {
    local prompt="$1"
    if $FORCE; then
        return 0
    fi
    
    read -p "$prompt (y/N): " response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Cleanup environment file
cleanup_environment() {
    log_info "Cleaning up environment file..."

    if $DRY_RUN; then
        log_info "[DRY RUN] Would remove environment file"
        return
    fi

    local env_file="${ENV_FILE:-${SCRIPT_DIR}/.deployment_env}"
    
    if [[ -f "$env_file" ]]; then
        if $FORCE || ask_confirmation "Remove environment file $env_file?"; then
            rm "$env_file"
            log_success "Removed environment file: $env_file"
        else
            log_warning "Skipped environment file: $env_file"
        fi
    else
        log_info "Environment file not found: $env_file"
    fi
}

# Main destruction function
main() {
    log_info "Starting Resource Governance destruction..."
    
    # Initialize logging
    exec 1> >(tee -a "${LOG_FILE}")
    exec 2> >(tee -a "${LOG_FILE}" >&2)
    
    log_info "Destruction started at $(date)"
    log_info "Log file: ${LOG_FILE}"

    # Parse command line arguments
    parse_args "$@"

    if $DRY_RUN; then
        log_info "=== DRY RUN MODE - No changes will be made ==="
    fi

    # Load environment and confirm
    load_environment
    check_prerequisites
    confirm_destruction

    # Execute destruction steps in reverse order of creation
    log_info "=== Starting resource removal ==="
    
    remove_scheduler_jobs
    remove_cloud_function
    remove_pubsub_topic
    remove_storage_bucket
    remove_service_accounts
    remove_organization_policies
    
    # Optional project removal
    if ! $DRY_RUN; then
        echo
        log_info "=== Project Removal ==="
        remove_project
    fi

    # Cleanup
    cleanup_environment

    # Destruction summary
    if $DRY_RUN; then
        log_info "=== DRY RUN COMPLETED ==="
        log_info "Run without --dry-run flag to perform actual destruction"
    else
        log_success "=== DESTRUCTION COMPLETED ==="
        log_info "All specified resources have been removed"
        log_info "If you chose to keep the project, you may still have:"
        log_info "  - Enabled APIs (these don't incur charges)"
        log_info "  - IAM bindings (review and clean up if needed)"
        log_info "  - Any manually created resources"
        
        echo
        log_info "Destruction log saved to: ${LOG_FILE}"
    fi
}

# Run main function with all arguments
main "$@"