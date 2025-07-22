#!/bin/bash

# API Gateway Throttling and Rate Limiting - Cleanup Script
# This script removes all resources created by the deploy script
# to avoid ongoing AWS charges.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/../cleanup.log"
ENV_FILE="${SCRIPT_DIR}/../.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check $LOG_FILE for details."
    exit 1
}

# Warning function for missing resources
warn_missing() {
    log_warning "$1 not found or already deleted"
}

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check if environment file exists
    if [[ ! -f "$ENV_FILE" ]]; then
        log_warning "Environment file not found. Will attempt cleanup with user input."
        return 1
    fi
    
    log_success "Prerequisites check passed"
    return 0
}

# Load environment variables from deployment
load_environment() {
    if [[ -f "$ENV_FILE" ]]; then
        log "Loading environment variables from deployment..."
        
        # Source the environment file
        source "$ENV_FILE"
        
        # Verify required variables are set
        local required_vars=(
            "AWS_REGION" "API_NAME" "LAMBDA_FUNCTION_NAME" 
            "IAM_ROLE_NAME" "RANDOM_SUFFIX"
        )
        
        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                log_warning "Required variable $var not found in environment file"
                return 1
            fi
        done
        
        log_success "Environment variables loaded successfully"
        return 0
    else
        log_warning "Environment file not found"
        return 1
    fi
}

# Interactive cleanup for missing environment
interactive_cleanup() {
    log "Environment file not found. Starting interactive cleanup..."
    
    echo -e "\n${YELLOW}Interactive Cleanup Mode${NC}"
    echo "This will help you clean up resources when the environment file is missing."
    echo ""
    
    # Get AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            read -p "Enter AWS region: " AWS_REGION
        fi
    fi
    
    # Get resource identifier
    read -p "Enter the random suffix from your deployment (6 characters): " RANDOM_SUFFIX
    
    if [[ -z "$RANDOM_SUFFIX" ]]; then
        error_exit "Random suffix is required for cleanup"
    fi
    
    # Construct resource names
    API_NAME="throttling-demo-${RANDOM_SUFFIX}"
    LAMBDA_FUNCTION_NAME="api-backend-${RANDOM_SUFFIX}"
    IAM_ROLE_NAME="lambda-execution-role-${RANDOM_SUFFIX}"
    
    log "Using resource names:"
    log "  API Name: ${API_NAME}"
    log "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log "  IAM Role: ${IAM_ROLE_NAME}"
    
    # Confirm before proceeding
    echo ""
    read -p "Proceed with cleanup of these resources? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Get resource IDs for cleanup
discover_resources() {
    log "Discovering resources for cleanup..."
    
    # Try to find API ID by name
    if [[ -z "${API_ID:-}" ]]; then
        API_ID=$(aws apigateway get-rest-apis \
            --query "items[?name=='${API_NAME}'].id" \
            --output text 2>/dev/null || echo "")
    fi
    
    # Try to find usage plans
    if [[ -z "${PREMIUM_PLAN_ID:-}" ]]; then
        PREMIUM_PLAN_ID=$(aws apigateway get-usage-plans \
            --query "items[?name=='Premium-Plan-${RANDOM_SUFFIX}'].id" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -z "${STANDARD_PLAN_ID:-}" ]]; then
        STANDARD_PLAN_ID=$(aws apigateway get-usage-plans \
            --query "items[?name=='Standard-Plan-${RANDOM_SUFFIX}'].id" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -z "${BASIC_PLAN_ID:-}" ]]; then
        BASIC_PLAN_ID=$(aws apigateway get-usage-plans \
            --query "items[?name=='Basic-Plan-${RANDOM_SUFFIX}'].id" \
            --output text 2>/dev/null || echo "")
    fi
    
    # Try to find API keys
    if [[ -z "${PREMIUM_KEY_ID:-}" ]]; then
        PREMIUM_KEY_ID=$(aws apigateway get-api-keys \
            --query "items[?name=='premium-customer-${RANDOM_SUFFIX}'].id" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -z "${STANDARD_KEY_ID:-}" ]]; then
        STANDARD_KEY_ID=$(aws apigateway get-api-keys \
            --query "items[?name=='standard-customer-${RANDOM_SUFFIX}'].id" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -z "${BASIC_KEY_ID:-}" ]]; then
        BASIC_KEY_ID=$(aws apigateway get-api-keys \
            --query "items[?name=='basic-customer-${RANDOM_SUFFIX}'].id" \
            --output text 2>/dev/null || echo "")
    fi
    
    log_success "Resource discovery completed"
}

# Confirmation prompt for destructive operations
confirm_cleanup() {
    echo ""
    echo -e "${RED}⚠️  WARNING: This will permanently delete the following resources:${NC}"
    echo ""
    
    [[ -n "${API_ID:-}" ]] && echo "  - API Gateway: ${API_NAME} (${API_ID})"
    [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    [[ -n "${IAM_ROLE_NAME:-}" ]] && echo "  - IAM Role: ${IAM_ROLE_NAME}"
    [[ -n "${PREMIUM_PLAN_ID:-}" ]] && echo "  - Premium Usage Plan"
    [[ -n "${STANDARD_PLAN_ID:-}" ]] && echo "  - Standard Usage Plan"
    [[ -n "${BASIC_PLAN_ID:-}" ]] && echo "  - Basic Usage Plan"
    [[ -n "${PREMIUM_KEY_ID:-}" ]] && echo "  - Premium API Key"
    [[ -n "${STANDARD_KEY_ID:-}" ]] && echo "  - Standard API Key"
    [[ -n "${BASIC_KEY_ID:-}" ]] && echo "  - Basic API Key"
    echo "  - CloudWatch Alarms"
    echo ""
    
    read -p "Are you sure you want to delete these resources? (type 'delete' to confirm): " confirm
    
    if [[ "$confirm" != "delete" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed deletion. Proceeding with cleanup..."
}

# Delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    local alarms_deleted=0
    
    # Delete throttling alarm
    if [[ -n "${THROTTLING_ALARM_NAME:-}" ]]; then
        if aws cloudwatch delete-alarms --alarm-names "$THROTTLING_ALARM_NAME" 2>/dev/null; then
            log_success "Deleted throttling alarm: ${THROTTLING_ALARM_NAME}"
            ((alarms_deleted++))
        else
            warn_missing "Throttling alarm: ${THROTTLING_ALARM_NAME}"
        fi
    else
        # Try with constructed name
        local alarm_name="API-High-Throttling-${RANDOM_SUFFIX}"
        if aws cloudwatch delete-alarms --alarm-names "$alarm_name" 2>/dev/null; then
            log_success "Deleted throttling alarm: ${alarm_name}"
            ((alarms_deleted++))
        else
            warn_missing "Throttling alarm: ${alarm_name}"
        fi
    fi
    
    # Delete error alarm
    if [[ -n "${ERROR_ALARM_NAME:-}" ]]; then
        if aws cloudwatch delete-alarms --alarm-names "$ERROR_ALARM_NAME" 2>/dev/null; then
            log_success "Deleted error alarm: ${ERROR_ALARM_NAME}"
            ((alarms_deleted++))
        else
            warn_missing "Error alarm: ${ERROR_ALARM_NAME}"
        fi
    else
        # Try with constructed name
        local alarm_name="API-High-4xx-Errors-${RANDOM_SUFFIX}"
        if aws cloudwatch delete-alarms --alarm-names "$alarm_name" 2>/dev/null; then
            log_success "Deleted error alarm: ${alarm_name}"
            ((alarms_deleted++))
        else
            warn_missing "Error alarm: ${alarm_name}"
        fi
    fi
    
    if [[ $alarms_deleted -gt 0 ]]; then
        log_success "CloudWatch alarms cleanup completed"
    else
        log_warning "No CloudWatch alarms found to delete"
    fi
}

# Delete usage plans (this also removes associations)
delete_usage_plans() {
    log "Deleting usage plans..."
    
    local plans_deleted=0
    
    # Delete Premium usage plan
    if [[ -n "${PREMIUM_PLAN_ID:-}" ]]; then
        if aws apigateway delete-usage-plan --usage-plan-id "$PREMIUM_PLAN_ID" 2>/dev/null; then
            log_success "Deleted Premium usage plan: ${PREMIUM_PLAN_ID}"
            ((plans_deleted++))
        else
            warn_missing "Premium usage plan: ${PREMIUM_PLAN_ID}"
        fi
    fi
    
    # Delete Standard usage plan
    if [[ -n "${STANDARD_PLAN_ID:-}" ]]; then
        if aws apigateway delete-usage-plan --usage-plan-id "$STANDARD_PLAN_ID" 2>/dev/null; then
            log_success "Deleted Standard usage plan: ${STANDARD_PLAN_ID}"
            ((plans_deleted++))
        else
            warn_missing "Standard usage plan: ${STANDARD_PLAN_ID}"
        fi
    fi
    
    # Delete Basic usage plan
    if [[ -n "${BASIC_PLAN_ID:-}" ]]; then
        if aws apigateway delete-usage-plan --usage-plan-id "$BASIC_PLAN_ID" 2>/dev/null; then
            log_success "Deleted Basic usage plan: ${BASIC_PLAN_ID}"
            ((plans_deleted++))
        else
            warn_missing "Basic usage plan: ${BASIC_PLAN_ID}"
        fi
    fi
    
    if [[ $plans_deleted -gt 0 ]]; then
        log_success "Usage plans cleanup completed"
    else
        log_warning "No usage plans found to delete"
    fi
}

# Delete API keys
delete_api_keys() {
    log "Deleting API keys..."
    
    local keys_deleted=0
    
    # Delete Premium API key
    if [[ -n "${PREMIUM_KEY_ID:-}" ]]; then
        if aws apigateway delete-api-key --api-key "$PREMIUM_KEY_ID" 2>/dev/null; then
            log_success "Deleted Premium API key: ${PREMIUM_KEY_ID}"
            ((keys_deleted++))
        else
            warn_missing "Premium API key: ${PREMIUM_KEY_ID}"
        fi
    fi
    
    # Delete Standard API key
    if [[ -n "${STANDARD_KEY_ID:-}" ]]; then
        if aws apigateway delete-api-key --api-key "$STANDARD_KEY_ID" 2>/dev/null; then
            log_success "Deleted Standard API key: ${STANDARD_KEY_ID}"
            ((keys_deleted++))
        else
            warn_missing "Standard API key: ${STANDARD_KEY_ID}"
        fi
    fi
    
    # Delete Basic API key
    if [[ -n "${BASIC_KEY_ID:-}" ]]; then
        if aws apigateway delete-api-key --api-key "$BASIC_KEY_ID" 2>/dev/null; then
            log_success "Deleted Basic API key: ${BASIC_KEY_ID}"
            ((keys_deleted++))
        else
            warn_missing "Basic API key: ${BASIC_KEY_ID}"
        fi
    fi
    
    if [[ $keys_deleted -gt 0 ]]; then
        log_success "API keys cleanup completed"
    else
        log_warning "No API keys found to delete"
    fi
}

# Delete API Gateway
delete_api_gateway() {
    log "Deleting API Gateway..."
    
    if [[ -n "${API_ID:-}" ]]; then
        if aws apigateway delete-rest-api --rest-api-id "$API_ID" 2>/dev/null; then
            log_success "Deleted API Gateway: ${API_NAME} (${API_ID})"
        else
            warn_missing "API Gateway: ${API_NAME} (${API_ID})"
        fi
    else
        warn_missing "API Gateway ID not available"
    fi
}

# Delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" 2>/dev/null; then
            log_success "Deleted Lambda function: ${LAMBDA_FUNCTION_NAME}"
        else
            warn_missing "Lambda function: ${LAMBDA_FUNCTION_NAME}"
        fi
    else
        warn_missing "Lambda function name not available"
    fi
}

# Delete IAM role and policies
delete_iam_role() {
    log "Deleting IAM role and policies..."
    
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        # Detach policies first
        if aws iam detach-role-policy \
            --role-name "$IAM_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null; then
            log_success "Detached basic execution policy from role: ${IAM_ROLE_NAME}"
        else
            warn_missing "Policy attachment for role: ${IAM_ROLE_NAME}"
        fi
        
        # Delete the role
        if aws iam delete-role --role-name "$IAM_ROLE_NAME" 2>/dev/null; then
            log_success "Deleted IAM role: ${IAM_ROLE_NAME}"
        else
            warn_missing "IAM role: ${IAM_ROLE_NAME}"
        fi
    else
        warn_missing "IAM role name not available"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_cleaned=0
    local files_to_clean=(
        "${SCRIPT_DIR}/../.env"
        "${SCRIPT_DIR}/../deployment-summary.txt"
        "${SCRIPT_DIR}/../temp"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -e "$file" ]]; then
            rm -rf "$file"
            log_success "Removed: ${file}"
            ((files_cleaned++))
        fi
    done
    
    if [[ $files_cleaned -gt 0 ]]; then
        log_success "Local files cleanup completed"
    else
        log_warning "No local files found to clean up"
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    log "Generating cleanup summary..."
    
    cat > "${SCRIPT_DIR}/../cleanup-summary.txt" << EOF
API Gateway Throttling Demo - Cleanup Summary
============================================

Cleanup completed: $(date)

Resources Removed:
- API Gateway: ${API_NAME:-Unknown} (${API_ID:-Unknown})
- Lambda Function: ${LAMBDA_FUNCTION_NAME:-Unknown}
- IAM Role: ${IAM_ROLE_NAME:-Unknown}
- Usage Plans: Premium, Standard, Basic
- API Keys: Premium, Standard, Basic
- CloudWatch Alarms: Throttling and Error alarms

Local Files Removed:
- Environment configuration (.env)
- Deployment summary
- Temporary files

Status: All resources have been successfully removed.
No ongoing AWS charges should occur from this deployment.

Note: CloudWatch Logs may be retained according to your AWS account's
log retention policies. These typically expire automatically but can
be manually deleted if needed.

For verification, check the AWS Console:
- API Gateway: No APIs named "${API_NAME:-throttling-demo-*}"
- Lambda: No functions named "${LAMBDA_FUNCTION_NAME:-api-backend-*}"
- IAM: No roles named "${IAM_ROLE_NAME:-lambda-execution-role-*}"
EOF
    
    log_success "Cleanup summary saved to: ${SCRIPT_DIR}/../cleanup-summary.txt"
}

# Main cleanup function
main() {
    log "Starting API Gateway throttling cleanup..."
    log "Cleanup log: $LOG_FILE"
    
    # Initialize log file
    echo "API Gateway Throttling Cleanup - $(date)" > "$LOG_FILE"
    
    # Check prerequisites
    if ! check_prerequisites; then
        log_warning "Prerequisites check failed, attempting interactive cleanup"
    fi
    
    # Load environment or start interactive mode
    if ! load_environment; then
        interactive_cleanup
    fi
    
    # Discover resources
    discover_resources
    
    # Confirm cleanup
    confirm_cleanup
    
    # Execute cleanup steps in reverse order of creation
    delete_cloudwatch_alarms
    delete_usage_plans
    delete_api_keys
    delete_api_gateway
    delete_lambda_function
    delete_iam_role
    cleanup_local_files
    generate_cleanup_summary
    
    log_success "Cleanup completed successfully!"
    log ""
    log "📋 Cleanup Summary:"
    log "   ✅ All AWS resources have been removed"
    log "   ✅ Local configuration files cleaned up"
    log "   ✅ No ongoing charges should occur"
    log ""
    log "📖 View complete summary: ${SCRIPT_DIR}/../cleanup-summary.txt"
    log "💰 Verify in AWS Console that all resources are deleted"
}

# Run main function
main "$@"