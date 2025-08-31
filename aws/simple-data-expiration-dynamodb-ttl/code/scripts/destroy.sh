#!/bin/bash

#######################################################################
# Destroy Script for DynamoDB TTL Recipe
# 
# This script removes all infrastructure created by the DynamoDB TTL
# recipe deployment, including disabling TTL and deleting the table.
#
# Prerequisites:
# - AWS CLI installed and configured
# - Deployment configuration file from deploy.sh
# - Appropriate IAM permissions for DynamoDB operations
#######################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CONFIG_FILE="${SCRIPT_DIR}/.deploy_config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO: $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log "SUCCESS: $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "WARNING: $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "ERROR: $1"
}

# Cleanup function for script termination
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        print_error "Cleanup failed with exit code $exit_code"
        print_info "Check the log file at: ${LOG_FILE}"
        print_info "Some resources may still exist and require manual cleanup"
    fi
    exit $exit_code
}

trap cleanup_on_exit EXIT

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions by attempting to list tables
    if ! aws dynamodb list-tables &> /dev/null; then
        print_error "Insufficient DynamoDB permissions. Please ensure you have the following permissions:"
        print_error "- dynamodb:DeleteTable"
        print_error "- dynamodb:UpdateTimeToLive"
        print_error "- dynamodb:DescribeTable"
        print_error "- dynamodb:DescribeTimeToLive"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Load deployment configuration
load_configuration() {
    print_info "Loading deployment configuration..."
    
    if [ ! -f "${CONFIG_FILE}" ]; then
        print_error "Configuration file not found: ${CONFIG_FILE}"
        print_error "This usually means the deployment script hasn't been run successfully."
        print_info "If resources were created manually, you can specify them as parameters:"
        print_info "Usage: $0 --table-name <table-name> --region <region>"
        exit 1
    fi
    
    # Source the configuration file
    source "${CONFIG_FILE}"
    
    # Verify required variables are set
    if [ -z "${TABLE_NAME:-}" ] || [ -z "${AWS_REGION:-}" ]; then
        print_error "Invalid configuration file. Missing required variables."
        exit 1
    fi
    
    print_success "Configuration loaded"
    print_info "Table Name: ${TABLE_NAME}"
    print_info "TTL Attribute: ${TTL_ATTRIBUTE:-expires_at}"
    print_info "AWS Region: ${AWS_REGION}"
}

# Parse command line arguments for manual cleanup
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --table-name)
                TABLE_NAME="$2"
                shift 2
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --ttl-attribute)
                TTL_ATTRIBUTE="$2"
                shift 2
                ;;
            --force)
                FORCE_CLEANUP=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --table-name <name>        Specify table name to delete"
                echo "  --region <region>          Specify AWS region"
                echo "  --ttl-attribute <attr>     Specify TTL attribute name"
                echo "  --force                    Skip confirmation prompts"
                echo "  --dry-run                  Show what would be done without executing"
                echo "  --help, -h                 Show this help message"
                echo
                echo "If no options are provided, configuration is loaded from .deploy_config"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_info "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Display cleanup plan
display_cleanup_plan() {
    print_info "=== CLEANUP PLAN ==="
    print_info "The following resources will be removed:"
    print_info "1. Disable TTL on table: ${TABLE_NAME}"
    print_info "2. Delete DynamoDB table: ${TABLE_NAME}"
    print_info "3. Remove configuration file: ${CONFIG_FILE}"
    print_info "4. Clean up environment variables"
    echo
    print_warning "This action is IRREVERSIBLE!"
    print_warning "All data in the table will be permanently lost."
    echo
}

# Confirm cleanup action
confirm_cleanup() {
    if [ "${FORCE_CLEANUP:-false}" = "true" ]; then
        print_warning "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    if [ "${DRY_RUN:-false}" = "true" ]; then
        print_info "DRY RUN MODE - No resources will be deleted"
        return 0
    fi
    
    echo -n "Are you sure you want to proceed with cleanup? (yes/no): "
    read -r response
    
    case "$response" in
        yes|YES|y|Y)
            print_info "Proceeding with cleanup..."
            ;;
        *)
            print_info "Cleanup cancelled by user"
            exit 0
            ;;
    esac
}

# Check if table exists
check_table_exists() {
    print_info "Checking if table ${TABLE_NAME} exists..."
    
    if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${AWS_REGION}" &> /dev/null; then
        print_info "Table ${TABLE_NAME} exists"
        return 0
    else
        print_warning "Table ${TABLE_NAME} does not exist or is not accessible"
        return 1
    fi
}

# Disable TTL on the table
disable_ttl() {
    if [ "${DRY_RUN:-false}" = "true" ]; then
        print_info "[DRY RUN] Would disable TTL on table ${TABLE_NAME}"
        return 0
    fi
    
    print_info "Disabling TTL on table ${TABLE_NAME}..."
    
    # Check current TTL status
    local ttl_status=$(aws dynamodb describe-time-to-live \
        --table-name "${TABLE_NAME}" \
        --region "${AWS_REGION}" \
        --query 'TimeToLiveDescription.TimeToLiveStatus' \
        --output text 2>/dev/null || echo "DISABLED")
    
    if [ "$ttl_status" = "DISABLED" ]; then
        print_warning "TTL is already disabled on table ${TABLE_NAME}"
        return 0
    fi
    
    # Disable TTL
    aws dynamodb update-time-to-live \
        --table-name "${TABLE_NAME}" \
        --time-to-live-specification \
            Enabled=false,AttributeName="${TTL_ATTRIBUTE:-expires_at}" \
        --region "${AWS_REGION}"
    
    # Wait a moment for the change to propagate
    sleep 2
    
    # Verify TTL is disabled
    local new_status=$(aws dynamodb describe-time-to-live \
        --table-name "${TABLE_NAME}" \
        --region "${AWS_REGION}" \
        --query 'TimeToLiveDescription.TimeToLiveStatus' \
        --output text 2>/dev/null || echo "DISABLED")
    
    if [ "$new_status" = "DISABLED" ]; then
        print_success "TTL disabled on table ${TABLE_NAME}"
    else
        print_warning "TTL status is: $new_status (may still be transitioning)"
    fi
}

# Delete the DynamoDB table
delete_table() {
    if [ "${DRY_RUN:-false}" = "true" ]; then
        print_info "[DRY RUN] Would delete table ${TABLE_NAME}"
        return 0
    fi
    
    print_info "Deleting DynamoDB table ${TABLE_NAME}..."
    
    # Get table info before deletion for logging
    local item_count=$(aws dynamodb describe-table \
        --table-name "${TABLE_NAME}" \
        --region "${AWS_REGION}" \
        --query 'Table.ItemCount' \
        --output text 2>/dev/null || echo "unknown")
    
    print_info "Table contains approximately ${item_count} items"
    
    # Delete the table
    aws dynamodb delete-table \
        --table-name "${TABLE_NAME}" \
        --region "${AWS_REGION}"
    
    # Wait for table deletion to complete
    print_info "Waiting for table deletion to complete..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ! aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${AWS_REGION}" &> /dev/null; then
            print_success "Table ${TABLE_NAME} deleted successfully"
            return 0
        fi
        
        print_info "Attempt ${attempt}/${max_attempts}: Table still exists, waiting..."
        sleep 10
        ((attempt++))
    done
    
    print_error "Table deletion did not complete within expected time"
    print_info "Please check the AWS console to verify table status"
    exit 1
}

# Clean up configuration files
cleanup_files() {
    if [ "${DRY_RUN:-false}" = "true" ]; then
        print_info "[DRY RUN] Would remove configuration file ${CONFIG_FILE}"
        return 0
    fi
    
    print_info "Cleaning up configuration files..."
    
    if [ -f "${CONFIG_FILE}" ]; then
        rm -f "${CONFIG_FILE}"
        print_success "Removed configuration file: ${CONFIG_FILE}"
    else
        print_info "Configuration file not found: ${CONFIG_FILE}"
    fi
    
    # Clean up environment variables if they're set
    if [ -n "${TABLE_NAME:-}" ]; then
        unset TABLE_NAME
    fi
    if [ -n "${TTL_ATTRIBUTE:-}" ]; then
        unset TTL_ATTRIBUTE
    fi
    if [ -n "${AWS_REGION:-}" ]; then
        # Don't unset AWS_REGION as it might be used by other processes
        print_info "AWS_REGION preserved for other processes"
    fi
    
    print_success "Environment variables cleaned up"
}

# Validate cleanup completion
validate_cleanup() {
    print_info "Validating cleanup completion..."
    
    # Check if table still exists
    if aws dynamodb describe-table --table-name "${TABLE_NAME}" --region "${AWS_REGION}" &> /dev/null; then
        print_error "Table ${TABLE_NAME} still exists!"
        return 1
    fi
    
    # Check if configuration file is removed
    if [ -f "${CONFIG_FILE}" ]; then
        print_error "Configuration file still exists: ${CONFIG_FILE}"
        return 1
    fi
    
    print_success "Cleanup validation completed"
}

# Display cleanup summary
display_summary() {
    print_success "DynamoDB TTL Recipe cleanup completed successfully!"
    echo
    print_info "=== CLEANUP SUMMARY ==="
    print_info "✅ TTL disabled (if it was enabled)"
    print_info "✅ DynamoDB table deleted: ${TABLE_NAME}"
    print_info "✅ Configuration files removed"
    print_info "✅ Environment variables cleaned up"
    echo
    print_info "All resources have been successfully removed."
    print_info "No ongoing costs should be incurred from this recipe."
    echo
    print_info "Cleanup log saved to: ${LOG_FILE}"
}

# Main execution
main() {
    print_info "Starting DynamoDB TTL Recipe cleanup..."
    print_info "Log file: ${LOG_FILE}"
    echo
    
    check_prerequisites
    
    # Try to load configuration, fall back to command line args if not found
    if [ ! -f "${CONFIG_FILE}" ] && [ $# -eq 0 ]; then
        print_error "No configuration file found and no arguments provided"
        print_info "Use --help for usage information"
        exit 1
    elif [ -f "${CONFIG_FILE}" ]; then
        load_configuration
    fi
    
    display_cleanup_plan
    confirm_cleanup
    
    # Only proceed with actual cleanup if table exists
    if check_table_exists; then
        disable_ttl
        delete_table
    else
        print_warning "Skipping table operations as table does not exist"
    fi
    
    cleanup_files
    
    if [ "${DRY_RUN:-false}" != "true" ]; then
        validate_cleanup
    fi
    
    display_summary
    
    print_success "Cleanup completed successfully!"
}

# Initialize variables
TABLE_NAME=""
AWS_REGION=""
TTL_ATTRIBUTE=""
FORCE_CLEANUP=false
DRY_RUN=false

# Parse command line arguments
parse_arguments "$@"

# Execute main function
main "$@"