#!/bin/bash

# AWS Transfer Family and Step Functions File Processing Pipeline Cleanup Script
# This script removes all infrastructure created by the deployment script
# Author: Recipe Generator
# Version: 1.0

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if AWS CLI is configured
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI installation
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not configured. Please set AWS_DEFAULT_REGION or run 'aws configure'."
        exit 1
    fi
    
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "AWS Region: ${AWS_REGION}"
    
    success "Prerequisites check completed"
}

# Function to prompt for confirmation
confirm_destruction() {
    echo -e "${YELLOW}WARNING: This script will permanently delete all resources created by the deployment script.${NC}"
    echo "This action cannot be undone!"
    echo ""
    
    # Try to detect project name from existing resources if not provided
    if [ -z "$PROJECT_NAME" ]; then
        log "Attempting to auto-detect project name..."
        
        # Look for Step Functions with file-processing prefix
        DETECTED_PROJECTS=$(aws stepfunctions list-state-machines \
            --query "stateMachines[?starts_with(name, 'file-processing-')].name" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$DETECTED_PROJECTS" ]; then
            echo "Detected projects:"
            for project in $DETECTED_PROJECTS; do
                echo "  - $project"
            done
            echo ""
        fi
        
        read -p "Enter the PROJECT_NAME to delete (e.g., file-processing-abc123): " PROJECT_NAME
        
        if [ -z "$PROJECT_NAME" ]; then
            error "PROJECT_NAME is required for cleanup"
            exit 1
        fi
    fi
    
    echo "Project to be deleted: ${PROJECT_NAME}"
    echo ""
    
    # List resources that will be deleted
    log "The following resources will be deleted:"
    echo "- S3 Buckets: ${PROJECT_NAME}-landing, ${PROJECT_NAME}-processed, ${PROJECT_NAME}-archive"
    echo "- Lambda Functions: ${PROJECT_NAME}-validator, ${PROJECT_NAME}-processor, ${PROJECT_NAME}-router"
    echo "- Step Functions: ${PROJECT_NAME}-workflow"
    echo "- Transfer Family server and users"
    echo "- IAM Roles and Policies"
    echo "- EventBridge rules and targets"
    echo "- CloudWatch alarms and SNS topics"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to load stored resource information
load_resource_info() {
    log "Loading stored resource information..."
    
    # Try to load from stored environment file
    if [ -f "/tmp/${PROJECT_NAME}-resources.env" ]; then
        source /tmp/${PROJECT_NAME}-resources.env
        log "Loaded resource information from /tmp/${PROJECT_NAME}-resources.env"
    else
        warning "Resource information file not found. Will attempt to discover resources."
    fi
    
    # Set bucket names
    export LANDING_BUCKET="${PROJECT_NAME}-landing"
    export PROCESSED_BUCKET="${PROJECT_NAME}-processed"
    export ARCHIVE_BUCKET="${PROJECT_NAME}-archive"
}

# Function to remove EventBridge and Step Functions resources
cleanup_eventbridge_stepfunctions() {
    log "Removing EventBridge and Step Functions resources..."
    
    # Remove EventBridge targets and rules
    aws events remove-targets \
        --rule ${PROJECT_NAME}-file-processing \
        --ids "1" 2>/dev/null || warning "EventBridge targets may not exist"
    
    aws events delete-rule \
        --name ${PROJECT_NAME}-file-processing 2>/dev/null || warning "EventBridge rule may not exist"
    
    # Get and delete Step Functions state machine
    STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?name=='${PROJECT_NAME}-workflow'].stateMachineArn" \
        --output text 2>/dev/null)
    
    if [ -n "$STATE_MACHINE_ARN" ] && [ "$STATE_MACHINE_ARN" != "None" ]; then
        aws stepfunctions delete-state-machine \
            --state-machine-arn ${STATE_MACHINE_ARN}
        success "Step Functions state machine deleted"
    else
        warning "Step Functions state machine not found"
    fi
}

# Function to remove Transfer Family resources
cleanup_transfer_family() {
    log "Removing Transfer Family resources..."
    
    # Get Transfer Family server ID
    if [ -z "$TRANSFER_SERVER_ID" ]; then
        TRANSFER_SERVER_ID=$(aws transfer list-servers \
            --query "Servers[?Tags[?Key=='Project' && Value=='${PROJECT_NAME}']].ServerId" \
            --output text 2>/dev/null)
    fi
    
    if [ -n "$TRANSFER_SERVER_ID" ] && [ "$TRANSFER_SERVER_ID" != "None" ]; then
        # Delete SFTP users first
        USERS=$(aws transfer list-users --server-id ${TRANSFER_SERVER_ID} \
            --query 'Users[].UserName' --output text 2>/dev/null || echo "")
        
        for user in $USERS; do
            if [ -n "$user" ]; then
                aws transfer delete-user \
                    --server-id ${TRANSFER_SERVER_ID} \
                    --user-name $user
                log "Deleted Transfer Family user: $user"
            fi
        done
        
        # Delete Transfer Family server
        aws transfer delete-server \
            --server-id ${TRANSFER_SERVER_ID}
        success "Transfer Family server deleted: ${TRANSFER_SERVER_ID}"
    else
        warning "Transfer Family server not found"
    fi
}

# Function to remove Lambda functions
cleanup_lambda_functions() {
    log "Removing Lambda functions..."
    
    # List of Lambda functions to delete
    LAMBDA_FUNCTIONS=(
        "${PROJECT_NAME}-validator"
        "${PROJECT_NAME}-processor"
        "${PROJECT_NAME}-router"
    )
    
    for function_name in "${LAMBDA_FUNCTIONS[@]}"; do
        if aws lambda get-function --function-name $function_name &>/dev/null; then
            aws lambda delete-function --function-name $function_name
            log "Deleted Lambda function: $function_name"
        else
            warning "Lambda function not found: $function_name"
        fi
    done
    
    success "Lambda functions cleanup completed"
}

# Function to remove S3 buckets and contents
cleanup_s3_buckets() {
    log "Removing S3 buckets and contents..."
    
    # List of S3 buckets to delete
    S3_BUCKETS=(
        "${LANDING_BUCKET}"
        "${PROCESSED_BUCKET}"
        "${ARCHIVE_BUCKET}"
    )
    
    for bucket in "${S3_BUCKETS[@]}"; do
        if aws s3api head-bucket --bucket $bucket &>/dev/null; then
            log "Emptying bucket: $bucket"
            
            # Remove all object versions and delete markers
            aws s3api list-object-versions --bucket $bucket \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text | while read key version; do
                if [ -n "$key" ] && [ -n "$version" ]; then
                    aws s3api delete-object --bucket $bucket --key "$key" --version-id "$version" >/dev/null
                fi
            done
            
            aws s3api list-object-versions --bucket $bucket \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text | while read key version; do
                if [ -n "$key" ] && [ -n "$version" ]; then
                    aws s3api delete-object --bucket $bucket --key "$key" --version-id "$version" >/dev/null
                fi
            done
            
            # Remove current objects
            aws s3 rm s3://$bucket --recursive >/dev/null 2>&1 || true
            
            # Delete bucket
            aws s3 rb s3://$bucket
            log "Deleted S3 bucket: $bucket"
        else
            warning "S3 bucket not found: $bucket"
        fi
    done
    
    success "S3 storage resources deleted"
}

# Function to remove CloudWatch and SNS resources
cleanup_monitoring() {
    log "Removing CloudWatch alarms and SNS topics..."
    
    # Delete CloudWatch alarms
    if aws cloudwatch describe-alarms --alarm-names ${PROJECT_NAME}-failed-executions &>/dev/null; then
        aws cloudwatch delete-alarms --alarm-names ${PROJECT_NAME}-failed-executions
        log "Deleted CloudWatch alarm: ${PROJECT_NAME}-failed-executions"
    else
        warning "CloudWatch alarm not found: ${PROJECT_NAME}-failed-executions"
    fi
    
    # Delete SNS topics
    TOPIC_ARN=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, '${PROJECT_NAME}-alerts')].TopicArn" \
        --output text 2>/dev/null)
    
    if [ -n "$TOPIC_ARN" ] && [ "$TOPIC_ARN" != "None" ]; then
        aws sns delete-topic --topic-arn ${TOPIC_ARN}
        log "Deleted SNS topic: ${TOPIC_ARN}"
    else
        warning "SNS topic not found: ${PROJECT_NAME}-alerts"
    fi
    
    success "Monitoring resources deleted"
}

# Function to remove IAM roles and policies
cleanup_iam_resources() {
    log "Removing IAM roles and policies..."
    
    # List of IAM roles to clean up
    IAM_ROLES=(
        "${PROJECT_NAME}-lambda-role"
        "${PROJECT_NAME}-transfer-role"
        "${PROJECT_NAME}-stepfunctions-role"
        "${PROJECT_NAME}-events-role"
    )
    
    # List of custom IAM policies to delete
    IAM_POLICIES=(
        "${PROJECT_NAME}-lambda-policy"
        "${PROJECT_NAME}-transfer-policy"
        "${PROJECT_NAME}-stepfunctions-policy"
        "${PROJECT_NAME}-events-policy"
    )
    
    # Detach policies from roles and delete roles
    for role in "${IAM_ROLES[@]}"; do
        if aws iam get-role --role-name $role &>/dev/null; then
            # Detach AWS managed policies
            case $role in
                *lambda-role)
                    aws iam detach-role-policy \
                        --role-name $role \
                        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
                    ;;
            esac
            
            # Detach custom policies
            for policy in "${IAM_POLICIES[@]}"; do
                aws iam detach-role-policy \
                    --role-name $role \
                    --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy 2>/dev/null || true
            done
            
            # Delete role
            aws iam delete-role --role-name $role
            log "Deleted IAM role: $role"
        else
            warning "IAM role not found: $role"
        fi
    done
    
    # Delete custom IAM policies
    for policy in "${IAM_POLICIES[@]}"; do
        if aws iam get-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy &>/dev/null; then
            aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy
            log "Deleted IAM policy: $policy"
        else
            warning "IAM policy not found: $policy"
        fi
    done
    
    success "IAM roles and policies deleted"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary resource files
    rm -f /tmp/${PROJECT_NAME}-resources.env
    rm -f /tmp/${PROJECT_NAME}-deployment-info.txt
    
    success "Temporary files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check S3 buckets
    for bucket in "${LANDING_BUCKET}" "${PROCESSED_BUCKET}" "${ARCHIVE_BUCKET}"; do
        if aws s3api head-bucket --bucket $bucket &>/dev/null; then
            error "S3 bucket still exists: $bucket"
            cleanup_errors=$((cleanup_errors + 1))
        fi
    done
    
    # Check Lambda functions
    for function_name in "${PROJECT_NAME}-validator" "${PROJECT_NAME}-processor" "${PROJECT_NAME}-router"; do
        if aws lambda get-function --function-name $function_name &>/dev/null; then
            error "Lambda function still exists: $function_name"
            cleanup_errors=$((cleanup_errors + 1))
        fi
    done
    
    # Check Step Functions state machine
    STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?name=='${PROJECT_NAME}-workflow'].stateMachineArn" \
        --output text 2>/dev/null)
    
    if [ -n "$STATE_MACHINE_ARN" ] && [ "$STATE_MACHINE_ARN" != "None" ]; then
        error "Step Functions state machine still exists: ${PROJECT_NAME}-workflow"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check IAM roles
    for role in "${PROJECT_NAME}-lambda-role" "${PROJECT_NAME}-transfer-role" "${PROJECT_NAME}-stepfunctions-role" "${PROJECT_NAME}-events-role"; do
        if aws iam get-role --role-name $role &>/dev/null; then
            error "IAM role still exists: $role"
            cleanup_errors=$((cleanup_errors + 1))
        fi
    done
    
    if [ $cleanup_errors -eq 0 ]; then
        success "Cleanup verification completed successfully"
    else
        error "Cleanup verification found $cleanup_errors remaining resources"
        error "You may need to manually remove these resources"
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "=================================="
    echo "Project Name: ${PROJECT_NAME}"
    echo "Cleanup completed: $(date)"
    echo ""
    echo "Resources removed:"
    echo "- S3 Buckets: ${LANDING_BUCKET}, ${PROCESSED_BUCKET}, ${ARCHIVE_BUCKET}"
    echo "- Lambda Functions: validator, processor, router"
    echo "- Step Functions workflow"
    echo "- Transfer Family server and users"
    echo "- IAM Roles and Policies"
    echo "- EventBridge rules and targets"
    echo "- CloudWatch alarms and SNS topics"
    echo ""
    success "All resources have been successfully removed!"
}

# Main cleanup function
main() {
    log "Starting AWS Transfer Family and Step Functions cleanup..."
    
    # Handle command line argument for project name
    if [ $# -eq 1 ]; then
        PROJECT_NAME=$1
        log "Using provided project name: ${PROJECT_NAME}"
    fi
    
    check_prerequisites
    confirm_destruction
    load_resource_info
    
    # Perform cleanup in reverse order of creation
    cleanup_eventbridge_stepfunctions
    cleanup_transfer_family
    cleanup_lambda_functions
    cleanup_s3_buckets
    cleanup_monitoring
    cleanup_iam_resources
    cleanup_temp_files
    
    # Verify cleanup
    if verify_cleanup; then
        display_cleanup_summary
    else
        error "Cleanup completed with some remaining resources. Please check manually."
        exit 1
    fi
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Display usage information
usage() {
    echo "Usage: $0 [PROJECT_NAME]"
    echo ""
    echo "Arguments:"
    echo "  PROJECT_NAME  Optional. The project name to clean up (e.g., file-processing-abc123)"
    echo "                If not provided, the script will attempt to auto-detect or prompt for it."
    echo ""
    echo "Examples:"
    echo "  $0                              # Interactive mode with auto-detection"
    echo "  $0 file-processing-abc123       # Direct cleanup of specific project"
    echo ""
    echo "This script will remove ALL resources created by the deployment script."
    echo "This action cannot be undone!"
}

# Handle help flag
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 0
fi

# Run main function
main "$@"