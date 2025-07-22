#!/bin/bash

# Destroy script for Amazon Connect Contact Center Solution
# This script safely removes all resources created by the deploy script

set -euo pipefail

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Check for deployment state file
    if [ ! -f "deployment_state.json" ]; then
        log_warning "deployment_state.json not found. Manual cleanup may be required."
        return 1
    fi
    
    log_success "Prerequisites check completed"
    return 0
}

# Load deployment state
load_deployment_state() {
    if [ -f "deployment_state.json" ]; then
        log_info "Loading deployment state..."
        
        # Extract values from deployment state
        DEPLOYMENT_ID=$(jq -r '.deployment_id' deployment_state.json)
        AWS_REGION=$(jq -r '.region' deployment_state.json)
        AWS_ACCOUNT_ID=$(jq -r '.account_id' deployment_state.json)
        
        INSTANCE_ID=$(jq -r '.resources.instance_id // empty' deployment_state.json)
        S3_BUCKET_NAME=$(jq -r '.resources.s3_bucket // empty' deployment_state.json)
        ADMIN_USER_ID=$(jq -r '.resources.admin_user_id // empty' deployment_state.json)
        AGENT_USER_ID=$(jq -r '.resources.agent_user_id // empty' deployment_state.json)
        CONTACT_NUMBER=$(jq -r '.resources.contact_number // empty' deployment_state.json)
        DASHBOARD_NAME=$(jq -r '.resources.dashboard_name // empty' deployment_state.json)
        
        log_info "Deployment ID: ${DEPLOYMENT_ID}"
        log_info "Region: ${AWS_REGION}"
        
        return 0
    else
        log_warning "No deployment state found. Proceeding with manual cleanup prompts."
        return 1
    fi
}

# Manual cleanup prompts
prompt_manual_cleanup() {
    log_warning "Manual cleanup mode - you'll need to provide resource identifiers"
    echo
    
    read -p "Enter AWS Region (default: us-east-1): " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}
    
    read -p "Enter Connect Instance ID (if known): " INSTANCE_ID
    read -p "Enter S3 Bucket Name (if known): " S3_BUCKET_NAME
    read -p "Enter Contact Number (if claimed): " CONTACT_NUMBER
    read -p "Enter CloudWatch Dashboard Name (if created): " DASHBOARD_NAME
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log_info "Manual cleanup configuration loaded"
}

# Confirmation prompt
confirm_destruction() {
    echo
    log_warning "This will permanently delete the following resources:"
    echo "  - Amazon Connect Instance: ${INSTANCE_ID:-'Unknown'}"
    echo "  - S3 Bucket and contents: ${S3_BUCKET_NAME:-'Unknown'}"
    echo "  - CloudWatch Dashboard: ${DASHBOARD_NAME:-'Unknown'}"
    if [ ! -z "${CONTACT_NUMBER:-}" ]; then
        echo "  - Phone Number: ${CONTACT_NUMBER}"
    fi
    echo "  - All associated users, queues, and contact flows"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    log_info "Proceeding with resource cleanup..."
}

# Safe resource deletion with error handling
safe_delete() {
    local action="$1"
    local resource="$2"
    
    log_info "Attempting to delete: $resource"
    
    if eval "$action" 2>/dev/null; then
        log_success "Deleted: $resource"
        return 0
    else
        log_warning "Failed to delete or resource not found: $resource"
        return 1
    fi
}

# Delete Connect users
delete_connect_users() {
    if [ -z "${INSTANCE_ID:-}" ]; then
        log_warning "Instance ID not available. Skipping user deletion."
        return
    fi
    
    log_info "Deleting Connect users..."
    
    # Delete admin user
    if [ ! -z "${ADMIN_USER_ID:-}" ]; then
        safe_delete "aws connect delete-user --instance-id ${INSTANCE_ID} --user-id ${ADMIN_USER_ID}" "Admin user"
    fi
    
    # Delete agent user
    if [ ! -z "${AGENT_USER_ID:-}" ]; then
        safe_delete "aws connect delete-user --instance-id ${INSTANCE_ID} --user-id ${AGENT_USER_ID}" "Agent user"
    fi
    
    # List and delete any other users created
    log_info "Checking for additional users to delete..."
    USER_LIST=$(aws connect list-users --instance-id ${INSTANCE_ID} --output json 2>/dev/null || echo '{"UserSummaryList":[]}')
    
    echo "$USER_LIST" | jq -r '.UserSummaryList[] | select(.Username | test("connect-admin|service-agent")) | .Id' | while read -r USER_ID; do
        if [ ! -z "$USER_ID" ]; then
            safe_delete "aws connect delete-user --instance-id ${INSTANCE_ID} --user-id ${USER_ID}" "Additional user: ${USER_ID}"
        fi
    done
}

# Release phone number
release_phone_number() {
    if [ -z "${CONTACT_NUMBER:-}" ]; then
        log_info "No phone number to release"
        return
    fi
    
    log_info "Releasing phone number..."
    
    # Get phone number ID
    PHONE_NUMBER_ID=$(aws connect list-phone-numbers \
        --instance-id ${INSTANCE_ID} \
        --query "PhoneNumberSummaryList[?PhoneNumber=='${CONTACT_NUMBER}'].Id" \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$PHONE_NUMBER_ID" ]; then
        safe_delete "aws connect release-phone-number --phone-number-id ${PHONE_NUMBER_ID}" "Phone number: ${CONTACT_NUMBER}"
    else
        log_warning "Phone number ID not found for: ${CONTACT_NUMBER}"
    fi
}

# Delete Connect instance
delete_connect_instance() {
    if [ -z "${INSTANCE_ID:-}" ]; then
        log_warning "Instance ID not available. Skipping instance deletion."
        return
    fi
    
    log_info "Deleting Connect instance..."
    log_warning "This may take several minutes to complete..."
    
    if aws connect delete-instance --instance-id ${INSTANCE_ID} 2>/dev/null; then
        log_info "Instance deletion initiated: ${INSTANCE_ID}"
        
        # Wait for deletion to complete
        log_info "Waiting for instance deletion to complete..."
        for i in {1..60}; do
            if ! aws connect describe-instance --instance-id ${INSTANCE_ID} &>/dev/null; then
                log_success "Connect instance deleted successfully"
                return 0
            fi
            
            if [ $i -eq 60 ]; then
                log_warning "Timeout waiting for instance deletion. It may still be in progress."
                return 1
            fi
            
            log_info "Instance still deleting... (${i}/60)"
            sleep 30
        done
    else
        log_warning "Failed to delete instance or instance not found: ${INSTANCE_ID}"
    fi
}

# Delete S3 bucket and contents
delete_s3_bucket() {
    if [ -z "${S3_BUCKET_NAME:-}" ]; then
        log_warning "S3 bucket name not available. Skipping bucket deletion."
        return
    fi
    
    log_info "Deleting S3 bucket and contents..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket ${S3_BUCKET_NAME} 2>/dev/null; then
        # Delete all objects in bucket
        log_info "Removing all objects from bucket..."
        aws s3 rm s3://${S3_BUCKET_NAME} --recursive 2>/dev/null || log_warning "Failed to delete some objects"
        
        # Delete the bucket
        safe_delete "aws s3 rb s3://${S3_BUCKET_NAME}" "S3 bucket: ${S3_BUCKET_NAME}"
    else
        log_warning "S3 bucket not found or already deleted: ${S3_BUCKET_NAME}"
    fi
}

# Delete CloudWatch dashboard
delete_cloudwatch_dashboard() {
    if [ -z "${DASHBOARD_NAME:-}" ]; then
        log_warning "Dashboard name not available. Skipping dashboard deletion."
        return
    fi
    
    log_info "Deleting CloudWatch dashboard..."
    safe_delete "aws cloudwatch delete-dashboards --dashboard-names ${DASHBOARD_NAME}" "CloudWatch dashboard: ${DASHBOARD_NAME}"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove temporary files
    for file in contact-flow.json dashboard-config.json; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_info "Removed temporary file: $file"
        fi
    done
    
    # Archive deployment state file
    if [ -f "deployment_state.json" ]; then
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        mv deployment_state.json "deployment_state_deleted_${TIMESTAMP}.json"
        log_info "Archived deployment state to: deployment_state_deleted_${TIMESTAMP}.json"
    fi
}

# Main cleanup function
cleanup_resources() {
    log_info "Starting resource cleanup..."
    
    # Step 1: Delete users first (they depend on the instance)
    delete_connect_users
    
    # Step 2: Release phone number
    release_phone_number
    
    # Step 3: Delete Connect instance (this will delete queues, flows, etc.)
    delete_connect_instance
    
    # Step 4: Delete S3 bucket
    delete_s3_bucket
    
    # Step 5: Delete CloudWatch dashboard
    delete_cloudwatch_dashboard
    
    # Step 6: Clean up local files
    cleanup_local_files
    
    log_success "Resource cleanup completed!"
}

# List orphaned resources
list_orphaned_resources() {
    log_info "Checking for potentially orphaned resources..."
    
    # List Connect instances
    echo
    log_info "Amazon Connect instances in region ${AWS_REGION}:"
    aws connect list-instances --output table 2>/dev/null || log_warning "Failed to list Connect instances"
    
    # List S3 buckets with 'connect' in the name
    echo
    log_info "S3 buckets containing 'connect' in the name:"
    aws s3api list-buckets --query "Buckets[?contains(Name, 'connect')].{Name:Name,CreationDate:CreationDate}" --output table 2>/dev/null || log_warning "Failed to list S3 buckets"
    
    # List CloudWatch dashboards
    echo
    log_info "CloudWatch dashboards containing 'Connect' in the name:"
    aws cloudwatch list-dashboards --query "DashboardEntries[?contains(DashboardName, 'Connect')].DashboardName" --output table 2>/dev/null || log_warning "Failed to list CloudWatch dashboards"
    
    echo
    log_info "If you see unexpected resources above, you may need to clean them up manually."
}

# Display help
show_help() {
    echo "Amazon Connect Contact Center Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help              Show this help message"
    echo "  --list-orphaned     List potentially orphaned resources without deleting"
    echo "  --force             Skip confirmation prompt (use with caution)"
    echo
    echo "This script will:"
    echo "  1. Delete all Connect users"
    echo "  2. Release claimed phone numbers"
    echo "  3. Delete the Connect instance"
    echo "  4. Delete the S3 bucket and all contents"
    echo "  5. Delete CloudWatch dashboard"
    echo "  6. Clean up local files"
    echo
    echo "The script looks for deployment_state.json to identify resources."
    echo "If not found, it will prompt for manual input."
}

# Main execution
main() {
    local FORCE_MODE=false
    local LIST_ORPHANED=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_help
                exit 0
                ;;
            --list-orphaned)
                LIST_ORPHANED=true
                shift
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo "================================================================"
    echo "Amazon Connect Contact Center Cleanup Script"
    echo "================================================================"
    echo
    
    # Check prerequisites
    if ! check_prerequisites; then
        if [ "$LIST_ORPHANED" = true ]; then
            prompt_manual_cleanup
            list_orphaned_resources
            exit 0
        else
            prompt_manual_cleanup
        fi
    else
        load_deployment_state
    fi
    
    # List orphaned resources if requested
    if [ "$LIST_ORPHANED" = true ]; then
        list_orphaned_resources
        exit 0
    fi
    
    # Confirm destruction unless force mode
    if [ "$FORCE_MODE" = false ]; then
        confirm_destruction
    else
        log_warning "Force mode enabled - skipping confirmation"
    fi
    
    # Perform cleanup
    cleanup_resources
    
    echo
    echo "================================================================"
    echo "Cleanup completed!"
    echo "================================================================"
    echo
    log_success "All Amazon Connect Contact Center resources have been removed"
    log_info "Thank you for using Amazon Connect!"
}

# Run main function with all arguments
main "$@"