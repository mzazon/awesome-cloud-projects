#!/bin/bash

# destroy.sh - Cleanup script for Serverless API Development with SAM and API Gateway
# This script safely removes all resources created by the deployment script

set -e

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in force mode (skip confirmations)
FORCE_MODE=false
if [[ "$1" == "--force" ]] || [[ "$1" == "-f" ]]; then
    FORCE_MODE=true
    warning "Running in force mode - skipping confirmation prompts"
fi

# Function to load deployment variables
load_deployment_vars() {
    if [[ -f "deployment_vars.env" ]]; then
        log "Loading deployment variables from deployment_vars.env..."
        source deployment_vars.env
        
        if [[ -z "${STACK_NAME:-}" ]]; then
            error "STACK_NAME not found in deployment_vars.env"
            return 1
        fi
        
        log "Loaded deployment configuration:"
        log "  Stack Name: ${STACK_NAME}"
        log "  Project Name: ${PROJECT_NAME:-unknown}"
        log "  AWS Region: ${AWS_REGION:-unknown}"
        
        return 0
    else
        warning "deployment_vars.env not found. Attempting to discover resources..."
        return 1
    fi
}

# Function to discover existing resources
discover_resources() {
    log "Attempting to discover SAM/CloudFormation stacks..."
    
    # List SAM-created stacks
    DISCOVERED_STACKS=$(aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query 'StackSummaries[?contains(StackName, `sam-api-`)].StackName' \
        --output text)
    
    if [[ -n "$DISCOVERED_STACKS" ]]; then
        echo ""
        echo "Found potential SAM API stacks:"
        echo "$DISCOVERED_STACKS" | tr '\t' '\n' | nl
        echo ""
        
        if ! $FORCE_MODE; then
            read -p "Enter the stack name to delete (or 'exit' to quit): " STACK_NAME
            if [[ "$STACK_NAME" == "exit" ]]; then
                log "Exiting without making changes"
                exit 0
            fi
        else
            # In force mode, select the first stack
            STACK_NAME=$(echo "$DISCOVERED_STACKS" | awk '{print $1}')
            warning "Force mode: selecting first stack: $STACK_NAME"
        fi
        
        # Set default region if not available
        if [[ -z "${AWS_REGION:-}" ]]; then
            export AWS_REGION=$(aws configure get region)
        fi
        
        return 0
    else
        error "No SAM API stacks found. Nothing to clean up."
        return 1
    fi
}

# Function to confirm destruction
confirm_destruction() {
    if $FORCE_MODE; then
        return 0
    fi
    
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   • CloudFormation Stack: ${STACK_NAME}"
    echo "   • All Lambda functions in the stack"
    echo "   • API Gateway REST API"
    echo "   • DynamoDB table and all data"
    echo "   • IAM roles and policies"
    echo "   • S3 bucket: ${S3_BUCKET_NAME:-unknown}"
    echo "   • CloudWatch dashboard: ${STACK_NAME}-monitoring"
    echo "   • CloudWatch log groups"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Last chance! Type 'DELETE' to proceed with destruction: " final_confirmation
    
    if [[ "$final_confirmation" != "DELETE" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
}

# Function to get stack resources before deletion
get_stack_resources() {
    log "Identifying stack resources..."
    
    # Get stack outputs for additional cleanup
    STACK_OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --query 'Stacks[0].Outputs' \
        --output json 2>/dev/null || echo '[]')
    
    # Extract important resource identifiers
    API_URL=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="ApiGatewayUrl") | .OutputValue' 2>/dev/null || echo "")
    TABLE_NAME=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="UsersTableName") | .OutputValue' 2>/dev/null || echo "")
    
    # Get physical resource IDs
    STACK_RESOURCES=$(aws cloudformation list-stack-resources \
        --stack-name "${STACK_NAME}" \
        --query 'StackResourceSummaries[].{Type:ResourceType,Id:PhysicalResourceId}' \
        --output json 2>/dev/null || echo '[]')
    
    log "Found stack resources to be deleted"
}

# Function to empty and delete S3 bucket
cleanup_s3_bucket() {
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        log "Cleaning up S3 bucket: ${S3_BUCKET_NAME}"
        
        # Check if bucket exists
        if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
            # Empty bucket first
            log "Emptying S3 bucket..."
            aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>/dev/null || true
            
            # Delete all versions and delete markers
            aws s3api list-object-versions \
                --bucket "${S3_BUCKET_NAME}" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | while read key version; do
                if [[ -n "$key" ]] && [[ -n "$version" ]]; then
                    aws s3api delete-object \
                        --bucket "${S3_BUCKET_NAME}" \
                        --key "$key" \
                        --version-id "$version" 2>/dev/null || true
                fi
            done
            
            # Delete delete markers
            aws s3api list-object-versions \
                --bucket "${S3_BUCKET_NAME}" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | while read key version; do
                if [[ -n "$key" ]] && [[ -n "$version" ]]; then
                    aws s3api delete-object \
                        --bucket "${S3_BUCKET_NAME}" \
                        --key "$key" \
                        --version-id "$version" 2>/dev/null || true
                fi
            done
            
            # Delete bucket
            log "Deleting S3 bucket..."
            aws s3api delete-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null || warning "Failed to delete S3 bucket"
            
            success "S3 bucket cleaned up"
        else
            log "S3 bucket ${S3_BUCKET_NAME} not found or already deleted"
        fi
    fi
}

# Function to delete CloudWatch dashboard
cleanup_cloudwatch_dashboard() {
    log "Cleaning up CloudWatch dashboard..."
    
    aws cloudwatch delete-dashboards \
        --dashboard-names "${STACK_NAME}-monitoring" 2>/dev/null || warning "CloudWatch dashboard not found or already deleted"
    
    success "CloudWatch dashboard cleaned up"
}

# Function to delete CloudWatch log groups
cleanup_cloudwatch_logs() {
    log "Cleaning up CloudWatch log groups..."
    
    # Find log groups related to this stack
    LOG_GROUPS=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/lambda/${STACK_NAME}" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$LOG_GROUPS" ]]; then
        for log_group in $LOG_GROUPS; do
            log "Deleting log group: $log_group"
            aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || warning "Failed to delete log group: $log_group"
        done
        success "CloudWatch log groups cleaned up"
    else
        log "No CloudWatch log groups found for this stack"
    fi
}

# Function to delete CloudFormation stack
delete_cloudformation_stack() {
    log "Deleting CloudFormation stack: ${STACK_NAME}"
    
    # Check if stack exists
    if ! aws cloudformation describe-stacks --stack-name "${STACK_NAME}" &>/dev/null; then
        warning "CloudFormation stack ${STACK_NAME} not found"
        return 0
    fi
    
    # Delete the stack
    aws cloudformation delete-stack --stack-name "${STACK_NAME}"
    
    log "Waiting for stack deletion to complete..."
    log "This may take several minutes..."
    
    # Wait for deletion with timeout
    local timeout=1800  # 30 minutes
    local elapsed=0
    local interval=30
    
    while [[ $elapsed -lt $timeout ]]; do
        if ! aws cloudformation describe-stacks --stack-name "${STACK_NAME}" &>/dev/null; then
            success "CloudFormation stack deleted successfully"
            return 0
        fi
        
        # Check for DELETE_FAILED status
        STACK_STATUS=$(aws cloudformation describe-stacks \
            --stack-name "${STACK_NAME}" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null || echo "DELETED")
        
        if [[ "$STACK_STATUS" == "DELETE_FAILED" ]]; then
            error "Stack deletion failed. Check the CloudFormation console for details."
            log "You may need to manually delete resources and retry stack deletion."
            return 1
        fi
        
        printf "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    error "Stack deletion timed out after ${timeout} seconds"
    return 1
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment variables
    if [[ -f "deployment_vars.env" ]]; then
        rm deployment_vars.env
        log "Removed deployment_vars.env"
    fi
    
    # Remove SAM project directory if it exists
    if [[ -n "${PROJECT_NAME:-}" ]] && [[ -d "${PROJECT_NAME}" ]]; then
        if ! $FORCE_MODE; then
            read -p "Remove local SAM project directory '${PROJECT_NAME}'? (y/N): " remove_dir
        else
            remove_dir="y"
        fi
        
        if [[ "$remove_dir" =~ ^[Yy]$ ]]; then
            rm -rf "${PROJECT_NAME}"
            log "Removed local project directory: ${PROJECT_NAME}"
        fi
    fi
    
    success "Local files cleaned up"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup completion..."
    
    # Check if stack still exists
    if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" &>/dev/null; then
        warning "CloudFormation stack still exists"
        return 1
    fi
    
    # Check if S3 bucket still exists
    if [[ -n "${S3_BUCKET_NAME:-}" ]] && aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
        warning "S3 bucket still exists"
        return 1
    fi
    
    success "Cleanup validation passed"
    return 0
}

# Function to show cleanup summary
show_cleanup_summary() {
    echo ""
    echo "🧹 Cleanup Summary"
    echo "=================="
    echo "✅ CloudFormation Stack: ${STACK_NAME} - DELETED"
    
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        echo "✅ S3 Bucket: ${S3_BUCKET_NAME} - DELETED"
    fi
    
    echo "✅ CloudWatch Dashboard: ${STACK_NAME}-monitoring - DELETED"
    echo "✅ CloudWatch Log Groups - CLEANED UP"
    echo "✅ Local Files - CLEANED UP"
    
    echo ""
    echo "All resources have been successfully removed!"
    echo "Total cleanup time: $(date)"
}

# Function to handle partial cleanup failures
handle_cleanup_failure() {
    error "Cleanup encountered errors!"
    echo ""
    echo "Manual cleanup may be required for:"
    echo "• CloudFormation Stack: ${STACK_NAME}"
    echo "• S3 Bucket: ${S3_BUCKET_NAME:-unknown}"
    echo "• CloudWatch Dashboard: ${STACK_NAME}-monitoring"
    echo ""
    echo "Check the AWS Console for any remaining resources."
    echo "You can re-run this script with --force to skip confirmations."
}

# Main execution flow
main() {
    echo "🗑️  Starting Serverless API Cleanup"
    echo "===================================="
    
    # Load configuration or discover resources
    if ! load_deployment_vars; then
        if ! discover_resources; then
            exit 1
        fi
    fi
    
    # Confirm destruction
    confirm_destruction
    
    # Get stack resources
    get_stack_resources
    
    echo ""
    log "Starting cleanup process..."
    
    # Cleanup in reverse order of creation
    cleanup_cloudwatch_dashboard
    cleanup_s3_bucket
    cleanup_cloudwatch_logs
    delete_cloudformation_stack
    cleanup_local_files
    
    # Validate cleanup
    if validate_cleanup; then
        show_cleanup_summary
    else
        handle_cleanup_failure
        exit 1
    fi
    
    echo ""
    echo "===================================="
    success "🎉 Cleanup completed successfully!"
}

# Handle script termination
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        handle_cleanup_failure
    fi
}

trap cleanup_on_exit EXIT

# Check prerequisites
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed or not in PATH"
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials are not configured"
    exit 1
fi

# Run main function
main "$@"