#!/bin/bash

# Cleanup script for Serverless API Patterns with Lambda Authorizers and API Gateway
# This script safely removes all resources created by the deployment script

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [ -f "deployment-info.json" ]; then
        # Extract deployment info using AWS CLI jq-like functionality
        export AWS_REGION=$(grep -o '"aws_region":[^,]*' deployment-info.json | cut -d'"' -f4)
        export AWS_ACCOUNT_ID=$(grep -o '"aws_account_id":[^,]*' deployment-info.json | cut -d'"' -f4)
        export API_ID=$(grep -o '"api_id":[^,]*' deployment-info.json | cut -d'"' -f4)
        export TOKEN_AUTH_FUNCTION=$(grep -o '"token_authorizer":[^,]*' deployment-info.json | cut -d'"' -f4)
        export REQUEST_AUTH_FUNCTION=$(grep -o '"request_authorizer":[^,]*' deployment-info.json | cut -d'"' -f4)
        export PROTECTED_FUNCTION=$(grep -o '"protected_api":[^,]*' deployment-info.json | cut -d'"' -f4)
        export PUBLIC_FUNCTION=$(grep -o '"public_api":[^,]*' deployment-info.json | cut -d'"' -f4)
        export ROLE_NAME=$(grep -o '"role_name":[^,]*' deployment-info.json | cut -d'"' -f4)
        
        log_success "Loaded deployment information from deployment-info.json"
        log_info "API ID: $API_ID"
        log_info "Region: $AWS_REGION"
    else
        log_warning "deployment-info.json not found. Attempting to discover resources..."
        discover_resources
    fi
}

# Function to discover resources if deployment info is not available
discover_resources() {
    log_info "Attempting to discover deployed resources..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not configured. Please set it using 'aws configure'."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Try to find API Gateway by name pattern
    API_LIST=$(aws apigateway get-rest-apis --query 'items[?contains(name, `secure-api-`)].{id:id,name:name}' --output text)
    
    if [ -n "$API_LIST" ]; then
        export API_ID=$(echo "$API_LIST" | head -1 | awk '{print $1}')
        API_NAME=$(echo "$API_LIST" | head -1 | awk '{print $2}')
        
        # Extract suffix from API name
        SUFFIX=$(echo "$API_NAME" | sed 's/secure-api-//')
        
        # Set function names based on discovered pattern
        export TOKEN_AUTH_FUNCTION="token-authorizer-${SUFFIX}"
        export REQUEST_AUTH_FUNCTION="request-authorizer-${SUFFIX}"
        export PROTECTED_FUNCTION="protected-api-${SUFFIX}"
        export PUBLIC_FUNCTION="public-api-${SUFFIX}"
        export ROLE_NAME="api-auth-role-${SUFFIX}"
        
        log_info "Discovered API Gateway: $API_ID"
    else
        log_warning "No API Gateway found with pattern 'secure-api-*'"
        export API_ID=""
    fi
}

# Function to prompt for confirmation
confirm_deletion() {
    echo -e "\n${YELLOW}⚠️  WARNING: This will delete ALL resources created by the deployment script!${NC}"
    echo -e "${YELLOW}This action cannot be undone.${NC}\n"
    
    if [ -n "$API_ID" ]; then
        echo -e "${BLUE}Resources to be deleted:${NC}"
        echo -e "  • API Gateway: $API_ID"
        echo -e "  • Lambda Functions: $TOKEN_AUTH_FUNCTION, $REQUEST_AUTH_FUNCTION, $PROTECTED_FUNCTION, $PUBLIC_FUNCTION"
        echo -e "  • IAM Role: $ROLE_NAME"
        echo -e "  • CloudWatch Log Groups for all Lambda functions"
    else
        echo -e "${BLUE}Will attempt to delete any discovered resources matching the pattern.${NC}"
    fi
    
    echo -e "\n${YELLOW}Do you want to continue? (yes/no):${NC} "
    read -r response
    
    if [ "$response" != "yes" ] && [ "$response" != "y" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Function to delete API Gateway
delete_api_gateway() {
    if [ -n "$API_ID" ]; then
        log_info "Deleting API Gateway: $API_ID"
        
        if aws apigateway delete-rest-api --rest-api-id "$API_ID" 2>/dev/null; then
            log_success "Deleted API Gateway: $API_ID"
        else
            log_warning "Failed to delete API Gateway or it doesn't exist: $API_ID"
        fi
    else
        log_info "No API Gateway ID found, skipping API Gateway deletion"
    fi
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log_info "Deleting Lambda functions..."
    
    local functions=("$TOKEN_AUTH_FUNCTION" "$REQUEST_AUTH_FUNCTION" "$PROTECTED_FUNCTION" "$PUBLIC_FUNCTION")
    
    for func in "${functions[@]}"; do
        if [ -n "$func" ]; then
            log_info "Deleting Lambda function: $func"
            
            if aws lambda delete-function --function-name "$func" 2>/dev/null; then
                log_success "Deleted Lambda function: $func"
            else
                log_warning "Failed to delete Lambda function or it doesn't exist: $func"
            fi
        fi
    done
    
    # Also try to delete any functions matching the pattern if we couldn't load specific names
    if [ -z "$TOKEN_AUTH_FUNCTION" ]; then
        log_info "Searching for Lambda functions with authorizer patterns..."
        
        local pattern_functions=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `token-authorizer-`) || contains(FunctionName, `request-authorizer-`) || contains(FunctionName, `protected-api-`) || contains(FunctionName, `public-api-`)].FunctionName' --output text)
        
        if [ -n "$pattern_functions" ]; then
            for func in $pattern_functions; do
                log_info "Deleting discovered Lambda function: $func"
                if aws lambda delete-function --function-name "$func" 2>/dev/null; then
                    log_success "Deleted Lambda function: $func"
                else
                    log_warning "Failed to delete Lambda function: $func"
                fi
            done
        fi
    fi
}

# Function to delete CloudWatch Log Groups
delete_log_groups() {
    log_info "Deleting CloudWatch Log Groups..."
    
    if [ -n "$TOKEN_AUTH_FUNCTION" ]; then
        local functions=("$TOKEN_AUTH_FUNCTION" "$REQUEST_AUTH_FUNCTION" "$PROTECTED_FUNCTION" "$PUBLIC_FUNCTION")
        
        for func in "${functions[@]}"; do
            if [ -n "$func" ]; then
                local log_group="/aws/lambda/$func"
                log_info "Deleting CloudWatch Log Group: $log_group"
                
                if aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null; then
                    log_success "Deleted CloudWatch Log Group: $log_group"
                else
                    log_warning "Failed to delete CloudWatch Log Group or it doesn't exist: $log_group"
                fi
            fi
        done
    else
        # Search for log groups with our patterns
        log_info "Searching for CloudWatch Log Groups with function patterns..."
        
        local pattern_log_groups=$(aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/" --query 'logGroups[?contains(logGroupName, `token-authorizer-`) || contains(logGroupName, `request-authorizer-`) || contains(logGroupName, `protected-api-`) || contains(logGroupName, `public-api-`)].logGroupName' --output text)
        
        if [ -n "$pattern_log_groups" ]; then
            for log_group in $pattern_log_groups; do
                log_info "Deleting discovered CloudWatch Log Group: $log_group"
                if aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null; then
                    log_success "Deleted CloudWatch Log Group: $log_group"
                else
                    log_warning "Failed to delete CloudWatch Log Group: $log_group"
                fi
            done
        fi
    fi
}

# Function to delete IAM role
delete_iam_role() {
    if [ -n "$ROLE_NAME" ]; then
        log_info "Deleting IAM role: $ROLE_NAME"
        
        # First, detach all policies from the role
        log_info "Detaching policies from IAM role..."
        
        # Detach AWS managed policy
        if aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null; then
            log_success "Detached AWSLambdaBasicExecutionRole policy"
        else
            log_warning "Failed to detach AWSLambdaBasicExecutionRole policy or it wasn't attached"
        fi
        
        # Delete the role
        if aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null; then
            log_success "Deleted IAM role: $ROLE_NAME"
        else
            log_warning "Failed to delete IAM role or it doesn't exist: $ROLE_NAME"
        fi
    else
        # Search for roles with our pattern
        log_info "Searching for IAM roles with pattern 'api-auth-role-*'"
        
        local pattern_roles=$(aws iam list-roles --query 'Roles[?contains(RoleName, `api-auth-role-`)].RoleName' --output text)
        
        if [ -n "$pattern_roles" ]; then
            for role in $pattern_roles; do
                log_info "Deleting discovered IAM role: $role"
                
                # Detach policies first
                if aws iam detach-role-policy \
                    --role-name "$role" \
                    --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null; then
                    log_success "Detached policy from role: $role"
                fi
                
                # Delete the role
                if aws iam delete-role --role-name "$role" 2>/dev/null; then
                    log_success "Deleted IAM role: $role"
                else
                    log_warning "Failed to delete IAM role: $role"
                fi
            done
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_delete=(
        "deployment-info.json"
        "lambda-trust-policy.json"
        "token_authorizer.py"
        "request_authorizer.py"
        "protected_api.py"
        "public_api.py"
        "token-authorizer.zip"
        "request-authorizer.zip"
        "protected-api.zip"
        "public-api.zip"
    )
    
    for file in "${files_to_delete[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Deleted local file: $file"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check if API Gateway still exists
    if [ -n "$API_ID" ]; then
        if aws apigateway get-rest-api --rest-api-id "$API_ID" &>/dev/null; then
            log_warning "API Gateway still exists: $API_ID"
            ((cleanup_issues++))
        fi
    fi
    
    # Check Lambda functions
    if [ -n "$TOKEN_AUTH_FUNCTION" ]; then
        local functions=("$TOKEN_AUTH_FUNCTION" "$REQUEST_AUTH_FUNCTION" "$PROTECTED_FUNCTION" "$PUBLIC_FUNCTION")
        
        for func in "${functions[@]}"; do
            if [ -n "$func" ] && aws lambda get-function --function-name "$func" &>/dev/null; then
                log_warning "Lambda function still exists: $func"
                ((cleanup_issues++))
            fi
        done
    fi
    
    # Check IAM role
    if [ -n "$ROLE_NAME" ] && aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log_warning "IAM role still exists: $ROLE_NAME"
        ((cleanup_issues++))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log_success "All resources appear to have been cleaned up successfully"
    else
        log_warning "Some resources may still exist. You may need to clean them up manually."
        return 1
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    echo -e "\n${GREEN}=================================================================="
    echo -e "🧹 CLEANUP COMPLETED! 🧹"
    echo -e "==================================================================${NC}"
    echo -e "\n${BLUE}Resources that were targeted for deletion:${NC}"
    echo -e "  ✅ API Gateway REST API"
    echo -e "  ✅ Lambda Functions (authorizers and business logic)"
    echo -e "  ✅ CloudWatch Log Groups"
    echo -e "  ✅ IAM Role and attached policies"
    echo -e "  ✅ Local temporary files"
    echo -e "\n${BLUE}Note:${NC} It may take a few minutes for all AWS resources to be fully removed from the console."
    echo -e "\n${BLUE}Cost Impact:${NC} All billable resources have been removed. You should not incur further charges."
    
    if [ -f "deployment-info.json" ]; then
        echo -e "\n${YELLOW}Info:${NC} deployment-info.json was found and deleted. If you need to re-deploy,"
        echo -e "you can run the deploy.sh script again."
    fi
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Serverless API Patterns with Lambda Authorizers"
    log_info "=================================================================="
    
    check_prerequisites
    load_deployment_info
    confirm_deletion
    
    # Perform cleanup in reverse order of creation
    delete_api_gateway
    delete_lambda_functions
    delete_log_groups
    delete_iam_role
    cleanup_local_files
    
    # Verify cleanup was successful
    if verify_cleanup; then
        show_cleanup_summary
    else
        echo -e "\n${YELLOW}=================================================================="
        echo -e "⚠️  CLEANUP COMPLETED WITH WARNINGS ⚠️"
        echo -e "==================================================================${NC}"
        echo -e "\n${YELLOW}Some resources may still exist.${NC} Please check the AWS console and"
        echo -e "manually delete any remaining resources to avoid unexpected charges."
    fi
}

# Handle script interruption
trap 'log_error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"