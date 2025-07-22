#!/bin/bash

# Destroy script for Data Quality Monitoring with Dataform and Cloud Scheduler
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed. Please install Google Cloud SDK with BigQuery components."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID environment variable is not set."
        log_info "Please set PROJECT_ID environment variable or use: export PROJECT_ID=your-project-id"
        exit 1
    fi
    
    # Verify project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Cannot access project $PROJECT_ID. Please check project ID and permissions."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export REGION="${REGION:-us-central1}"
    export DATAFORM_REGION="${DATAFORM_REGION:-us-central1}"
    export REPOSITORY_ID="${REPOSITORY_ID:-data-quality-repo}"
    export WORKSPACE_ID="${WORKSPACE_ID:-quality-workspace}"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    
    log_success "Environment configured for project: ${PROJECT_ID}"
}

# Confirmation prompt
confirm_destruction() {
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo
    echo "This script will permanently delete the following resources:"
    echo "  • All Cloud Scheduler jobs matching pattern: dataform-quality-job-*"
    echo "  • All Dataform repositories named: ${REPOSITORY_ID}"
    echo "  • All BigQuery datasets matching pattern: sample_ecommerce_*"
    echo "  • All BigQuery datasets matching pattern: dataform_assertions_*"
    echo "  • All Cloud Monitoring alert policies for data quality"
    echo "  • All Cloud Monitoring notification channels for data quality"
    echo "  • Service account: dataform-scheduler-sa"
    echo "  • Local Dataform project files"
    echo
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "FORCE_DESTROY is set - skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    echo
    log_info "Proceeding with resource destruction..."
}

# Delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log_info "Deleting Cloud Scheduler jobs..."
    
    # Find all dataform quality jobs
    local jobs
    jobs=$(gcloud scheduler jobs list \
        --location="${REGION}" \
        --filter="name~dataform-quality-job-*" \
        --format="value(name)" \
        --quiet 2>/dev/null || echo "")
    
    if [[ -n "$jobs" ]]; then
        while IFS= read -r job; do
            if [[ -n "$job" ]]; then
                log_info "Deleting scheduler job: $(basename "$job")"
                if gcloud scheduler jobs delete "$(basename "$job")" \
                    --location="${REGION}" \
                    --quiet 2>/dev/null; then
                    log_success "Deleted scheduler job: $(basename "$job")"
                else
                    log_warning "Failed to delete scheduler job: $(basename "$job")"
                fi
            fi
        done <<< "$jobs"
    else
        log_info "No Cloud Scheduler jobs found to delete"
    fi
}

# Delete Dataform resources
delete_dataform_resources() {
    log_info "Deleting Dataform resources..."
    
    # Delete workflow invocations first
    log_info "Deleting workflow invocations..."
    local invocations
    invocations=$(gcloud dataform workflow-invocations list \
        --location="${DATAFORM_REGION}" \
        --repository="${REPOSITORY_ID}" \
        --format="value(name)" \
        --project="${PROJECT_ID}" \
        --quiet 2>/dev/null || echo "")
    
    if [[ -n "$invocations" ]]; then
        while IFS= read -r invocation; do
            if [[ -n "$invocation" ]]; then
                log_info "Deleting workflow invocation: $(basename "$invocation")"
                gcloud dataform workflow-invocations delete "$(basename "$invocation")" \
                    --location="${DATAFORM_REGION}" \
                    --quiet 2>/dev/null || log_warning "Failed to delete invocation: $(basename "$invocation")"
            fi
        done <<< "$invocations"
    fi
    
    # Delete compilation results
    log_info "Deleting compilation results..."
    local compilations
    compilations=$(gcloud dataform compilation-results list \
        --location="${DATAFORM_REGION}" \
        --repository="${REPOSITORY_ID}" \
        --format="value(name)" \
        --project="${PROJECT_ID}" \
        --quiet 2>/dev/null || echo "")
    
    if [[ -n "$compilations" ]]; then
        while IFS= read -r compilation; do
            if [[ -n "$compilation" ]]; then
                log_info "Deleting compilation result: $(basename "$compilation")"
                gcloud dataform compilation-results delete "$(basename "$compilation")" \
                    --location="${DATAFORM_REGION}" \
                    --quiet 2>/dev/null || log_warning "Failed to delete compilation: $(basename "$compilation")"
            fi
        done <<< "$compilations"
    fi
    
    # Delete release configurations
    log_info "Deleting release configurations..."
    local releases
    releases=$(gcloud dataform release-configs list \
        --location="${DATAFORM_REGION}" \
        --repository="${REPOSITORY_ID}" \
        --format="value(name)" \
        --project="${PROJECT_ID}" \
        --quiet 2>/dev/null || echo "")
    
    if [[ -n "$releases" ]]; then
        while IFS= read -r release; do
            if [[ -n "$release" ]]; then
                log_info "Deleting release config: $(basename "$release")"
                gcloud dataform release-configs delete "$(basename "$release")" \
                    --location="${DATAFORM_REGION}" \
                    --repository="${REPOSITORY_ID}" \
                    --quiet 2>/dev/null || log_warning "Failed to delete release: $(basename "$release")"
            fi
        done <<< "$releases"
    fi
    
    # Delete workspaces
    log_info "Deleting workspaces..."
    local workspaces
    workspaces=$(gcloud dataform workspaces list \
        --location="${DATAFORM_REGION}" \
        --repository="${REPOSITORY_ID}" \
        --format="value(name)" \
        --project="${PROJECT_ID}" \
        --quiet 2>/dev/null || echo "")
    
    if [[ -n "$workspaces" ]]; then
        while IFS= read -r workspace; do
            if [[ -n "$workspace" ]]; then
                log_info "Deleting workspace: $(basename "$workspace")"
                gcloud dataform workspaces delete "$(basename "$workspace")" \
                    --location="${DATAFORM_REGION}" \
                    --repository="${REPOSITORY_ID}" \
                    --quiet 2>/dev/null || log_warning "Failed to delete workspace: $(basename "$workspace")"
            fi
        done <<< "$workspaces"
    fi
    
    # Delete repository
    log_info "Deleting Dataform repository: ${REPOSITORY_ID}"
    if gcloud dataform repositories delete "${REPOSITORY_ID}" \
        --location="${DATAFORM_REGION}" \
        --quiet 2>/dev/null; then
        log_success "Deleted Dataform repository: ${REPOSITORY_ID}"
    else
        log_warning "Failed to delete Dataform repository or it doesn't exist"
    fi
}

# Delete BigQuery datasets
delete_bigquery_datasets() {
    log_info "Deleting BigQuery datasets..."
    
    # Get all datasets in the project
    local datasets
    datasets=$(bq ls --format=csv --max_results=1000 2>/dev/null | tail -n +2 | cut -d, -f1 || echo "")
    
    if [[ -n "$datasets" ]]; then
        while IFS= read -r dataset; do
            if [[ -n "$dataset" ]]; then
                # Remove quotes if present
                dataset=$(echo "$dataset" | tr -d '"')
                
                # Delete datasets matching our patterns
                if [[ "$dataset" =~ ^sample_ecommerce_[a-f0-9]{6}$ ]] || [[ "$dataset" =~ ^dataform_assertions_[a-f0-9]{6}$ ]]; then
                    log_info "Deleting BigQuery dataset: ${dataset}"
                    if bq rm -r -f -d "${PROJECT_ID}:${dataset}" 2>/dev/null; then
                        log_success "Deleted BigQuery dataset: ${dataset}"
                    else
                        log_warning "Failed to delete BigQuery dataset: ${dataset}"
                    fi
                fi
            fi
        done <<< "$datasets"
    else
        log_info "No BigQuery datasets found to delete"
    fi
}

# Delete Cloud Monitoring resources
delete_monitoring_resources() {
    log_info "Deleting Cloud Monitoring resources..."
    
    # Delete alert policies
    log_info "Deleting alert policies..."
    local policies
    policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:'Data Quality Alert Policy'" \
        --format="value(name)" \
        --quiet 2>/dev/null || echo "")
    
    if [[ -n "$policies" ]]; then
        while IFS= read -r policy; do
            if [[ -n "$policy" ]]; then
                log_info "Deleting alert policy: $(basename "$policy")"
                if gcloud alpha monitoring policies delete "$policy" --quiet 2>/dev/null; then
                    log_success "Deleted alert policy: $(basename "$policy")"
                else
                    log_warning "Failed to delete alert policy: $(basename "$policy")"
                fi
            fi
        done <<< "$policies"
    else
        log_info "No alert policies found to delete"
    fi
    
    # Delete notification channels
    log_info "Deleting notification channels..."
    local channels
    channels=$(gcloud alpha monitoring channels list \
        --filter="displayName:'Data Quality Alerts'" \
        --format="value(name)" \
        --quiet 2>/dev/null || echo "")
    
    if [[ -n "$channels" ]]; then
        while IFS= read -r channel; do
            if [[ -n "$channel" ]]; then
                log_info "Deleting notification channel: $(basename "$channel")"
                if gcloud alpha monitoring channels delete "$channel" --quiet 2>/dev/null; then
                    log_success "Deleted notification channel: $(basename "$channel")"
                else
                    log_warning "Failed to delete notification channel: $(basename "$channel")"
                fi
            fi
        done <<< "$channels"
    else
        log_info "No notification channels found to delete"
    fi
    
    # Delete log-based metrics
    log_info "Deleting log-based metrics..."
    if gcloud logging metrics delete data_quality_failures --quiet 2>/dev/null; then
        log_success "Deleted log-based metric: data_quality_failures"
    else
        log_warning "Failed to delete log-based metric or it doesn't exist"
    fi
}

# Delete IAM service account
delete_service_account() {
    log_info "Deleting service account..."
    
    local sa_email="dataform-scheduler-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "$sa_email" >/dev/null 2>&1; then
        log_info "Deleting service account: $sa_email"
        if gcloud iam service-accounts delete "$sa_email" --quiet 2>/dev/null; then
            log_success "Deleted service account: $sa_email"
        else
            log_warning "Failed to delete service account: $sa_email"
        fi
    else
        log_info "Service account not found or already deleted: $sa_email"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove Dataform project directory
    if [[ -d ~/dataform-project ]]; then
        log_info "Removing local Dataform project directory..."
        rm -rf ~/dataform-project
        log_success "Removed local Dataform project directory"
    fi
    
    # Remove temporary files in current directory
    local temp_files=(
        "notification-channel.json"
        "alert-policy.json"
        "workflow_settings.yaml"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing temporary file: $file"
            rm -f "$file"
        fi
    done
    
    log_success "Local file cleanup completed"
}

# Validation function
validate_cleanup() {
    log_info "Validating cleanup..."
    
    local cleanup_issues=0
    
    # Check if Dataform repository still exists
    if gcloud dataform repositories describe "${REPOSITORY_ID}" \
        --location="${DATAFORM_REGION}" \
        --project="${PROJECT_ID}" \
        --quiet >/dev/null 2>&1; then
        log_warning "Dataform repository still exists: ${REPOSITORY_ID}"
        ((cleanup_issues++))
    fi
    
    # Check for remaining BigQuery datasets
    local remaining_datasets
    remaining_datasets=$(bq ls --format=csv --max_results=1000 2>/dev/null | tail -n +2 | cut -d, -f1 | tr -d '"' | grep -E '^(sample_ecommerce_|dataform_assertions_)[a-f0-9]{6}$' || echo "")
    
    if [[ -n "$remaining_datasets" ]]; then
        log_warning "Some BigQuery datasets still exist:"
        echo "$remaining_datasets"
        ((cleanup_issues++))
    fi
    
    # Check if service account still exists
    if gcloud iam service-accounts describe "dataform-scheduler-sa@${PROJECT_ID}.iam.gserviceaccount.com" >/dev/null 2>&1; then
        log_warning "Service account still exists: dataform-scheduler-sa@${PROJECT_ID}.iam.gserviceaccount.com"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup validation completed - no issues found"
    else
        log_warning "Cleanup validation found $cleanup_issues issues that may require manual attention"
    fi
    
    return $cleanup_issues
}

# Display cleanup summary
show_cleanup_summary() {
    echo
    log_success "🧹 Cleanup Summary"
    echo
    echo "The following resources have been removed:"
    echo "  ✅ Cloud Scheduler jobs"
    echo "  ✅ Dataform repositories and workspaces"
    echo "  ✅ BigQuery datasets and tables"
    echo "  ✅ Cloud Monitoring alert policies and notification channels"
    echo "  ✅ Log-based metrics"
    echo "  ✅ IAM service account"
    echo "  ✅ Local project files"
    echo
    log_info "💡 Additional Manual Steps (if needed):"
    echo "  • Review Cloud Logging for any remaining logs"
    echo "  • Check IAM policies for any remaining custom roles"
    echo "  • Verify billing to ensure no unexpected charges"
    echo
    log_info "📊 To verify complete cleanup, you can run:"
    echo "  • gcloud dataform repositories list --location=${DATAFORM_REGION}"
    echo "  • bq ls"
    echo "  • gcloud scheduler jobs list --location=${REGION}"
    echo "  • gcloud iam service-accounts list"
}

# Main destruction function
main() {
    log_info "Starting cleanup of Data Quality Monitoring resources"
    
    check_prerequisites
    setup_environment
    confirm_destruction
    
    log_info "🧹 Beginning resource cleanup..."
    echo
    
    # Delete resources in reverse order of creation
    delete_scheduler_jobs
    delete_monitoring_resources
    delete_dataform_resources
    delete_bigquery_datasets
    delete_service_account
    cleanup_local_files
    
    echo
    validate_cleanup
    show_cleanup_summary
    
    log_success "🎉 Cleanup completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "This script removes all resources created by the Data Quality Monitoring deployment."
        echo
        echo "Environment Variables:"
        echo "  PROJECT_ID        Google Cloud project ID (required)"
        echo "  REGION           Google Cloud region (default: us-central1)"
        echo "  DATAFORM_REGION  Dataform region (default: us-central1)"
        echo "  REPOSITORY_ID    Dataform repository name (default: data-quality-repo)"
        echo "  WORKSPACE_ID     Dataform workspace name (default: quality-workspace)"
        echo "  FORCE_DESTROY    Skip confirmation prompt (default: false)"
        echo
        echo "Options:"
        echo "  --help, -h       Show this help message"
        echo "  --force          Skip confirmation prompt (same as FORCE_DESTROY=true)"
        echo
        echo "Examples:"
        echo "  export PROJECT_ID=my-project"
        echo "  $0"
        echo
        echo "  export PROJECT_ID=my-project"
        echo "  $0 --force"
        echo
        exit 0
        ;;
    --force)
        export FORCE_DESTROY=true
        ;;
    "")
        # No arguments, proceed normally
        ;;
    *)
        log_error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main "$@"