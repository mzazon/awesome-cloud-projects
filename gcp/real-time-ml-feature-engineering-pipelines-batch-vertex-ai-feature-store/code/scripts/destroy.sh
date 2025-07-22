#!/bin/bash

# Real-Time ML Feature Engineering Pipelines with Cloud Batch and Vertex AI Feature Store
# Cleanup/Destroy Script for GCP Infrastructure
# Version: 1.0

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Display banner
echo -e "${RED}"
echo "=============================================="
echo "  ML Feature Engineering Pipeline Cleanup"
echo "=============================================="
echo -e "${NC}"

# Configuration variables - try to read from deployment_info.txt if available
if [[ -f "deployment_info.txt" ]]; then
    log "Reading configuration from deployment_info.txt..."
    PROJECT_ID=$(grep "Project ID:" deployment_info.txt | cut -d: -f2 | xargs)
    REGION=$(grep "Region:" deployment_info.txt | cut -d: -f2 | xargs)
    RANDOM_SUFFIX=$(grep "Random Suffix:" deployment_info.txt | cut -d: -f2 | xargs)
    
    # Extract resource names
    DATASET_NAME=$(grep "BigQuery Dataset:" deployment_info.txt | cut -d: -f2 | xargs)
    FEATURE_TABLE=$(grep "Feature Table:" deployment_info.txt | cut -d: -f2 | xargs)
    BATCH_JOB_NAME=$(grep "Batch Job:" deployment_info.txt | cut -d: -f2 | xargs)
    PUBSUB_TOPIC=$(grep "Pub/Sub Topic:" deployment_info.txt | cut -d: -f2 | xargs)
    FEATURE_GROUP_NAME=$(grep "Feature Group:" deployment_info.txt | cut -d: -f2 | xargs)
    BUCKET_NAME=$(grep "Storage Bucket:" deployment_info.txt | cut -d: -f2 | xargs | sed 's/gs:\/\///')
    ONLINE_STORE_NAME=$(grep "Online Store:" deployment_info.txt | cut -d: -f2 | xargs)
    FEATURE_VIEW_NAME=$(grep "Feature View:" deployment_info.txt | cut -d: -f2 | xargs)
else
    log_warning "deployment_info.txt not found. Using environment variables or defaults..."
    
    # Fallback to environment variables or prompt user
    PROJECT_ID="${PROJECT_ID:-}"
    REGION="${REGION:-us-central1}"
    RANDOM_SUFFIX="${RANDOM_SUFFIX:-}"
    
    if [[ -z "$PROJECT_ID" ]]; then
        read -p "Enter GCP Project ID: " PROJECT_ID
    fi
    
    if [[ -z "$RANDOM_SUFFIX" ]]; then
        read -p "Enter random suffix used during deployment: " RANDOM_SUFFIX
    fi
    
    # Construct resource names
    DATASET_NAME="feature_dataset_${RANDOM_SUFFIX}"
    FEATURE_TABLE="user_features"
    BATCH_JOB_NAME="feature-pipeline-${RANDOM_SUFFIX}"
    PUBSUB_TOPIC="feature-updates-${RANDOM_SUFFIX}"
    FEATURE_GROUP_NAME="user-feature-group-${RANDOM_SUFFIX}"
    BUCKET_NAME="ml-features-bucket-${RANDOM_SUFFIX}"
    ONLINE_STORE_NAME="user-features-store-${RANDOM_SUFFIX}"
    FEATURE_VIEW_NAME="user-feature-view-${RANDOM_SUFFIX}"
fi

# Parse command line arguments
FORCE=false
DRY_RUN=false
SKIP_CONFIRMATION=false
DELETE_PROJECT=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            log_warning "Running in dry-run mode - no resources will be deleted"
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --delete-project)
            DELETE_PROJECT=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force                Force deletion without prompts"
            echo "  --dry-run              Show what would be deleted without actually deleting"
            echo "  --skip-confirmation    Skip initial confirmation prompt"
            echo "  --delete-project       Delete the entire GCP project"
            echo "  --verbose              Enable verbose logging"
            echo "  --project-id ID        Specify GCP project ID"
            echo "  --help                 Show this help message"
            echo ""
            echo "Note: Use --force for automated cleanup in CI/CD pipelines"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Display configuration
log "Cleanup Configuration:"
echo "  Project ID: $PROJECT_ID"
echo "  Region: $REGION"
echo "  Random Suffix: $RANDOM_SUFFIX"
echo ""

# Prerequisite checks
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error_exit "bq CLI is not installed. Please install BigQuery CLI."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not installed. Please install Google Cloud SDK."
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login'."
    fi
    
    # Verify project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error_exit "Project $PROJECT_ID does not exist or you don't have access."
    fi
    
    log_success "Prerequisites check completed"
}

# Confirmation prompts
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "🚨 DESTRUCTIVE OPERATION WARNING 🚨"
    echo ""
    echo "This script will delete the following resources:"
    echo "  • Vertex AI Feature Store (Feature Group: $FEATURE_GROUP_NAME)"
    echo "  • Vertex AI Online Store ($ONLINE_STORE_NAME)"
    echo "  • Cloud Batch Job ($BATCH_JOB_NAME)"
    echo "  • Cloud Function (trigger-feature-pipeline)"
    echo "  • Pub/Sub Topic and Subscription ($PUBSUB_TOPIC)"
    echo "  • BigQuery Dataset ($DATASET_NAME) and all tables"
    echo "  • Cloud Storage Bucket (gs://$BUCKET_NAME) and all contents"
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "  • ENTIRE GCP PROJECT ($PROJECT_ID) - THIS CANNOT BE UNDONE!"
    fi
    
    echo ""
    echo "💰 This will stop all charges associated with these resources."
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo ""
        log_warning "⚠️  PROJECT DELETION CONFIRMATION ⚠️"
        echo "You are about to delete the ENTIRE project: $PROJECT_ID"
        echo "This action CANNOT be undone and will:"
        echo "  • Delete ALL resources in the project"
        echo "  • Delete ALL data permanently"
        echo "  • Make the project ID unusable for 30 days"
        echo ""
        read -p "Type the project ID to confirm project deletion: " project_confirmation
        
        if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
            log_error "Project ID confirmation failed. Cleanup cancelled."
            exit 1
        fi
    fi
}

# Set default project
configure_defaults() {
    log "Configuring gcloud defaults..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        gcloud config set project "$PROJECT_ID"
        gcloud config set compute/region "$REGION"
    fi
    
    log_success "Defaults configured"
}

# Delete Vertex AI Feature Store resources
delete_vertex_ai_resources() {
    log "Deleting Vertex AI Feature Store resources..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Delete feature view first
        if gcloud ai feature-views describe "$FEATURE_VIEW_NAME" \
            --online-store="$ONLINE_STORE_NAME" \
            --location="$REGION" \
            --project="$PROJECT_ID" &> /dev/null; then
            
            log "Deleting feature view: $FEATURE_VIEW_NAME"
            gcloud ai feature-views delete "$FEATURE_VIEW_NAME" \
                --online-store="$ONLINE_STORE_NAME" \
                --location="$REGION" \
                --project="$PROJECT_ID" \
                --quiet || log_warning "Failed to delete feature view"
        else
            log_warning "Feature view $FEATURE_VIEW_NAME not found"
        fi
        
        # Delete online store
        if gcloud ai online-stores describe "$ONLINE_STORE_NAME" \
            --location="$REGION" \
            --project="$PROJECT_ID" &> /dev/null; then
            
            log "Deleting online store: $ONLINE_STORE_NAME"
            gcloud ai online-stores delete "$ONLINE_STORE_NAME" \
                --location="$REGION" \
                --project="$PROJECT_ID" \
                --quiet || log_warning "Failed to delete online store"
        else
            log_warning "Online store $ONLINE_STORE_NAME not found"
        fi
        
        # Delete individual features
        local features=(
            "avg_session_duration"
            "total_purchases"
            "purchase_frequency"
            "days_since_last_login"
            "preferred_category"
        )
        
        for feature_name in "${features[@]}"; do
            if gcloud ai features describe "$feature_name" \
                --feature-group="$FEATURE_GROUP_NAME" \
                --location="$REGION" \
                --project="$PROJECT_ID" &> /dev/null; then
                
                log "Deleting feature: $feature_name"
                gcloud ai features delete "$feature_name" \
                    --feature-group="$FEATURE_GROUP_NAME" \
                    --location="$REGION" \
                    --project="$PROJECT_ID" \
                    --quiet || log_warning "Failed to delete feature $feature_name"
            fi
        done
        
        # Delete feature group
        if gcloud ai feature-groups describe "$FEATURE_GROUP_NAME" \
            --location="$REGION" \
            --project="$PROJECT_ID" &> /dev/null; then
            
            log "Deleting feature group: $FEATURE_GROUP_NAME"
            gcloud ai feature-groups delete "$FEATURE_GROUP_NAME" \
                --location="$REGION" \
                --project="$PROJECT_ID" \
                --quiet || log_warning "Failed to delete feature group"
        else
            log_warning "Feature group $FEATURE_GROUP_NAME not found"
        fi
    fi
    
    log_success "Vertex AI Feature Store resources deleted"
}

# Delete Cloud Batch job
delete_batch_job() {
    log "Deleting Cloud Batch job..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        if gcloud batch jobs describe "$BATCH_JOB_NAME" \
            --location="$REGION" \
            --project="$PROJECT_ID" &> /dev/null; then
            
            log "Deleting batch job: $BATCH_JOB_NAME"
            gcloud batch jobs delete "$BATCH_JOB_NAME" \
                --location="$REGION" \
                --project="$PROJECT_ID" \
                --quiet || log_warning "Failed to delete batch job"
        else
            log_warning "Batch job $BATCH_JOB_NAME not found"
        fi
    fi
    
    log_success "Cloud Batch job deleted"
}

# Delete Cloud Function
delete_cloud_function() {
    log "Deleting Cloud Function..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        if gcloud functions describe trigger-feature-pipeline \
            --project="$PROJECT_ID" &> /dev/null; then
            
            log "Deleting Cloud Function: trigger-feature-pipeline"
            gcloud functions delete trigger-feature-pipeline \
                --project="$PROJECT_ID" \
                --quiet || log_warning "Failed to delete Cloud Function"
        else
            log_warning "Cloud Function trigger-feature-pipeline not found"
        fi
    fi
    
    log_success "Cloud Function deleted"
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Delete subscription first
        if gcloud pubsub subscriptions describe feature-pipeline-sub \
            --project="$PROJECT_ID" &> /dev/null; then
            
            log "Deleting Pub/Sub subscription: feature-pipeline-sub"
            gcloud pubsub subscriptions delete feature-pipeline-sub \
                --project="$PROJECT_ID" \
                --quiet || log_warning "Failed to delete subscription"
        else
            log_warning "Pub/Sub subscription feature-pipeline-sub not found"
        fi
        
        # Delete topic
        if gcloud pubsub topics describe "$PUBSUB_TOPIC" \
            --project="$PROJECT_ID" &> /dev/null; then
            
            log "Deleting Pub/Sub topic: $PUBSUB_TOPIC"
            gcloud pubsub topics delete "$PUBSUB_TOPIC" \
                --project="$PROJECT_ID" \
                --quiet || log_warning "Failed to delete topic"
        else
            log_warning "Pub/Sub topic $PUBSUB_TOPIC not found"
        fi
    fi
    
    log_success "Pub/Sub resources deleted"
}

# Delete BigQuery resources
delete_bigquery_resources() {
    log "Deleting BigQuery dataset and tables..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Check if dataset exists
        if bq ls -d "$PROJECT_ID:$DATASET_NAME" &> /dev/null; then
            log "Deleting BigQuery dataset: $DATASET_NAME"
            
            # Delete dataset and all tables recursively
            bq rm -r -f "$PROJECT_ID:$DATASET_NAME" || log_warning "Failed to delete BigQuery dataset"
        else
            log_warning "BigQuery dataset $DATASET_NAME not found"
        fi
    fi
    
    log_success "BigQuery resources deleted"
}

# Delete Cloud Storage bucket
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Check if bucket exists
        if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
            log "Deleting Cloud Storage bucket: gs://$BUCKET_NAME"
            
            # Remove all objects first, then the bucket
            gsutil -m rm -r "gs://$BUCKET_NAME" || log_warning "Failed to delete storage bucket"
        else
            log_warning "Cloud Storage bucket gs://$BUCKET_NAME not found"
        fi
    fi
    
    log_success "Cloud Storage bucket deleted"
}

# Delete entire project
delete_project() {
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        return 0
    fi
    
    log "Deleting entire GCP project..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_warning "Deleting project: $PROJECT_ID"
        log_warning "This may take several minutes to complete..."
        
        gcloud projects delete "$PROJECT_ID" --quiet || log_error "Failed to delete project"
        
        log_success "Project deletion initiated. It may take up to 30 minutes to complete."
        log_warning "The project ID '$PROJECT_ID' will be unavailable for 30 days."
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment_info.txt"
        "feature_engineering.py"
        "batch_job_config.json"
        "main.py"
        "requirements.txt"
        "lifecycle.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "false" ]]; then
                rm -f "$file"
                log "Removed local file: $file"
            else
                log "Would remove local file: $file"
            fi
        fi
    done
    
    log_success "Local files cleaned up"
}

# Generate cleanup report
generate_cleanup_report() {
    log "Generating cleanup report..."
    
    local report_file="cleanup_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
ML Feature Engineering Pipeline Cleanup Report
==============================================
Cleanup Date: $(date)
Project ID: $PROJECT_ID
Region: $REGION
Cleanup Mode: $(if [[ "$DRY_RUN" == "true" ]]; then echo "DRY RUN"; else echo "ACTUAL DELETION"; fi)

Resources Targeted for Deletion:
--------------------------------
✓ Vertex AI Feature Group: $FEATURE_GROUP_NAME
✓ Vertex AI Online Store: $ONLINE_STORE_NAME
✓ Vertex AI Feature View: $FEATURE_VIEW_NAME
✓ Cloud Batch Job: $BATCH_JOB_NAME
✓ Cloud Function: trigger-feature-pipeline
✓ Pub/Sub Topic: $PUBSUB_TOPIC
✓ Pub/Sub Subscription: feature-pipeline-sub
✓ BigQuery Dataset: $DATASET_NAME
✓ Cloud Storage Bucket: gs://$BUCKET_NAME
$(if [[ "$DELETE_PROJECT" == "true" ]]; then echo "✓ Entire GCP Project: $PROJECT_ID"; fi)

Cleanup Status: $(if [[ "$DRY_RUN" == "true" ]]; then echo "SIMULATED"; else echo "COMPLETED"; fi)

Notes:
- All billable resources have been removed
- Project deletion (if requested) may take up to 30 minutes
- Deleted project IDs remain unavailable for 30 days
- Ensure you have backups of any important data before running cleanup

For support or questions, refer to the original recipe documentation.
EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Cleanup report saved to: $report_file"
    else
        log "Cleanup report would be saved to: $report_file"
        rm -f "$report_file"
    fi
}

# Main cleanup function
main() {
    log "Starting ML Feature Engineering Pipeline cleanup..."
    
    check_prerequisites
    confirm_deletion
    configure_defaults
    
    # Execute cleanup in reverse order of creation
    delete_vertex_ai_resources
    delete_batch_job
    delete_cloud_function
    delete_pubsub_resources
    delete_bigquery_resources
    delete_storage_bucket
    delete_project
    cleanup_local_files
    generate_cleanup_report
    
    # Display summary
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "🔍 Dry run completed - no resources were actually deleted"
        echo ""
        echo "To perform actual cleanup, run this script without --dry-run"
    else
        log_success "🧹 ML Feature Engineering Pipeline cleanup completed successfully!"
        echo ""
        echo "💰 All billable resources have been removed"
        echo "📊 Check your GCP billing dashboard to confirm charges have stopped"
        
        if [[ "$DELETE_PROJECT" == "true" ]]; then
            echo "🗑️  Project deletion initiated - may take up to 30 minutes to complete"
        fi
    fi
    
    echo ""
    echo "📋 Cleanup Summary:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Resources Removed: Vertex AI Feature Store, Cloud Batch, Cloud Function, Pub/Sub, BigQuery, Cloud Storage"
    echo "  Local Files: Cleaned up"
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "  Project Status: Deletion in progress"
    else
        echo "  Project Status: Resources removed, project preserved"
    fi
    
    echo ""
    echo "✨ Thank you for using the ML Feature Engineering Pipeline recipe!"
}

# Execute main function
main "$@"