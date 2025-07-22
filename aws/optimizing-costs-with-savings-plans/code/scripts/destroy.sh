#!/bin/bash

# AWS Savings Plans Recommendations with Cost Explorer - Cleanup Script
# This script removes all resources created by the deployment script

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warn "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            info "Force delete enabled - will skip confirmation prompts"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --force      Skip confirmation prompts"
            echo "  -h, --help   Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

log "Starting AWS Savings Plans Recommendations cleanup..."

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
    fi
    
    log "Prerequisites check completed successfully"
}

# Set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warn "No default region found, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "Environment variables set successfully"
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Discover resources by pattern
discover_resources() {
    log "Discovering resources to cleanup..."
    
    # Find Lambda functions
    LAMBDA_FUNCTIONS=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `savings-plans-analyzer`)].FunctionName' \
        --output text)
    
    # Find S3 buckets
    S3_BUCKETS=$(aws s3api list-buckets \
        --query 'Buckets[?contains(Name, `cost-recommendations`)].Name' \
        --output text)
    
    # Find IAM roles
    IAM_ROLES=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `SavingsPlansAnalyzerRole`)].RoleName' \
        --output text)
    
    # Find EventBridge rules
    EVENTBRIDGE_RULES=$(aws events list-rules \
        --query 'Rules[?contains(Name, `MonthlySavingsPlansAnalysis`)].Name' \
        --output text)
    
    # Find CloudWatch dashboards
    CLOUDWATCH_DASHBOARDS=$(aws cloudwatch list-dashboards \
        --query 'DashboardEntries[?contains(DashboardName, `SavingsPlansRecommendations`)].DashboardName' \
        --output text)
    
    info "Found resources to cleanup:"
    info "Lambda Functions: ${LAMBDA_FUNCTIONS:-none}"
    info "S3 Buckets: ${S3_BUCKETS:-none}"
    info "IAM Roles: ${IAM_ROLES:-none}"
    info "EventBridge Rules: ${EVENTBRIDGE_RULES:-none}"
    info "CloudWatch Dashboards: ${CLOUDWATCH_DASHBOARDS:-none}"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    warn "This will permanently delete all Savings Plans Recommendations resources!"
    warn "This action cannot be undone."
    echo
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
}

# Remove EventBridge rules and targets
remove_eventbridge_resources() {
    log "Removing EventBridge resources..."
    
    if [[ -z "$EVENTBRIDGE_RULES" ]]; then
        info "No EventBridge rules found to remove"
        return
    fi
    
    for rule in $EVENTBRIDGE_RULES; do
        info "Processing EventBridge rule: $rule"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY-RUN: Would remove EventBridge rule: $rule"
            continue
        fi
        
        # Get targets for the rule
        local targets=$(aws events list-targets-by-rule --rule "$rule" \
            --query 'Targets[].Id' --output text 2>/dev/null || true)
        
        if [[ -n "$targets" ]]; then
            info "Removing targets from rule: $rule"
            
            # Remove targets
            for target_id in $targets; do
                aws events remove-targets --rule "$rule" --ids "$target_id" || true
            done
            
            # Wait for targets to be removed
            sleep 2
        fi
        
        # Remove the rule
        aws events delete-rule --name "$rule" || true
        
        log "EventBridge rule removed: $rule"
    done
}

# Remove Lambda functions
remove_lambda_functions() {
    log "Removing Lambda functions..."
    
    if [[ -z "$LAMBDA_FUNCTIONS" ]]; then
        info "No Lambda functions found to remove"
        return
    fi
    
    for function in $LAMBDA_FUNCTIONS; do
        info "Processing Lambda function: $function"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY-RUN: Would remove Lambda function: $function"
            continue
        fi
        
        # Remove any resource-based policies
        aws lambda remove-permission \
            --function-name "$function" \
            --statement-id "AllowEventBridgeInvoke" 2>/dev/null || true
        
        # Remove the function
        aws lambda delete-function --function-name "$function" || true
        
        log "Lambda function removed: $function"
    done
}

# Remove IAM roles and policies
remove_iam_resources() {
    log "Removing IAM resources..."
    
    if [[ -z "$IAM_ROLES" ]]; then
        info "No IAM roles found to remove"
        return
    fi
    
    for role in $IAM_ROLES; do
        info "Processing IAM role: $role"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY-RUN: Would remove IAM role: $role"
            continue
        fi
        
        # List and detach managed policies
        local managed_policies=$(aws iam list-attached-role-policies \
            --role-name "$role" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || true)
        
        if [[ -n "$managed_policies" ]]; then
            info "Detaching managed policies from role: $role"
            for policy_arn in $managed_policies; do
                aws iam detach-role-policy \
                    --role-name "$role" \
                    --policy-arn "$policy_arn" || true
            done
        fi
        
        # List and delete inline policies
        local inline_policies=$(aws iam list-role-policies \
            --role-name "$role" \
            --query 'PolicyNames[]' \
            --output text 2>/dev/null || true)
        
        if [[ -n "$inline_policies" ]]; then
            info "Removing inline policies from role: $role"
            for policy_name in $inline_policies; do
                aws iam delete-role-policy \
                    --role-name "$role" \
                    --policy-name "$policy_name" || true
            done
        fi
        
        # Delete the role
        aws iam delete-role --role-name "$role" || true
        
        log "IAM role removed: $role"
    done
}

# Remove S3 buckets
remove_s3_buckets() {
    log "Removing S3 buckets..."
    
    if [[ -z "$S3_BUCKETS" ]]; then
        info "No S3 buckets found to remove"
        return
    fi
    
    for bucket in $S3_BUCKETS; do
        info "Processing S3 bucket: $bucket"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY-RUN: Would remove S3 bucket: $bucket"
            continue
        fi
        
        # Check if bucket exists
        if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            warn "S3 bucket $bucket does not exist or is not accessible"
            continue
        fi
        
        # Remove all objects and versions
        info "Emptying S3 bucket: $bucket"
        
        # Delete all object versions
        aws s3api list-object-versions \
            --bucket "$bucket" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output json | \
        jq -r '.[]? | "\(.Key) \(.VersionId)"' | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object \
                    --bucket "$bucket" \
                    --key "$key" \
                    --version-id "$version_id" || true
            fi
        done
        
        # Delete all delete markers
        aws s3api list-object-versions \
            --bucket "$bucket" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output json | \
        jq -r '.[]? | "\(.Key) \(.VersionId)"' | \
        while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object \
                    --bucket "$bucket" \
                    --key "$key" \
                    --version-id "$version_id" || true
            fi
        done
        
        # Remove all current objects (fallback)
        aws s3 rm "s3://$bucket" --recursive || true
        
        # Remove bucket lifecycle configuration
        aws s3api delete-bucket-lifecycle --bucket "$bucket" 2>/dev/null || true
        
        # Remove bucket versioning
        aws s3api put-bucket-versioning \
            --bucket "$bucket" \
            --versioning-configuration Status=Suspended 2>/dev/null || true
        
        # Delete the bucket
        aws s3api delete-bucket --bucket "$bucket" || true
        
        log "S3 bucket removed: $bucket"
    done
}

# Remove CloudWatch dashboards
remove_cloudwatch_dashboards() {
    log "Removing CloudWatch dashboards..."
    
    if [[ -z "$CLOUDWATCH_DASHBOARDS" ]]; then
        info "No CloudWatch dashboards found to remove"
        return
    fi
    
    for dashboard in $CLOUDWATCH_DASHBOARDS; do
        info "Processing CloudWatch dashboard: $dashboard"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY-RUN: Would remove CloudWatch dashboard: $dashboard"
            continue
        fi
        
        # Delete the dashboard
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard" || true
        
        log "CloudWatch dashboard removed: $dashboard"
    done
}

# Remove CloudWatch log groups
remove_cloudwatch_logs() {
    log "Removing CloudWatch log groups..."
    
    if [[ -z "$LAMBDA_FUNCTIONS" ]]; then
        info "No Lambda functions found, skipping log group cleanup"
        return
    fi
    
    for function in $LAMBDA_FUNCTIONS; do
        local log_group="/aws/lambda/$function"
        
        info "Processing log group: $log_group"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "DRY-RUN: Would remove log group: $log_group"
            continue
        fi
        
        # Check if log group exists
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" \
            --query 'logGroups[?logGroupName==`'$log_group'`]' \
            --output text | grep -q "$log_group"; then
            
            # Delete log group
            aws logs delete-log-group --log-group-name "$log_group" || true
            
            log "CloudWatch log group removed: $log_group"
        else
            info "Log group not found: $log_group"
        fi
    done
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Skipping cleanup verification"
        return
    fi
    
    local cleanup_issues=0
    
    # Check Lambda functions
    local remaining_functions=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `savings-plans-analyzer`)].FunctionName' \
        --output text)
    
    if [[ -n "$remaining_functions" ]]; then
        warn "Some Lambda functions still exist: $remaining_functions"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check S3 buckets
    local remaining_buckets=$(aws s3api list-buckets \
        --query 'Buckets[?contains(Name, `cost-recommendations`)].Name' \
        --output text)
    
    if [[ -n "$remaining_buckets" ]]; then
        warn "Some S3 buckets still exist: $remaining_buckets"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check IAM roles
    local remaining_roles=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `SavingsPlansAnalyzerRole`)].RoleName' \
        --output text)
    
    if [[ -n "$remaining_roles" ]]; then
        warn "Some IAM roles still exist: $remaining_roles"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check EventBridge rules
    local remaining_rules=$(aws events list-rules \
        --query 'Rules[?contains(Name, `MonthlySavingsPlansAnalysis`)].Name' \
        --output text)
    
    if [[ -n "$remaining_rules" ]]; then
        warn "Some EventBridge rules still exist: $remaining_rules"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check CloudWatch dashboards
    local remaining_dashboards=$(aws cloudwatch list-dashboards \
        --query 'DashboardEntries[?contains(DashboardName, `SavingsPlansRecommendations`)].DashboardName' \
        --output text)
    
    if [[ -n "$remaining_dashboards" ]]; then
        warn "Some CloudWatch dashboards still exist: $remaining_dashboards"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log "Cleanup verification completed successfully - all resources removed"
    else
        warn "Cleanup verification found $cleanup_issues issues"
        warn "You may need to manually remove remaining resources"
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    log "Generating cleanup summary..."
    
    info "=== CLEANUP SUMMARY ==="
    info "Cleanup Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "Mode: $([ "$DRY_RUN" == "true" ] && echo "DRY-RUN" || echo "ACTUAL")"
    info "========================"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Resources that were removed:"
        info "- Lambda Functions: ${LAMBDA_FUNCTIONS:-none}"
        info "- S3 Buckets: ${S3_BUCKETS:-none}"
        info "- IAM Roles: ${IAM_ROLES:-none}"
        info "- EventBridge Rules: ${EVENTBRIDGE_RULES:-none}"
        info "- CloudWatch Dashboards: ${CLOUDWATCH_DASHBOARDS:-none}"
        info "- CloudWatch Log Groups: associated with Lambda functions"
        info "========================"
    fi
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    # No temporary files created during cleanup
}

# Main execution
main() {
    log "Starting AWS Savings Plans Recommendations cleanup..."
    
    # Run all cleanup steps
    check_prerequisites
    set_environment_variables
    discover_resources
    
    # Show what will be deleted
    if [[ -z "$LAMBDA_FUNCTIONS" && -z "$S3_BUCKETS" && -z "$IAM_ROLES" && -z "$EVENTBRIDGE_RULES" && -z "$CLOUDWATCH_DASHBOARDS" ]]; then
        info "No Savings Plans Recommendations resources found to cleanup"
        exit 0
    fi
    
    # Confirm deletion
    confirm_deletion
    
    # Remove resources in proper order
    remove_eventbridge_resources
    remove_lambda_functions
    remove_iam_resources
    remove_s3_buckets
    remove_cloudwatch_dashboards
    remove_cloudwatch_logs
    
    # Verify cleanup
    verify_cleanup
    
    # Generate summary
    generate_cleanup_summary
    
    # Cleanup temporary files
    cleanup_temp_files
    
    log "Cleanup completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "All Savings Plans Recommendations resources have been removed"
        info "You may want to:"
        info "1. Check AWS Console to verify all resources are gone"
        info "2. Review your AWS bill to ensure charges have stopped"
        info "3. Clear any local configuration files if needed"
    fi
}

# Run main function
main "$@"