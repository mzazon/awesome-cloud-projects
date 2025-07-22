#!/bin/bash

# AWS URL Shortener Service Cleanup Script
# This script removes all resources created by the URL shortener deployment
# Based on the recipe: URL Shortener Service with Lambda

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_NAME="AWS URL Shortener Destroy"
LOG_FILE="/tmp/url-shortener-destroy-$(date +%Y%m%d-%H%M%S).log"
TEMP_DIR="/tmp/url-shortener-cleanup"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Progress indicator
progress() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Success indicator
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Warning indicator
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Error indicator
error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Cleanup function for script exit
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Cleanup failed with exit code $exit_code"
        error "Check log file: $LOG_FILE"
        error "Some resources may still exist and require manual cleanup"
    fi
    # Clean up temporary files
    rm -rf "$TEMP_DIR" 2>/dev/null || true
    exit $exit_code
}

trap cleanup EXIT

# Help function
show_help() {
    cat << EOF
$SCRIPT_NAME

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deleted without actually removing resources
    -v, --verbose       Enable verbose logging
    -f, --force         Skip confirmation prompts (dangerous!)
    -r, --region        AWS region (default: from AWS CLI config)
    --suffix            Resource suffix to target for deletion
    --keep-monitoring   Skip CloudWatch dashboard deletion

EXAMPLES:
    $0                              # Interactive cleanup with confirmations
    $0 --dry-run                    # Show what would be deleted
    $0 --force                      # Skip confirmations (use with caution!)
    $0 --suffix abc123              # Target specific deployment

PREREQUISITES:
    - AWS CLI installed and configured
    - Appropriate AWS permissions for Lambda, DynamoDB, API Gateway, CloudWatch, IAM
    - deployment-env.sh file from deployment (if available)

WARNING:
    This script will permanently delete AWS resources and cannot be undone.
    Always run with --dry-run first to verify what will be deleted.

EOF
}

# Parse command line arguments
DRY_RUN=false
VERBOSE=false
FORCE=false
CUSTOM_REGION=""
CUSTOM_SUFFIX=""
KEEP_MONITORING=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -r|--region)
            CUSTOM_REGION="$2"
            shift 2
            ;;
        --suffix)
            CUSTOM_SUFFIX="$2"
            shift 2
            ;;
        --keep-monitoring)
            KEEP_MONITORING=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Enable verbose logging if requested
if [ "$VERBOSE" = true ]; then
    set -x
fi

log "Starting $SCRIPT_NAME"
log "Log file: $LOG_FILE"

# Prerequisites check
check_prerequisites() {
    progress "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Load environment variables
load_environment() {
    progress "Loading environment configuration..."
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Try to load from deployment environment file
    DEPLOYMENT_ENV_FILE="$(dirname "$0")/deployment-env.sh"
    if [ -f "$DEPLOYMENT_ENV_FILE" ]; then
        progress "Loading environment from: $DEPLOYMENT_ENV_FILE"
        source "$DEPLOYMENT_ENV_FILE"
        success "Environment loaded from deployment file"
    else
        warning "deployment-env.sh not found, using manual configuration"
        
        # Set AWS region
        if [ -n "$CUSTOM_REGION" ]; then
            export AWS_REGION="$CUSTOM_REGION"
        else
            export AWS_REGION=$(aws configure get region)
            if [ -z "$AWS_REGION" ]; then
                export AWS_REGION="us-east-1"
                warning "No region configured, using default: $AWS_REGION"
            fi
        fi
        
        # Get AWS account ID
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # If suffix provided, construct resource names
        if [ -n "$CUSTOM_SUFFIX" ]; then
            export TABLE_NAME="url-shortener-${CUSTOM_SUFFIX}"
            export FUNCTION_NAME="url-shortener-${CUSTOM_SUFFIX}"
            export API_NAME="url-shortener-api-${CUSTOM_SUFFIX}"
            export ROLE_NAME="${FUNCTION_NAME}-role"
            export POLICY_NAME="${FUNCTION_NAME}-dynamodb-policy"
            export DASHBOARD_NAME="URLShortener-${CUSTOM_SUFFIX}"
        else
            error "No deployment environment found and no suffix provided."
            error "Either provide --suffix parameter or ensure deployment-env.sh exists."
            exit 1
        fi
    fi
    
    log "Environment configuration:"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account ID: $AWS_ACCOUNT_ID"
    log "  Table Name: $TABLE_NAME"
    log "  Function Name: $FUNCTION_NAME"
    log "  API Name: $API_NAME"
    log "  Role Name: $ROLE_NAME"
    log "  Policy Name: $POLICY_NAME"
    log "  Dashboard Name: $DASHBOARD_NAME"
}

# Confirmation prompt
confirm_destruction() {
    if [ "$FORCE" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    warning "This will permanently delete the following AWS resources:"
    warning "  - DynamoDB Table: $TABLE_NAME"
    warning "  - Lambda Function: $FUNCTION_NAME"
    warning "  - API Gateway: $API_NAME"
    warning "  - IAM Role: $ROLE_NAME"
    warning "  - IAM Policy: $POLICY_NAME"
    if [ "$KEEP_MONITORING" != true ]; then
        warning "  - CloudWatch Dashboard: $DASHBOARD_NAME"
    fi
    warning ""
    warning "THIS ACTION CANNOT BE UNDONE!"
    warning ""
    
    read -p "Are you sure you want to continue? Type 'yes' to proceed: " -r
    echo
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
}

# Find and list resources
discover_resources() {
    progress "Discovering existing resources..."
    
    local resources_found=false
    
    # Check for API Gateway
    if [ -n "${API_ID:-}" ]; then
        if aws apigatewayv2 get-api --api-id "$API_ID" &>/dev/null; then
            log "  Found API Gateway: $API_NAME ($API_ID)"
            resources_found=true
        fi
    else
        # Try to find API by name
        local found_api_id=$(aws apigatewayv2 get-apis \
            --query "Items[?Name=='$API_NAME'].ApiId" \
            --output text 2>/dev/null || echo "")
        if [ -n "$found_api_id" ] && [ "$found_api_id" != "None" ]; then
            export API_ID="$found_api_id"
            log "  Found API Gateway: $API_NAME ($API_ID)"
            resources_found=true
        fi
    fi
    
    # Check for Lambda function
    if aws lambda get-function --function-name "$FUNCTION_NAME" &>/dev/null; then
        log "  Found Lambda Function: $FUNCTION_NAME"
        resources_found=true
    fi
    
    # Check for DynamoDB table
    if aws dynamodb describe-table --table-name "$TABLE_NAME" &>/dev/null; then
        log "  Found DynamoDB Table: $TABLE_NAME"
        resources_found=true
    fi
    
    # Check for IAM role
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log "  Found IAM Role: $ROLE_NAME"
        resources_found=true
    fi
    
    # Check for IAM policy
    if aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME" &>/dev/null; then
        log "  Found IAM Policy: $POLICY_NAME"
        resources_found=true
    fi
    
    # Check for CloudWatch dashboard
    if [ "$KEEP_MONITORING" != true ]; then
        if aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" &>/dev/null; then
            log "  Found CloudWatch Dashboard: $DASHBOARD_NAME"
            resources_found=true
        fi
    fi
    
    if [ "$resources_found" = false ]; then
        warning "No resources found matching the configuration"
        log "Either the resources don't exist or have already been deleted"
        exit 0
    fi
    
    success "Resource discovery complete"
}

# Remove API Gateway
remove_api_gateway() {
    progress "Removing API Gateway..."
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would delete API Gateway: $API_NAME"
        return 0
    fi
    
    # Check if API exists
    if [ -z "${API_ID:-}" ]; then
        warning "API_ID not set, skipping API Gateway deletion"
        return 0
    fi
    
    if ! aws apigatewayv2 get-api --api-id "$API_ID" &>/dev/null; then
        warning "API Gateway $API_ID not found, skipping"
        return 0
    fi
    
    # Delete API Gateway (this removes all associated resources)
    aws apigatewayv2 delete-api --api-id "$API_ID"
    
    success "API Gateway deleted: $API_ID"
}

# Remove Lambda function
remove_lambda_function() {
    progress "Removing Lambda function..."
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would delete Lambda function: $FUNCTION_NAME"
        return 0
    fi
    
    # Check if function exists
    if ! aws lambda get-function --function-name "$FUNCTION_NAME" &>/dev/null; then
        warning "Lambda function $FUNCTION_NAME not found, skipping"
        return 0
    fi
    
    # Delete Lambda function
    aws lambda delete-function --function-name "$FUNCTION_NAME"
    
    success "Lambda function deleted: $FUNCTION_NAME"
}

# Remove DynamoDB table
remove_dynamodb_table() {
    progress "Removing DynamoDB table..."
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would delete DynamoDB table: $TABLE_NAME"
        return 0
    fi
    
    # Check if table exists
    if ! aws dynamodb describe-table --table-name "$TABLE_NAME" &>/dev/null; then
        warning "DynamoDB table $TABLE_NAME not found, skipping"
        return 0
    fi
    
    # Delete DynamoDB table
    aws dynamodb delete-table --table-name "$TABLE_NAME"
    
    # Wait for table to be deleted (with timeout)
    progress "Waiting for DynamoDB table deletion to complete..."
    local timeout=300  # 5 minutes
    local elapsed=0
    local interval=10
    
    while [ $elapsed -lt $timeout ]; do
        if ! aws dynamodb describe-table --table-name "$TABLE_NAME" &>/dev/null; then
            success "DynamoDB table deleted: $TABLE_NAME"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        progress "Still waiting for table deletion... (${elapsed}s elapsed)"
    done
    
    warning "Table deletion timeout reached, table may still be deleting"
}

# Remove IAM resources
remove_iam_resources() {
    progress "Removing IAM resources..."
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would delete IAM role: $ROLE_NAME"
        log "DRY RUN: Would delete IAM policy: $POLICY_NAME"
        return 0
    fi
    
    # Remove IAM role
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        progress "Detaching policies from IAM role..."
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME" 2>/dev/null || true
        
        # Wait a moment for detachment to propagate
        sleep 5
        
        # Delete IAM role
        aws iam delete-role --role-name "$ROLE_NAME"
        success "IAM role deleted: $ROLE_NAME"
    else
        warning "IAM role $ROLE_NAME not found, skipping"
    fi
    
    # Remove custom IAM policy
    if aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME" &>/dev/null; then
        # Delete all policy versions except default
        local versions=$(aws iam list-policy-versions \
            --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME" \
            --query 'Versions[?!IsDefaultVersion].VersionId' \
            --output text 2>/dev/null || echo "")
        
        for version in $versions; do
            aws iam delete-policy-version \
                --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME" \
                --version-id "$version" 2>/dev/null || true
        done
        
        # Delete the policy
        aws iam delete-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME"
        success "IAM policy deleted: $POLICY_NAME"
    else
        warning "IAM policy $POLICY_NAME not found, skipping"
    fi
}

# Remove CloudWatch monitoring
remove_monitoring() {
    if [ "$KEEP_MONITORING" = true ]; then
        progress "Skipping CloudWatch dashboard deletion (--keep-monitoring specified)"
        return 0
    fi
    
    progress "Removing CloudWatch monitoring..."
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would delete CloudWatch dashboard: $DASHBOARD_NAME"
        return 0
    fi
    
    # Check if dashboard exists
    if ! aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" &>/dev/null; then
        warning "CloudWatch dashboard $DASHBOARD_NAME not found, skipping"
        return 0
    fi
    
    # Delete CloudWatch dashboard
    aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME"
    
    success "CloudWatch dashboard deleted: $DASHBOARD_NAME"
}

# Clean up deployment artifacts
cleanup_artifacts() {
    progress "Cleaning up deployment artifacts..."
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would clean up deployment artifacts"
        return 0
    fi
    
    # Remove deployment environment file
    local env_file="$(dirname "$0")/deployment-env.sh"
    if [ -f "$env_file" ]; then
        rm -f "$env_file"
        success "Removed deployment environment file"
    fi
    
    # Clean up any temporary Lambda packages
    rm -f /tmp/lambda-function*.zip 2>/dev/null || true
    rm -rf /tmp/url-shortener-deployment* 2>/dev/null || true
    
    success "Deployment artifacts cleaned up"
}

# Display destruction summary
show_destruction_summary() {
    progress "Destruction Summary"
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN - No resources were actually deleted"
        log "Run without --dry-run to perform actual deletion"
        return 0
    fi
    
    log "====================================="
    success "URL Shortener Service Cleanup Complete!"
    log "====================================="
    log ""
    log "Removed Resources:"
    log "  ✅ DynamoDB Table: $TABLE_NAME"
    log "  ✅ Lambda Function: $FUNCTION_NAME"
    log "  ✅ API Gateway: $API_NAME"
    log "  ✅ IAM Role: $ROLE_NAME"
    log "  ✅ IAM Policy: $POLICY_NAME"
    if [ "$KEEP_MONITORING" != true ]; then
        log "  ✅ CloudWatch Dashboard: $DASHBOARD_NAME"
    fi
    log "  ✅ Deployment artifacts"
    log ""
    log "Log file: $LOG_FILE"
    log ""
    success "All resources have been successfully removed!"
}

# Verify resources are deleted
verify_cleanup() {
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    progress "Verifying resource cleanup..."
    
    local cleanup_errors=0
    
    # Check API Gateway
    if [ -n "${API_ID:-}" ] && aws apigatewayv2 get-api --api-id "$API_ID" &>/dev/null; then
        error "API Gateway still exists: $API_ID"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$FUNCTION_NAME" &>/dev/null; then
        error "Lambda function still exists: $FUNCTION_NAME"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check DynamoDB table (may still be deleting)
    if aws dynamodb describe-table --table-name "$TABLE_NAME" &>/dev/null; then
        local table_status=$(aws dynamodb describe-table --table-name "$TABLE_NAME" \
            --query 'Table.TableStatus' --output text 2>/dev/null || echo "UNKNOWN")
        if [ "$table_status" = "DELETING" ]; then
            warning "DynamoDB table is still deleting: $TABLE_NAME"
        else
            error "DynamoDB table still exists: $TABLE_NAME (status: $table_status)"
            cleanup_errors=$((cleanup_errors + 1))
        fi
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        error "IAM role still exists: $ROLE_NAME"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check IAM policy
    if aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME" &>/dev/null; then
        error "IAM policy still exists: $POLICY_NAME"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    if [ $cleanup_errors -gt 0 ]; then
        error "Cleanup verification failed. Some resources may require manual deletion."
        exit 1
    fi
    
    success "Cleanup verification passed"
}

# Main destruction function
main() {
    # Run cleanup steps
    check_prerequisites
    load_environment
    discover_resources
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_api_gateway
    remove_lambda_function
    remove_dynamodb_table
    remove_iam_resources
    remove_monitoring
    cleanup_artifacts
    
    # Verify cleanup
    verify_cleanup
    show_destruction_summary
}

# Run main function
main "$@"