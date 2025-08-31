#!/bin/bash

# Cleanup script for Persistent Customer Support Agent with Bedrock AgentCore Memory
# This script safely removes all infrastructure components created by the deployment script
# Resources are deleted in reverse order of creation to handle dependencies properly

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"
FORCE_DELETE=false
DRY_RUN=false
CONFIRM_DELETE=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            CONFIRM_DELETE=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes|-y)
            CONFIRM_DELETE=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force      Force deletion without confirmation prompts"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --yes, -y    Skip confirmation prompts (non-destructive)"
            echo "  --help, -h   Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to load deployment configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Deployment configuration file not found: $CONFIG_FILE"
        log_info "This script requires the configuration file created during deployment."
        log_info "If you know the resource names, you can create the file manually with:"
        log_info "MEMORY_NAME=your-memory-name"
        log_info "LAMBDA_FUNCTION_NAME=your-function-name"
        log_info "DDB_TABLE_NAME=your-table-name"
        log_info "API_NAME=your-api-name"
        log_info "IAM_ROLE_NAME=your-role-name"
        log_info "AWS_REGION=your-region"
        log_info "AWS_ACCOUNT_ID=your-account-id"
        exit 1
    fi
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    # Validate required variables
    if [ -z "${MEMORY_NAME:-}" ] || [ -z "${LAMBDA_FUNCTION_NAME:-}" ] || \
       [ -z "${DDB_TABLE_NAME:-}" ] || [ -z "${API_NAME:-}" ] || \
       [ -z "${IAM_ROLE_NAME:-}" ]; then
        log_error "Required configuration variables are missing from $CONFIG_FILE"
        exit 1
    fi
    
    log_info "Loaded configuration for cleanup"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Verify we're in the correct account and region
    CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    CURRENT_REGION=$(aws configure get region)
    
    if [ "${AWS_ACCOUNT_ID:-}" != "${CURRENT_ACCOUNT}" ]; then
        log_warning "Current AWS account (${CURRENT_ACCOUNT}) differs from deployment account (${AWS_ACCOUNT_ID:-unknown})"
    fi
    
    if [ "${AWS_REGION:-}" != "${CURRENT_REGION}" ]; then
        log_warning "Current AWS region (${CURRENT_REGION}) differs from deployment region (${AWS_REGION:-unknown})"
    fi
    
    log_success "Prerequisites check completed"
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$CONFIRM_DELETE" = false ]; then
        return 0
    fi
    
    echo "=================================================="
    echo "DESTRUCTIVE OPERATION WARNING"
    echo "=================================================="
    echo "This will permanently delete the following resources:"
    echo "  - AgentCore Memory: ${MEMORY_NAME}"
    echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  - DynamoDB Table: ${DDB_TABLE_NAME} (and all data)"
    echo "  - API Gateway: ${API_NAME}"
    echo "  - IAM Role: ${IAM_ROLE_NAME}"
    echo ""
    echo "This action cannot be undone. All customer data and conversation"
    echo "history stored in the AgentCore Memory and DynamoDB will be lost."
    echo ""
    
    if [ "$FORCE_DELETE" = true ]; then
        log_warning "Force delete mode enabled - proceeding without confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    if [ "$confirmation" != "DELETE" ]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_info "Deletion confirmed - proceeding with cleanup"
}

# Function to check if resource exists and get details
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "$resource_type" in
        "lambda")
            aws lambda get-function --function-name "$resource_name" &> /dev/null
            ;;
        "dynamodb")
            aws dynamodb describe-table --table-name "$resource_name" &> /dev/null
            ;;
        "apigateway")
            # For API Gateway, we need to find by name since we might not have the ID
            aws apigateway get-rest-apis --query "items[?name=='$resource_name'].id" --output text | grep -q .
            ;;
        "iam")
            aws iam get-role --role-name "$resource_name" &> /dev/null
            ;;
        "memory")
            aws bedrock-agentcore-control get-memory --name "$resource_name" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to delete API Gateway
delete_api_gateway() {
    log_info "Deleting API Gateway: ${API_NAME}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete API Gateway: ${API_NAME}"
        return 0
    fi
    
    # Get API ID by name if not in config
    if [ -z "${API_ID:-}" ]; then
        API_ID=$(aws apigateway get-rest-apis \
            --query "items[?name=='${API_NAME}'].id" --output text)
    fi
    
    if [ -z "$API_ID" ] || [ "$API_ID" = "None" ]; then
        log_warning "API Gateway ${API_NAME} not found or already deleted"
        return 0
    fi
    
    # Delete API Gateway
    aws apigateway delete-rest-api --rest-api-id "$API_ID"
    
    log_success "API Gateway deleted: ${API_NAME}"
}

# Function to delete Lambda function
delete_lambda_function() {
    log_info "Deleting Lambda function: ${LAMBDA_FUNCTION_NAME}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete Lambda function: ${LAMBDA_FUNCTION_NAME}"
        return 0
    fi
    
    if ! resource_exists "lambda" "${LAMBDA_FUNCTION_NAME}"; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} not found or already deleted"
        return 0
    fi
    
    # Delete Lambda function
    aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}"
    
    log_success "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
}

# Function to delete IAM role and policies
delete_iam_role() {
    log_info "Deleting IAM role: ${IAM_ROLE_NAME}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete IAM role and policies: ${IAM_ROLE_NAME}"
        return 0
    fi
    
    if ! resource_exists "iam" "${IAM_ROLE_NAME}"; then
        log_warning "IAM role ${IAM_ROLE_NAME} not found or already deleted"
        return 0
    fi
    
    # Detach managed policies
    aws iam detach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        2>/dev/null || log_warning "Failed to detach AWSLambdaBasicExecutionRole (may not be attached)"
    
    # Delete inline policy
    aws iam delete-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-name SupportAgentPolicy \
        2>/dev/null || log_warning "Failed to delete SupportAgentPolicy (may not exist)"
    
    # Delete IAM role
    aws iam delete-role --role-name "${IAM_ROLE_NAME}"
    
    log_success "IAM role and policies deleted: ${IAM_ROLE_NAME}"
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    log_info "Deleting DynamoDB table: ${DDB_TABLE_NAME}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete DynamoDB table: ${DDB_TABLE_NAME}"
        return 0
    fi
    
    if ! resource_exists "dynamodb" "${DDB_TABLE_NAME}"; then
        log_warning "DynamoDB table ${DDB_TABLE_NAME} not found or already deleted"
        return 0
    fi
    
    # Delete DynamoDB table
    aws dynamodb delete-table --table-name "${DDB_TABLE_NAME}"
    
    # Wait for table deletion to complete
    log_info "Waiting for DynamoDB table deletion to complete..."
    aws dynamodb wait table-not-exists --table-name "${DDB_TABLE_NAME}" || {
        log_warning "Timeout waiting for table deletion, but deletion was initiated"
    }
    
    log_success "DynamoDB table deleted: ${DDB_TABLE_NAME}"
}

# Function to delete AgentCore Memory
delete_agentcore_memory() {
    log_info "Deleting AgentCore Memory: ${MEMORY_NAME}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete AgentCore Memory: ${MEMORY_NAME}"
        return 0
    fi
    
    if ! resource_exists "memory" "${MEMORY_NAME}"; then
        log_warning "AgentCore Memory ${MEMORY_NAME} not found or already deleted"
        return 0
    fi
    
    # Delete AgentCore Memory
    aws bedrock-agentcore-control delete-memory --name "${MEMORY_NAME}"
    
    log_success "AgentCore Memory deleted: ${MEMORY_NAME}"
    log_warning "All conversation history and extracted insights have been permanently removed"
}

# Function to display deletion summary
display_deletion_summary() {
    local deleted_resources=()
    local failed_resources=()
    
    # Check what was actually deleted/exists
    if [ "$DRY_RUN" = false ]; then
        if resource_exists "memory" "${MEMORY_NAME}"; then
            failed_resources+=("AgentCore Memory: ${MEMORY_NAME}")
        else
            deleted_resources+=("AgentCore Memory: ${MEMORY_NAME}")
        fi
        
        if resource_exists "lambda" "${LAMBDA_FUNCTION_NAME}"; then
            failed_resources+=("Lambda Function: ${LAMBDA_FUNCTION_NAME}")
        else
            deleted_resources+=("Lambda Function: ${LAMBDA_FUNCTION_NAME}")
        fi
        
        if resource_exists "dynamodb" "${DDB_TABLE_NAME}"; then
            failed_resources+=("DynamoDB Table: ${DDB_TABLE_NAME}")
        else
            deleted_resources+=("DynamoDB Table: ${DDB_TABLE_NAME}")
        fi
        
        if resource_exists "iam" "${IAM_ROLE_NAME}"; then
            failed_resources+=("IAM Role: ${IAM_ROLE_NAME}")
        else
            deleted_resources+=("IAM Role: ${IAM_ROLE_NAME}")
        fi
    fi
    
    echo "=================================================="
    echo "CLEANUP SUMMARY"
    echo "=================================================="
    
    if [ "$DRY_RUN" = true ]; then
        echo "DRY RUN - No resources were actually deleted"
        echo ""
        echo "Would have deleted:"
        echo "  - AgentCore Memory: ${MEMORY_NAME}"
        echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        echo "  - DynamoDB Table: ${DDB_TABLE_NAME}"
        echo "  - API Gateway: ${API_NAME}"
        echo "  - IAM Role: ${IAM_ROLE_NAME}"
    else
        if [ ${#deleted_resources[@]} -gt 0 ]; then
            echo "Successfully deleted:"
            for resource in "${deleted_resources[@]}"; do
                echo "  ✓ $resource"
            done
            echo ""
        fi
        
        if [ ${#failed_resources[@]} -gt 0 ]; then
            echo "Failed to delete or still exist:"
            for resource in "${failed_resources[@]}"; do
                echo "  ✗ $resource"
            done
            echo ""
            log_warning "Some resources may still exist. Please check manually."
        fi
        
        if [ ${#failed_resources[@]} -eq 0 ]; then
            log_success "All resources successfully deleted!"
        fi
    fi
    
    echo "=================================================="
}

# Function to clean up configuration file
cleanup_config_file() {
    if [ "$DRY_RUN" = false ] && [ -f "$CONFIG_FILE" ]; then
        log_info "Removing deployment configuration file"
        rm -f "$CONFIG_FILE"
        log_success "Configuration file removed: $CONFIG_FILE"
    fi
}

# Function to handle errors during deletion
handle_deletion_error() {
    local resource_type="$1"
    local resource_name="$2"
    local error_message="$3"
    
    log_error "Failed to delete $resource_type: $resource_name"
    log_error "Error: $error_message"
    
    if [ "$FORCE_DELETE" = true ]; then
        log_warning "Continuing deletion due to --force flag"
        return 0
    else
        log_info "Use --force flag to continue deletion despite errors"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting cleanup of Persistent Customer Support Agent resources"
    
    # Load configuration and check prerequisites
    load_config
    check_prerequisites
    
    # Confirm deletion with user
    confirm_deletion
    
    # Delete resources in reverse order of creation
    # This ensures proper dependency handling
    
    # 1. Delete API Gateway first (removes external access)
    delete_api_gateway || handle_deletion_error "API Gateway" "${API_NAME}" "See logs above"
    
    # 2. Delete Lambda function (removes compute layer)
    delete_lambda_function || handle_deletion_error "Lambda Function" "${LAMBDA_FUNCTION_NAME}" "See logs above"
    
    # 3. Delete IAM role (removes permissions)
    delete_iam_role || handle_deletion_error "IAM Role" "${IAM_ROLE_NAME}" "See logs above"
    
    # 4. Delete DynamoDB table (removes structured data)
    delete_dynamodb_table || handle_deletion_error "DynamoDB Table" "${DDB_TABLE_NAME}" "See logs above"
    
    # 5. Delete AgentCore Memory last (removes conversation history)
    delete_agentcore_memory || handle_deletion_error "AgentCore Memory" "${MEMORY_NAME}" "See logs above"
    
    # Display summary
    display_deletion_summary
    
    # Clean up configuration file
    cleanup_config_file
    
    if [ "$DRY_RUN" = false ]; then
        log_success "Cleanup completed!"
        log_info "All resources have been removed from your AWS account"
        log_warning "This action cannot be undone - all data has been permanently deleted"
    else
        log_info "Dry run completed - no resources were actually deleted"
        log_info "Run without --dry-run to perform actual deletion"
    fi
}

# Error handling
set +e  # Don't exit on errors in main execution
main "$@"
exit_code=$?

# Final status
if [ $exit_code -eq 0 ]; then
    if [ "$DRY_RUN" = false ]; then
        log_success "All cleanup operations completed successfully"
    else
        log_info "Dry run completed successfully"
    fi
else
    log_error "Some cleanup operations failed - please check the logs above"
    log_info "You may need to manually delete remaining resources in the AWS console"
fi

exit $exit_code