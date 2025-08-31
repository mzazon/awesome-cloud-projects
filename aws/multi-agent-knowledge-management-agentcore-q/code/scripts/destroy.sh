#!/bin/bash

################################################################################
# Multi-Agent Knowledge Management with Bedrock AgentCore and Q Business
# Cleanup/Destroy Script
# 
# This script safely removes all resources created by the deployment script:
# - Lambda functions and their permissions
# - Q Business application, index, and data sources
# - S3 buckets and their contents
# - DynamoDB table
# - API Gateway
# - IAM roles and policies
#
# IMPORTANT: This script will permanently delete all data and resources!
################################################################################

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
ERROR_FILE="cleanup_errors_$(date +%Y%m%d_%H%M%S).log"

# Flags
FORCE_DELETE=false
DRY_RUN=false
CONFIRM_PROMPTS=true

# Log function
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

# Error logging function
log_error() {
    echo -e "${RED}ERROR: ${1}${NC}" | tee -a "$LOG_FILE" | tee -a "$ERROR_FILE"
}

# Success logging function
log_success() {
    echo -e "${GREEN}✅ ${1}${NC}" | tee -a "$LOG_FILE"
}

# Warning logging function
log_warning() {
    echo -e "${YELLOW}⚠️  ${1}${NC}" | tee -a "$LOG_FILE"
}

# Info logging function
log_info() {
    echo -e "${BLUE}ℹ️  ${1}${NC}" | tee -a "$LOG_FILE"
}

# Progress logging function
log_progress() {
    echo -e "${PURPLE}🗑️  ${1}${NC}" | tee -a "$LOG_FILE"
}

# Function to load environment from deployment
load_deployment_environment() {
    log_progress "Loading deployment environment..."
    
    if [[ -f ".deployment_env" ]]; then
        source .deployment_env
        log_info "Loaded environment from .deployment_env"
    else
        log_warning "No .deployment_env file found. You may need to specify resources manually."
        return 1
    fi
    
    # Verify required variables are set
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "PROJECT_NAME" "RANDOM_SUFFIX"
        "S3_BUCKET_FINANCE" "S3_BUCKET_HR" "S3_BUCKET_TECH"
        "IAM_ROLE_NAME" "SESSION_TABLE"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable $var is not set"
            return 1
        fi
    done
    
    log_success "Environment loaded successfully"
    return 0
}

# Function to find resources by tags or naming patterns
discover_resources() {
    log_progress "Discovering resources to clean up..."
    
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        log_error "Cannot discover resources without RANDOM_SUFFIX"
        return 1
    fi
    
    # Discover Lambda functions
    local lambda_functions
    lambda_functions=$(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, '${RANDOM_SUFFIX}')].FunctionName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$lambda_functions" ]]; then
        log_info "Found Lambda functions: $lambda_functions"
    fi
    
    # Discover S3 buckets
    local s3_buckets
    s3_buckets=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, '${RANDOM_SUFFIX}')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$s3_buckets" ]]; then
        log_info "Found S3 buckets: $s3_buckets"
    fi
    
    # Discover DynamoDB tables
    local dynamo_tables
    dynamo_tables=$(aws dynamodb list-tables \
        --query "TableNames[?contains(@, '${RANDOM_SUFFIX}')]" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$dynamo_tables" ]]; then
        log_info "Found DynamoDB tables: $dynamo_tables"
    fi
    
    # Discover IAM roles
    local iam_roles
    iam_roles=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, '${RANDOM_SUFFIX}')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$iam_roles" ]]; then
        log_info "Found IAM roles: $iam_roles"
    fi
    
    log_success "Resource discovery completed"
}

# Function to confirm dangerous operations
confirm_action() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "$FORCE_DELETE" == "true" ]] || [[ "$CONFIRM_PROMPTS" == "false" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}${message}${NC}"
    echo -n "Are you sure? [y/N]: "
    read -r response
    
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to safely delete S3 bucket
safe_delete_s3_bucket() {
    local bucket_name="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would delete S3 bucket: $bucket_name"
        return 0
    fi
    
    log_progress "Deleting S3 bucket: $bucket_name"
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log_warning "Bucket $bucket_name does not exist or is not accessible"
        return 0
    fi
    
    # Delete all object versions (including delete markers)
    log_info "Deleting all objects and versions from $bucket_name..."
    
    # Get all versions and delete markers
    local versions
    versions=$(aws s3api list-object-versions --bucket "$bucket_name" --output json 2>/dev/null || echo '{}')
    
    # Delete versions
    local version_objects
    version_objects=$(echo "$versions" | jq -r '.Versions[]? | {Key: .Key, VersionId: .VersionId}' 2>/dev/null || echo "")
    
    if [[ -n "$version_objects" ]]; then
        echo "$versions" | jq -r '.Versions[]? | "aws s3api delete-object --bucket '"$bucket_name"' --key \"\(.Key)\" --version-id \"\(.VersionId)\""' | while read -r cmd; do
            eval "$cmd" >/dev/null 2>&1 || true
        done
    fi
    
    # Delete delete markers
    local delete_markers
    delete_markers=$(echo "$versions" | jq -r '.DeleteMarkers[]? | "aws s3api delete-object --bucket '"$bucket_name"' --key \"\(.Key)\" --version-id \"\(.VersionId)\""' 2>/dev/null || echo "")
    
    if [[ -n "$delete_markers" ]]; then
        echo "$delete_markers" | while read -r cmd; do
            eval "$cmd" >/dev/null 2>&1 || true
        done
    fi
    
    # Delete any remaining objects (for non-versioned buckets)
    aws s3 rm "s3://${bucket_name}" --recursive >/dev/null 2>&1 || true
    
    # Delete the bucket
    if aws s3 rb "s3://${bucket_name}" >/dev/null 2>&1; then
        log_success "Successfully deleted S3 bucket: $bucket_name"
    else
        log_error "Failed to delete S3 bucket: $bucket_name"
    fi
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log_progress "Deleting Lambda functions..."
    
    local functions=(
        "supervisor-agent-${RANDOM_SUFFIX}"
        "finance-agent-${RANDOM_SUFFIX}"
        "hr-agent-${RANDOM_SUFFIX}"
        "technical-agent-${RANDOM_SUFFIX}"
    )
    
    for func in "${functions[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "DRY RUN: Would delete Lambda function: $func"
            continue
        fi
        
        # Check if function exists
        if aws lambda get-function --function-name "$func" >/dev/null 2>&1; then
            # Remove any event source mappings first
            local mappings
            mappings=$(aws lambda list-event-source-mappings --function-name "$func" --query 'EventSourceMappings[].UUID' --output text 2>/dev/null || echo "")
            
            for mapping in $mappings; do
                aws lambda delete-event-source-mapping --uuid "$mapping" >/dev/null 2>&1 || true
            done
            
            # Delete the function
            if aws lambda delete-function --function-name "$func" >/dev/null 2>&1; then
                log_success "Deleted Lambda function: $func"
            else
                log_error "Failed to delete Lambda function: $func"
            fi
        else
            log_info "Lambda function does not exist: $func"
        fi
    done
}

# Function to delete API Gateway
delete_api_gateway() {
    log_progress "Deleting API Gateway..."
    
    local api_name="multi-agent-km-api-${RANDOM_SUFFIX}"
    
    # Find API by name
    local api_id
    api_id=$(aws apigatewayv2 get-apis --query "Items[?Name=='${api_name}'].ApiId" --output text 2>/dev/null || echo "")
    
    if [[ -n "$api_id" && "$api_id" != "None" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "DRY RUN: Would delete API Gateway: $api_id"
            return 0
        fi
        
        if aws apigatewayv2 delete-api --api-id "$api_id" >/dev/null 2>&1; then
            log_success "Deleted API Gateway: $api_id"
        else
            log_error "Failed to delete API Gateway: $api_id"
        fi
    else
        log_info "API Gateway not found: $api_name"
    fi
}

# Function to delete Q Business resources
delete_qbusiness_resources() {
    log_progress "Deleting Q Business resources..."
    
    if [[ -z "${Q_APP_ID:-}" ]]; then
        log_warning "Q Business Application ID not found in environment"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would delete Q Business application: $Q_APP_ID"
        return 0
    fi
    
    # Delete data sources first
    local data_sources=("${FINANCE_DS_ID:-}" "${HR_DS_ID:-}" "${TECH_DS_ID:-}")
    
    for ds_id in "${data_sources[@]}"; do
        if [[ -n "$ds_id" ]]; then
            log_info "Deleting data source: $ds_id"
            aws qbusiness delete-data-source \
                --application-id "$Q_APP_ID" \
                --data-source-id "$ds_id" >/dev/null 2>&1 || true
        fi
    done
    
    # Wait for data sources to be deleted
    log_info "Waiting for data sources to be deleted..."
    sleep 30
    
    # Delete index
    if [[ -n "${INDEX_ID:-}" ]]; then
        log_info "Deleting Q Business index: $INDEX_ID"
        aws qbusiness delete-index \
            --application-id "$Q_APP_ID" \
            --index-id "$INDEX_ID" >/dev/null 2>&1 || true
        
        # Wait for index deletion
        sleep 30
    fi
    
    # Delete application
    log_info "Deleting Q Business application: $Q_APP_ID"
    if aws qbusiness delete-application --application-id "$Q_APP_ID" >/dev/null 2>&1; then
        log_success "Deleted Q Business application: $Q_APP_ID"
    else
        log_error "Failed to delete Q Business application: $Q_APP_ID"
    fi
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    log_progress "Deleting DynamoDB table..."
    
    if [[ -z "${SESSION_TABLE:-}" ]]; then
        log_warning "Session table name not found in environment"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would delete DynamoDB table: $SESSION_TABLE"
        return 0
    fi
    
    # Check if table exists
    if aws dynamodb describe-table --table-name "$SESSION_TABLE" >/dev/null 2>&1; then
        if aws dynamodb delete-table --table-name "$SESSION_TABLE" >/dev/null 2>&1; then
            log_success "Deleted DynamoDB table: $SESSION_TABLE"
        else
            log_error "Failed to delete DynamoDB table: $SESSION_TABLE"
        fi
    else
        log_info "DynamoDB table does not exist: $SESSION_TABLE"
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    log_progress "Deleting IAM resources..."
    
    if [[ -z "${IAM_ROLE_NAME:-}" ]]; then
        log_warning "IAM role name not found in environment"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would delete IAM role: $IAM_ROLE_NAME"
        return 0
    fi
    
    # Check if role exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        # Detach all attached policies
        local attached_policies
        attached_policies=$(aws iam list-attached-role-policies --role-name "$IAM_ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        
        for policy_arn in $attached_policies; do
            log_info "Detaching policy: $(basename "$policy_arn")"
            aws iam detach-role-policy --role-name "$IAM_ROLE_NAME" --policy-arn "$policy_arn" >/dev/null 2>&1 || true
        done
        
        # Delete inline policies
        local inline_policies
        inline_policies=$(aws iam list-role-policies --role-name "$IAM_ROLE_NAME" --query 'PolicyNames' --output text 2>/dev/null || echo "")
        
        for policy_name in $inline_policies; do
            log_info "Deleting inline policy: $policy_name"
            aws iam delete-role-policy --role-name "$IAM_ROLE_NAME" --policy-name "$policy_name" >/dev/null 2>&1 || true
        done
        
        # Delete the role
        if aws iam delete-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
            log_success "Deleted IAM role: $IAM_ROLE_NAME"
        else
            log_error "Failed to delete IAM role: $IAM_ROLE_NAME"
        fi
    else
        log_info "IAM role does not exist: $IAM_ROLE_NAME"
    fi
    
    # Delete custom policies
    local policy_name="QBusinessAccess-${RANDOM_SUFFIX}"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
    
    if aws iam get-policy --policy-arn "$policy_arn" >/dev/null 2>&1; then
        # Delete all policy versions except default
        local versions
        versions=$(aws iam list-policy-versions --policy-arn "$policy_arn" --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text 2>/dev/null || echo "")
        
        for version in $versions; do
            aws iam delete-policy-version --policy-arn "$policy_arn" --version-id "$version" >/dev/null 2>&1 || true
        done
        
        # Delete the policy
        if aws iam delete-policy --policy-arn "$policy_arn" >/dev/null 2>&1; then
            log_success "Deleted custom policy: $policy_name"
        else
            log_error "Failed to delete custom policy: $policy_name"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_progress "Cleaning up local files..."
    
    local files_to_clean=(
        "supervisor-agent.py" "finance-agent.py" "hr-agent.py" "technical-agent.py"
        "supervisor-agent.zip" "finance-agent.zip" "hr-agent.zip" "technical-agent.zip"
        "finance-policy.txt" "hr-handbook.txt" "tech-guidelines.txt"
        "memory-config.json" ".deployment_env"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "DRY RUN: Would delete local file: $file"
            else
                rm -f "$file"
                log_info "Removed local file: $file"
            fi
        fi
    done
    
    log_success "Local file cleanup completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    local start_time="$1"
    local end_time="$2"
    local duration=$((end_time - start_time))
    
    echo ""
    echo "======================================================================"
    echo "                    CLEANUP SUMMARY"
    echo "======================================================================"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "🔍 DRY RUN COMPLETED - No resources were actually deleted"
    else
        echo "🗑️  CLEANUP COMPLETED SUCCESSFULLY"
    fi
    
    echo ""
    echo "⏱️  Total cleanup time: ${duration} seconds"
    echo ""
    echo "📋 RESOURCES PROCESSED:"
    echo "   ✓ Lambda Functions (4 agents)"
    echo "   ✓ API Gateway"
    echo "   ✓ Q Business Application and Data Sources"
    echo "   ✓ S3 Buckets (3 knowledge bases)"
    echo "   ✓ DynamoDB Session Table"
    echo "   ✓ IAM Role and Policies"
    echo "   ✓ Local Files and Artifacts"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "💰 COST SAVINGS:"
        echo "   • Lambda charges stopped"
        echo "   • Q Business subscription can be cancelled"
        echo "   • S3 storage charges eliminated"
        echo "   • DynamoDB charges stopped"
        echo "   • API Gateway charges stopped"
        echo ""
        echo "✅ All billable resources have been removed!"
    fi
    
    echo ""
    echo "📝 LOGS:"
    echo "   Cleanup log: $LOG_FILE"
    
    if [[ -s "$ERROR_FILE" ]]; then
        echo "   Error log: $ERROR_FILE"
        echo "   ⚠️  Some errors occurred during cleanup. Please review the error log."
    fi
    
    echo ""
    echo "======================================================================"
}

# Function to validate AWS credentials and permissions
validate_aws_access() {
    log_progress "Validating AWS access..."
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        return 1
    fi
    
    # Check if we can get caller identity
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or lacks permissions"
        return 1
    fi
    
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    log_info "Authenticated to AWS Account: $account_id"
    
    log_success "AWS access validated"
}

# Main cleanup function
main() {
    echo ""
    echo "======================================================================"
    echo "    Multi-Agent Knowledge Management System Cleanup"
    echo "    This will delete ALL resources created by the deployment!"
    echo "======================================================================"
    echo ""
    
    # Start timing
    local start_time
    start_time=$(date +%s)
    
    # Validate AWS access
    validate_aws_access
    
    # Load deployment environment
    if ! load_deployment_environment; then
        log_warning "Could not load deployment environment. Attempting resource discovery..."
        discover_resources
    fi
    
    # Final confirmation for destructive operations
    if [[ "$DRY_RUN" == "false" ]]; then
        echo -e "${RED}⚠️  WARNING: This will permanently delete all resources and data!${NC}"
        echo ""
        
        if [[ -n "${PROJECT_NAME:-}" ]]; then
            echo "Project: $PROJECT_NAME"
        fi
        
        if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
            echo "Resource Suffix: $RANDOM_SUFFIX"
        fi
        
        echo ""
        
        if ! confirm_action "This action cannot be undone. Continue with cleanup?"; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup steps
    log_progress "Starting resource cleanup..."
    
    # Delete in reverse order of creation to handle dependencies
    delete_api_gateway
    delete_lambda_functions
    delete_qbusiness_resources
    
    # Delete storage resources
    if [[ -n "${S3_BUCKET_FINANCE:-}" ]]; then
        safe_delete_s3_bucket "$S3_BUCKET_FINANCE"
    fi
    
    if [[ -n "${S3_BUCKET_HR:-}" ]]; then
        safe_delete_s3_bucket "$S3_BUCKET_HR"
    fi
    
    if [[ -n "${S3_BUCKET_TECH:-}" ]]; then
        safe_delete_s3_bucket "$S3_BUCKET_TECH"
    fi
    
    delete_dynamodb_table
    delete_iam_resources
    cleanup_local_files
    
    # Calculate timing
    local end_time
    end_time=$(date +%s)
    
    # Display summary
    display_cleanup_summary "$start_time" "$end_time"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Multi-Agent Knowledge Management System cleanup completed successfully!"
    else
        log_info "Dry run completed. Use without --dry-run to actually delete resources."
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Clean up Multi-Agent Knowledge Management System resources"
            echo ""
            echo "Options:"
            echo "  --help, -h          Show this help message"
            echo "  --force             Skip confirmation prompts"
            echo "  --dry-run           Show what would be deleted without actually deleting"
            echo "  --no-confirm        Don't prompt for confirmations (use with caution!)"
            echo ""
            echo "Examples:"
            echo "  $0                  Interactive cleanup with confirmations"
            echo "  $0 --dry-run        Preview what will be deleted"
            echo "  $0 --force          Delete everything without prompts"
            echo ""
            echo "⚠️  WARNING: This script will permanently delete resources and data!"
            echo ""
            exit 0
            ;;
        --force)
            FORCE_DELETE=true
            CONFIRM_PROMPTS=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-confirm)
            CONFIRM_PROMPTS=false
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main cleanup
main "$@"