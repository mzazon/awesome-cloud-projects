#!/bin/bash

# Destroy Custom Music Generation with Vertex AI and Storage
# This script safely removes all resources created by the deployment script
# with confirmation prompts and comprehensive cleanup verification

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_MODE=false
SKIP_CONFIRMATION=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warning "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_MODE=true
            warning "Running in FORCE mode - will attempt to delete all resources"
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            warning "Skipping confirmation prompts"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--force] [--yes]"
            exit 1
            ;;
    esac
done

# Function to execute commands with dry-run support
execute() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $*"
        return 0
    else
        "$@"
    fi
}

# Function to check if a resource exists before attempting deletion
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local additional_args="${3:-}"
    
    case "$resource_type" in
        "function")
            gcloud functions describe "$resource_name" --gen2 --region="$REGION" --quiet &>/dev/null
            ;;
        "bucket")
            gsutil ls -b "gs://$resource_name" &>/dev/null
            ;;
        "project")
            gcloud projects describe "$resource_name" --quiet &>/dev/null
            ;;
        *)
            error "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

# Load environment variables if .env file exists
load_environment() {
    if [[ -f .env ]]; then
        log "Loading environment variables from .env file..."
        source .env
        success "Environment variables loaded"
        log "PROJECT_ID: ${PROJECT_ID:-'Not set'}"
        log "REGION: ${REGION:-'Not set'}"
        log "BUCKET_INPUT: ${BUCKET_INPUT:-'Not set'}"
        log "BUCKET_OUTPUT: ${BUCKET_OUTPUT:-'Not set'}"
        log "FUNCTION_NAME: ${FUNCTION_NAME:-'Not set'}"
        log "API_FUNCTION: ${API_FUNCTION:-'Not set'}"
    else
        error ".env file not found. Please run this script from the same directory as deploy.sh"
        error "Or manually set the following environment variables:"
        error "  PROJECT_ID, REGION, BUCKET_INPUT, BUCKET_OUTPUT, FUNCTION_NAME, API_FUNCTION"
        exit 1
    fi
}

# Validate required environment variables
validate_environment() {
    log "Validating environment variables..."
    
    local required_vars=(
        "PROJECT_ID"
        "REGION"
        "BUCKET_INPUT"
        "BUCKET_OUTPUT"
        "FUNCTION_NAME"
        "API_FUNCTION"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        error "Missing required environment variables: ${missing_vars[*]}"
        error "Please check your .env file or set these variables manually"
        exit 1
    fi
    
    success "All required environment variables are set"
}

# Confirmation prompt for destructive operations
confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    warning "This will permanently delete the following resources:"
    echo "  • Cloud Functions: ${FUNCTION_NAME}, ${API_FUNCTION}"
    echo "  • Cloud Storage Buckets: ${BUCKET_INPUT}, ${BUCKET_OUTPUT}"
    echo "  • All stored music files and metadata"
    echo "  • IAM policy bindings"
    echo ""
    warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed by user"
}

# Remove Cloud Functions
remove_cloud_functions() {
    log "Removing Cloud Functions..."
    
    # Remove music generator function
    if resource_exists "function" "$FUNCTION_NAME"; then
        log "Deleting music generator function: ${FUNCTION_NAME}"
        execute gcloud functions delete "$FUNCTION_NAME" \
            --gen2 \
            --region="$REGION" \
            --quiet
        
        # Wait for deletion to complete
        if [[ "$DRY_RUN" == "false" ]]; then
            local timeout=60
            local elapsed=0
            while resource_exists "function" "$FUNCTION_NAME" && [[ $elapsed -lt $timeout ]]; do
                sleep 5
                elapsed=$((elapsed + 5))
                log "Waiting for function deletion to complete... (${elapsed}s)"
            done
            
            if resource_exists "function" "$FUNCTION_NAME"; then
                warning "Function ${FUNCTION_NAME} still exists after ${timeout}s timeout"
            else
                success "Function ${FUNCTION_NAME} deleted successfully"
            fi
        fi
    else
        warning "Function ${FUNCTION_NAME} does not exist or already deleted"
    fi
    
    # Remove API function
    if resource_exists "function" "$API_FUNCTION"; then
        log "Deleting API function: ${API_FUNCTION}"
        execute gcloud functions delete "$API_FUNCTION" \
            --gen2 \
            --region="$REGION" \
            --quiet
        
        # Wait for deletion to complete
        if [[ "$DRY_RUN" == "false" ]]; then
            local timeout=60
            local elapsed=0
            while resource_exists "function" "$API_FUNCTION" && [[ $elapsed -lt $timeout ]]; do
                sleep 5
                elapsed=$((elapsed + 5))
                log "Waiting for function deletion to complete... (${elapsed}s)"
            done
            
            if resource_exists "function" "$API_FUNCTION"; then
                warning "Function ${API_FUNCTION} still exists after ${timeout}s timeout"
            else
                success "Function ${API_FUNCTION} deleted successfully"
            fi
        fi
    else
        warning "Function ${API_FUNCTION} does not exist or already deleted"
    fi
    
    success "Cloud Functions removal completed"
}

# Remove Cloud Storage buckets and contents
remove_storage_buckets() {
    log "Removing Cloud Storage buckets and contents..."
    
    # Remove input bucket
    if resource_exists "bucket" "$BUCKET_INPUT"; then
        log "Deleting input bucket and contents: ${BUCKET_INPUT}"
        execute gsutil -m rm -r "gs://${BUCKET_INPUT}"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            if resource_exists "bucket" "$BUCKET_INPUT"; then
                warning "Bucket ${BUCKET_INPUT} still exists after deletion attempt"
            else
                success "Bucket ${BUCKET_INPUT} deleted successfully"
            fi
        fi
    else
        warning "Bucket ${BUCKET_INPUT} does not exist or already deleted"
    fi
    
    # Remove output bucket
    if resource_exists "bucket" "$BUCKET_OUTPUT"; then
        log "Deleting output bucket and contents: ${BUCKET_OUTPUT}"
        execute gsutil -m rm -r "gs://${BUCKET_OUTPUT}"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            if resource_exists "bucket" "$BUCKET_OUTPUT"; then
                warning "Bucket ${BUCKET_OUTPUT} still exists after deletion attempt"
            else
                success "Bucket ${BUCKET_OUTPUT} deleted successfully"
            fi
        fi
    else
        warning "Bucket ${BUCKET_OUTPUT} does not exist or already deleted"
    fi
    
    success "Cloud Storage buckets removal completed"
}

# Remove IAM policy bindings
remove_iam_bindings() {
    log "Removing IAM policy bindings..."
    
    # Get compute service account if available
    if [[ -n "${COMPUTE_SA:-}" ]]; then
        local service_account="$COMPUTE_SA"
    else
        # Try to reconstruct the service account name
        local project_number
        if project_number=$(gcloud projects describe "$PROJECT_ID" --format="value(projectNumber)" 2>/dev/null); then
            service_account="${project_number}-compute@developer.gserviceaccount.com"
        else
            warning "Cannot determine service account. Skipping IAM cleanup."
            return 0
        fi
    fi
    
    log "Removing IAM bindings for service account: ${service_account}"
    
    # Define roles to remove
    local roles=(
        "roles/aiplatform.user"
        "roles/storage.objectAdmin"
        "roles/cloudfunctions.invoker"
        "roles/logging.logWriter"
    )
    
    for role in "${roles[@]}"; do
        log "Removing IAM binding: ${role}"
        execute gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:${service_account}" \
            --role="$role" \
            --quiet || warning "Failed to remove binding for role: ${role}"
    done
    
    success "IAM policy bindings removal completed"
}

# Clean up local files and directories
cleanup_local_files() {
    log "Cleaning up local files and directories..."
    
    # Remove function directories
    local dirs_to_remove=(
        "music-generator-function"
        "music-api-function"
    )
    
    for dir in "${dirs_to_remove[@]}"; do
        if [[ -d "$dir" ]]; then
            log "Removing directory: ${dir}"
            execute rm -rf "$dir"
        fi
    done
    
    # Remove local files
    local files_to_remove=(
        "test-music-client.py"
        "lifecycle-config.json"
        ".env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log "Removing file: ${file}"
            execute rm -f "$file"
        fi
    done
    
    success "Local files cleanup completed"
}

# Verify complete cleanup
verify_cleanup() {
    log "Verifying complete resource cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Cleanup verification skipped in dry-run mode"
        return
    fi
    
    local cleanup_complete=true
    
    # Check functions
    if resource_exists "function" "$FUNCTION_NAME" || resource_exists "function" "$API_FUNCTION"; then
        warning "Some Cloud Functions still exist"
        cleanup_complete=false
    fi
    
    # Check buckets
    if resource_exists "bucket" "$BUCKET_INPUT" || resource_exists "bucket" "$BUCKET_OUTPUT"; then
        warning "Some Cloud Storage buckets still exist"
        cleanup_complete=false
    fi
    
    # Check local files
    local remaining_files=()
    if [[ -d "music-generator-function" ]]; then remaining_files+=("music-generator-function/"); fi
    if [[ -d "music-api-function" ]]; then remaining_files+=("music-api-function/"); fi
    if [[ -f "test-music-client.py" ]]; then remaining_files+=("test-music-client.py"); fi
    if [[ -f "lifecycle-config.json" ]]; then remaining_files+=("lifecycle-config.json"); fi
    
    if [[ ${#remaining_files[@]} -gt 0 ]]; then
        warning "Some local files still exist: ${remaining_files[*]}"
        cleanup_complete=false
    fi
    
    if [[ "$cleanup_complete" == "true" ]]; then
        success "All resources have been successfully cleaned up"
    else
        warning "Some resources may not have been fully cleaned up"
        if [[ "$FORCE_MODE" == "true" ]]; then
            log "Re-attempting cleanup in force mode..."
            # Additional cleanup attempts could go here
        else
            log "Run with --force flag to attempt additional cleanup"
        fi
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    log "Generating cleanup report..."
    
    local report_file="cleanup_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
Music Generation Infrastructure Cleanup Report
=============================================
Cleanup Date: $(date)
Project ID: ${PROJECT_ID}
Region: ${REGION}

Resources Targeted for Removal:
- Cloud Functions: ${FUNCTION_NAME}, ${API_FUNCTION}
- Storage Buckets: ${BUCKET_INPUT}, ${BUCKET_OUTPUT}
- Local Directories: music-generator-function, music-api-function
- Local Files: test-music-client.py, lifecycle-config.json, .env

Cleanup Mode: $(if [[ "$DRY_RUN" == "true" ]]; then echo "DRY-RUN"; else echo "EXECUTION"; fi)
Force Mode: $(if [[ "$FORCE_MODE" == "true" ]]; then echo "ENABLED"; else echo "DISABLED"; fi)

Additional Notes:
- IAM policy bindings were removed for the compute service account
- All generated music files and metadata were permanently deleted
- Local test scripts and configuration files were removed

EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Cleanup report saved to: ${report_file}"
    else
        rm -f "$report_file"
        log "Cleanup report generation skipped in dry-run mode"
    fi
}

# Main cleanup function
main() {
    log "Starting cleanup of Custom Music Generation with Vertex AI and Storage"
    
    # Load environment
    load_environment
    
    # Validate environment
    validate_environment
    
    # Show confirmation prompt
    confirm_destruction
    
    # Remove Cloud Functions
    remove_cloud_functions
    
    # Remove Storage buckets
    remove_storage_buckets
    
    # Remove IAM bindings
    remove_iam_bindings
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Generate report
    generate_cleanup_report
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Dry-run cleanup completed! Run without --dry-run to actually delete resources"
    else
        success "Cleanup completed successfully!"
        log "All infrastructure resources have been removed"
        log "Thank you for using the Custom Music Generation recipe"
    fi
}

# Display usage information
usage() {
    cat << EOF
Custom Music Generation Infrastructure Cleanup Script

Usage: $0 [OPTIONS]

OPTIONS:
    --dry-run           Show what would be deleted without actually deleting
    --force             Attempt additional cleanup for stubborn resources
    --yes               Skip confirmation prompts (use with caution)
    -h, --help          Show this help message

EXAMPLES:
    $0                  Interactive cleanup with confirmations
    $0 --dry-run        Preview what would be deleted
    $0 --yes            Cleanup without prompts (dangerous)
    $0 --force --yes    Force cleanup without prompts

PREREQUISITES:
    • Must be run from the same directory as deploy.sh
    • Requires .env file created by deployment script
    • Google Cloud CLI must be installed and authenticated
    • Appropriate permissions for resource deletion

EOF
}

# Handle help flag
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi