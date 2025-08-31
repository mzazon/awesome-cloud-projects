#!/bin/bash

# Smart City Infrastructure Monitoring with IoT and AI - Cleanup Script
# This script safely removes all GCP resources created for smart city monitoring
# including Pub/Sub, BigQuery, Vertex AI, Cloud Functions, and monitoring components

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
    log_error "Cleanup failed at line $1. Some resources may still exist."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Banner
echo "======================================================================"
echo "  Smart City Infrastructure Monitoring - Cleanup Script"
echo "  Provider: Google Cloud Platform"
echo "  Recipe: smart-city-infrastructure-monitoring-iot-ai"
echo "======================================================================"

# Check if running with dry-run flag
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    log_warning "Running in DRY-RUN mode - no resources will be deleted"
fi

# Check if running with force flag (skip confirmations)
FORCE=${FORCE:-false}

# Function to execute or simulate commands
execute_cmd() {
    local cmd="$1"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        log_info "Executing: $cmd"
        eval "$cmd" || {
            log_warning "Command failed but continuing cleanup: $cmd"
            return 0
        }
    fi
}

# Get confirmation from user
confirm_destruction() {
    if [ "$FORCE" = "true" ]; then
        log_warning "FORCE mode enabled - skipping confirmation prompts"
        return 0
    fi
    
    echo ""
    log_warning "This will PERMANENTLY DELETE all Smart City Infrastructure Monitoring resources!"
    echo ""
    echo "Resources to be deleted:"
    echo "  🗄️  BigQuery datasets and all data"
    echo "  📡 Pub/Sub topics and subscriptions"
    echo "  🤖 Vertex AI datasets and models"
    echo "  ☁️  Cloud Functions"
    echo "  📊 Cloud Monitoring dashboards and alerts"
    echo "  🗂️  Cloud Storage buckets and all contents"
    echo "  🔑 Service accounts and keys"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [[ $confirmation != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Type 'DELETE' to confirm permanent resource deletion: " final_confirmation
    
    if [[ $final_confirmation != "DELETE" ]]; then
        log_info "Cleanup cancelled - confirmation failed"
        exit 0
    fi
    
    log_warning "Proceeding with resource deletion..."
}

# Check prerequisites and load configuration
check_prerequisites() {
    log_info "Checking prerequisites and loading configuration..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if required utilities are available
    for cmd in bq gsutil; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd is not available. Please ensure Google Cloud SDK is fully installed."
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Load environment variables
load_environment_variables() {
    log_info "Loading environment variables..."
    
    # Try to load from deployment info file
    if [ -f "deployment_info.txt" ] && [ "$DRY_RUN" != "true" ]; then
        log_info "Loading configuration from deployment_info.txt..."
        
        export PROJECT_ID=$(grep "Project ID:" deployment_info.txt | cut -d' ' -f3)
        export DATASET_NAME=$(grep "BigQuery Dataset:" deployment_info.txt | cut -d' ' -f3)
        export BUCKET_NAME=$(grep "Cloud Storage Bucket:" deployment_info.txt | cut -d' ' -f4)
        export SERVICE_ACCOUNT_NAME=$(grep "Service Account:" deployment_info.txt | cut -d' ' -f3)
        export TOPIC_NAME=$(grep "Pub/Sub Topic:" deployment_info.txt | cut -d' ' -f3)
    fi
    
    # Fallback to environment variables or defaults
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
    export REGION="${REGION:-us-central1}"
    export DATASET_NAME="${DATASET_NAME:-smart_city_data}"
    export TOPIC_NAME="${TOPIC_NAME:-sensor-telemetry}"
    
    # Validate required variables
    if [ -z "$PROJECT_ID" ]; then
        log_error "PROJECT_ID not found. Please set PROJECT_ID environment variable or run from deployment directory."
        exit 1
    fi
    
    log_info "Configuration loaded:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Dataset: $DATASET_NAME"
    log_info "  Topic: $TOPIC_NAME"
    
    # Set gcloud project
    gcloud config set project "$PROJECT_ID" 2>/dev/null || true
}

# Remove Vertex AI resources
cleanup_vertex_ai() {
    log_info "Cleaning up Vertex AI resources..."
    
    # List and delete Vertex AI datasets
    if [ "$DRY_RUN" != "true" ]; then
        datasets=$(gcloud ai datasets list --region="$REGION" --format="value(name)" --filter="displayName:smart-city" 2>/dev/null || true)
        for dataset in $datasets; do
            if [ -n "$dataset" ]; then
                execute_cmd "gcloud ai datasets delete $dataset --region=$REGION --quiet"
            fi
        done
    else
        execute_cmd "gcloud ai datasets list --region=$REGION --format='value(name)' --filter='displayName:smart-city' | xargs -I {} gcloud ai datasets delete {} --region=$REGION --quiet"
    fi
    
    # Clean up any training jobs
    if [ "$DRY_RUN" != "true" ]; then
        jobs=$(gcloud ai custom-jobs list --region="$REGION" --format="value(name)" --filter="displayName:smart-city" 2>/dev/null || true)
        for job in $jobs; do
            if [ -n "$job" ]; then
                execute_cmd "gcloud ai custom-jobs cancel $job --region=$REGION --quiet"
            fi
        done
    else
        execute_cmd "gcloud ai custom-jobs list --region=$REGION --format='value(name)' --filter='displayName:smart-city' | xargs -I {} gcloud ai custom-jobs cancel {} --region=$REGION --quiet"
    fi
    
    # Clean up models
    if [ "$DRY_RUN" != "true" ]; then
        models=$(gcloud ai models list --region="$REGION" --format="value(name)" --filter="displayName:city-sensor" 2>/dev/null || true)
        for model in $models; do
            if [ -n "$model" ]; then
                execute_cmd "gcloud ai models delete $model --region=$REGION --quiet"
            fi
        done
    else
        execute_cmd "gcloud ai models list --region=$REGION --format='value(name)' --filter='displayName:city-sensor' | xargs -I {} gcloud ai models delete {} --region=$REGION --quiet"
    fi
    
    log_success "Vertex AI resources cleaned up"
}

# Remove Cloud Functions
cleanup_cloud_functions() {
    log_info "Cleaning up Cloud Functions..."
    
    # Delete the sensor data processing function
    execute_cmd "gcloud functions delete process-sensor-data --region=$REGION --quiet"
    
    # Clean up local function code directory
    if [ -d "sensor-processor" ] && [ "$DRY_RUN" != "true" ]; then
        rm -rf sensor-processor/
        log_info "Removed local function code directory"
    fi
    
    log_success "Cloud Functions cleaned up"
}

# Remove Cloud Monitoring resources
cleanup_monitoring() {
    log_info "Cleaning up Cloud Monitoring resources..."
    
    # Remove monitoring dashboards
    if [ "$DRY_RUN" != "true" ]; then
        dashboards=$(gcloud monitoring dashboards list --format="value(name)" --filter="displayName:Smart City" 2>/dev/null || true)
        for dashboard in $dashboards; do
            if [ -n "$dashboard" ]; then
                execute_cmd "gcloud monitoring dashboards delete $dashboard --quiet"
            fi
        done
    else
        execute_cmd "gcloud monitoring dashboards list --format='value(name)' --filter='displayName:Smart City' | xargs -I {} gcloud monitoring dashboards delete {} --quiet"
    fi
    
    # Remove alert policies
    if [ "$DRY_RUN" != "true" ]; then
        policies=$(gcloud alpha monitoring policies list --format="value(name)" --filter="displayName:Smart City" 2>/dev/null || true)
        for policy in $policies; do
            if [ -n "$policy" ]; then
                execute_cmd "gcloud alpha monitoring policies delete $policy --quiet"
            fi
        done
    else
        execute_cmd "gcloud alpha monitoring policies list --format='value(name)' --filter='displayName:Smart City' | xargs -I {} gcloud alpha monitoring policies delete {} --quiet"
    fi
    
    # Clean up local monitoring configuration files
    if [ "$DRY_RUN" != "true" ]; then
        for file in smart_city_dashboard.json anomaly_alert_policy.json; do
            if [ -f "$file" ]; then
                rm "$file"
                log_info "Removed $file"
            fi
        done
    fi
    
    log_success "Cloud Monitoring resources cleaned up"
}

# Remove Cloud Storage resources
cleanup_storage() {
    log_info "Cleaning up Cloud Storage resources..."
    
    # Find and remove buckets with the smart-city-ml prefix
    if [ -n "${BUCKET_NAME:-}" ]; then
        execute_cmd "gsutil -m rm -r gs://$BUCKET_NAME"
    else
        # Fallback: find buckets by prefix
        if [ "$DRY_RUN" != "true" ]; then
            buckets=$(gsutil ls -p "$PROJECT_ID" | grep "smart-city-ml-" || true)
            for bucket in $buckets; do
                if [ -n "$bucket" ]; then
                    bucket_name=${bucket%/}  # Remove trailing slash
                    execute_cmd "gsutil -m rm -r $bucket_name"
                fi
            done
        else
            execute_cmd "gsutil ls -p $PROJECT_ID | grep 'smart-city-ml-' | xargs -I {} gsutil -m rm -r {}"
        fi
    fi
    
    # Clean up local files
    if [ "$DRY_RUN" != "true" ]; then
        for file in prepare_training_data.py lifecycle.json; do
            if [ -f "$file" ]; then
                rm "$file"
                log_info "Removed $file"
            fi
        done
    fi
    
    log_success "Cloud Storage resources cleaned up"
}

# Remove BigQuery resources
cleanup_bigquery() {
    log_info "Cleaning up BigQuery resources..."
    
    # Delete BigQuery dataset and all tables
    execute_cmd "bq rm -r -f ${PROJECT_ID}:${DATASET_NAME}"
    
    log_success "BigQuery resources cleaned up"
}

# Remove Pub/Sub resources
cleanup_pubsub() {
    log_info "Cleaning up Pub/Sub resources..."
    
    # Delete Pub/Sub subscriptions first (dependencies)
    local subscriptions=(
        "${TOPIC_NAME}-bigquery"
        "${TOPIC_NAME}-ml"
        "${TOPIC_NAME}-dlq-sub"
    )
    
    for subscription in "${subscriptions[@]}"; do
        execute_cmd "gcloud pubsub subscriptions delete $subscription --quiet"
    done
    
    # Delete Pub/Sub topics
    local topics=(
        "$TOPIC_NAME"
        "${TOPIC_NAME}-dlq"
    )
    
    for topic in "${topics[@]}"; do
        execute_cmd "gcloud pubsub topics delete $topic --quiet"
    done
    
    log_success "Pub/Sub resources cleaned up"
}

# Remove IAM resources
cleanup_iam() {
    log_info "Cleaning up IAM resources..."
    
    # Find service accounts with the city-sensors prefix
    if [ -n "${SERVICE_ACCOUNT_NAME:-}" ]; then
        execute_cmd "gcloud iam service-accounts delete ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --quiet"
    else
        # Fallback: find service accounts by pattern
        if [ "$DRY_RUN" != "true" ]; then
            service_accounts=$(gcloud iam service-accounts list --format="value(email)" --filter="email:city-sensors-*" 2>/dev/null || true)
            for sa in $service_accounts; do
                if [ -n "$sa" ]; then
                    execute_cmd "gcloud iam service-accounts delete $sa --quiet"
                fi
            done
        else
            execute_cmd "gcloud iam service-accounts list --format='value(email)' --filter='email:city-sensors-*' | xargs -I {} gcloud iam service-accounts delete {} --quiet"
        fi
    fi
    
    # Clean up local service account key
    if [ -f "sensor-key.json" ] && [ "$DRY_RUN" != "true" ]; then
        rm sensor-key.json
        log_info "Removed local service account key file"
    fi
    
    log_success "IAM resources cleaned up"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [ "$DRY_RUN" != "true" ]; then
        local files=(
            "deployment_info.txt"
            "test_sensor_payload.json"
            "sensor-key.json"
            "smart_city_dashboard.json"
            "anomaly_alert_policy.json"
            "prepare_training_data.py"
            "lifecycle.json"
        )
        
        for file in "${files[@]}"; do
            if [ -f "$file" ]; then
                rm "$file"
                log_info "Removed $file"
            fi
        done
        
        # Remove sensor-processor directory if it exists
        if [ -d "sensor-processor" ]; then
            rm -rf sensor-processor/
            log_info "Removed sensor-processor/ directory"
        fi
    fi
    
    log_success "Local files cleaned up"
}

# Validate cleanup
validate_cleanup() {
    log_info "Validating cleanup completion..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_success "DRY-RUN mode - skipping validation"
        return
    fi
    
    local cleanup_issues=0
    
    # Check if Pub/Sub topics still exist
    if gcloud pubsub topics describe "$TOPIC_NAME" &> /dev/null; then
        log_warning "Pub/Sub topic still exists: $TOPIC_NAME"
        ((cleanup_issues++))
    fi
    
    # Check if BigQuery dataset still exists
    if bq show "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log_warning "BigQuery dataset still exists: $DATASET_NAME"
        ((cleanup_issues++))
    fi
    
    # Check if Cloud Function still exists
    if gcloud functions describe process-sensor-data --region="$REGION" &> /dev/null; then
        log_warning "Cloud Function still exists: process-sensor-data"
        ((cleanup_issues++))
    fi
    
    # Check for remaining storage buckets
    if gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -q "smart-city-ml-"; then
        log_warning "Smart City storage buckets may still exist"
        ((cleanup_issues++))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log_success "Cleanup validation passed - no remaining resources detected"
    else
        log_warning "Cleanup validation found $cleanup_issues potential issues"
        log_info "Some resources may take time to be fully deleted or may require manual removal"
    fi
}

# Optional: Delete the entire project
offer_project_deletion() {
    if [ "$FORCE" = "true" ] || [ "$DRY_RUN" = "true" ]; then
        return
    fi
    
    echo ""
    log_info "All Smart City Infrastructure Monitoring resources have been cleaned up."
    echo ""
    read -p "Do you want to delete the entire project '$PROJECT_ID'? (yes/no): " delete_project
    
    if [[ $delete_project == "yes" ]]; then
        echo ""
        log_warning "This will PERMANENTLY DELETE the entire project and ALL its contents!"
        read -p "Type the project ID '$PROJECT_ID' to confirm: " project_confirmation
        
        if [[ $project_confirmation == "$PROJECT_ID" ]]; then
            log_info "Deleting project $PROJECT_ID..."
            gcloud projects delete "$PROJECT_ID" --quiet
            log_success "Project deletion initiated. This may take several minutes to complete."
        else
            log_info "Project deletion cancelled - confirmation failed"
        fi
    else
        log_info "Project preserved. You can delete it later with: gcloud projects delete $PROJECT_ID"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Smart City Infrastructure Monitoring cleanup..."
    
    check_prerequisites
    load_environment_variables
    confirm_destruction
    
    # Execute cleanup in reverse order of creation
    cleanup_vertex_ai
    cleanup_cloud_functions
    cleanup_monitoring
    cleanup_storage
    cleanup_bigquery
    cleanup_pubsub
    cleanup_iam
    cleanup_local_files
    
    validate_cleanup
    
    echo ""
    echo "======================================================================"
    log_success "Smart City Infrastructure Monitoring cleanup completed!"
    echo "======================================================================"
    echo ""
    
    offer_project_deletion
    
    log_info "Cleanup process finished."
    echo ""
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi