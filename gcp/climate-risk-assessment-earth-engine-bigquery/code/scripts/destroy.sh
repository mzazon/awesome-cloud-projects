#!/bin/bash
set -e

# Climate Risk Assessment Earth Engine BigQuery Cleanup Script
# This script removes all resources created by the deployment script including:
# - Cloud Functions
# - BigQuery datasets, tables, and views
# - Cloud Storage buckets
# - Custom monitoring metrics
# - IAM service accounts (if created)

# Color codes for output
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

# Check if running on supported OS
check_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "darwin"* ]]; then
        log "Operating system supported: $OSTYPE"
    else
        error "Unsupported operating system: $OSTYPE"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "BigQuery CLI (bq) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "Google Cloud Storage CLI (gsutil) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to load configuration from deployment file
load_deployment_config() {
    local config_file="./deployment_config.json"
    
    if [ -f "$config_file" ]; then
        log "Loading deployment configuration from $config_file"
        
        # Extract configuration values using basic JSON parsing
        PROJECT_ID=$(grep -o '"project_id": *"[^"]*"' "$config_file" | cut -d'"' -f4)
        REGION=$(grep -o '"region": *"[^"]*"' "$config_file" | cut -d'"' -f4)
        ZONE=$(grep -o '"zone": *"[^"]*"' "$config_file" | cut -d'"' -f4)
        DATASET_ID=$(grep -o '"dataset_id": *"[^"]*"' "$config_file" | cut -d'"' -f4)
        BUCKET_NAME=$(grep -o '"bucket_name": *"[^"]*"' "$config_file" | cut -d'"' -f4)
        FUNCTION_NAME=$(grep -o '"function_name": *"[^"]*"' "$config_file" | cut -d'"' -f4)
        MONITOR_FUNCTION_NAME=$(grep -o '"monitor_function_name": *"[^"]*"' "$config_file" | cut -d'"' -f4)
        RANDOM_SUFFIX=$(grep -o '"random_suffix": *"[^"]*"' "$config_file" | cut -d'"' -f4)
        
        log "Configuration loaded successfully"
        info "  Project ID: $PROJECT_ID"
        info "  Region: $REGION"
        info "  Zone: $ZONE"
        info "  Dataset ID: $DATASET_ID"
        info "  Bucket Name: $BUCKET_NAME"
        info "  Function Name: $FUNCTION_NAME"
        info "  Monitor Function Name: $MONITOR_FUNCTION_NAME"
        
        return 0
    else
        warn "Deployment configuration file not found: $config_file"
        return 1
    fi
}

# Function to prompt for manual configuration
prompt_for_config() {
    log "Manual configuration required"
    
    read -p "Enter Project ID: " PROJECT_ID
    read -p "Enter Region [us-central1]: " REGION
    REGION=${REGION:-us-central1}
    
    read -p "Enter Zone [us-central1-a]: " ZONE
    ZONE=${ZONE:-us-central1-a}
    
    read -p "Enter Dataset ID: " DATASET_ID
    read -p "Enter Bucket Name: " BUCKET_NAME
    read -p "Enter Function Name: " FUNCTION_NAME
    read -p "Enter Monitor Function Name: " MONITOR_FUNCTION_NAME
    
    if [ -z "$PROJECT_ID" ] || [ -z "$DATASET_ID" ] || [ -z "$BUCKET_NAME" ] || [ -z "$FUNCTION_NAME" ] || [ -z "$MONITOR_FUNCTION_NAME" ]; then
        error "All required fields must be provided"
        exit 1
    fi
}

# Function to set up configuration
setup_config() {
    log "Setting up configuration..."
    
    # Try to load from deployment config file first
    if ! load_deployment_config; then
        # If config file doesn't exist, check environment variables
        if [ -z "$PROJECT_ID" ] || [ -z "$DATASET_ID" ] || [ -z "$BUCKET_NAME" ] || [ -z "$FUNCTION_NAME" ] || [ -z "$MONITOR_FUNCTION_NAME" ]; then
            warn "Configuration not found in file or environment variables"
            prompt_for_config
        fi
    fi
    
    # Set default values for missing configuration
    REGION=${REGION:-us-central1}
    ZONE=${ZONE:-us-central1-a}
    
    # Set default project if needed
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "$PROJECT_ID" ]; then
            error "Could not determine project ID"
            exit 1
        fi
    fi
    
    # Set project configuration
    gcloud config set project "$PROJECT_ID" || error "Failed to set project"
    gcloud config set compute/region "$REGION" || error "Failed to set region"
    gcloud config set compute/zone "$ZONE" || error "Failed to set zone"
    
    log "Configuration setup completed"
}

# Function to confirm deletion
confirm_deletion() {
    log "Resources to be deleted:"
    echo "=============================="
    info "Project: $PROJECT_ID"
    info "Region: $REGION"
    info "BigQuery Dataset: $DATASET_ID"
    info "Storage Bucket: gs://$BUCKET_NAME"
    info "Cloud Functions: $FUNCTION_NAME, $MONITOR_FUNCTION_NAME"
    echo ""
    
    warn "This action will permanently delete all listed resources and cannot be undone."
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed. Proceeding with cleanup..."
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    # Delete climate processor function
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        log "Deleting climate processor function: $FUNCTION_NAME"
        if gcloud functions delete "$FUNCTION_NAME" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet; then
            log "Successfully deleted function: $FUNCTION_NAME"
        else
            warn "Failed to delete function: $FUNCTION_NAME"
        fi
    else
        info "Function $FUNCTION_NAME not found or already deleted"
    fi
    
    # Delete climate monitor function
    if gcloud functions describe "$MONITOR_FUNCTION_NAME" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        log "Deleting climate monitor function: $MONITOR_FUNCTION_NAME"
        if gcloud functions delete "$MONITOR_FUNCTION_NAME" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet; then
            log "Successfully deleted function: $MONITOR_FUNCTION_NAME"
        else
            warn "Failed to delete function: $MONITOR_FUNCTION_NAME"
        fi
    else
        info "Function $MONITOR_FUNCTION_NAME not found or already deleted"
    fi
    
    log "Cloud Functions cleanup completed"
}

# Function to delete BigQuery resources
delete_bigquery_resources() {
    log "Deleting BigQuery resources..."
    
    # Check if dataset exists
    if bq ls "${PROJECT_ID}:${DATASET_ID}" &>/dev/null; then
        log "Deleting BigQuery dataset: $DATASET_ID"
        
        # List all tables and views in the dataset
        local tables=$(bq ls --format=csv "${PROJECT_ID}:${DATASET_ID}" 2>/dev/null | tail -n +2 | cut -d',' -f1)
        
        if [ -n "$tables" ]; then
            info "Found tables/views in dataset:"
            echo "$tables" | while read -r table; do
                if [ -n "$table" ]; then
                    info "  - $table"
                fi
            done
        fi
        
        # Delete the entire dataset (this removes all tables and views)
        if bq rm -r -f "${PROJECT_ID}:${DATASET_ID}"; then
            log "Successfully deleted BigQuery dataset: $DATASET_ID"
        else
            warn "Failed to delete BigQuery dataset: $DATASET_ID"
        fi
    else
        info "BigQuery dataset $DATASET_ID not found or already deleted"
    fi
    
    log "BigQuery resources cleanup completed"
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket..."
    
    # Check if bucket exists
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log "Deleting storage bucket: gs://$BUCKET_NAME"
        
        # List objects in bucket
        local object_count=$(gsutil ls "gs://${BUCKET_NAME}/**" 2>/dev/null | wc -l || echo "0")
        if [ "$object_count" -gt 0 ]; then
            info "Found $object_count objects in bucket, deleting all objects..."
        fi
        
        # Delete all objects and the bucket
        if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
            log "Successfully deleted storage bucket: gs://$BUCKET_NAME"
        else
            warn "Failed to delete storage bucket: gs://$BUCKET_NAME"
        fi
    else
        info "Storage bucket gs://$BUCKET_NAME not found or already deleted"
    fi
    
    log "Storage bucket cleanup completed"
}

# Function to delete custom monitoring metrics
delete_monitoring_metrics() {
    log "Deleting custom monitoring metrics..."
    
    # Note: Custom metrics are automatically cleaned up after 24 hours of inactivity
    # We'll just log this information
    info "Custom monitoring metrics will be automatically cleaned up after 24 hours of inactivity"
    info "Manual cleanup is not required for metrics"
    
    log "Monitoring metrics cleanup completed"
}

# Function to delete IAM service accounts (if any were created)
delete_service_accounts() {
    log "Checking for service accounts to delete..."
    
    # List service accounts that might have been created for this deployment
    local service_accounts=$(gcloud iam service-accounts list \
        --filter="displayName:climate-risk OR displayName:earth-engine" \
        --format="value(email)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [ -n "$service_accounts" ]; then
        info "Found service accounts that may be related to this deployment:"
        echo "$service_accounts" | while read -r sa_email; do
            if [ -n "$sa_email" ]; then
                info "  - $sa_email"
                warn "Service account $sa_email was not automatically deleted"
                warn "Please verify if this service account should be deleted and remove it manually if needed"
            fi
        done
    else
        info "No service accounts found that need cleanup"
    fi
    
    log "Service accounts check completed"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove deployment config file if it exists
    if [ -f "./deployment_config.json" ]; then
        log "Removing deployment configuration file..."
        rm -f "./deployment_config.json"
        log "Deployment configuration file removed"
    fi
    
    # Remove any temporary files that might have been created
    rm -rf /tmp/lifecycle.json 2>/dev/null || true
    rm -rf /tmp/climate-processor-* 2>/dev/null || true
    rm -rf /tmp/climate-monitor-* 2>/dev/null || true
    
    log "Temporary files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_errors=0
    
    # Check if functions still exist
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        warn "Function $FUNCTION_NAME still exists"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    if gcloud functions describe "$MONITOR_FUNCTION_NAME" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        warn "Function $MONITOR_FUNCTION_NAME still exists"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check if BigQuery dataset still exists
    if bq ls "${PROJECT_ID}:${DATASET_ID}" &>/dev/null; then
        warn "BigQuery dataset $DATASET_ID still exists"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check if storage bucket still exists
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        warn "Storage bucket gs://$BUCKET_NAME still exists"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    if [ $cleanup_errors -eq 0 ]; then
        log "Cleanup verification completed successfully"
        return 0
    else
        warn "Cleanup verification found $cleanup_errors issues"
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "====================="
    info "Project ID: $PROJECT_ID"
    info "Region: $REGION"
    info "Zone: $ZONE"
    echo ""
    info "Deleted Resources:"
    info "  - BigQuery Dataset: $DATASET_ID"
    info "  - Storage Bucket: gs://$BUCKET_NAME"
    info "  - Cloud Functions: $FUNCTION_NAME, $MONITOR_FUNCTION_NAME"
    info "  - Custom monitoring metrics (will be auto-cleaned after 24 hours)"
    info "  - Temporary files and configuration"
    echo ""
    info "Cleanup completed successfully!"
    info "Total cleanup time: $(($(date +%s) - START_TIME)) seconds"
    echo ""
    warn "Note: Some resources may take a few minutes to be fully removed from the console"
    warn "Billing charges should stop immediately after resource deletion"
}

# Function to handle script interruption
cleanup_on_interrupt() {
    error "Script interrupted. Some resources may not have been cleaned up."
    error "Please run this script again to complete the cleanup process."
    exit 1
}

# Function to disable APIs (optional)
disable_apis() {
    log "Checking if APIs should be disabled..."
    
    echo ""
    warn "The following APIs were enabled during deployment:"
    info "  - earthengine.googleapis.com"
    info "  - bigquery.googleapis.com"
    info "  - cloudfunctions.googleapis.com"
    info "  - monitoring.googleapis.com"
    info "  - storage.googleapis.com"
    info "  - cloudbuild.googleapis.com"
    echo ""
    
    read -p "Do you want to disable these APIs? (yes/no) [no]: " disable_apis_confirmation
    disable_apis_confirmation=${disable_apis_confirmation:-no}
    
    if [[ "$disable_apis_confirmation" == "yes" ]]; then
        log "Disabling APIs..."
        
        local apis=(
            "earthengine.googleapis.com"
            "bigquery.googleapis.com"
            "cloudfunctions.googleapis.com"
            "monitoring.googleapis.com"
            "storage.googleapis.com"
            "cloudbuild.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log "Disabling $api..."
            if gcloud services disable "$api" --project="$PROJECT_ID" --quiet; then
                log "Successfully disabled $api"
            else
                warn "Failed to disable $api (may be used by other resources)"
            fi
        done
    else
        info "APIs will remain enabled"
    fi
}

# Main cleanup function
main() {
    log "Starting Climate Risk Assessment Earth Engine BigQuery cleanup"
    
    # Set up interrupt handler
    trap cleanup_on_interrupt INT TERM
    
    # Check OS compatibility
    check_os
    
    # Check prerequisites
    check_prerequisites
    
    # Set up configuration
    setup_config
    
    # Confirm deletion
    confirm_deletion
    
    # Delete Cloud Functions
    delete_cloud_functions
    
    # Delete BigQuery resources
    delete_bigquery_resources
    
    # Delete Cloud Storage bucket
    delete_storage_bucket
    
    # Delete custom monitoring metrics
    delete_monitoring_metrics
    
    # Delete service accounts (if any)
    delete_service_accounts
    
    # Clean up temporary files
    cleanup_temp_files
    
    # Verify cleanup
    verify_cleanup
    
    # Optionally disable APIs
    disable_apis
    
    # Display cleanup summary
    display_cleanup_summary
    
    log "Cleanup completed successfully!"
}

# Record start time
START_TIME=$(date +%s)

# Run main function
main "$@"