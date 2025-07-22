#!/bin/bash

# Cross-Cloud Data Migration with Storage Transfer Service and Cloud Composer - Cleanup Script
# This script removes all resources created for the cross-cloud data migration solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    warn "Running in DRY-RUN mode - no resources will be deleted"
    GCLOUD_CMD="echo [DRY-RUN] gcloud"
    GSUTIL_CMD="echo [DRY-RUN] gsutil"
else
    GCLOUD_CMD="gcloud"
    GSUTIL_CMD="gsutil"
fi

# Safety confirmation
confirm_destruction() {
    if [ "$DRY_RUN" != "true" ]; then
        echo ""
        warn "This will permanently delete all resources created for the cross-cloud data migration solution."
        warn "This action cannot be undone!"
        echo ""
        info "Resources that will be deleted:"
        info "- Cloud Composer environment: ${COMPOSER_ENV_NAME:-data-migration-env}"
        info "- Storage Transfer Service jobs"
        info "- Storage buckets and all data: ${STAGING_BUCKET:-migration-staging-*}, ${TARGET_BUCKET:-migration-target-*}"
        info "- Service accounts and IAM bindings"
        info "- Log sinks and monitoring policies"
        echo ""
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
        
        if [ "$confirmation" != "yes" ]; then
            info "Destruction cancelled by user"
            exit 0
        fi
    fi
}

# Load configuration from environment variables
load_configuration() {
    log "Loading configuration from environment variables..."
    
    # Try to get current project if not set
    if [ -z "${PROJECT_ID:-}" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "$PROJECT_ID" ]; then
            error "PROJECT_ID not set and cannot determine current project"
            exit 1
        fi
    fi
    
    # Set default values if not provided
    export REGION=${REGION:-"us-central1"}
    export COMPOSER_ENV_NAME=${COMPOSER_ENV_NAME:-"data-migration-env"}
    
    # Try to detect bucket names if not provided
    if [ -z "${STAGING_BUCKET:-}" ] || [ -z "${TARGET_BUCKET:-}" ]; then
        info "Bucket names not provided, attempting to detect them..."
        
        # List buckets with migration prefix
        MIGRATION_BUCKETS=$(gsutil ls -p ${PROJECT_ID} 2>/dev/null | grep -E "migration-(staging|target)-" || echo "")
        
        if [ -n "$MIGRATION_BUCKETS" ]; then
            info "Found migration buckets:"
            echo "$MIGRATION_BUCKETS"
            
            # Set bucket names if found
            STAGING_BUCKET=${STAGING_BUCKET:-$(echo "$MIGRATION_BUCKETS" | grep staging | head -1 | sed 's|gs://||' | sed 's|/||')}
            TARGET_BUCKET=${TARGET_BUCKET:-$(echo "$MIGRATION_BUCKETS" | grep target | head -1 | sed 's|gs://||' | sed 's|/||')}
        fi
    fi
    
    info "Configuration loaded:"
    info "  PROJECT_ID: $PROJECT_ID"
    info "  REGION: $REGION"
    info "  COMPOSER_ENV_NAME: $COMPOSER_ENV_NAME"
    info "  STAGING_BUCKET: ${STAGING_BUCKET:-not found}"
    info "  TARGET_BUCKET: ${TARGET_BUCKET:-not found}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is required but not installed"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is required but not installed"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Please authenticate with gcloud: gcloud auth login"
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Delete Cloud Composer environment
delete_composer_environment() {
    log "Deleting Cloud Composer environment..."
    
    # Check if environment exists
    if [ "$DRY_RUN" != "true" ]; then
        ENV_EXISTS=$(gcloud composer environments describe ${COMPOSER_ENV_NAME} \
            --location ${REGION} \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [ -n "$ENV_EXISTS" ]; then
            info "Deleting Composer environment: ${COMPOSER_ENV_NAME} (this takes 10-15 minutes)..."
            $GCLOUD_CMD composer environments delete ${COMPOSER_ENV_NAME} \
                --location ${REGION} \
                --quiet
            
            # Wait for deletion to complete
            info "Waiting for Composer environment deletion to complete..."
            while true; do
                ENV_STATUS=$(gcloud composer environments describe ${COMPOSER_ENV_NAME} \
                    --location ${REGION} \
                    --format="value(state)" 2>/dev/null || echo "DELETED")
                
                if [ "$ENV_STATUS" = "DELETED" ] || [ -z "$ENV_STATUS" ]; then
                    log "Composer environment deleted successfully"
                    break
                else
                    info "Composer environment state: $ENV_STATUS - waiting 30 seconds..."
                    sleep 30
                fi
            done
        else
            info "Composer environment ${COMPOSER_ENV_NAME} not found, skipping deletion"
        fi
    else
        info "Would delete Composer environment: ${COMPOSER_ENV_NAME}"
    fi
}

# Delete Storage Transfer Service jobs
delete_transfer_jobs() {
    log "Deleting Storage Transfer Service jobs..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Get list of transfer jobs
        TRANSFER_JOBS=$(gcloud transfer jobs list --format="value(name)" 2>/dev/null || echo "")
        
        if [ -n "$TRANSFER_JOBS" ]; then
            info "Found transfer jobs to delete:"
            echo "$TRANSFER_JOBS"
            
            # Disable and delete each job
            for job in $TRANSFER_JOBS; do
                info "Disabling transfer job: $job"
                $GCLOUD_CMD transfer jobs update $job --status=DISABLED --quiet || true
                
                # Note: Transfer jobs cannot be deleted, only disabled
                info "Transfer job $job has been disabled"
            done
        else
            info "No transfer jobs found to delete"
        fi
    else
        info "Would disable all Storage Transfer Service jobs"
    fi
}

# Delete Storage buckets
delete_storage_buckets() {
    log "Deleting Storage buckets..."
    
    # Delete staging bucket if it exists
    if [ -n "${STAGING_BUCKET:-}" ]; then
        info "Deleting staging bucket: gs://${STAGING_BUCKET}"
        
        if [ "$DRY_RUN" != "true" ]; then
            # Check if bucket exists
            if gsutil ls -b gs://${STAGING_BUCKET} &> /dev/null; then
                # Remove all objects first
                $GSUTIL_CMD -m rm -r gs://${STAGING_BUCKET}/* || true
                
                # Remove bucket
                $GSUTIL_CMD rb gs://${STAGING_BUCKET} || true
                log "Staging bucket deleted: gs://${STAGING_BUCKET}"
            else
                info "Staging bucket gs://${STAGING_BUCKET} not found, skipping"
            fi
        else
            info "Would delete staging bucket: gs://${STAGING_BUCKET}"
        fi
    fi
    
    # Delete target bucket if it exists
    if [ -n "${TARGET_BUCKET:-}" ]; then
        info "Deleting target bucket: gs://${TARGET_BUCKET}"
        
        if [ "$DRY_RUN" != "true" ]; then
            # Check if bucket exists
            if gsutil ls -b gs://${TARGET_BUCKET} &> /dev/null; then
                # Remove all objects first
                $GSUTIL_CMD -m rm -r gs://${TARGET_BUCKET}/* || true
                
                # Remove bucket
                $GSUTIL_CMD rb gs://${TARGET_BUCKET} || true
                log "Target bucket deleted: gs://${TARGET_BUCKET}"
            else
                info "Target bucket gs://${TARGET_BUCKET} not found, skipping"
            fi
        else
            info "Would delete target bucket: gs://${TARGET_BUCKET}"
        fi
    fi
}

# Delete service account and IAM bindings
delete_service_account() {
    log "Deleting service account and IAM bindings..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Get service account email
        TRANSFER_SA_EMAIL=$(gcloud iam service-accounts list \
            --filter="displayName:Storage Transfer Service Account" \
            --format="value(email)" 2>/dev/null || echo "")
        
        if [ -n "$TRANSFER_SA_EMAIL" ]; then
            info "Found service account: $TRANSFER_SA_EMAIL"
            
            # Remove IAM policy bindings
            info "Removing IAM policy bindings..."
            $GCLOUD_CMD projects remove-iam-policy-binding ${PROJECT_ID} \
                --member="serviceAccount:${TRANSFER_SA_EMAIL}" \
                --role="roles/storagetransfer.admin" \
                --quiet || true
            
            $GCLOUD_CMD projects remove-iam-policy-binding ${PROJECT_ID} \
                --member="serviceAccount:${TRANSFER_SA_EMAIL}" \
                --role="roles/storage.admin" \
                --quiet || true
            
            # Delete service account
            info "Deleting service account..."
            $GCLOUD_CMD iam service-accounts delete ${TRANSFER_SA_EMAIL} \
                --quiet || true
            
            log "Service account and IAM bindings removed"
        else
            info "Storage Transfer Service Account not found, skipping"
        fi
    else
        info "Would delete service account and IAM bindings"
    fi
}

# Delete logging sinks
delete_logging_sinks() {
    log "Deleting logging sinks..."
    
    local sinks=("storage-transfer-sink" "composer-migration-sink")
    
    for sink in "${sinks[@]}"; do
        if [ "$DRY_RUN" != "true" ]; then
            # Check if sink exists
            if gcloud logging sinks describe $sink &> /dev/null; then
                info "Deleting log sink: $sink"
                $GCLOUD_CMD logging sinks delete $sink --quiet || true
            else
                info "Log sink $sink not found, skipping"
            fi
        else
            info "Would delete log sink: $sink"
        fi
    done
    
    log "Logging sinks cleanup completed"
}

# Delete monitoring policies
delete_monitoring_policies() {
    log "Deleting monitoring policies..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Get monitoring policies related to storage transfer
        POLICIES=$(gcloud alpha monitoring policies list \
            --filter="displayName:Storage Transfer Job Failures" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [ -n "$POLICIES" ]; then
            info "Found monitoring policies to delete:"
            echo "$POLICIES"
            
            for policy in $POLICIES; do
                info "Deleting monitoring policy: $policy"
                $GCLOUD_CMD alpha monitoring policies delete $policy --quiet || true
            done
        else
            info "No monitoring policies found to delete"
        fi
    else
        info "Would delete monitoring policies"
    fi
    
    log "Monitoring policies cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files=("transfer-job-config.json" "migration_orchestrator.py" "alert-policy.json")
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            info "Removing local file: $file"
            rm -f "$file" || true
        fi
    done
    
    log "Local files cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Check for remaining resources
        info "Checking for remaining resources..."
        
        # Check Composer environments
        REMAINING_COMPOSER=$(gcloud composer environments list \
            --locations=${REGION} \
            --filter="name:${COMPOSER_ENV_NAME}" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [ -n "$REMAINING_COMPOSER" ]; then
            warn "Composer environment still exists: $REMAINING_COMPOSER"
        fi
        
        # Check buckets
        if [ -n "${STAGING_BUCKET:-}" ] && gsutil ls -b gs://${STAGING_BUCKET} &> /dev/null; then
            warn "Staging bucket still exists: gs://${STAGING_BUCKET}"
        fi
        
        if [ -n "${TARGET_BUCKET:-}" ] && gsutil ls -b gs://${TARGET_BUCKET} &> /dev/null; then
            warn "Target bucket still exists: gs://${TARGET_BUCKET}"
        fi
        
        # Check service accounts
        REMAINING_SA=$(gcloud iam service-accounts list \
            --filter="displayName:Storage Transfer Service Account" \
            --format="value(email)" 2>/dev/null || echo "")
        
        if [ -n "$REMAINING_SA" ]; then
            warn "Service account still exists: $REMAINING_SA"
        fi
        
        log "Cleanup verification completed"
    else
        info "Skipping cleanup verification in dry-run mode"
    fi
}

# Main cleanup function
main() {
    log "Starting cleanup of Cross-Cloud Data Migration infrastructure..."
    
    # Check prerequisites
    check_prerequisites
    
    # Load configuration
    load_configuration
    
    # Confirm destruction
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_monitoring_policies
    delete_logging_sinks
    delete_transfer_jobs
    delete_composer_environment
    delete_service_account
    delete_storage_buckets
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    log "Cleanup completed successfully!"
    
    # Print summary
    info "=== CLEANUP SUMMARY ==="
    info "All resources for the Cross-Cloud Data Migration solution have been removed."
    info "Project: $PROJECT_ID"
    info "Region: $REGION"
    info ""
    info "If you see any warnings above, please verify those resources manually."
    info "Some resources may take additional time to be fully removed from the Google Cloud Console."
    info ""
    log "Thank you for using the Cross-Cloud Data Migration solution!"
}

# Handle script interruption
trap 'error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"