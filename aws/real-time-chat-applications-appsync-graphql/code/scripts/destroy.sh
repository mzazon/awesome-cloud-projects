#!/bin/bash

# Real-Time Chat Applications with AppSync and GraphQL - Cleanup Script
# This script destroys all infrastructure created by the deployment script
# to avoid ongoing charges and clean up AWS resources

set -e  # Exit on any error

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Load resource configuration
load_resource_config() {
    log "Loading resource configuration..."
    
    if [ -f "/tmp/chat-app-resources.env" ]; then
        source /tmp/chat-app-resources.env
        log_success "Loaded resource configuration from /tmp/chat-app-resources.env"
        log "Chat App Name: ${CHAT_APP_NAME}"
        log "AWS Region: ${AWS_REGION}"
    else
        log_warning "Resource configuration file not found. Will attempt to discover resources."
        
        # Try to get current AWS region
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            log_warning "No region configured, using default: us-east-1"
        fi
        
        # Prompt user for app name pattern if not available
        if [ -z "$CHAT_APP_NAME" ]; then
            echo ""
            echo "Resource configuration not found. Please provide the chat app name or pattern:"
            echo "Example: realtime-chat-abcd1234"
            read -p "Chat app name (or pattern): " CHAT_APP_NAME
            
            if [ -z "$CHAT_APP_NAME" ]; then
                log_error "Chat app name is required for cleanup"
                exit 1
            fi
        fi
    fi
}

# Confirm destruction with user
confirm_destruction() {
    echo ""
    echo "======================================"
    echo "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "======================================"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "  • AppSync API and all resolvers"
    echo "  • DynamoDB tables and all data"
    echo "  • Cognito User Pool and all users"
    echo "  • IAM roles and policies"
    echo ""
    echo "App Name Pattern: ${CHAT_APP_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo ""
    echo "⚠️  THIS ACTION CANNOT BE UNDONE ⚠️"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Proceeding with resource cleanup..."
}

# Delete AppSync API and related resources
delete_appsync_api() {
    log "Deleting AppSync API..."
    
    # Try to get API ID from configuration or discover it
    if [ -z "$API_ID" ]; then
        log "Discovering AppSync API..."
        API_ID=$(aws appsync list-graphql-apis \
            --query "graphqlApis[?contains(name, '${CHAT_APP_NAME}')].apiId" \
            --output text 2>/dev/null | head -1)
    fi
    
    if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
        log "Found AppSync API: ${API_ID}"
        
        # Delete AppSync API (this removes all resolvers and data sources)
        aws appsync delete-graphql-api \
            --api-id "${API_ID}" > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            log_success "Deleted AppSync API: ${API_ID}"
        else
            log_warning "Failed to delete AppSync API (may not exist or already deleted)"
        fi
    else
        log_warning "No AppSync API found matching pattern: ${CHAT_APP_NAME}"
    fi
}

# Delete DynamoDB tables
delete_dynamodb_tables() {
    log "Deleting DynamoDB tables..."
    
    # Define table patterns if not loaded from config
    if [ -z "$DYNAMODB_MESSAGES_TABLE" ]; then
        DYNAMODB_MESSAGES_TABLE="${CHAT_APP_NAME}-messages"
    fi
    if [ -z "$DYNAMODB_CONVERSATIONS_TABLE" ]; then
        DYNAMODB_CONVERSATIONS_TABLE="${CHAT_APP_NAME}-conversations"
    fi
    if [ -z "$DYNAMODB_USERS_TABLE" ]; then
        DYNAMODB_USERS_TABLE="${CHAT_APP_NAME}-users"
    fi
    
    # Delete Messages table
    if aws dynamodb describe-table --table-name "${DYNAMODB_MESSAGES_TABLE}" &> /dev/null; then
        log "Deleting Messages table: ${DYNAMODB_MESSAGES_TABLE}"
        aws dynamodb delete-table \
            --table-name "${DYNAMODB_MESSAGES_TABLE}" > /dev/null
        
        if [ $? -eq 0 ]; then
            log_success "Initiated deletion of Messages table"
        else
            log_warning "Failed to delete Messages table"
        fi
    else
        log_warning "Messages table not found: ${DYNAMODB_MESSAGES_TABLE}"
    fi
    
    # Delete Conversations table
    if aws dynamodb describe-table --table-name "${DYNAMODB_CONVERSATIONS_TABLE}" &> /dev/null; then
        log "Deleting Conversations table: ${DYNAMODB_CONVERSATIONS_TABLE}"
        aws dynamodb delete-table \
            --table-name "${DYNAMODB_CONVERSATIONS_TABLE}" > /dev/null
        
        if [ $? -eq 0 ]; then
            log_success "Initiated deletion of Conversations table"
        else
            log_warning "Failed to delete Conversations table"
        fi
    else
        log_warning "Conversations table not found: ${DYNAMODB_CONVERSATIONS_TABLE}"
    fi
    
    # Delete Users table
    if aws dynamodb describe-table --table-name "${DYNAMODB_USERS_TABLE}" &> /dev/null; then
        log "Deleting Users table: ${DYNAMODB_USERS_TABLE}"
        aws dynamodb delete-table \
            --table-name "${DYNAMODB_USERS_TABLE}" > /dev/null
        
        if [ $? -eq 0 ]; then
            log_success "Initiated deletion of Users table"
        else
            log_warning "Failed to delete Users table"
        fi
    else
        log_warning "Users table not found: ${DYNAMODB_USERS_TABLE}"
    fi
    
    log "DynamoDB table deletion initiated (tables will be deleted asynchronously)"
}

# Delete Cognito User Pool
delete_cognito_user_pool() {
    log "Deleting Cognito User Pool..."
    
    # Try to get User Pool ID from configuration or discover it
    if [ -z "$USER_POOL_ID" ]; then
        log "Discovering Cognito User Pool..."
        USER_POOL_NAME="${CHAT_APP_NAME}-users"
        USER_POOL_ID=$(aws cognito-idp list-user-pools \
            --max-items 50 \
            --query "UserPools[?contains(Name, '${USER_POOL_NAME}')].Id" \
            --output text 2>/dev/null | head -1)
    fi
    
    if [ -n "$USER_POOL_ID" ] && [ "$USER_POOL_ID" != "None" ]; then
        log "Found Cognito User Pool: ${USER_POOL_ID}"
        
        # Delete User Pool (this also deletes all clients and users)
        aws cognito-idp delete-user-pool \
            --user-pool-id "${USER_POOL_ID}" > /dev/null
        
        if [ $? -eq 0 ]; then
            log_success "Deleted Cognito User Pool: ${USER_POOL_ID}"
        else
            log_warning "Failed to delete Cognito User Pool (may not exist or already deleted)"
        fi
    else
        log_warning "No Cognito User Pool found matching pattern: ${CHAT_APP_NAME}"
    fi
}

# Delete IAM role and policies
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    IAM_ROLE_NAME="${CHAT_APP_NAME}-appsync-role"
    
    # Check if role exists
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        log "Found IAM role: ${IAM_ROLE_NAME}"
        
        # Delete inline policies first
        log "Deleting inline policies..."
        POLICIES=$(aws iam list-role-policies \
            --role-name "${IAM_ROLE_NAME}" \
            --query 'PolicyNames[]' \
            --output text 2>/dev/null)
        
        if [ -n "$POLICIES" ]; then
            for policy in $POLICIES; do
                log "Deleting policy: ${policy}"
                aws iam delete-role-policy \
                    --role-name "${IAM_ROLE_NAME}" \
                    --policy-name "${policy}" > /dev/null
                
                if [ $? -eq 0 ]; then
                    log_success "Deleted policy: ${policy}"
                else
                    log_warning "Failed to delete policy: ${policy}"
                fi
            done
        fi
        
        # Detach managed policies
        log "Detaching managed policies..."
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "${IAM_ROLE_NAME}" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null)
        
        if [ -n "$ATTACHED_POLICIES" ]; then
            for policy_arn in $ATTACHED_POLICIES; do
                log "Detaching policy: ${policy_arn}"
                aws iam detach-role-policy \
                    --role-name "${IAM_ROLE_NAME}" \
                    --policy-arn "${policy_arn}" > /dev/null
                
                if [ $? -eq 0 ]; then
                    log_success "Detached policy: ${policy_arn}"
                else
                    log_warning "Failed to detach policy: ${policy_arn}"
                fi
            done
        fi
        
        # Delete the role
        aws iam delete-role \
            --role-name "${IAM_ROLE_NAME}" > /dev/null
        
        if [ $? -eq 0 ]; then
            log_success "Deleted IAM role: ${IAM_ROLE_NAME}"
        else
            log_warning "Failed to delete IAM role: ${IAM_ROLE_NAME}"
        fi
    else
        log_warning "IAM role not found: ${IAM_ROLE_NAME}"
    fi
}

# Wait for DynamoDB table deletions to complete
wait_for_table_deletions() {
    log "Waiting for DynamoDB table deletions to complete..."
    
    tables_to_check=(
        "${DYNAMODB_MESSAGES_TABLE}"
        "${DYNAMODB_CONVERSATIONS_TABLE}"
        "${DYNAMODB_USERS_TABLE}"
    )
    
    for table in "${tables_to_check[@]}"; do
        log "Checking deletion status for table: ${table}"
        
        # Wait up to 5 minutes for table deletion
        timeout_counter=0
        max_timeout=30  # 30 * 10 seconds = 5 minutes
        
        while [ $timeout_counter -lt $max_timeout ]; do
            if aws dynamodb describe-table --table-name "${table}" &> /dev/null; then
                log "Table ${table} still exists, waiting..."
                sleep 10
                ((timeout_counter++))
            else
                log_success "Table ${table} has been deleted"
                break
            fi
        done
        
        if [ $timeout_counter -eq $max_timeout ]; then
            log_warning "Timeout waiting for table ${table} deletion (may still be in progress)"
        fi
    done
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove resource configuration file
    if [ -f "/tmp/chat-app-resources.env" ]; then
        rm -f /tmp/chat-app-resources.env
        log_success "Removed resource configuration file"
    fi
    
    # Remove any remaining temporary files
    rm -f /tmp/chat-schema.graphql \
          /tmp/appsync-trust-policy.json \
          /tmp/appsync-dynamodb-policy.json \
          /tmp/send-message-*.vtl \
          /tmp/list-messages-*.vtl \
          /tmp/create-conversation-*.vtl \
          /tmp/update-user-presence-*.vtl
    
    log_success "Cleaned up temporary files"
}

# Verify resource deletion
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    # Check AppSync APIs
    REMAINING_APIS=$(aws appsync list-graphql-apis \
        --query "graphqlApis[?contains(name, '${CHAT_APP_NAME}')].name" \
        --output text 2>/dev/null)
    
    if [ -n "$REMAINING_APIS" ] && [ "$REMAINING_APIS" != "None" ]; then
        log_warning "Some AppSync APIs may still exist: ${REMAINING_APIS}"
    else
        log_success "No AppSync APIs found with pattern: ${CHAT_APP_NAME}"
    fi
    
    # Check DynamoDB tables
    for table in "${DYNAMODB_MESSAGES_TABLE}" "${DYNAMODB_CONVERSATIONS_TABLE}" "${DYNAMODB_USERS_TABLE}"; do
        if aws dynamodb describe-table --table-name "${table}" &> /dev/null; then
            log_warning "DynamoDB table still exists: ${table}"
        else
            log_success "DynamoDB table deleted: ${table}"
        fi
    done
    
    # Check Cognito User Pools
    REMAINING_POOLS=$(aws cognito-idp list-user-pools \
        --max-items 50 \
        --query "UserPools[?contains(Name, '${CHAT_APP_NAME}')].Name" \
        --output text 2>/dev/null)
    
    if [ -n "$REMAINING_POOLS" ] && [ "$REMAINING_POOLS" != "None" ]; then
        log_warning "Some Cognito User Pools may still exist: ${REMAINING_POOLS}"
    else
        log_success "No Cognito User Pools found with pattern: ${CHAT_APP_NAME}"
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name "${CHAT_APP_NAME}-appsync-role" &> /dev/null; then
        log_warning "IAM role still exists: ${CHAT_APP_NAME}-appsync-role"
    else
        log_success "IAM role deleted: ${CHAT_APP_NAME}-appsync-role"
    fi
}

# Display cleanup summary
display_summary() {
    log_success "Cleanup completed!"
    echo ""
    echo "======================================"
    echo "REAL-TIME CHAT APPLICATION CLEANUP"
    echo "======================================"
    echo ""
    echo "Resources cleaned up:"
    echo "  ✅ AppSync API and resolvers"
    echo "  ✅ DynamoDB tables (Messages, Conversations, Users)"
    echo "  ✅ Cognito User Pool and test users"
    echo "  ✅ IAM roles and policies"
    echo "  ✅ Temporary files"
    echo ""
    echo "Chat App Pattern: ${CHAT_APP_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo ""
    echo "Note: Some resources may take additional time to be fully"
    echo "removed from your AWS account. Check the AWS Console to"
    echo "verify all resources have been deleted."
    echo ""
    echo "If you encounter any remaining resources, you can:"
    echo "1. Check the AWS Console for each service"
    echo "2. Manually delete any remaining resources"
    echo "3. Re-run this script with the correct app name"
    echo ""
}

# Main cleanup function
main() {
    log "Starting Real-Time Chat Application cleanup..."
    
    check_prerequisites
    load_resource_config
    confirm_destruction
    delete_appsync_api
    delete_dynamodb_tables
    delete_cognito_user_pool
    delete_iam_resources
    wait_for_table_deletions
    cleanup_temp_files
    verify_cleanup
    display_summary
}

# Handle script interruption
cleanup_on_exit() {
    log_warning "Cleanup script interrupted"
    log "Some resources may not have been fully cleaned up"
    log "You may need to manually delete remaining resources or re-run this script"
    exit 1
}

# Set trap for script interruption
trap cleanup_on_exit INT TERM

# Run main function
main "$@"