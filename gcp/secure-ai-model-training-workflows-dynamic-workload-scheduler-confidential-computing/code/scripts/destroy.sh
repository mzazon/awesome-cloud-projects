#!/bin/bash

# Secure AI Model Training Workflows with Dynamic Workload Scheduler and Confidential Computing
# Cleanup Script for GCP Infrastructure
# 
# This script safely removes all resources created for secure AI model training
# infrastructure on Google Cloud Platform.

set -euo pipefail

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/secure-ai-training-cleanup-$(date +%Y%m%d-%H%M%S).log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

log_warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $*${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    echo -e "${RED}Cleanup failed. Check log file: $LOG_FILE${NC}"
    exit 1
}

# Display usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Safely remove secure AI model training infrastructure from Google Cloud Platform.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           GCP region (default: us-central1)
    -z, --zone ZONE              GCP zone (default: us-central1-a)
    -f, --force                  Skip confirmation prompts (default: false)
    -d, --dry-run                Show what would be deleted without executing
    -v, --verbose                Enable verbose logging
    -k, --keep-data              Keep training data bucket (default: false)
    -h, --help                   Show this help message

EXAMPLES:
    $SCRIPT_NAME --project-id my-secure-ai-project
    $SCRIPT_NAME -p my-project -f
    $SCRIPT_NAME --project-id my-project --dry-run
    $SCRIPT_NAME -p my-project --keep-data

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT         Alternative way to specify project ID
    GCP_REGION                   Alternative way to specify region
    GCP_ZONE                     Alternative way to specify zone

WARNING:
    This script will permanently delete resources and data.
    Use --dry-run first to review what will be deleted.

EOF
}

# Default values
PROJECT_ID=""
REGION="us-central1"
ZONE="us-central1-a"
FORCE=false
DRY_RUN=false
VERBOSE=false
KEEP_DATA=false

# Parse command line arguments
parse_args() {
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
                FORCE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -k|--keep-data)
                KEEP_DATA=true
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

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi
    
    # Check if project ID is provided
    if [[ -z "$PROJECT_ID" ]]; then
        if [[ -n "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
            PROJECT_ID="$GOOGLE_CLOUD_PROJECT"
            log "Using project ID from environment variable: $PROJECT_ID"
        else
            error_exit "Project ID is required. Use --project-id option or set GOOGLE_CLOUD_PROJECT environment variable."
        fi
    fi
    
    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error_exit "Project '$PROJECT_ID' does not exist or is not accessible."
    fi
    
    # Set gcloud configuration
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    log_success "Prerequisites validation completed"
}

# Confirm deletion with user
confirm_deletion() {
    if [[ "$FORCE" == true ]] || [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}WARNING: This will permanently delete the following resources:${NC}"
    echo "  - Confidential Computing VM and instance templates"
    echo "  - Compute reservations for Dynamic Workload Scheduler"
    echo "  - Service accounts and IAM bindings"
    echo "  - Monitoring policies and audit logging sinks"
    if [[ "$KEEP_DATA" == false ]]; then
        echo "  - Cloud Storage bucket with training data"
        echo "  - Cloud KMS keys and keyrings"
    else
        echo "  - Cloud KMS keys will be scheduled for destruction (kept: storage bucket)"
    fi
    echo ""
    echo "Project: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
    
    log "User confirmed deletion"
}

# Stop and cancel running training jobs
stop_training_jobs() {
    log "Stopping running Vertex AI training jobs..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would cancel any running Vertex AI training jobs"
        return 0
    fi
    
    # List and cancel running custom jobs
    local running_jobs
    running_jobs=$(gcloud ai custom-jobs list --region="$REGION" --filter="state:JOB_STATE_RUNNING" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$running_jobs" ]]; then
        while IFS= read -r job_id; do
            if [[ -n "$job_id" ]]; then
                log "Cancelling training job: $job_id"
                if gcloud ai custom-jobs cancel "$job_id" --region="$REGION" --quiet; then
                    log "✅ Cancelled job: $job_id"
                else
                    log_warning "Failed to cancel job: $job_id"
                fi
            fi
        done <<< "$running_jobs"
    else
        log "No running training jobs found"
    fi
    
    log_success "Training jobs stopped"
}

# Delete confidential computing resources
delete_confidential_resources() {
    log "Deleting confidential computing resources..."
    
    # Delete confidential VM instances
    log "Deleting confidential VM instances..."
    local vms
    vms=$(gcloud compute instances list --zones="$ZONE" --filter="name:confidential-training-vm" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$vms" ]]; then
        while IFS= read -r vm_name; do
            if [[ -n "$vm_name" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    log "[DRY-RUN] Would delete VM: $vm_name"
                else
                    log "Deleting VM: $vm_name"
                    if gcloud compute instances delete "$vm_name" --zone="$ZONE" --quiet; then
                        log "✅ Deleted VM: $vm_name"
                    else
                        log_warning "Failed to delete VM: $vm_name"
                    fi
                fi
            fi
        done <<< "$vms"
    else
        log "No confidential VMs found"
    fi
    
    # Delete instance templates
    log "Deleting instance templates..."
    local templates
    templates=$(gcloud compute instance-templates list --filter="name:confidential-training-template" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$templates" ]]; then
        while IFS= read -r template_name; do
            if [[ -n "$template_name" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    log "[DRY-RUN] Would delete template: $template_name"
                else
                    log "Deleting template: $template_name"
                    if gcloud compute instance-templates delete "$template_name" --quiet; then
                        log "✅ Deleted template: $template_name"
                    else
                        log_warning "Failed to delete template: $template_name"
                    fi
                fi
            fi
        done <<< "$templates"
    else
        log "No instance templates found"
    fi
    
    log_success "Confidential computing resources cleaned up"
}

# Delete Dynamic Workload Scheduler reservations
delete_workload_scheduler_resources() {
    log "Deleting Dynamic Workload Scheduler resources..."
    
    # Delete compute reservations
    log "Deleting compute reservations..."
    local reservations
    reservations=$(gcloud compute reservations list --zones="$ZONE" --filter="name:secure-ai-training-reservation" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$reservations" ]]; then
        while IFS= read -r reservation_name; do
            if [[ -n "$reservation_name" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    log "[DRY-RUN] Would delete reservation: $reservation_name"
                else
                    log "Deleting reservation: $reservation_name"
                    if gcloud compute reservations delete "$reservation_name" --zone="$ZONE" --quiet; then
                        log "✅ Deleted reservation: $reservation_name"
                    else
                        log_warning "Failed to delete reservation: $reservation_name"
                    fi
                fi
            fi
        done <<< "$reservations"
    else
        log "No compute reservations found"
    fi
    
    log_success "Dynamic Workload Scheduler resources cleaned up"
}

# Delete service accounts and IAM bindings
delete_service_accounts() {
    log "Deleting service accounts and IAM bindings..."
    
    local service_accounts
    service_accounts=$(gcloud iam service-accounts list --filter="email:ai-training-sa@${PROJECT_ID}.iam.gserviceaccount.com" --format="value(email)" 2>/dev/null || echo "")
    
    if [[ -n "$service_accounts" ]]; then
        while IFS= read -r sa_email; do
            if [[ -n "$sa_email" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    log "[DRY-RUN] Would delete service account: $sa_email"
                else
                    log "Removing IAM policy bindings for: $sa_email"
                    
                    # Remove IAM role bindings
                    local roles=(
                        "roles/aiplatform.user"
                        "roles/storage.objectAdmin"
                        "roles/cloudkms.cryptoKeyEncrypterDecrypter"
                        "roles/confidentialcomputing.workloadUser"
                        "roles/compute.instanceAdmin.v1"
                    )
                    
                    for role in "${roles[@]}"; do
                        if gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                            --member="serviceAccount:$sa_email" \
                            --role="$role" \
                            --quiet 2>/dev/null; then
                            log "✅ Removed role: $role"
                        else
                            log_warning "Failed to remove role: $role (may not exist)"
                        fi
                    done
                    
                    # Delete service account
                    log "Deleting service account: $sa_email"
                    if gcloud iam service-accounts delete "$sa_email" --quiet; then
                        log "✅ Deleted service account: $sa_email"
                    else
                        log_warning "Failed to delete service account: $sa_email"
                    fi
                fi
            fi
        done <<< "$service_accounts"
    else
        log "No AI training service accounts found"
    fi
    
    log_success "Service accounts cleaned up"
}

# Delete monitoring and logging resources
delete_monitoring_resources() {
    log "Deleting monitoring and logging resources..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY-RUN] Would delete monitoring policies and logging sinks"
        return 0
    fi
    
    # Delete monitoring policies
    log "Deleting monitoring policies..."
    local policies
    policies=$(gcloud alpha monitoring policies list --filter="displayName:'Confidential Training Security Policy'" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$policies" ]]; then
        while IFS= read -r policy_name; do
            if [[ -n "$policy_name" ]]; then
                log "Deleting monitoring policy: $policy_name"
                if gcloud alpha monitoring policies delete "$policy_name" --quiet 2>/dev/null; then
                    log "✅ Deleted monitoring policy"
                else
                    log_warning "Failed to delete monitoring policy (may require alpha components)"
                fi
            fi
        done <<< "$policies"
    else
        log "No monitoring policies found"
    fi
    
    # Delete logging sinks
    log "Deleting logging sinks..."
    local sinks
    sinks=$(gcloud logging sinks list --filter="name:confidential-training-audit" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$sinks" ]]; then
        while IFS= read -r sink_name; do
            if [[ -n "$sink_name" ]]; then
                log "Deleting logging sink: $sink_name"
                if gcloud logging sinks delete "$sink_name" --quiet; then
                    log "✅ Deleted logging sink: $sink_name"
                else
                    log_warning "Failed to delete logging sink: $sink_name"
                fi
            fi
        done <<< "$sinks"
    else
        log "No logging sinks found"
    fi
    
    log_success "Monitoring and logging resources cleaned up"
}

# Delete Cloud Storage buckets
delete_storage_resources() {
    if [[ "$KEEP_DATA" == true ]]; then
        log "Skipping storage deletion (--keep-data specified)"
        return 0
    fi
    
    log "Deleting Cloud Storage resources..."
    
    # Find training data buckets
    local buckets
    buckets=$(gsutil ls | grep -E "gs://secure-training-data-[a-f0-9]{6}/" | sed 's|gs://||g' | sed 's|/||g' 2>/dev/null || echo "")
    
    if [[ -n "$buckets" ]]; then
        while IFS= read -r bucket_name; do
            if [[ -n "$bucket_name" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    log "[DRY-RUN] Would delete bucket: gs://$bucket_name"
                else
                    log "Deleting bucket: gs://$bucket_name"
                    # Remove all objects and versions first
                    if gsutil -m rm -r "gs://$bucket_name/**" 2>/dev/null || true; then
                        log "Removed bucket contents"
                    fi
                    
                    # Delete the bucket
                    if gsutil rb "gs://$bucket_name"; then
                        log "✅ Deleted bucket: gs://$bucket_name"
                    else
                        log_warning "Failed to delete bucket: gs://$bucket_name"
                    fi
                fi
            fi
        done <<< "$buckets"
    else
        log "No training data buckets found"
    fi
    
    log_success "Storage resources cleaned up"
}

# Delete Cloud KMS resources
delete_kms_resources() {
    if [[ "$KEEP_DATA" == true ]]; then
        log "Keeping KMS resources (--keep-data specified)"
        return 0
    fi
    
    log "Deleting Cloud KMS resources..."
    
    # Find KMS keyrings
    local keyrings
    keyrings=$(gcloud kms keyrings list --location="$REGION" --filter="name:ai-training-keyring-*" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$keyrings" ]]; then
        while IFS= read -r keyring_path; do
            if [[ -n "$keyring_path" ]]; then
                local keyring_name
                keyring_name=$(basename "$keyring_path")
                
                if [[ "$DRY_RUN" == true ]]; then
                    log "[DRY-RUN] Would schedule KMS keys for destruction in keyring: $keyring_name"
                else
                    log "Processing KMS keyring: $keyring_name"
                    
                    # List and schedule keys for destruction
                    local keys
                    keys=$(gcloud kms keys list --location="$REGION" --keyring="$keyring_name" --format="value(name)" 2>/dev/null || echo "")
                    
                    if [[ -n "$keys" ]]; then
                        while IFS= read -r key_path; do
                            if [[ -n "$key_path" ]]; then
                                local key_name
                                key_name=$(basename "$key_path")
                                
                                log "Scheduling key for destruction: $key_name"
                                
                                # Get the primary version
                                local primary_version
                                primary_version=$(gcloud kms keys describe "$key_name" --location="$REGION" --keyring="$keyring_name" --format="value(primary.name)" 2>/dev/null || echo "")
                                
                                if [[ -n "$primary_version" ]]; then
                                    local version_number
                                    version_number=$(basename "$primary_version")
                                    
                                    if gcloud kms keys versions destroy "$version_number" \
                                        --key="$key_name" \
                                        --location="$REGION" \
                                        --keyring="$keyring_name" \
                                        --quiet 2>/dev/null; then
                                        log "✅ Scheduled key version for destruction: $key_name/$version_number"
                                    else
                                        log_warning "Failed to schedule key version for destruction: $key_name/$version_number"
                                    fi
                                fi
                            fi
                        done <<< "$keys"
                    fi
                    
                    log "✅ Processed keyring: $keyring_name"
                fi
            fi
        done <<< "$keyrings"
    else
        log "No KMS keyrings found"
    fi
    
    if [[ "$DRY_RUN" == false ]]; then
        log "Note: KMS keys are scheduled for destruction but keyrings cannot be deleted"
        log "Keyrings will remain but are not charged after key destruction"
    fi
    
    log_success "KMS resources processed"
}

# Verify deletion
verify_cleanup() {
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    
    log "Verifying resource cleanup..."
    
    local remaining_resources=0
    
    # Check for remaining VMs
    local vms
    vms=$(gcloud compute instances list --zones="$ZONE" --filter="name:confidential-training-vm" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$vms" ]]; then
        log_warning "Remaining VMs found: $vms"
        ((remaining_resources++))
    fi
    
    # Check for remaining templates
    local templates
    templates=$(gcloud compute instance-templates list --filter="name:confidential-training-template" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$templates" ]]; then
        log_warning "Remaining templates found: $templates"
        ((remaining_resources++))
    fi
    
    # Check for remaining reservations
    local reservations
    reservations=$(gcloud compute reservations list --zones="$ZONE" --filter="name:secure-ai-training-reservation" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$reservations" ]]; then
        log_warning "Remaining reservations found: $reservations"
        ((remaining_resources++))
    fi
    
    # Check for remaining service accounts
    local service_accounts
    service_accounts=$(gcloud iam service-accounts list --filter="email:ai-training-sa@${PROJECT_ID}.iam.gserviceaccount.com" --format="value(email)" 2>/dev/null || echo "")
    if [[ -n "$service_accounts" ]]; then
        log_warning "Remaining service accounts found: $service_accounts"
        ((remaining_resources++))
    fi
    
    if [[ "$KEEP_DATA" == false ]]; then
        # Check for remaining buckets
        local buckets
        buckets=$(gsutil ls | grep -E "gs://secure-training-data-[a-f0-9]{6}/" 2>/dev/null || echo "")
        if [[ -n "$buckets" ]]; then
            log_warning "Remaining buckets found: $buckets"
            ((remaining_resources++))
        fi
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log_success "All resources cleaned up successfully"
    else
        log_warning "$remaining_resources resource types may not have been fully cleaned up"
        log_warning "Manual verification recommended"
    fi
}

# Execute cleanup
execute_cleanup() {
    log "Starting secure AI model training infrastructure cleanup..."
    
    # Cleanup steps in dependency order
    stop_training_jobs
    delete_confidential_resources
    delete_workload_scheduler_resources
    delete_monitoring_resources
    delete_service_accounts
    delete_storage_resources
    delete_kms_resources
    verify_cleanup
    
    if [[ "$DRY_RUN" == true ]]; then
        log_success "Dry-run completed successfully. No resources were deleted."
        return 0
    fi
    
    # Display cleanup summary
    echo ""
    echo "======================================"
    echo "CLEANUP SUMMARY"
    echo "======================================"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    if [[ "$KEEP_DATA" == true ]]; then
        echo "Data preserved: Training buckets and KMS keys retained"
    else
        echo "Data deleted: All training data and encryption keys removed"
    fi
    echo "Log File: $LOG_FILE"
    echo ""
    echo "Next Steps:"
    echo "1. Verify no unexpected charges in Cloud Billing Console"
    echo "2. Review the log file for any warnings or failed deletions"
    if [[ "$KEEP_DATA" == false ]]; then
        echo "3. Note: KMS keys are scheduled for destruction (30-day recovery period)"
    fi
    echo "======================================"
    
    log_success "Secure AI model training infrastructure cleanup completed"
}

# Main execution
main() {
    echo -e "${BLUE}Secure AI Model Training Infrastructure Cleanup${NC}"
    echo "Starting cleanup on $(date)"
    echo "Log file: $LOG_FILE"
    echo ""
    
    parse_args "$@"
    validate_prerequisites
    confirm_deletion
    execute_cleanup
    
    echo ""
    echo -e "${GREEN}Cleanup completed successfully!${NC}"
    exit 0
}

# Execute main function with all arguments
main "$@"