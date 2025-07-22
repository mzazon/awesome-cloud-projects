#!/bin/bash

# Destroy script for Lambda Function Deployment Patterns with Blue-Green and Canary Releases
# This script safely removes all resources created during deployment

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Change to script directory
    cd "$(dirname "$0")"
    
    # Check if .env file exists
    if [ ! -f ".env" ]; then
        error ".env file not found. Either run deploy.sh first or resources may already be cleaned up."
        exit 1
    fi
    
    # Load environment variables from .env file
    set -o allexport
    source .env
    set +o allexport
    
    # Verify required variables are set
    if [ -z "${FUNCTION_NAME:-}" ] || [ -z "${API_ID:-}" ] || [ -z "${ROLE_NAME:-}" ]; then
        error "Required environment variables not found in .env file."
        exit 1
    fi
    
    info "Function Name: $FUNCTION_NAME"
    info "API ID: $API_ID"
    info "Role Name: $ROLE_NAME"
    info "AWS Region: $AWS_REGION"
    
    log "Environment variables loaded ✅"
}

# Confirmation prompt
confirm_destruction() {
    info "This will destroy the following resources:"
    info "  - Lambda Function: $FUNCTION_NAME"
    info "  - API Gateway: $API_ID"
    info "  - IAM Role: $ROLE_NAME"
    info "  - CloudWatch Alarm: ${ALARM_NAME:-${FUNCTION_NAME}-error-rate}"
    info ""
    
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Destruction cancelled."
        exit 0
    fi
}

# Remove API Gateway
remove_api_gateway() {
    log "Removing API Gateway..."
    
    # Check if API Gateway exists
    if aws apigateway get-rest-api --rest-api-id "$API_ID" &> /dev/null; then
        # Delete API Gateway
        aws apigateway delete-rest-api --rest-api-id "$API_ID"
        log "API Gateway deleted ✅"
    else
        warn "API Gateway not found, may already be deleted"
    fi
}

# Remove Lambda function
remove_lambda_function() {
    log "Removing Lambda function and versions..."
    
    # Check if function exists
    if aws lambda get-function --function-name "$FUNCTION_NAME" &> /dev/null; then
        
        # Delete production alias (if exists)
        if aws lambda get-alias --function-name "$FUNCTION_NAME" --name production &> /dev/null; then
            aws lambda delete-alias \
                --function-name "$FUNCTION_NAME" \
                --name production
            info "Production alias deleted"
        fi
        
        # Delete the function (this removes all versions)
        aws lambda delete-function --function-name "$FUNCTION_NAME"
        log "Lambda function and all versions deleted ✅"
        
    else
        warn "Lambda function not found, may already be deleted"
    fi
}

# Remove CloudWatch alarm
remove_cloudwatch_alarm() {
    log "Removing CloudWatch alarm..."
    
    local alarm_name="${ALARM_NAME:-${FUNCTION_NAME}-error-rate}"
    
    # Check if alarm exists
    if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm_name"; then
        # Delete CloudWatch alarm
        aws cloudwatch delete-alarms --alarm-names "$alarm_name"
        log "CloudWatch alarm deleted ✅"
    else
        warn "CloudWatch alarm not found, may already be deleted"
    fi
}

# Remove IAM role
remove_iam_role() {
    log "Removing IAM role..."
    
    # Check if role exists
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        
        # List and detach all attached policies
        local policies
        policies=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text)
        
        if [ -n "$policies" ]; then
            for policy in $policies; do
                aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy"
                info "Detached policy: $policy"
            done
        fi
        
        # Delete IAM role
        aws iam delete-role --role-name "$ROLE_NAME"
        log "IAM role deleted ✅"
        
    else
        warn "IAM role not found, may already be deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files
    rm -f trust-policy.json lambda_function_v*.py function-v*.zip
    
    # Remove .env file
    if [ -f ".env" ]; then
        rm -f .env
        info ".env file removed"
    fi
    
    log "Local files cleaned up ✅"
}

# Verify resources are deleted
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_success=true
    
    # Check Lambda function
    if aws lambda get-function --function-name "$FUNCTION_NAME" &> /dev/null; then
        error "Lambda function still exists"
        cleanup_success=false
    fi
    
    # Check API Gateway
    if aws apigateway get-rest-api --rest-api-id "$API_ID" &> /dev/null; then
        error "API Gateway still exists"
        cleanup_success=false
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        error "IAM role still exists"
        cleanup_success=false
    fi
    
    # Check CloudWatch alarm
    local alarm_name="${ALARM_NAME:-${FUNCTION_NAME}-error-rate}"
    if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm_name"; then
        error "CloudWatch alarm still exists"
        cleanup_success=false
    fi
    
    if [ "$cleanup_success" = true ]; then
        log "Resource cleanup verification passed ✅"
    else
        error "Some resources may not have been deleted properly"
        return 1
    fi
}

# Handle partial cleanup scenarios
handle_partial_cleanup() {
    warn "Attempting to clean up any remaining resources..."
    
    # Try to find and clean up resources by pattern
    local function_pattern="deploy-patterns-demo-"
    local api_pattern="deployment-api-"
    local role_pattern="lambda-deploy-role-"
    
    # Find Lambda functions with our pattern
    local functions
    functions=$(aws lambda list-functions --query "Functions[?starts_with(FunctionName, '$function_pattern')].FunctionName" --output text)
    
    if [ -n "$functions" ]; then
        for func in $functions; do
            warn "Found orphaned Lambda function: $func"
            # Delete production alias if exists
            if aws lambda get-alias --function-name "$func" --name production &> /dev/null; then
                aws lambda delete-alias --function-name "$func" --name production
            fi
            # Delete function
            aws lambda delete-function --function-name "$func"
            info "Cleaned up orphaned function: $func"
        done
    fi
    
    # Find API Gateways with our pattern
    local apis
    apis=$(aws apigateway get-rest-apis --query "items[?starts_with(name, '$api_pattern')].id" --output text)
    
    if [ -n "$apis" ]; then
        for api in $apis; do
            warn "Found orphaned API Gateway: $api"
            aws apigateway delete-rest-api --rest-api-id "$api"
            info "Cleaned up orphaned API Gateway: $api"
        done
    fi
    
    # Find IAM roles with our pattern
    local roles
    roles=$(aws iam list-roles --query "Roles[?starts_with(RoleName, '$role_pattern')].RoleName" --output text)
    
    if [ -n "$roles" ]; then
        for role in $roles; do
            warn "Found orphaned IAM role: $role"
            # Detach policies
            local policies
            policies=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text)
            if [ -n "$policies" ]; then
                for policy in $policies; do
                    aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
                done
            fi
            # Delete role
            aws iam delete-role --role-name "$role"
            info "Cleaned up orphaned IAM role: $role"
        done
    fi
    
    # Find CloudWatch alarms with our pattern
    local alarms
    alarms=$(aws cloudwatch describe-alarms --query "MetricAlarms[?starts_with(AlarmName, '$function_pattern')].AlarmName" --output text)
    
    if [ -n "$alarms" ]; then
        for alarm in $alarms; do
            warn "Found orphaned CloudWatch alarm: $alarm"
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            info "Cleaned up orphaned CloudWatch alarm: $alarm"
        done
    fi
    
    log "Partial cleanup completed ✅"
}

# Main destruction function
main() {
    log "Starting Lambda Function Deployment Patterns cleanup..."
    
    # Check if we should perform partial cleanup
    if [ "${1:-}" = "--force" ]; then
        warn "Force cleanup mode enabled"
        check_prerequisites
        handle_partial_cleanup
        cleanup_local_files
        log "🧹 Force cleanup completed!"
        return 0
    fi
    
    # Normal cleanup process
    check_prerequisites
    
    # Try to load environment, if it fails, attempt partial cleanup
    if ! load_environment; then
        warn "Could not load environment, attempting partial cleanup..."
        handle_partial_cleanup
        cleanup_local_files
        log "🧹 Partial cleanup completed!"
        return 0
    fi
    
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_api_gateway
    remove_lambda_function
    remove_cloudwatch_alarm
    remove_iam_role
    cleanup_local_files
    
    # Verify cleanup
    if verify_cleanup; then
        log "🧹 Cleanup completed successfully!"
        info "All resources have been removed."
    else
        error "Cleanup may not have completed successfully. Please check AWS console."
        exit 1
    fi
}

# Handle script interruption
cleanup_on_exit() {
    error "Script interrupted. Some resources may not have been cleaned up."
    exit 1
}

trap cleanup_on_exit INT TERM

# Show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --force    Force cleanup of resources even without .env file"
    echo "  --help     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0               # Normal cleanup using .env file"
    echo "  $0 --force       # Force cleanup without .env file"
}

# Check for help flag
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    show_help
    exit 0
fi

# Run main function
main "$@"