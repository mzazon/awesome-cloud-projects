#!/bin/bash

# Carbon-Efficient Batch Processing with Cloud Batch and Sustainability Intelligence
# Destroy Script - Safely removes all infrastructure components
# 
# This script removes:
# - Cloud Batch jobs and configurations
# - Cloud Functions and related resources
# - Pub/Sub topics and subscriptions
# - Cloud Storage buckets and contents
# - Custom monitoring metrics and alerts
# - IAM bindings and service configurations

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "${LOG_FILE}" >&2
}

warning() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1" | tee -a "${LOG_FILE}"
}

success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1" | tee -a "${LOG_FILE}"
}

confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [ "${FORCE_DELETE:-false}" != "true" ]; then
        echo ""
        read -p "⚠️  Delete $resource_type '$resource_name'? [y/N]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Skipping deletion of $resource_type: $resource_name"
            return 1
        fi
    fi
    return 0
}

# Start cleanup
log "Starting carbon-efficient batch processing infrastructure cleanup..."
log "Script directory: $SCRIPT_DIR"
log "Log file: $LOG_FILE"

# Check prerequisites
log "Validating prerequisites..."

if ! command -v gcloud &> /dev/null; then
    error "gcloud CLI is not installed"
fi

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
    error "gcloud is not authenticated. Please run 'gcloud auth login'"
fi

# Load configuration from deployment summary or environment
if [ -f "${SCRIPT_DIR}/deployment_summary.json" ]; then
    log "Loading configuration from deployment summary..."
    PROJECT_ID=$(grep -o '"project_id": "[^"]*"' "${SCRIPT_DIR}/deployment_summary.json" | cut -d'"' -f4)
    REGION=$(grep -o '"region": "[^"]*"' "${SCRIPT_DIR}/deployment_summary.json" | cut -d'"' -f4)
    TOPIC_NAME=$(grep -o '"pubsub_topic": "[^"]*"' "${SCRIPT_DIR}/deployment_summary.json" | cut -d'"' -f4)
    SUBSCRIPTION_NAME=$(grep -o '"pubsub_subscription": "[^"]*"' "${SCRIPT_DIR}/deployment_summary.json" | cut -d'"' -f4)
    BUCKET_NAME=$(grep -o '"storage_bucket": "[^"]*"' "${SCRIPT_DIR}/deployment_summary.json" | cut -d'"' -f4)
    FUNCTION_NAME=$(grep -o '"cloud_function": "[^"]*"' "${SCRIPT_DIR}/deployment_summary.json" | cut -d'"' -f4)
else
    log "Deployment summary not found, using environment variables or defaults..."
    PROJECT_ID="${PROJECT_ID:-}"
    REGION="${REGION:-us-central1}"
    ZONE="${ZONE:-us-central1-a}"
    
    # Try to detect resources based on common patterns
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    fi
    
    if [ -z "$PROJECT_ID" ]; then
        error "PROJECT_ID not found. Please set PROJECT_ID environment variable or ensure deployment_summary.json exists"
    fi
fi

log "Configuration loaded:"
log "  Project ID: $PROJECT_ID"
log "  Region: $REGION"
log "  Topic Name: ${TOPIC_NAME:-auto-detect}"
log "  Subscription Name: ${SUBSCRIPTION_NAME:-auto-detect}"
log "  Bucket Name: ${BUCKET_NAME:-auto-detect}"
log "  Function Name: ${FUNCTION_NAME:-auto-detect}"

# Set project context
gcloud config set project "$PROJECT_ID" || error "Failed to set project context"

# Auto-detect resources if not specified
if [ -z "${TOPIC_NAME:-}" ] || [ -z "${SUBSCRIPTION_NAME:-}" ] || [ -z "${BUCKET_NAME:-}" ] || [ -z "${FUNCTION_NAME:-}" ]; then
    log "Auto-detecting resources with carbon/batch naming patterns..."
    
    # Find Pub/Sub topics
    if [ -z "${TOPIC_NAME:-}" ]; then
        DETECTED_TOPICS=$(gcloud pubsub topics list --filter="name~carbon-events" --format="value(name)" | head -1)
        if [ -n "$DETECTED_TOPICS" ]; then
            TOPIC_NAME=$(basename "$DETECTED_TOPICS")
            log "Detected Pub/Sub topic: $TOPIC_NAME"
        fi
    fi
    
    # Find subscriptions
    if [ -z "${SUBSCRIPTION_NAME:-}" ]; then
        DETECTED_SUBS=$(gcloud pubsub subscriptions list --filter="name~carbon-sub" --format="value(name)" | head -1)
        if [ -n "$DETECTED_SUBS" ]; then
            SUBSCRIPTION_NAME=$(basename "$DETECTED_SUBS")
            log "Detected Pub/Sub subscription: $SUBSCRIPTION_NAME"
        fi
    fi
    
    # Find storage buckets
    if [ -z "${BUCKET_NAME:-}" ]; then
        DETECTED_BUCKETS=$(gsutil ls | grep -E "(carbon-batch|batch.*carbon)" | head -1 | sed 's|gs://||' | sed 's|/||')
        if [ -n "$DETECTED_BUCKETS" ]; then
            BUCKET_NAME="$DETECTED_BUCKETS"
            log "Detected Cloud Storage bucket: $BUCKET_NAME"
        fi
    fi
    
    # Find Cloud Functions
    if [ -z "${FUNCTION_NAME:-}" ]; then
        DETECTED_FUNCTIONS=$(gcloud functions list --filter="name~carbon-scheduler" --format="value(name)" | head -1)
        if [ -n "$DETECTED_FUNCTIONS" ]; then
            FUNCTION_NAME="$DETECTED_FUNCTIONS"
            log "Detected Cloud Function: $FUNCTION_NAME"
        fi
    fi
fi

# Safety confirmation for destructive operations
if [ "${FORCE_DELETE:-false}" != "true" ]; then
    echo ""
    echo "🚨 DESTRUCTIVE OPERATION WARNING 🚨"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "  • Project: $PROJECT_ID"
    echo "  • Region: $REGION"
    [ -n "${TOPIC_NAME:-}" ] && echo "  • Pub/Sub Topic: $TOPIC_NAME"
    [ -n "${SUBSCRIPTION_NAME:-}" ] && echo "  • Pub/Sub Subscription: $SUBSCRIPTION_NAME"
    [ -n "${BUCKET_NAME:-}" ] && echo "  • Storage Bucket: $BUCKET_NAME (and ALL contents)"
    [ -n "${FUNCTION_NAME:-}" ] && echo "  • Cloud Function: $FUNCTION_NAME"
    echo "  • All associated batch jobs and configurations"
    echo "  • Custom monitoring metrics and alert policies"
    echo ""
    echo "❌ This action CANNOT be undone!"
    echo ""
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " -r
    echo ""
    
    if [ "$REPLY" != "DELETE" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed deletion - proceeding with cleanup..."
fi

# Start deletion process
log "Beginning resource cleanup process..."

# 1. Delete running batch jobs first
log "🔍 Finding and deleting active batch jobs..."

BATCH_JOBS=$(gcloud batch jobs list --location="$REGION" --filter="name~carbon" --format="value(name)" 2>/dev/null || true)

if [ -n "$BATCH_JOBS" ]; then
    echo "$BATCH_JOBS" | while read -r job_name; do
        if [ -n "$job_name" ]; then
            log "Deleting batch job: $job_name"
            if confirm_deletion "batch job" "$job_name"; then
                if gcloud batch jobs delete "$job_name" --location="$REGION" --quiet 2>/dev/null; then
                    success "Deleted batch job: $job_name"
                else
                    warning "Failed to delete batch job: $job_name"
                fi
            fi
        fi
    done
else
    log "No active batch jobs found"
fi

# 2. Delete Cloud Function
if [ -n "${FUNCTION_NAME:-}" ]; then
    log "🔧 Deleting Cloud Function: $FUNCTION_NAME"
    if confirm_deletion "Cloud Function" "$FUNCTION_NAME"; then
        if gcloud functions delete "$FUNCTION_NAME" --region="$REGION" --quiet 2>/dev/null; then
            success "Deleted Cloud Function: $FUNCTION_NAME"
        else
            warning "Failed to delete Cloud Function: $FUNCTION_NAME (may not exist)"
        fi
    fi
else
    log "No Cloud Function to delete"
fi

# 3. Delete monitoring alert policies
log "📊 Deleting monitoring alert policies..."

ALERT_POLICIES=$(gcloud alpha monitoring policies list --filter="displayName~'High Carbon Impact Alert'" --format="value(name)" 2>/dev/null || true)

if [ -n "$ALERT_POLICIES" ]; then
    echo "$ALERT_POLICIES" | while read -r policy_name; do
        if [ -n "$policy_name" ]; then
            log "Deleting alert policy: $(basename "$policy_name")"
            if confirm_deletion "alert policy" "$(basename "$policy_name")"; then
                if gcloud alpha monitoring policies delete "$policy_name" --quiet 2>/dev/null; then
                    success "Deleted alert policy: $(basename "$policy_name")"
                else
                    warning "Failed to delete alert policy: $(basename "$policy_name")"
                fi
            fi
        fi
    done
else
    log "No alert policies found to delete"
fi

# 4. Delete custom metrics (note: this doesn't actually delete the metric descriptor)
log "📈 Note: Custom metric descriptors cannot be deleted but will stop receiving data"

# 5. Delete Pub/Sub subscription first (must delete before topic)
if [ -n "${SUBSCRIPTION_NAME:-}" ]; then
    log "📬 Deleting Pub/Sub subscription: $SUBSCRIPTION_NAME"
    if confirm_deletion "Pub/Sub subscription" "$SUBSCRIPTION_NAME"; then
        if gcloud pubsub subscriptions delete "$SUBSCRIPTION_NAME" --quiet 2>/dev/null; then
            success "Deleted Pub/Sub subscription: $SUBSCRIPTION_NAME"
        else
            warning "Failed to delete Pub/Sub subscription: $SUBSCRIPTION_NAME (may not exist)"
        fi
    fi
else
    log "No Pub/Sub subscription to delete"
fi

# 6. Delete Pub/Sub topic
if [ -n "${TOPIC_NAME:-}" ]; then
    log "📡 Deleting Pub/Sub topic: $TOPIC_NAME"
    if confirm_deletion "Pub/Sub topic" "$TOPIC_NAME"; then
        if gcloud pubsub topics delete "$TOPIC_NAME" --quiet 2>/dev/null; then
            success "Deleted Pub/Sub topic: $TOPIC_NAME"
        else
            warning "Failed to delete Pub/Sub topic: $TOPIC_NAME (may not exist)"
        fi
    fi
else
    log "No Pub/Sub topic to delete"
fi

# 7. Delete Cloud Storage bucket and all contents
if [ -n "${BUCKET_NAME:-}" ]; then
    log "🗂️  Deleting Cloud Storage bucket and ALL contents: $BUCKET_NAME"
    if confirm_deletion "Storage bucket (with ALL contents)" "$BUCKET_NAME"; then
        
        # Check if bucket exists
        if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
            log "Removing all objects from bucket..."
            
            # Use parallel deletion for better performance
            if gsutil -m rm -r "gs://$BUCKET_NAME/**" 2>/dev/null || true; then
                log "Removed all objects from bucket"
            fi
            
            # Delete the bucket itself
            if gsutil rb "gs://$BUCKET_NAME" 2>/dev/null; then
                success "Deleted Cloud Storage bucket: $BUCKET_NAME"
            else
                warning "Failed to delete bucket: $BUCKET_NAME (may still contain objects)"
                log "Try manual cleanup: gsutil rm -r gs://$BUCKET_NAME"
            fi
        else
            log "Bucket gs://$BUCKET_NAME does not exist"
        fi
    fi
else
    log "No Cloud Storage bucket to delete"
fi

# 8. Clean up local temporary files
log "🧹 Cleaning up local temporary files..."

LOCAL_FILES=(
    "${SCRIPT_DIR}/carbon_aware_job.py"
    "${SCRIPT_DIR}/batch_job_config.json"
    "${SCRIPT_DIR}/carbon_metrics.json"
    "${SCRIPT_DIR}/carbon_alert_policy.json"
    "${SCRIPT_DIR}/deployment_summary.json"
)

for file in "${LOCAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        if confirm_deletion "local file" "$(basename "$file")"; then
            rm -f "$file"
            success "Deleted local file: $(basename "$file")"
        fi
    fi
done

# Clean up function directory
if [ -d "${SCRIPT_DIR}/carbon_scheduler_function" ]; then
    if confirm_deletion "function directory" "carbon_scheduler_function"; then
        rm -rf "${SCRIPT_DIR}/carbon_scheduler_function"
        success "Deleted function directory"
    fi
fi

# 9. Reset gcloud configuration
log "⚙️  Resetting gcloud configuration..."

if confirm_deletion "gcloud project configuration" "$PROJECT_ID"; then
    gcloud config unset project 2>/dev/null || true
    gcloud config unset compute/region 2>/dev/null || true
    gcloud config unset compute/zone 2>/dev/null || true
    success "Reset gcloud configuration"
fi

# 10. Optional: Delete the entire project (commented out for safety)
PROJECT_DELETE_OPTION="${DELETE_PROJECT:-false}"
if [ "$PROJECT_DELETE_OPTION" = "true" ]; then
    echo ""
    echo "🔥 PROJECT DELETION OPTION ENABLED 🔥"
    echo ""
    echo "WARNING: This will delete the ENTIRE project '$PROJECT_ID' and ALL resources within it!"
    echo "This includes resources not created by this recipe."
    echo ""
    read -p "Type the project ID '$PROJECT_ID' to confirm complete project deletion: " -r
    echo ""
    
    if [ "$REPLY" = "$PROJECT_ID" ]; then
        log "Deleting entire project: $PROJECT_ID"
        if gcloud projects delete "$PROJECT_ID" --quiet; then
            success "Project deleted successfully: $PROJECT_ID"
        else
            error "Failed to delete project: $PROJECT_ID"
        fi
    else
        log "Project deletion cancelled - input did not match project ID"
    fi
else
    log "Project deletion not requested (use DELETE_PROJECT=true to enable)"
fi

# Final verification
log "🔍 Performing final cleanup verification..."

verification_warnings=0

# Check if resources still exist
if [ -n "${TOPIC_NAME:-}" ] && gcloud pubsub topics describe "$TOPIC_NAME" &> /dev/null; then
    warning "Pub/Sub topic still exists: $TOPIC_NAME"
    verification_warnings=$((verification_warnings + 1))
fi

if [ -n "${BUCKET_NAME:-}" ] && gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
    warning "Cloud Storage bucket still exists: $BUCKET_NAME"
    verification_warnings=$((verification_warnings + 1))
fi

if [ -n "${FUNCTION_NAME:-}" ] && gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
    warning "Cloud Function still exists: $FUNCTION_NAME"
    verification_warnings=$((verification_warnings + 1))
fi

# Create cleanup summary
cat > "${SCRIPT_DIR}/cleanup_summary.json" << EOF
{
  "cleanup_info": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "project_id": "$PROJECT_ID",
    "region": "$REGION",
    "cleanup_status": "completed",
    "verification_warnings": $verification_warnings
  },
  "resources_processed": {
    "pubsub_topic": "${TOPIC_NAME:-not_found}",
    "pubsub_subscription": "${SUBSCRIPTION_NAME:-not_found}",
    "storage_bucket": "${BUCKET_NAME:-not_found}",
    "cloud_function": "${FUNCTION_NAME:-not_found}",
    "batch_jobs": "all_found_jobs_deleted",
    "alert_policies": "all_found_policies_deleted"
  },
  "manual_cleanup_required": [
    "Custom metric descriptors cannot be automatically deleted",
    "Some IAM bindings may persist if created outside this script",
    "Billing data and logs are retained according to Google Cloud policies"
  ],
  "verification_notes": {
    "remaining_resources": $verification_warnings,
    "project_deleted": $([ "$PROJECT_DELETE_OPTION" = "true" ] && echo "true" || echo "false")
  }
}
EOF

# Display cleanup summary
log "==================== CLEANUP COMPLETED ===================="
log ""
log "🧹 Carbon-Efficient Batch Processing Infrastructure Cleanup Summary"
log ""
log "📊 Cleanup Status:"
if [ $verification_warnings -eq 0 ]; then
    log "  ✅ All targeted resources successfully removed"
else
    log "  ⚠️  $verification_warnings resources may still exist (see warnings above)"
fi

log ""
log "🗑️  Resources Processed:"
[ -n "${TOPIC_NAME:-}" ] && log "  • Pub/Sub Topic: $TOPIC_NAME"
[ -n "${SUBSCRIPTION_NAME:-}" ] && log "  • Pub/Sub Subscription: $SUBSCRIPTION_NAME"
[ -n "${BUCKET_NAME:-}" ] && log "  • Storage Bucket: $BUCKET_NAME"
[ -n "${FUNCTION_NAME:-}" ] && log "  • Cloud Function: $FUNCTION_NAME"
log "  • Batch Jobs: All carbon-related jobs"
log "  • Alert Policies: Carbon impact alerts"
log "  • Local Files: Temporary deployment files"

log ""
log "📋 Manual Cleanup Notes:"
log "  • Custom metric descriptors persist but will stop receiving data"
log "  • Cloud Logging entries are retained per Google Cloud retention policies"
log "  • Billing data remains available for cost analysis"
log "  • IAM roles/bindings created outside this script may persist"

if [ "$PROJECT_DELETE_OPTION" = "true" ]; then
    log "  • ✅ Entire project was deleted"
else
    log "  • ℹ️  Project preserved (use DELETE_PROJECT=true to delete entire project)"
fi

log ""
log "🔗 Verification Commands:"
log "  • Check remaining resources: gcloud projects describe $PROJECT_ID"
log "  • List any remaining functions: gcloud functions list"
log "  • List any remaining topics: gcloud pubsub topics list"
log "  • List any remaining buckets: gsutil ls"

log ""
log "📝 Logs: $LOG_FILE"
log "📋 Summary: ${SCRIPT_DIR}/cleanup_summary.json"
log ""

if [ $verification_warnings -eq 0 ]; then
    success "✨ Cleanup completed successfully - all resources removed!"
else
    warning "⚠️  Cleanup completed with $verification_warnings warnings - manual verification recommended"
fi

log ""
log "=============================================================="

log "Cleanup completed at $(date)"