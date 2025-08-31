#!/bin/bash

# Simple File Organization with S3 and Lambda - Cleanup Script
# This script removes all infrastructure created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Change to script directory
    cd "$(dirname "$0")"
    
    # Check if .env file exists
    if [ ! -f .env ]; then
        log_error ".env file not found. Please run deploy.sh first or provide resource names manually."
        log "You can also set the following environment variables manually:"
        log "  AWS_REGION, AWS_ACCOUNT_ID, BUCKET_NAME, FUNCTION_NAME, ROLE_NAME"
        exit 1
    fi
    
    # Load environment variables from .env file
    source .env
    
    log_success "Environment variables loaded"
    log "AWS Region: ${AWS_REGION}"
    log "Bucket Name: ${BUCKET_NAME}"
    log "Function Name: ${FUNCTION_NAME}"
    log "Role Name: ${ROLE_NAME}"
}

# Function to confirm destructive action
confirm_destruction() {
    log_warning "This will permanently delete all resources created by the deployment script:"
    log "  • S3 Bucket: ${BUCKET_NAME} (and all contents)"
    log "  • Lambda Function: ${FUNCTION_NAME}"
    log "  • IAM Role: ${ROLE_NAME}"
    log "  • Associated IAM policies"
    log ""
    
    # Check for force flag
    if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-f" ]; then
        log_warning "Force flag detected, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to remove S3 bucket and contents
remove_s3_resources() {
    log "Removing S3 bucket and all contents..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
        # Delete all objects in bucket (including versions if versioning is enabled)
        log "Deleting all objects and versions from bucket..."
        aws s3api delete-objects \
            --bucket ${BUCKET_NAME} \
            --delete "$(aws s3api list-object-versions \
                --bucket ${BUCKET_NAME} \
                --output json \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
        
        # Delete all delete markers if versioning was enabled
        aws s3api delete-objects \
            --bucket ${BUCKET_NAME} \
            --delete "$(aws s3api list-object-versions \
                --bucket ${BUCKET_NAME} \
                --output json \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
        
        # Alternative method using CLI
        aws s3 rm s3://${BUCKET_NAME} --recursive || true
        
        # Delete the bucket
        aws s3 rb s3://${BUCKET_NAME} --force
        
        log_success "S3 bucket deleted: ${BUCKET_NAME}"
    else
        log_warning "S3 bucket ${BUCKET_NAME} not found, skipping"
    fi
}

# Function to remove Lambda function
remove_lambda_function() {
    log "Removing Lambda function..."
    
    # Check if function exists
    if aws lambda get-function --function-name ${FUNCTION_NAME} &>/dev/null; then
        aws lambda delete-function --function-name ${FUNCTION_NAME}
        log_success "Lambda function deleted: ${FUNCTION_NAME}"
    else
        log_warning "Lambda function ${FUNCTION_NAME} not found, skipping"
    fi
}

# Function to remove IAM resources
remove_iam_resources() {
    log "Removing IAM resources..."
    
    # Check if role exists
    if aws iam get-role --role-name ${ROLE_NAME} &>/dev/null; then
        # Detach managed policies from role
        log "Detaching managed policies from role..."
        aws iam detach-role-policy \
            --role-name ${ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
        
        # Detach custom S3 policy
        aws iam detach-role-policy \
            --role-name ${ROLE_NAME} \
            --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-s3-policy || true
        
        # Delete custom S3 policy
        if aws iam get-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-s3-policy &>/dev/null; then
            aws iam delete-policy \
                --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-s3-policy
            log_success "Custom S3 policy deleted"
        fi
        
        # Delete IAM role
        aws iam delete-role --role-name ${ROLE_NAME}
        log_success "IAM role deleted: ${ROLE_NAME}"
    else
        log_warning "IAM role ${ROLE_NAME} not found, skipping"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files that might be left over
    rm -f trust-policy.json s3-policy.json notification.json
    rm -f lambda_function.py function.zip
    rm -f test-image.jpg test-document.pdf test-video.mp4 test-file.unknown
    
    # Remove .env file
    if [ -f .env ]; then
        rm -f .env
        log_success "Environment file cleaned up"
    fi
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_success=true
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
        log_error "S3 bucket still exists: ${BUCKET_NAME}"
        cleanup_success=false
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name ${FUNCTION_NAME} &>/dev/null; then
        log_error "Lambda function still exists: ${FUNCTION_NAME}"
        cleanup_success=false
    fi
    
    # Check IAM role
    if aws iam get-role --role-name ${ROLE_NAME} &>/dev/null; then
        log_error "IAM role still exists: ${ROLE_NAME}"
        cleanup_success=false
    fi
    
    if [ "$cleanup_success" = true ]; then
        log_success "All resources have been successfully removed"
    else
        log_warning "Some resources may still exist. Please check manually."
        return 1
    fi
}

# Function to display cleanup summary
display_summary() {
    log_success "=== CLEANUP COMPLETED ==="
    log ""
    log "🧹 All infrastructure resources have been removed:"
    log "  ✅ S3 Bucket and all contents"
    log "  ✅ Lambda Function"
    log "  ✅ IAM Role and policies"
    log "  ✅ Local temporary files"
    log ""
    log "💰 You should no longer incur charges for these resources."
    log ""
    log "📝 Note: CloudWatch logs may still exist and incur minimal charges."
    log "   You can remove them manually if needed:"
    log "   aws logs delete-log-group --log-group-name /aws/lambda/${FUNCTION_NAME}"
    log ""
}

# Function to handle partial cleanup on error
partial_cleanup_handler() {
    log_error "Cleanup process encountered an error at line $1"
    log_warning "Some resources may still exist. Please check the AWS console and remove them manually if needed."
    log ""
    log "Resources that may still exist:"
    log "  • S3 Bucket: ${BUCKET_NAME}"
    log "  • Lambda Function: ${FUNCTION_NAME}"
    log "  • IAM Role: ${ROLE_NAME}"
    log ""
    log "You can also try running this script again to complete the cleanup."
    exit 1
}

# Main cleanup function
main() {
    log "Starting cleanup of Simple File Organization infrastructure..."
    
    # Check for help flag
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --force, -f     Skip confirmation prompt"
        echo "  --help, -h      Show this help message"
        echo ""
        echo "This script removes all AWS resources created by deploy.sh"
        exit 0
    fi
    
    # Set up error handling
    trap 'partial_cleanup_handler $LINENO' ERR
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_destruction "$@"
    
    log "🗑️  Starting resource removal process..."
    
    remove_s3_resources
    remove_lambda_function
    remove_iam_resources
    cleanup_local_files
    verify_cleanup
    display_summary
}

# Run main function with all arguments
main "$@"