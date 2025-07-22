#!/bin/bash

# AWS Reserved Instance Management Automation - Cleanup Script
# This script removes all resources created by the deployment script

set -e
set -o pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI not authenticated. Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    success "AWS CLI authentication verified"
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    success "AWS CLI found"
    
    # Check AWS authentication
    check_aws_auth
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f ".env_vars" ]; then
        source .env_vars
        success "Environment variables loaded from .env_vars"
        log "Project Name: ${PROJECT_NAME}"
        log "Region: ${AWS_REGION}"
    else
        warning ".env_vars file not found. You may need to provide resource names manually."
        
        # Try to detect resources by pattern
        read -p "Enter project name (or press Enter to search for resources): " PROJECT_NAME
        
        if [ -z "$PROJECT_NAME" ]; then
            log "Searching for RI management resources..."
            # This is a fallback - we'll try to find resources by pattern
            PROJECT_NAME="ri-management"
        fi
        
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warning "AWS region not configured, defaulting to us-east-1"
        fi
        
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "======================================"
    echo "           CLEANUP WARNING"
    echo "======================================"
    echo ""
    echo "This script will PERMANENTLY DELETE the following resources:"
    echo ""
    echo "  • S3 Bucket: ${S3_BUCKET_NAME:-ri-reports-*}"
    echo "  • SNS Topic: ${SNS_TOPIC_NAME:-ri-alerts-*}"
    echo "  • DynamoDB Table: ${DYNAMODB_TABLE_NAME:-ri-tracking-*}"
    echo "  • IAM Role: ${PROJECT_NAME}-lambda-role"
    echo "  • Lambda Functions: ${PROJECT_NAME}-ri-*"
    echo "  • EventBridge Rules: ${PROJECT_NAME}-*"
    echo ""
    echo "  Region: ${AWS_REGION}"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " CONFIRMATION
    
    if [ "$CONFIRMATION" != "DELETE" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed deletion. Proceeding with cleanup..."
}

# Function to delete EventBridge rules and targets
delete_eventbridge_rules() {
    log "Deleting EventBridge rules and targets..."
    
    # List of rule names to delete
    RULES=(
        "${PROJECT_NAME}-daily-utilization"
        "${PROJECT_NAME}-weekly-recommendations"
        "${PROJECT_NAME}-weekly-monitoring"
    )
    
    for rule in "${RULES[@]}"; do
        if aws events describe-rule --name "$rule" --region "${AWS_REGION}" >/dev/null 2>&1; then
            log "Deleting rule: $rule"
            
            # Remove targets first
            TARGET_IDS=$(aws events list-targets-by-rule --rule "$rule" --region "${AWS_REGION}" \
                --query 'Targets[].Id' --output text 2>/dev/null || echo "")
            
            if [ -n "$TARGET_IDS" ]; then
                aws events remove-targets \
                    --rule "$rule" \
                    --ids $TARGET_IDS \
                    --region "${AWS_REGION}" >/dev/null 2>&1 || true
            fi
            
            # Delete the rule
            aws events delete-rule \
                --name "$rule" \
                --region "${AWS_REGION}" >/dev/null 2>&1 || true
            
            success "Deleted EventBridge rule: $rule"
        else
            warning "EventBridge rule not found: $rule"
        fi
    done
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    # List of function names to delete
    FUNCTIONS=(
        "${PROJECT_NAME}-ri-utilization"
        "${PROJECT_NAME}-ri-recommendations"
        "${PROJECT_NAME}-ri-monitoring"
    )
    
    for func in "${FUNCTIONS[@]}"; do
        if aws lambda get-function --function-name "$func" --region "${AWS_REGION}" >/dev/null 2>&1; then
            log "Deleting Lambda function: $func"
            aws lambda delete-function \
                --function-name "$func" \
                --region "${AWS_REGION}" >/dev/null 2>&1 || true
            success "Deleted Lambda function: $func"
        else
            warning "Lambda function not found: $func"
        fi
    done
}

# Function to delete IAM role and policies
delete_iam_role() {
    log "Deleting IAM role and policies..."
    
    ROLE_NAME="${PROJECT_NAME}-lambda-role"
    
    if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
        log "Deleting IAM role: $ROLE_NAME"
        
        # Detach managed policies
        MANAGED_POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" \
            --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        
        for policy_arn in $MANAGED_POLICIES; do
            if [ -n "$policy_arn" ]; then
                aws iam detach-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-arn "$policy_arn" >/dev/null 2>&1 || true
                log "Detached managed policy: $policy_arn"
            fi
        done
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" \
            --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
        
        for policy_name in $INLINE_POLICIES; do
            if [ -n "$policy_name" ]; then
                aws iam delete-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-name "$policy_name" >/dev/null 2>&1 || true
                log "Deleted inline policy: $policy_name"
            fi
        done
        
        # Delete the role
        aws iam delete-role --role-name "$ROLE_NAME" >/dev/null 2>&1 || true
        success "Deleted IAM role: $ROLE_NAME"
    else
        warning "IAM role not found: $ROLE_NAME"
    fi
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    log "Deleting DynamoDB table..."
    
    if [ -n "$DYNAMODB_TABLE_NAME" ]; then
        if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" --region "${AWS_REGION}" >/dev/null 2>&1; then
            log "Deleting DynamoDB table: $DYNAMODB_TABLE_NAME"
            aws dynamodb delete-table \
                --table-name "$DYNAMODB_TABLE_NAME" \
                --region "${AWS_REGION}" >/dev/null 2>&1 || true
            
            log "Waiting for DynamoDB table deletion..."
            aws dynamodb wait table-not-exists \
                --table-name "$DYNAMODB_TABLE_NAME" \
                --region "${AWS_REGION}" 2>/dev/null || true
            
            success "Deleted DynamoDB table: $DYNAMODB_TABLE_NAME"
        else
            warning "DynamoDB table not found: $DYNAMODB_TABLE_NAME"
        fi
    else
        # Try to find tables by pattern
        log "Searching for DynamoDB tables with pattern: ri-tracking-*"
        TABLES=$(aws dynamodb list-tables --region "${AWS_REGION}" \
            --query 'TableNames[?starts_with(@, `ri-tracking-`)]' --output text 2>/dev/null || echo "")
        
        for table in $TABLES; do
            if [ -n "$table" ]; then
                log "Found table: $table - deleting..."
                aws dynamodb delete-table --table-name "$table" --region "${AWS_REGION}" >/dev/null 2>&1 || true
                success "Deleted DynamoDB table: $table"
            fi
        done
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    log "Deleting SNS topic..."
    
    if [ -n "$SNS_TOPIC_ARN" ]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" --region "${AWS_REGION}" >/dev/null 2>&1; then
            log "Deleting SNS topic: $SNS_TOPIC_ARN"
            aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" --region "${AWS_REGION}" >/dev/null 2>&1 || true
            success "Deleted SNS topic: $SNS_TOPIC_ARN"
        else
            warning "SNS topic not found: $SNS_TOPIC_ARN"
        fi
    else
        # Try to find topics by pattern
        log "Searching for SNS topics with pattern: ri-alerts-*"
        TOPICS=$(aws sns list-topics --region "${AWS_REGION}" \
            --query 'Topics[?contains(TopicArn, `ri-alerts-`)].TopicArn' --output text 2>/dev/null || echo "")
        
        for topic_arn in $TOPICS; do
            if [ -n "$topic_arn" ]; then
                log "Found topic: $topic_arn - deleting..."
                aws sns delete-topic --topic-arn "$topic_arn" --region "${AWS_REGION}" >/dev/null 2>&1 || true
                success "Deleted SNS topic: $topic_arn"
            fi
        done
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket..."
    
    if [ -n "$S3_BUCKET_NAME" ]; then
        if aws s3 ls "s3://$S3_BUCKET_NAME" >/dev/null 2>&1; then
            log "Deleting S3 bucket contents: $S3_BUCKET_NAME"
            
            # Delete all objects and versions
            aws s3api delete-objects \
                --bucket "$S3_BUCKET_NAME" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$S3_BUCKET_NAME" \
                    --output json \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
                >/dev/null 2>&1 || true
            
            # Delete all delete markers
            aws s3api delete-objects \
                --bucket "$S3_BUCKET_NAME" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$S3_BUCKET_NAME" \
                    --output json \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" \
                >/dev/null 2>&1 || true
            
            # Remove all objects (fallback)
            aws s3 rm "s3://$S3_BUCKET_NAME" --recursive >/dev/null 2>&1 || true
            
            log "Deleting S3 bucket: $S3_BUCKET_NAME"
            aws s3 rb "s3://$S3_BUCKET_NAME" >/dev/null 2>&1 || true
            success "Deleted S3 bucket: $S3_BUCKET_NAME"
        else
            warning "S3 bucket not found: $S3_BUCKET_NAME"
        fi
    else
        # Try to find buckets by pattern
        log "Searching for S3 buckets with pattern: ri-reports-*"
        BUCKETS=$(aws s3api list-buckets \
            --query 'Buckets[?starts_with(Name, `ri-reports-`)].Name' --output text 2>/dev/null || echo "")
        
        for bucket in $BUCKETS; do
            if [ -n "$bucket" ]; then
                log "Found bucket: $bucket - deleting..."
                aws s3 rm "s3://$bucket" --recursive >/dev/null 2>&1 || true
                aws s3 rb "s3://$bucket" >/dev/null 2>&1 || true
                success "Deleted S3 bucket: $bucket"
            fi
        done
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment variables file
    if [ -f ".env_vars" ]; then
        rm -f .env_vars
        success "Removed .env_vars file"
    fi
    
    # Remove any leftover deployment artifacts
    rm -f lambda-trust-policy.json lambda-policy.json
    rm -f lifecycle-policy.json
    rm -f ri_*.py *.zip
    rm -f *-test-response.json
    
    success "Local cleanup completed"
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    RESOURCES_REMAINING=0
    
    # Check Lambda functions
    FUNCTIONS=$(aws lambda list-functions --region "${AWS_REGION}" \
        --query "Functions[?starts_with(FunctionName, '${PROJECT_NAME}')].FunctionName" --output text 2>/dev/null || echo "")
    if [ -n "$FUNCTIONS" ]; then
        warning "Remaining Lambda functions: $FUNCTIONS"
        RESOURCES_REMAINING=$((RESOURCES_REMAINING + 1))
    fi
    
    # Check EventBridge rules
    RULES=$(aws events list-rules --region "${AWS_REGION}" \
        --query "Rules[?starts_with(Name, '${PROJECT_NAME}')].Name" --output text 2>/dev/null || echo "")
    if [ -n "$RULES" ]; then
        warning "Remaining EventBridge rules: $RULES"
        RESOURCES_REMAINING=$((RESOURCES_REMAINING + 1))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${PROJECT_NAME}-lambda-role" >/dev/null 2>&1; then
        warning "IAM role still exists: ${PROJECT_NAME}-lambda-role"
        RESOURCES_REMAINING=$((RESOURCES_REMAINING + 1))
    fi
    
    if [ $RESOURCES_REMAINING -eq 0 ]; then
        success "All resources have been successfully deleted"
    else
        warning "$RESOURCES_REMAINING resource groups may still exist. Check AWS console for manual cleanup."
    fi
}

# Function to display cleanup summary
display_summary() {
    echo ""
    echo "======================================"
    echo "    CLEANUP COMPLETED"
    echo "======================================"
    echo ""
    echo "Deleted Resources:"
    echo "  • EventBridge Rules and Targets"
    echo "  • Lambda Functions"
    echo "  • IAM Role and Policies"
    echo "  • DynamoDB Table"
    echo "  • SNS Topic"
    echo "  • S3 Bucket and Contents"
    echo "  • Local Configuration Files"
    echo ""
    echo "The AWS Reserved Instance Management Automation"
    echo "solution has been completely removed."
    echo ""
    
    # Show final cost note
    echo "Note: Some costs may continue for a few hours due to"
    echo "AWS billing granularity, but all ongoing charges"
    echo "have been eliminated."
    echo ""
}

# Main cleanup function
main() {
    echo "======================================"
    echo "  AWS RI Management Automation Cleanup"
    echo "======================================"
    echo ""
    
    validate_prerequisites
    load_environment
    confirm_destruction
    
    log "Starting cleanup process..."
    
    # Delete resources in reverse order of creation
    delete_eventbridge_rules
    delete_lambda_functions
    delete_iam_role
    delete_dynamodb_table
    delete_sns_topic
    delete_s3_bucket
    cleanup_local_files
    verify_deletion
    display_summary
    
    success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'echo -e "\n${YELLOW}Cleanup interrupted. Some resources may still exist.${NC}"; exit 1' INT TERM

# Run main function
main "$@"