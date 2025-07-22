#!/bin/bash

# Destroy script for Automated File Lifecycle Management with Amazon FSx Intelligent-Tiering and Lambda
# This script safely removes all infrastructure created by the deploy script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Script metadata
SCRIPT_NAME="FSx Lifecycle Management Cleanup"
SCRIPT_VERSION="1.0"
RECIPE_NAME="automated-file-lifecycle-management-fsx-intelligent-tiering-lambda"

log "Starting $SCRIPT_NAME v$SCRIPT_VERSION"

# Check parameters
FORCE_DELETE=${1:-""}
RESOURCE_SUFFIX=${2:-""}

if [[ "$FORCE_DELETE" == "--help" ]] || [[ "$FORCE_DELETE" == "-h" ]]; then
    echo "Usage: $0 [--force] [RESOURCE_SUFFIX]"
    echo ""
    echo "Options:"
    echo "  --force              Skip confirmation prompts (dangerous!)"
    echo "  RESOURCE_SUFFIX      Specify the suffix used during deployment"
    echo ""
    echo "Examples:"
    echo "  $0                   Interactive cleanup (will ask for suffix)"
    echo "  $0 --force abc123    Force cleanup resources with suffix 'abc123'"
    echo "  $0 abc123           Cleanup resources with suffix 'abc123'"
    echo ""
    echo "Note: This script will permanently delete AWS resources. Use with caution!"
    exit 0
fi

# Set force mode
if [[ "$FORCE_DELETE" == "--force" ]]; then
    FORCE_MODE=true
    RESOURCE_SUFFIX=${2:-""}
else
    FORCE_MODE=false
    if [[ -n "$FORCE_DELETE" ]]; then
        RESOURCE_SUFFIX="$FORCE_DELETE"
    fi
fi

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is required but not installed"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
    fi
    
    # Check if we're in the correct directory
    if [[ ! -f "../../${RECIPE_NAME}.md" ]]; then
        error "Script must be run from the scripts directory within the recipe code folder"
    fi
    
    success "Prerequisites check completed"
}

# Get resource suffix
get_resource_suffix() {
    if [[ -z "$RESOURCE_SUFFIX" ]]; then
        log "Available FSx file systems with lifecycle management pattern:"
        
        # List FSx file systems that match our naming pattern
        aws fsx describe-file-systems \
            --query "FileSystems[?contains(Tags[?Key=='Name'].Value, 'fsx-lifecycle-')].{Name:Tags[?Key=='Name']|[0].Value,FileSystemId:FileSystemId,State:Lifecycle}" \
            --output table 2>/dev/null || echo "No matching FSx file systems found"
        
        echo ""
        echo "Available Lambda functions with FSx lifecycle pattern:"
        
        # List relevant Lambda functions
        aws lambda list-functions \
            --query "Functions[?contains(FunctionName, 'fsx-')].{FunctionName:FunctionName,LastModified:LastModified}" \
            --output table 2>/dev/null || echo "No matching Lambda functions found"
        
        echo ""
        if [[ "$FORCE_MODE" == "false" ]]; then
            echo "Please enter the resource suffix used during deployment (e.g., 'abc123'):"
            read -r RESOURCE_SUFFIX
            
            if [[ -z "$RESOURCE_SUFFIX" ]]; then
                error "Resource suffix cannot be empty"
            fi
        else
            error "Resource suffix must be provided when using --force mode"
        fi
    fi
    
    log "Using resource suffix: $RESOURCE_SUFFIX"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warn "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Set resource names based on suffix
    export FSX_FILE_SYSTEM_NAME="fsx-lifecycle-${RESOURCE_SUFFIX}"
    export LAMBDA_ROLE_NAME="FSxLifecycleRole-${RESOURCE_SUFFIX}"
    export SNS_TOPIC_NAME="fsx-lifecycle-alerts-${RESOURCE_SUFFIX}"
    export S3_BUCKET_NAME="fsx-lifecycle-reports-${RESOURCE_SUFFIX}"
    
    log "Environment initialized:"
    log "  Region: $AWS_REGION"
    log "  Account: $AWS_ACCOUNT_ID"
    log "  Suffix: $RESOURCE_SUFFIX"
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE_MODE" == "true" ]]; then
        warn "FORCE MODE: Skipping confirmation prompts"
        return
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                            ⚠️  DANGER ZONE ⚠️"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    warn "This script will permanently delete the following resources:"
    echo ""
    echo "🗄️  FSx File System:"
    echo "   • Name: $FSX_FILE_SYSTEM_NAME"
    echo "   • ALL DATA WILL BE PERMANENTLY LOST"
    echo ""
    echo "🔧 Lambda Functions:"
    echo "   • fsx-lifecycle-policy"
    echo "   • fsx-cost-reporting"
    echo "   • fsx-alert-handler"
    echo ""
    echo "📊 Monitoring & Automation:"
    echo "   • EventBridge rules and targets"
    echo "   • CloudWatch alarms and dashboard"
    echo "   • SNS topic and subscriptions"
    echo ""
    echo "🔐 IAM Resources:"
    echo "   • Role: $LAMBDA_ROLE_NAME"
    echo "   • Associated policies"
    echo ""
    echo "💾 Storage:"
    echo "   • S3 bucket: $S3_BUCKET_NAME (including all reports)"
    echo "   • Security groups for FSx"
    echo ""
    echo "💰 This action will:"
    echo "   ✅ Stop all recurring charges"
    echo "   ❌ Permanently delete all file system data"
    echo "   ❌ Remove all cost optimization reports"
    echo "   ❌ Cannot be undone"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    echo "Type 'DELETE' in all caps to confirm deletion:"
    read -r confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    echo ""
    echo "Are you absolutely sure? This will delete the FSx file system and ALL DATA."
    echo "Type the resource suffix '$RESOURCE_SUFFIX' to confirm:"
    read -r suffix_confirmation
    
    if [[ "$suffix_confirmation" != "$RESOURCE_SUFFIX" ]]; then
        log "Deletion cancelled - suffix mismatch"
        exit 0
    fi
    
    warn "Proceeding with deletion in 5 seconds... (Press Ctrl+C to cancel)"
    sleep 5
}

# Find and store FSx file system ID
get_fsx_file_system_id() {
    log "Finding FSx file system..."
    
    export FSX_FILE_SYSTEM_ID=$(aws fsx describe-file-systems \
        --query "FileSystems[?Tags[?Key=='Name' && Value=='${FSX_FILE_SYSTEM_NAME}']].FileSystemId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$FSX_FILE_SYSTEM_ID" || "$FSX_FILE_SYSTEM_ID" == "None" ]]; then
        warn "FSx file system not found: $FSX_FILE_SYSTEM_NAME"
        FSX_FILE_SYSTEM_ID=""
    else
        log "Found FSx file system: $FSX_FILE_SYSTEM_ID"
    fi
}

# Delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    local functions=("fsx-lifecycle-policy" "fsx-cost-reporting" "fsx-alert-handler")
    
    for func in "${functions[@]}"; do
        if aws lambda get-function --function-name "$func" &> /dev/null; then
            aws lambda delete-function --function-name "$func"
            success "Deleted Lambda function: $func"
        else
            warn "Lambda function not found: $func"
        fi
    done
}

# Delete EventBridge rules
delete_eventbridge_rules() {
    log "Deleting EventBridge rules..."
    
    local rules=("fsx-lifecycle-policy-schedule" "fsx-cost-reporting-schedule")
    
    for rule in "${rules[@]}"; do
        if aws events describe-rule --name "$rule" &> /dev/null; then
            # Remove targets first
            local target_ids=$(aws events list-targets-by-rule --rule "$rule" \
                --query 'Targets[].Id' --output text 2>/dev/null || echo "")
            
            if [[ -n "$target_ids" ]]; then
                for target_id in $target_ids; do
                    aws events remove-targets --rule "$rule" --ids "$target_id"
                done
            fi
            
            # Delete rule
            aws events delete-rule --name "$rule"
            success "Deleted EventBridge rule: $rule"
        else
            warn "EventBridge rule not found: $rule"
        fi
    done
}

# Delete CloudWatch alarms and dashboard
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete alarms
    local alarms=(
        "FSx-Low-Cache-Hit-Ratio-${RESOURCE_SUFFIX}"
        "FSx-High-Storage-Utilization-${RESOURCE_SUFFIX}"
        "FSx-High-Network-Utilization-${RESOURCE_SUFFIX}"
    )
    
    local existing_alarms=""
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" \
            --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -v "None"; then
            existing_alarms="$existing_alarms $alarm"
        fi
    done
    
    if [[ -n "$existing_alarms" ]]; then
        aws cloudwatch delete-alarms --alarm-names $existing_alarms
        success "Deleted CloudWatch alarms"
    else
        warn "No CloudWatch alarms found to delete"
    fi
    
    # Delete dashboard
    local dashboard_name="FSx-Lifecycle-Management-${RESOURCE_SUFFIX}"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" &> /dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name"
        success "Deleted CloudWatch dashboard: $dashboard_name"
    else
        warn "CloudWatch dashboard not found: $dashboard_name"
    fi
}

# Delete FSx file system
delete_fsx_filesystem() {
    log "Deleting FSx file system..."
    
    if [[ -z "$FSX_FILE_SYSTEM_ID" ]]; then
        warn "No FSx file system to delete"
        return
    fi
    
    # Check current state
    local fs_state=$(aws fsx describe-file-systems \
        --file-system-ids "$FSX_FILE_SYSTEM_ID" \
        --query 'FileSystems[0].Lifecycle' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$fs_state" == "NOT_FOUND" ]]; then
        warn "FSx file system not found or already deleted"
        return
    fi
    
    if [[ "$fs_state" == "DELETING" ]]; then
        warn "FSx file system is already being deleted"
        return
    fi
    
    if [[ "$fs_state" != "AVAILABLE" ]]; then
        warn "FSx file system is in state: $fs_state - attempting deletion anyway"
    fi
    
    log "Deleting FSx file system: $FSX_FILE_SYSTEM_ID"
    aws fsx delete-file-system --file-system-id "$FSX_FILE_SYSTEM_ID"
    
    # Wait for deletion to complete
    log "Waiting for FSx file system deletion to complete (this may take several minutes)..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local current_state=$(aws fsx describe-file-systems \
            --file-system-ids "$FSX_FILE_SYSTEM_ID" \
            --query 'FileSystems[0].Lifecycle' \
            --output text 2>/dev/null || echo "DELETED")
        
        if [[ "$current_state" == "DELETED" ]] || [[ "$current_state" == "None" ]]; then
            success "FSx file system deletion completed"
            break
        fi
        
        log "FSx deletion state: $current_state (attempt $attempt/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        warn "Timeout waiting for FSx deletion - check AWS console"
    fi
}

# Delete security group
delete_security_group() {
    log "Deleting security group..."
    
    local sg_name="fsx-sg-${RESOURCE_SUFFIX}"
    local sg_id=$(aws ec2 describe-security-groups \
        --filters Name=group-name,Values="$sg_name" \
        --query SecurityGroups[0].GroupId --output text 2>/dev/null || echo "None")
    
    if [[ "$sg_id" != "None" && -n "$sg_id" ]]; then
        # Wait a bit to ensure FSx is fully deleted before removing security group
        sleep 10
        
        aws ec2 delete-security-group --group-id "$sg_id"
        success "Deleted security group: $sg_name"
    else
        warn "Security group not found: $sg_name"
    fi
}

# Delete SNS resources
delete_sns_resources() {
    log "Deleting SNS resources..."
    
    local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    
    if aws sns get-topic-attributes --topic-arn "$topic_arn" &> /dev/null; then
        # List and delete subscriptions first
        local subscriptions=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$topic_arn" \
            --query 'Subscriptions[].SubscriptionArn' \
            --output text 2>/dev/null || echo "")
        
        for sub_arn in $subscriptions; do
            if [[ "$sub_arn" != "None" && -n "$sub_arn" ]]; then
                aws sns unsubscribe --subscription-arn "$sub_arn" 2>/dev/null || true
            fi
        done
        
        # Delete topic
        aws sns delete-topic --topic-arn "$topic_arn"
        success "Deleted SNS topic: $SNS_TOPIC_NAME"
    else
        warn "SNS topic not found: $SNS_TOPIC_NAME"
    fi
}

# Delete S3 bucket and contents
delete_s3_resources() {
    log "Deleting S3 resources..."
    
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" &> /dev/null; then
        # Delete all objects first
        log "Deleting all objects in S3 bucket..."
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive --quiet
        
        # Delete the bucket
        aws s3 rb "s3://${S3_BUCKET_NAME}"
        success "Deleted S3 bucket: $S3_BUCKET_NAME"
    else
        warn "S3 bucket not found: $S3_BUCKET_NAME"
    fi
}

# Delete IAM role
delete_iam_role() {
    log "Deleting IAM role..."
    
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        # Detach managed policies
        local attached_policies=$(aws iam list-attached-role-policies \
            --role-name "$LAMBDA_ROLE_NAME" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in $attached_policies; do
            aws iam detach-role-policy \
                --role-name "$LAMBDA_ROLE_NAME" \
                --policy-arn "$policy_arn"
        done
        
        # Delete inline policies
        local inline_policies=$(aws iam list-role-policies \
            --role-name "$LAMBDA_ROLE_NAME" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        for policy_name in $inline_policies; do
            aws iam delete-role-policy \
                --role-name "$LAMBDA_ROLE_NAME" \
                --policy-name "$policy_name"
        done
        
        # Delete the role
        aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"
        success "Deleted IAM role: $LAMBDA_ROLE_NAME"
    else
        warn "IAM role not found: $LAMBDA_ROLE_NAME"
    fi
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local issues_found=false
    
    # Check FSx file system
    if [[ -n "$FSX_FILE_SYSTEM_ID" ]]; then
        local fs_state=$(aws fsx describe-file-systems \
            --file-system-ids "$FSX_FILE_SYSTEM_ID" \
            --query 'FileSystems[0].Lifecycle' \
            --output text 2>/dev/null || echo "DELETED")
        
        if [[ "$fs_state" != "DELETED" && "$fs_state" != "None" ]]; then
            warn "FSx file system still exists: $FSX_FILE_SYSTEM_ID (state: $fs_state)"
            issues_found=true
        fi
    fi
    
    # Check Lambda functions
    local functions=("fsx-lifecycle-policy" "fsx-cost-reporting" "fsx-alert-handler")
    for func in "${functions[@]}"; do
        if aws lambda get-function --function-name "$func" &> /dev/null; then
            warn "Lambda function still exists: $func"
            issues_found=true
        fi
    done
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" &> /dev/null; then
        warn "S3 bucket still exists: $S3_BUCKET_NAME"
        issues_found=true
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        warn "IAM role still exists: $LAMBDA_ROLE_NAME"
        issues_found=true
    fi
    
    if [[ "$issues_found" == "false" ]]; then
        success "Cleanup verification completed - all resources have been removed"
    else
        warn "Some resources may still exist - check AWS console for manual cleanup"
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed!"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                       CLEANUP SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🗑️  Resources Deleted:"
    echo ""
    echo "   📁 FSx File System:     $FSX_FILE_SYSTEM_NAME"
    echo "   🔧 Lambda Functions:    fsx-lifecycle-policy, fsx-cost-reporting, fsx-alert-handler"
    echo "   ⏰ EventBridge Rules:   fsx-lifecycle-policy-schedule, fsx-cost-reporting-schedule"
    echo "   🚨 CloudWatch Alarms:   FSx monitoring alarms"
    echo "   📊 CloudWatch Dashboard: FSx-Lifecycle-Management-$RESOURCE_SUFFIX"
    echo "   📧 SNS Topic:           $SNS_TOPIC_NAME"
    echo "   💾 S3 Bucket:           $S3_BUCKET_NAME (including all reports)"
    echo "   🔐 IAM Role:            $LAMBDA_ROLE_NAME"
    echo "   🛡️  Security Group:      fsx-sg-$RESOURCE_SUFFIX"
    echo ""
    echo "💰 Cost Impact:"
    echo "   ✅ All recurring charges have been stopped"
    echo "   ✅ No further costs will be incurred from these resources"
    echo ""
    echo "⚠️  Important Notes:"
    echo "   • All FSx file system data has been permanently deleted"
    echo "   • All cost optimization reports have been removed"
    echo "   • This action cannot be undone"
    echo "   • If you need the data, you must restore from backups (if any exist)"
    echo ""
    echo "🔍 Verification:"
    echo "   • Check AWS Console to confirm all resources are removed"
    echo "   • Monitor your AWS bill to ensure charges have stopped"
    echo ""
    echo "✅ Cleanup operation completed successfully!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main execution flow
main() {
    check_prerequisites
    get_resource_suffix
    initialize_environment
    get_fsx_file_system_id
    confirm_deletion
    
    log "Starting resource deletion process..."
    
    # Delete resources in reverse order of creation
    delete_lambda_functions
    delete_eventbridge_rules
    delete_cloudwatch_resources
    delete_fsx_filesystem
    delete_security_group
    delete_sns_resources
    delete_s3_resources
    delete_iam_role
    
    # Verify cleanup
    verify_cleanup
    display_cleanup_summary
}

# Cleanup temporary files on exit
cleanup() {
    rm -f /tmp/trust-policy.json /tmp/fsx-policy.json /tmp/dashboard-config.json 2>/dev/null || true
}
trap cleanup EXIT

# Run main function
main "$@"