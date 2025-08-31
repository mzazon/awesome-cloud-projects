#!/bin/bash

# Simple Random Data API Cleanup Script
# This script removes all AWS resources created by the deployment script
# including Lambda function, API Gateway, and IAM role.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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
        log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure credentials."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites met"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ -f "deployment-info.json" ]]; then
        # Extract values from deployment info
        export AWS_REGION=$(jq -r '.aws_region' deployment-info.json)
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' deployment-info.json)
        export FUNCTION_NAME=$(jq -r '.function_name' deployment-info.json)
        export ROLE_NAME=$(jq -r '.role_name' deployment-info.json)
        export API_NAME=$(jq -r '.api_name' deployment-info.json)
        export API_ID=$(jq -r '.api_id' deployment-info.json)
        export API_URL=$(jq -r '.api_url' deployment-info.json)
        export ROLE_ARN=$(jq -r '.role_arn' deployment-info.json)
        
        log_success "Deployment information loaded"
        log_info "Function Name: ${FUNCTION_NAME}"
        log_info "Role Name: ${ROLE_NAME}"
        log_info "API ID: ${API_ID}"
    else
        log_warning "deployment-info.json not found. Will attempt manual cleanup."
        
        # Prompt for manual input if no deployment info file
        read -p "Enter Lambda function name (or press Enter to skip): " FUNCTION_NAME
        read -p "Enter IAM role name (or press Enter to skip): " ROLE_NAME
        read -p "Enter API Gateway ID (or press Enter to skip): " API_ID
        
        # Set AWS region from CLI config
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
        fi
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "This will permanently delete the following resources:"
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_warning "  - Lambda function: ${FUNCTION_NAME}"
    fi
    
    if [[ -n "${ROLE_NAME:-}" ]]; then
        log_warning "  - IAM role: ${ROLE_NAME}"
    fi
    
    if [[ -n "${API_ID:-}" ]]; then
        log_warning "  - API Gateway: ${API_ID}"
    fi
    
    log_warning "  - Local deployment files"
    echo
    
    # Check for --force flag
    if [[ "${1:-}" != "--force" ]]; then
        read -p "Are you sure you want to continue? (yes/no): " confirmation
        if [[ "$confirmation" != "yes" ]]; then
            log_info "Cleanup cancelled by user."
            exit 0
        fi
    else
        log_info "Force flag detected, skipping confirmation."
    fi
}

# Function to delete API Gateway
delete_api_gateway() {
    if [[ -n "${API_ID:-}" ]]; then
        log_info "Deleting API Gateway: ${API_ID}..."
        
        # Check if API exists
        if aws apigateway get-rest-api --rest-api-id "${API_ID}" &>/dev/null; then
            aws apigateway delete-rest-api --rest-api-id "${API_ID}"
            log_success "API Gateway deleted: ${API_ID}"
        else
            log_warning "API Gateway ${API_ID} not found or already deleted"
        fi
    else
        log_info "No API Gateway ID provided, skipping..."
    fi
}

# Function to remove Lambda permission
remove_lambda_permission() {
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_info "Removing Lambda permission for API Gateway..."
        
        # Try to remove the permission (ignore errors if it doesn't exist)
        aws lambda remove-permission \
            --function-name "${FUNCTION_NAME}" \
            --statement-id apigateway-invoke 2>/dev/null || true
        
        log_success "Lambda permission removed (if it existed)"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_info "Deleting Lambda function: ${FUNCTION_NAME}..."
        
        # Check if function exists
        if aws lambda get-function --function-name "${FUNCTION_NAME}" &>/dev/null; then
            aws lambda delete-function --function-name "${FUNCTION_NAME}"
            log_success "Lambda function deleted: ${FUNCTION_NAME}"
        else
            log_warning "Lambda function ${FUNCTION_NAME} not found or already deleted"
        fi
    else
        log_info "No Lambda function name provided, skipping..."
    fi
}

# Function to delete IAM role
delete_iam_role() {
    if [[ -n "${ROLE_NAME:-}" ]]; then
        log_info "Deleting IAM role: ${ROLE_NAME}..."
        
        # Check if role exists
        if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
            # Detach policies first
            log_info "Detaching policies from role..."
            
            # List and detach all attached policies
            ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
                --role-name "${ROLE_NAME}" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text)
            
            if [[ -n "$ATTACHED_POLICIES" ]]; then
                for policy_arn in $ATTACHED_POLICIES; do
                    aws iam detach-role-policy \
                        --role-name "${ROLE_NAME}" \
                        --policy-arn "$policy_arn"
                    log_info "Detached policy: $policy_arn"
                done
            fi
            
            # Delete inline policies if any
            INLINE_POLICIES=$(aws iam list-role-policies \
                --role-name "${ROLE_NAME}" \
                --query 'PolicyNames' \
                --output text)
            
            if [[ -n "$INLINE_POLICIES" && "$INLINE_POLICIES" != "None" ]]; then
                for policy_name in $INLINE_POLICIES; do
                    aws iam delete-role-policy \
                        --role-name "${ROLE_NAME}" \
                        --policy-name "$policy_name"
                    log_info "Deleted inline policy: $policy_name"
                done
            fi
            
            # Wait a moment for policy detachment to propagate
            sleep 5
            
            # Delete the role
            aws iam delete-role --role-name "${ROLE_NAME}"
            log_success "IAM role deleted: ${ROLE_NAME}"
        else
            log_warning "IAM role ${ROLE_NAME} not found or already deleted"
        fi
    else
        log_info "No IAM role name provided, skipping..."
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-info.json"
        "trust-policy.json"
        "function.zip"
        "lambda-function/"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            rm -rf "$file"
            log_info "Removed: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to scan for orphaned resources
scan_orphaned_resources() {
    log_info "Scanning for potential orphaned resources..."
    
    # Look for Lambda functions with similar naming pattern
    log_info "Checking for Lambda functions with 'random-data-api' pattern..."
    LAMBDA_FUNCTIONS=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `random-data-api`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$LAMBDA_FUNCTIONS" ]]; then
        log_warning "Found potential orphaned Lambda functions:"
        for func in $LAMBDA_FUNCTIONS; do
            log_warning "  - $func"
        done
        echo
        read -p "Would you like to delete these functions? (yes/no): " delete_functions
        if [[ "$delete_functions" == "yes" ]]; then
            for func in $LAMBDA_FUNCTIONS; do
                aws lambda delete-function --function-name "$func"
                log_success "Deleted orphaned Lambda function: $func"
            done
        fi
    fi
    
    # Look for IAM roles with similar naming pattern
    log_info "Checking for IAM roles with 'lambda-random-api-role' pattern..."
    IAM_ROLES=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `lambda-random-api-role`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$IAM_ROLES" ]]; then
        log_warning "Found potential orphaned IAM roles:"
        for role in $IAM_ROLES; do
            log_warning "  - $role"
        done
        echo
        read -p "Would you like to delete these roles? (yes/no): " delete_roles
        if [[ "$delete_roles" == "yes" ]]; then
            for role in $IAM_ROLES; do
                # Clean up policies first
                ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
                    --role-name "$role" \
                    --query 'AttachedPolicies[].PolicyArn' \
                    --output text 2>/dev/null || echo "")
                
                if [[ -n "$ATTACHED_POLICIES" ]]; then
                    for policy_arn in $ATTACHED_POLICIES; do
                        aws iam detach-role-policy \
                            --role-name "$role" \
                            --policy-arn "$policy_arn" 2>/dev/null || true
                    done
                fi
                
                aws iam delete-role --role-name "$role"
                log_success "Deleted orphaned IAM role: $role"
            done
        fi
    fi
    
    # Look for API Gateways with similar naming pattern
    log_info "Checking for API Gateways with 'random-data-api' pattern..."
    API_GATEWAYS=$(aws apigateway get-rest-apis \
        --query 'items[?contains(name, `random-data-api`)].id' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$API_GATEWAYS" ]]; then
        log_warning "Found potential orphaned API Gateways:"
        for api in $API_GATEWAYS; do
            API_NAME=$(aws apigateway get-rest-api --rest-api-id "$api" --query 'name' --output text)
            log_warning "  - $api ($API_NAME)"
        done
        echo
        read -p "Would you like to delete these APIs? (yes/no): " delete_apis
        if [[ "$delete_apis" == "yes" ]]; then
            for api in $API_GATEWAYS; do
                aws apigateway delete-rest-api --rest-api-id "$api"
                log_success "Deleted orphaned API Gateway: $api"
            done
        fi
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_success=true
    
    # Verify Lambda function deletion
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "${FUNCTION_NAME}" &>/dev/null; then
            log_error "Lambda function ${FUNCTION_NAME} still exists"
            cleanup_success=false
        else
            log_success "Lambda function cleanup verified"
        fi
    fi
    
    # Verify IAM role deletion
    if [[ -n "${ROLE_NAME:-}" ]]; then
        if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
            log_error "IAM role ${ROLE_NAME} still exists"
            cleanup_success=false
        else
            log_success "IAM role cleanup verified"
        fi
    fi
    
    # Verify API Gateway deletion
    if [[ -n "${API_ID:-}" ]]; then
        if aws apigateway get-rest-api --rest-api-id "${API_ID}" &>/dev/null; then
            log_error "API Gateway ${API_ID} still exists"
            cleanup_success=false
        else
            log_success "API Gateway cleanup verified"
        fi
    fi
    
    # Verify local files cleanup
    if [[ -f "deployment-info.json" ]]; then
        log_error "deployment-info.json still exists"
        cleanup_success=false
    else
        log_success "Local files cleanup verified"
    fi
    
    if [[ "$cleanup_success" == true ]]; then
        log_success "All resources successfully cleaned up"
    else
        log_warning "Some resources may still exist. Please check manually."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary:"
    log_info "=================="
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_info "✓ Lambda function: ${FUNCTION_NAME}"
    fi
    
    if [[ -n "${ROLE_NAME:-}" ]]; then
        log_info "✓ IAM role: ${ROLE_NAME}"
    fi
    
    if [[ -n "${API_ID:-}" ]]; then
        log_info "✓ API Gateway: ${API_ID}"
    fi
    
    log_info "✓ Local deployment files"
    log_info "=================="
}

# Main cleanup function
main() {
    log_info "Starting Simple Random Data API cleanup..."
    log_info "=========================================="
    
    check_prerequisites
    load_deployment_info
    confirm_destruction "$@"
    
    # Perform cleanup in reverse order of creation
    delete_api_gateway
    remove_lambda_permission
    delete_lambda_function
    delete_iam_role
    cleanup_local_files
    
    # Optional: scan for orphaned resources
    if [[ "${1:-}" != "--force" ]]; then
        echo
        read -p "Would you like to scan for orphaned resources? (yes/no): " scan_orphaned
        if [[ "$scan_orphaned" == "yes" ]]; then
            scan_orphaned_resources
        fi
    fi
    
    verify_cleanup
    display_cleanup_summary
    
    log_success "=========================================="
    log_success "Cleanup completed successfully!"
    log_success "=========================================="
    log_info "All AWS resources have been removed."
    log_info "Your AWS account is now clean of Random Data API resources."
}

# Function to display help
show_help() {
    echo "Simple Random Data API Cleanup Script"
    echo "======================================"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --force    Skip confirmation prompts and perform cleanup automatically"
    echo "  --help     Show this help message"
    echo
    echo "Examples:"
    echo "  $0                    # Interactive cleanup with confirmations"
    echo "  $0 --force          # Automatic cleanup without prompts"
    echo
    echo "This script will remove:"
    echo "  - Lambda function"
    echo "  - API Gateway"
    echo "  - IAM role and policies"
    echo "  - Local deployment files"
    echo
    echo "Note: This action cannot be undone. Make sure you want to delete these resources."
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac