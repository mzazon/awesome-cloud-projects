#!/bin/bash

# Destroy script for Real-Time WebSocket APIs with Route Management and Connection Handling
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    warn "Running in DRY-RUN mode - no resources will be deleted"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    info "$description"
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY-RUN: $cmd"
        return 0
    else
        if [ "$ignore_errors" = "true" ]; then
            eval "$cmd" || warn "Command failed but continuing: $cmd"
            return 0
        else
            eval "$cmd"
            return $?
        fi
    fi
}

# Function to check if deployment info exists
check_deployment_info() {
    if [ ! -f "deployment-info.txt" ]; then
        error "No deployment-info.txt file found. Cannot determine resources to delete."
        echo "This could mean:"
        echo "  1. No deployment was made from this directory"
        echo "  2. The deployment-info.txt file was deleted"
        echo "  3. You're running this script from the wrong directory"
        echo ""
        echo "To manually clean up resources, you'll need to identify and delete:"
        echo "  - DynamoDB tables (websocket-connections-*, websocket-rooms-*, websocket-messages-*)"
        echo "  - Lambda functions (websocket-connect-*, websocket-disconnect-*, websocket-message-*)"
        echo "  - API Gateway WebSocket APIs"
        echo "  - IAM roles and policies (websocket-lambda-role-*, websocket-policy-*)"
        exit 1
    fi
}

# Function to load deployment info
load_deployment_info() {
    log "Loading deployment information..."
    
    # Source the deployment info file
    source deployment-info.txt
    
    # Verify required variables are present
    if [ -z "$DEPLOYMENT_ID" ] || [ -z "$AWS_REGION" ] || [ -z "$AWS_ACCOUNT_ID" ]; then
        error "Deployment info file is missing required variables"
        exit 1
    fi
    
    info "Deployment ID: $DEPLOYMENT_ID"
    info "AWS Region: $AWS_REGION"
    info "AWS Account: $AWS_ACCOUNT_ID"
    
    # Export variables for use in cleanup
    export AWS_REGION
    export AWS_ACCOUNT_ID
    export DEPLOYMENT_ID
    export API_NAME
    export CONNECTIONS_TABLE
    export ROOMS_TABLE
    export MESSAGES_TABLE
    export LAMBDA_ROLE_NAME
    export POLICY_NAME
    export API_ID
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$DRY_RUN" = "true" ]; then
        return 0
    fi
    
    echo ""
    warn "This will permanently delete the following resources:"
    echo "  - WebSocket API: $API_NAME"
    echo "  - DynamoDB Tables: $CONNECTIONS_TABLE, $ROOMS_TABLE, $MESSAGES_TABLE"
    echo "  - Lambda Functions: websocket-connect-$DEPLOYMENT_ID, websocket-disconnect-$DEPLOYMENT_ID, websocket-message-$DEPLOYMENT_ID"
    echo "  - IAM Role: $LAMBDA_ROLE_NAME"
    echo "  - IAM Policy: $POLICY_NAME"
    echo ""
    echo "This action cannot be undone and will result in data loss."
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        echo "Deletion cancelled."
        exit 0
    fi
    
    echo ""
    log "Proceeding with resource deletion..."
}

# Function to delete WebSocket API
delete_websocket_api() {
    log "Deleting WebSocket API..."
    
    if [ -n "$API_ID" ]; then
        execute_cmd "aws apigatewayv2 delete-api \
            --api-id $API_ID \
            --region $AWS_REGION" "Deleting WebSocket API: $API_ID" true
    else
        warn "API_ID not found in deployment info, skipping API deletion"
    fi
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    # Delete connection handler
    execute_cmd "aws lambda delete-function \
        --function-name websocket-connect-$DEPLOYMENT_ID \
        --region $AWS_REGION" "Deleting connect handler function" true
    
    # Delete disconnect handler
    execute_cmd "aws lambda delete-function \
        --function-name websocket-disconnect-$DEPLOYMENT_ID \
        --region $AWS_REGION" "Deleting disconnect handler function" true
    
    # Delete message handler
    execute_cmd "aws lambda delete-function \
        --function-name websocket-message-$DEPLOYMENT_ID \
        --region $AWS_REGION" "Deleting message handler function" true
}

# Function to delete DynamoDB tables
delete_dynamodb_tables() {
    log "Deleting DynamoDB tables..."
    
    # Delete connections table
    if [ -n "$CONNECTIONS_TABLE" ]; then
        execute_cmd "aws dynamodb delete-table \
            --table-name $CONNECTIONS_TABLE \
            --region $AWS_REGION" "Deleting connections table: $CONNECTIONS_TABLE" true
    fi
    
    # Delete rooms table
    if [ -n "$ROOMS_TABLE" ]; then
        execute_cmd "aws dynamodb delete-table \
            --table-name $ROOMS_TABLE \
            --region $AWS_REGION" "Deleting rooms table: $ROOMS_TABLE" true
    fi
    
    # Delete messages table
    if [ -n "$MESSAGES_TABLE" ]; then
        execute_cmd "aws dynamodb delete-table \
            --table-name $MESSAGES_TABLE \
            --region $AWS_REGION" "Deleting messages table: $MESSAGES_TABLE" true
    fi
    
    if [ "$DRY_RUN" != "true" ]; then
        # Wait for table deletion to complete
        info "Waiting for DynamoDB tables to be deleted..."
        
        if [ -n "$CONNECTIONS_TABLE" ]; then
            aws dynamodb wait table-not-exists --table-name $CONNECTIONS_TABLE --region $AWS_REGION 2>/dev/null || true
        fi
        
        if [ -n "$ROOMS_TABLE" ]; then
            aws dynamodb wait table-not-exists --table-name $ROOMS_TABLE --region $AWS_REGION 2>/dev/null || true
        fi
        
        if [ -n "$MESSAGES_TABLE" ]; then
            aws dynamodb wait table-not-exists --table-name $MESSAGES_TABLE --region $AWS_REGION 2>/dev/null || true
        fi
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    if [ -n "$LAMBDA_ROLE_NAME" ]; then
        # Detach policies from role
        execute_cmd "aws iam detach-role-policy \
            --role-name $LAMBDA_ROLE_NAME \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" "Detaching Lambda basic execution policy" true
        
        if [ -n "$POLICY_NAME" ]; then
            execute_cmd "aws iam detach-role-policy \
                --role-name $LAMBDA_ROLE_NAME \
                --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME" "Detaching custom WebSocket policy" true
        fi
        
        # Delete role
        execute_cmd "aws iam delete-role \
            --role-name $LAMBDA_ROLE_NAME" "Deleting IAM role: $LAMBDA_ROLE_NAME" true
    fi
    
    if [ -n "$POLICY_NAME" ]; then
        # Delete custom policy
        execute_cmd "aws iam delete-policy \
            --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME" "Deleting IAM policy: $POLICY_NAME" true
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove Python Lambda function files
    execute_cmd "rm -f connect_handler.py connect_handler.zip" "Removing connect handler files" true
    execute_cmd "rm -f disconnect_handler.py disconnect_handler.zip" "Removing disconnect handler files" true
    execute_cmd "rm -f message_handler.py message_handler.zip" "Removing message handler files" true
    
    # Remove test client
    execute_cmd "rm -f websocket_client.py" "Removing test client" true
    
    # Remove deployment info file
    if [ "$DRY_RUN" != "true" ]; then
        execute_cmd "rm -f deployment-info.txt" "Removing deployment info file" true
    fi
}

# Function to verify resource deletion
verify_deletion() {
    if [ "$DRY_RUN" = "true" ]; then
        return 0
    fi
    
    log "Verifying resource deletion..."
    
    # Check if Lambda functions still exist
    local lambda_functions=("websocket-connect-$DEPLOYMENT_ID" "websocket-disconnect-$DEPLOYMENT_ID" "websocket-message-$DEPLOYMENT_ID")
    
    for func in "${lambda_functions[@]}"; do
        if aws lambda get-function --function-name "$func" --region "$AWS_REGION" >/dev/null 2>&1; then
            warn "Lambda function $func still exists"
        else
            info "✅ Lambda function $func deleted"
        fi
    done
    
    # Check if DynamoDB tables still exist
    local tables=("$CONNECTIONS_TABLE" "$ROOMS_TABLE" "$MESSAGES_TABLE")
    
    for table in "${tables[@]}"; do
        if [ -n "$table" ]; then
            if aws dynamodb describe-table --table-name "$table" --region "$AWS_REGION" >/dev/null 2>&1; then
                warn "DynamoDB table $table still exists"
            else
                info "✅ DynamoDB table $table deleted"
            fi
        fi
    done
    
    # Check if API Gateway still exists
    if [ -n "$API_ID" ]; then
        if aws apigatewayv2 get-api --api-id "$API_ID" --region "$AWS_REGION" >/dev/null 2>&1; then
            warn "API Gateway $API_ID still exists"
        else
            info "✅ API Gateway $API_ID deleted"
        fi
    fi
    
    # Check if IAM role still exists
    if [ -n "$LAMBDA_ROLE_NAME" ]; then
        if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" >/dev/null 2>&1; then
            warn "IAM role $LAMBDA_ROLE_NAME still exists"
        else
            info "✅ IAM role $LAMBDA_ROLE_NAME deleted"
        fi
    fi
    
    # Check if IAM policy still exists
    if [ -n "$POLICY_NAME" ]; then
        if aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME" >/dev/null 2>&1; then
            warn "IAM policy $POLICY_NAME still exists"
        else
            info "✅ IAM policy $POLICY_NAME deleted"
        fi
    fi
}

# Function to show deletion summary
show_deletion_summary() {
    log "Deletion Summary"
    echo "=================="
    echo "Deployment ID: $DEPLOYMENT_ID"
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account: $AWS_ACCOUNT_ID"
    echo ""
    echo "Resources Deleted:"
    echo "- WebSocket API: $API_NAME"
    echo "- DynamoDB Tables: $CONNECTIONS_TABLE, $ROOMS_TABLE, $MESSAGES_TABLE"
    echo "- Lambda Functions: websocket-connect-$DEPLOYMENT_ID, websocket-disconnect-$DEPLOYMENT_ID, websocket-message-$DEPLOYMENT_ID"
    echo "- IAM Role: $LAMBDA_ROLE_NAME"
    echo "- IAM Policy: $POLICY_NAME"
    echo ""
    
    if [ "$DRY_RUN" != "true" ]; then
        echo "Local files cleaned up:"
        echo "- Python Lambda function files and zips"
        echo "- WebSocket test client"
        echo "- deployment-info.txt"
        echo ""
        echo "All resources have been deleted successfully."
    else
        echo "DRY-RUN mode: No resources were actually deleted."
    fi
}

# Function to handle cleanup of partial deployments
cleanup_partial_deployment() {
    log "Attempting to clean up partial deployment..."
    
    # Try to find and delete resources by pattern
    local deployment_pattern="websocket-*-$DEPLOYMENT_ID"
    
    # Find and delete Lambda functions
    info "Searching for Lambda functions matching pattern: $deployment_pattern"
    
    # Get all Lambda functions and filter by pattern
    local lambda_functions=$(aws lambda list-functions --region "$AWS_REGION" --query "Functions[?contains(FunctionName, 'websocket-') && contains(FunctionName, '$DEPLOYMENT_ID')].FunctionName" --output text 2>/dev/null || true)
    
    if [ -n "$lambda_functions" ]; then
        for func in $lambda_functions; do
            execute_cmd "aws lambda delete-function \
                --function-name $func \
                --region $AWS_REGION" "Deleting Lambda function: $func" true
        done
    fi
    
    # Find and delete DynamoDB tables
    info "Searching for DynamoDB tables matching pattern: websocket-*-$DEPLOYMENT_ID"
    
    local dynamodb_tables=$(aws dynamodb list-tables --region "$AWS_REGION" --query "TableNames[?contains(@, 'websocket-') && contains(@, '$DEPLOYMENT_ID')]" --output text 2>/dev/null || true)
    
    if [ -n "$dynamodb_tables" ]; then
        for table in $dynamodb_tables; do
            execute_cmd "aws dynamodb delete-table \
                --table-name $table \
                --region $AWS_REGION" "Deleting DynamoDB table: $table" true
        done
    fi
    
    # Find and delete API Gateway APIs
    info "Searching for API Gateway APIs matching pattern: websocket-api-$DEPLOYMENT_ID"
    
    local api_ids=$(aws apigatewayv2 get-apis --region "$AWS_REGION" --query "Items[?contains(Name, 'websocket-api-$DEPLOYMENT_ID')].ApiId" --output text 2>/dev/null || true)
    
    if [ -n "$api_ids" ]; then
        for api_id in $api_ids; do
            execute_cmd "aws apigatewayv2 delete-api \
                --api-id $api_id \
                --region $AWS_REGION" "Deleting API Gateway: $api_id" true
        done
    fi
    
    # Find and delete IAM roles
    info "Searching for IAM roles matching pattern: websocket-lambda-role-$DEPLOYMENT_ID"
    
    local iam_roles=$(aws iam list-roles --query "Roles[?contains(RoleName, 'websocket-lambda-role-$DEPLOYMENT_ID')].RoleName" --output text 2>/dev/null || true)
    
    if [ -n "$iam_roles" ]; then
        for role in $iam_roles; do
            # Detach policies first
            execute_cmd "aws iam detach-role-policy \
                --role-name $role \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" "Detaching basic execution policy from $role" true
            
            execute_cmd "aws iam detach-role-policy \
                --role-name $role \
                --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/websocket-policy-$DEPLOYMENT_ID" "Detaching custom policy from $role" true
            
            execute_cmd "aws iam delete-role \
                --role-name $role" "Deleting IAM role: $role" true
        done
    fi
    
    # Find and delete IAM policies
    info "Searching for IAM policies matching pattern: websocket-policy-$DEPLOYMENT_ID"
    
    local policy_arn="arn:aws:iam::$AWS_ACCOUNT_ID:policy/websocket-policy-$DEPLOYMENT_ID"
    if aws iam get-policy --policy-arn "$policy_arn" >/dev/null 2>&1; then
        execute_cmd "aws iam delete-policy \
            --policy-arn $policy_arn" "Deleting IAM policy: websocket-policy-$DEPLOYMENT_ID" true
    fi
}

# Main cleanup function
main() {
    log "Starting WebSocket API cleanup..."
    
    # Check if we're in a deployment directory
    if [ ! -f "deployment-info.txt" ]; then
        error "No deployment-info.txt found. This script must be run from the deployment directory."
        echo ""
        echo "If you need to clean up resources manually, you can:"
        echo "1. Use the AWS Console to identify and delete resources"
        echo "2. Use AWS CLI to list and delete resources by pattern"
        echo "3. Run this script with a valid deployment-info.txt file"
        exit 1
    fi
    
    load_deployment_info
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_websocket_api
    delete_lambda_functions
    delete_dynamodb_tables
    delete_iam_resources
    cleanup_local_files
    
    # Verify deletion
    verify_deletion
    
    show_deletion_summary
    
    log "WebSocket API cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may still exist. Please run the script again or clean up manually."; exit 1' INT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            echo "WebSocket API Cleanup Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --force      Skip confirmation prompts"
            echo "  --help       Show this help message"
            echo ""
            echo "This script reads deployment-info.txt to determine which resources to delete."
            echo "Make sure to run this from the same directory where you ran deploy.sh"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Override confirmation if force flag is set
if [ "$FORCE" = "true" ]; then
    confirm_deletion() {
        log "Force flag set, skipping confirmation..."
    }
fi

# Run main function
main "$@"