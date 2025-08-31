#!/bin/bash

# Automated Cost Analytics with Worker Pools and BigQuery - Cleanup Script
# This script removes all infrastructure created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if bq CLI is installed
    if ! command -v bq &> /dev/null; then
        error "BigQuery CLI (bq) is not installed."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to get environment variables or prompt user
setup_environment() {
    log "Setting up environment variables..."
    
    # Try to get current project if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            echo -n "Enter Project ID: "
            read -r PROJECT_ID
        fi
    fi
    
    # Set default region if not provided
    REGION="${REGION:-us-central1}"
    
    # Set default resource name pattern if not provided
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        echo -n "Enter random suffix used during deployment (or leave empty to search all): "
        read -r RANDOM_SUFFIX
    fi
    
    export PROJECT_ID
    export REGION
    export RANDOM_SUFFIX
    
    log "Cleanup Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Random Suffix: ${RANDOM_SUFFIX:-<search all>}"
    
    success "Environment variables configured"
}

# Function to confirm destructive operation
confirm_destruction() {
    echo ""
    warning "This script will permanently delete the following resources:"
    echo "  - Cloud Run services (cost-worker-*)"
    echo "  - BigQuery datasets and tables (cost_analytics_*)"
    echo "  - Pub/Sub topics and subscriptions (cost-processing-*)"
    echo "  - Cloud Scheduler jobs (daily-cost-analysis-*)"
    echo "  - Service accounts (cost-worker-sa-*)"
    echo "  - IAM policy bindings"
    echo ""
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        warning "Force delete mode enabled, skipping confirmation"
        return 0
    fi
    
    echo -n "Are you sure you want to proceed? (yes/no): "
    read -r confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Cleanup confirmed"
}

# Function to find resources by pattern
find_resources() {
    local resource_type="$1"
    local pattern="$2"
    local filter="$3"
    
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        # Use specific suffix
        echo "${pattern}${RANDOM_SUFFIX}"
    else
        # Search for all matching resources
        case "${resource_type}" in
            "cloud-run")
                gcloud run services list --region="${REGION}" --filter="${filter}" --format="value(metadata.name)" 2>/dev/null | grep "^${pattern}" || true
                ;;
            "bigquery-dataset")
                bq ls --max_results=1000 --format=csv | tail -n +2 | cut -d',' -f1 | grep "^${pattern}" || true
                ;;
            "pubsub-topic")
                gcloud pubsub topics list --filter="${filter}" --format="value(name.basename())" 2>/dev/null | grep "^${pattern}" || true
                ;;
            "pubsub-subscription")
                gcloud pubsub subscriptions list --filter="${filter}" --format="value(name.basename())" 2>/dev/null | grep "^${pattern}" || true
                ;;
            "scheduler-job")
                gcloud scheduler jobs list --filter="${filter}" --format="value(name.basename())" 2>/dev/null | grep "^${pattern}" || true
                ;;
            "service-account")
                gcloud iam service-accounts list --filter="${filter}" --format="value(email)" 2>/dev/null | grep "${pattern}" || true
                ;;
        esac
    fi
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log "Deleting Cloud Scheduler jobs..."
    
    local jobs
    jobs=$(find_resources "scheduler-job" "daily-cost-analysis-" "name:daily-cost-analysis")
    
    if [[ -n "${jobs}" ]]; then
        while IFS= read -r job; do
            if [[ -n "${job}" ]]; then
                log "Deleting scheduler job: ${job}"
                if gcloud scheduler jobs delete "${job}" --quiet 2>/dev/null; then
                    success "Deleted scheduler job: ${job}"
                else
                    warning "Failed to delete scheduler job: ${job}"
                fi
            fi
        done <<< "${jobs}"
    else
        warning "No scheduler jobs found to delete"
    fi
    
    success "Scheduler jobs cleanup completed"
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    # Delete subscriptions first
    local subscriptions
    subscriptions=$(find_resources "pubsub-subscription" "cost-processing-sub-" "name:cost-processing-sub")
    
    if [[ -n "${subscriptions}" ]]; then
        while IFS= read -r subscription; do
            if [[ -n "${subscription}" ]]; then
                log "Deleting Pub/Sub subscription: ${subscription}"
                if gcloud pubsub subscriptions delete "${subscription}" --quiet 2>/dev/null; then
                    success "Deleted subscription: ${subscription}"
                else
                    warning "Failed to delete subscription: ${subscription}"
                fi
            fi
        done <<< "${subscriptions}"
    else
        warning "No Pub/Sub subscriptions found to delete"
    fi
    
    # Delete topics
    local topics
    topics=$(find_resources "pubsub-topic" "cost-processing-" "name:cost-processing")
    
    if [[ -n "${topics}" ]]; then
        while IFS= read -r topic; do
            if [[ -n "${topic}" ]]; then
                log "Deleting Pub/Sub topic: ${topic}"
                if gcloud pubsub topics delete "${topic}" --quiet 2>/dev/null; then
                    success "Deleted topic: ${topic}"
                else
                    warning "Failed to delete topic: ${topic}"
                fi
            fi
        done <<< "${topics}"
    else
        warning "No Pub/Sub topics found to delete"
    fi
    
    success "Pub/Sub resources cleanup completed"
}

# Function to delete Cloud Run services
delete_cloud_run_services() {
    log "Deleting Cloud Run services..."
    
    local services
    services=$(find_resources "cloud-run" "cost-worker-" "metadata.name:cost-worker")
    
    if [[ -n "${services}" ]]; then
        while IFS= read -r service; do
            if [[ -n "${service}" ]]; then
                log "Deleting Cloud Run service: ${service}"
                if gcloud run services delete "${service}" --region="${REGION}" --quiet 2>/dev/null; then
                    success "Deleted Cloud Run service: ${service}"
                else
                    warning "Failed to delete Cloud Run service: ${service}"
                fi
            fi
        done <<< "${services}"
    else
        warning "No Cloud Run services found to delete"
    fi
    
    success "Cloud Run services cleanup completed"
}

# Function to delete service accounts and IAM bindings
delete_service_accounts() {
    log "Deleting service accounts and IAM bindings..."
    
    local service_accounts
    service_accounts=$(find_resources "service-account" "cost-worker-sa-" "email:cost-worker-sa")
    
    if [[ -n "${service_accounts}" ]]; then
        while IFS= read -r sa_email; do
            if [[ -n "${sa_email}" ]]; then
                log "Removing IAM policy bindings for: ${sa_email}"
                
                # Remove IAM bindings
                local roles=("roles/bigquery.dataEditor" "roles/billing.viewer" "roles/run.invoker")
                for role in "${roles[@]}"; do
                    if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                        --member "serviceAccount:${sa_email}" \
                        --role "${role}" --quiet 2>/dev/null; then
                        success "Removed ${role} binding for ${sa_email}"
                    else
                        warning "Failed to remove ${role} binding for ${sa_email}"
                    fi
                done
                
                log "Deleting service account: ${sa_email}"
                if gcloud iam service-accounts delete "${sa_email}" --quiet 2>/dev/null; then
                    success "Deleted service account: ${sa_email}"
                else
                    warning "Failed to delete service account: ${sa_email}"
                fi
            fi
        done <<< "${service_accounts}"
    else
        warning "No service accounts found to delete"
    fi
    
    success "Service accounts cleanup completed"
}

# Function to delete BigQuery resources
delete_bigquery_resources() {
    log "Deleting BigQuery resources..."
    
    local datasets
    datasets=$(find_resources "bigquery-dataset" "cost_analytics_" "")
    
    if [[ -n "${datasets}" ]]; then
        while IFS= read -r dataset; do
            if [[ -n "${dataset}" ]]; then
                log "Deleting BigQuery dataset: ${dataset}"
                if bq rm -r -f "${PROJECT_ID}:${dataset}" 2>/dev/null; then
                    success "Deleted BigQuery dataset: ${dataset}"
                else
                    warning "Failed to delete BigQuery dataset: ${dataset}"
                fi
            fi
        done <<< "${datasets}"
    else
        warning "No BigQuery datasets found to delete"
    fi
    
    success "BigQuery resources cleanup completed"
}

# Function to disable APIs (optional)
disable_apis() {
    if [[ "${DISABLE_APIS:-}" == "true" ]]; then
        log "Disabling APIs (optional)..."
        
        local apis=(
            "cloudscheduler.googleapis.com"
            "cloudbilling.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log "Disabling ${api}..."
            if gcloud services disable "${api}" --force --quiet 2>/dev/null; then
                success "Disabled ${api}"
            else
                warning "Failed to disable ${api}"
            fi
        done
        
        success "APIs disabled"
    else
        log "Skipping API disabling (set DISABLE_APIS=true to enable)"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local remaining_resources=0
    
    # Check Cloud Run services
    local services
    services=$(gcloud run services list --region="${REGION}" --filter="metadata.name:cost-worker" --format="value(metadata.name)" 2>/dev/null | wc -l)
    if [[ "${services}" -gt 0 ]]; then
        warning "${services} Cloud Run services still exist"
        remaining_resources=$((remaining_resources + services))
    fi
    
    # Check BigQuery datasets
    local datasets
    datasets=$(bq ls --max_results=1000 --format=csv 2>/dev/null | tail -n +2 | cut -d',' -f1 | grep "cost_analytics_" | wc -l || echo "0")
    if [[ "${datasets}" -gt 0 ]]; then
        warning "${datasets} BigQuery datasets still exist"
        remaining_resources=$((remaining_resources + datasets))
    fi
    
    # Check Pub/Sub topics
    local topics
    topics=$(gcloud pubsub topics list --filter="name:cost-processing" --format="value(name.basename())" 2>/dev/null | wc -l)
    if [[ "${topics}" -gt 0 ]]; then
        warning "${topics} Pub/Sub topics still exist"
        remaining_resources=$((remaining_resources + topics))
    fi
    
    # Check service accounts
    local sa_count
    sa_count=$(gcloud iam service-accounts list --filter="email:cost-worker-sa" --format="value(email)" 2>/dev/null | wc -l)
    if [[ "${sa_count}" -gt 0 ]]; then
        warning "${sa_count} service accounts still exist"
        remaining_resources=$((remaining_resources + sa_count))
    fi
    
    if [[ "${remaining_resources}" -eq 0 ]]; then
        success "All resources have been successfully deleted"
    else
        warning "${remaining_resources} resources may still exist - please check manually"
    fi
    
    success "Cleanup verification completed"
}

# Function to show cleanup summary
show_cleanup_summary() {
    log "Cleanup Summary:"
    echo "================"
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Random Suffix: ${RANDOM_SUFFIX:-<searched all>}"
    echo ""
    echo "Resources cleaned up:"
    echo "- Cloud Scheduler jobs"
    echo "- Pub/Sub topics and subscriptions"
    echo "- Cloud Run services"
    echo "- Service accounts and IAM bindings"
    echo "- BigQuery datasets and tables"
    echo ""
    echo "Note: Some resources may take a few minutes to be fully deleted."
    echo "Note: Billing data may continue to show until the next billing cycle."
    echo ""
    success "Cleanup completed!"
}

# Main cleanup function
main() {
    echo "==========================================="
    echo "Automated Cost Analytics - Cleanup Script"
    echo "==========================================="
    echo ""
    
    check_prerequisites
    setup_environment
    confirm_destruction
    
    # Delete resources in reverse dependency order
    delete_scheduler_jobs
    delete_pubsub_resources
    delete_cloud_run_services
    delete_service_accounts
    delete_bigquery_resources
    disable_apis
    
    verify_cleanup
    show_cleanup_summary
}

# Handle script interruption
trap 'error "Cleanup interrupted!"; exit 1' INT TERM

# Check for command line flags
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DELETE="true"
            shift
            ;;
        --disable-apis)
            export DISABLE_APIS="true"
            shift
            ;;
        --project)
            export PROJECT_ID="$2"
            shift
            shift
            ;;
        --region)
            export REGION="$2"
            shift
            shift
            ;;
        --suffix)
            export RANDOM_SUFFIX="$2"
            shift
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force                Skip confirmation prompt"
            echo "  --disable-apis         Disable APIs after cleanup"
            echo "  --project PROJECT_ID   Specify project ID"
            echo "  --region REGION        Specify region (default: us-central1)"
            echo "  --suffix SUFFIX        Specify resource suffix used during deployment"
            echo "  -h, --help            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --project my-project --suffix abc123"
            echo "  $0 --force --disable-apis"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"