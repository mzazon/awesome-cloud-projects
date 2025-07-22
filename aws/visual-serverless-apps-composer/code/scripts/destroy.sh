#!/bin/bash

# Destroy Visual Serverless Application with AWS Infrastructure Composer and CodeCatalyst
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="/tmp/destroy-visual-serverless-$(date +%Y%m%d-%H%M%S).log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    log_error "Destruction encountered an error. Check log file: $LOG_FILE"
    log_error "Some resources may still exist. Please check AWS console manually."
    exit 1
}

trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    # Check if SAM CLI is installed (for optional SAM delete)
    if command -v sam &> /dev/null; then
        SAM_CLI_VERSION=$(sam --version 2>&1 | cut -d' ' -f4)
        log "SAM CLI version: $SAM_CLI_VERSION"
        SAM_AVAILABLE=true
    else
        log_warning "SAM CLI not found. Will use CloudFormation directly for cleanup"
        SAM_AVAILABLE=false
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "No AWS region configured, using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "Environment variables configured:"
    log "  - AWS_REGION: $AWS_REGION"
    log "  - AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    
    log_success "Environment variables set up successfully"
}

# Function to discover stacks to delete
discover_stacks() {
    log "Discovering CloudFormation stacks to delete..."
    
    # Look for stacks with common patterns
    STACK_PATTERNS=(
        "serverless-visual-app-*"
        "*-serverless-visual-app*"
        "*visual-serverless*"
        "*Application-Composer*"
        "*CodeCatalyst*"
    )
    
    STACKS_TO_DELETE=()
    
    for pattern in "${STACK_PATTERNS[@]}"; do
        log "Searching for stacks matching pattern: $pattern"
        
        # Get stacks matching pattern
        MATCHING_STACKS=$(aws cloudformation list-stacks \
            --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
            --query "StackSummaries[?contains(StackName, '${pattern//\*/}')].StackName" \
            --output text 2>/dev/null | tr '\t' '\n' | grep -v "^$" || true)
        
        if [ ! -z "$MATCHING_STACKS" ]; then
            while IFS= read -r stack; do
                if [ ! -z "$stack" ]; then
                    STACKS_TO_DELETE+=("$stack")
                fi
            done <<< "$MATCHING_STACKS"
        fi
    done
    
    # Remove duplicates
    UNIQUE_STACKS=($(printf '%s\n' "${STACKS_TO_DELETE[@]}" | sort -u))
    
    if [ ${#UNIQUE_STACKS[@]} -eq 0 ]; then
        log_warning "No CloudFormation stacks found with common patterns"
        return 0
    fi
    
    log "Found ${#UNIQUE_STACKS[@]} stack(s) to potentially delete:"
    for stack in "${UNIQUE_STACKS[@]}"; do
        log "  - $stack"
    done
    
    log_success "Stack discovery completed"
}

# Function to confirm deletion
confirm_deletion() {
    log "Confirming deletion of resources..."
    
    echo
    echo "=== DESTRUCTIVE OPERATION WARNING ==="
    echo "This script will DELETE the following resources:"
    echo
    
    if [ ${#UNIQUE_STACKS[@]} -gt 0 ]; then
        echo "CloudFormation Stacks:"
        for stack in "${UNIQUE_STACKS[@]}"; do
            echo "  - $stack"
        done
        echo
    fi
    
    echo "Additional cleanup will include:"
    echo "  - CloudWatch log groups"
    echo "  - S3 buckets (if empty)"
    echo "  - Local project files"
    echo
    
    echo "This action is IRREVERSIBLE and will destroy all data!"
    echo
    
    # Check if running in interactive mode
    if [ -t 0 ]; then
        read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
        if [[ ! $REPLY =~ ^yes$ ]]; then
            log "Deletion cancelled by user"
            exit 0
        fi
    else
        log_warning "Running in non-interactive mode. Proceeding with deletion."
    fi
    
    log_success "Deletion confirmed"
}

# Function to delete CloudFormation stacks
delete_cloudformation_stacks() {
    log "Deleting CloudFormation stacks..."
    
    if [ ${#UNIQUE_STACKS[@]} -eq 0 ]; then
        log_warning "No stacks to delete"
        return 0
    fi
    
    # Delete stacks in parallel for efficiency
    STACK_DELETE_JOBS=()
    
    for stack in "${UNIQUE_STACKS[@]}"; do
        log "Initiating deletion of stack: $stack"
        
        # Check if stack exists and is in a deletable state
        STACK_STATUS=$(aws cloudformation describe-stacks \
            --stack-name "$stack" \
            --region "$AWS_REGION" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$STACK_STATUS" = "NOT_FOUND" ]; then
            log_warning "Stack $stack not found, skipping"
            continue
        fi
        
        if [[ "$STACK_STATUS" =~ DELETE_IN_PROGRESS|DELETE_COMPLETE ]]; then
            log_warning "Stack $stack already being deleted or deleted, skipping"
            continue
        fi
        
        # Attempt to delete the stack
        if aws cloudformation delete-stack \
            --stack-name "$stack" \
            --region "$AWS_REGION" 2>/dev/null; then
            log "Stack deletion initiated: $stack"
            STACK_DELETE_JOBS+=("$stack")
        else
            log_error "Failed to initiate deletion of stack: $stack"
        fi
    done
    
    # Wait for stack deletions to complete
    if [ ${#STACK_DELETE_JOBS[@]} -gt 0 ]; then
        log "Waiting for stack deletions to complete..."
        
        for stack in "${STACK_DELETE_JOBS[@]}"; do
            log "Waiting for stack deletion: $stack"
            
            # Wait for stack deletion with timeout
            local timeout=1800  # 30 minutes
            local elapsed=0
            local interval=30
            
            while [ $elapsed -lt $timeout ]; do
                STACK_STATUS=$(aws cloudformation describe-stacks \
                    --stack-name "$stack" \
                    --region "$AWS_REGION" \
                    --query 'Stacks[0].StackStatus' \
                    --output text 2>/dev/null || echo "DELETE_COMPLETE")
                
                if [ "$STACK_STATUS" = "DELETE_COMPLETE" ]; then
                    log_success "Stack deleted successfully: $stack"
                    break
                elif [ "$STACK_STATUS" = "DELETE_FAILED" ]; then
                    log_error "Stack deletion failed: $stack"
                    # Try to get the failure reason
                    aws cloudformation describe-stack-events \
                        --stack-name "$stack" \
                        --region "$AWS_REGION" \
                        --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].ResourceStatusReason' \
                        --output text 2>/dev/null | head -3
                    break
                elif [[ "$STACK_STATUS" =~ DELETE_IN_PROGRESS ]]; then
                    log "Stack deletion in progress: $stack (${elapsed}s elapsed)"
                    sleep $interval
                    elapsed=$((elapsed + interval))
                else
                    log_warning "Unexpected stack status: $STACK_STATUS for $stack"
                    break
                fi
            done
            
            if [ $elapsed -ge $timeout ]; then
                log_error "Timeout waiting for stack deletion: $stack"
            fi
        done
    fi
    
    log_success "CloudFormation stack deletion completed"
}

# Function to clean up orphaned resources
cleanup_orphaned_resources() {
    log "Cleaning up orphaned resources..."
    
    # Clean up CloudWatch log groups
    log "Cleaning up CloudWatch log groups..."
    
    LOG_GROUPS=$(aws logs describe-log-groups \
        --region "$AWS_REGION" \
        --query 'logGroups[?contains(logGroupName, `serverless-visual`) || contains(logGroupName, `visual-serverless`) || contains(logGroupName, `/aws/lambda/`)].[logGroupName]' \
        --output text 2>/dev/null | tr '\t' '\n' | grep -v "^$" || true)
    
    if [ ! -z "$LOG_GROUPS" ]; then
        while IFS= read -r log_group; do
            if [ ! -z "$log_group" ]; then
                log "Deleting log group: $log_group"
                aws logs delete-log-group \
                    --log-group-name "$log_group" \
                    --region "$AWS_REGION" 2>/dev/null || log_warning "Failed to delete log group: $log_group"
            fi
        done <<< "$LOG_GROUPS"
    fi
    
    # Clean up S3 buckets (only if empty)
    log "Checking for S3 buckets to clean up..."
    
    S3_BUCKETS=$(aws s3api list-buckets \
        --query 'Buckets[?contains(Name, `serverless-visual`) || contains(Name, `visual-serverless`) || contains(Name, `codecatalyst`) || contains(Name, `sam-`) || contains(Name, `aws-sam-`)].Name' \
        --output text 2>/dev/null | tr '\t' '\n' | grep -v "^$" || true)
    
    if [ ! -z "$S3_BUCKETS" ]; then
        while IFS= read -r bucket; do
            if [ ! -z "$bucket" ]; then
                log "Checking S3 bucket: $bucket"
                
                # Check if bucket is empty
                OBJECT_COUNT=$(aws s3api list-objects-v2 \
                    --bucket "$bucket" \
                    --query 'KeyCount' \
                    --output text 2>/dev/null || echo "0")
                
                if [ "$OBJECT_COUNT" = "0" ]; then
                    log "Deleting empty S3 bucket: $bucket"
                    aws s3api delete-bucket \
                        --bucket "$bucket" \
                        --region "$AWS_REGION" 2>/dev/null || log_warning "Failed to delete S3 bucket: $bucket"
                else
                    log_warning "S3 bucket $bucket is not empty, skipping deletion"
                fi
            fi
        done <<< "$S3_BUCKETS"
    fi
    
    # Clean up IAM roles (be very careful with this)
    log "Checking for IAM roles to clean up..."
    
    IAM_ROLES=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `serverless-visual`) || contains(RoleName, `visual-serverless`) || contains(RoleName, `CodeCatalyst`)].RoleName' \
        --output text 2>/dev/null | tr '\t' '\n' | grep -v "^$" || true)
    
    if [ ! -z "$IAM_ROLES" ]; then
        while IFS= read -r role; do
            if [ ! -z "$role" ]; then
                log "Found IAM role: $role"
                log_warning "IAM role cleanup skipped for safety. Please review and delete manually if needed."
            fi
        done <<< "$IAM_ROLES"
    fi
    
    log_success "Orphaned resources cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # List of potential local directories to clean
    LOCAL_DIRS=(
        "$HOME/serverless-visual-app"
        "$HOME/visual-serverless-app"
        "$HOME/codecatalyst-project"
        "./serverless-visual-app"
        "./visual-serverless-app"
    )
    
    for dir in "${LOCAL_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            log "Found local directory: $dir"
            
            # Check if running in interactive mode
            if [ -t 0 ]; then
                read -p "Delete local directory $dir? [y/N]: " -r
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    log "Deleting local directory: $dir"
                    rm -rf "$dir"
                    log_success "Local directory deleted: $dir"
                else
                    log "Skipping local directory: $dir"
                fi
            else
                log_warning "Non-interactive mode: Skipping local directory deletion for safety"
            fi
        fi
    done
    
    # Clean up temporary files
    log "Cleaning up temporary files..."
    
    TEMP_FILES=(
        "/tmp/deploy-visual-serverless-*.log"
        "/tmp/destroy-visual-serverless-*.log"
        "./deployment-info.txt"
        "./samconfig.toml"
        "./.aws-sam"
    )
    
    for pattern in "${TEMP_FILES[@]}"; do
        if ls $pattern 1> /dev/null 2>&1; then
            log "Cleaning up: $pattern"
            rm -rf $pattern
        fi
    done
    
    log_success "Local files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    # Check for remaining CloudFormation stacks
    REMAINING_STACKS=$(aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query 'StackSummaries[?contains(StackName, `serverless-visual`) || contains(StackName, `visual-serverless`)].StackName' \
        --output text 2>/dev/null | tr '\t' '\n' | grep -v "^$" || true)
    
    if [ ! -z "$REMAINING_STACKS" ]; then
        log_warning "Found remaining CloudFormation stacks:"
        while IFS= read -r stack; do
            if [ ! -z "$stack" ]; then
                log "  - $stack"
            fi
        done <<< "$REMAINING_STACKS"
    else
        log_success "No remaining CloudFormation stacks found"
    fi
    
    # Check for remaining Lambda functions
    REMAINING_FUNCTIONS=$(aws lambda list-functions \
        --region "$AWS_REGION" \
        --query 'Functions[?contains(FunctionName, `serverless-visual`) || contains(FunctionName, `visual-serverless`)].FunctionName' \
        --output text 2>/dev/null | tr '\t' '\n' | grep -v "^$" || true)
    
    if [ ! -z "$REMAINING_FUNCTIONS" ]; then
        log_warning "Found remaining Lambda functions:"
        while IFS= read -r func; do
            if [ ! -z "$func" ]; then
                log "  - $func"
            fi
        done <<< "$REMAINING_FUNCTIONS"
    else
        log_success "No remaining Lambda functions found"
    fi
    
    # Check for remaining API Gateways
    REMAINING_APIS=$(aws apigateway get-rest-apis \
        --region "$AWS_REGION" \
        --query 'items[?contains(name, `serverless-visual`) || contains(name, `visual-serverless`)].name' \
        --output text 2>/dev/null | tr '\t' '\n' | grep -v "^$" || true)
    
    if [ ! -z "$REMAINING_APIS" ]; then
        log_warning "Found remaining API Gateways:"
        while IFS= read -r api; do
            if [ ! -z "$api" ]; then
                log "  - $api"
            fi
        done <<< "$REMAINING_APIS"
    else
        log_success "No remaining API Gateways found"
    fi
    
    # Check for remaining DynamoDB tables
    REMAINING_TABLES=$(aws dynamodb list-tables \
        --region "$AWS_REGION" \
        --query 'TableNames[?contains(@, `users-table`) || contains(@, `serverless-visual`)]' \
        --output text 2>/dev/null | tr '\t' '\n' | grep -v "^$" || true)
    
    if [ ! -z "$REMAINING_TABLES" ]; then
        log_warning "Found remaining DynamoDB tables:"
        while IFS= read -r table; do
            if [ ! -z "$table" ]; then
                log "  - $table"
            fi
        done <<< "$REMAINING_TABLES"
    else
        log_success "No remaining DynamoDB tables found"
    fi
    
    log_success "Cleanup verification completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Generating cleanup summary..."
    
    cat > cleanup-summary.txt << EOF
Cleanup Summary
===============

Timestamp: $(date)
AWS Account: $AWS_ACCOUNT_ID
AWS Region: $AWS_REGION

Actions Performed:
- CloudFormation stacks deleted: ${#UNIQUE_STACKS[@]}
- CloudWatch log groups cleaned up
- S3 buckets checked and cleaned (if empty)
- Local files cleaned up
- Verification completed

Stacks Deleted:
EOF
    
    if [ ${#UNIQUE_STACKS[@]} -gt 0 ]; then
        for stack in "${UNIQUE_STACKS[@]}"; do
            echo "  - $stack" >> cleanup-summary.txt
        done
    else
        echo "  - No stacks were deleted" >> cleanup-summary.txt
    fi
    
    cat >> cleanup-summary.txt << EOF

Important Notes:
- Some resources may have been skipped for safety
- IAM roles were not automatically deleted
- Please check AWS console for any remaining resources
- CodeCatalyst projects must be deleted manually from the console

Log File: $LOG_FILE
EOF
    
    log_success "Cleanup summary saved to: cleanup-summary.txt"
    echo
    echo "=== CLEANUP SUMMARY ==="
    cat cleanup-summary.txt
    echo
}

# Main destruction function
main() {
    log "Starting destruction of Visual Serverless Application..."
    log "Log file: $LOG_FILE"
    
    # Run destruction steps
    check_prerequisites
    setup_environment
    discover_stacks
    confirm_deletion
    delete_cloudformation_stacks
    cleanup_orphaned_resources
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    log_success "Destruction completed successfully!"
    log_success "Check cleanup-summary.txt for details"
    log_success "Log file available at: $LOG_FILE"
    
    echo
    echo "=== CLEANUP COMPLETED ==="
    echo "Most resources have been cleaned up automatically."
    echo "Please check the following manually:"
    echo "1. CodeCatalyst projects and spaces: https://codecatalyst.aws/"
    echo "2. IAM roles and policies (if any remain)"
    echo "3. S3 buckets with content"
    echo "4. Any custom resources not covered by this script"
    echo
    echo "If you encounter any issues, check the log file: $LOG_FILE"
    echo
}

# Run main function
main "$@"