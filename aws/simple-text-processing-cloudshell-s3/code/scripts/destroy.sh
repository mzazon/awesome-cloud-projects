#!/bin/bash

# Simple Text Processing with CloudShell and S3 - Cleanup Script
# This script removes all resources created by the deployment script

set -e
set -o pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
DEPLOYMENT_INFO="${SCRIPT_DIR}/deployment_info.txt"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[${TIMESTAMP}]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[${TIMESTAMP}] ✅ $1${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[${TIMESTAMP}] ⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[${TIMESTAMP}] ❌ $1${NC}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI or run this script in AWS CloudShell."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please configure AWS CLI or run in CloudShell."
    fi
    
    log_success "Prerequisites check completed"
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ -f "${DEPLOYMENT_INFO}" ]]; then
        # Source the deployment info file
        source "${DEPLOYMENT_INFO}"
        log "Loaded deployment info from ${DEPLOYMENT_INFO}"
        log "Found bucket: ${BUCKET_NAME:-'Not found'}"
    else
        log_warning "Deployment info file not found at ${DEPLOYMENT_INFO}"
        
        # Try to find bucket by pattern if deployment info is missing
        log "Attempting to find bucket by pattern..."
        BUCKET_NAME=$(aws s3 ls | grep "text-processing-demo-" | awk '{print $3}' | head -n1)
        
        if [[ -z "${BUCKET_NAME}" ]]; then
            log_warning "No bucket found matching pattern 'text-processing-demo-*'"
            log "Manual cleanup may be required"
            return 1
        else
            log "Found bucket by pattern: ${BUCKET_NAME}"
        fi
    fi
    
    log_success "Deployment information loaded"
}

# Confirm destruction
confirm_destruction() {
    local force_flag="${1:-}"
    
    if [[ "${force_flag}" != "--force" && "${force_flag}" != "-f" ]]; then
        echo ""
        log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
        echo ""
        echo "This script will PERMANENTLY DELETE the following resources:"
        echo ""
        if [[ -n "${BUCKET_NAME}" ]]; then
            echo "  • S3 Bucket: ${BUCKET_NAME}"
            echo "    - All objects in input/ folder"
            echo "    - All objects in output/ folder"
            echo "    - The bucket itself"
        fi
        echo "  • Local processing files and directories"
        echo "  • Environment variables and temporary data"
        echo ""
        echo "💰 This will stop any ongoing S3 storage charges."
        echo ""
        read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log "Cleanup confirmed, proceeding with resource destruction..."
}

# Remove S3 bucket and contents
remove_s3_resources() {
    if [[ -z "${BUCKET_NAME}" ]]; then
        log_warning "No bucket name found, skipping S3 cleanup"
        return 0
    fi
    
    log "Removing S3 bucket and all contents..."
    
    # Check if bucket exists
    if ! aws s3 ls s3://${BUCKET_NAME} &> /dev/null; then
        log_warning "S3 bucket ${BUCKET_NAME} does not exist or is not accessible"
        return 0
    fi
    
    # List bucket contents before deletion (for logging)
    log "Current bucket contents:"
    aws s3 ls s3://${BUCKET_NAME} --recursive | tee -a "${LOG_FILE}" || true
    
    # Delete all objects in the bucket recursively
    log "Deleting all objects in bucket..."
    aws s3 rm s3://${BUCKET_NAME} --recursive || log_warning "Some objects may not have been deleted"
    
    # Wait a moment for eventual consistency
    sleep 2
    
    # Delete the bucket itself
    log "Deleting S3 bucket..."
    if aws s3 rb s3://${BUCKET_NAME}; then
        log_success "S3 bucket ${BUCKET_NAME} deleted successfully"
    else
        log_error "Failed to delete S3 bucket ${BUCKET_NAME}"
        log_warning "You may need to manually delete the bucket from the AWS Console"
        return 1
    fi
    
    # Verify bucket deletion
    if aws s3 ls s3://${BUCKET_NAME} &> /dev/null; then
        log_warning "Bucket still exists after deletion attempt"
        return 1
    fi
    
    log_success "S3 resources removed successfully"
}

# Clean up local CloudShell files
cleanup_local_files() {
    log "Cleaning up local CloudShell files and directories..."
    
    local cleanup_items=(
        "sales_data.txt"
        "processing/"
        "verify/"
        "*.csv"
    )
    
    # Change to home directory for safety
    cd ~
    
    for item in "${cleanup_items[@]}"; do
        if [[ "$item" == "*"* ]]; then
            # Handle glob patterns
            if ls $item 1> /dev/null 2>&1; then
                log "Removing files matching pattern: $item"
                rm -f $item
            fi
        elif [[ -e "$item" ]]; then
            if [[ -d "$item" ]]; then
                log "Removing directory: $item"
                rm -rf "$item"
            else
                log "Removing file: $item"
                rm -f "$item"
            fi
        fi
    done
    
    # Clean up any remaining processing artifacts
    find . -maxdepth 1 -name "*processing*" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -maxdepth 1 -name "*summary*" -type f -exec rm -f {} + 2>/dev/null || true
    
    log_success "Local files cleaned up"
}

# Clean up environment variables
cleanup_environment_variables() {
    log "Cleaning up environment variables..."
    
    # List of environment variables to unset
    local env_vars=(
        "BUCKET_NAME"
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "RANDOM_SUFFIX"
    )
    
    for var in "${env_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            log "Unsetting environment variable: $var"
            unset "$var"
        fi
    done
    
    log_success "Environment variables cleaned up"
}

# Remove deployment information
remove_deployment_info() {
    log "Removing deployment information files..."
    
    local files_to_remove=(
        "${DEPLOYMENT_INFO}"
        "${SCRIPT_DIR}/deploy.log"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log "Removing: $file"
            rm -f "$file"
        fi
    done
    
    log_success "Deployment information files removed"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_successful=true
    
    # Check if S3 bucket still exists
    if [[ -n "${BUCKET_NAME}" ]]; then
        if aws s3 ls s3://${BUCKET_NAME} &> /dev/null; then
            log_error "S3 bucket ${BUCKET_NAME} still exists"
            cleanup_successful=false
        else
            log_success "S3 bucket successfully removed"
        fi
    fi
    
    # Check for remaining local files
    cd ~
    local remaining_files=()
    
    if [[ -f "sales_data.txt" ]]; then
        remaining_files+=("sales_data.txt")
    fi
    
    if [[ -d "processing" ]]; then
        remaining_files+=("processing/")
    fi
    
    if [[ -d "verify" ]]; then
        remaining_files+=("verify/")
    fi
    
    if [[ ${#remaining_files[@]} -gt 0 ]]; then
        log_warning "Some local files still exist: ${remaining_files[*]}"
        cleanup_successful=false
    fi
    
    if [[ "$cleanup_successful" == true ]]; then
        log_success "Cleanup verification completed successfully"
        return 0
    else
        log_warning "Cleanup verification found some remaining resources"
        return 1
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    echo ""
    log_success "🧹 Simple Text Processing with CloudShell and S3 cleanup completed!"
    echo ""
    echo "📋 Resources removed:"
    if [[ -n "${BUCKET_NAME}" ]]; then
        echo "   • S3 bucket: ${BUCKET_NAME}"
        echo "   • All objects in input/ and output/ folders"
    fi
    echo "   • Local processing files and directories"
    echo "   • Environment variables and temporary data"
    echo "   • Deployment information files"
    echo ""
    echo "💰 Cost impact:"
    echo "   • S3 storage charges have been stopped"
    echo "   • No ongoing costs from this tutorial"
    echo ""
    echo "🔍 Manual verification (optional):"
    echo "   • Check AWS S3 Console to confirm bucket deletion"
    echo "   • Check local directory for any remaining files"
    echo ""
    
    if ! verify_cleanup; then
        echo "⚠️  Some resources may require manual cleanup:"
        echo "   • Check the AWS S3 Console for any remaining buckets"
        echo "   • Review your local directory for any remaining files"
        echo ""
    fi
    
    echo "✅ You can now safely re-run the deployment script for a fresh start!"
}

# Main cleanup function
main() {
    local force_flag="${1:-}"
    
    log "Starting Simple Text Processing with CloudShell and S3 cleanup..."
    
    # Initialize log file
    echo "=== Simple Text Processing Cleanup Log ===" > "${LOG_FILE}"
    echo "Started: ${TIMESTAMP}" >> "${LOG_FILE}"
    
    # Run cleanup steps
    check_prerequisites
    
    if load_deployment_info; then
        confirm_destruction "$force_flag"
        remove_s3_resources
        cleanup_local_files
        cleanup_environment_variables
        remove_deployment_info
        show_cleanup_summary
    else
        log_warning "Could not load deployment information"
        log "Attempting basic cleanup anyway..."
        
        confirm_destruction "$force_flag"
        cleanup_local_files
        cleanup_environment_variables
        
        echo ""
        log_warning "⚠️  Partial cleanup completed"
        echo ""
        echo "Manual steps required:"
        echo "1. Check AWS S3 Console for any 'text-processing-demo-*' buckets"
        echo "2. Delete any found buckets manually"
        echo "3. Review your local directory for remaining files"
    fi
    
    log_success "Cleanup completed in $(( SECONDS / 60 )) minutes and $(( SECONDS % 60 )) seconds"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Simple Text Processing with CloudShell and S3 - Cleanup Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --force, -f    Skip confirmation prompt"
        echo ""
        echo "This script removes:"
        echo "  • S3 bucket and all contents"
        echo "  • Local processing files and directories"
        echo "  • Environment variables and temporary data"
        echo "  • Deployment information files"
        echo ""
        echo "⚠️  WARNING: This operation is irreversible!"
        exit 0
        ;;
    --dry-run)
        echo "DRY RUN MODE - No resources will be deleted"
        echo ""
        echo "This cleanup would:"
        echo "  1. Delete S3 bucket and all contents"
        echo "  2. Remove local processing files"
        echo "  3. Clean up environment variables"
        echo "  4. Remove deployment information"
        echo ""
        if [[ -f "${DEPLOYMENT_INFO}" ]]; then
            source "${DEPLOYMENT_INFO}"
            echo "Found deployment info:"
            echo "  • Bucket: ${BUCKET_NAME:-'Not found'}"
        else
            echo "No deployment info found - would attempt pattern-based cleanup"
        fi
        echo ""
        echo "Use './destroy.sh' to perform actual cleanup"
        echo "Use './destroy.sh --force' to skip confirmation"
        exit 0
        ;;
esac

# Run main cleanup
main "$@"