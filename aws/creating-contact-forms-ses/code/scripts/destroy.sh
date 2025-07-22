#!/bin/bash

# AWS Simple Contact Form Backend Cleanup Script
# This script removes all resources created by the deployment script
# Recipe: Creating Contact Forms with SES and Lambda

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
ENV_FILE="${SCRIPT_DIR}/deployment_vars.env"
TEMP_DIR="${SCRIPT_DIR}/temp"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Error handling (non-fatal for cleanup script)
error_log() {
    log "WARNING: $1"
}

# Success handler
success_handler() {
    log "✅ Cleanup completed successfully!"
    log "💰 All AWS resources have been removed to avoid charges"
    log "📝 Check cleanup.log for detailed information"
    
    # Clean up environment file
    if [ -f "${ENV_FILE}" ]; then
        rm -f "${ENV_FILE}"
        log "🗑️  Environment file removed"
    fi
}

# Cleanup temporary files
cleanup_temp_files() {
    if [ -d "${TEMP_DIR}" ]; then
        rm -rf "${TEMP_DIR}"
        log "🧹 Temporary files cleaned up"
    fi
}

# Load environment variables
load_environment() {
    log "📋 Loading deployment environment..."
    
    if [ ! -f "${ENV_FILE}" ]; then
        error_log "Environment file not found. Some resources may need manual cleanup."
        log "Expected file: ${ENV_FILE}"
        
        # Try to prompt for manual input
        read -p "Do you want to proceed with manual resource identification? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "❌ Cleanup cancelled"
            exit 1
        fi
        
        manual_resource_discovery
        return
    fi
    
    # Source the environment file
    source "${ENV_FILE}"
    
    # Verify required variables
    if [ -z "${AWS_REGION:-}" ] || [ -z "${AWS_ACCOUNT_ID:-}" ]; then
        error_log "Missing required environment variables"
        manual_resource_discovery
        return
    fi
    
    log "✅ Environment loaded:"
    log "   Region: ${AWS_REGION}"
    log "   Account: ${AWS_ACCOUNT_ID}"
    log "   Resources identified with suffix: ${RANDOM_SUFFIX:-unknown}"
}

# Manual resource discovery
manual_resource_discovery() {
    log "🔍 Attempting manual resource discovery..."
    
    # Set basic AWS environment
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    
    if [ -z "${AWS_ACCOUNT_ID}" ]; then
        error_log "Cannot determine AWS account ID. Please check AWS credentials."
        exit 1
    fi
    
    # Try to find resources by name pattern
    log "Looking for Lambda functions..."
    LAMBDA_FUNCTIONS=$(aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `contact-form-processor-`)].FunctionName' --output text 2>/dev/null || echo "")
    
    log "Looking for API Gateways..."
    API_GATEWAYS=$(aws apigateway get-rest-apis --query 'items[?starts_with(name, `contact-form-api-`)].{id:id,name:name}' --output text 2>/dev/null || echo "")
    
    log "Looking for IAM roles..."
    IAM_ROLES=$(aws iam list-roles --query 'Roles[?starts_with(RoleName, `contact-form-lambda-role-`)].RoleName' --output text 2>/dev/null || echo "")
    
    # If resources found, prompt user
    if [ -n "$LAMBDA_FUNCTIONS" ] || [ -n "$API_GATEWAYS" ] || [ -n "$IAM_ROLES" ]; then
        log "Found potential contact form resources:"
        [ -n "$LAMBDA_FUNCTIONS" ] && log "  Lambda: $LAMBDA_FUNCTIONS"
        [ -n "$API_GATEWAYS" ] && log "  API Gateway: $API_GATEWAYS"
        [ -n "$IAM_ROLES" ] && log "  IAM Roles: $IAM_ROLES"
        
        read -p "Proceed with cleanup of these resources? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "❌ Cleanup cancelled"
            exit 1
        fi
    else
        log "⚠️  No contact form resources found automatically"
        log "You may need to clean up resources manually in the AWS Console"
        exit 0
    fi
}

# Confirmation prompt
confirm_destruction() {
    log "⚠️  WARNING: This will permanently delete all contact form resources!"
    log "Resources to be deleted:"
    [ -n "${API_ID:-}" ] && log "  - API Gateway: ${API_GATEWAY_NAME:-unknown} (${API_ID})"
    [ -n "${LAMBDA_FUNCTION_NAME:-}" ] && log "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    [ -n "${IAM_ROLE_NAME:-}" ] && log "  - IAM Role: ${IAM_ROLE_NAME}"
    [ -n "${POLICY_NAME:-}" ] && log "  - IAM Policy: ${POLICY_NAME}"
    log ""
    
    # Skip confirmation if --force flag is provided
    if [[ "${1:-}" == "--force" ]]; then
        log "🚀 Force flag detected, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    if [[ ! $REPLY == "yes" ]]; then
        log "❌ Cleanup cancelled"
        exit 0
    fi
}

# Delete API Gateway
delete_api_gateway() {
    if [ -n "${API_ID:-}" ]; then
        log "🗑️  Deleting API Gateway..."
        
        if aws apigateway get-rest-api --rest-api-id "${API_ID}" &> /dev/null; then
            aws apigateway delete-rest-api --rest-api-id "${API_ID}" || \
                error_log "Failed to delete API Gateway ${API_ID}"
            log "✅ API Gateway deleted (${API_ID})"
        else
            log "ℹ️  API Gateway ${API_ID} not found (may already be deleted)"
        fi
    else
        # Try manual discovery
        if [ -n "${API_GATEWAYS:-}" ]; then
            for api_info in $API_GATEWAYS; do
                api_id=$(echo "$api_info" | cut -f1)
                if [ -n "$api_id" ] && [ "$api_id" != "None" ]; then
                    log "🗑️  Deleting discovered API Gateway ${api_id}..."
                    aws apigateway delete-rest-api --rest-api-id "$api_id" || \
                        error_log "Failed to delete API Gateway $api_id"
                    log "✅ API Gateway deleted ($api_id)"
                fi
            done
        else
            log "ℹ️  No API Gateway to delete"
        fi
    fi
}

# Delete Lambda function
delete_lambda_function() {
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        log "⚡ Deleting Lambda function..."
        
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
            aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}" || \
                error_log "Failed to delete Lambda function ${LAMBDA_FUNCTION_NAME}"
            log "✅ Lambda function deleted (${LAMBDA_FUNCTION_NAME})"
        else
            log "ℹ️  Lambda function ${LAMBDA_FUNCTION_NAME} not found (may already be deleted)"
        fi
    else
        # Try manual discovery
        if [ -n "${LAMBDA_FUNCTIONS:-}" ]; then
            for func_name in $LAMBDA_FUNCTIONS; do
                if [ -n "$func_name" ] && [ "$func_name" != "None" ]; then
                    log "⚡ Deleting discovered Lambda function ${func_name}..."
                    aws lambda delete-function --function-name "$func_name" || \
                        error_log "Failed to delete Lambda function $func_name"
                    log "✅ Lambda function deleted ($func_name)"
                fi
            done
        else
            log "ℹ️  No Lambda function to delete"
        fi
    fi
}

# Delete IAM resources
delete_iam_resources() {
    log "🔐 Deleting IAM resources..."
    
    # Handle IAM role deletion
    if [ -n "${IAM_ROLE_NAME:-}" ]; then
        delete_iam_role "${IAM_ROLE_NAME}"
    else
        # Try manual discovery
        if [ -n "${IAM_ROLES:-}" ]; then
            for role_name in $IAM_ROLES; do
                if [ -n "$role_name" ] && [ "$role_name" != "None" ]; then
                    delete_iam_role "$role_name"
                fi
            done
        else
            log "ℹ️  No IAM role to delete"
        fi
    fi
    
    # Handle IAM policy deletion
    if [ -n "${POLICY_NAME:-}" ]; then
        delete_iam_policy "${POLICY_NAME}"
    else
        # Try to find policies by name pattern
        local policies=$(aws iam list-policies --scope Local --query 'Policies[?starts_with(PolicyName, `contact-form-ses-policy-`)].PolicyName' --output text 2>/dev/null || echo "")
        if [ -n "$policies" ]; then
            for policy_name in $policies; do
                if [ -n "$policy_name" ] && [ "$policy_name" != "None" ]; then
                    delete_iam_policy "$policy_name"
                fi
            done
        else
            log "ℹ️  No custom IAM policy to delete"
        fi
    fi
}

# Delete specific IAM role
delete_iam_role() {
    local role_name="$1"
    
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        log "Deleting IAM role: $role_name"
        
        # Detach all policies from role
        local attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        
        if [ -n "$attached_policies" ]; then
            for policy_arn in $attached_policies; do
                if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
                    log "  Detaching policy: $policy_arn"
                    aws iam detach-role-policy \
                        --role-name "$role_name" \
                        --policy-arn "$policy_arn" || \
                        error_log "Failed to detach policy $policy_arn from role $role_name"
                fi
            done
        fi
        
        # Delete the role
        aws iam delete-role --role-name "$role_name" || \
            error_log "Failed to delete IAM role $role_name"
        log "✅ IAM role deleted ($role_name)"
    else
        log "ℹ️  IAM role $role_name not found (may already be deleted)"
    fi
}

# Delete specific IAM policy
delete_iam_policy() {
    local policy_name="$1"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy_name"
    
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        log "Deleting IAM policy: $policy_name"
        
        # Check if policy is attached to any entities
        local entities=$(aws iam list-entities-for-policy --policy-arn "$policy_arn" --query 'PolicyRoles[].RoleName' --output text 2>/dev/null || echo "")
        
        if [ -n "$entities" ] && [ "$entities" != "None" ]; then
            log "  Policy is still attached to entities: $entities"
            for entity in $entities; do
                log "  Detaching from role: $entity"
                aws iam detach-role-policy \
                    --role-name "$entity" \
                    --policy-arn "$policy_arn" || \
                    error_log "Failed to detach policy from $entity"
            done
        fi
        
        # Delete the policy
        aws iam delete-policy --policy-arn "$policy_arn" || \
            error_log "Failed to delete IAM policy $policy_name"
        log "✅ IAM policy deleted ($policy_name)"
    else
        log "ℹ️  IAM policy $policy_name not found (may already be deleted)"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "🧹 Cleaning up local files..."
    
    # Remove temporary files if they exist
    local files_to_remove=(
        "${TEMP_DIR}/lambda_function.py"
        "${TEMP_DIR}/lambda-function.zip"
        "${TEMP_DIR}/trust-policy.json"
        "${TEMP_DIR}/ses-policy.json"
        "${TEMP_DIR}/test-event.json"
        "${TEMP_DIR}/response.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "  Removed: $(basename "$file")"
        fi
    done
    
    cleanup_temp_files
    log "✅ Local files cleaned up"
}

# Verify cleanup
verify_cleanup() {
    log "🔍 Verifying cleanup..."
    
    local issues_found=false
    
    # Check for remaining Lambda functions
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
            error_log "Lambda function ${LAMBDA_FUNCTION_NAME} still exists"
            issues_found=true
        fi
    fi
    
    # Check for remaining API Gateways
    if [ -n "${API_ID:-}" ]; then
        if aws apigateway get-rest-api --rest-api-id "${API_ID}" &> /dev/null; then
            error_log "API Gateway ${API_ID} still exists"
            issues_found=true
        fi
    fi
    
    # Check for remaining IAM role
    if [ -n "${IAM_ROLE_NAME:-}" ]; then
        if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
            error_log "IAM role ${IAM_ROLE_NAME} still exists"
            issues_found=true
        fi
    fi
    
    # Check for remaining IAM policy
    if [ -n "${POLICY_NAME:-}" ]; then
        local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
        if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
            error_log "IAM policy ${POLICY_NAME} still exists"
            issues_found=true
        fi
    fi
    
    if [ "$issues_found" = true ]; then
        log "⚠️  Some resources may still exist - check AWS Console for manual cleanup"
        log "💡 Tip: Check CloudFormation stacks if resources were created via other means"
    else
        log "✅ Cleanup verification passed - no resources detected"
    fi
}

# Display cost information
show_cost_info() {
    log ""
    log "💰 Cost Information:"
    log "  - Lambda: No charges if within free tier (1M requests/month)"
    log "  - API Gateway: No charges if within free tier (1M requests/month)"
    log "  - SES: No charges if within free tier (62K emails/month)"
    log "  - IAM: No charges for roles and policies"
    log ""
    log "🔍 To verify no charges are accruing:"
    log "  1. Check AWS Billing Dashboard"
    log "  2. Review AWS Cost Explorer"
    log "  3. Set up billing alerts for future deployments"
    log ""
}

# Prerequisites check
check_prerequisites() {
    log "🔍 Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_log "AWS CLI is not installed"
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_log "AWS credentials not configured"
        exit 1
    fi
    
    log "✅ Prerequisites check passed"
}

# Main cleanup function
main() {
    log "🗑️  Starting AWS Contact Form Backend cleanup..."
    
    # Set trap for cleanup on exit
    trap cleanup_temp_files EXIT
    
    check_prerequisites
    load_environment
    confirm_destruction "$@"
    
    # Create temp directory for any cleanup operations
    mkdir -p "${TEMP_DIR}"
    
    # Delete resources in reverse order of creation
    delete_api_gateway
    delete_lambda_function
    delete_iam_resources
    cleanup_local_files
    verify_cleanup
    show_cost_info
    
    success_handler
}

# Display help
show_help() {
    echo "AWS Contact Form Backend Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompt"
    echo "  --help     Show this help message"
    echo ""
    echo "This script removes all AWS resources created by the deployment script."
    echo "It will safely delete:"
    echo "  - API Gateway REST API"
    echo "  - Lambda function"
    echo "  - IAM role and custom policies"
    echo "  - Local temporary files"
    echo ""
    echo "Note: SES email verification will NOT be removed (manual action required)"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac