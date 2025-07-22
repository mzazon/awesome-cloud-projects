#!/bin/bash

# Database Fleet Governance Cleanup Script
# Recipe: Centralized Database Fleet Governance with Database Center and Cloud Asset Inventory
# Provider: Google Cloud Platform

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$ERROR_LOG" >&2)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling
handle_error() {
    log_error "An error occurred during cleanup. Check $ERROR_LOG for details."
    log_warning "Some resources may not have been deleted. Please review manually."
}

# Set trap for error handling (but continue with cleanup)
trap handle_error ERR

# Banner
echo "============================================================"
echo "  Database Fleet Governance Cleanup"
echo "  Recipe: Centralized Database Fleet Governance"
echo "  Provider: Google Cloud Platform"
echo "============================================================"
echo

# Load environment variables from deployment
load_environment() {
    log_info "Loading environment variables from deployment..."
    
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        # shellcheck source=/dev/null
        source "${SCRIPT_DIR}/.env"
        log_info "Environment loaded from ${SCRIPT_DIR}/.env"
        log_info "PROJECT_ID: $PROJECT_ID"
        log_info "REGION: $REGION"
        log_info "ZONE: $ZONE"
        log_info "RANDOM_SUFFIX: $RANDOM_SUFFIX"
    else
        log_warning "Environment file not found. Attempting to use existing gcloud configuration..."
        export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo '')}"
        export REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null || echo 'us-central1')}"
        export ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || echo 'us-central1-a')}"
        export RANDOM_SUFFIX="${RANDOM_SUFFIX:-unknown}"
        export SERVICE_ACCOUNT="db-governance-sa@${PROJECT_ID}.iam.gserviceaccount.com"
        
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "PROJECT_ID not found. Please set it manually or run from the same directory as deploy.sh"
            echo "Usage: PROJECT_ID=your-project-id ./destroy.sh"
            exit 1
        fi
    fi
    
    # Set gcloud configuration
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    log_success "Environment configured for cleanup"
}

# Confirmation prompt
confirm_destruction() {
    echo
    log_warning "This will PERMANENTLY DELETE the following resources:"
    echo "- Project: $PROJECT_ID (if created by deploy script)"
    echo "- Cloud SQL instance: fleet-sql-${RANDOM_SUFFIX}"
    echo "- Spanner instance: fleet-spanner-${RANDOM_SUFFIX}"
    echo "- Bigtable instance: fleet-bigtable-${RANDOM_SUFFIX}"
    echo "- BigQuery dataset: database_governance"
    echo "- Cloud Storage bucket: db-governance-assets-${RANDOM_SUFFIX}"
    echo "- Cloud Function: compliance-reporter"
    echo "- Workflow: database-governance-workflow"
    echo "- All associated data and configurations"
    echo
    log_warning "This action CANNOT be undone!"
    echo
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Delete Cloud Functions and automation
cleanup_automation() {
    log_info "Cleaning up automation components..."
    
    # Delete Cloud Scheduler job
    if gcloud scheduler jobs describe governance-scheduler --location="$REGION" &>/dev/null; then
        log_info "Deleting Cloud Scheduler job..."
        gcloud scheduler jobs delete governance-scheduler \
            --location="$REGION" \
            --quiet
        log_success "Cloud Scheduler job deleted"
    else
        log_info "Cloud Scheduler job not found, skipping"
    fi
    
    # Delete Cloud Function
    if gcloud functions describe compliance-reporter --region="$REGION" &>/dev/null; then
        log_info "Deleting Cloud Function..."
        gcloud functions delete compliance-reporter \
            --region="$REGION" \
            --quiet
        log_success "Cloud Function deleted"
    else
        log_info "Cloud Function not found, skipping"
    fi
    
    # Delete Workflow
    if gcloud workflows describe database-governance-workflow --location="$REGION" &>/dev/null; then
        log_info "Deleting governance workflow..."
        gcloud workflows delete database-governance-workflow \
            --location="$REGION" \
            --quiet
        log_success "Governance workflow deleted"
    else
        log_info "Governance workflow not found, skipping"
    fi
    
    log_success "Automation components cleanup completed"
}

# Delete monitoring and alerting resources
cleanup_monitoring() {
    log_info "Cleaning up monitoring and alerting resources..."
    
    # Delete alert policies
    local alert_policies
    alert_policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:Database Governance Violations" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$alert_policies" ]]; then
        log_info "Deleting alert policies..."
        echo "$alert_policies" | while read -r policy; do
            gcloud alpha monitoring policies delete "$policy" --quiet
        done
        log_success "Alert policies deleted"
    else
        log_info "No alert policies found, skipping"
    fi
    
    # Delete notification channels
    local notification_channels
    notification_channels=$(gcloud alpha monitoring channels list \
        --filter="displayName:Database Governance Alerts" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$notification_channels" ]]; then
        log_info "Deleting notification channels..."
        echo "$notification_channels" | while read -r channel; do
            gcloud alpha monitoring channels delete "$channel" --quiet
        done
        log_success "Notification channels deleted"
    else
        log_info "No notification channels found, skipping"
    fi
    
    # Delete custom metrics
    local metrics=("database_compliance_score" "governance_events")
    for metric in "${metrics[@]}"; do
        if gcloud logging metrics describe "$metric" &>/dev/null; then
            log_info "Deleting log-based metric: $metric"
            gcloud logging metrics delete "$metric" --quiet
            log_success "Metric $metric deleted"
        else
            log_info "Metric $metric not found, skipping"
        fi
    done
    
    log_success "Monitoring and alerting cleanup completed"
}

# Delete Pub/Sub resources
cleanup_pubsub() {
    log_info "Cleaning up Pub/Sub resources..."
    
    # Delete Pub/Sub subscription
    if gcloud pubsub subscriptions describe governance-automation &>/dev/null; then
        log_info "Deleting Pub/Sub subscription..."
        gcloud pubsub subscriptions delete governance-automation --quiet
        log_success "Pub/Sub subscription deleted"
    else
        log_info "Pub/Sub subscription not found, skipping"
    fi
    
    # Delete Pub/Sub topic
    if gcloud pubsub topics describe database-asset-changes &>/dev/null; then
        log_info "Deleting Pub/Sub topic..."
        gcloud pubsub topics delete database-asset-changes --quiet
        log_success "Pub/Sub topic deleted"
    else
        log_info "Pub/Sub topic not found, skipping"
    fi
    
    log_success "Pub/Sub resources cleanup completed"
}

# Delete storage resources
cleanup_storage() {
    log_info "Cleaning up storage resources..."
    
    # Delete BigQuery dataset
    if bq ls -d "${PROJECT_ID}:database_governance" &>/dev/null; then
        log_info "Deleting BigQuery dataset..."
        bq rm -r -f "${PROJECT_ID}:database_governance"
        log_success "BigQuery dataset deleted"
    else
        log_info "BigQuery dataset not found, skipping"
    fi
    
    # Delete Cloud Storage bucket
    local bucket_name="db-governance-assets-${RANDOM_SUFFIX}"
    if gsutil ls "gs://$bucket_name" &>/dev/null; then
        log_info "Deleting Cloud Storage bucket..."
        gsutil -m rm -r "gs://$bucket_name"
        log_success "Cloud Storage bucket deleted"
    else
        log_info "Cloud Storage bucket not found, skipping"
    fi
    
    log_success "Storage resources cleanup completed"
}

# Delete database instances
cleanup_database_fleet() {
    log_info "Cleaning up database fleet..."
    
    # Delete Cloud SQL instance (remove deletion protection first)
    if gcloud sql instances describe "fleet-sql-${RANDOM_SUFFIX}" &>/dev/null; then
        log_info "Removing deletion protection from Cloud SQL instance..."
        gcloud sql instances patch "fleet-sql-${RANDOM_SUFFIX}" \
            --no-deletion-protection \
            --quiet
        
        log_info "Deleting Cloud SQL instance..."
        gcloud sql instances delete "fleet-sql-${RANDOM_SUFFIX}" --quiet
        log_success "Cloud SQL instance deleted"
    else
        log_info "Cloud SQL instance not found, skipping"
    fi
    
    # Delete Spanner instance
    if gcloud spanner instances describe "fleet-spanner-${RANDOM_SUFFIX}" &>/dev/null; then
        log_info "Deleting Spanner instance..."
        gcloud spanner instances delete "fleet-spanner-${RANDOM_SUFFIX}" --quiet
        log_success "Spanner instance deleted"
    else
        log_info "Spanner instance not found, skipping"
    fi
    
    # Delete Bigtable instance
    if gcloud bigtable instances describe "fleet-bigtable-${RANDOM_SUFFIX}" &>/dev/null; then
        log_info "Deleting Bigtable instance..."
        gcloud bigtable instances delete "fleet-bigtable-${RANDOM_SUFFIX}" --quiet
        log_success "Bigtable instance deleted"
    else
        log_info "Bigtable instance not found, skipping"
    fi
    
    log_success "Database fleet cleanup completed"
}

# Delete IAM resources
cleanup_iam() {
    log_info "Cleaning up IAM resources..."
    
    # Remove IAM policy bindings for service account
    local roles=(
        "roles/cloudasset.viewer"
        "roles/workflows.invoker"
        "roles/monitoring.metricWriter"
        "roles/aiplatform.user"
        "roles/cloudsql.viewer"
        "roles/spanner.databaseReader"
        "roles/bigtable.reader"
        "roles/bigquery.dataEditor"
        "roles/bigquery.jobUser"
        "roles/storage.objectAdmin"
        "roles/pubsub.publisher"
        "roles/pubsub.subscriber"
        "roles/cloudfunctions.invoker"
    )
    
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT" &>/dev/null; then
        for role in "${roles[@]}"; do
            log_info "Removing role $role from service account..."
            gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$SERVICE_ACCOUNT" \
                --role="$role" \
                --quiet 2>/dev/null || log_warning "Failed to remove role $role"
        done
        
        # Delete service account
        log_info "Deleting service account..."
        gcloud iam service-accounts delete "$SERVICE_ACCOUNT" --quiet
        log_success "Service account deleted"
    else
        log_info "Service account not found, skipping"
    fi
    
    log_success "IAM resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_delete=(
        "${SCRIPT_DIR}/.env"
        "${SCRIPT_DIR}/governance-workflow.yaml"
        "${SCRIPT_DIR}/governance-alert-policy.json"
        "${SCRIPT_DIR}/gemini-queries.json"
    )
    
    for file in "${files_to_delete[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Deleted: $file"
        fi
    done
    
    # Remove function directory
    if [[ -d "${SCRIPT_DIR}/governance-reporting" ]]; then
        rm -rf "${SCRIPT_DIR}/governance-reporting"
        log_info "Deleted: governance-reporting directory"
    fi
    
    log_success "Local files cleanup completed"
}

# Optional: Delete project entirely
cleanup_project() {
    echo
    log_warning "Do you want to delete the entire project '$PROJECT_ID'?"
    log_warning "This will delete ALL resources in the project, not just the ones created by this recipe."
    echo
    read -p "Delete entire project? Type 'delete-project' to confirm: " project_confirmation
    
    if [[ "$project_confirmation" == "delete-project" ]]; then
        log_info "Deleting project: $PROJECT_ID"
        gcloud projects delete "$PROJECT_ID" --quiet
        log_success "Project $PROJECT_ID deleted"
    else
        log_info "Project deletion skipped"
        log_info "You may want to manually review and clean up any remaining resources"
    fi
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local remaining_resources=()
    
    # Check for remaining database instances
    if gcloud sql instances list --filter="name:fleet-sql-${RANDOM_SUFFIX}" --format="value(name)" | grep -q .; then
        remaining_resources+=("Cloud SQL instance: fleet-sql-${RANDOM_SUFFIX}")
    fi
    
    if gcloud spanner instances list --filter="name:fleet-spanner-${RANDOM_SUFFIX}" --format="value(name)" | grep -q .; then
        remaining_resources+=("Spanner instance: fleet-spanner-${RANDOM_SUFFIX}")
    fi
    
    if gcloud bigtable instances list --filter="name:fleet-bigtable-${RANDOM_SUFFIX}" --format="value(name)" | grep -q .; then
        remaining_resources+=("Bigtable instance: fleet-bigtable-${RANDOM_SUFFIX}")
    fi
    
    # Check for remaining functions and workflows
    if gcloud functions describe compliance-reporter --region="$REGION" &>/dev/null; then
        remaining_resources+=("Cloud Function: compliance-reporter")
    fi
    
    if gcloud workflows describe database-governance-workflow --location="$REGION" &>/dev/null; then
        remaining_resources+=("Workflow: database-governance-workflow")
    fi
    
    # Check for remaining storage
    if bq ls -d "${PROJECT_ID}:database_governance" &>/dev/null; then
        remaining_resources+=("BigQuery dataset: database_governance")
    fi
    
    local bucket_name="db-governance-assets-${RANDOM_SUFFIX}"
    if gsutil ls "gs://$bucket_name" &>/dev/null; then
        remaining_resources+=("Cloud Storage bucket: $bucket_name")
    fi
    
    if [[ ${#remaining_resources[@]} -eq 0 ]]; then
        log_success "All resources cleaned up successfully"
    else
        log_warning "Some resources may still exist:"
        printf '%s\n' "${remaining_resources[@]}"
        log_info "Please review and clean up manually if needed"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Database Fleet Governance cleanup..."
    
    load_environment
    confirm_destruction
    
    # Perform cleanup in reverse order of creation
    cleanup_automation
    cleanup_monitoring
    cleanup_pubsub
    cleanup_storage
    cleanup_database_fleet
    cleanup_iam
    cleanup_local_files
    
    verify_cleanup
    cleanup_project
    
    echo
    echo "============================================================"
    log_success "Database Fleet Governance cleanup completed!"
    echo "============================================================"
    echo
    log_info "Cleanup summary:"
    echo "- Automation components removed"
    echo "- Monitoring and alerting resources deleted"
    echo "- Database fleet instances deleted"
    echo "- Storage resources cleaned up"
    echo "- IAM resources removed"
    echo "- Local files cleaned up"
    echo
    log_info "If you deleted the entire project, all resources have been removed."
    log_info "Otherwise, please verify that no unwanted resources remain in your project."
    echo
    log_info "Thank you for using the Database Fleet Governance recipe!"
}

# Run main function
main "$@"