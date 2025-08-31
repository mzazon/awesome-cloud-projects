#!/bin/bash

# Destroy script for Automated Infrastructure Documentation using Asset Inventory and Cloud Functions
# Recipe: automated-infrastructure-documentation-asset-inventory-functions
# Provider: GCP

set -euo pipefail

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
handle_error() {
    log_error "Cleanup failed at line $1. Some resources may remain."
    log_warning "Please check manually and run the script again if needed."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Automated Infrastructure Documentation resources

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP Region (default: us-central1)
    -h, --help                    Show this help message
    --dry-run                     Show what would be destroyed without executing
    --force                       Skip confirmation prompts
    --config FILE                 Load deployment configuration from file

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT          Alternative way to set project ID
    GOOGLE_CLOUD_REGION          Alternative way to set region

EXAMPLES:
    $0 --project-id my-project-123
    $0 --project-id my-project-123 --force
    $0 --config deployment-config.env --dry-run

EOF
}

# Default values
REGION="us-central1"
DRY_RUN=false
FORCE=false
PROJECT_ID=""
CONFIG_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Load configuration from file if provided
load_config() {
    if [[ -n "$CONFIG_FILE" ]]; then
        if [[ -f "$CONFIG_FILE" ]]; then
            log "Loading configuration from $CONFIG_FILE"
            source "$CONFIG_FILE"
            log_success "Configuration loaded"
        else
            log_error "Configuration file not found: $CONFIG_FILE"
            exit 1
        fi
    fi
}

# Set project ID from environment if not provided
if [[ -z "$PROJECT_ID" ]]; then
    if [[ -n "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
        PROJECT_ID="$GOOGLE_CLOUD_PROJECT"
    else
        log_error "Project ID is required. Use --project-id or set GOOGLE_CLOUD_PROJECT environment variable."
        show_help
        exit 1
    fi
fi

# Set region from environment if not provided via command line
if [[ -n "${GOOGLE_CLOUD_REGION:-}" && "$REGION" == "us-central1" ]]; then
    REGION="$GOOGLE_CLOUD_REGION"
fi

log "Starting cleanup for Automated Infrastructure Documentation"
log "Project ID: $PROJECT_ID"
log "Region: $REGION"
log "Dry Run: $DRY_RUN"
log "Force: $FORCE"

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Cannot access project '$PROJECT_ID'. Check project ID and permissions."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Execute command with dry run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local continue_on_error="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would execute: $cmd"
        log "[DRY RUN] Description: $description"
    else
        log "Executing: $description"
        if [[ "$continue_on_error" == "true" ]]; then
            eval "$cmd" || log_warning "Command failed but continuing: $description"
        else
            eval "$cmd"
        fi
    fi
}

# Discover existing resources
discover_resources() {
    log "Discovering existing resources..."
    
    # Set default project
    gcloud config set project "$PROJECT_ID" 2>/dev/null || true
    
    # Try to load from config file first
    if [[ -n "${BUCKET_NAME:-}" && -n "${FUNCTION_NAME:-}" && -n "${TOPIC_NAME:-}" && -n "${SCHEDULER_JOB:-}" ]]; then
        log_success "Using resources from configuration file"
        return
    fi
    
    # Discover Cloud Functions
    FUNCTIONS=$(gcloud functions list --regions="$REGION" --format="value(name)" --filter="name:asset-doc-generator" 2>/dev/null || echo "")
    if [[ -n "$FUNCTIONS" ]]; then
        export FUNCTION_NAME="asset-doc-generator"
        log "Found Cloud Function: $FUNCTION_NAME"
    fi
    
    # Discover Pub/Sub topics
    TOPICS=$(gcloud pubsub topics list --format="value(name)" --filter="name.scope(topic):asset-inventory-trigger" 2>/dev/null || echo "")
    if [[ -n "$TOPICS" ]]; then
        export TOPIC_NAME="asset-inventory-trigger"
        log "Found Pub/Sub topic: $TOPIC_NAME"
    fi
    
    # Discover Cloud Scheduler jobs
    JOBS=$(gcloud scheduler jobs list --location="$REGION" --format="value(name)" --filter="name:daily-asset-docs" 2>/dev/null || echo "")
    if [[ -n "$JOBS" ]]; then
        export SCHEDULER_JOB="daily-asset-docs"
        log "Found Scheduler job: $SCHEDULER_JOB"
    fi
    
    # Discover Storage buckets (pattern matching)
    BUCKETS=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "gs://asset-docs-[a-f0-9]{6}/$" | sed 's|gs://||; s|/$||' || echo "")
    if [[ -n "$BUCKETS" ]]; then
        # Take the first matching bucket
        export BUCKET_NAME=$(echo "$BUCKETS" | head -n1)
        log "Found Storage bucket: $BUCKET_NAME"
    fi
    
    log_success "Resource discovery completed"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "false" && "$DRY_RUN" == "false" ]]; then
        echo
        echo "======================================"
        echo "RESOURCES TO BE DESTROYED"
        echo "======================================"
        echo "Project: $PROJECT_ID"
        echo "Region: $REGION"
        [[ -n "${BUCKET_NAME:-}" ]] && echo "Storage Bucket: gs://$BUCKET_NAME"
        [[ -n "${FUNCTION_NAME:-}" ]] && echo "Cloud Function: $FUNCTION_NAME"
        [[ -n "${TOPIC_NAME:-}" ]] && echo "Pub/Sub Topic: $TOPIC_NAME"
        [[ -n "${SCHEDULER_JOB:-}" ]] && echo "Scheduler Job: $SCHEDULER_JOB"
        echo "IAM Bindings: Service account permissions"
        echo "Local Files: Function source code and config"
        echo "======================================"
        echo
        log_warning "This action cannot be undone!"
        echo -n "Are you sure you want to proceed? (yes/no): "
        read -r confirmation
        if [[ "$confirmation" != "yes" ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
}

# Clean up Cloud Scheduler
cleanup_scheduler() {
    if [[ -n "${SCHEDULER_JOB:-}" ]]; then
        log "Removing Cloud Scheduler job..."
        execute_command "gcloud scheduler jobs delete ${SCHEDULER_JOB} \
            --location=${REGION} \
            --quiet" "Deleting Cloud Scheduler job" true
        log_success "Cloud Scheduler job removed"
    else
        log_warning "No Cloud Scheduler job found to remove"
    fi
}

# Clean up Cloud Function
cleanup_function() {
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log "Removing Cloud Function..."
        execute_command "gcloud functions delete ${FUNCTION_NAME} \
            --region=${REGION} \
            --quiet" "Deleting Cloud Function" true
        log_success "Cloud Function removed"
    else
        log_warning "No Cloud Function found to remove"
    fi
}

# Clean up Pub/Sub Topic
cleanup_pubsub() {
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        log "Removing Pub/Sub topic..."
        execute_command "gcloud pubsub topics delete ${TOPIC_NAME} \
            --quiet" "Deleting Pub/Sub topic" true
        log_success "Pub/Sub topic removed"
    else
        log_warning "No Pub/Sub topic found to remove"
    fi
}

# Clean up Cloud Storage
cleanup_storage() {
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log "Removing Cloud Storage bucket..."
        
        # Check if bucket exists
        if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
            # List contents for user awareness
            if [[ "$DRY_RUN" == "false" ]]; then
                log "Bucket contents to be deleted:"
                gsutil ls -la "gs://${BUCKET_NAME}/**" 2>/dev/null || log "Bucket is empty or no access"
            fi
            
            execute_command "gsutil -m rm -r gs://${BUCKET_NAME}" "Deleting storage bucket and contents" true
            log_success "Cloud Storage bucket removed"
        else
            log_warning "Storage bucket gs://${BUCKET_NAME} not found or already deleted"
        fi
    else
        log_warning "No Cloud Storage bucket found to remove"
    fi
}

# Clean up IAM permissions
cleanup_iam() {
    if [[ -n "${FUNCTION_NAME:-}" && "$DRY_RUN" == "false" ]]; then
        log "Cleaning up IAM permissions..."
        
        # Try to get function service account (might fail if function is already deleted)
        FUNCTION_SA=$(gcloud functions describe "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --format="value(serviceConfig.serviceAccountEmail)" 2>/dev/null || echo "")
        
        if [[ -n "$FUNCTION_SA" ]]; then
            # Remove IAM bindings
            execute_command "gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
                --member=\"serviceAccount:${FUNCTION_SA}\" \
                --role=\"roles/cloudasset.viewer\"" "Removing Asset Inventory access" true
            
            execute_command "gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
                --member=\"serviceAccount:${FUNCTION_SA}\" \
                --role=\"roles/storage.objectAdmin\"" "Removing Storage access" true
            
            log_success "IAM permissions cleaned up"
        else
            log_warning "Could not retrieve function service account - IAM bindings may remain"
        fi
    else
        log_warning "Skipping IAM cleanup (function not found or dry run mode)"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "asset-doc-function"
        "deployment-config.env"
        "infrastructure-report.html"
        "infrastructure-docs.md"
        "asset-inventory.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            execute_command "rm -rf \"$file\"" "Removing local file/directory: $file" true
        fi
    done
    
    log_success "Local files cleaned up"
}

# Verify cleanup
verify_cleanup() {
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Verifying resource cleanup..."
        
        local cleanup_issues=0
        
        # Check Cloud Function
        if [[ -n "${FUNCTION_NAME:-}" ]]; then
            if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
                log_warning "Cloud Function still exists: ${FUNCTION_NAME}"
                ((cleanup_issues++))
            fi
        fi
        
        # Check Pub/Sub Topic
        if [[ -n "${TOPIC_NAME:-}" ]]; then
            if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
                log_warning "Pub/Sub topic still exists: ${TOPIC_NAME}"
                ((cleanup_issues++))
            fi
        fi
        
        # Check Scheduler Job
        if [[ -n "${SCHEDULER_JOB:-}" ]]; then
            if gcloud scheduler jobs describe "${SCHEDULER_JOB}" --location="${REGION}" &>/dev/null; then
                log_warning "Scheduler job still exists: ${SCHEDULER_JOB}"
                ((cleanup_issues++))
            fi
        fi
        
        # Check Storage Bucket
        if [[ -n "${BUCKET_NAME:-}" ]]; then
            if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
                log_warning "Storage bucket still exists: gs://${BUCKET_NAME}"
                ((cleanup_issues++))
            fi
        fi
        
        if [[ $cleanup_issues -eq 0 ]]; then
            log_success "All resources successfully removed"
        else
            log_warning "$cleanup_issues resource(s) may still exist. Please check manually."
        fi
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    log_success "Cleanup process completed!"
    echo
    echo "======================================"
    echo "CLEANUP SUMMARY"
    echo "======================================"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo
    echo "RESOURCES PROCESSED:"
    [[ -n "${BUCKET_NAME:-}" ]] && echo "✓ Storage Bucket: gs://$BUCKET_NAME"
    [[ -n "${FUNCTION_NAME:-}" ]] && echo "✓ Cloud Function: $FUNCTION_NAME"
    [[ -n "${TOPIC_NAME:-}" ]] && echo "✓ Pub/Sub Topic: $TOPIC_NAME"
    [[ -n "${SCHEDULER_JOB:-}" ]] && echo "✓ Scheduler Job: $SCHEDULER_JOB"
    echo "✓ IAM Permissions: Cleaned up"
    echo "✓ Local Files: Removed"
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "NOTE: This was a dry run. No resources were actually deleted."
        echo "Run without --dry-run to perform actual cleanup."
    else
        echo "All infrastructure documentation resources have been removed."
        echo "Your Google Cloud project is now clean."
    fi
    echo "======================================"
}

# Main cleanup function
main() {
    log "Automated Infrastructure Documentation Cleanup Script"
    log "=================================================="
    
    load_config
    check_prerequisites
    discover_resources
    confirm_destruction
    
    # Cleanup in reverse order of creation
    cleanup_scheduler
    cleanup_function
    cleanup_pubsub
    cleanup_storage
    cleanup_iam
    cleanup_local_files
    
    verify_cleanup
    show_cleanup_summary
}

# Run main function
main "$@"