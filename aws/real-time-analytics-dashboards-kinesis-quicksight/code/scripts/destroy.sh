#!/bin/bash

# Real-time Analytics Dashboard Cleanup Script
# This script safely removes all resources created by the deployment script

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or credentials are invalid"
        log_info "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
}

# Function to load deployment state
load_deployment_state() {
    if [ -f "deployment-state.json" ]; then
        log_info "Loading deployment state from deployment-state.json"
        
        # Extract values from JSON using jq or fallback to grep/sed
        if command_exists jq; then
            export STREAM_NAME=$(jq -r '.resources.kinesis_stream' deployment-state.json)
            export FLINK_APP_NAME=$(jq -r '.resources.flink_application' deployment-state.json)
            export S3_BUCKET_NAME=$(jq -r '.resources.s3_bucket_results' deployment-state.json)
            export FLINK_CODE_BUCKET=$(jq -r '.resources.s3_bucket_code' deployment-state.json)
            export IAM_ROLE_NAME=$(jq -r '.resources.iam_role' deployment-state.json)
            export AWS_REGION=$(jq -r '.aws_region' deployment-state.json)
            export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' deployment-state.json)
        else
            # Fallback parsing without jq
            export STREAM_NAME=$(grep '"kinesis_stream"' deployment-state.json | cut -d'"' -f4)
            export FLINK_APP_NAME=$(grep '"flink_application"' deployment-state.json | cut -d'"' -f4)
            export S3_BUCKET_NAME=$(grep '"s3_bucket_results"' deployment-state.json | cut -d'"' -f4)
            export FLINK_CODE_BUCKET=$(grep '"s3_bucket_code"' deployment-state.json | cut -d'"' -f4)
            export IAM_ROLE_NAME=$(grep '"iam_role"' deployment-state.json | cut -d'"' -f4)
            export AWS_REGION=$(grep '"aws_region"' deployment-state.json | cut -d'"' -f4)
            export AWS_ACCOUNT_ID=$(grep '"aws_account_id"' deployment-state.json | cut -d'"' -f4)
        fi
        
        log_success "Loaded deployment state successfully"
        log_info "Region: ${AWS_REGION}"
        log_info "Stream: ${STREAM_NAME}"
        log_info "Flink App: ${FLINK_APP_NAME}"
        log_info "Buckets: ${S3_BUCKET_NAME}, ${FLINK_CODE_BUCKET}"
        log_info "IAM Role: ${IAM_ROLE_NAME}"
        
        return 0
    else
        log_warning "deployment-state.json not found"
        return 1
    fi
}

# Function to prompt for manual resource identification
prompt_manual_cleanup() {
    log_warning "No deployment state found. You'll need to specify resource names manually."
    echo
    
    read -p "Enter Kinesis stream name (or press Enter to skip): " STREAM_NAME
    read -p "Enter Flink application name (or press Enter to skip): " FLINK_APP_NAME
    read -p "Enter S3 results bucket name (or press Enter to skip): " S3_BUCKET_NAME
    read -p "Enter S3 code bucket name (or press Enter to skip): " FLINK_CODE_BUCKET
    read -p "Enter IAM role name (or press Enter to skip): " IAM_ROLE_NAME
    
    # Set AWS region if not already set
    if [ -z "${AWS_REGION:-}" ]; then
        AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            AWS_REGION="us-east-1"
            log_warning "Using default region: us-east-1"
        fi
    fi
    
    export STREAM_NAME FLINK_APP_NAME S3_BUCKET_NAME FLINK_CODE_BUCKET IAM_ROLE_NAME AWS_REGION
}

# Function to validate prerequisites for cleanup
validate_prerequisites() {
    log_info "Validating prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS configuration
    check_aws_config
    
    log_success "Prerequisites validation completed"
}

# Function to stop and delete Flink application
cleanup_flink_application() {
    if [ -z "${FLINK_APP_NAME:-}" ]; then
        log_warning "Flink application name not specified, skipping Flink cleanup"
        return 0
    fi
    
    log_info "Cleaning up Flink application: ${FLINK_APP_NAME}"
    
    # Check if application exists
    if ! aws kinesisanalyticsv2 describe-application \
        --application-name "${FLINK_APP_NAME}" >/dev/null 2>&1; then
        log_warning "Flink application ${FLINK_APP_NAME} not found or already deleted"
        return 0
    fi
    
    # Get application status
    local app_status=$(aws kinesisanalyticsv2 describe-application \
        --application-name "${FLINK_APP_NAME}" \
        --query 'ApplicationDetail.ApplicationStatus' \
        --output text 2>/dev/null || echo "UNKNOWN")
    
    log_info "Application status: ${app_status}"
    
    # Stop application if running
    if [ "$app_status" = "RUNNING" ]; then
        log_info "Stopping Flink application..."
        if aws kinesisanalyticsv2 stop-application \
            --application-name "${FLINK_APP_NAME}" >/dev/null 2>&1; then
            log_success "Stopped Flink application"
            
            # Wait for application to stop
            log_info "Waiting for application to stop..."
            local max_attempts=30
            local attempt=0
            while [ $attempt -lt $max_attempts ]; do
                local current_status=$(aws kinesisanalyticsv2 describe-application \
                    --application-name "${FLINK_APP_NAME}" \
                    --query 'ApplicationDetail.ApplicationStatus' \
                    --output text 2>/dev/null || echo "UNKNOWN")
                
                if [ "$current_status" = "READY" ] || [ "$current_status" = "UNKNOWN" ]; then
                    break
                fi
                
                attempt=$((attempt + 1))
                sleep 10
            done
        else
            log_warning "Failed to stop Flink application, attempting to delete anyway"
        fi
    fi
    
    # Delete application
    log_info "Deleting Flink application..."
    local create_timestamp=$(aws kinesisanalyticsv2 describe-application \
        --application-name "${FLINK_APP_NAME}" \
        --query 'ApplicationDetail.CreateTimestamp' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$create_timestamp" ]; then
        if aws kinesisanalyticsv2 delete-application \
            --application-name "${FLINK_APP_NAME}" \
            --create-timestamp "$create_timestamp" >/dev/null 2>&1; then
            log_success "Deleted Flink application: ${FLINK_APP_NAME}"
        else
            log_error "Failed to delete Flink application"
        fi
    else
        log_warning "Could not retrieve create timestamp for Flink application"
    fi
}

# Function to delete Kinesis Data Stream
cleanup_kinesis_stream() {
    if [ -z "${STREAM_NAME:-}" ]; then
        log_warning "Kinesis stream name not specified, skipping stream cleanup"
        return 0
    fi
    
    log_info "Deleting Kinesis Data Stream: ${STREAM_NAME}"
    
    # Check if stream exists
    if ! aws kinesis describe-stream \
        --stream-name "${STREAM_NAME}" >/dev/null 2>&1; then
        log_warning "Kinesis stream ${STREAM_NAME} not found or already deleted"
        return 0
    fi
    
    # Delete stream
    if aws kinesis delete-stream \
        --stream-name "${STREAM_NAME}" >/dev/null 2>&1; then
        log_success "Deleted Kinesis Data Stream: ${STREAM_NAME}"
    else
        log_error "Failed to delete Kinesis Data Stream"
    fi
}

# Function to clean up S3 buckets
cleanup_s3_buckets() {
    local buckets=()
    
    # Add buckets to cleanup list if they exist
    if [ -n "${S3_BUCKET_NAME:-}" ]; then
        buckets+=("${S3_BUCKET_NAME}")
    fi
    
    if [ -n "${FLINK_CODE_BUCKET:-}" ]; then
        buckets+=("${FLINK_CODE_BUCKET}")
    fi
    
    if [ ${#buckets[@]} -eq 0 ]; then
        log_warning "No S3 bucket names specified, skipping S3 cleanup"
        return 0
    fi
    
    for bucket in "${buckets[@]}"; do
        log_info "Cleaning up S3 bucket: ${bucket}"
        
        # Check if bucket exists
        if ! aws s3 ls "s3://${bucket}" >/dev/null 2>&1; then
            log_warning "S3 bucket ${bucket} not found or already deleted"
            continue
        fi
        
        # Empty bucket first
        log_info "Emptying S3 bucket: ${bucket}"
        if aws s3 rm "s3://${bucket}" --recursive >/dev/null 2>&1; then
            log_success "Emptied S3 bucket: ${bucket}"
        else
            log_warning "Failed to empty S3 bucket: ${bucket}"
        fi
        
        # Delete bucket
        log_info "Deleting S3 bucket: ${bucket}"
        if aws s3 rb "s3://${bucket}" >/dev/null 2>&1; then
            log_success "Deleted S3 bucket: ${bucket}"
        else
            log_error "Failed to delete S3 bucket: ${bucket}"
        fi
    done
}

# Function to clean up IAM role and policies
cleanup_iam_role() {
    if [ -z "${IAM_ROLE_NAME:-}" ]; then
        log_warning "IAM role name not specified, skipping IAM cleanup"
        return 0
    fi
    
    log_info "Cleaning up IAM role: ${IAM_ROLE_NAME}"
    
    # Check if role exists
    if ! aws iam get-role \
        --role-name "${IAM_ROLE_NAME}" >/dev/null 2>&1; then
        log_warning "IAM role ${IAM_ROLE_NAME} not found or already deleted"
        return 0
    fi
    
    # Delete inline policies
    log_info "Deleting IAM role policies..."
    local policies=$(aws iam list-role-policies \
        --role-name "${IAM_ROLE_NAME}" \
        --query 'PolicyNames' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$policies" ]; then
        for policy in $policies; do
            if aws iam delete-role-policy \
                --role-name "${IAM_ROLE_NAME}" \
                --policy-name "$policy" >/dev/null 2>&1; then
                log_success "Deleted policy: $policy"
            else
                log_warning "Failed to delete policy: $policy"
            fi
        done
    fi
    
    # Delete role
    log_info "Deleting IAM role..."
    if aws iam delete-role \
        --role-name "${IAM_ROLE_NAME}" >/dev/null 2>&1; then
        log_success "Deleted IAM role: ${IAM_ROLE_NAME}"
    else
        log_error "Failed to delete IAM role"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-state.json"
        "generate_sample_data.py"
        "flink-analytics-app"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -e "$file" ]; then
            rm -rf "$file"
            log_success "Removed: $file"
        fi
    done
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local issues=0
    
    # Check Flink application
    if [ -n "${FLINK_APP_NAME:-}" ]; then
        if aws kinesisanalyticsv2 describe-application \
            --application-name "${FLINK_APP_NAME}" >/dev/null 2>&1; then
            log_warning "Flink application still exists: ${FLINK_APP_NAME}"
            issues=$((issues + 1))
        fi
    fi
    
    # Check Kinesis stream
    if [ -n "${STREAM_NAME:-}" ]; then
        if aws kinesis describe-stream \
            --stream-name "${STREAM_NAME}" >/dev/null 2>&1; then
            log_warning "Kinesis stream still exists: ${STREAM_NAME}"
            issues=$((issues + 1))
        fi
    fi
    
    # Check S3 buckets
    for bucket in "${S3_BUCKET_NAME:-}" "${FLINK_CODE_BUCKET:-}"; do
        if [ -n "$bucket" ] && aws s3 ls "s3://$bucket" >/dev/null 2>&1; then
            log_warning "S3 bucket still exists: $bucket"
            issues=$((issues + 1))
        fi
    done
    
    # Check IAM role
    if [ -n "${IAM_ROLE_NAME:-}" ]; then
        if aws iam get-role \
            --role-name "${IAM_ROLE_NAME}" >/dev/null 2>&1; then
            log_warning "IAM role still exists: ${IAM_ROLE_NAME}"
            issues=$((issues + 1))
        fi
    fi
    
    if [ $issues -eq 0 ]; then
        log_success "Cleanup verification completed - all resources removed"
    else
        log_warning "Cleanup verification found $issues remaining resources"
        log_info "You may need to manually remove these resources"
    fi
}

# Function to run cleanup
run_cleanup() {
    log_info "Starting cleanup of Real-time Analytics Dashboard resources..."
    
    validate_prerequisites
    
    # Try to load deployment state, otherwise prompt for manual input
    if ! load_deployment_state; then
        prompt_manual_cleanup
    fi
    
    # Cleanup resources in reverse order of creation
    cleanup_flink_application
    cleanup_kinesis_stream
    cleanup_s3_buckets
    cleanup_iam_role
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    log_success "Cleanup completed!"
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help, -h          Show this help message"
    echo "  --force             Skip confirmation prompts"
    echo "  --verify-only       Only verify cleanup, don't delete resources"
    echo
    echo "This script safely removes all resources created by the deployment script."
    echo "It will attempt to load resource names from deployment-state.json."
    echo "If not found, you'll be prompted to enter resource names manually."
}

# Main execution
main() {
    local force_cleanup=false
    local verify_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --force)
                force_cleanup=true
                shift
                ;;
            --verify-only)
                verify_only=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo "=============================================="
    echo "Real-time Analytics Dashboard Cleanup"
    echo "=============================================="
    echo
    
    if [ "$verify_only" = true ]; then
        log_info "Verification mode - checking for remaining resources"
        validate_prerequisites
        if load_deployment_state; then
            verify_cleanup
        else
            log_warning "Cannot verify without deployment state"
        fi
        exit 0
    fi
    
    # Confirm cleanup unless forced
    if [ "$force_cleanup" = false ]; then
        echo -e "${RED}WARNING: This will permanently delete all deployed resources!${NC}"
        echo
        read -p "Are you sure you want to proceed with cleanup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi
    
    run_cleanup
}

# Script entry point
main "$@"