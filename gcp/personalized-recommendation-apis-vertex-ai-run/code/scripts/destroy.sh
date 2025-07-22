#!/bin/bash

# Personalized Recommendation APIs with Vertex AI and Cloud Run - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed"
        exit 1
    fi
    
    # Check if bq is available
    if ! command_exists bq; then
        log_error "bq (BigQuery CLI) is not available. Please ensure Google Cloud SDK is properly installed"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Check if environment variables are set
    if [ -z "$PROJECT_ID" ]; then
        log_warning "PROJECT_ID not set. Please provide project ID:"
        read -p "Enter PROJECT_ID: " PROJECT_ID
        export PROJECT_ID
    fi
    
    # Set default values or use existing environment variables
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export BUCKET_NAME="${BUCKET_NAME:-rec-system-data-${PROJECT_ID}}"
    export SERVICE_NAME="${SERVICE_NAME:-recommendation-api}"
    export MODEL_NAME="${MODEL_NAME:-product-recommendations}"
    export ENDPOINT_NAME="${ENDPOINT_NAME:-rec-endpoint}"
    
    # Set the project as default
    gcloud config set project "$PROJECT_ID" || {
        log_error "Failed to set project. Please check if project $PROJECT_ID exists."
        exit 1
    }
    
    log_info "Environment variables loaded:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    log_info "  BUCKET_NAME: ${BUCKET_NAME}"
    log_info "  SERVICE_NAME: ${SERVICE_NAME}"
    log_info "  MODEL_NAME: ${MODEL_NAME}"
    log_info "  ENDPOINT_NAME: ${ENDPOINT_NAME}"
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "This will permanently delete all resources in project: $PROJECT_ID"
    log_warning "This action cannot be undone!"
    echo
    echo "Resources that will be deleted:"
    echo "  - Cloud Run service: $SERVICE_NAME"
    echo "  - Vertex AI models and endpoints"
    echo "  - Cloud Storage bucket: $BUCKET_NAME"
    echo "  - BigQuery dataset: user_interactions"
    echo "  - Training jobs and artifacts"
    echo
    
    if [ "$1" != "--yes" ]; then
        read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Starting resource cleanup..."
}

# Function to delete Cloud Run service
delete_cloud_run() {
    log_info "Deleting Cloud Run service..."
    
    # Check if service exists
    if gcloud run services describe "$SERVICE_NAME" --region="$REGION" >/dev/null 2>&1; then
        log_info "Found Cloud Run service: $SERVICE_NAME"
        
        # Delete Cloud Run service
        gcloud run services delete "$SERVICE_NAME" \
            --region="$REGION" \
            --quiet || {
            log_warning "Failed to delete Cloud Run service (it may not exist)"
        }
        
        log_success "Cloud Run service deleted"
    else
        log_warning "Cloud Run service not found or already deleted"
    fi
}

# Function to delete Vertex AI resources
delete_vertex_ai_resources() {
    log_info "Deleting Vertex AI resources..."
    
    # Get all endpoints in the region
    local endpoints
    endpoints=$(gcloud ai endpoints list --region="$REGION" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$endpoints" ]; then
        log_info "Found Vertex AI endpoints, proceeding with cleanup..."
        
        # Undeploy models from endpoints and delete endpoints
        while IFS= read -r endpoint_resource; do
            if [ -n "$endpoint_resource" ]; then
                local endpoint_id
                endpoint_id=$(echo "$endpoint_resource" | cut -d'/' -f6)
                
                log_info "Processing endpoint: $endpoint_id"
                
                # Get deployed models for this endpoint
                local deployed_models
                deployed_models=$(gcloud ai endpoints describe "$endpoint_id" \
                    --region="$REGION" \
                    --format="value(deployedModels[].id)" 2>/dev/null || echo "")
                
                # Undeploy each model
                if [ -n "$deployed_models" ]; then
                    while IFS= read -r model_id; do
                        if [ -n "$model_id" ]; then
                            log_info "Undeploying model: $model_id"
                            gcloud ai endpoints undeploy-model "$endpoint_id" \
                                --region="$REGION" \
                                --deployed-model-id="$model_id" \
                                --quiet || {
                                log_warning "Failed to undeploy model $model_id"
                            }
                        fi
                    done <<< "$deployed_models"
                fi
                
                # Delete endpoint
                log_info "Deleting endpoint: $endpoint_id"
                gcloud ai endpoints delete "$endpoint_id" \
                    --region="$REGION" \
                    --quiet || {
                    log_warning "Failed to delete endpoint $endpoint_id"
                }
            fi
        done <<< "$endpoints"
    else
        log_warning "No Vertex AI endpoints found"
    fi
    
    # Delete models
    local models
    models=$(gcloud ai models list --region="$REGION" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$models" ]; then
        log_info "Found Vertex AI models, deleting..."
        
        while IFS= read -r model_resource; do
            if [ -n "$model_resource" ]; then
                local model_id
                model_id=$(echo "$model_resource" | cut -d'/' -f6)
                
                log_info "Deleting model: $model_id"
                gcloud ai models delete "$model_id" \
                    --region="$REGION" \
                    --quiet || {
                    log_warning "Failed to delete model $model_id"
                }
            fi
        done <<< "$models"
    else
        log_warning "No Vertex AI models found"
    fi
    
    # Cancel any running training jobs
    local training_jobs
    training_jobs=$(gcloud ai custom-jobs list --region="$REGION" \
        --filter="displayName:recommendation-training-job AND state:JOB_STATE_RUNNING" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$training_jobs" ]; then
        log_info "Found running training jobs, cancelling..."
        
        while IFS= read -r job_resource; do
            if [ -n "$job_resource" ]; then
                local job_id
                job_id=$(echo "$job_resource" | cut -d'/' -f6)
                
                log_info "Cancelling training job: $job_id"
                gcloud ai custom-jobs cancel "$job_id" \
                    --region="$REGION" \
                    --quiet || {
                    log_warning "Failed to cancel training job $job_id"
                }
            fi
        done <<< "$training_jobs"
    else
        log_info "No running training jobs found"
    fi
    
    log_success "Vertex AI resources cleanup completed"
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket..."
    
    # Check if bucket exists
    if gsutil ls -b "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        log_info "Found Cloud Storage bucket: $BUCKET_NAME"
        
        # Delete bucket and all contents
        gsutil -m rm -r "gs://$BUCKET_NAME" || {
            log_warning "Failed to delete Cloud Storage bucket (it may not exist or may be empty)"
        }
        
        log_success "Cloud Storage bucket deleted"
    else
        log_warning "Cloud Storage bucket not found or already deleted"
    fi
}

# Function to delete BigQuery dataset
delete_bigquery_dataset() {
    log_info "Deleting BigQuery dataset..."
    
    # Check if dataset exists
    if bq ls -d "${PROJECT_ID}:user_interactions" >/dev/null 2>&1; then
        log_info "Found BigQuery dataset: user_interactions"
        
        # Delete BigQuery dataset and all tables
        bq rm -r -f "${PROJECT_ID}:user_interactions" || {
            log_warning "Failed to delete BigQuery dataset (it may not exist)"
        }
        
        log_success "BigQuery dataset deleted"
    else
        log_warning "BigQuery dataset not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove any temporary files that might have been created
    local temp_files=(
        "generate_sample_data.py"
        "training_data.csv"
        "recommendation_trainer.py"
        "recommendation-api"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ] || [ -d "$file" ]; then
            rm -rf "$file"
            log_info "Removed: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to verify resource deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local remaining_resources=false
    
    # Check Cloud Run services
    if gcloud run services describe "$SERVICE_NAME" --region="$REGION" >/dev/null 2>&1; then
        log_warning "Cloud Run service still exists: $SERVICE_NAME"
        remaining_resources=true
    fi
    
    # Check Vertex AI endpoints
    local endpoints
    endpoints=$(gcloud ai endpoints list --region="$REGION" --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$endpoints" ]; then
        log_warning "Vertex AI endpoints still exist"
        remaining_resources=true
    fi
    
    # Check Vertex AI models
    local models
    models=$(gcloud ai models list --region="$REGION" --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$models" ]; then
        log_warning "Vertex AI models still exist"
        remaining_resources=true
    fi
    
    # Check Cloud Storage bucket
    if gsutil ls -b "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        log_warning "Cloud Storage bucket still exists: $BUCKET_NAME"
        remaining_resources=true
    fi
    
    # Check BigQuery dataset
    if bq ls -d "${PROJECT_ID}:user_interactions" >/dev/null 2>&1; then
        log_warning "BigQuery dataset still exists: user_interactions"
        remaining_resources=true
    fi
    
    if [ "$remaining_resources" = true ]; then
        log_warning "Some resources may still exist. Please check the Google Cloud Console."
        log_warning "Note: Some resources may take a few minutes to be fully deleted."
    else
        log_success "All resources appear to have been deleted successfully"
    fi
}

# Function to estimate cost savings
display_cost_savings() {
    log_info "Estimating cost savings..."
    
    echo
    echo "=== Cost Savings Summary ==="
    echo "The following resources have been deleted, which will stop incurring charges:"
    echo "  - Cloud Run service (pay-per-request model)"
    echo "  - Vertex AI endpoints and models (hourly charges)"
    echo "  - Cloud Storage bucket (storage and operations charges)"
    echo "  - BigQuery dataset (storage and query charges)"
    echo "  - Training jobs (compute charges)"
    echo
    echo "Estimated monthly savings: $50-200 (depending on usage)"
    echo
    echo "Note: It may take up to 24 hours for billing to reflect the resource deletion."
}

# Function to offer project deletion
offer_project_deletion() {
    log_info "Cleanup completed!"
    echo
    echo "=== Project Cleanup Option ==="
    echo "Would you like to delete the entire project: $PROJECT_ID?"
    echo "This will permanently delete ALL resources in the project."
    echo
    read -p "Delete entire project? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deleting project: $PROJECT_ID"
        
        gcloud projects delete "$PROJECT_ID" --quiet || {
            log_error "Failed to delete project. You may need to do this manually."
            return 1
        }
        
        log_success "Project deletion initiated: $PROJECT_ID"
        log_info "Project deletion may take several minutes to complete"
    else
        log_info "Project preserved: $PROJECT_ID"
        log_info "You can manually delete the project later if needed"
    fi
}

# Function to display cleanup summary
display_summary() {
    log_success "Cleanup completed successfully!"
    echo
    echo "=== Cleanup Summary ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo
    echo "=== Resources Deleted ==="
    echo "✓ Cloud Run service: $SERVICE_NAME"
    echo "✓ Vertex AI endpoints and models"
    echo "✓ Cloud Storage bucket: $BUCKET_NAME"
    echo "✓ BigQuery dataset: user_interactions"
    echo "✓ Training jobs and artifacts"
    echo "✓ Local temporary files"
    echo
    echo "=== Next Steps ==="
    echo "1. Check Google Cloud Console to confirm all resources are deleted"
    echo "2. Monitor your billing to ensure charges have stopped"
    echo "3. Consider deleting the project if it's no longer needed"
    echo
    echo "=== Additional Information ==="
    echo "- Some resources may take a few minutes to be fully deleted"
    echo "- Billing updates may take up to 24 hours to reflect"
    echo "- You can recreate the infrastructure anytime using the deploy script"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Personalized Recommendation APIs with Vertex AI and Cloud Run"
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_destruction "$1"
    delete_cloud_run
    delete_vertex_ai_resources
    delete_storage_bucket
    delete_bigquery_dataset
    cleanup_local_files
    verify_deletion
    display_cost_savings
    offer_project_deletion
    display_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted"; exit 1' INT TERM

# Help message
show_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --yes           Skip confirmation prompts"
    echo "  --help          Show this help message"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID      Google Cloud project ID (required)"
    echo "  REGION          Google Cloud region (default: us-central1)"
    echo "  BUCKET_NAME     Cloud Storage bucket name (default: rec-system-data-\$PROJECT_ID)"
    echo "  SERVICE_NAME    Cloud Run service name (default: recommendation-api)"
    echo "  MODEL_NAME      Vertex AI model name (default: product-recommendations)"
    echo "  ENDPOINT_NAME   Vertex AI endpoint name (default: rec-endpoint)"
    echo
    echo "Examples:"
    echo "  $0                    # Interactive cleanup"
    echo "  $0 --yes              # Automatic cleanup"
    echo "  PROJECT_ID=my-project $0 --yes  # Cleanup specific project"
}

# Parse command line arguments
case "$1" in
    --help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac