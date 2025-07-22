#!/bin/bash

# Fleet Operations with Fleet Engine and Cloud Run Jobs - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Configuration variables (these should match the deployment script)
PROJECT_ID=${PROJECT_ID:-""}
REGION=${REGION:-"us-central1"}
ZONE=${ZONE:-"us-central1-a"}
ANALYTICS_JOB_NAME=${ANALYTICS_JOB_NAME:-""}
BUCKET_NAME=${BUCKET_NAME:-""}
DATASET_NAME=${DATASET_NAME:-"fleet_analytics"}
FLEET_ENGINE_SA_EMAIL=""
DELETE_PROJECT=${DELETE_PROJECT:-"false"}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "bq CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Auto-detect project configuration
auto_detect_config() {
    log_info "Auto-detecting project configuration..."
    
    # Get current project if not set
    if [[ -z "${PROJECT_ID}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "Could not determine project ID. Please set PROJECT_ID environment variable."
            exit 1
        fi
    fi
    
    # Set project context
    gcloud config set project ${PROJECT_ID}
    FLEET_ENGINE_SA_EMAIL="fleet-engine-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Try to detect analytics job name
    if [[ -z "${ANALYTICS_JOB_NAME}" ]]; then
        ANALYTICS_JOB_NAME=$(gcloud run jobs list --region=${REGION} \
            --filter="metadata.name~fleet-analytics" \
            --format="value(metadata.name)" | head -1)
        if [[ -z "${ANALYTICS_JOB_NAME}" ]]; then
            log_warning "Could not auto-detect analytics job name"
        fi
    fi
    
    # Try to detect bucket name
    if [[ -z "${BUCKET_NAME}" ]]; then
        BUCKET_NAME=$(gsutil ls -p ${PROJECT_ID} | grep "fleet-data-" | head -1 | sed 's|gs://||' | sed 's|/||')
        if [[ -z "${BUCKET_NAME}" ]]; then
            log_warning "Could not auto-detect bucket name"
        fi
    fi
    
    log_info "Configuration detected:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Analytics Job: ${ANALYTICS_JOB_NAME:-"Not found"}"
    log_info "  Bucket: ${BUCKET_NAME:-"Not found"}"
    log_info "  Service Account: ${FLEET_ENGINE_SA_EMAIL}"
}

# Confirm deletion
confirm_deletion() {
    log_warning "This will permanently delete all Fleet Operations resources!"
    echo ""
    echo "Resources to be deleted:"
    echo "- Project: ${PROJECT_ID}"
    echo "- Cloud Run Job: ${ANALYTICS_JOB_NAME}"
    echo "- Storage Bucket: ${BUCKET_NAME}"
    echo "- BigQuery Dataset: ${DATASET_NAME}"
    echo "- Service Account: ${FLEET_ENGINE_SA_EMAIL}"
    echo "- All associated data and configurations"
    echo ""
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        log_warning "THE ENTIRE PROJECT WILL BE DELETED!"
        echo ""
        read -p "Are you absolutely sure you want to DELETE THE ENTIRE PROJECT? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Deletion cancelled."
            exit 0
        fi
    else
        read -p "Are you sure you want to delete these resources? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Deletion cancelled."
            exit 0
        fi
    fi
    
    log_info "Proceeding with deletion..."
}

# Remove Cloud Scheduler jobs
remove_scheduler_jobs() {
    log_info "Removing Cloud Scheduler jobs..."
    
    # Delete daily analytics job
    if gcloud scheduler jobs describe fleet-analytics-daily --location=${REGION} &> /dev/null; then
        gcloud scheduler jobs delete fleet-analytics-daily \
            --location=${REGION} \
            --quiet || {
            log_warning "Failed to delete daily scheduler job"
        }
        log_success "Daily scheduler job deleted"
    else
        log_warning "Daily scheduler job not found"
    fi
    
    # Delete hourly insights job
    if gcloud scheduler jobs describe fleet-insights-hourly --location=${REGION} &> /dev/null; then
        gcloud scheduler jobs delete fleet-insights-hourly \
            --location=${REGION} \
            --quiet || {
            log_warning "Failed to delete hourly scheduler job"
        }
        log_success "Hourly scheduler job deleted"
    else
        log_warning "Hourly scheduler job not found"
    fi
    
    log_success "Cloud Scheduler jobs removal completed"
}

# Remove Cloud Run Job and container images
remove_cloud_run_job() {
    log_info "Removing Cloud Run Job and container images..."
    
    # Delete Cloud Run Job
    if [[ -n "${ANALYTICS_JOB_NAME}" ]]; then
        if gcloud run jobs describe ${ANALYTICS_JOB_NAME} --region=${REGION} &> /dev/null; then
            gcloud run jobs delete ${ANALYTICS_JOB_NAME} \
                --region=${REGION} \
                --quiet || {
                log_warning "Failed to delete Cloud Run Job"
            }
            log_success "Cloud Run Job deleted"
        else
            log_warning "Cloud Run Job not found"
        fi
        
        # Delete container images
        if gcloud container images describe gcr.io/${PROJECT_ID}/${ANALYTICS_JOB_NAME} &> /dev/null; then
            gcloud container images delete gcr.io/${PROJECT_ID}/${ANALYTICS_JOB_NAME} \
                --quiet || {
                log_warning "Failed to delete container image"
            }
            log_success "Container image deleted"
        else
            log_warning "Container image not found"
        fi
    else
        log_warning "Analytics job name not specified, skipping Cloud Run Job deletion"
    fi
    
    log_success "Cloud Run Job removal completed"
}

# Remove monitoring resources
remove_monitoring() {
    log_info "Removing monitoring resources..."
    
    # List and delete dashboards related to fleet operations
    dashboard_ids=$(gcloud monitoring dashboards list \
        --filter="displayName:'Fleet Operations Dashboard'" \
        --format="value(name)" | cut -d'/' -f4)
    
    if [[ -n "${dashboard_ids}" ]]; then
        for dashboard_id in ${dashboard_ids}; do
            gcloud monitoring dashboards delete ${dashboard_id} \
                --quiet || {
                log_warning "Failed to delete dashboard ${dashboard_id}"
            }
        done
        log_success "Monitoring dashboards deleted"
    else
        log_warning "No fleet operations dashboards found"
    fi
    
    # Delete alerting policies
    policy_ids=$(gcloud alpha monitoring policies list \
        --filter="displayName:'Fleet Analytics Job Failures'" \
        --format="value(name)" | cut -d'/' -f4)
    
    if [[ -n "${policy_ids}" ]]; then
        for policy_id in ${policy_ids}; do
            gcloud alpha monitoring policies delete ${policy_id} \
                --quiet || {
                log_warning "Failed to delete alerting policy ${policy_id}"
            }
        done
        log_success "Alerting policies deleted"
    else
        log_warning "No fleet operations alerting policies found"
    fi
    
    log_success "Monitoring resources removal completed"
}

# Remove storage and database resources
remove_storage_and_databases() {
    log_info "Removing storage and database resources..."
    
    # Delete Cloud Storage bucket
    if [[ -n "${BUCKET_NAME}" ]]; then
        if gsutil ls -b gs://${BUCKET_NAME} &> /dev/null; then
            log_info "Deleting bucket contents..."
            gsutil -m rm -r gs://${BUCKET_NAME}/* || {
                log_warning "Some bucket contents may not have been deleted"
            }
            
            log_info "Deleting bucket..."
            gsutil rb gs://${BUCKET_NAME} || {
                log_warning "Failed to delete storage bucket"
            }
            log_success "Storage bucket deleted"
        else
            log_warning "Storage bucket not found"
        fi
    else
        log_warning "Bucket name not specified, skipping storage deletion"
    fi
    
    # Delete BigQuery dataset
    if bq ls -d ${PROJECT_ID}:${DATASET_NAME} &> /dev/null; then
        bq rm -r -f ${PROJECT_ID}:${DATASET_NAME} || {
            log_warning "Failed to delete BigQuery dataset"
        }
        log_success "BigQuery dataset deleted"
    else
        log_warning "BigQuery dataset not found"
    fi
    
    # Note about Firestore database
    log_warning "Firestore database cannot be deleted via CLI"
    log_warning "To delete Firestore database, visit:"
    log_warning "https://console.cloud.google.com/firestore/databases?project=${PROJECT_ID}"
    
    log_success "Storage and database resources removal completed"
}

# Remove IAM resources
remove_iam_resources() {
    log_info "Removing IAM resources..."
    
    # Remove IAM policy bindings
    local roles=(
        "roles/fleetengine.deliveryFleetReader"
        "roles/fleetengine.deliveryConsumer"
        "roles/bigquery.dataEditor"
        "roles/storage.objectAdmin"
        "roles/datastore.user"
        "roles/run.invoker"
    )
    
    for role in "${roles[@]}"; do
        log_info "Removing role: ${role}"
        gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
            --member="serviceAccount:${FLEET_ENGINE_SA_EMAIL}" \
            --role="${role}" &> /dev/null || {
            log_warning "Role ${role} may not be assigned or already removed"
        }
    done
    
    # Delete service account
    if gcloud iam service-accounts describe ${FLEET_ENGINE_SA_EMAIL} &> /dev/null; then
        gcloud iam service-accounts delete ${FLEET_ENGINE_SA_EMAIL} \
            --quiet || {
            log_warning "Failed to delete service account"
        }
        log_success "Service account deleted"
    else
        log_warning "Service account not found"
    fi
    
    # Remove service account key file
    if [[ -f "fleet-engine-key.json" ]]; then
        rm fleet-engine-key.json
        log_success "Service account key file removed"
    else
        log_warning "Service account key file not found"
    fi
    
    log_success "IAM resources removal completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove fleet analytics job source code
    if [[ -d "fleet-analytics-job" ]]; then
        rm -rf fleet-analytics-job
        log_success "Fleet analytics job source code removed"
    else
        log_warning "Fleet analytics job source code not found"
    fi
    
    # Remove any temporary files
    rm -f lifecycle-policy.json firestore-indexes.yaml fleet-dashboard.json alerting-policy.json
    
    log_success "Local files cleanup completed"
}

# Delete entire project
delete_project() {
    log_info "Deleting entire project: ${PROJECT_ID}"
    
    # Delete the project
    gcloud projects delete ${PROJECT_ID} \
        --quiet || {
        log_error "Failed to delete project ${PROJECT_ID}"
        exit 1
    }
    
    log_success "Project ${PROJECT_ID} deleted successfully"
    log_warning "It may take a few minutes for the project to be completely removed"
}

# Print cleanup summary
print_cleanup_summary() {
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        log_success "Fleet Operations project deletion completed!"
        echo ""
        echo "=== CLEANUP SUMMARY ==="
        echo "Project ${PROJECT_ID} has been scheduled for deletion"
        echo "All resources within the project will be permanently removed"
        echo ""
        echo "=== IMPORTANT NOTES ==="
        echo "- Project deletion is irreversible"
        echo "- It may take several minutes for complete removal"
        echo "- Billing will stop once the project is fully deleted"
        echo "- Some resources may have a retention period"
        echo ""
    else
        log_success "Fleet Operations cleanup completed!"
        echo ""
        echo "=== CLEANUP SUMMARY ==="
        echo "Removed resources:"
        echo "- Cloud Scheduler jobs"
        echo "- Cloud Run Job: ${ANALYTICS_JOB_NAME}"
        echo "- Container images"
        echo "- Storage bucket: ${BUCKET_NAME}"
        echo "- BigQuery dataset: ${DATASET_NAME}"
        echo "- Service account: ${FLEET_ENGINE_SA_EMAIL}"
        echo "- Monitoring dashboards and alerts"
        echo "- Local files and directories"
        echo ""
        echo "=== MANUAL CLEANUP REQUIRED ==="
        echo "- Firestore database (delete manually in console)"
        echo "- Any remaining log entries in Cloud Logging"
        echo "- Project-level IAM policies (if any were created)"
        echo ""
        echo "=== BILLING NOTES ==="
        echo "- Most resources should stop incurring charges immediately"
        echo "- Some storage costs may continue until retention periods expire"
        echo "- Monitor your billing dashboard for any unexpected charges"
        echo ""
    fi
}

# Main execution
main() {
    log_info "Starting Fleet Operations cleanup..."
    
    check_prerequisites
    auto_detect_config
    confirm_deletion
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        delete_project
    else
        remove_scheduler_jobs
        remove_cloud_run_job
        remove_monitoring
        remove_storage_and_databases
        remove_iam_resources
        cleanup_local_files
    fi
    
    print_cleanup_summary
    
    log_success "Fleet Operations cleanup completed successfully!"
}

# Show help
show_help() {
    echo "Fleet Operations Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  --delete-project        Delete the entire project (DESTRUCTIVE)"
    echo "  --project-id PROJECT    Specify project ID (otherwise auto-detected)"
    echo "  --region REGION         Specify region (default: us-central1)"
    echo "  --job-name JOB_NAME     Specify analytics job name (otherwise auto-detected)"
    echo "  --bucket-name BUCKET    Specify bucket name (otherwise auto-detected)"
    echo "  --yes                   Skip confirmation prompt"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID              Google Cloud project ID"
    echo "  REGION                  Google Cloud region"
    echo "  ANALYTICS_JOB_NAME      Cloud Run job name"
    echo "  BUCKET_NAME             Cloud Storage bucket name"
    echo "  DELETE_PROJECT          Set to 'true' to delete entire project"
    echo ""
    echo "Examples:"
    echo "  $0                                  # Interactive cleanup"
    echo "  $0 --delete-project                # Delete entire project"
    echo "  $0 --project-id my-fleet-project   # Cleanup specific project"
    echo "  PROJECT_ID=my-fleet-project $0     # Using environment variable"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --delete-project)
            DELETE_PROJECT="true"
            shift
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --job-name)
            ANALYTICS_JOB_NAME="$2"
            shift 2
            ;;
        --bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        --yes)
            # Skip confirmation (for automated scenarios)
            confirm_deletion() { return 0; }
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"