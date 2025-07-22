#!/bin/bash

# Destroy script for Serverless Web Applications with Amplify and Lambda
# This script removes all resources created by the deploy.sh script
# including Amplify apps, Lambda functions, API Gateway, Cognito, and DynamoDB

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

if [ "$DRY_RUN" = "true" ]; then
    warning "Running in DRY-RUN mode. No resources will be deleted."
fi

# Function to execute commands with dry-run support
execute() {
    if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY-RUN] Would execute: $*"
    else
        "$@"
    fi
}

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f .env ]; then
        source .env
        log "Environment loaded from .env file"
        log "  AWS Region: ${AWS_REGION}"
        log "  App Name: ${APP_NAME}"
    else
        warning "No .env file found. Attempting to discover resources..."
        
        # Try to discover resources by common patterns
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            error "AWS region not configured. Cannot proceed with cleanup."
            exit 1
        fi
        
        # List Amplify apps to find matching app
        AMPLIFY_APPS=$(aws amplify list-apps --query 'apps[?contains(name, `serverless-web-app`)].name' --output text 2>/dev/null || echo "")
        if [ -n "$AMPLIFY_APPS" ]; then
            APP_NAME=$(echo "$AMPLIFY_APPS" | head -n 1)
            warning "Found Amplify app: ${APP_NAME}"
        else
            error "No Amplify apps found matching pattern. Manual cleanup may be required."
            list_resources
            exit 1
        fi
    fi
    
    success "Environment variables loaded"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check Amplify CLI
    if ! command -v amplify &> /dev/null; then
        warning "Amplify CLI not found. Some cleanup operations may fail."
    fi
    
    success "Prerequisites check completed"
}

# Confirmation prompt
confirm_destruction() {
    if [ "$DRY_RUN" = "true" ]; then
        warning "DRY-RUN mode: Skipping confirmation"
        return 0
    fi
    
    echo ""
    warning "This will permanently delete the following resources:"
    echo "  - Amplify app: ${APP_NAME}"
    echo "  - All associated Lambda functions"
    echo "  - API Gateway REST APIs"
    echo "  - Cognito User Pools"
    echo "  - DynamoDB tables"
    echo "  - CloudWatch log groups and dashboards"
    echo "  - S3 buckets (if any)"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    warning "Last chance! This action cannot be undone."
    read -p "Type 'DELETE' to confirm: " -r
    if [[ $REPLY != "DELETE" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Delete Amplify app and all associated resources
delete_amplify_app() {
    log "Deleting Amplify app and associated resources..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Try to navigate to project directory
        PROJECT_DIR="${HOME}/amplify-projects/${APP_NAME}/frontend"
        if [ -d "$PROJECT_DIR" ]; then
            cd "$PROJECT_DIR"
            
            # Delete Amplify app and all resources
            log "Deleting Amplify app: ${APP_NAME}"
            amplify delete --yes 2>/dev/null || {
                warning "Amplify CLI delete failed, attempting manual cleanup..."
                
                # Get Amplify app ID
                APP_ID=$(aws amplify list-apps --query "apps[?name=='${APP_NAME}'].appId" --output text 2>/dev/null)
                if [ -n "$APP_ID" ] && [ "$APP_ID" != "None" ]; then
                    log "Found Amplify app ID: ${APP_ID}"
                    aws amplify delete-app --app-id "$APP_ID" 2>/dev/null || warning "Failed to delete Amplify app"
                fi
            }
        else
            warning "Project directory not found, attempting direct AWS resource cleanup..."
            
            # Try to find and delete Amplify app directly
            APP_ID=$(aws amplify list-apps --query "apps[?name=='${APP_NAME}'].appId" --output text 2>/dev/null)
            if [ -n "$APP_ID" ] && [ "$APP_ID" != "None" ]; then
                log "Deleting Amplify app directly: ${APP_ID}"
                aws amplify delete-app --app-id "$APP_ID" 2>/dev/null || warning "Failed to delete Amplify app"
            fi
        fi
    else
        echo "[DRY-RUN] Would delete Amplify app: ${APP_NAME}"
    fi
    
    success "Amplify app deletion completed"
}

# Delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Get all Lambda functions that match our pattern
        LAMBDA_FUNCTIONS=$(aws lambda list-functions \
            --query "Functions[?contains(FunctionName, '${APP_NAME}') || contains(FunctionName, '${LAMBDA_FUNCTION_NAME}')].FunctionName" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$LAMBDA_FUNCTIONS" ]; then
            for func in $LAMBDA_FUNCTIONS; do
                log "Deleting Lambda function: ${func}"
                aws lambda delete-function --function-name "$func" 2>/dev/null || warning "Failed to delete Lambda function: $func"
            done
        else
            log "No Lambda functions found matching pattern"
        fi
    else
        echo "[DRY-RUN] Would delete Lambda functions matching pattern: ${APP_NAME}"
    fi
    
    success "Lambda functions cleanup completed"
}

# Delete API Gateway resources
delete_api_gateway() {
    log "Deleting API Gateway resources..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Get REST APIs that match our pattern
        API_IDS=$(aws apigateway get-rest-apis \
            --query "items[?contains(name, '${APP_NAME}')].id" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$API_IDS" ]; then
            for api_id in $API_IDS; do
                log "Deleting API Gateway: ${api_id}"
                aws apigateway delete-rest-api --rest-api-id "$api_id" 2>/dev/null || warning "Failed to delete API Gateway: $api_id"
            done
        else
            log "No API Gateway resources found matching pattern"
        fi
    else
        echo "[DRY-RUN] Would delete API Gateway resources matching pattern: ${APP_NAME}"
    fi
    
    success "API Gateway cleanup completed"
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Delete CloudWatch dashboard
        DASHBOARD_NAME="${APP_NAME}-dashboard"
        aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME" 2>/dev/null || log "Dashboard not found or already deleted"
        
        # Delete Lambda log groups
        LOG_GROUPS=$(aws logs describe-log-groups \
            --query "logGroups[?contains(logGroupName, '${APP_NAME}') || contains(logGroupName, '${LAMBDA_FUNCTION_NAME}')].logGroupName" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$LOG_GROUPS" ]; then
            for log_group in $LOG_GROUPS; do
                log "Deleting log group: ${log_group}"
                aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null || warning "Failed to delete log group: $log_group"
            done
        else
            log "No log groups found matching pattern"
        fi
    else
        echo "[DRY-RUN] Would delete CloudWatch dashboard and log groups"
    fi
    
    success "CloudWatch resources cleanup completed"
}

# Delete DynamoDB tables
delete_dynamodb_tables() {
    log "Deleting DynamoDB tables..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Get DynamoDB tables that match our pattern
        TABLES=$(aws dynamodb list-tables \
            --query "TableNames[?contains(@, '${APP_NAME}')]" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$TABLES" ]; then
            for table in $TABLES; do
                log "Deleting DynamoDB table: ${table}"
                aws dynamodb delete-table --table-name "$table" 2>/dev/null || warning "Failed to delete table: $table"
                
                # Wait for table deletion to complete
                log "Waiting for table deletion to complete..."
                aws dynamodb wait table-not-exists --table-name "$table" 2>/dev/null || warning "Wait timeout for table: $table"
            done
        else
            log "No DynamoDB tables found matching pattern"
        fi
    else
        echo "[DRY-RUN] Would delete DynamoDB tables matching pattern: ${APP_NAME}"
    fi
    
    success "DynamoDB tables cleanup completed"
}

# Delete Cognito resources
delete_cognito_resources() {
    log "Deleting Cognito resources..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Get User Pools that match our pattern
        USER_POOLS=$(aws cognito-idp list-user-pools --max-items 60 \
            --query "UserPools[?contains(Name, '${APP_NAME}')].Id" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$USER_POOLS" ]; then
            for pool_id in $USER_POOLS; do
                log "Deleting Cognito User Pool: ${pool_id}"
                aws cognito-idp delete-user-pool --user-pool-id "$pool_id" 2>/dev/null || warning "Failed to delete User Pool: $pool_id"
            done
        else
            log "No Cognito User Pools found matching pattern"
        fi
        
        # Get Identity Pools that match our pattern
        IDENTITY_POOLS=$(aws cognito-identity list-identity-pools --max-results 60 \
            --query "IdentityPools[?contains(IdentityPoolName, '${APP_NAME}')].IdentityPoolId" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$IDENTITY_POOLS" ]; then
            for pool_id in $IDENTITY_POOLS; do
                log "Deleting Cognito Identity Pool: ${pool_id}"
                aws cognito-identity delete-identity-pool --identity-pool-id "$pool_id" 2>/dev/null || warning "Failed to delete Identity Pool: $pool_id"
            done
        else
            log "No Cognito Identity Pools found matching pattern"
        fi
    else
        echo "[DRY-RUN] Would delete Cognito User Pools and Identity Pools"
    fi
    
    success "Cognito resources cleanup completed"
}

# Delete S3 buckets
delete_s3_buckets() {
    log "Deleting S3 buckets..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Get S3 buckets that match our pattern
        BUCKETS=$(aws s3 ls | grep "${APP_NAME}" | awk '{print $3}' 2>/dev/null || echo "")
        
        if [ -n "$BUCKETS" ]; then
            for bucket in $BUCKETS; do
                log "Deleting S3 bucket: ${bucket}"
                
                # Delete all objects in bucket first
                aws s3 rm "s3://${bucket}" --recursive 2>/dev/null || warning "Failed to empty bucket: $bucket"
                
                # Delete the bucket
                aws s3 rb "s3://${bucket}" 2>/dev/null || warning "Failed to delete bucket: $bucket"
            done
        else
            log "No S3 buckets found matching pattern"
        fi
    else
        echo "[DRY-RUN] Would delete S3 buckets matching pattern: ${APP_NAME}"
    fi
    
    success "S3 buckets cleanup completed"
}

# Delete IAM roles and policies
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Get IAM roles that match our pattern
        ROLES=$(aws iam list-roles \
            --query "Roles[?contains(RoleName, '${APP_NAME}')].RoleName" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$ROLES" ]; then
            for role in $ROLES; do
                log "Processing IAM role: ${role}"
                
                # Detach managed policies
                ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" \
                    --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || echo "")
                for policy_arn in $ATTACHED_POLICIES; do
                    aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
                done
                
                # Delete inline policies
                INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" \
                    --query "PolicyNames" --output text 2>/dev/null || echo "")
                for policy in $INLINE_POLICIES; do
                    aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
                done
                
                # Delete the role
                aws iam delete-role --role-name "$role" 2>/dev/null || warning "Failed to delete IAM role: $role"
            done
        else
            log "No IAM roles found matching pattern"
        fi
    else
        echo "[DRY-RUN] Would delete IAM roles matching pattern: ${APP_NAME}"
    fi
    
    success "IAM resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [ "$DRY_RUN" != "true" ]; then
        # Remove project directory
        PROJECT_DIR="${HOME}/amplify-projects/${APP_NAME}"
        if [ -d "$PROJECT_DIR" ]; then
            log "Removing project directory: ${PROJECT_DIR}"
            rm -rf "$PROJECT_DIR"
        fi
        
        # Remove environment file
        if [ -f .env ]; then
            log "Removing environment file"
            rm -f .env
        fi
        
        # Remove any temporary files
        rm -f /tmp/lambda-response.json 2>/dev/null || true
    else
        echo "[DRY-RUN] Would remove local project files and environment"
    fi
    
    success "Local files cleanup completed"
}

# List remaining resources for manual cleanup
list_resources() {
    log "Scanning for any remaining resources..."
    
    echo ""
    echo "=== Remaining AWS Resources ==="
    
    # Check Amplify apps
    echo "Amplify Apps:"
    aws amplify list-apps --query 'apps[?contains(name, `serverless-web-app`)].{Name:name,AppId:appId}' --output table 2>/dev/null || echo "  None found"
    
    # Check Lambda functions
    echo ""
    echo "Lambda Functions:"
    aws lambda list-functions --query "Functions[?contains(FunctionName, 'serverless-web-app') || contains(FunctionName, 'api-')].{Name:FunctionName,Runtime:Runtime}" --output table 2>/dev/null || echo "  None found"
    
    # Check API Gateway
    echo ""
    echo "API Gateway REST APIs:"
    aws apigateway get-rest-apis --query "items[?contains(name, 'serverless-web-app')].{Name:name,Id:id}" --output table 2>/dev/null || echo "  None found"
    
    # Check DynamoDB tables
    echo ""
    echo "DynamoDB Tables:"
    aws dynamodb list-tables --query "TableNames[?contains(@, 'serverless-web-app')]" --output table 2>/dev/null || echo "  None found"
    
    # Check S3 buckets
    echo ""
    echo "S3 Buckets:"
    aws s3 ls | grep "serverless-web-app" 2>/dev/null || echo "  None found"
    
    echo ""
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY-RUN] Would verify all resources have been deleted"
        return 0
    fi
    
    # Check for remaining resources
    REMAINING_APPS=$(aws amplify list-apps --query "apps[?name=='${APP_NAME}'].name" --output text 2>/dev/null || echo "")
    REMAINING_FUNCTIONS=$(aws lambda list-functions --query "Functions[?contains(FunctionName, '${APP_NAME}')].FunctionName" --output text 2>/dev/null || echo "")
    REMAINING_APIS=$(aws apigateway get-rest-apis --query "items[?contains(name, '${APP_NAME}')].name" --output text 2>/dev/null || echo "")
    
    if [ -n "$REMAINING_APPS" ] || [ -n "$REMAINING_FUNCTIONS" ] || [ -n "$REMAINING_APIS" ]; then
        warning "Some resources may still exist. Run with --list to see remaining resources."
        list_resources
    else
        success "All resources have been successfully deleted"
    fi
}

# Display final status
display_final_status() {
    echo ""
    if [ "$DRY_RUN" = "true" ]; then
        success "DRY-RUN completed successfully!"
        echo ""
        echo "=== What would be deleted ==="
        echo "- Amplify app: ${APP_NAME}"
        echo "- All Lambda functions with pattern: ${APP_NAME}"
        echo "- All API Gateway resources with pattern: ${APP_NAME}"
        echo "- All DynamoDB tables with pattern: ${APP_NAME}"
        echo "- All Cognito resources with pattern: ${APP_NAME}"
        echo "- All S3 buckets with pattern: ${APP_NAME}"
        echo "- All IAM roles with pattern: ${APP_NAME}"
        echo "- CloudWatch dashboards and log groups"
        echo "- Local project files and environment"
    else
        success "Cleanup completed successfully!"
        echo ""
        echo "=== Cleanup Summary ==="
        echo "✅ Amplify app deleted"
        echo "✅ Lambda functions removed"
        echo "✅ API Gateway resources deleted"
        echo "✅ DynamoDB tables removed"
        echo "✅ Cognito resources deleted"
        echo "✅ S3 buckets removed"
        echo "✅ IAM roles cleaned up"
        echo "✅ CloudWatch resources deleted"
        echo "✅ Local files removed"
        echo ""
        echo "All serverless web application resources have been successfully removed."
        echo "You should not incur any further charges from this deployment."
    fi
}

# Handle command line arguments
handle_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                export DRY_RUN=true
                shift
                ;;
            --list)
                list_resources
                exit 0
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --dry-run    Show what would be deleted without actually deleting"
                echo "  --list       List all resources that match the cleanup pattern"
                echo "  --help       Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  DRY_RUN      Set to 'true' to enable dry-run mode"
                echo ""
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Main cleanup function
main() {
    log "Starting cleanup of Serverless Web Application with Amplify and Lambda"
    log "======================================================================"
    
    handle_arguments "$@"
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Execute cleanup in order (dependencies first)
    delete_amplify_app
    delete_lambda_functions
    delete_api_gateway
    delete_dynamodb_tables
    delete_cognito_resources
    delete_s3_buckets
    delete_iam_resources
    delete_cloudwatch_resources
    cleanup_local_files
    
    verify_cleanup
    display_final_status
    
    success "Cleanup process completed!"
}

# Error handling
set -e
trap 'error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"