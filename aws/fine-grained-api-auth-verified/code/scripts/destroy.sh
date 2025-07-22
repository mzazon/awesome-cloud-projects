#!/bin/bash

# Destroy script for Fine-Grained API Authorization with Verified Permissions
# This script safely removes all resources created by the deployment script

set -e

# Color codes for output
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

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Load environment variables from deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [ ! -f ".deployment-state/resources.env" ]; then
        error "Deployment state file not found. Cannot proceed with cleanup."
        error "Please ensure you're running this script from the same directory as the deployment."
        exit 1
    fi
    
    # Source the environment variables
    source .deployment-state/resources.env
    
    # Validate required variables
    if [ -z "$RANDOM_SUFFIX" ]; then
        error "RANDOM_SUFFIX not found in deployment state"
        exit 1
    fi
    
    success "Deployment state loaded successfully"
}

# Confirmation prompt
confirm_destruction() {
    echo
    warn "⚠️  WARNING: This will permanently delete all resources created by the deployment script!"
    echo
    echo "Resources to be deleted:"
    echo "- API Gateway: ${API_NAME:-Not found}"
    echo "- Lambda Functions: ${AUTHORIZER_FUNCTION_NAME:-Not found}, ${BUSINESS_FUNCTION_NAME:-Not found}"
    echo "- Cognito User Pool: ${USER_POOL_NAME:-Not found}"
    echo "- Verified Permissions Policy Store: ${POLICY_STORE_NAME:-Not found}"
    echo "- DynamoDB Table: ${DOCUMENTS_TABLE:-Not found}"
    echo "- IAM Role: ${LAMBDA_ROLE_NAME:-Not found}"
    echo
    
    # Skip confirmation if --force flag is provided
    if [ "$1" = "--force" ]; then
        warn "Force flag detected, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Remove API Gateway
remove_api_gateway() {
    log "Removing API Gateway..."
    
    if [ -z "$API_ID" ]; then
        warn "API_ID not found in deployment state, skipping API Gateway removal"
        return 0
    fi
    
    # Check if API Gateway exists
    if ! aws apigateway get-rest-api --rest-api-id "$API_ID" &> /dev/null; then
        warn "API Gateway ${API_ID} not found, may have been deleted already"
        return 0
    fi
    
    # Delete API Gateway
    aws apigateway delete-rest-api --rest-api-id "$API_ID"
    
    success "API Gateway removed successfully"
}

# Remove Lambda functions
remove_lambda_functions() {
    log "Removing Lambda functions..."
    
    # Remove Lambda authorizer function
    if [ -n "$AUTHORIZER_FUNCTION_NAME" ]; then
        if aws lambda get-function --function-name "$AUTHORIZER_FUNCTION_NAME" &> /dev/null; then
            aws lambda delete-function --function-name "$AUTHORIZER_FUNCTION_NAME"
            success "Lambda authorizer function removed"
        else
            warn "Lambda authorizer function ${AUTHORIZER_FUNCTION_NAME} not found"
        fi
    fi
    
    # Remove Lambda business function
    if [ -n "$BUSINESS_FUNCTION_NAME" ]; then
        if aws lambda get-function --function-name "$BUSINESS_FUNCTION_NAME" &> /dev/null; then
            aws lambda delete-function --function-name "$BUSINESS_FUNCTION_NAME"
            success "Lambda business function removed"
        else
            warn "Lambda business function ${BUSINESS_FUNCTION_NAME} not found"
        fi
    fi
    
    success "Lambda functions cleanup completed"
}

# Remove Verified Permissions resources
remove_verified_permissions() {
    log "Removing Verified Permissions resources..."
    
    if [ -z "$POLICY_STORE_ID" ]; then
        warn "POLICY_STORE_ID not found in deployment state, skipping Verified Permissions removal"
        return 0
    fi
    
    # Check if policy store exists
    if ! aws verifiedpermissions get-policy-store --policy-store-id "$POLICY_STORE_ID" &> /dev/null; then
        warn "Policy Store ${POLICY_STORE_ID} not found, may have been deleted already"
        return 0
    fi
    
    # Remove policies
    for POLICY_VAR in VIEW_POLICY_ID EDIT_POLICY_ID DELETE_POLICY_ID; do
        POLICY_ID=${!POLICY_VAR}
        if [ -n "$POLICY_ID" ]; then
            if aws verifiedpermissions get-policy --policy-store-id "$POLICY_STORE_ID" --policy-id "$POLICY_ID" &> /dev/null; then
                aws verifiedpermissions delete-policy \
                    --policy-store-id "$POLICY_STORE_ID" \
                    --policy-id "$POLICY_ID"
                log "Removed policy: $POLICY_ID"
            else
                warn "Policy ${POLICY_ID} not found"
            fi
        fi
    done
    
    # Remove identity source
    if [ -n "$IDENTITY_SOURCE_ID" ]; then
        if aws verifiedpermissions get-identity-source --policy-store-id "$POLICY_STORE_ID" --identity-source-id "$IDENTITY_SOURCE_ID" &> /dev/null; then
            aws verifiedpermissions delete-identity-source \
                --policy-store-id "$POLICY_STORE_ID" \
                --identity-source-id "$IDENTITY_SOURCE_ID"
            log "Removed identity source: $IDENTITY_SOURCE_ID"
        else
            warn "Identity source ${IDENTITY_SOURCE_ID} not found"
        fi
    fi
    
    # Remove policy store
    aws verifiedpermissions delete-policy-store --policy-store-id "$POLICY_STORE_ID"
    
    success "Verified Permissions resources removed successfully"
}

# Remove Cognito User Pool
remove_cognito_user_pool() {
    log "Removing Cognito User Pool..."
    
    if [ -z "$USER_POOL_ID" ]; then
        warn "USER_POOL_ID not found in deployment state, skipping Cognito removal"
        return 0
    fi
    
    # Check if user pool exists
    if ! aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" &> /dev/null; then
        warn "User Pool ${USER_POOL_ID} not found, may have been deleted already"
        return 0
    fi
    
    # Delete user pool (this automatically deletes the client as well)
    aws cognito-idp delete-user-pool --user-pool-id "$USER_POOL_ID"
    
    success "Cognito User Pool removed successfully"
}

# Remove DynamoDB table
remove_dynamodb_table() {
    log "Removing DynamoDB table..."
    
    if [ -z "$DOCUMENTS_TABLE" ]; then
        warn "DOCUMENTS_TABLE not found in deployment state, skipping DynamoDB removal"
        return 0
    fi
    
    # Check if table exists
    if ! aws dynamodb describe-table --table-name "$DOCUMENTS_TABLE" &> /dev/null; then
        warn "DynamoDB table ${DOCUMENTS_TABLE} not found, may have been deleted already"
        return 0
    fi
    
    # Delete table
    aws dynamodb delete-table --table-name "$DOCUMENTS_TABLE"
    
    # Wait for table to be deleted
    log "Waiting for DynamoDB table to be deleted..."
    aws dynamodb wait table-not-exists --table-name "$DOCUMENTS_TABLE"
    
    success "DynamoDB table removed successfully"
}

# Remove IAM role and policies
remove_iam_role() {
    log "Removing IAM role and policies..."
    
    if [ -z "$LAMBDA_ROLE_NAME" ]; then
        warn "LAMBDA_ROLE_NAME not found in deployment state, skipping IAM role removal"
        return 0
    fi
    
    # Check if role exists
    if ! aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        warn "IAM role ${LAMBDA_ROLE_NAME} not found, may have been deleted already"
        return 0
    fi
    
    # Remove inline policies
    INLINE_POLICIES=$(aws iam list-role-policies --role-name "$LAMBDA_ROLE_NAME" --query 'PolicyNames' --output text)
    for POLICY in $INLINE_POLICIES; do
        if [ "$POLICY" != "None" ]; then
            aws iam delete-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-name "$POLICY"
            log "Removed inline policy: $POLICY"
        fi
    done
    
    # Detach managed policies
    ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text)
    for POLICY_ARN in $ATTACHED_POLICIES; do
        if [ "$POLICY_ARN" != "None" ]; then
            aws iam detach-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-arn "$POLICY_ARN"
            log "Detached managed policy: $POLICY_ARN"
        fi
    done
    
    # Delete role
    aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"
    
    success "IAM role removed successfully"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment state directory
    if [ -d ".deployment-state" ]; then
        rm -rf .deployment-state
        success "Deployment state directory removed"
    fi
    
    # Remove any remaining temporary files
    rm -f cognito-config.json
    rm -f trust-policy.json
    rm -f lambda-policy.json
    rm -f *.cedar
    rm -f *.zip
    rm -rf lambda-authorizer
    rm -rf lambda-business
    
    success "Local files cleaned up"
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check API Gateway
    if [ -n "$API_ID" ] && aws apigateway get-rest-api --rest-api-id "$API_ID" &> /dev/null; then
        error "API Gateway still exists: $API_ID"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check Lambda functions
    if [ -n "$AUTHORIZER_FUNCTION_NAME" ] && aws lambda get-function --function-name "$AUTHORIZER_FUNCTION_NAME" &> /dev/null; then
        error "Lambda authorizer function still exists: $AUTHORIZER_FUNCTION_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ -n "$BUSINESS_FUNCTION_NAME" ] && aws lambda get-function --function-name "$BUSINESS_FUNCTION_NAME" &> /dev/null; then
        error "Lambda business function still exists: $BUSINESS_FUNCTION_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check Cognito User Pool
    if [ -n "$USER_POOL_ID" ] && aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" &> /dev/null; then
        error "Cognito User Pool still exists: $USER_POOL_ID"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check Verified Permissions Policy Store
    if [ -n "$POLICY_STORE_ID" ] && aws verifiedpermissions get-policy-store --policy-store-id "$POLICY_STORE_ID" &> /dev/null; then
        error "Verified Permissions Policy Store still exists: $POLICY_STORE_ID"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check DynamoDB table
    if [ -n "$DOCUMENTS_TABLE" ] && aws dynamodb describe-table --table-name "$DOCUMENTS_TABLE" &> /dev/null; then
        error "DynamoDB table still exists: $DOCUMENTS_TABLE"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check IAM role
    if [ -n "$LAMBDA_ROLE_NAME" ] && aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        error "IAM role still exists: $LAMBDA_ROLE_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        success "Cleanup verification passed - all resources removed"
        return 0
    else
        error "Cleanup verification failed - $cleanup_issues resources still exist"
        return 1
    fi
}

# Main destruction function
main() {
    log "Starting destruction of Fine-Grained API Authorization resources..."
    
    load_deployment_state
    confirm_destruction "$1"
    
    # Remove resources in reverse order of creation
    remove_api_gateway
    remove_lambda_functions
    remove_verified_permissions
    remove_cognito_user_pool
    remove_dynamodb_table
    remove_iam_role
    cleanup_local_files
    
    echo
    success "🗑️  Destruction completed!"
    echo
    
    # Verify cleanup
    if verify_cleanup; then
        success "All resources have been successfully removed"
    else
        warn "Some resources may still exist. Please check manually."
        exit 1
    fi
    
    echo
    success "Fine-Grained API Authorization infrastructure has been completely removed"
    echo "Thank you for using the automated cleanup script!"
}

# Handle script arguments
case "$1" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "  --force    Skip confirmation prompt"
        echo "  --help     Show this help message"
        echo
        echo "This script safely removes all AWS resources created by the deployment script."
        echo "It will prompt for confirmation unless --force is used."
        exit 0
        ;;
    *)
        main "$1"
        ;;
esac