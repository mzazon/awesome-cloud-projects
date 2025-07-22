#!/bin/bash

###################################################################################
# Destroy Script for Enterprise GraphQL API Architecture
# 
# This script safely removes all infrastructure created by the deploy.sh script,
# including AppSync APIs, DynamoDB tables, OpenSearch domains, Lambda functions,
# Cognito User Pools, and associated IAM roles.
# 
# Features:
# - Safe resource deletion with confirmation prompts
# - Dependency-aware cleanup order
# - Comprehensive logging and error handling
# - Resource verification before deletion
# - Partial cleanup handling
#
# Author: AWS Recipes Project
# Version: 1.0
# Last Updated: 2025-01-12
###################################################################################

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handling function
handle_error() {
    local line_number=$1
    log_error "Script failed at line $line_number"
    log_error "Some resources may remain. Check AWS console and manually clean up if needed."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/../.env"

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log_info "Starting GraphQL API cleanup at $(date)"
log_info "Log file: $LOG_FILE"

###################################################################################
# Configuration Loading and Validation
###################################################################################

load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_error "This usually means no deployment was created or the config file was deleted."
        log_info "You may need to manually identify and clean up resources using the AWS console."
        exit 1
    fi
    
    # Source the configuration file
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    # Validate required variables
    local required_vars=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "PROJECT_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable $var not found in configuration"
            exit 1
        fi
    done
    
    log_success "Configuration loaded successfully"
    log_info "Project: $PROJECT_NAME"
    log_info "Region: $AWS_REGION"
    log_info "Account: $AWS_ACCOUNT_ID"
}

###################################################################################
# Confirmation and Safety Functions
###################################################################################

confirm_destruction() {
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log_warning "This script will permanently delete the following resources:"
    echo ""
    
    if [[ -n "${API_ID:-}" ]]; then
        log_info "  • AppSync GraphQL API: $API_ID"
    fi
    
    if [[ -n "${PRODUCTS_TABLE:-}" ]]; then
        log_info "  • DynamoDB Tables: $PRODUCTS_TABLE, $USERS_TABLE, $ANALYTICS_TABLE"
    fi
    
    if [[ -n "${OPENSEARCH_DOMAIN:-}" ]]; then
        log_info "  • OpenSearch Domain: $OPENSEARCH_DOMAIN"
    fi
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log_info "  • Lambda Function: $LAMBDA_FUNCTION_NAME"
    fi
    
    if [[ -n "${USER_POOL_ID:-}" ]]; then
        log_info "  • Cognito User Pool: $USER_POOL_ID"
    fi
    
    log_info "  • Associated IAM Roles and Policies"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    
    if [[ "${FORCE_CLEANUP:-false}" == "true" ]]; then
        log_warning "Force cleanup mode enabled - proceeding without confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to delete all these resources? (type 'DELETE' to confirm): " -r
    echo
    
    if [[ "$REPLY" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Cleanup confirmed - proceeding with resource deletion"
}

###################################################################################
# Resource Existence Check Functions
###################################################################################

check_resource_existence() {
    log_info "Checking which resources exist..."
    
    # Check AppSync API
    if [[ -n "${API_ID:-}" ]]; then
        if aws appsync get-graphql-api --api-id "$API_ID" &> /dev/null; then
            log_info "✓ AppSync API exists: $API_ID"
            APPSYNC_EXISTS=true
        else
            log_warning "AppSync API not found: $API_ID"
            APPSYNC_EXISTS=false
        fi
    else
        APPSYNC_EXISTS=false
    fi
    
    # Check DynamoDB tables
    local tables=("${PRODUCTS_TABLE:-}" "${USERS_TABLE:-}" "${ANALYTICS_TABLE:-}")
    DYNAMODB_TABLES_EXIST=()
    
    for table in "${tables[@]}"; do
        if [[ -n "$table" ]]; then
            if aws dynamodb describe-table --table-name "$table" &> /dev/null; then
                log_info "✓ DynamoDB table exists: $table"
                DYNAMODB_TABLES_EXIST+=("$table")
            else
                log_warning "DynamoDB table not found: $table"
            fi
        fi
    done
    
    # Check OpenSearch domain
    if [[ -n "${OPENSEARCH_DOMAIN:-}" ]]; then
        if aws opensearch describe-domain --domain-name "$OPENSEARCH_DOMAIN" &> /dev/null; then
            log_info "✓ OpenSearch domain exists: $OPENSEARCH_DOMAIN"
            OPENSEARCH_EXISTS=true
        else
            log_warning "OpenSearch domain not found: $OPENSEARCH_DOMAIN"
            OPENSEARCH_EXISTS=false
        fi
    else
        OPENSEARCH_EXISTS=false
    fi
    
    # Check Lambda function
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
            log_info "✓ Lambda function exists: $LAMBDA_FUNCTION_NAME"
            LAMBDA_EXISTS=true
        else
            log_warning "Lambda function not found: $LAMBDA_FUNCTION_NAME"
            LAMBDA_EXISTS=false
        fi
    else
        LAMBDA_EXISTS=false
    fi
    
    # Check Cognito User Pool
    if [[ -n "${USER_POOL_ID:-}" ]]; then
        if aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" &> /dev/null; then
            log_info "✓ Cognito User Pool exists: $USER_POOL_ID"
            COGNITO_EXISTS=true
        else
            log_warning "Cognito User Pool not found: $USER_POOL_ID"
            COGNITO_EXISTS=false
        fi
    else
        COGNITO_EXISTS=false
    fi
    
    log_success "Resource existence check completed"
}

###################################################################################
# AppSync Cleanup Functions
###################################################################################

delete_appsync_api() {
    if [[ "$APPSYNC_EXISTS" != "true" ]]; then
        log_warning "Skipping AppSync cleanup - API not found"
        return 0
    fi
    
    log_info "Deleting AppSync GraphQL API: $API_ID"
    
    # Delete API (this automatically removes all associated resolvers, data sources, etc.)
    aws appsync delete-graphql-api --api-id "$API_ID" > /dev/null
    
    # Wait for deletion to complete
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if ! aws appsync get-graphql-api --api-id "$API_ID" &> /dev/null; then
            log_success "AppSync API deleted successfully"
            return 0
        fi
        
        attempts=$((attempts + 1))
        log_info "Waiting for AppSync API deletion... (attempt $attempts/$max_attempts)"
        sleep 10
    done
    
    log_warning "AppSync API deletion taking longer than expected"
    log_info "The API may still be deleting in the background"
}

###################################################################################
# DynamoDB Cleanup Functions
###################################################################################

delete_dynamodb_tables() {
    if [[ ${#DYNAMODB_TABLES_EXIST[@]} -eq 0 ]]; then
        log_warning "Skipping DynamoDB cleanup - no tables found"
        return 0
    fi
    
    log_info "Deleting DynamoDB tables..."
    
    # Delete all tables in parallel
    for table in "${DYNAMODB_TABLES_EXIST[@]}"; do
        log_info "Deleting table: $table"
        aws dynamodb delete-table --table-name "$table" > /dev/null &
    done
    
    # Wait for all background jobs to complete
    wait
    
    # Wait for tables to be deleted
    for table in "${DYNAMODB_TABLES_EXIST[@]}"; do
        log_info "Waiting for table deletion: $table"
        
        local attempts=0
        local max_attempts=60  # 10 minutes max
        
        while [[ $attempts -lt $max_attempts ]]; do
            if ! aws dynamodb describe-table --table-name "$table" &> /dev/null; then
                log_success "Table deleted: $table"
                break
            fi
            
            attempts=$((attempts + 1))
            if [[ $((attempts % 6)) -eq 0 ]]; then  # Log every minute
                log_info "Still waiting for table deletion: $table (${attempts}0 seconds)"
            fi
            sleep 10
        done
        
        if [[ $attempts -eq $max_attempts ]]; then
            log_warning "Table deletion taking longer than expected: $table"
        fi
    done
    
    log_success "DynamoDB tables cleanup completed"
}

###################################################################################
# OpenSearch Cleanup Functions
###################################################################################

delete_opensearch_domain() {
    if [[ "$OPENSEARCH_EXISTS" != "true" ]]; then
        log_warning "Skipping OpenSearch cleanup - domain not found"
        return 0
    fi
    
    log_info "Deleting OpenSearch domain: $OPENSEARCH_DOMAIN"
    log_warning "OpenSearch domain deletion takes 10-15 minutes..."
    
    # Delete the domain
    aws opensearch delete-domain --domain-name "$OPENSEARCH_DOMAIN" > /dev/null
    
    # Wait for deletion to start
    log_info "Waiting for OpenSearch domain deletion to begin..."
    sleep 30
    
    # Check deletion status periodically
    local attempts=0
    local max_attempts=90  # 90 minutes max (OpenSearch can take a while)
    
    while [[ $attempts -lt $max_attempts ]]; do
        local domain_status
        domain_status=$(aws opensearch describe-domain --domain-name "$OPENSEARCH_DOMAIN" \
            --query 'DomainStatus.Deleted' --output text 2>/dev/null || echo "true")
        
        if [[ "$domain_status" == "true" ]] || ! aws opensearch describe-domain --domain-name "$OPENSEARCH_DOMAIN" &> /dev/null; then
            log_success "OpenSearch domain deleted successfully"
            return 0
        fi
        
        attempts=$((attempts + 1))
        if [[ $((attempts % 5)) -eq 0 ]]; then  # Log every 5 minutes
            log_info "Still waiting for OpenSearch domain deletion... (${attempts} minutes)"
        fi
        sleep 60
    done
    
    log_warning "OpenSearch domain deletion taking longer than expected"
    log_info "The domain may still be deleting in the background"
}

###################################################################################
# Lambda Cleanup Functions
###################################################################################

delete_lambda_function() {
    if [[ "$LAMBDA_EXISTS" != "true" ]]; then
        log_warning "Skipping Lambda cleanup - function not found"
        return 0
    fi
    
    log_info "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
    
    # Delete the Lambda function
    aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" > /dev/null
    
    # Delete Lambda execution role
    delete_lambda_execution_role
    
    log_success "Lambda function deleted successfully"
}

delete_lambda_execution_role() {
    local role_name="LambdaExecutionRole-$(echo "$PROJECT_NAME" | cut -d'-' -f3)"
    
    log_info "Deleting Lambda execution role: $role_name"
    
    # Detach managed policies
    aws iam detach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        2> /dev/null || log_warning "Failed to detach basic execution policy from $role_name"
    
    # Delete inline policies
    aws iam delete-role-policy \
        --role-name "$role_name" \
        --policy-name "LambdaCustomPolicy" \
        2> /dev/null || log_warning "Failed to delete custom policy from $role_name"
    
    # Delete the role
    aws iam delete-role --role-name "$role_name" \
        2> /dev/null || log_warning "Failed to delete role $role_name"
    
    log_success "Lambda execution role cleanup completed"
}

###################################################################################
# Cognito Cleanup Functions
###################################################################################

delete_cognito_user_pool() {
    if [[ "$COGNITO_EXISTS" != "true" ]]; then
        log_warning "Skipping Cognito cleanup - user pool not found"
        return 0
    fi
    
    log_info "Deleting Cognito User Pool: $USER_POOL_ID"
    
    # Delete the user pool (this cascades to delete the client and groups)
    aws cognito-idp delete-user-pool --user-pool-id "$USER_POOL_ID" > /dev/null
    
    log_success "Cognito User Pool deleted successfully"
}

###################################################################################
# IAM Cleanup Functions
###################################################################################

delete_appsync_service_role() {
    local role_name="AppSyncDynamoDBRole-$(echo "$PROJECT_NAME" | cut -d'-' -f3)"
    
    log_info "Deleting AppSync service role: $role_name"
    
    # Delete inline policies first
    aws iam delete-role-policy \
        --role-name "$role_name" \
        --policy-name "DynamoDBAccess" \
        2> /dev/null || log_warning "Failed to delete policy from $role_name"
    
    # Delete the role
    aws iam delete-role --role-name "$role_name" \
        2> /dev/null || log_warning "Failed to delete role $role_name"
    
    log_success "AppSync service role cleanup completed"
}

###################################################################################
# Configuration File Cleanup
###################################################################################

cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    # Backup the config file before deletion
    if [[ -f "$CONFIG_FILE" ]]; then
        local backup_file="${CONFIG_FILE}.deleted.$(date +%s)"
        cp "$CONFIG_FILE" "$backup_file"
        log_info "Configuration backed up to: $backup_file"
        
        # Remove the active config file
        rm -f "$CONFIG_FILE"
        log_success "Configuration file removed"
    fi
    
    # Clean up any temporary files that might exist
    local temp_files=(
        "${SCRIPT_DIR}/../lambda-function.zip"
        "${SCRIPT_DIR}/../*.vtl"
        "${SCRIPT_DIR}/../*-policy.json"
        "${SCRIPT_DIR}/../ecommerce-schema.graphql"
    )
    
    for pattern in "${temp_files[@]}"; do
        # Use glob expansion but don't fail if no files match
        for file in $pattern; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                log_info "Removed temporary file: $(basename "$file")"
            fi
        done 2>/dev/null || true
    done
    
    log_success "Local files cleanup completed"
}

###################################################################################
# Main Cleanup Orchestration
###################################################################################

execute_cleanup() {
    log_info "Starting infrastructure cleanup..."
    
    # Phase 1: Delete AppSync API (removes resolvers, data sources automatically)
    delete_appsync_api
    
    # Phase 2: Delete Lambda function and associated role
    delete_lambda_function
    
    # Phase 3: Delete Cognito User Pool
    delete_cognito_user_pool
    
    # Phase 4: Delete DynamoDB tables (can be done in parallel)
    delete_dynamodb_tables
    
    # Phase 5: Delete OpenSearch domain (longest operation)
    delete_opensearch_domain
    
    # Phase 6: Clean up remaining IAM roles
    delete_appsync_service_role
    
    # Phase 7: Clean up local files
    cleanup_local_files
    
    log_success "Infrastructure cleanup completed successfully!"
}

###################################################################################
# Cost and Resource Summary
###################################################################################

display_cleanup_summary() {
    log_info "=== CLEANUP SUMMARY ==="
    echo ""
    
    local deleted_resources=0
    local failed_resources=0
    
    if [[ "$APPSYNC_EXISTS" == "true" ]]; then
        log_success "✓ AppSync GraphQL API deleted"
        deleted_resources=$((deleted_resources + 1))
    fi
    
    if [[ ${#DYNAMODB_TABLES_EXIST[@]} -gt 0 ]]; then
        log_success "✓ DynamoDB tables deleted (${#DYNAMODB_TABLES_EXIST[@]} tables)"
        deleted_resources=$((deleted_resources + ${#DYNAMODB_TABLES_EXIST[@]}))
    fi
    
    if [[ "$OPENSEARCH_EXISTS" == "true" ]]; then
        log_success "✓ OpenSearch domain deletion initiated"
        deleted_resources=$((deleted_resources + 1))
    fi
    
    if [[ "$LAMBDA_EXISTS" == "true" ]]; then
        log_success "✓ Lambda function and execution role deleted"
        deleted_resources=$((deleted_resources + 1))
    fi
    
    if [[ "$COGNITO_EXISTS" == "true" ]]; then
        log_success "✓ Cognito User Pool deleted"
        deleted_resources=$((deleted_resources + 1))
    fi
    
    log_success "✓ IAM roles and policies cleaned up"
    log_success "✓ Local configuration files cleaned up"
    
    echo ""
    log_info "Total resources processed: $deleted_resources"
    
    if [[ $failed_resources -gt 0 ]]; then
        log_warning "Some resources may require manual cleanup"
        log_info "Check the AWS console for any remaining resources"
    fi
    
    echo ""
    log_info "Cost Impact:"
    log_info "• Stopped all recurring charges from this deployment"
    log_info "• OpenSearch domain deletion may take up to 15 minutes to complete"
    log_info "• DynamoDB tables are deleted immediately (no additional charges)"
    log_info "• Lambda and AppSync charges stop immediately"
    echo ""
    
    log_info "Important Notes:"
    log_info "• This cleanup only removes resources created by this recipe"
    log_info "• Data in deleted tables cannot be recovered"
    log_info "• IAM roles associated with this deployment have been removed"
    echo ""
}

###################################################################################
# Monitoring and Verification
###################################################################################

verify_cleanup_completion() {
    log_info "Verifying cleanup completion..."
    
    local remaining_resources=()
    
    # Check if any major resources still exist
    if [[ -n "${API_ID:-}" ]] && aws appsync get-graphql-api --api-id "$API_ID" &> /dev/null; then
        remaining_resources+=("AppSync API: $API_ID")
    fi
    
    for table in "${DYNAMODB_TABLES_EXIST[@]}"; do
        if aws dynamodb describe-table --table-name "$table" &> /dev/null; then
            remaining_resources+=("DynamoDB Table: $table")
        fi
    done
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        remaining_resources+=("Lambda Function: $LAMBDA_FUNCTION_NAME")
    fi
    
    if [[ -n "${USER_POOL_ID:-}" ]] && aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" &> /dev/null; then
        remaining_resources+=("Cognito User Pool: $USER_POOL_ID")
    fi
    
    if [[ ${#remaining_resources[@]} -eq 0 ]]; then
        log_success "All resources have been successfully deleted"
    else
        log_warning "The following resources are still present:"
        for resource in "${remaining_resources[@]}"; do
            log_warning "  • $resource"
        done
        log_info "These resources may still be in the process of deletion"
    fi
}

###################################################################################
# Main Script Execution
###################################################################################

main() {
    log_info "GraphQL API with AppSync and DynamoDB Cleanup Script"
    log_info "======================================================="
    
    # Handle command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_CLEANUP=true
                shift
                ;;
            --help)
                echo "Usage: $0 [--force] [--help]"
                echo "  --force  Skip confirmation prompts"
                echo "  --help   Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Load configuration and validate
    load_configuration
    
    # Check what resources actually exist
    check_resource_existence
    
    # Get user confirmation unless in force mode
    confirm_destruction
    
    # Execute the cleanup
    execute_cleanup
    
    # Verify cleanup completion
    verify_cleanup_completion
    
    # Display summary
    display_cleanup_summary
    
    log_success "Cleanup completed successfully at $(date)"
    log_info "Total cleanup time: $((SECONDS / 60)) minutes"
    log_info "All GraphQL API infrastructure has been removed!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi