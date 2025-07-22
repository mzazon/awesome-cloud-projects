#!/bin/bash

# AI-Powered Cost Analytics with BigQuery Analytics Hub and Vertex AI - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Colors for output
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Check if dry run mode is enabled
DRY_RUN=${DRY_RUN:-false}
if [[ "$DRY_RUN" == "true" ]]; then
    warning "Running in DRY RUN mode - no actual resources will be deleted"
fi

# Function to execute commands (supports dry run)
execute() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would execute: $*"
    else
        eval "$@"
    fi
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Command '$1' is not installed. Please install it before running this script."
    fi
}

# Function to check if gcloud is authenticated
check_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        error "No active gcloud authentication found. Please run 'gcloud auth login' first."
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites for cleanup..."
    
    # Check required commands
    check_command "gcloud"
    check_command "bq"
    check_command "gsutil"
    
    # Check gcloud authentication
    check_auth
    
    # Validate required environment variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        error "PROJECT_ID environment variable is required. Please set it before running cleanup."
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        export REGION="us-central1"
        warning "REGION not set, using default: ${REGION}"
    fi
    
    success "Prerequisites validated"
}

# Function to set up environment variables from deployment
setup_environment() {
    log "Setting up environment variables for cleanup..."
    
    # Export core variables
    export ZONE="${ZONE:-${REGION}-a}"
    export DATASET_ID="${DATASET_ID:-cost_analytics}"
    export EXCHANGE_ID="${EXCHANGE_ID:-cost_data_exchange}"
    
    # Resource names - these should match the deployment script
    export BUCKET_NAME="${BUCKET_NAME:-}"
    export MODEL_NAME="${MODEL_NAME:-}"
    export ENDPOINT_NAME="${ENDPOINT_NAME:-}"
    
    # If specific resource names aren't provided, try to discover them
    if [[ -z "$BUCKET_NAME" && "$DRY_RUN" != "true" ]]; then
        log "Discovering storage bucket..."
        BUCKET_NAME=$(gsutil ls -p "${PROJECT_ID}" | grep "cost-analytics-data-" | head -n1 | sed 's|gs://||' | sed 's|/||' || true)
    fi
    
    if [[ -z "$MODEL_NAME" && "$DRY_RUN" != "true" ]]; then
        log "Discovering Vertex AI model..."
        MODEL_NAME=$(gcloud ai models list --region="${REGION}" --filter="displayName~cost-prediction-model" --format="value(displayName)" | head -n1 || true)
    fi
    
    if [[ -z "$ENDPOINT_NAME" && "$DRY_RUN" != "true" ]]; then
        log "Discovering Vertex AI endpoint..."
        ENDPOINT_NAME=$(gcloud ai endpoints list --region="${REGION}" --filter="displayName~cost-prediction-endpoint" --format="value(displayName)" | head -n1 || true)
    fi
    
    # Set gcloud defaults
    execute gcloud config set project "${PROJECT_ID}"
    execute gcloud config set compute/region "${REGION}"
    execute gcloud config set compute/zone "${ZONE}"
    
    log "Environment variables configured:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  DATASET_ID: ${DATASET_ID}"
    log "  BUCKET_NAME: ${BUCKET_NAME:-'not found'}"
    log "  MODEL_NAME: ${MODEL_NAME:-'not found'}"
    log "  ENDPOINT_NAME: ${ENDPOINT_NAME:-'not found'}"
    
    success "Environment setup complete"
}

# Function to confirm destructive actions
confirm_destruction() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry run mode - skipping confirmation"
        return
    fi
    
    warning "This will permanently delete the following resources:"
    warning "  - BigQuery dataset: ${PROJECT_ID}:${DATASET_ID} (including all tables and views)"
    warning "  - Analytics Hub exchange: ${EXCHANGE_ID}"
    warning "  - Vertex AI model: ${MODEL_NAME:-'auto-detected'}"
    warning "  - Vertex AI endpoint: ${ENDPOINT_NAME:-'auto-detected'}"
    warning "  - Cloud Storage bucket: gs://${BUCKET_NAME:-'auto-detected'}"
    warning "  - Cloud Monitoring alert policies"
    warning ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Confirmation received - proceeding with cleanup"
}

# Function to clean up Vertex AI resources
cleanup_vertex_ai() {
    log "Cleaning up Vertex AI resources..."
    
    if [[ -n "$ENDPOINT_NAME" ]]; then
        # Get endpoint ID
        if [[ "$DRY_RUN" != "true" ]]; then
            ENDPOINT_ID=$(gcloud ai endpoints list \
                --region="${REGION}" \
                --filter="displayName:${ENDPOINT_NAME}" \
                --format="value(name)" | cut -d'/' -f6 || true)
        else
            ENDPOINT_ID="endpoint-id-placeholder"
        fi
        
        if [[ -n "$ENDPOINT_ID" ]]; then
            log "Undeploying model from endpoint: ${ENDPOINT_ID}..."
            
            # Get deployed model ID
            if [[ "$DRY_RUN" != "true" ]]; then
                DEPLOYED_MODEL_ID=$(gcloud ai endpoints describe "${ENDPOINT_ID}" \
                    --region="${REGION}" \
                    --format="value(deployedModels[0].id)" 2>/dev/null || true)
            else
                DEPLOYED_MODEL_ID="deployed-model-id-placeholder"
            fi
            
            if [[ -n "$DEPLOYED_MODEL_ID" ]]; then
                execute gcloud ai endpoints undeploy-model "${ENDPOINT_ID}" \
                    --region="${REGION}" \
                    --deployed-model-id="${DEPLOYED_MODEL_ID}" \
                    --quiet
            fi
            
            # Delete endpoint
            log "Deleting endpoint: ${ENDPOINT_ID}..."
            execute gcloud ai endpoints delete "${ENDPOINT_ID}" \
                --region="${REGION}" \
                --quiet
        fi
    else
        warning "Endpoint name not found - checking for any cost prediction endpoints..."
        if [[ "$DRY_RUN" != "true" ]]; then
            gcloud ai endpoints list --region="${REGION}" --filter="displayName~cost-prediction" --format="value(name)" | while read -r endpoint_resource; do
                if [[ -n "$endpoint_resource" ]]; then
                    endpoint_id=$(echo "$endpoint_resource" | cut -d'/' -f6)
                    log "Found endpoint to delete: ${endpoint_id}"
                    execute gcloud ai endpoints delete "${endpoint_id}" --region="${REGION}" --quiet
                fi
            done
        fi
    fi
    
    if [[ -n "$MODEL_NAME" ]]; then
        # Get model ID
        if [[ "$DRY_RUN" != "true" ]]; then
            MODEL_ID=$(gcloud ai models list \
                --region="${REGION}" \
                --filter="displayName:${MODEL_NAME}" \
                --format="value(name)" | cut -d'/' -f6 || true)
        else
            MODEL_ID="model-id-placeholder"
        fi
        
        if [[ -n "$MODEL_ID" ]]; then
            log "Deleting model: ${MODEL_ID}..."
            execute gcloud ai models delete "${MODEL_ID}" \
                --region="${REGION}" \
                --quiet
        fi
    else
        warning "Model name not found - checking for any cost prediction models..."
        if [[ "$DRY_RUN" != "true" ]]; then
            gcloud ai models list --region="${REGION}" --filter="displayName~cost-prediction" --format="value(name)" | while read -r model_resource; do
                if [[ -n "$model_resource" ]]; then
                    model_id=$(echo "$model_resource" | cut -d'/' -f6)
                    log "Found model to delete: ${model_id}"
                    execute gcloud ai models delete "${model_id}" --region="${REGION}" --quiet
                fi
            done
        fi
    fi
    
    success "Vertex AI resources cleaned up"
}

# Function to clean up BigQuery resources
cleanup_bigquery() {
    log "Cleaning up BigQuery resources..."
    
    # Check if dataset exists before trying to delete
    if [[ "$DRY_RUN" != "true" ]]; then
        if bq ls "${PROJECT_ID}:${DATASET_ID}" &>/dev/null; then
            log "Dataset ${DATASET_ID} exists, proceeding with cleanup..."
        else
            warning "Dataset ${DATASET_ID} not found, skipping BigQuery cleanup"
            return
        fi
    fi
    
    # Delete Analytics Hub listing and exchange first
    log "Removing Analytics Hub exchange and listings..."
    
    # Check if exchange exists
    if [[ "$DRY_RUN" != "true" ]]; then
        if bq ls --data_exchange --location="${REGION}" | grep -q "${EXCHANGE_ID}"; then
            execute bq rm --data_exchange --location="${REGION}" \
                "${PROJECT_ID}:${EXCHANGE_ID}" \
                --quiet
        else
            warning "Analytics Hub exchange ${EXCHANGE_ID} not found"
        fi
    else
        execute bq rm --data_exchange --location="${REGION}" \
            "${PROJECT_ID}:${EXCHANGE_ID}" \
            --quiet
    fi
    
    # Delete dataset and all tables/views
    log "Deleting BigQuery dataset and all resources..."
    execute bq rm -r -f "${PROJECT_ID}:${DATASET_ID}"
    
    success "BigQuery resources deleted"
}

# Function to clean up Cloud Storage
cleanup_storage() {
    log "Cleaning up Cloud Storage resources..."
    
    if [[ -n "$BUCKET_NAME" ]]; then
        # Check if bucket exists
        if [[ "$DRY_RUN" != "true" ]]; then
            if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
                log "Bucket gs://${BUCKET_NAME} exists, deleting..."
                execute gsutil -m rm -r "gs://${BUCKET_NAME}"
            else
                warning "Bucket gs://${BUCKET_NAME} not found"
            fi
        else
            execute gsutil -m rm -r "gs://${BUCKET_NAME}"
        fi
    else
        warning "Bucket name not provided - checking for cost analytics buckets..."
        if [[ "$DRY_RUN" != "true" ]]; then
            gsutil ls -p "${PROJECT_ID}" | grep "cost-analytics-data-" | while read -r bucket_uri; do
                log "Found bucket to delete: ${bucket_uri}"
                execute gsutil -m rm -r "${bucket_uri}"
            done
        fi
    fi
    
    success "Cloud Storage resources cleaned up"
}

# Function to clean up Cloud Monitoring
cleanup_monitoring() {
    log "Cleaning up Cloud Monitoring alert policies..."
    
    # Find and delete cost anomaly alert policies
    if [[ "$DRY_RUN" != "true" ]]; then
        gcloud alpha monitoring policies list \
            --filter="displayName:'High Cost Anomaly Alert'" \
            --format="value(name)" | while read -r policy_name; do
                if [[ -n "$policy_name" ]]; then
                    log "Deleting alert policy: ${policy_name}"
                    execute gcloud alpha monitoring policies delete "${policy_name}" --quiet
                fi
            done
    else
        execute gcloud alpha monitoring policies list \
            --filter="displayName:'High Cost Anomaly Alert'" \
            --format="value(name)"
    fi
    
    success "Cloud Monitoring resources cleaned up"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local temporary files..."
    
    # Remove any temporary files that might have been created
    local temp_files=(
        "/tmp/cost_alert_policy.json"
        "cost_alert_policy.json"
        "prediction_input.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            execute rm -f "$file"
            log "Removed temporary file: $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup completion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Dry run cleanup validation complete"
        return
    fi
    
    local cleanup_issues=0
    
    # Check BigQuery dataset
    if bq ls "${PROJECT_ID}:${DATASET_ID}" &>/dev/null; then
        error "BigQuery dataset still exists: ${PROJECT_ID}:${DATASET_ID}"
        ((cleanup_issues++))
    else
        success "BigQuery dataset successfully deleted"
    fi
    
    # Check Cloud Storage bucket
    if [[ -n "$BUCKET_NAME" ]] && gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        error "Cloud Storage bucket still exists: gs://${BUCKET_NAME}"
        ((cleanup_issues++))
    else
        success "Cloud Storage bucket successfully deleted"
    fi
    
    # Check Vertex AI resources
    local remaining_models
    remaining_models=$(gcloud ai models list --region="${REGION}" --filter="displayName~cost-prediction" --format="value(displayName)" | wc -l)
    if [[ "$remaining_models" -gt 0 ]]; then
        warning "${remaining_models} Vertex AI model(s) still exist"
        ((cleanup_issues++))
    else
        success "Vertex AI models successfully deleted"
    fi
    
    local remaining_endpoints
    remaining_endpoints=$(gcloud ai endpoints list --region="${REGION}" --filter="displayName~cost-prediction" --format="value(displayName)" | wc -l)
    if [[ "$remaining_endpoints" -gt 0 ]]; then
        warning "${remaining_endpoints} Vertex AI endpoint(s) still exist"
        ((cleanup_issues++))
    else
        success "Vertex AI endpoints successfully deleted"
    fi
    
    if [[ "$cleanup_issues" -eq 0 ]]; then
        success "Cleanup validation completed successfully"
    else
        warning "Cleanup completed with ${cleanup_issues} issues that may require manual intervention"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "=== CLEANUP SUMMARY ==="
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log ""
    log "Resources cleaned up:"
    log "✅ BigQuery dataset: ${PROJECT_ID}:${DATASET_ID}"
    log "✅ Analytics Hub exchange: ${EXCHANGE_ID}"
    log "✅ Vertex AI models and endpoints"
    log "✅ Cloud Storage bucket: gs://${BUCKET_NAME:-'auto-detected'}"
    log "✅ Cloud Monitoring alert policies"
    log "✅ Local temporary files"
    log ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "This was a DRY RUN - no actual resources were deleted"
        log "To perform actual cleanup, run: DRY_RUN=false ./destroy.sh"
    else
        success "AI-Powered Cost Analytics cleanup completed successfully!"
        log ""
        log "Note: Some resources may take a few minutes to be fully deleted."
        log "If you encounter any issues, you may need to manually delete remaining resources."
    fi
}

# Main cleanup function
main() {
    log "Starting AI-Powered Cost Analytics cleanup..."
    log "=== AI-POWERED COST ANALYTICS CLEANUP ==="
    
    validate_prerequisites
    setup_environment
    confirm_destruction
    cleanup_vertex_ai
    cleanup_bigquery
    cleanup_storage
    cleanup_monitoring
    cleanup_local_files
    validate_cleanup
    display_summary
}

# Handle script interruption
trap 'error "Cleanup script interrupted. Some resources may still exist."' INT TERM

# Run main function
main "$@"