#!/bin/bash

# Real-time Data Synchronization with AWS AppSync - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy-errors.log"
STATE_FILE="${SCRIPT_DIR}/deployment-state.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$ERROR_LOG" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Cleanup failed with exit code $exit_code"
        log_info "Check $ERROR_LOG for detailed error information"
        log_info "Some resources may still exist - review manually in AWS Console"
    fi
}

trap cleanup_on_error EXIT

# Help function
show_help() {
    cat << EOF
Real-time Data Synchronization with AWS AppSync - Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Skip confirmation prompts (use with caution)
    -d, --dry-run          Show what would be deleted without making changes
    -v, --verbose          Enable verbose logging
    --keep-logs            Keep CloudWatch logs after cleanup
    --partial-cleanup      Attempt cleanup even if state file is missing

EXAMPLES:
    $0                      # Interactive cleanup with confirmations
    $0 --dry-run           # Preview what would be deleted
    $0 --force             # Non-interactive cleanup
    $0 --partial-cleanup   # Cleanup when state file is missing

SAFETY:
    This script includes multiple confirmation steps to prevent accidental
    deletion of resources. Use --force only when you're certain.

EOF
}

# Parse command line arguments
FORCE=false
DRY_RUN=false
VERBOSE=false
KEEP_LOGS=false
PARTIAL_CLEANUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        --partial-cleanup)
            PARTIAL_CLEANUP=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize logging
echo "=== AWS AppSync Real-time Data Synchronization Cleanup ===" > "$LOG_FILE"
echo "Started at: $(date)" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

log_info "Starting cleanup of real-time data synchronization system"

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [ ! -f "$STATE_FILE" ]; then
        if [ "$PARTIAL_CLEANUP" = true ]; then
            log_warning "State file not found, attempting partial cleanup"
            log_warning "You'll need to specify resource names manually"
            return 1
        else
            log_error "State file not found: $STATE_FILE"
            log_error "Cannot determine what resources to clean up"
            log_error "Use --partial-cleanup to attempt manual cleanup"
            exit 1
        fi
    fi
    
    if ! jq empty "$STATE_FILE" 2>/dev/null; then
        log_error "State file is corrupted or invalid JSON"
        exit 1
    fi
    
    # Load variables from state file
    export API_ID=$(jq -r '.api_id // empty' "$STATE_FILE")
    export API_NAME=$(jq -r '.api_name // empty' "$STATE_FILE")
    export TABLE_NAME=$(jq -r '.table_name // empty' "$STATE_FILE")
    export ROLE_NAME=$(jq -r '.role_name // empty' "$STATE_FILE")
    export AWS_REGION=$(jq -r '.region // empty' "$STATE_FILE")
    export API_KEY=$(jq -r '.api_key // empty' "$STATE_FILE")
    
    log_success "Deployment state loaded:"
    [ -n "$API_ID" ] && log_info "  API ID: $API_ID"
    [ -n "$API_NAME" ] && log_info "  API Name: $API_NAME"
    [ -n "$TABLE_NAME" ] && log_info "  Table Name: $TABLE_NAME"
    [ -n "$ROLE_NAME" ] && log_info "  Role Name: $ROLE_NAME"
    [ -n "$AWS_REGION" ] && log_info "  Region: $AWS_REGION"
    
    return 0
}

# Manual resource specification for partial cleanup
manual_resource_input() {
    if [ "$FORCE" = true ]; then
        log_error "Cannot use --force with --partial-cleanup (manual input required)"
        exit 1
    fi
    
    log_info "Manual resource specification required"
    
    echo -n "Enter AppSync API ID (or press Enter to skip): "
    read -r API_ID
    
    echo -n "Enter DynamoDB table name (or press Enter to skip): "
    read -r TABLE_NAME
    
    echo -n "Enter IAM role name (or press Enter to skip): "
    read -r ROLE_NAME
    
    echo -n "Enter AWS region (default: current configured region): "
    read -r input_region
    export AWS_REGION=${input_region:-$(aws configure get region)}
    
    log_info "Manual input completed"
}

# Confirmation prompts
confirm_deletion() {
    if [ "$FORCE" = true ]; then
        log_info "Force mode enabled, skipping confirmations"
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry run mode, no confirmations needed"
        return 0
    fi
    
    echo ""
    log_warning "⚠️  WARNING: This will permanently delete the following resources:"
    
    [ -n "$API_ID" ] && echo "  - AppSync API: $API_ID ($API_NAME)"
    [ -n "$TABLE_NAME" ] && echo "  - DynamoDB Table: $TABLE_NAME (including all data)"
    [ -n "$ROLE_NAME" ] && echo "  - IAM Role: $ROLE_NAME (and attached policies)"
    echo "  - All associated resolvers, data sources, and API keys"
    echo ""
    
    echo -n "Are you sure you want to proceed? (type 'yes' to confirm): "
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log_warning "Final confirmation: This action cannot be undone!"
    echo -n "Type 'DELETE' to proceed: "
    read -r final_confirmation
    
    if [ "$final_confirmation" != "DELETE" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed deletion, proceeding with cleanup"
}

# Verify AWS credentials and permissions
verify_aws_access() {
    log_info "Verifying AWS access..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    log_info "AWS Account: $account_id"
    
    # Set region if not already set
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            log_warning "No region found, defaulting to us-east-1"
        fi
    fi
    
    log_info "AWS Region: $AWS_REGION"
    log_success "AWS access verified"
}

# Delete AppSync API and related resources
delete_appsync_api() {
    if [ -z "$API_ID" ]; then
        log_warning "No AppSync API ID provided, skipping AppSync deletion"
        return 0
    fi
    
    log_info "Deleting AppSync API: $API_ID"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete AppSync API and all related resources"
        return 0
    fi
    
    # Check if API exists
    if ! aws appsync get-graphql-api --api-id "$API_ID" &> /dev/null; then
        log_warning "AppSync API $API_ID not found, may have been deleted already"
        return 0
    fi
    
    # Delete AppSync API (this automatically deletes resolvers, data sources, and API keys)
    if aws appsync delete-graphql-api --api-id "$API_ID" &> /dev/null; then
        log_success "AppSync API $API_ID deleted successfully"
        
        # Wait a moment for deletion to propagate
        sleep 5
    else
        log_error "Failed to delete AppSync API $API_ID"
        log_error "You may need to delete it manually from the AWS Console"
    fi
}

# Delete DynamoDB table
delete_dynamodb_table() {
    if [ -z "$TABLE_NAME" ]; then
        log_warning "No DynamoDB table name provided, skipping table deletion"
        return 0
    fi
    
    log_info "Deleting DynamoDB table: $TABLE_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete DynamoDB table and all data"
        return 0
    fi
    
    # Check if table exists
    if ! aws dynamodb describe-table --table-name "$TABLE_NAME" &> /dev/null; then
        log_warning "DynamoDB table $TABLE_NAME not found, may have been deleted already"
        return 0
    fi
    
    # Delete table
    if aws dynamodb delete-table --table-name "$TABLE_NAME" &> /dev/null; then
        log_info "DynamoDB table deletion initiated"
        
        # Wait for table deletion (with timeout)
        log_info "Waiting for table deletion to complete..."
        local timeout=300  # 5 minutes
        local elapsed=0
        
        while [ $elapsed -lt $timeout ]; do
            if ! aws dynamodb describe-table --table-name "$TABLE_NAME" &> /dev/null; then
                log_success "DynamoDB table $TABLE_NAME deleted successfully"
                return 0
            fi
            sleep 10
            elapsed=$((elapsed + 10))
            
            if [ $((elapsed % 60)) -eq 0 ]; then
                log_info "Still waiting for table deletion... ($((elapsed/60)) minutes elapsed)"
            fi
        done
        
        log_warning "Table deletion taking longer than expected, but deletion is in progress"
    else
        log_error "Failed to delete DynamoDB table $TABLE_NAME"
        log_error "You may need to delete it manually from the AWS Console"
    fi
}

# Delete IAM role and policies
delete_iam_role() {
    if [ -z "$ROLE_NAME" ]; then
        log_warning "No IAM role name provided, skipping role deletion"
        return 0
    fi
    
    log_info "Deleting IAM role: $ROLE_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete IAM role and attached policies"
        return 0
    fi
    
    # Check if role exists
    if ! aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        log_warning "IAM role $ROLE_NAME not found, may have been deleted already"
        return 0
    fi
    
    # Delete inline policies first
    log_info "Deleting inline policies from role..."
    local policies=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[]' --output text)
    
    for policy in $policies; do
        if [ -n "$policy" ] && [ "$policy" != "None" ]; then
            log_info "Deleting policy: $policy"
            aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$policy" || \
                log_warning "Failed to delete policy $policy"
        fi
    done
    
    # Detach managed policies
    log_info "Detaching managed policies from role..."
    local attached_policies=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text)
    
    for policy_arn in $attached_policies; do
        if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
            log_info "Detaching policy: $policy_arn"
            aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy_arn" || \
                log_warning "Failed to detach policy $policy_arn"
        fi
    done
    
    # Delete the role
    if aws iam delete-role --role-name "$ROLE_NAME" &> /dev/null; then
        log_success "IAM role $ROLE_NAME deleted successfully"
    else
        log_error "Failed to delete IAM role $ROLE_NAME"
        log_error "You may need to delete it manually from the AWS Console"
    fi
}

# Clean up CloudWatch logs (optional)
cleanup_cloudwatch_logs() {
    if [ "$KEEP_LOGS" = true ]; then
        log_info "Keeping CloudWatch logs as requested"
        return 0
    fi
    
    if [ -z "$API_ID" ]; then
        log_warning "No API ID available, skipping CloudWatch log cleanup"
        return 0
    fi
    
    log_info "Cleaning up CloudWatch logs..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete AppSync CloudWatch log groups"
        return 0
    fi
    
    local log_group="/aws/appsync/apis/${API_ID}"
    
    # Check if log group exists
    if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0]' --output text | grep -q "$log_group"; then
        log_info "Deleting CloudWatch log group: $log_group"
        
        if aws logs delete-log-group --log-group-name "$log_group" &> /dev/null; then
            log_success "CloudWatch log group deleted"
        else
            log_warning "Failed to delete CloudWatch log group (may not exist or have different permissions)"
        fi
    else
        log_info "No CloudWatch log groups found for this API"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would delete temporary files"
        return 0
    fi
    
    local temp_files=(
        "trust-policy.json"
        "dynamodb-policy.json"
        "schema.graphql"
        "*-request.vtl"
        "*-response.vtl"
    )
    
    for pattern in "${temp_files[@]}"; do
        # Use find to handle glob patterns safely
        find "$SCRIPT_DIR" -maxdepth 1 -name "$pattern" -type f 2>/dev/null | while read -r file; do
            if [ -f "$file" ]; then
                rm -f "$file"
                log_info "Deleted: $(basename "$file")"
            fi
        done
    done
    
    log_success "Temporary files cleaned up"
}

# Update state file
update_state_file() {
    if [ ! -f "$STATE_FILE" ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    log_info "Updating state file to reflect cleanup"
    
    # Mark as destroyed
    jq '.status = "destroyed" | .destruction_time = now' \
       "$STATE_FILE" > "${STATE_FILE}.tmp" && \
       mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    log_info "State file updated"
}

# Generate cleanup report
generate_cleanup_report() {
    log_info "Generating cleanup report..."
    
    local report_file="${SCRIPT_DIR}/cleanup-report.txt"
    
    cat > "$report_file" << EOF
=== AWS AppSync Real-time Data Synchronization Cleanup Report ===

Cleanup completed at: $(date)

Resources Processed:
$([ -n "$API_ID" ] && echo "- AppSync API: $API_ID" || echo "- AppSync API: Not specified")
$([ -n "$TABLE_NAME" ] && echo "- DynamoDB Table: $TABLE_NAME" || echo "- DynamoDB Table: Not specified")
$([ -n "$ROLE_NAME" ] && echo "- IAM Role: $ROLE_NAME" || echo "- IAM Role: Not specified")

Options Used:
- Dry Run: $DRY_RUN
- Force Mode: $FORCE
- Keep Logs: $KEEP_LOGS
- Partial Cleanup: $PARTIAL_CLEANUP

Files:
- Cleanup log: $(basename "$LOG_FILE")
$([ -f "$ERROR_LOG" ] && echo "- Error log: $(basename "$ERROR_LOG")" || echo "- No errors logged")
- State file: $([ -f "$STATE_FILE" ] && echo "Updated" || echo "Not found")

$(if [ "$DRY_RUN" = true ]; then
    echo "NOTE: This was a dry run - no resources were actually deleted"
else
    echo "All specified resources have been processed for deletion"
    echo "Verify in AWS Console that all resources are properly removed"
fi)

EOF
    
    log_success "Cleanup report generated: $report_file"
    
    if [ "$VERBOSE" = true ]; then
        echo ""
        log_info "Cleanup Report:"
        cat "$report_file"
    fi
}

# Main cleanup function
main() {
    log_info "Starting main cleanup flow"
    
    # Verify AWS access
    verify_aws_access
    
    # Load state or get manual input
    if ! load_deployment_state; then
        manual_resource_input
    fi
    
    # Confirm deletion
    confirm_deletion
    
    # Perform cleanup in reverse order of creation
    delete_appsync_api
    delete_dynamodb_table
    delete_iam_role
    cleanup_cloudwatch_logs
    cleanup_temp_files
    
    # Finalize
    update_state_file
    generate_cleanup_report
    
    log_success "Cleanup completed successfully!"
    
    if [ "$DRY_RUN" = false ]; then
        log_info "Please verify in AWS Console that all resources are properly removed"
    fi
}

# Run main function
main "$@"

# Disable error trap for successful completion
trap - EXIT