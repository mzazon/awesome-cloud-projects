#!/bin/bash

# Destroy Word Count API with Cloud Functions
# This script removes all resources created by the Word Count API deployment
# 
# Prerequisites:
# - Google Cloud CLI (gcloud) installed and configured
# - Access to the project where resources were deployed
# - Appropriate IAM permissions for resource deletion
#
# Usage: ./destroy.sh [--project PROJECT_ID] [--region REGION] [--force] [--dry-run]

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration values
DEFAULT_PROJECT_ID=""
DEFAULT_REGION="us-central1"
DEFAULT_FUNCTION_NAME="word-count-api"
FORCE_DELETE=false
DRY_RUN=false

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup failed. Check ${LOG_FILE} for details."
    fi
    exit $exit_code
}

trap cleanup EXIT

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Word Count API resources

OPTIONS:
    --project PROJECT_ID    Google Cloud Project ID (required if not set in gcloud config)
    --region REGION         Deployment region (default: us-central1)
    --function-name NAME    Cloud Function name (default: word-count-api)
    --force                 Skip confirmation prompts
    --dry-run              Show what would be deleted without making changes
    --help                 Show this help message

EXAMPLES:
    $0 --project my-project-123
    $0 --project my-project-123 --region us-east1 --force
    $0 --project my-project-123 --dry-run
    $0 --help

WARNING: This will permanently delete all Word Count API resources!

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project)
                DEFAULT_PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                DEFAULT_REGION="$2"
                shift 2
                ;;
            --function-name)
                DEFAULT_FUNCTION_NAME="$2"
                shift 2
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated with gcloud
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -n1 > /dev/null 2>&1; then
        log_error "Not authenticated with Google Cloud"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    # Get current project if not specified
    if [[ -z "$DEFAULT_PROJECT_ID" ]]; then
        DEFAULT_PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$DEFAULT_PROJECT_ID" ]]; then
            log_error "No project specified and no default project configured"
            log_error "Please specify --project PROJECT_ID or run: gcloud config set project PROJECT_ID"
            exit 1
        fi
    fi
    
    # Validate project exists and is accessible
    if ! gcloud projects describe "$DEFAULT_PROJECT_ID" > /dev/null 2>&1; then
        log_error "Cannot access project: $DEFAULT_PROJECT_ID"
        log_error "Please check that the project exists and you have access"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set resource variables
set_resource_variables() {
    export PROJECT_ID="$DEFAULT_PROJECT_ID"
    export REGION="$DEFAULT_REGION"
    export FUNCTION_NAME="$DEFAULT_FUNCTION_NAME"
    
    log_info "Target resources:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Function Name: $FUNCTION_NAME"
}

# Discover resources to delete
discover_resources() {
    log_info "Discovering resources to delete..."
    
    # Find Cloud Functions
    local functions=()
    while IFS= read -r function; do
        if [[ -n "$function" ]]; then
            functions+=("$function")
        fi
    done < <(gcloud functions list \
        --regions="$REGION" \
        --project="$PROJECT_ID" \
        --filter="name:$FUNCTION_NAME" \
        --format="value(name)" 2>/dev/null || true)
    
    # Find Storage buckets with word-count prefix
    local buckets=()
    while IFS= read -r bucket; do
        if [[ -n "$bucket" ]]; then
            buckets+=("$bucket")
        fi
    done < <(gcloud storage buckets list \
        --project="$PROJECT_ID" \
        --format="value(name)" 2>/dev/null | grep "word-count-files" || true)
    
    # Store discovered resources
    DISCOVERED_FUNCTIONS=("${functions[@]}")
    DISCOVERED_BUCKETS=("${buckets[@]}")
    
    log_info "Discovered resources:"
    log_info "  Cloud Functions: ${#DISCOVERED_FUNCTIONS[@]} found"
    for func in "${DISCOVERED_FUNCTIONS[@]}"; do
        log_info "    - $func"
    done
    
    log_info "  Storage Buckets: ${#DISCOVERED_BUCKETS[@]} found"
    for bucket in "${DISCOVERED_BUCKETS[@]}"; do
        log_info "    - $bucket"
    done
    
    if [[ ${#DISCOVERED_FUNCTIONS[@]} -eq 0 && ${#DISCOVERED_BUCKETS[@]} -eq 0 ]]; then
        log_warn "No Word Count API resources found in project $PROJECT_ID"
        return 1
    fi
    
    return 0
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_warn "This will permanently delete the following resources:"
    
    if [[ ${#DISCOVERED_FUNCTIONS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Cloud Functions:${NC}"
        for func in "${DISCOVERED_FUNCTIONS[@]}"; do
            echo "  - $func"
        done
    fi
    
    if [[ ${#DISCOVERED_BUCKETS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Storage Buckets (and ALL contents):${NC}"
        for bucket in "${DISCOVERED_BUCKETS[@]}"; do
            echo "  - $bucket"
        done
    fi
    
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
}

# Delete Cloud Functions
delete_functions() {
    if [[ ${#DISCOVERED_FUNCTIONS[@]} -eq 0 ]]; then
        log_info "No Cloud Functions to delete"
        return 0
    fi
    
    log_info "Deleting Cloud Functions..."
    
    for func in "${DISCOVERED_FUNCTIONS[@]}"; do
        log_info "Deleting function: $func"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete function: $func"
            continue
        fi
        
        # Extract function name from full path
        local function_name
        function_name=$(basename "$func")
        
        if gcloud functions delete "$function_name" \
            --gen2 \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet >> "$LOG_FILE" 2>&1; then
            log_success "Deleted function: $function_name"
        else
            log_error "Failed to delete function: $function_name"
            # Continue with other resources instead of failing completely
        fi
    done
}

# Delete Storage buckets
delete_buckets() {
    if [[ ${#DISCOVERED_BUCKETS[@]} -eq 0 ]]; then
        log_info "No Storage buckets to delete"
        return 0
    fi
    
    log_info "Deleting Storage buckets..."
    
    for bucket in "${DISCOVERED_BUCKETS[@]}"; do
        log_info "Deleting bucket and all contents: $bucket"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete bucket: $bucket"
            continue
        fi
        
        # Delete all objects in bucket first, then the bucket
        if gcloud storage rm -r "gs://$bucket" \
            --project="$PROJECT_ID" \
            --quiet >> "$LOG_FILE" 2>&1; then
            log_success "Deleted bucket: $bucket"
        else
            log_error "Failed to delete bucket: $bucket"
            # Try to continue with other resources
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/.function_url"
        "${SCRIPT_DIR}/deployment-summary.txt"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would remove local file: $file"
            else
                rm -f "$file"
                log_success "Removed local file: $(basename "$file")"
            fi
        fi
    done
}

# Verify deletion
verify_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify resource deletion"
        return 0
    fi
    
    log_info "Verifying resource deletion..."
    
    # Check if functions still exist
    local remaining_functions
    remaining_functions=$(gcloud functions list \
        --regions="$REGION" \
        --project="$PROJECT_ID" \
        --filter="name:$FUNCTION_NAME" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ "$remaining_functions" -gt 0 ]]; then
        log_warn "$remaining_functions Cloud Function(s) still exist"
    else
        log_success "All Cloud Functions deleted successfully"
    fi
    
    # Check if buckets still exist
    local remaining_buckets
    remaining_buckets=$(gcloud storage buckets list \
        --project="$PROJECT_ID" \
        --format="value(name)" 2>/dev/null | grep -c "word-count-files" || true)
    
    if [[ "$remaining_buckets" -gt 0 ]]; then
        log_warn "$remaining_buckets Storage bucket(s) still exist"
    else
        log_success "All Storage buckets deleted successfully"
    fi
}

# Create cleanup summary
create_cleanup_summary() {
    local summary_file="${SCRIPT_DIR}/cleanup-summary.txt"
    
    log_info "Creating cleanup summary..."
    
    cat > "$summary_file" << EOF
Word Count API Cleanup Summary
==============================

Cleanup Date: $(date)
Project ID: $PROJECT_ID
Region: $REGION

Resources Processed:
- Cloud Functions: ${#DISCOVERED_FUNCTIONS[@]} function(s)
- Storage Buckets: ${#DISCOVERED_BUCKETS[@]} bucket(s)

Actions Taken:
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "- DRY RUN: No actual resources were deleted" >> "$summary_file"
    else
        echo "- Deleted all discovered Word Count API resources" >> "$summary_file"
        echo "- Cleaned up local deployment files" >> "$summary_file"
    fi
    
    echo "" >> "$summary_file"
    echo "Log File: $LOG_FILE" >> "$summary_file"
    
    log_success "Cleanup summary created: $summary_file"
}

# Main cleanup function
main() {
    # Initialize log file
    echo "=== Word Count API Cleanup Started at $(date) ===" > "$LOG_FILE"
    
    log_info "Starting Word Count API resource cleanup..."
    
    # Parse command line arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Set resource variables
    set_resource_variables
    
    # Discover resources to delete
    if ! discover_resources; then
        log_info "No resources to clean up"
        exit 0
    fi
    
    # Confirm deletion (unless force or dry-run)
    confirm_deletion
    
    # Delete resources
    delete_functions
    delete_buckets
    
    # Clean up local files
    cleanup_local_files
    
    # Verify deletion
    verify_deletion
    
    # Create cleanup summary
    create_cleanup_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "Dry run completed - no resources were actually deleted"
        log_info "Run without --dry-run to perform actual cleanup"
    else
        log_success "Word Count API cleanup completed successfully!"
        log_info "All resources have been removed from project: $PROJECT_ID"
    fi
    
    log_info "Check cleanup-summary.txt for details"
}

# Execute main function with all arguments
main "$@"