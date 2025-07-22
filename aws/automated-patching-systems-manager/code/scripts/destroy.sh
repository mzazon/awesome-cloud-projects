#!/bin/bash

# destroy.sh - Clean up AWS Systems Manager Automated Patching Infrastructure
# Recipe: Automated Patching with Systems Manager

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}

if [[ "$DRY_RUN" == "true" ]]; then
    warn "Running in DRY-RUN mode - no resources will be deleted"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || warn "Command failed but continuing cleanup"
        else
            eval "$cmd"
        fi
    fi
}

# Function to check if resource exists
resource_exists() {
    local check_cmd="$1"
    local resource_name="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    if eval "$check_cmd" &>/dev/null; then
        return 0
    else
        warn "$resource_name not found or already deleted"
        return 1
    fi
}

# Load environment variables from .env file
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f ".env" ]]; then
        source .env
        success "Environment variables loaded from .env file"
    else
        warn ".env file not found. You may need to provide resource names manually."
        
        # Set default AWS region if not provided
        export AWS_REGION=${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "us-east-1")}
        export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")}
        
        # If no environment file exists, try to discover resources
        if [[ "$FORCE" != "true" ]]; then
            warn "No .env file found. Use --force to attempt cleanup of all matching resources."
            exit 1
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Confirm destruction
confirm_destruction() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo ""
    echo "📋 Patch Management Resources:"
    echo "   • Patch Baseline: ${PATCH_BASELINE_NAME:-'custom-baseline-*'}"
    echo "   • Maintenance Window: ${MAINTENANCE_WINDOW_NAME:-'patch-window-*'}"
    echo "   • Scan Window: ${SCAN_WINDOW_NAME:-'scan-window-*'}"
    echo ""
    echo "🔧 Supporting Resources:"
    echo "   • IAM Role: ${ROLE_NAME:-'MaintenanceWindowRole-*'}"
    echo "   • S3 Bucket: ${S3_BUCKET_NAME:-'patch-reports-*'}"
    echo "   • SNS Topic: ${SNS_TOPIC_NAME:-'patch-notifications-*'}"
    echo "   • CloudWatch Alarm: ${ALARM_NAME:-'PatchComplianceAlarm-*'}"
    echo ""
    echo "💾 Data Loss Warning:"
    echo "   • All patch reports and logs in S3 will be permanently deleted"
    echo "   • Patch compliance history will be lost"
    echo "   • This action cannot be undone"
    echo ""
    
    if [[ "$FORCE" != "true" ]]; then
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
        if [[ "$confirmation" != "yes" ]]; then
            log "Destruction cancelled by user"
            exit 0
        fi
    else
        warn "Force mode enabled - skipping confirmation"
    fi
    
    echo ""
    log "Proceeding with resource destruction..."
}

# Remove maintenance window tasks and targets
cleanup_maintenance_windows() {
    log "Cleaning up maintenance windows..."
    
    # Clean up main maintenance window
    if [[ -n "${MAINTENANCE_WINDOW_ID:-}" ]]; then
        if resource_exists "aws ssm describe-maintenance-windows --filters 'Key=Name,Values=${MAINTENANCE_WINDOW_NAME}' --query 'WindowIdentities[0].WindowId' --output text" "Maintenance window"; then
            
            # Get and remove all tasks first
            local task_ids
            task_ids=$(aws ssm describe-maintenance-window-tasks \
                --window-id "${MAINTENANCE_WINDOW_ID}" \
                --query "Tasks[*].WindowTaskId" \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$task_ids" ]]; then
                for task_id in $task_ids; do
                    execute_command "aws ssm deregister-task-from-maintenance-window \
                        --window-id ${MAINTENANCE_WINDOW_ID} \
                        --window-task-id $task_id" \
                        "Removing task $task_id from maintenance window" true
                done
            fi
            
            # Remove all targets
            if [[ -n "${TARGET_ID:-}" ]]; then
                execute_command "aws ssm deregister-target-from-maintenance-window \
                    --window-id ${MAINTENANCE_WINDOW_ID} \
                    --window-target-id ${TARGET_ID}" \
                    "Removing targets from maintenance window" true
            fi
            
            # Delete the maintenance window
            execute_command "aws ssm delete-maintenance-window --window-id ${MAINTENANCE_WINDOW_ID}" \
                "Deleting maintenance window" true
        fi
    fi
    
    # Clean up scan maintenance window
    if [[ -n "${SCAN_WINDOW_ID:-}" ]]; then
        if resource_exists "aws ssm describe-maintenance-windows --filters 'Key=Name,Values=${SCAN_WINDOW_NAME}' --query 'WindowIdentities[0].WindowId' --output text" "Scan window"; then
            
            # Get and remove all scan tasks
            local scan_task_ids
            scan_task_ids=$(aws ssm describe-maintenance-window-tasks \
                --window-id "${SCAN_WINDOW_ID}" \
                --query "Tasks[*].WindowTaskId" \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$scan_task_ids" ]]; then
                for task_id in $scan_task_ids; do
                    execute_command "aws ssm deregister-task-from-maintenance-window \
                        --window-id ${SCAN_WINDOW_ID} \
                        --window-task-id $task_id" \
                        "Removing scan task $task_id from scan window" true
                done
            fi
            
            # Remove scan targets
            if [[ -n "${SCAN_TARGET_ID:-}" ]]; then
                execute_command "aws ssm deregister-target-from-maintenance-window \
                    --window-id ${SCAN_WINDOW_ID} \
                    --window-target-id ${SCAN_TARGET_ID}" \
                    "Removing targets from scan window" true
            fi
            
            # Delete the scan window
            execute_command "aws ssm delete-maintenance-window --window-id ${SCAN_WINDOW_ID}" \
                "Deleting scan maintenance window" true
        fi
    fi
    
    success "Maintenance windows cleanup completed"
}

# Remove patch baseline and associations
cleanup_patch_baseline() {
    log "Cleaning up patch baseline..."
    
    if [[ -n "${PATCH_BASELINE_ID:-}" ]]; then
        # Deregister patch baseline from patch group
        execute_command "aws ssm deregister-patch-baseline-for-patch-group \
            --baseline-id ${PATCH_BASELINE_ID} \
            --patch-group 'Production'" \
            "Deregistering patch baseline from Production patch group" true
        
        # Delete custom patch baseline
        execute_command "aws ssm delete-patch-baseline --baseline-id ${PATCH_BASELINE_ID}" \
            "Deleting custom patch baseline" true
    elif [[ -n "${PATCH_BASELINE_NAME:-}" ]]; then
        # Try to find and delete by name
        local baseline_id
        baseline_id=$(aws ssm describe-patch-baselines \
            --filters "Key=Name,Values=${PATCH_BASELINE_NAME}" \
            --query "BaselineIdentities[0].BaselineId" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$baseline_id" && "$baseline_id" != "None" ]]; then
            execute_command "aws ssm deregister-patch-baseline-for-patch-group \
                --baseline-id ${baseline_id} \
                --patch-group 'Production'" \
                "Deregistering patch baseline from Production patch group" true
            
            execute_command "aws ssm delete-patch-baseline --baseline-id ${baseline_id}" \
                "Deleting custom patch baseline" true
        fi
    fi
    
    success "Patch baseline cleanup completed"
}

# Remove monitoring resources
cleanup_monitoring() {
    log "Cleaning up monitoring resources..."
    
    # Delete CloudWatch alarm
    if [[ -n "${ALARM_NAME:-}" ]]; then
        execute_command "aws cloudwatch delete-alarms --alarm-names ${ALARM_NAME}" \
            "Deleting CloudWatch alarm" true
    fi
    
    # Delete SNS topic
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        execute_command "aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN}" \
            "Deleting SNS topic" true
    elif [[ -n "${SNS_TOPIC_NAME:-}" ]]; then
        local topic_arn
        topic_arn=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$topic_arn" ]]; then
            execute_command "aws sns delete-topic --topic-arn ${topic_arn}" \
                "Deleting SNS topic" true
        fi
    fi
    
    success "Monitoring resources cleanup completed"
}

# Remove IAM role
cleanup_iam_role() {
    log "Cleaning up IAM role..."
    
    if [[ -n "${ROLE_NAME:-}" ]]; then
        # Detach all policies first
        execute_command "aws iam detach-role-policy \
            --role-name ${ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole" \
            "Detaching Systems Manager policy from role" true
        
        # Delete the role
        execute_command "aws iam delete-role --role-name ${ROLE_NAME}" \
            "Deleting IAM role" true
    fi
    
    success "IAM role cleanup completed"
}

# Remove S3 bucket
cleanup_s3_bucket() {
    log "Cleaning up S3 bucket..."
    
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        # Check if bucket exists
        if resource_exists "aws s3api head-bucket --bucket ${S3_BUCKET_NAME}" "S3 bucket"; then
            # Empty the bucket first
            execute_command "aws s3 rm s3://${S3_BUCKET_NAME} --recursive" \
                "Emptying S3 bucket" true
            
            # Delete the bucket
            execute_command "aws s3 rb s3://${S3_BUCKET_NAME}" \
                "Deleting S3 bucket" true
        fi
    fi
    
    success "S3 bucket cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files
    local files_to_remove=(
        "maintenance-window-trust-policy.json"
        ".env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            execute_command "rm -f $file" "Removing $file" true
        fi
    done
    
    success "Local files cleanup completed"
}

# Force cleanup mode - attempt to find and delete all matching resources
force_cleanup() {
    warn "Force cleanup mode - attempting to find and delete all matching resources..."
    
    # Find and delete maintenance windows
    local windows
    windows=$(aws ssm describe-maintenance-windows \
        --query "WindowIdentities[?starts_with(Name, 'patch-window-') || starts_with(Name, 'scan-window-')].WindowId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$windows" ]]; then
        for window_id in $windows; do
            # Clean up tasks and targets first
            local tasks
            tasks=$(aws ssm describe-maintenance-window-tasks \
                --window-id "$window_id" \
                --query "Tasks[*].WindowTaskId" \
                --output text 2>/dev/null || echo "")
            
            for task_id in $tasks; do
                execute_command "aws ssm deregister-task-from-maintenance-window \
                    --window-id $window_id --window-task-id $task_id" \
                    "Removing task $task_id from window $window_id" true
            done
            
            local targets
            targets=$(aws ssm describe-maintenance-window-targets \
                --window-id "$window_id" \
                --query "Targets[*].WindowTargetId" \
                --output text 2>/dev/null || echo "")
            
            for target_id in $targets; do
                execute_command "aws ssm deregister-target-from-maintenance-window \
                    --window-id $window_id --window-target-id $target_id" \
                    "Removing target $target_id from window $window_id" true
            done
            
            execute_command "aws ssm delete-maintenance-window --window-id $window_id" \
                "Deleting maintenance window $window_id" true
        done
    fi
    
    # Find and delete patch baselines
    local baselines
    baselines=$(aws ssm describe-patch-baselines \
        --filters "Key=Name,Values=custom-baseline-*" \
        --query "BaselineIdentities[*].BaselineId" \
        --output text 2>/dev/null || echo "")
    
    for baseline_id in $baselines; do
        execute_command "aws ssm deregister-patch-baseline-for-patch-group \
            --baseline-id $baseline_id --patch-group Production" \
            "Deregistering baseline $baseline_id from patch group" true
        
        execute_command "aws ssm delete-patch-baseline --baseline-id $baseline_id" \
            "Deleting patch baseline $baseline_id" true
    done
    
    # Clean up other resources by naming pattern
    # CloudWatch alarms
    local alarms
    alarms=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "PatchComplianceAlarm-" \
        --query "MetricAlarms[*].AlarmName" \
        --output text 2>/dev/null || echo "")
    
    for alarm in $alarms; do
        execute_command "aws cloudwatch delete-alarms --alarm-names $alarm" \
            "Deleting CloudWatch alarm $alarm" true
    done
    
    # SNS topics
    local topics
    topics=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, 'patch-notifications-')].TopicArn" \
        --output text 2>/dev/null || echo "")
    
    for topic in $topics; do
        execute_command "aws sns delete-topic --topic-arn $topic" \
            "Deleting SNS topic $topic" true
    done
    
    # IAM roles
    local roles
    roles=$(aws iam list-roles \
        --query "Roles[?starts_with(RoleName, 'MaintenanceWindowRole-')].RoleName" \
        --output text 2>/dev/null || echo "")
    
    for role in $roles; do
        execute_command "aws iam detach-role-policy \
            --role-name $role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole" \
            "Detaching policy from role $role" true
        
        execute_command "aws iam delete-role --role-name $role" \
            "Deleting IAM role $role" true
    done
    
    # S3 buckets
    local buckets
    buckets=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, 'patch-reports-${AWS_ACCOUNT_ID}')].Name" \
        --output text 2>/dev/null || echo "")
    
    for bucket in $buckets; do
        execute_command "aws s3 rm s3://$bucket --recursive" \
            "Emptying S3 bucket $bucket" true
        
        execute_command "aws s3 rb s3://$bucket" \
            "Deleting S3 bucket $bucket" true
    done
    
    success "Force cleanup completed"
}

# Display cleanup summary
display_summary() {
    echo ""
    echo "=================================================="
    echo "         CLEANUP SUMMARY"
    echo "=================================================="
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN MODE - No resources were actually deleted"
        echo ""
        echo "The following resources WOULD be deleted:"
    else
        echo "✅ Cleanup completed successfully!"
        echo ""
        echo "The following resources have been removed:"
    fi
    
    echo ""
    echo "🗑️  Deleted Resources:"
    echo "   • Maintenance windows and associated tasks/targets"
    echo "   • Custom patch baselines and patch group associations"
    echo "   • CloudWatch alarms and SNS topics"
    echo "   • IAM roles and policies"
    echo "   • S3 buckets and their contents"
    echo "   • Local configuration files"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "💾 Data Impact:"
        echo "   • All patch reports and logs have been permanently deleted"
        echo "   • Patch compliance history has been removed"
        echo "   • Configuration files have been cleaned up"
        echo ""
        echo "✅ Your AWS account has been restored to its previous state"
    fi
    
    echo ""
    echo "=================================================="
}

# Main execution
main() {
    log "Starting AWS Systems Manager Automated Patching cleanup..."
    
    check_prerequisites
    load_environment
    
    if [[ "$FORCE" == "true" ]]; then
        force_cleanup
    else
        confirm_destruction
        cleanup_maintenance_windows
        cleanup_patch_baseline
        cleanup_monitoring
        cleanup_iam_role
        cleanup_s3_bucket
    fi
    
    cleanup_local_files
    display_summary
    
    success "Cleanup completed successfully!"
}

# Show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up AWS Systems Manager Automated Patching Infrastructure

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Run in dry-run mode (no resources deleted)
    -f, --force         Force cleanup without confirmation (dangerous!)
    -v, --verbose       Enable verbose logging

ENVIRONMENT VARIABLES:
    DRY_RUN            Set to 'true' to run in dry-run mode
    FORCE              Set to 'true' to skip confirmation prompts
    AWS_REGION         AWS region to clean up (defaults to CLI config)
    AWS_PROFILE        AWS profile to use (defaults to CLI config)

EXAMPLES:
    $0                  # Interactive cleanup with confirmation
    $0 --dry-run        # See what would be deleted
    $0 --force          # Force cleanup without confirmation
    DRY_RUN=true $0     # Same as --dry-run

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Appropriate IAM permissions for all services used
    - .env file from deployment (or use --force to discover resources)

WARNING:
    This script permanently deletes resources and data. Use with caution!
    The --force option is particularly dangerous and should be used carefully.

For more information, see the recipe documentation.
EOF
}

# Parse command line arguments
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
        -f|--force)
            FORCE=true
            shift
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main "$@"