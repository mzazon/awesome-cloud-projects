#!/bin/bash

#########################################
# Destroy Simple Timezone Converter
# Infrastructure
#
# This script safely removes all AWS
# resources created by the deploy.sh
# script with confirmation prompts and
# proper error handling.
#########################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS credentials
validate_aws_credentials() {
    log "Validating AWS credentials..."
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    success "AWS credentials validated"
}

# Function to load deployment variables
load_deployment_vars() {
    log "Loading deployment variables..."
    
    if [ ! -f .deployment-vars ]; then
        error "Deployment variables file not found (.deployment-vars)"
        error "This file is created by deploy.sh and contains resource identifiers."
        error "If you deployed manually, please set the following environment variables:"
        error "  FUNCTION_NAME, ROLE_NAME, API_NAME, AWS_REGION, AWS_ACCOUNT_ID"
        exit 1
    fi
    
    # Source the deployment variables
    source .deployment-vars
    
    # Validate required variables
    if [ -z "${FUNCTION_NAME:-}" ] || [ -z "${ROLE_NAME:-}" ] || [ -z "${API_NAME:-}" ]; then
        error "Required variables not found in .deployment-vars"
        error "Required: FUNCTION_NAME, ROLE_NAME, API_NAME"
        exit 1
    fi
    
    success "Deployment variables loaded:"
    log "  Function: ${FUNCTION_NAME}"
    log "  Role: ${ROLE_NAME}"
    log "  API: ${API_NAME}"
    log "  Region: ${AWS_REGION:-}"
}

# Function to confirm destruction
confirm_destruction() {
    log "The following resources will be PERMANENTLY DELETED:"
    echo ""
    echo "🗑️  Lambda Function: ${FUNCTION_NAME}"
    echo "🗑️  IAM Role: ${ROLE_NAME}"
    echo "🗑️  API Gateway: ${API_NAME}"
    if [ -n "${API_ID:-}" ]; then
        echo "🗑️  API Endpoint: https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod/convert"
    fi
    echo ""
    
    # Skip confirmation if FORCE_DESTROY is set
    if [ "${FORCE_DESTROY:-}" = "true" ]; then
        warn "FORCE_DESTROY is set, skipping confirmation"
        return 0
    fi
    
    # Prompt for confirmation
    echo -n "Are you sure you want to destroy these resources? (yes/no): "
    read -r CONFIRMATION
    
    case "$CONFIRMATION" in
        yes|YES|y|Y)
            log "Proceeding with resource destruction..."
            ;;
        *)
            log "Destruction cancelled by user"
            exit 0
            ;;
    esac
}

# Function to remove API Gateway
remove_api_gateway() {
    log "Removing API Gateway..."
    
    # Try to get API ID if not already set
    if [ -z "${API_ID:-}" ]; then
        API_ID=$(aws apigateway get-rest-apis \
            --query "items[?name=='${API_NAME}'].id" --output text 2>/dev/null || echo "")
    fi
    
    if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
        # Delete the REST API (removes all resources, methods, deployments)
        if aws apigateway delete-rest-api --rest-api-id "$API_ID" 2>/dev/null; then
            success "API Gateway deleted: $API_ID"
        else
            warn "Failed to delete API Gateway: $API_ID (may not exist)"
        fi
    else
        warn "API Gateway '$API_NAME' not found, skipping deletion"
    fi
}

# Function to remove Lambda function
remove_lambda_function() {
    log "Removing Lambda function..."
    
    # Check if function exists before attempting deletion
    if aws lambda get-function --function-name "${FUNCTION_NAME}" >/dev/null 2>&1; then
        # Delete Lambda function
        if aws lambda delete-function --function-name "${FUNCTION_NAME}" 2>/dev/null; then
            success "Lambda function deleted: ${FUNCTION_NAME}"
        else
            error "Failed to delete Lambda function: ${FUNCTION_NAME}"
            return 1
        fi
    else
        warn "Lambda function '${FUNCTION_NAME}' not found, skipping deletion"
    fi
}

# Function to remove IAM role
remove_iam_role() {
    log "Removing IAM role..."
    
    # Check if role exists
    if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
        # Detach all attached policies first
        log "Detaching policies from role..."
        
        # Detach managed policy
        if aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null; then
            log "Detached AWSLambdaBasicExecutionRole policy"
        else
            warn "Failed to detach AWSLambdaBasicExecutionRole policy (may not be attached)"
        fi
        
        # List and detach any other managed policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "${ROLE_NAME}" \
            --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        
        if [ -n "$ATTACHED_POLICIES" ]; then
            for policy_arn in $ATTACHED_POLICIES; do
                if [ "$policy_arn" != "None" ]; then
                    aws iam detach-role-policy \
                        --role-name "${ROLE_NAME}" \
                        --policy-arn "$policy_arn" 2>/dev/null || true
                    log "Detached policy: $policy_arn"
                fi
            done
        fi
        
        # List and delete any inline policies
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "${ROLE_NAME}" \
            --query 'PolicyNames' --output text 2>/dev/null || echo "")
        
        if [ -n "$INLINE_POLICIES" ] && [ "$INLINE_POLICIES" != "None" ]; then
            for policy_name in $INLINE_POLICIES; do
                aws iam delete-role-policy \
                    --role-name "${ROLE_NAME}" \
                    --policy-name "$policy_name" 2>/dev/null || true
                log "Deleted inline policy: $policy_name"
            done
        fi
        
        # Wait a moment for policy detachment to propagate
        sleep 2
        
        # Delete the IAM role
        if aws iam delete-role --role-name "${ROLE_NAME}" 2>/dev/null; then
            success "IAM role deleted: ${ROLE_NAME}"
        else
            error "Failed to delete IAM role: ${ROLE_NAME}"
            error "This might be due to remaining attached policies or dependencies"
            return 1
        fi
    else
        warn "IAM role '${ROLE_NAME}' not found, skipping deletion"
    fi
}

# Function to clean up local files  
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment variables file
    if [ -f .deployment-vars ]; then
        rm -f .deployment-vars
        success "Removed .deployment-vars file"
    fi
    
    # Remove any remaining temporary files
    local temp_files=(
        "trust-policy.json"
        "lambda_function.py" 
        "lambda-deployment.zip"
        "response.json"
        "api_response.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed temporary file: $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local all_deleted=true
    
    # Check Lambda function
    if aws lambda get-function --function-name "${FUNCTION_NAME}" >/dev/null 2>&1; then
        error "Lambda function still exists: ${FUNCTION_NAME}"
        all_deleted=false
    else
        success "✅ Lambda function deleted"
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
        error "IAM role still exists: ${ROLE_NAME}"
        all_deleted=false
    else
        success "✅ IAM role deleted"
    fi
    
    # Check API Gateway
    if [ -n "${API_ID:-}" ]; then
        if aws apigateway get-rest-api --rest-api-id "${API_ID}" >/dev/null 2>&1; then
            error "API Gateway still exists: ${API_ID}"
            all_deleted=false
        else
            success "✅ API Gateway deleted"
        fi
    fi
    
    if [ "$all_deleted" = true ]; then
        success "All resources successfully deleted"
    else
        error "Some resources may still exist. Please check manually."
        return 1
    fi
}

# Function to display destruction summary
display_summary() {
    log "Destruction Summary:"
    echo ""
    echo "🗑️  All Timezone Converter resources have been destroyed!"
    echo ""
    echo "📋 Deleted Resources:"
    echo "   • Lambda Function: ${FUNCTION_NAME}"
    echo "   • IAM Role: ${ROLE_NAME}"  
    echo "   • API Gateway: ${API_NAME}"
    if [ -n "${API_ID:-}" ]; then
        echo "   • API Endpoint: https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod/convert"
    fi
    echo ""
    echo "💰 Cost Impact: All pay-per-use charges have stopped"
    echo "📊 Monitoring: CloudWatch logs may remain (minimal cost)"
    echo ""
    success "Infrastructure destruction completed successfully!"
}

# Function to handle partial failures
handle_partial_failure() {
    error "Some resources could not be deleted automatically."
    echo ""
    echo "Manual cleanup may be required for:"
    echo "🔍 Check the AWS Console for any remaining resources:"
    echo "   • Lambda: https://console.aws.amazon.com/lambda/"
    echo "   • IAM: https://console.aws.amazon.com/iam/"
    echo "   • API Gateway: https://console.aws.amazon.com/apigateway/"
    echo ""
    echo "Common reasons for deletion failures:"
    echo "   • Resource dependencies still exist"
    echo "   • Insufficient IAM permissions"
    echo "   • Resources in use by other services"
    echo ""
}

# Main destruction function
main() {
    log "Starting destruction of Simple Timezone Converter infrastructure..."
    
    local failed_operations=0
    
    # Run all destruction steps
    validate_aws_credentials
    load_deployment_vars
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_api_gateway || ((failed_operations++))
    remove_lambda_function || ((failed_operations++))
    remove_iam_role || ((failed_operations++))
    
    # Clean up local files regardless of AWS resource deletion status
    cleanup_local_files
    
    # Verify deletion and provide summary
    if [ $failed_operations -eq 0 ]; then
        verify_deletion
        display_summary
        success "Destruction completed successfully!"
    else
        warn "Some operations failed during resource deletion"
        handle_partial_failure
        exit 1
    fi
}

# Show help if requested
show_help() {
    echo "Simple Timezone Converter Destruction Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -f, --force    Skip confirmation prompt (use with caution)"
    echo ""
    echo "Environment Variables:"
    echo "  FORCE_DESTROY=true   Skip confirmation prompt"
    echo ""
    echo "Prerequisites:"
    echo "  • AWS CLI installed and configured"
    echo "  • .deployment-vars file from deploy.sh"
    echo "  • Appropriate AWS permissions"
    echo ""
    echo "Examples:"
    echo "  $0                   # Interactive destruction with confirmation"
    echo "  $0 --force          # Skip confirmation prompt"
    echo "  FORCE_DESTROY=true $0  # Skip confirmation via environment variable"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            export FORCE_DESTROY=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Handle script interruption
trap 'error "Destruction interrupted. Some resources may still exist."; exit 1' INT TERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi