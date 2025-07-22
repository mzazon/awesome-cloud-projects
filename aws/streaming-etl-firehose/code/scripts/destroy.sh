#!/bin/bash

# Destroy script for Streaming ETL with Kinesis Data Firehose Transformations
# This script safely removes all resources created by the deploy script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or not authenticated"
        log_info "Please run 'aws configure' or set appropriate environment variables"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check for required commands
    local required_commands=("aws" "jq")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command '$cmd' is not installed"
            exit 1
        fi
    done
    
    # Check AWS authentication
    check_aws_auth
    
    log_success "Prerequisites check completed"
}

# Function to get user confirmation
confirm_destruction() {
    echo
    echo "=========================================="
    echo "  WARNING: DESTRUCTIVE OPERATION"
    echo "=========================================="
    echo
    echo "This script will permanently delete the following resources:"
    echo "- Kinesis Data Firehose delivery streams"
    echo "- Lambda functions"
    echo "- IAM roles and policies"
    echo "- S3 buckets and ALL their contents"
    echo "- CloudWatch log groups"
    echo
    echo "This action CANNOT be undone!"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    echo
    log_warning "Proceeding with resource destruction..."
    sleep 2
}

# Function to discover and set environment variables
discover_resources() {
    log_info "Discovering existing resources..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region is not configured"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Discover Firehose streams
    local firehose_streams
    firehose_streams=$(aws firehose list-delivery-streams \
        --query 'DeliveryStreamNames' --output text 2>/dev/null | tr '\t' '\n' | grep "streaming-etl-" || true)
    
    # Discover Lambda functions
    local lambda_functions
    lambda_functions=$(aws lambda list-functions \
        --query 'Functions[?starts_with(FunctionName, `firehose-transform-`)].FunctionName' \
        --output text 2>/dev/null | tr '\t' '\n' || true)
    
    # Discover S3 buckets
    local s3_buckets
    s3_buckets=$(aws s3api list-buckets \
        --query 'Buckets[?starts_with(Name, `streaming-etl-data-`)].Name' \
        --output text 2>/dev/null | tr '\t' '\n' || true)
    
    # Discover IAM roles
    local iam_roles
    iam_roles=$(aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `FirehoseDeliveryRole-`) || starts_with(RoleName, `FirehoseLambdaRole-`)].RoleName' \
        --output text 2>/dev/null | tr '\t' '\n' || true)
    
    # Store discovered resources in arrays
    FIREHOSE_STREAMS=($firehose_streams)
    LAMBDA_FUNCTIONS=($lambda_functions)
    S3_BUCKETS=($s3_buckets)
    IAM_ROLES=($iam_roles)
    
    # Display discovered resources
    echo
    echo "=== Discovered Resources ==="
    echo "Firehose Streams: ${#FIREHOSE_STREAMS[@]}"
    for stream in "${FIREHOSE_STREAMS[@]}"; do
        [[ -n "$stream" ]] && echo "  - $stream"
    done
    
    echo "Lambda Functions: ${#LAMBDA_FUNCTIONS[@]}"
    for func in "${LAMBDA_FUNCTIONS[@]}"; do
        [[ -n "$func" ]] && echo "  - $func"
    done
    
    echo "S3 Buckets: ${#S3_BUCKETS[@]}"
    for bucket in "${S3_BUCKETS[@]}"; do
        [[ -n "$bucket" ]] && echo "  - $bucket"
    done
    
    echo "IAM Roles: ${#IAM_ROLES[@]}"
    for role in "${IAM_ROLES[@]}"; do
        [[ -n "$role" ]] && echo "  - $role"
    done
    echo
    
    if [[ ${#FIREHOSE_STREAMS[@]} -eq 0 && ${#LAMBDA_FUNCTIONS[@]} -eq 0 && ${#S3_BUCKETS[@]} -eq 0 && ${#IAM_ROLES[@]} -eq 0 ]]; then
        log_info "No streaming ETL resources found to delete"
        exit 0
    fi
}

# Function to delete Firehose delivery streams
delete_firehose_streams() {
    if [[ ${#FIREHOSE_STREAMS[@]} -eq 0 ]]; then
        log_info "No Firehose delivery streams to delete"
        return 0
    fi
    
    log_info "Deleting Firehose delivery streams..."
    
    for stream in "${FIREHOSE_STREAMS[@]}"; do
        if [[ -n "$stream" ]]; then
            log_info "Deleting Firehose stream: $stream"
            
            # Check if stream exists
            if aws firehose describe-delivery-stream --delivery-stream-name "$stream" >/dev/null 2>&1; then
                aws firehose delete-delivery-stream --delivery-stream-name "$stream"
                log_success "Firehose stream $stream deletion initiated"
                
                # Wait for deletion to complete
                log_info "Waiting for stream deletion to complete..."
                local max_attempts=30
                local attempt=1
                
                while [[ $attempt -le $max_attempts ]]; do
                    if ! aws firehose describe-delivery-stream --delivery-stream-name "$stream" >/dev/null 2>&1; then
                        log_success "Firehose stream $stream deleted successfully"
                        break
                    fi
                    
                    if [[ $attempt -eq $max_attempts ]]; then
                        log_warning "Timeout waiting for stream deletion. Stream may still be deleting."
                        break
                    fi
                    
                    sleep 10
                    ((attempt++))
                done
            else
                log_warning "Firehose stream $stream not found"
            fi
        fi
    done
    
    log_success "Firehose streams cleanup completed"
}

# Function to delete Lambda functions
delete_lambda_functions() {
    if [[ ${#LAMBDA_FUNCTIONS[@]} -eq 0 ]]; then
        log_info "No Lambda functions to delete"
        return 0
    fi
    
    log_info "Deleting Lambda functions..."
    
    for func in "${LAMBDA_FUNCTIONS[@]}"; do
        if [[ -n "$func" ]]; then
            log_info "Deleting Lambda function: $func"
            
            if aws lambda get-function --function-name "$func" >/dev/null 2>&1; then
                aws lambda delete-function --function-name "$func"
                log_success "Lambda function $func deleted"
                
                # Delete associated CloudWatch log group
                local log_group="/aws/lambda/$func"
                if aws logs describe-log-groups --log-group-name-prefix "$log_group" \
                    --query 'logGroups[?logGroupName==`'$log_group'`]' --output text | grep -q "$log_group"; then
                    aws logs delete-log-group --log-group-name "$log_group"
                    log_success "CloudWatch log group $log_group deleted"
                fi
            else
                log_warning "Lambda function $func not found"
            fi
        fi
    done
    
    log_success "Lambda functions cleanup completed"
}

# Function to delete S3 buckets
delete_s3_buckets() {
    if [[ ${#S3_BUCKETS[@]} -eq 0 ]]; then
        log_info "No S3 buckets to delete"
        return 0
    fi
    
    log_info "Deleting S3 buckets and all contents..."
    
    for bucket in "${S3_BUCKETS[@]}"; do
        if [[ -n "$bucket" ]]; then
            log_info "Deleting S3 bucket: $bucket"
            
            # Check if bucket exists
            if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
                # Delete all objects in bucket (including versioned objects)
                log_info "Removing all objects from bucket $bucket..."
                
                # Delete all object versions
                aws s3api list-object-versions --bucket "$bucket" \
                    --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | \
                while read -r key version_id; do
                    if [[ -n "$key" && -n "$version_id" ]]; then
                        aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" >/dev/null 2>&1 || true
                    fi
                done
                
                # Delete all delete markers
                aws s3api list-object-versions --bucket "$bucket" \
                    --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null | \
                while read -r key version_id; do
                    if [[ -n "$key" && -n "$version_id" ]]; then
                        aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" >/dev/null 2>&1 || true
                    fi
                done
                
                # Use s3 rm for any remaining objects
                aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
                
                # Delete the bucket
                aws s3 rb "s3://$bucket" 2>/dev/null || aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
                log_success "S3 bucket $bucket deleted"
            else
                log_warning "S3 bucket $bucket not found"
            fi
        fi
    done
    
    log_success "S3 buckets cleanup completed"
}

# Function to delete IAM resources
delete_iam_resources() {
    if [[ ${#IAM_ROLES[@]} -eq 0 ]]; then
        log_info "No IAM roles to delete"
        return 0
    fi
    
    log_info "Deleting IAM roles and policies..."
    
    for role in "${IAM_ROLES[@]}"; do
        if [[ -n "$role" ]]; then
            log_info "Processing IAM role: $role"
            
            if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
                # Get attached policies
                local attached_policies
                attached_policies=$(aws iam list-attached-role-policies --role-name "$role" \
                    --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null | tr '\t' '\n' || true)
                
                # Detach managed policies
                for policy_arn in $attached_policies; do
                    if [[ -n "$policy_arn" ]]; then
                        log_info "Detaching policy: $policy_arn"
                        aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
                        
                        # Delete custom policies (not AWS managed)
                        if [[ "$policy_arn" == *":policy/"* ]] && [[ "$policy_arn" != *"aws:policy"* ]]; then
                            log_info "Deleting custom policy: $policy_arn"
                            aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null || true
                        fi
                    fi
                done
                
                # Get and delete inline policies
                local inline_policies
                inline_policies=$(aws iam list-role-policies --role-name "$role" \
                    --query 'PolicyNames' --output text 2>/dev/null | tr '\t' '\n' || true)
                
                for policy_name in $inline_policies; do
                    if [[ -n "$policy_name" ]]; then
                        log_info "Deleting inline policy: $policy_name"
                        aws iam delete-role-policy --role-name "$role" --policy-name "$policy_name" 2>/dev/null || true
                    fi
                done
                
                # Delete the role
                aws iam delete-role --role-name "$role"
                log_success "IAM role $role deleted"
            else
                log_warning "IAM role $role not found"
            fi
        fi
    done
    
    # Clean up any orphaned custom policies
    log_info "Checking for orphaned custom policies..."
    local custom_policies
    custom_policies=$(aws iam list-policies --scope Local \
        --query 'Policies[?starts_with(PolicyName, `FirehoseS3DeliveryPolicy-`) || starts_with(PolicyName, `FirehoseLambdaInvokePolicy-`)].Arn' \
        --output text 2>/dev/null | tr '\t' '\n' || true)
    
    for policy_arn in $custom_policies; do
        if [[ -n "$policy_arn" ]]; then
            log_info "Deleting orphaned policy: $policy_arn"
            aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null || true
        fi
    done
    
    log_success "IAM resources cleanup completed"
}

# Function to display cleanup summary
display_summary() {
    echo
    log_success "Cleanup completed successfully!"
    echo
    echo "=== Cleanup Summary ==="
    echo "✅ Firehose delivery streams: ${#FIREHOSE_STREAMS[@]} processed"
    echo "✅ Lambda functions: ${#LAMBDA_FUNCTIONS[@]} processed"
    echo "✅ S3 buckets: ${#S3_BUCKETS[@]} processed"
    echo "✅ IAM roles: ${#IAM_ROLES[@]} processed"
    echo
    echo "All streaming ETL pipeline resources have been removed."
    echo
    log_info "Note: It may take a few minutes for all AWS resources to be fully removed from the console"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    rm -f /tmp/firehose-streams.txt /tmp/lambda-functions.txt
    rm -f /tmp/s3-buckets.txt /tmp/iam-roles.txt
}

# Main cleanup function
main() {
    echo "========================================"
    echo "  Streaming ETL Pipeline Cleanup"
    echo "========================================"
    echo
    
    # Trap to cleanup on exit
    trap cleanup_temp_files EXIT
    
    check_prerequisites
    discover_resources
    confirm_destruction
    
    # Delete resources in reverse order of dependencies
    delete_firehose_streams
    delete_lambda_functions
    delete_s3_buckets
    delete_iam_resources
    
    display_summary
    
    log_success "Cleanup script completed successfully"
}

# Check for command line arguments
if [[ $# -gt 0 ]]; then
    case "$1" in
        --force)
            # Skip confirmation prompt (useful for automation)
            SKIP_CONFIRMATION=true
            ;;
        --help|-h)
            echo "Usage: $0 [--force] [--help]"
            echo
            echo "Options:"
            echo "  --force    Skip confirmation prompt"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            log_info "Use --help for usage information"
            exit 1
            ;;
    esac
fi

# Override confirmation function if --force is used
if [[ "${SKIP_CONFIRMATION:-false}" == "true" ]]; then
    confirm_destruction() {
        log_warning "Force mode enabled - skipping confirmation"
    }
fi

# Run main function
main "$@"