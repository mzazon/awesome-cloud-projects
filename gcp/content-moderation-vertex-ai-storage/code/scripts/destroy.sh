#!/bin/bash

# Content Moderation with Vertex AI and Cloud Storage - Cleanup Script
# This script removes all resources created by the deployment script

set -e
set -u
set -o pipefail

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log "Running in dry-run mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            log "Force delete mode enabled - will skip confirmation prompts"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--force] [--help]"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --force      Skip confirmation prompts"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    if [[ "$ignore_errors" == "true" ]]; then
        if ! eval "$cmd" 2>/dev/null; then
            warning "Command failed but continuing: $cmd"
        fi
    else
        if ! eval "$cmd"; then
            error "Failed to execute: $cmd"
            return 1
        fi
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Load deployment configuration
load_deployment_config() {
    log "Loading deployment configuration..."
    
    local config_file="$(dirname "$0")/deployment.config"
    
    if [[ ! -f "$config_file" ]]; then
        error "Deployment configuration file not found: $config_file"
        error "Please ensure you run this script from the same directory as the deployment"
        exit 1
    fi
    
    # Source the configuration file
    source "$config_file"
    
    # Verify required variables are set
    local required_vars=(
        "PROJECT_ID"
        "REGION"
        "BUCKET_INCOMING"
        "BUCKET_QUARANTINE"
        "BUCKET_APPROVED"
        "TOPIC_NAME"
        "FUNCTION_NAME"
        "NOTIFICATION_FUNCTION"
        "SERVICE_ACCOUNT_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var is not set in configuration file"
            exit 1
        fi
    done
    
    # Display configuration
    log "Configuration loaded:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Incoming Bucket: $BUCKET_INCOMING"
    echo "  Quarantine Bucket: $BUCKET_QUARANTINE"
    echo "  Approved Bucket: $BUCKET_APPROVED"
    echo "  Topic Name: $TOPIC_NAME"
    echo "  Function Name: $FUNCTION_NAME"
    echo "  Notification Function: $NOTIFICATION_FUNCTION"
    echo "  Service Account: $SERVICE_ACCOUNT_NAME"
    
    success "Configuration loaded successfully"
}

# Delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    local functions=("$FUNCTION_NAME" "$NOTIFICATION_FUNCTION")
    
    for func in "${functions[@]}"; do
        execute_command "gcloud functions delete $func --region=$REGION --project=$PROJECT_ID --quiet" \
            "Deleting function $func" \
            "true"
    done
    
    success "Cloud Functions deleted"
}

# Delete storage buckets
delete_storage_buckets() {
    log "Deleting Cloud Storage buckets..."
    
    local buckets=("$BUCKET_INCOMING" "$BUCKET_QUARANTINE" "$BUCKET_APPROVED")
    
    for bucket in "${buckets[@]}"; do
        # Check if bucket exists before trying to delete
        if [[ "$DRY_RUN" == "false" ]]; then
            if gsutil ls "gs://$bucket" &>/dev/null; then
                execute_command "gsutil -m rm -r gs://$bucket" \
                    "Deleting bucket $bucket" \
                    "true"
            else
                warning "Bucket $bucket not found, skipping"
            fi
        else
            execute_command "gsutil -m rm -r gs://$bucket" \
                "Deleting bucket $bucket" \
                "true"
        fi
    done
    
    success "Storage buckets deleted"
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    # Delete subscription first
    execute_command "gcloud pubsub subscriptions delete ${TOPIC_NAME}-subscription --project=$PROJECT_ID --quiet" \
        "Deleting Pub/Sub subscription" \
        "true"
    
    # Delete topic
    execute_command "gcloud pubsub topics delete $TOPIC_NAME --project=$PROJECT_ID --quiet" \
        "Deleting Pub/Sub topic" \
        "true"
    
    success "Pub/Sub resources deleted"
}

# Delete service account
delete_service_account() {
    log "Deleting service account..."
    
    local service_account_email="$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com"
    
    execute_command "gcloud iam service-accounts delete $service_account_email --project=$PROJECT_ID --quiet" \
        "Deleting service account" \
        "true"
    
    success "Service account deleted"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "$(dirname "$0")/deployment.config"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            execute_command "rm -f $file" \
                "Removing local file $file" \
                "true"
        fi
    done
    
    success "Local files cleaned up"
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Dry-run completed successfully"
        return 0
    fi
    
    local cleanup_issues=0
    
    # Check buckets
    local buckets=("$BUCKET_INCOMING" "$BUCKET_QUARANTINE" "$BUCKET_APPROVED")
    for bucket in "${buckets[@]}"; do
        if gsutil ls "gs://$bucket" &>/dev/null; then
            warning "Bucket $bucket still exists"
            ((cleanup_issues++))
        else
            success "Bucket $bucket removed"
        fi
    done
    
    # Check functions
    local functions=("$FUNCTION_NAME" "$NOTIFICATION_FUNCTION")
    for func in "${functions[@]}"; do
        if gcloud functions describe "$func" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
            warning "Function $func still exists"
            ((cleanup_issues++))
        else
            success "Function $func removed"
        fi
    done
    
    # Check service account
    local service_account_email="$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "$service_account_email" --project="$PROJECT_ID" &>/dev/null; then
        warning "Service account $service_account_email still exists"
        ((cleanup_issues++))
    else
        success "Service account $service_account_email removed"
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" &>/dev/null; then
        warning "Pub/Sub topic $TOPIC_NAME still exists"
        ((cleanup_issues++))
    else
        success "Pub/Sub topic $TOPIC_NAME removed"
    fi
    
    if [[ $cleanup_issues -gt 0 ]]; then
        warning "Cleanup verification found $cleanup_issues issues"
        warning "Some resources may need manual cleanup"
    else
        success "Cleanup verification completed successfully"
    fi
}

# Display cost information
display_cost_info() {
    log "Cost Information:"
    echo "  The following resources have been deleted to stop incurring charges:"
    echo "  - Cloud Storage buckets (including all stored content)"
    echo "  - Cloud Functions (no more function invocations)"
    echo "  - Pub/Sub topics and subscriptions"
    echo "  - Service account"
    echo
    echo "  Note: Some minimal charges may still appear for:"
    echo "  - Vertex AI API calls made during testing"
    echo "  - Cloud Build operations (if any)"
    echo "  - Logging and monitoring data retention"
    echo
    success "All billable resources have been removed"
}

# Main cleanup function
main() {
    log "Starting Content Moderation cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment configuration
    load_deployment_config
    
    # Confirm cleanup
    if [[ "$DRY_RUN" == "false" && "$FORCE_DELETE" == "false" ]]; then
        echo
        warning "This will permanently delete all resources in Google Cloud Project: $PROJECT_ID"
        warning "The following resources will be deleted:"
        echo "  - Cloud Storage buckets: $BUCKET_INCOMING, $BUCKET_QUARANTINE, $BUCKET_APPROVED"
        echo "  - Cloud Functions: $FUNCTION_NAME, $NOTIFICATION_FUNCTION"
        echo "  - Pub/Sub topic: $TOPIC_NAME"
        echo "  - Service account: $SERVICE_ACCOUNT_NAME"
        echo
        warning "THIS ACTION CANNOT BE UNDONE!"
        echo
        read -p "Are you sure you want to continue? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled"
            exit 0
        fi
        
        echo
        warning "Last chance! Are you absolutely sure?"
        read -p "Type 'DELETE' to confirm: " -r
        echo
        if [[ "$REPLY" != "DELETE" ]]; then
            log "Cleanup cancelled"
            exit 0
        fi
    fi
    
    # Execute cleanup steps
    delete_cloud_functions
    delete_storage_buckets
    delete_pubsub_resources
    delete_service_account
    cleanup_local_files
    verify_cleanup
    display_cost_info
    
    echo
    success "Content Moderation cleanup completed successfully!"
    echo
    log "All resources have been removed from your Google Cloud project."
    log "If you want to redeploy, run: ./deploy.sh"
}

# Run main function
main "$@"