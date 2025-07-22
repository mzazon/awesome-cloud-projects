#!/bin/bash

# Podcast Content Generation with Text-to-Speech and Natural Language - Cleanup Script
# This script safely removes all infrastructure created for the podcast generation system

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

# Print usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up podcast generation infrastructure from Google Cloud Platform

OPTIONS:
    -p, --project-id        GCP Project ID (required)
    -r, --region           GCP region (default: us-central1)
    -f, --force            Skip confirmation prompts
    -d, --dry-run          Show what would be deleted without making changes
    --keep-project         Keep the project (only delete resources)
    --keep-data            Keep Cloud Storage bucket and data
    --delete-project       Delete the entire project (destructive)
    -h, --help             Show this help message

EXAMPLES:
    $0 --project-id my-podcast-project
    $0 --project-id my-project --force
    $0 --dry-run --project-id test-project
    $0 --project-id my-project --keep-data --keep-project

SAFETY:
    By default, this script will ask for confirmation before deleting resources.
    Use --force to skip confirmations (useful for automation).
    Use --dry-run to see what would be deleted without making changes.

EOF
}

# Default values
REGION="us-central1"
DRY_RUN=false
FORCE=false
KEEP_PROJECT=false
KEEP_DATA=false
DELETE_PROJECT=false
PROJECT_ID=""

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
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --keep-project)
            KEEP_PROJECT=true
            shift
            ;;
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        --delete-project)
            DELETE_PROJECT=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    log_error "Project ID is required. Use --project-id or -p"
    usage
    exit 1
fi

# Validate conflicting options
if [[ "$DELETE_PROJECT" == "true" && "$KEEP_PROJECT" == "true" ]]; then
    log_error "Cannot use --delete-project and --keep-project together"
    exit 1
fi

# Derive resource names (should match deployment script)
FUNCTION_NAME="podcast-processor"
SERVICE_ACCOUNT_NAME="podcast-generator"

log_info "Starting podcast generation infrastructure cleanup"
log_info "Project ID: ${PROJECT_ID}"
log_info "Region: ${REGION}"

if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN MODE - No resources will be actually deleted"
fi

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "No active gcloud authentication found."
        log_info "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project ${PROJECT_ID} does not exist or you don't have access"
        exit 1
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    
    log_success "Prerequisites check completed"
}

# Confirm destructive actions
confirm_action() {
    local action="$1"
    local resource="$2"
    
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "About to ${action}: ${resource}"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipped ${action} for ${resource}"
        return 1
    fi
    
    return 0
}

# List resources that will be deleted
list_resources() {
    log_info "Scanning for podcast generation resources in project ${PROJECT_ID}..."
    
    echo
    echo "=== RESOURCES TO BE DELETED ==="
    
    # Check Cloud Functions
    local functions=$(gcloud functions list --filter="name:${FUNCTION_NAME}" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$functions" ]]; then
        echo "Cloud Functions:"
        echo "$functions" | sed 's/^/  - /'
    fi
    
    # Check Service Accounts
    local service_accounts=$(gcloud iam service-accounts list --filter="email:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --format="value(email)" 2>/dev/null || echo "")
    if [[ -n "$service_accounts" ]]; then
        echo "Service Accounts:"
        echo "$service_accounts" | sed 's/^/  - /'
    fi
    
    # Check Storage Buckets (podcast-content-*)
    local buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "gs://podcast-content-" || echo "")
    if [[ -n "$buckets" && "$KEEP_DATA" == "false" ]]; then
        echo "Storage Buckets:"
        echo "$buckets" | sed 's/^/  - /'
    fi
    
    # Check Log Metrics
    local metrics=$(gcloud logging metrics list --filter="name:podcast_generation_count" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$metrics" ]]; then
        echo "Log Metrics:"
        echo "$metrics" | sed 's/^/  - /'
    fi
    
    # Local files
    echo "Local Files:"
    [[ -f "${HOME}/podcast-key.json" ]] && echo "  - ${HOME}/podcast-key.json"
    [[ -f "${HOME}/batch-podcast-generator.sh" ]] && echo "  - ${HOME}/batch-podcast-generator.sh"
    [[ -f "${HOME}/podcast-function-url.txt" ]] && echo "  - ${HOME}/podcast-function-url.txt"
    [[ -d "${HOME}/podcast-content" ]] && echo "  - ${HOME}/podcast-content/ (directory)"
    
    echo
}

# Delete Cloud Functions
delete_cloud_functions() {
    log_info "Checking for Cloud Functions to delete..."
    
    local functions=$(gcloud functions list --filter="name:${FUNCTION_NAME}" --format="value(name)" --region="$REGION" 2>/dev/null || echo "")
    
    if [[ -z "$functions" ]]; then
        log_info "No Cloud Functions found to delete"
        return 0
    fi
    
    for function in $functions; do
        if confirm_action "delete Cloud Function" "$function"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete Cloud Function: $function"
            else
                log_info "Deleting Cloud Function: $function"
                if gcloud functions delete "$function" --region="$REGION" --quiet; then
                    log_success "Deleted Cloud Function: $function"
                else
                    log_error "Failed to delete Cloud Function: $function"
                fi
            fi
        fi
    done
}

# Delete Cloud Storage buckets
delete_storage_buckets() {
    if [[ "$KEEP_DATA" == "true" ]]; then
        log_info "Keeping Cloud Storage buckets as requested"
        return 0
    fi
    
    log_info "Checking for Cloud Storage buckets to delete..."
    
    local buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "gs://podcast-content-" || echo "")
    
    if [[ -z "$buckets" ]]; then
        log_info "No podcast-related storage buckets found"
        return 0
    fi
    
    for bucket in $buckets; do
        # Remove trailing slash
        bucket=${bucket%/}
        bucket_name=${bucket#gs://}
        
        if confirm_action "delete storage bucket and all contents" "$bucket"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete bucket: $bucket"
            else
                log_info "Deleting bucket contents: $bucket"
                # Delete all objects in bucket (including versions)
                if gsutil -m rm -r "$bucket"/* &> /dev/null; then
                    log_info "Bucket contents deleted"
                else
                    log_warning "Bucket might be empty or already cleaned"
                fi
                
                log_info "Deleting bucket: $bucket"
                if gsutil rb "$bucket"; then
                    log_success "Deleted bucket: $bucket"
                else
                    log_error "Failed to delete bucket: $bucket"
                fi
            fi
        fi
    done
}

# Delete IAM Service Accounts
delete_service_accounts() {
    log_info "Checking for Service Accounts to delete..."
    
    local service_account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if ! gcloud iam service-accounts describe "$service_account" &> /dev/null; then
        log_info "Service account not found: $service_account"
        return 0
    fi
    
    if confirm_action "delete service account" "$service_account"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete service account: $service_account"
        else
            log_info "Deleting service account: $service_account"
            if gcloud iam service-accounts delete "$service_account" --quiet; then
                log_success "Deleted service account: $service_account"
            else
                log_error "Failed to delete service account: $service_account"
            fi
        fi
    fi
}

# Delete monitoring resources
delete_monitoring_resources() {
    log_info "Checking for monitoring resources to delete..."
    
    # Delete log-based metrics
    local metrics=$(gcloud logging metrics list --filter="name:podcast_generation_count" --format="value(name)" 2>/dev/null || echo "")
    
    for metric in $metrics; do
        if confirm_action "delete log metric" "$metric"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete log metric: $metric"
            else
                log_info "Deleting log metric: $metric"
                if gcloud logging metrics delete "$metric" --quiet; then
                    log_success "Deleted log metric: $metric"
                else
                    log_error "Failed to delete log metric: $metric"
                fi
            fi
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    log_info "Checking for local files to clean up..."
    
    local files=(
        "${HOME}/podcast-key.json"
        "${HOME}/batch-podcast-generator.sh"
        "${HOME}/podcast-function-url.txt"
    )
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            if confirm_action "delete local file" "$file"; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would delete file: $file"
                else
                    if rm "$file"; then
                        log_success "Deleted file: $file"
                    else
                        log_error "Failed to delete file: $file"
                    fi
                fi
            fi
        fi
    done
    
    # Clean up directory
    if [[ -d "${HOME}/podcast-content" ]]; then
        if confirm_action "delete local directory" "${HOME}/podcast-content"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete directory: ${HOME}/podcast-content"
            else
                if rm -rf "${HOME}/podcast-content"; then
                    log_success "Deleted directory: ${HOME}/podcast-content"
                else
                    log_error "Failed to delete directory: ${HOME}/podcast-content"
                fi
            fi
        fi
    fi
}

# Disable APIs (optional)
disable_apis() {
    log_info "Checking APIs to disable..."
    
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        log_info "Keeping project - not disabling APIs"
        return 0
    fi
    
    local apis=(
        "texttospeech.googleapis.com"
        "language.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    if confirm_action "disable APIs" "${apis[*]}"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would disable APIs: ${apis[*]}"
        else
            for api in "${apis[@]}"; do
                log_info "Disabling API: $api"
                if gcloud services disable "$api" --force --quiet; then
                    log_success "Disabled API: $api"
                else
                    log_warning "Failed to disable API: $api (might be in use by other resources)"
                fi
            done
        fi
    fi
}

# Delete entire project
delete_project() {
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        return 0
    fi
    
    log_warning "Preparing to delete entire project: ${PROJECT_ID}"
    log_warning "This action is IRREVERSIBLE and will delete ALL resources in the project!"
    
    if confirm_action "DELETE ENTIRE PROJECT" "$PROJECT_ID"; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete project: $PROJECT_ID"
        else
            log_info "Deleting project: $PROJECT_ID"
            if gcloud projects delete "$PROJECT_ID" --quiet; then
                log_success "Project deleted: $PROJECT_ID"
                log_info "All resources in the project have been deleted"
                return 0
            else
                log_error "Failed to delete project: $PROJECT_ID"
                return 1
            fi
        fi
    else
        log_info "Project deletion cancelled"
        return 1
    fi
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" || "$DELETE_PROJECT" == "true" ]]; then
        return 0
    fi
    
    log_info "Verifying cleanup completion..."
    
    # Check for remaining resources
    local remaining_functions=$(gcloud functions list --filter="name:${FUNCTION_NAME}" --format="value(name)" 2>/dev/null | wc -l)
    local remaining_sa=$(gcloud iam service-accounts list --filter="email:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --format="value(email)" 2>/dev/null | wc -l)
    
    local remaining_buckets=0
    if [[ "$KEEP_DATA" == "false" ]]; then
        remaining_buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -c "gs://podcast-content-" || echo "0")
    fi
    
    if [[ $remaining_functions -eq 0 && $remaining_sa -eq 0 && $remaining_buckets -eq 0 ]]; then
        log_success "Cleanup verification passed - all resources removed"
    else
        log_warning "Some resources may still exist:"
        [[ $remaining_functions -gt 0 ]] && log_warning "  - Cloud Functions: $remaining_functions"
        [[ $remaining_sa -gt 0 ]] && log_warning "  - Service Accounts: $remaining_sa"
        [[ $remaining_buckets -gt 0 ]] && log_warning "  - Storage Buckets: $remaining_buckets"
    fi
}

# Print cleanup summary
print_summary() {
    echo
    log_success "Podcast Generation Infrastructure Cleanup Complete!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    
    if [[ "$DELETE_PROJECT" == "true" && "$DRY_RUN" == "false" ]]; then
        echo "Action: Project deleted entirely"
    else
        echo "Actions performed:"
        echo "  - Cloud Functions: deleted"
        echo "  - Service Accounts: deleted"
        echo "  - IAM roles: removed"
        echo "  - Monitoring metrics: deleted"
        
        if [[ "$KEEP_DATA" == "true" ]]; then
            echo "  - Storage buckets: kept (as requested)"
        else
            echo "  - Storage buckets: deleted"
        fi
        
        if [[ "$KEEP_PROJECT" == "true" ]]; then
            echo "  - Project: kept (as requested)"
            echo "  - APIs: kept enabled"
        else
            echo "  - APIs: disabled"
        fi
        
        echo "  - Local files: cleaned up"
    fi
    
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "This was a dry run. No actual resources were deleted."
        log_info "Run without --dry-run to perform actual cleanup."
    else
        echo "=== NEXT STEPS ==="
        if [[ "$DELETE_PROJECT" != "true" ]]; then
            echo "1. Verify no unexpected charges in billing console"
            echo "2. Check for any remaining resources in Cloud Console"
            if [[ "$KEEP_PROJECT" == "true" ]]; then
                echo "3. Project ${PROJECT_ID} is still active and can be reused"
            fi
        fi
        echo
        log_info "Cleanup completed successfully!"
    fi
}

# Main execution
main() {
    log_info "Starting cleanup process..."
    
    check_prerequisites
    list_resources
    
    # Show final confirmation for non-dry-run
    if [[ "$DRY_RUN" == "false" && "$FORCE" == "false" ]]; then
        echo
        log_warning "This will delete podcast generation infrastructure from project: ${PROJECT_ID}"
        if [[ "$DELETE_PROJECT" == "true" ]]; then
            log_warning "THE ENTIRE PROJECT WILL BE DELETED!"
        fi
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Perform cleanup based on options
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        delete_project
    else
        delete_cloud_functions
        delete_service_accounts
        delete_storage_buckets
        delete_monitoring_resources
        disable_apis
    fi
    
    cleanup_local_files
    verify_cleanup
    print_summary
    
    log_success "Cleanup process completed!"
}

# Handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup script failed with exit code: $exit_code"
        log_info "Some resources may not have been cleaned up"
        log_info "You may need to manually remove remaining resources"
    fi
    exit $exit_code
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"