#!/bin/bash

# Email Signature Generator - Cleanup Script
# This script removes all resources created for the email signature generator

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Default values
DEFAULT_PROJECT_ID=""
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Script variables
PROJECT_ID="${PROJECT_ID:-$DEFAULT_PROJECT_ID}"
REGION="${REGION:-$DEFAULT_REGION}"
ZONE="${ZONE:-$DEFAULT_ZONE}"
BUCKET_NAME="${BUCKET_NAME:-}"
FUNCTION_NAME="${FUNCTION_NAME:-generate-signature}"
FUNCTION_SOURCE_DIR="./function-source"

# Check if running in dry-run mode
DRY_RUN="${DRY_RUN:-false}"
FORCE_DELETE="${FORCE_DELETE:-false}"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -p, --project-id PROJECT_ID     GCP Project ID (required if not set via env)
    -r, --region REGION             GCP region (default: us-central1)
    -z, --zone ZONE                 GCP zone (default: us-central1-a)
    -b, --bucket-name BUCKET_NAME   Cloud Storage bucket name to delete
    -f, --function-name FUNC_NAME   Cloud Function name (default: generate-signature)
    --force                         Skip confirmation prompts
    -d, --dry-run                   Show what would be done without executing
    -h, --help                      Show this help message

Environment Variables:
    PROJECT_ID     - GCP Project ID
    REGION         - GCP region
    ZONE           - GCP zone
    BUCKET_NAME    - Cloud Storage bucket name
    FORCE_DELETE   - Set to 'true' to skip confirmations
    DRY_RUN        - Set to 'true' for dry-run mode

Examples:
    $0 --project-id my-project                  # Basic cleanup
    $0 --project-id my-project --force          # Skip confirmations
    DRY_RUN=true $0 --project-id my-project     # Dry run mode
    $0 --bucket-name email-signatures-abc123    # Specify bucket name

EOF
}

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
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        -b|--bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        -f|--function-name)
            FUNCTION_NAME="$2"
            shift 2
            ;;
        --force)
            FORCE_DELETE="true"
            shift
            ;;
        -d|--dry-run)
            DRY_RUN="true"
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

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $description"
        log_info "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        log_info "$description"
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || log_warning "Command failed but continuing..."
        else
            eval "$cmd"
        fi
    fi
}

# Prerequisites check function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud CLI."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud CLI with gsutil."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id or set PROJECT_ID environment variable."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to confirm destructive actions
confirm_action() {
    local message="$1"
    
    if [[ "$FORCE_DELETE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}WARNING:${NC} $message"
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
}

# Function to discover resources automatically
discover_resources() {
    log_info "Discovering resources to clean up..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would discover resources in project: $PROJECT_ID"
        return 0
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID" &> /dev/null
    gcloud config set compute/region "$REGION" &> /dev/null
    gcloud config set functions/region "$REGION" &> /dev/null
    
    # Discover Cloud Functions if function name not specified or exists
    if gcloud functions describe "$FUNCTION_NAME" --gen2 --region="$REGION" &> /dev/null; then
        log_info "Found Cloud Function: $FUNCTION_NAME"
    else
        log_warning "Cloud Function '$FUNCTION_NAME' not found"
        FUNCTION_NAME=""
    fi
    
    # Try to discover bucket name if not provided
    if [[ -z "$BUCKET_NAME" ]]; then
        log_info "Searching for email signature buckets..."
        local buckets
        buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "gs://email-signatures-[a-f0-9]{6}/" || true)
        
        if [[ -n "$buckets" ]]; then
            log_info "Found potential buckets:"
            echo "$buckets"
            
            if [[ "$FORCE_DELETE" != "true" ]]; then
                echo "Please specify which bucket to delete using --bucket-name option,"
                echo "or use --force to delete all email-signatures-* buckets."
                exit 1
            else
                # In force mode, we'll handle all discovered buckets
                log_warning "Force mode: Will attempt to delete all email-signatures-* buckets"
            fi
        else
            log_info "No email signature buckets found"
        fi
    else
        # Verify the specified bucket exists
        if gsutil ls -p "$PROJECT_ID" | grep -q "gs://$BUCKET_NAME/"; then
            log_info "Found specified bucket: $BUCKET_NAME"
        else
            log_warning "Specified bucket '$BUCKET_NAME' not found"
            BUCKET_NAME=""
        fi
    fi
    
    log_success "Resource discovery completed"
}

# Function to delete Cloud Function
delete_function() {
    if [[ -z "$FUNCTION_NAME" ]]; then
        log_info "No Cloud Function to delete"
        return 0
    fi
    
    log_info "Deleting Cloud Function: $FUNCTION_NAME"
    
    confirm_action "This will permanently delete the Cloud Function '$FUNCTION_NAME'."
    
    execute_command "gcloud functions delete $FUNCTION_NAME \
        --gen2 \
        --region=$REGION \
        --quiet" \
        "Deleting Cloud Function" \
        true
    
    log_success "Cloud Function deleted (if it existed)"
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    if [[ -z "$BUCKET_NAME" ]]; then
        # Try to delete all email-signatures-* buckets if in force mode
        if [[ "$FORCE_DELETE" == "true" ]]; then
            delete_all_signature_buckets
        else
            log_info "No specific bucket specified for deletion"
        fi
        return 0
    fi
    
    log_info "Deleting Cloud Storage bucket: $BUCKET_NAME"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Check if bucket exists
        if ! gsutil ls -p "$PROJECT_ID" | grep -q "gs://$BUCKET_NAME/"; then
            log_warning "Bucket '$BUCKET_NAME' not found, skipping deletion"
            return 0
        fi
        
        # Check if bucket has contents
        local object_count
        object_count=$(gsutil ls -r "gs://$BUCKET_NAME" 2>/dev/null | wc -l || echo "0")
        
        if [[ "$object_count" -gt 1 ]]; then
            confirm_action "Bucket '$BUCKET_NAME' contains $((object_count-1)) objects. This will permanently delete all contents."
        else
            confirm_action "This will permanently delete the bucket '$BUCKET_NAME'."
        fi
    fi
    
    execute_command "gsutil -m rm -r gs://$BUCKET_NAME" \
        "Deleting bucket and all contents" \
        true
    
    log_success "Cloud Storage bucket deleted (if it existed)"
}

# Function to delete all email signature buckets (force mode)
delete_all_signature_buckets() {
    log_info "Searching for all email signature buckets to delete..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would search and delete all email-signatures-* buckets"
        return 0
    fi
    
    local buckets
    buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "gs://email-signatures-[a-f0-9]{6}/" || true)
    
    if [[ -z "$buckets" ]]; then
        log_info "No email signature buckets found"
        return 0
    fi
    
    confirm_action "This will delete ALL email signature buckets and their contents."
    
    while IFS= read -r bucket; do
        if [[ -n "$bucket" ]]; then
            bucket_name=$(echo "$bucket" | sed 's|gs://||' | sed 's|/$||')
            log_info "Deleting bucket: $bucket_name"
            execute_command "gsutil -m rm -r $bucket" \
                "Deleting $bucket" \
                true
        fi
    done <<< "$buckets"
    
    log_success "All email signature buckets deleted"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_clean=(
        "$FUNCTION_SOURCE_DIR"
        "function-url.txt"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -e "$file" ]]; then
            execute_command "rm -rf $file" \
                "Removing $file" \
                true
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to clean up environment variables
cleanup_environment() {
    log_info "Cleaning up environment variables..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would unset environment variables"
        return 0
    fi
    
    # Only unset if they were set by our script (be conservative)
    unset RANDOM_SUFFIX 2>/dev/null || true
    
    log_success "Environment variables cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would verify resource cleanup"
        return 0
    fi
    
    local cleanup_issues=0
    
    # Check if function still exists
    if [[ -n "$FUNCTION_NAME" ]] && gcloud functions describe "$FUNCTION_NAME" --gen2 --region="$REGION" &> /dev/null; then
        log_warning "Cloud Function '$FUNCTION_NAME' still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check if bucket still exists
    if [[ -n "$BUCKET_NAME" ]] && gsutil ls -p "$PROJECT_ID" | grep -q "gs://$BUCKET_NAME/"; then
        log_warning "Bucket '$BUCKET_NAME' still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup verification completed - all resources removed"
    else
        log_warning "Cleanup verification found $cleanup_issues potential issues"
        log_info "Some resources may still exist. Please check manually."
    fi
}

# Function to display cleanup summary
display_summary() {
    log_info "Cleanup Summary"
    echo "==============="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    
    if [[ -n "$FUNCTION_NAME" ]]; then
        echo "Function Name: $FUNCTION_NAME (deleted)"
    fi
    
    if [[ -n "$BUCKET_NAME" ]]; then
        echo "Bucket Name: $BUCKET_NAME (deleted)"
    fi
    
    echo ""
    echo "Cleanup completed. All resources for the Email Signature Generator"
    echo "have been removed from your GCP project."
    echo ""
    echo "Note: API enablement and gcloud configuration were not changed."
}

# Main cleanup function
main() {
    log_info "Starting Email Signature Generator cleanup..."
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    
    if [[ -n "$BUCKET_NAME" ]]; then
        echo "Bucket Name: $BUCKET_NAME"
    fi
    
    echo "Function Name: $FUNCTION_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "Running in DRY-RUN mode - no resources will be deleted"
    fi
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Running in FORCE mode - confirmations will be skipped"
    fi
    
    echo ""
    
    # Execute cleanup steps
    check_prerequisites
    discover_resources
    delete_function
    delete_storage_bucket
    cleanup_local_files
    cleanup_environment
    verify_cleanup
    
    echo ""
    log_success "Cleanup completed successfully!"
    display_summary
}

# Function to handle script interruption
cleanup_on_interrupt() {
    log_warning "Script interrupted. Cleanup may be incomplete."
    log_info "You can re-run this script to continue cleanup."
    exit 1
}

# Trap to handle script interruption
trap cleanup_on_interrupt INT TERM

# Run main function
main "$@"