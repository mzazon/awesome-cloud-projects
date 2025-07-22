#!/bin/bash

# Progressive Web Applications with AWS Amplify - Cleanup Script
# This script removes all resources created by the deployment script

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to confirm destructive action
confirm_destruction() {
    log_warning "This script will permanently delete all AWS resources and local files created by the deployment."
    echo ""
    echo "Resources that will be deleted:"
    echo "- Amplify backend (Cognito User Pool, AppSync API, DynamoDB tables, S3 buckets)"
    echo "- Lambda functions and IAM roles"
    echo "- CloudFormation stacks"
    echo "- Local project directory and files"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    log_warning "Starting destruction process in 5 seconds..."
    sleep 5
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Check if .env file exists
    if [ ! -f ".env" ]; then
        log_error ".env file not found. Cannot determine what resources to clean up."
        log_error "Please ensure you're running this script from the same directory as deploy.sh"
        exit 1
    fi
    
    # Load environment variables
    source .env
    
    # Validate required variables
    if [ -z "${PROJECT_NAME:-}" ] || [ -z "${APP_NAME:-}" ] || [ -z "${AWS_REGION:-}" ]; then
        log_error "Required environment variables not found in .env file"
        log_error "Expected: PROJECT_NAME, APP_NAME, AWS_REGION"
        exit 1
    fi
    
    log_success "Environment variables loaded"
    log_info "Project Name: ${PROJECT_NAME}"
    log_info "App Name: ${APP_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Cannot clean up AWS resources."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check Amplify CLI
    if ! command_exists amplify; then
        log_warning "Amplify CLI not found. Will skip Amplify-specific cleanup."
        SKIP_AMPLIFY=true
    else
        SKIP_AMPLIFY=false
    fi
    
    log_success "Prerequisites checked"
}

# Function to remove Amplify backend resources
remove_amplify_backend() {
    if [ "$SKIP_AMPLIFY" = true ]; then
        log_warning "Skipping Amplify backend cleanup (CLI not available)"
        return
    fi
    
    log_info "Removing Amplify backend resources..."
    
    # Check if project directory exists
    if [ ! -d "${HOME}/${PROJECT_NAME}" ]; then
        log_warning "Project directory not found: ${HOME}/${PROJECT_NAME}"
        return
    fi
    
    cd "${HOME}/${PROJECT_NAME}"
    
    # Check if Amplify is initialized
    if [ ! -d "amplify" ]; then
        log_warning "Amplify not initialized in project directory"
        return
    fi
    
    # Remove Amplify backend
    log_info "Deleting Amplify backend..."
    amplify delete --yes
    
    if [ $? -eq 0 ]; then
        log_success "Amplify backend deleted successfully"
    else
        log_error "Failed to delete Amplify backend"
        log_warning "You may need to manually clean up resources in the AWS console"
    fi
}

# Function to remove CloudFormation stacks (fallback cleanup)
remove_cloudformation_stacks() {
    log_info "Checking for remaining CloudFormation stacks..."
    
    # List stacks that might be related to the project
    STACKS=$(aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query "StackSummaries[?contains(StackName, '${PROJECT_NAME}') || contains(StackName, '${APP_NAME}') || contains(StackName, 'amplify')].StackName" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$STACKS" ]; then
        log_info "No CloudFormation stacks found"
        return
    fi
    
    log_info "Found CloudFormation stacks: $STACKS"
    
    # Delete each stack
    for stack in $STACKS; do
        log_info "Deleting CloudFormation stack: $stack"
        aws cloudformation delete-stack --stack-name "$stack"
        
        if [ $? -eq 0 ]; then
            log_success "Initiated deletion of stack: $stack"
        else
            log_error "Failed to delete stack: $stack"
        fi
    done
    
    # Wait for stacks to be deleted
    if [ -n "$STACKS" ]; then
        log_info "Waiting for CloudFormation stacks to be deleted..."
        for stack in $STACKS; do
            log_info "Waiting for stack deletion: $stack"
            aws cloudformation wait stack-delete-complete --stack-name "$stack" || true
        done
        log_success "CloudFormation stacks cleanup completed"
    fi
}

# Function to remove S3 buckets (fallback cleanup)
remove_s3_buckets() {
    log_info "Checking for S3 buckets..."
    
    # List buckets that might be related to the project
    BUCKETS=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, '${PROJECT_NAME}') || contains(Name, '${APP_NAME}') || contains(Name, 'amplify')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$BUCKETS" ]; then
        log_info "No S3 buckets found"
        return
    fi
    
    log_info "Found S3 buckets: $BUCKETS"
    
    # Delete each bucket
    for bucket in $BUCKETS; do
        log_info "Deleting S3 bucket: $bucket"
        
        # Remove all objects first
        aws s3 rm "s3://$bucket" --recursive 2>/dev/null || true
        
        # Remove all versions and delete markers
        aws s3api delete-objects \
            --bucket "$bucket" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$bucket" \
                --query '{Objects: [].{Key: Key, VersionId: VersionId}}' \
                --output json 2>/dev/null || echo '{}')" 2>/dev/null || true
        
        # Delete the bucket
        aws s3api delete-bucket --bucket "$bucket" 2>/dev/null || true
        
        if [ $? -eq 0 ]; then
            log_success "Deleted S3 bucket: $bucket"
        else
            log_warning "Failed to delete S3 bucket: $bucket (may already be deleted)"
        fi
    done
}

# Function to remove DynamoDB tables (fallback cleanup)
remove_dynamodb_tables() {
    log_info "Checking for DynamoDB tables..."
    
    # List tables that might be related to the project
    TABLES=$(aws dynamodb list-tables \
        --query "TableNames[?contains(@, '${PROJECT_NAME}') || contains(@, '${APP_NAME}') || contains(@, 'Task')]" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$TABLES" ]; then
        log_info "No DynamoDB tables found"
        return
    fi
    
    log_info "Found DynamoDB tables: $TABLES"
    
    # Delete each table
    for table in $TABLES; do
        log_info "Deleting DynamoDB table: $table"
        aws dynamodb delete-table --table-name "$table" 2>/dev/null || true
        
        if [ $? -eq 0 ]; then
            log_success "Initiated deletion of DynamoDB table: $table"
        else
            log_warning "Failed to delete DynamoDB table: $table (may already be deleted)"
        fi
    done
}

# Function to remove Cognito User Pools (fallback cleanup)
remove_cognito_user_pools() {
    log_info "Checking for Cognito User Pools..."
    
    # List user pools that might be related to the project
    USER_POOLS=$(aws cognito-idp list-user-pools \
        --max-results 50 \
        --query "UserPools[?contains(Name, '${PROJECT_NAME}') || contains(Name, '${APP_NAME}')].Id" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$USER_POOLS" ]; then
        log_info "No Cognito User Pools found"
        return
    fi
    
    log_info "Found Cognito User Pools: $USER_POOLS"
    
    # Delete each user pool
    for pool_id in $USER_POOLS; do
        log_info "Deleting Cognito User Pool: $pool_id"
        aws cognito-idp delete-user-pool --user-pool-id "$pool_id" 2>/dev/null || true
        
        if [ $? -eq 0 ]; then
            log_success "Deleted Cognito User Pool: $pool_id"
        else
            log_warning "Failed to delete Cognito User Pool: $pool_id (may already be deleted)"
        fi
    done
}

# Function to remove AppSync APIs (fallback cleanup)
remove_appsync_apis() {
    log_info "Checking for AppSync APIs..."
    
    # List APIs that might be related to the project
    APIS=$(aws appsync list-graphql-apis \
        --query "graphqlApis[?contains(name, '${PROJECT_NAME}') || contains(name, '${APP_NAME}')].apiId" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$APIS" ]; then
        log_info "No AppSync APIs found"
        return
    fi
    
    log_info "Found AppSync APIs: $APIS"
    
    # Delete each API
    for api_id in $APIS; do
        log_info "Deleting AppSync API: $api_id"
        aws appsync delete-graphql-api --api-id "$api_id" 2>/dev/null || true
        
        if [ $? -eq 0 ]; then
            log_success "Deleted AppSync API: $api_id"
        else
            log_warning "Failed to delete AppSync API: $api_id (may already be deleted)"
        fi
    done
}

# Function to remove Lambda functions (fallback cleanup)
remove_lambda_functions() {
    log_info "Checking for Lambda functions..."
    
    # List functions that might be related to the project
    FUNCTIONS=$(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, '${PROJECT_NAME}') || contains(FunctionName, '${APP_NAME}')].FunctionName" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$FUNCTIONS" ]; then
        log_info "No Lambda functions found"
        return
    fi
    
    log_info "Found Lambda functions: $FUNCTIONS"
    
    # Delete each function
    for function_name in $FUNCTIONS; do
        log_info "Deleting Lambda function: $function_name"
        aws lambda delete-function --function-name "$function_name" 2>/dev/null || true
        
        if [ $? -eq 0 ]; then
            log_success "Deleted Lambda function: $function_name"
        else
            log_warning "Failed to delete Lambda function: $function_name (may already be deleted)"
        fi
    done
}

# Function to remove IAM roles (fallback cleanup)
remove_iam_roles() {
    log_info "Checking for IAM roles..."
    
    # List roles that might be related to the project
    ROLES=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, '${PROJECT_NAME}') || contains(RoleName, '${APP_NAME}') || contains(RoleName, 'amplify')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$ROLES" ]; then
        log_info "No IAM roles found"
        return
    fi
    
    log_info "Found IAM roles: $ROLES"
    
    # Delete each role
    for role_name in $ROLES; do
        log_info "Deleting IAM role: $role_name"
        
        # Detach policies first
        POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query "AttachedPolicies[].PolicyArn" \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in $POLICIES; do
            aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$role_name" \
            --query "PolicyNames" \
            --output text 2>/dev/null || echo "")
        
        for policy_name in $INLINE_POLICIES; do
            aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" 2>/dev/null || true
        done
        
        # Delete the role
        aws iam delete-role --role-name "$role_name" 2>/dev/null || true
        
        if [ $? -eq 0 ]; then
            log_success "Deleted IAM role: $role_name"
        else
            log_warning "Failed to delete IAM role: $role_name (may already be deleted)"
        fi
    done
}

# Function to remove local project files
remove_local_files() {
    log_info "Removing local project files..."
    
    # Remove project directory
    if [ -d "${HOME}/${PROJECT_NAME}" ]; then
        log_info "Removing project directory: ${HOME}/${PROJECT_NAME}"
        rm -rf "${HOME}/${PROJECT_NAME}"
        
        if [ $? -eq 0 ]; then
            log_success "Removed project directory"
        else
            log_error "Failed to remove project directory"
        fi
    else
        log_info "Project directory not found: ${HOME}/${PROJECT_NAME}"
    fi
    
    # Remove environment file
    if [ -f ".env" ]; then
        log_info "Removing environment file"
        rm -f ".env"
        log_success "Removed environment file"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check for remaining resources
    REMAINING_STACKS=$(aws cloudformation list-stacks \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
        --query "StackSummaries[?contains(StackName, '${PROJECT_NAME}') || contains(StackName, '${APP_NAME}')].StackName" \
        --output text 2>/dev/null || echo "")
    
    REMAINING_BUCKETS=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, '${PROJECT_NAME}') || contains(Name, '${APP_NAME}')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$REMAINING_STACKS" ] || [ -n "$REMAINING_BUCKETS" ]; then
        log_warning "Some resources may still exist:"
        [ -n "$REMAINING_STACKS" ] && echo "  CloudFormation stacks: $REMAINING_STACKS"
        [ -n "$REMAINING_BUCKETS" ] && echo "  S3 buckets: $REMAINING_BUCKETS"
        log_warning "Please check the AWS console for any remaining resources"
    else
        log_success "Cleanup verification completed - no remaining resources found"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "=========================================="
    echo "Project Name: ${PROJECT_NAME}"
    echo "App Name: ${APP_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo "=========================================="
    echo ""
    echo "Cleanup completed for:"
    echo "✓ Amplify backend resources"
    echo "✓ CloudFormation stacks"
    echo "✓ S3 buckets"
    echo "✓ DynamoDB tables"
    echo "✓ Cognito User Pools"
    echo "✓ AppSync APIs"
    echo "✓ Lambda functions"
    echo "✓ IAM roles"
    echo "✓ Local project files"
    echo ""
    echo "Note: Some resources may take a few minutes to be fully deleted."
    echo "Please check the AWS console if you notice any remaining resources."
    echo ""
    log_success "Cleanup completed successfully!"
}

# Main execution
main() {
    log_info "Starting Progressive Web Applications with AWS Amplify cleanup..."
    
    # Check if running from correct directory
    if [ ! -f "destroy.sh" ]; then
        log_error "This script must be run from the scripts directory"
        exit 1
    fi
    
    # Load environment and check prerequisites
    load_environment
    check_prerequisites
    
    # Confirm destructive action
    confirm_destruction
    
    # Remove resources in order
    remove_amplify_backend
    remove_cloudformation_stacks
    remove_s3_buckets
    remove_dynamodb_tables
    remove_cognito_user_pools
    remove_appsync_apis
    remove_lambda_functions
    remove_iam_roles
    remove_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
}

# Run main function
main "$@"