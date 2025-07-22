#!/bin/bash

# AWS IoT Firmware Updates with Device Management Jobs - Cleanup Script
# This script safely removes all infrastructure created by the deploy.sh script
# including IoT Things, Lambda functions, S3 storage, and AWS Signer profiles

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

# Progress tracking
show_progress() {
    echo -e "${BLUE}[CLEANUP]${NC} $1..."
}

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [ -f ".env" ]; then
        # Source environment file
        set -a  # automatically export all variables
        source .env
        set +a
        log_success "Environment variables loaded from .env file"
    else
        log_warning ".env file not found. Attempting to use current environment variables."
        
        # Check if required variables are set
        local required_vars=("AWS_REGION" "FIRMWARE_BUCKET" "THING_NAME" "THING_GROUP" "JOB_ROLE_NAME" "LAMBDA_ROLE_NAME" "SIGNING_PROFILE_NAME")
        local missing_vars=()
        
        for var in "${required_vars[@]}"; do
            if [ -z "${!var:-}" ]; then
                missing_vars+=("$var")
            fi
        done
        
        if [ ${#missing_vars[@]} -gt 0 ]; then
            log_error "Missing required environment variables: ${missing_vars[*]}"
            log_error "Please ensure deploy.sh was run successfully or set variables manually."
            exit 1
        fi
    fi
    
    # Set AWS_ACCOUNT_ID if not already set
    if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    fi
    
    log_info "Using AWS Region: ${AWS_REGION}"
    log_info "Resources to clean up with identifiers containing: ${FIRMWARE_BUCKET##*-}"
}

# Confirmation prompt
confirm_destruction() {
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo
    echo "This script will DELETE the following resources:"
    echo "  • S3 Bucket: ${FIRMWARE_BUCKET} (and all contents)"
    echo "  • IoT Thing: ${THING_NAME}"
    echo "  • Thing Group: ${THING_GROUP}"
    echo "  • Lambda Function: firmware-update-manager"
    echo "  • IAM Roles: ${JOB_ROLE_NAME}, ${LAMBDA_ROLE_NAME}"
    echo "  • Signer Profile: ${SIGNING_PROFILE_NAME}"
    echo "  • CloudWatch Dashboard: IoT-Firmware-Updates"
    echo "  • Any IoT Jobs associated with these resources"
    echo
    
    if [ "${FORCE_DESTROY:-false}" = "true" ]; then
        log_warning "FORCE_DESTROY is set. Proceeding without confirmation."
        return 0
    fi
    
    echo -n "Are you sure you want to continue? (type 'yes' to confirm): "
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "Confirmation received. Starting cleanup..."
}

# Delete IoT Jobs and Executions
cleanup_iot_jobs() {
    show_progress "Cleaning up IoT Jobs and Executions"
    
    # List and cancel/delete active jobs
    local jobs
    jobs=$(aws iot list-jobs --query 'jobs[?status!=`COMPLETED` && status!=`CANCELED` && status!=`DELETED`].jobId' --output text 2>/dev/null || echo "")
    
    if [ -n "$jobs" ]; then
        for job_id in $jobs; do
            log_info "Processing job: $job_id"
            
            # Try to cancel the job first
            if aws iot cancel-job --job-id "$job_id" --reason-code "USER_INITIATED" --comment "Cleanup script" 2>/dev/null; then
                log_info "Cancelled job: $job_id"
                sleep 2  # Give time for cancellation to process
            fi
            
            # Force delete the job
            if aws iot delete-job --job-id "$job_id" --force 2>/dev/null; then
                log_success "Deleted job: $job_id"
            else
                log_warning "Could not delete job: $job_id (may not exist or already deleted)"
            fi
        done
    else
        log_info "No active IoT Jobs found to clean up"
    fi
    
    # Also try to clean up any jobs with our specific patterns
    local firmware_jobs
    firmware_jobs=$(aws iot list-jobs --query 'jobs[?contains(jobId, `firmware-update`)].jobId' --output text 2>/dev/null || echo "")
    
    if [ -n "$firmware_jobs" ]; then
        for job_id in $firmware_jobs; do
            log_info "Cleaning up firmware job: $job_id"
            aws iot cancel-job --job-id "$job_id" --reason-code "USER_INITIATED" --comment "Cleanup script" 2>/dev/null || true
            aws iot delete-job --job-id "$job_id" --force 2>/dev/null || true
        done
    fi
    
    log_success "IoT Jobs cleanup completed"
}

# Remove IoT Things and Thing Groups
cleanup_iot_resources() {
    show_progress "Removing IoT Things and Thing Groups"
    
    # Remove thing from thing group if it exists
    if aws iot describe-thing --thing-name "${THING_NAME}" &> /dev/null; then
        if aws iot describe-thing-group --thing-group-name "${THING_GROUP}" &> /dev/null; then
            aws iot remove-thing-from-thing-group \
                --thing-group-name "${THING_GROUP}" \
                --thing-name "${THING_NAME}" 2>/dev/null || log_warning "Could not remove thing from group"
            log_info "Removed thing from group"
        fi
        
        # Delete the thing
        if aws iot delete-thing --thing-name "${THING_NAME}" 2>/dev/null; then
            log_success "Deleted IoT Thing: ${THING_NAME}"
        else
            log_warning "Could not delete IoT Thing: ${THING_NAME}"
        fi
    else
        log_info "IoT Thing ${THING_NAME} not found (may already be deleted)"
    fi
    
    # Delete thing group
    if aws iot describe-thing-group --thing-group-name "${THING_GROUP}" &> /dev/null; then
        if aws iot delete-thing-group --thing-group-name "${THING_GROUP}" 2>/dev/null; then
            log_success "Deleted Thing Group: ${THING_GROUP}"
        else
            log_warning "Could not delete Thing Group: ${THING_GROUP}"
        fi
    else
        log_info "Thing Group ${THING_GROUP} not found (may already be deleted)"
    fi
}

# Delete Lambda Function
cleanup_lambda_function() {
    show_progress "Deleting Lambda function"
    
    if aws lambda get-function --function-name firmware-update-manager &> /dev/null; then
        if aws lambda delete-function --function-name firmware-update-manager 2>/dev/null; then
            log_success "Deleted Lambda function: firmware-update-manager"
        else
            log_warning "Could not delete Lambda function: firmware-update-manager"
        fi
    else
        log_info "Lambda function firmware-update-manager not found (may already be deleted)"
    fi
}

# Delete S3 Bucket and Contents
cleanup_s3_bucket() {
    show_progress "Deleting S3 bucket and all contents"
    
    if aws s3 ls "s3://${FIRMWARE_BUCKET}" &> /dev/null; then
        # Delete all objects and versions in bucket
        log_info "Deleting all objects in bucket..."
        aws s3 rm "s3://${FIRMWARE_BUCKET}" --recursive 2>/dev/null || log_warning "Some objects could not be deleted"
        
        # Delete all object versions if versioning is enabled
        log_info "Deleting all object versions..."
        aws s3api delete-objects \
            --bucket "${FIRMWARE_BUCKET}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${FIRMWARE_BUCKET}" \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                --max-items 1000)" 2>/dev/null || log_info "No versions to delete"
        
        # Delete all delete markers
        aws s3api delete-objects \
            --bucket "${FIRMWARE_BUCKET}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${FIRMWARE_BUCKET}" \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                --max-items 1000)" 2>/dev/null || log_info "No delete markers to remove"
        
        # Delete the bucket
        if aws s3 rb "s3://${FIRMWARE_BUCKET}" 2>/dev/null; then
            log_success "Deleted S3 bucket: ${FIRMWARE_BUCKET}"
        else
            log_warning "Could not delete S3 bucket: ${FIRMWARE_BUCKET} (may not be empty)"
        fi
    else
        log_info "S3 bucket ${FIRMWARE_BUCKET} not found (may already be deleted)"
    fi
}

# Remove IAM Roles and Policies
cleanup_iam_roles() {
    show_progress "Removing IAM roles and policies"
    
    # Clean up Lambda role
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &> /dev/null; then
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-name FirmwareUpdatePermissions 2>/dev/null || log_info "Inline policy already deleted"
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || log_info "Managed policy already detached"
        
        # Delete the role
        if aws iam delete-role --role-name "${LAMBDA_ROLE_NAME}" 2>/dev/null; then
            log_success "Deleted Lambda IAM role: ${LAMBDA_ROLE_NAME}"
        else
            log_warning "Could not delete Lambda IAM role: ${LAMBDA_ROLE_NAME}"
        fi
    else
        log_info "Lambda IAM role ${LAMBDA_ROLE_NAME} not found (may already be deleted)"
    fi
    
    # Clean up IoT Jobs role
    if aws iam get-role --role-name "${JOB_ROLE_NAME}" &> /dev/null; then
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "${JOB_ROLE_NAME}" \
            --policy-name IoTJobsS3Access 2>/dev/null || log_info "Inline policy already deleted"
        
        # Delete the role
        if aws iam delete-role --role-name "${JOB_ROLE_NAME}" 2>/dev/null; then
            log_success "Deleted IoT Jobs IAM role: ${JOB_ROLE_NAME}"
        else
            log_warning "Could not delete IoT Jobs IAM role: ${JOB_ROLE_NAME}"
        fi
    else
        log_info "IoT Jobs IAM role ${JOB_ROLE_NAME} not found (may already be deleted)"
    fi
}

# Delete Signing Profile and CloudWatch Resources
cleanup_signer_and_monitoring() {
    show_progress "Removing Signer profile and CloudWatch resources"
    
    # Cancel/delete signing profile
    if aws signer get-signing-profile --profile-name "${SIGNING_PROFILE_NAME}" &> /dev/null; then
        if aws signer cancel-signing-profile --profile-name "${SIGNING_PROFILE_NAME}" 2>/dev/null; then
            log_success "Cancelled signing profile: ${SIGNING_PROFILE_NAME}"
        else
            log_info "Signing profile ${SIGNING_PROFILE_NAME} could not be cancelled (may already be cancelled)"
        fi
    else
        log_info "Signing profile ${SIGNING_PROFILE_NAME} not found (may already be deleted)"
    fi
    
    # Delete CloudWatch dashboard
    if aws cloudwatch delete-dashboards --dashboard-names "IoT-Firmware-Updates" 2>/dev/null; then
        log_success "Deleted CloudWatch dashboard: IoT-Firmware-Updates"
    else
        log_info "CloudWatch dashboard IoT-Firmware-Updates not found (may already be deleted)"
    fi
}

# Clean up local files
cleanup_local_files() {
    show_progress "Cleaning up local files"
    
    local files_to_remove=(
        ".env"
        "iot-jobs-trust-policy.json"
        "iot-jobs-permission-policy.json"
        "lambda-trust-policy.json"
        "lambda-permission-policy.json"
        "firmware_update_manager.py"
        "firmware_update_manager.zip"
        "sample_firmware_v1.0.0.bin"
        "firmware_metadata.json"
        "iot_jobs_dashboard.json"
        "device_simulator.py"
        "job_response.json"
        "job_status.json"
        "cancel_test_response.json"
        "cancel_response.json"
        "downloaded_firmware.bin"
    )
    
    local removed_count=0
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            ((removed_count++))
        fi
    done
    
    if [ $removed_count -gt 0 ]; then
        log_success "Removed $removed_count local files"
    else
        log_info "No local files to clean up"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    show_progress "Verifying cleanup completion"
    
    local cleanup_issues=()
    
    # Check S3 bucket
    if aws s3 ls "s3://${FIRMWARE_BUCKET}" &> /dev/null; then
        cleanup_issues+=("S3 bucket ${FIRMWARE_BUCKET} still exists")
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name firmware-update-manager &> /dev/null; then
        cleanup_issues+=("Lambda function firmware-update-manager still exists")
    fi
    
    # Check IoT Thing
    if aws iot describe-thing --thing-name "${THING_NAME}" &> /dev/null; then
        cleanup_issues+=("IoT Thing ${THING_NAME} still exists")
    fi
    
    # Check Thing Group
    if aws iot describe-thing-group --thing-group-name "${THING_GROUP}" &> /dev/null; then
        cleanup_issues+=("Thing Group ${THING_GROUP} still exists")
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &> /dev/null; then
        cleanup_issues+=("Lambda IAM role ${LAMBDA_ROLE_NAME} still exists")
    fi
    
    if aws iam get-role --role-name "${JOB_ROLE_NAME}" &> /dev/null; then
        cleanup_issues+=("IoT Jobs IAM role ${JOB_ROLE_NAME} still exists")
    fi
    
    if [ ${#cleanup_issues[@]} -gt 0 ]; then
        log_warning "Some resources could not be completely cleaned up:"
        for issue in "${cleanup_issues[@]}"; do
            log_warning "  • $issue"
        done
        echo
        log_info "You may need to manually delete these resources in the AWS Console"
        log_info "This can happen due to dependencies or timing issues"
    else
        log_success "All resources have been successfully cleaned up"
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    echo
    log_success "🧹 Cleanup completed!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "The following resources have been removed:"
    echo "  ✓ S3 Bucket and all contents"
    echo "  ✓ IoT Thing and Thing Group"
    echo "  ✓ Lambda function and deployment package"
    echo "  ✓ IAM roles and policies"
    echo "  ✓ AWS Signer profile"
    echo "  ✓ CloudWatch dashboard"
    echo "  ✓ Local temporary files"
    echo
    echo "=== COST IMPACT ==="
    echo "  ✓ No ongoing charges from this recipe's resources"
    echo "  ✓ Only usage-based charges remain (if any)"
    echo
    log_info "Your AWS account is now clean of this recipe's infrastructure"
}

# Handle partial cleanup on error
cleanup_on_error() {
    log_error "Cleanup script encountered an error."
    log_info "Some resources may still exist. Please check the AWS Console and manually delete any remaining resources."
    exit 1
}

# Check AWS CLI and credentials
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Main cleanup function
main() {
    echo "🧹 Starting AWS IoT Firmware Updates cleanup..."
    echo
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_destruction
    
    echo
    log_info "Beginning resource cleanup..."
    
    cleanup_iot_jobs
    cleanup_iot_resources
    cleanup_lambda_function
    cleanup_s3_bucket
    cleanup_iam_roles
    cleanup_signer_and_monitoring
    cleanup_local_files
    verify_cleanup
    show_cleanup_summary
    
    echo
    log_success "Cleanup completed successfully! 🎉"
    exit 0
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Support for forced destruction (useful for CI/CD)
if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-f" ]; then
    export FORCE_DESTROY=true
    log_info "Force mode enabled - skipping confirmation prompts"
fi

# Run main function
main "$@"