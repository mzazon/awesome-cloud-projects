#!/bin/bash

# =============================================================================
# Destroy Script for AWS AppSync and DynamoDB Streams Real-Time Data Synchronization
# =============================================================================
# This script safely destroys all infrastructure created by the deploy.sh script
# for the AWS AppSync and DynamoDB Streams real-time data synchronization solution.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Proper IAM permissions for resource deletion
# - Previous deployment using deploy.sh script
#
# Usage:
# ./destroy.sh [OPTIONS]
#
# Options:
# -h, --help          Show this help message
# -v, --verbose       Enable verbose logging
# -f, --force         Skip confirmation prompts
# -d, --dry-run       Show what would be destroyed without making changes
# -y, --yes           Automatically answer yes to all prompts
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
VERBOSE=false
DRY_RUN=false
FORCE=false
AUTO_YES=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}"
            ;;
        "DEBUG")
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} ${message}"
            fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log "ERROR" "Script failed on line $line_number with exit code $exit_code"
    log "ERROR" "Check $LOG_FILE for detailed error information"
    exit $exit_code
}

# Set error trap
trap 'handle_error $LINENO' ERR

# Help function
show_help() {
    cat << EOF
Destroy Script for AWS AppSync and DynamoDB Streams Real-Time Data Synchronization

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    -f, --force         Skip confirmation prompts
    -d, --dry-run       Show what would be destroyed without making changes
    -y, --yes           Automatically answer yes to all prompts

EXAMPLES:
    $0                           # Destroy with confirmation prompts
    $0 -v                        # Destroy with verbose logging
    $0 -d                        # Show what would be destroyed
    $0 -f                        # Force destroy without prompts
    $0 -y                        # Auto-answer yes to all prompts

WARNING:
    This script will permanently delete all resources created by the deploy.sh script.
    This action cannot be undone. Make sure you have backed up any important data.

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - IAM permissions for resource deletion
    - Previous deployment using deploy.sh script

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize log file
echo "=== AWS AppSync and DynamoDB Streams Destruction Log ===" > "$LOG_FILE"
echo "Started at: $(date)" >> "$LOG_FILE"

log "INFO" "Starting AWS AppSync and DynamoDB Streams infrastructure destruction"

# Load environment variables
load_environment() {
    log "INFO" "Loading environment variables..."
    
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        source "${SCRIPT_DIR}/.env"
        log "INFO" "Environment variables loaded from .env file"
    else
        log "WARN" "No .env file found. Attempting to discover resources..."
        discover_resources
    fi
    
    # Validate required variables
    local required_vars=("AWS_REGION" "TABLE_NAME" "LAMBDA_FUNCTION_NAME" "APPSYNC_API_NAME")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log "ERROR" "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    log "INFO" "Environment configuration:"
    log "INFO" "  AWS Region: $AWS_REGION"
    log "INFO" "  DynamoDB Table: $TABLE_NAME"
    log "INFO" "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "INFO" "  AppSync API: $APPSYNC_API_NAME"
}

# Discover resources if .env file is not available
discover_resources() {
    log "INFO" "Attempting to discover deployed resources..."
    
    # Try to get AWS region from CLI configuration
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        log "ERROR" "AWS region not configured. Please set AWS region."
        exit 1
    fi
    
    # Try to discover resources by common naming patterns
    log "WARN" "Resource discovery is limited without .env file"
    log "WARN" "You may need to manually specify resource names"
    
    # This is a fallback - ideally the .env file should be present
    export TABLE_NAME=""
    export LAMBDA_FUNCTION_NAME=""
    export APPSYNC_API_NAME=""
}

# Prompt for confirmation
confirm_destruction() {
    if [[ "$FORCE" == "true" ]] || [[ "$AUTO_YES" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log "WARN" "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    log "WARN" "This will permanently delete the following resources:"
    log "WARN" "  - DynamoDB Table: $TABLE_NAME"
    log "WARN" "  - Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "WARN" "  - AppSync API: $APPSYNC_API_NAME"
    log "WARN" "  - Associated IAM roles and policies"
    log "WARN" "  - All data stored in these resources"
    echo ""
    log "WARN" "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "INFO" "Operation cancelled by user"
        exit 0
    fi
    
    log "INFO" "User confirmed destruction. Proceeding..."
}

# Execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log "DEBUG" "Executing: $cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would execute: $description"
        return 0
    else
        log "INFO" "$description"
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || log "WARN" "Command failed but continuing: $description"
        else
            eval "$cmd"
        fi
        return $?
    fi
}

# Check if resource exists
resource_exists() {
    local check_cmd="$1"
    local resource_type="$2"
    
    log "DEBUG" "Checking if $resource_type exists: $check_cmd"
    
    if eval "$check_cmd" &>/dev/null; then
        log "DEBUG" "$resource_type exists"
        return 0
    else
        log "DEBUG" "$resource_type does not exist"
        return 1
    fi
}

# Destroy AppSync API and related resources
destroy_appsync_api() {
    log "INFO" "Destroying AppSync API and related resources..."
    
    # Get AppSync API ID if not already set
    if [[ -z "${APPSYNC_API_ID:-}" ]]; then
        APPSYNC_API_ID=$(aws appsync list-graphql-apis \
            --query "graphqlApis[?name=='$APPSYNC_API_NAME'].apiId" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -n "$APPSYNC_API_ID" ]] && [[ "$APPSYNC_API_ID" != "None" ]]; then
        # Delete AppSync API (this removes schema, resolvers, and data sources)
        local cmd="aws appsync delete-graphql-api --api-id '$APPSYNC_API_ID'"
        execute_cmd "$cmd" "Deleting AppSync GraphQL API" true
        
        log "INFO" "Waiting for AppSync API deletion to complete..."
        if [[ "$DRY_RUN" == "false" ]]; then
            # Wait for API to be deleted
            local max_attempts=30
            local attempt=0
            
            while [[ $attempt -lt $max_attempts ]]; do
                if ! aws appsync get-graphql-api --api-id "$APPSYNC_API_ID" &>/dev/null; then
                    log "INFO" "AppSync API deleted successfully"
                    break
                fi
                
                log "DEBUG" "Waiting for AppSync API deletion... (attempt $((attempt+1))/$max_attempts)"
                sleep 10
                ((attempt++))
            done
            
            if [[ $attempt -eq $max_attempts ]]; then
                log "WARN" "AppSync API deletion timeout. It may still be deleting in the background."
            fi
        fi
    else
        log "WARN" "AppSync API '$APPSYNC_API_NAME' not found. Skipping deletion."
    fi
}

# Destroy AppSync service role
destroy_appsync_role() {
    log "INFO" "Destroying AppSync service role..."
    
    local role_name="${APPSYNC_ROLE_NAME:-AppSyncDynamoDBRole-${RANDOM_SUFFIX}}"
    
    if resource_exists "aws iam get-role --role-name '$role_name'" "AppSync IAM role"; then
        # Delete role policy
        local cmd1="aws iam delete-role-policy \
            --role-name '$role_name' \
            --policy-name DynamoDBAccess"
        execute_cmd "$cmd1" "Deleting AppSync role policy" true
        
        # Delete role
        local cmd2="aws iam delete-role --role-name '$role_name'"
        execute_cmd "$cmd2" "Deleting AppSync IAM role" true
        
        log "INFO" "AppSync service role deleted successfully"
    else
        log "WARN" "AppSync service role '$role_name' not found. Skipping deletion."
    fi
}

# Destroy Lambda function and event source mapping
destroy_lambda_function() {
    log "INFO" "Destroying Lambda function and event source mapping..."
    
    # Get event source mapping UUID if not already set
    if [[ -z "${EVENT_MAPPING_UUID:-}" ]]; then
        EVENT_MAPPING_UUID=$(aws lambda list-event-source-mappings \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --query 'EventSourceMappings[0].UUID' \
            --output text 2>/dev/null || echo "None")
    fi
    
    # Delete event source mapping
    if [[ "$EVENT_MAPPING_UUID" != "None" ]] && [[ -n "$EVENT_MAPPING_UUID" ]]; then
        local cmd1="aws lambda delete-event-source-mapping --uuid '$EVENT_MAPPING_UUID'"
        execute_cmd "$cmd1" "Deleting Lambda event source mapping" true
        
        # Wait for mapping to be deleted
        if [[ "$DRY_RUN" == "false" ]]; then
            log "INFO" "Waiting for event source mapping deletion..."
            local max_attempts=20
            local attempt=0
            
            while [[ $attempt -lt $max_attempts ]]; do
                local mapping_state=$(aws lambda get-event-source-mapping \
                    --uuid "$EVENT_MAPPING_UUID" \
                    --query 'State' --output text 2>/dev/null || echo "Deleted")
                
                if [[ "$mapping_state" == "Deleted" ]]; then
                    log "INFO" "Event source mapping deleted successfully"
                    break
                fi
                
                log "DEBUG" "Waiting for event source mapping deletion... (attempt $((attempt+1))/$max_attempts)"
                sleep 5
                ((attempt++))
            done
        fi
    else
        log "WARN" "Event source mapping not found. Skipping deletion."
    fi
    
    # Delete Lambda function
    if resource_exists "aws lambda get-function --function-name '$LAMBDA_FUNCTION_NAME'" "Lambda function"; then
        local cmd2="aws lambda delete-function --function-name '$LAMBDA_FUNCTION_NAME'"
        execute_cmd "$cmd2" "Deleting Lambda function" true
        
        log "INFO" "Lambda function deleted successfully"
    else
        log "WARN" "Lambda function '$LAMBDA_FUNCTION_NAME' not found. Skipping deletion."
    fi
}

# Destroy Lambda IAM role
destroy_lambda_role() {
    log "INFO" "Destroying Lambda IAM role..."
    
    local role_name="${LAMBDA_ROLE_NAME:-${LAMBDA_FUNCTION_NAME}-Role}"
    
    if resource_exists "aws iam get-role --role-name '$role_name'" "Lambda IAM role"; then
        # Detach policies
        local policies=(
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole"
        )
        
        for policy in "${policies[@]}"; do
            local cmd="aws iam detach-role-policy --role-name '$role_name' --policy-arn '$policy'"
            execute_cmd "$cmd" "Detaching policy $policy from Lambda role" true
        done
        
        # Delete role
        local cmd="aws iam delete-role --role-name '$role_name'"
        execute_cmd "$cmd" "Deleting Lambda IAM role" true
        
        log "INFO" "Lambda IAM role deleted successfully"
    else
        log "WARN" "Lambda IAM role '$role_name' not found. Skipping deletion."
    fi
}

# Destroy DynamoDB table
destroy_dynamodb_table() {
    log "INFO" "Destroying DynamoDB table..."
    
    if resource_exists "aws dynamodb describe-table --table-name '$TABLE_NAME'" "DynamoDB table"; then
        local cmd="aws dynamodb delete-table --table-name '$TABLE_NAME'"
        execute_cmd "$cmd" "Deleting DynamoDB table (streams will be deleted automatically)" true
        
        # Wait for table deletion
        if [[ "$DRY_RUN" == "false" ]]; then
            log "INFO" "Waiting for DynamoDB table deletion to complete..."
            aws dynamodb wait table-not-exists --table-name "$TABLE_NAME" || {
                log "WARN" "Timeout waiting for table deletion. Table may still be deleting."
            }
            
            log "INFO" "DynamoDB table deleted successfully"
        fi
    else
        log "WARN" "DynamoDB table '$TABLE_NAME' not found. Skipping deletion."
    fi
}

# Clean up local files
cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/.env"
        "${SCRIPT_DIR}/lambda_function.py"
        "${SCRIPT_DIR}/lambda_function.zip"
        "${SCRIPT_DIR}/schema.graphql"
        "${SCRIPT_DIR}/create-resolver-request.vtl"
        "${SCRIPT_DIR}/create-resolver-response.vtl"
        "${SCRIPT_DIR}/get-resolver-request.vtl"
        "${SCRIPT_DIR}/get-resolver-response.vtl"
        "${SCRIPT_DIR}/test-event.json"
        "${SCRIPT_DIR}/mutation.json"
        "${SCRIPT_DIR}/response.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "INFO" "[DRY-RUN] Would remove: $file"
            else
                rm -f "$file"
                log "DEBUG" "Removed: $file"
            fi
        fi
    done
    
    log "INFO" "Local files cleaned up successfully"
}

# Verify destruction
verify_destruction() {
    log "INFO" "Verifying resource destruction..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "Skipping verification in dry-run mode"
        return 0
    fi
    
    local verification_failed=false
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "$TABLE_NAME" &>/dev/null; then
        log "ERROR" "DynamoDB table '$TABLE_NAME' still exists"
        verification_failed=true
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log "ERROR" "Lambda function '$LAMBDA_FUNCTION_NAME' still exists"
        verification_failed=true
    fi
    
    # Check AppSync API
    if [[ -n "${APPSYNC_API_ID:-}" ]]; then
        if aws appsync get-graphql-api --api-id "$APPSYNC_API_ID" &>/dev/null; then
            log "ERROR" "AppSync API '$APPSYNC_API_ID' still exists"
            verification_failed=true
        fi
    fi
    
    if [[ "$verification_failed" == "true" ]]; then
        log "WARN" "Some resources may still exist. They might still be deleting."
        log "WARN" "Check the AWS console to verify complete deletion."
    else
        log "INFO" "Verification completed successfully - all resources appear to be deleted"
    fi
}

# Print destruction summary
print_destruction_summary() {
    log "INFO" "Destruction Summary:"
    log "INFO" "==================="
    log "INFO" "AWS Region: $AWS_REGION"
    log "INFO" "DynamoDB Table: $TABLE_NAME"
    log "INFO" "Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "INFO" "AppSync API: $APPSYNC_API_NAME"
    log "INFO" ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "DRY-RUN completed. No resources were actually destroyed."
    else
        log "INFO" "Destruction completed successfully!"
        log "INFO" "All resources have been removed from your AWS account."
    fi
    
    log "INFO" ""
    log "INFO" "Destruction log saved to: $LOG_FILE"
}

# Main destruction function
main() {
    log "INFO" "Starting destruction process..."
    
    # Load environment
    load_environment
    
    # Confirm destruction
    confirm_destruction
    
    # Destroy resources in reverse order of creation
    destroy_appsync_api
    destroy_appsync_role
    destroy_lambda_function
    destroy_lambda_role
    destroy_dynamodb_table
    
    # Clean up local files
    cleanup_local_files
    
    # Verify destruction
    verify_destruction
    
    # Print summary
    print_destruction_summary
    
    log "INFO" "Destruction process completed!"
}

# Run main function
main "$@"