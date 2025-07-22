#!/bin/bash

# AWS AppSync GraphQL API Cleanup Script
# This script removes all resources created by the deploy.sh script
# Based on the recipe: Real-Time GraphQL API with AppSync

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log "Running in dry-run mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            log "Force delete mode enabled - skipping confirmation prompts"
            shift
            ;;
        *)
            warn "Unknown option: $1"
            shift
            ;;
    esac
done

# Function to execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN] Would execute: $cmd${NC}"
        if [[ -n "$description" ]]; then
            echo -e "${YELLOW}[DRY-RUN] Description: $description${NC}"
        fi
        return 0
    else
        log "$description"
        if eval "$cmd"; then
            return 0
        else
            warn "Command failed, continuing with cleanup: $cmd"
            return 1
        fi
    fi
}

# Load configuration from deployment
load_configuration() {
    log "Loading deployment configuration..."
    
    if [[ ! -f ".deployment-config" ]]; then
        error "Configuration file .deployment-config not found!"
        error "This script requires the configuration file created by deploy.sh"
        exit 1
    fi
    
    # Source the configuration file
    source .deployment-config
    
    # Validate required variables
    local required_vars=(
        "API_ID"
        "TABLE_NAME"
        "USER_POOL_ID"
        "ROLE_NAME"
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            error "Required variable $var not found in configuration"
            exit 1
        fi
    done
    
    success "Configuration loaded successfully"
    log "API ID: $API_ID"
    log "Table: $TABLE_NAME"
    log "User Pool: $USER_POOL_ID"
    log "Role: $ROLE_NAME"
    log "Region: $AWS_REGION"
}

# Confirm deletion with user
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log "Force delete mode - skipping confirmation"
        return 0
    fi
    
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   • AppSync GraphQL API: $API_ID"
    echo "   • DynamoDB Table: $TABLE_NAME"
    echo "   • Cognito User Pool: $USER_POOL_ID"
    echo "   • IAM Role: $ROLE_NAME"
    echo "   • All associated data and configurations"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry-run mode - no actual deletion will occur"
        return 0
    fi
    
    read -p "Are you sure you want to delete these resources? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed, proceeding with cleanup..."
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Verify we can access the resources
    if [[ "$DRY_RUN" == "false" ]]; then
        # Check if AppSync API exists
        if ! aws appsync get-graphql-api --api-id "$API_ID" &> /dev/null; then
            warn "AppSync API $API_ID not found or not accessible"
        fi
        
        # Check if DynamoDB table exists
        if ! aws dynamodb describe-table --table-name "$TABLE_NAME" &> /dev/null; then
            warn "DynamoDB table $TABLE_NAME not found or not accessible"
        fi
        
        # Check if Cognito User Pool exists
        if ! aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" &> /dev/null; then
            warn "Cognito User Pool $USER_POOL_ID not found or not accessible"
        fi
    fi
    
    success "Prerequisites check completed"
}

# Delete AppSync API (this also deletes resolvers and data sources)
delete_appsync_api() {
    log "Deleting AppSync GraphQL API..."
    
    local delete_api_cmd="aws appsync delete-graphql-api --api-id $API_ID"
    
    if execute_cmd "$delete_api_cmd" "Delete AppSync API"; then
        success "AppSync API deleted: $API_ID"
    else
        warn "Failed to delete AppSync API, it may not exist"
    fi
    
    # Wait for deletion to complete
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for AppSync API deletion to complete..."
        local max_attempts=20
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if ! aws appsync get-graphql-api --api-id "$API_ID" &> /dev/null; then
                success "AppSync API deletion confirmed"
                break
            fi
            
            log "Waiting for deletion... (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            warn "AppSync API deletion timeout - may still be in progress"
        fi
    fi
}

# Delete DynamoDB table
delete_dynamodb_table() {
    log "Deleting DynamoDB table..."
    
    local delete_table_cmd="aws dynamodb delete-table --table-name $TABLE_NAME"
    
    if execute_cmd "$delete_table_cmd" "Delete DynamoDB table"; then
        success "DynamoDB table deletion initiated: $TABLE_NAME"
    else
        warn "Failed to delete DynamoDB table, it may not exist"
        return 0
    fi
    
    # Wait for deletion to complete
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for DynamoDB table deletion to complete..."
        local max_attempts=30
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if ! aws dynamodb describe-table --table-name "$TABLE_NAME" &> /dev/null; then
                success "DynamoDB table deletion confirmed"
                break
            fi
            
            local table_status=$(aws dynamodb describe-table --table-name "$TABLE_NAME" \
                --query 'Table.TableStatus' --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [[ "$table_status" == "DELETING" ]]; then
                log "Table is being deleted... (attempt $attempt/$max_attempts)"
            elif [[ "$table_status" == "NOT_FOUND" ]]; then
                success "DynamoDB table deletion confirmed"
                break
            else
                warn "Unexpected table status: $table_status"
            fi
            
            sleep 10
            ((attempt++))
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            warn "DynamoDB table deletion timeout - may still be in progress"
        fi
    fi
}

# Delete Cognito User Pool
delete_cognito_user_pool() {
    log "Deleting Cognito User Pool..."
    
    local delete_pool_cmd="aws cognito-idp delete-user-pool --user-pool-id $USER_POOL_ID"
    
    if execute_cmd "$delete_pool_cmd" "Delete Cognito User Pool"; then
        success "Cognito User Pool deleted: $USER_POOL_ID"
    else
        warn "Failed to delete Cognito User Pool, it may not exist"
    fi
}

# Delete IAM role and policies
delete_iam_role() {
    log "Deleting IAM role and policies..."
    
    # First, delete the inline policy
    local delete_policy_cmd="aws iam delete-role-policy \
        --role-name $ROLE_NAME \
        --policy-name DynamoDBAccess"
    
    if execute_cmd "$delete_policy_cmd" "Delete IAM role policy"; then
        success "IAM role policy deleted"
    else
        warn "Failed to delete IAM role policy, it may not exist"
    fi
    
    # Then delete the role
    local delete_role_cmd="aws iam delete-role --role-name $ROLE_NAME"
    
    if execute_cmd "$delete_role_cmd" "Delete IAM role"; then
        success "IAM role deleted: $ROLE_NAME"
    else
        warn "Failed to delete IAM role, it may not exist"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        ".deployment-config"
        "schema.graphql"
        "appsync-service-role-trust-policy.json"
        "appsync-dynamodb-policy.json"
        "get-blog-post-request.vtl"
        "get-blog-post-response.vtl"
        "create-blog-post-request.vtl"
        "create-blog-post-response.vtl"
        "list-blog-posts-request.vtl"
        "list-blog-posts-response.vtl"
        "list-by-author-request.vtl"
        "test_client.py"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                echo -e "${YELLOW}[DRY-RUN] Would remove: $file${NC}"
            else
                rm -f "$file"
                log "Removed: $file"
            fi
        fi
    done
    
    success "Local files cleaned up"
}

# Verify resource deletion
verify_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry-run mode - skipping deletion verification"
        return 0
    fi
    
    log "Verifying resource deletion..."
    
    local verification_failed=false
    
    # Check AppSync API
    if aws appsync get-graphql-api --api-id "$API_ID" &> /dev/null; then
        warn "AppSync API still exists: $API_ID"
        verification_failed=true
    else
        success "AppSync API deletion verified"
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "$TABLE_NAME" &> /dev/null; then
        warn "DynamoDB table still exists: $TABLE_NAME"
        verification_failed=true
    else
        success "DynamoDB table deletion verified"
    fi
    
    # Check Cognito User Pool
    if aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" &> /dev/null; then
        warn "Cognito User Pool still exists: $USER_POOL_ID"
        verification_failed=true
    else
        success "Cognito User Pool deletion verified"
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        warn "IAM role still exists: $ROLE_NAME"
        verification_failed=true
    else
        success "IAM role deletion verified"
    fi
    
    if [[ "$verification_failed" == "true" ]]; then
        warn "Some resources may not have been deleted completely"
        warn "Please check the AWS console and delete any remaining resources manually"
    else
        success "All resources have been successfully deleted"
    fi
}

# Display destruction summary
display_summary() {
    echo ""
    echo "=============================================="
    echo "          DESTRUCTION SUMMARY"
    echo "=============================================="
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN COMPLETED - No resources were deleted"
        echo ""
        echo "The following resources would have been deleted:"
        echo "- AppSync GraphQL API: $API_ID"
        echo "- DynamoDB Table: $TABLE_NAME"
        echo "- Cognito User Pool: $USER_POOL_ID"
        echo "- IAM Role: $ROLE_NAME"
        echo "- Local configuration files"
        echo ""
        echo "To destroy for real, run: $0"
        return 0
    fi
    
    echo "🧹 Cleanup completed!"
    echo ""
    echo "📋 Resources Deleted:"
    echo "   • AppSync GraphQL API: $API_ID"
    echo "   • DynamoDB Table: $TABLE_NAME"
    echo "   • Cognito User Pool: $USER_POOL_ID"
    echo "   • IAM Role: $ROLE_NAME"
    echo "   • Local configuration files"
    echo ""
    echo "💰 Cost Impact:"
    echo "   • No more charges for these resources"
    echo "   • DynamoDB table data permanently deleted"
    echo "   • User authentication data removed"
    echo ""
    echo "⚠️  Important Notes:"
    echo "   • All data has been permanently deleted"
    echo "   • This action cannot be undone"
    echo "   • Check AWS console to confirm deletion"
    echo ""
    echo "🔄 To redeploy:"
    echo "   • Run: ./deploy.sh"
    echo ""
    echo "=============================================="
}

# Main execution
main() {
    log "Starting AppSync GraphQL API cleanup..."
    
    load_configuration
    check_prerequisites
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_appsync_api
    delete_dynamodb_table
    delete_cognito_user_pool
    delete_iam_role
    cleanup_local_files
    
    verify_deletion
    display_summary
    
    log "Cleanup completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "All resources have been removed."
        echo "You can now safely delete this directory or run deploy.sh again."
    fi
}

# Handle script interruption
trap 'error "Script interrupted by user"; exit 1' INT TERM

# Execute main function
main "$@"