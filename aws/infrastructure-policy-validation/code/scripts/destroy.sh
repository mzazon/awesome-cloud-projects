#!/bin/bash

# Destroy script for CloudFormation Guard Infrastructure Policy Validation
# This script removes all resources created by the deployment

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to confirm destruction
confirm_destruction() {
    echo -e "${RED}⚠️  WARNING: This will permanently delete all CloudFormation Guard resources!${NC}"
    echo ""
    echo "This includes:"
    echo "  - S3 bucket and all Guard rules"
    echo "  - Local validation files"
    echo "  - Sample templates"
    echo "  - Generated scripts and reports"
    echo ""
    
    if [ "$FORCE_DESTROY" != "true" ]; then
        read -p "Are you sure you want to continue? (yes/no): " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log "Destruction cancelled by user"
            exit 0
        fi
    else
        warn "Force destroy mode enabled - skipping confirmation"
    fi
}

# Function to load environment configuration
load_environment_config() {
    info "Loading environment configuration..."
    
    # Try to load from .env-config file first
    if [ -f ".env-config" ]; then
        source .env-config
        log "Environment configuration loaded from .env-config"
    else
        warn ".env-config file not found, using fallback configuration"
        
        # Fallback environment setup
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
        fi
        
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        
        # Try to find bucket by pattern
        if [ -z "$BUCKET_NAME" ]; then
            BUCKET_NAME=$(aws s3 ls | grep "cfn-guard-policies-" | head -1 | awk '{print $3}' || echo "")
            if [ -n "$BUCKET_NAME" ]; then
                warn "Found bucket: $BUCKET_NAME"
                export BUCKET_NAME
            else
                error "Cannot determine bucket name. Please set BUCKET_NAME environment variable."
            fi
        fi
        
        export VALIDATION_ROLE_NAME="CloudFormationGuardValidationRole"
        export STACK_NAME="cfn-guard-demo-stack"
    fi
    
    # Validate required variables
    if [ -z "$BUCKET_NAME" ]; then
        error "BUCKET_NAME is not set. Cannot proceed with cleanup."
    fi
    
    log "Environment loaded:"
    log "  AWS Region: ${AWS_REGION:-unknown}"
    log "  AWS Account ID: ${AWS_ACCOUNT_ID:-unknown}"
    log "  S3 Bucket: $BUCKET_NAME"
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
    fi
    
    log "Prerequisites check completed"
}

# Function to empty and delete S3 bucket
destroy_s3_bucket() {
    info "Destroying S3 bucket and contents..."
    
    # Check if bucket exists
    if ! aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
        warn "S3 bucket $BUCKET_NAME does not exist, skipping deletion"
        return 0
    fi
    
    # List bucket contents for confirmation
    local object_count=$(aws s3 ls "s3://${BUCKET_NAME}" --recursive --summarize | grep "Total Objects:" | awk '{print $3}' || echo "0")
    log "Found $object_count objects in bucket $BUCKET_NAME"
    
    # Empty the bucket (delete all objects and versions)
    log "Emptying S3 bucket: $BUCKET_NAME"
    aws s3 rm "s3://${BUCKET_NAME}" --recursive
    
    # Delete all object versions (important for versioned buckets)
    log "Deleting all object versions..."
    aws s3api list-object-versions --bucket "$BUCKET_NAME" \
        --query 'Versions[].[Key,VersionId]' --output text | \
        while read key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id"
            fi
        done 2>/dev/null || true
    
    # Delete all delete markers
    log "Deleting all delete markers..."
    aws s3api list-object-versions --bucket "$BUCKET_NAME" \
        --query 'DeleteMarkers[].[Key,VersionId]' --output text | \
        while read key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id"
            fi
        done 2>/dev/null || true
    
    # Delete the bucket
    log "Deleting S3 bucket: $BUCKET_NAME"
    aws s3 rb "s3://${BUCKET_NAME}" --force
    
    log "✅ S3 bucket deleted successfully"
}

# Function to clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    local files_cleaned=0
    
    # List of files and directories to clean up
    local cleanup_items=(
        "guard-rules"
        "local-validation"
        "compliant-template.yaml"
        "non-compliant-template.yaml"
        "validate-template.sh"
        "ci-cd-validation.sh"
        "validation-report.json"
        "compliance-report.json"
        "validation-summary.txt"
        "rules-manifest.json"
        ".env-config"
    )
    
    for item in "${cleanup_items[@]}"; do
        if [ -e "$item" ]; then
            if [ -d "$item" ]; then
                log "Removing directory: $item"
                rm -rf "$item"
            else
                log "Removing file: $item"
                rm -f "$item"
            fi
            ((files_cleaned++))
        fi
    done
    
    # Clean up any remaining Guard-related files
    find . -name "*guard*" -type f -delete 2>/dev/null || true
    find . -name "*compliance*" -type f -delete 2>/dev/null || true
    
    log "✅ Cleaned up $files_cleaned local items"
}

# Function to remove IAM resources (if any were created)
cleanup_iam_resources() {
    info "Checking for IAM resources to clean up..."
    
    # Check if validation role exists
    if aws iam get-role --role-name "$VALIDATION_ROLE_NAME" &> /dev/null; then
        warn "Found IAM role: $VALIDATION_ROLE_NAME"
        
        # Detach managed policies
        aws iam list-attached-role-policies --role-name "$VALIDATION_ROLE_NAME" \
            --query 'AttachedPolicies[].PolicyArn' --output text | \
            xargs -r -n1 aws iam detach-role-policy --role-name "$VALIDATION_ROLE_NAME" --policy-arn
        
        # Delete inline policies
        aws iam list-role-policies --role-name "$VALIDATION_ROLE_NAME" \
            --query 'PolicyNames[]' --output text | \
            xargs -r -n1 aws iam delete-role-policy --role-name "$VALIDATION_ROLE_NAME" --policy-name
        
        # Delete the role
        aws iam delete-role --role-name "$VALIDATION_ROLE_NAME"
        log "✅ IAM role deleted: $VALIDATION_ROLE_NAME"
    else
        log "No IAM role found to clean up"
    fi
}

# Function to remove CloudFormation stacks (if any exist)
cleanup_cloudformation_stacks() {
    info "Checking for CloudFormation stacks to clean up..."
    
    # Check if demo stack exists
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &> /dev/null; then
        warn "Found CloudFormation stack: $STACK_NAME"
        
        log "Deleting CloudFormation stack: $STACK_NAME"
        aws cloudformation delete-stack --stack-name "$STACK_NAME"
        
        # Wait for stack deletion to complete
        log "Waiting for stack deletion to complete..."
        aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" || true
        
        log "✅ CloudFormation stack deleted: $STACK_NAME"
    else
        log "No CloudFormation stack found to clean up"
    fi
}

# Function to clean up environment variables
cleanup_environment_variables() {
    info "Cleaning up environment variables..."
    
    unset AWS_REGION 2>/dev/null || true
    unset AWS_ACCOUNT_ID 2>/dev/null || true
    unset BUCKET_NAME 2>/dev/null || true
    unset VALIDATION_ROLE_NAME 2>/dev/null || true
    unset STACK_NAME 2>/dev/null || true
    unset RANDOM_SUFFIX 2>/dev/null || true
    
    log "✅ Environment variables cleaned up"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed successfully!"
    log ""
    log "📋 Cleanup Summary:"
    log "  ✅ S3 bucket and contents removed"
    log "  ✅ Local files and directories cleaned up"
    log "  ✅ IAM resources checked and cleaned"
    log "  ✅ CloudFormation stacks checked and cleaned"
    log "  ✅ Environment variables cleared"
    log ""
    log "🎯 All CloudFormation Guard resources have been removed."
    log ""
    log "Note: If you have custom Guard rules or templates elsewhere,"
    log "      those will need to be cleaned up manually."
}

# Function to handle partial cleanup on error
cleanup_on_error() {
    warn "Cleanup was interrupted. Some resources may still exist."
    warn "You may need to manually clean up:"
    warn "  - S3 bucket: ${BUCKET_NAME:-unknown}"
    warn "  - Local files in current directory"
    warn "  - IAM role: ${VALIDATION_ROLE_NAME:-CloudFormationGuardValidationRole}"
    warn "  - CloudFormation stack: ${STACK_NAME:-cfn-guard-demo-stack}"
    exit 1
}

# Function to perform dry run
perform_dry_run() {
    info "Performing dry run - no resources will be deleted"
    log ""
    log "Would delete the following resources:"
    
    # Check S3 bucket
    if aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
        local object_count=$(aws s3 ls "s3://${BUCKET_NAME}" --recursive --summarize | grep "Total Objects:" | awk '{print $3}' || echo "0")
        log "  📦 S3 bucket: $BUCKET_NAME ($object_count objects)"
    else
        log "  📦 S3 bucket: $BUCKET_NAME (not found)"
    fi
    
    # Check local files
    local local_items=(
        "guard-rules" "local-validation" "compliant-template.yaml"
        "non-compliant-template.yaml" "validate-template.sh" "ci-cd-validation.sh"
        "validation-report.json" "compliance-report.json" "validation-summary.txt"
        "rules-manifest.json" ".env-config"
    )
    
    local found_count=0
    for item in "${local_items[@]}"; do
        if [ -e "$item" ]; then
            ((found_count++))
        fi
    done
    log "  📁 Local files: $found_count items found"
    
    # Check IAM role
    if aws iam get-role --role-name "$VALIDATION_ROLE_NAME" &> /dev/null; then
        log "  👤 IAM role: $VALIDATION_ROLE_NAME (exists)"
    else
        log "  👤 IAM role: $VALIDATION_ROLE_NAME (not found)"
    fi
    
    # Check CloudFormation stack
    if aws cloudformation describe-stacks --stack-name "$STACK_NAME" &> /dev/null; then
        log "  ☁️  CloudFormation stack: $STACK_NAME (exists)"
    else
        log "  ☁️  CloudFormation stack: $STACK_NAME (not found)"
    fi
    
    log ""
    log "Dry run completed. Use --force to proceed with actual cleanup."
}

# Main destroy function
main() {
    log "Starting CloudFormation Guard cleanup..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_DESTROY=true
                shift
                ;;
            --dry-run)
                export DRY_RUN=true
                shift
                ;;
            --bucket)
                export BUCKET_NAME="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --force         Skip confirmation prompts"
                echo "  --dry-run       Show what would be deleted without deleting"
                echo "  --bucket NAME   Specify bucket name to delete"
                echo "  -h, --help      Show this help message"
                exit 0
                ;;
            *)
                warn "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    check_prerequisites
    load_environment_config
    
    if [ "$DRY_RUN" = "true" ]; then
        perform_dry_run
        exit 0
    fi
    
    confirm_destruction
    
    # Set up error handling
    trap cleanup_on_error ERR INT TERM
    
    # Perform cleanup steps
    destroy_s3_bucket
    cleanup_local_files
    cleanup_iam_resources
    cleanup_cloudformation_stacks
    cleanup_environment_variables
    
    # Remove error trap
    trap - ERR INT TERM
    
    display_cleanup_summary
}

# Handle script arguments and run main function
main "$@"