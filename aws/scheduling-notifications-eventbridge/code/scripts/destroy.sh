#!/bin/bash

# =============================================================================
# Destroy Script for Simple Business Notifications with EventBridge Scheduler and SNS
# 
# This script safely removes all resources created by the business notifications
# deployment including:
# - EventBridge Scheduler schedules and schedule groups
# - SNS topics and subscriptions
# - IAM roles and policies
#
# Prerequisites:
# - AWS CLI v2.x installed and configured
# - Same permissions used for deployment
# - Access to the same AWS account and region used for deployment
# =============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# -----------------------------------------------------------------------------
# Configuration and Setup
# -----------------------------------------------------------------------------

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Script metadata
readonly SCRIPT_NAME="Simple Business Notifications Cleanup"
readonly SCRIPT_VERSION="1.0"

# Global variables
FORCE_DELETE=false
INTERACTIVE_MODE=true
RESOURCE_COUNT=0
DELETED_COUNT=0
FAILED_COUNT=0

# -----------------------------------------------------------------------------
# Prerequisites Check
# -----------------------------------------------------------------------------

check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2.x"
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first"
        exit 1
    fi
    
    # Get AWS region and account ID
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS region not configured. Please set AWS_REGION or configure AWS CLI"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log_success "Prerequisites check completed"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "Account ID: ${AWS_ACCOUNT_ID}"
}

# -----------------------------------------------------------------------------
# Resource Discovery Functions
# -----------------------------------------------------------------------------

discover_schedule_groups() {
    log_info "Discovering EventBridge Scheduler groups..."
    
    # Find schedule groups with business notification tags
    local groups
    groups=$(aws scheduler list-schedule-groups \
        --query 'ScheduleGroups[?contains(Name, `business-schedule`)]' \
        --output json 2>/dev/null || echo '[]')
    
    if [[ "$groups" != "[]" && "$groups" != "" ]]; then
        echo "$groups" | jq -r '.[].Name' | while read -r group_name; do
            if [[ -n "$group_name" ]]; then
                SCHEDULE_GROUPS+=("$group_name")
                log_info "Found schedule group: $group_name"
            fi
        done
    fi
}

discover_sns_topics() {
    log_info "Discovering SNS topics..."
    
    # Find SNS topics with business notification pattern
    local topics
    topics=$(aws sns list-topics \
        --query 'Topics[?contains(TopicArn, `business-notifications`)]' \
        --output json 2>/dev/null || echo '[]')
    
    if [[ "$topics" != "[]" && "$topics" != "" ]]; then
        echo "$topics" | jq -r '.[].TopicArn' | while read -r topic_arn; do
            if [[ -n "$topic_arn" ]]; then
                SNS_TOPICS+=("$topic_arn")
                log_info "Found SNS topic: $topic_arn"
            fi
        done
    fi
}

discover_iam_roles() {
    log_info "Discovering IAM roles..."
    
    # Find IAM roles with EventBridge Scheduler pattern
    local roles
    roles=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `eventbridge-scheduler-role`)]' \
        --output json 2>/dev/null || echo '[]')
    
    if [[ "$roles" != "[]" && "$roles" != "" ]]; then
        echo "$roles" | jq -r '.[].RoleName' | while read -r role_name; do
            if [[ -n "$role_name" ]]; then
                IAM_ROLES+=("$role_name")
                log_info "Found IAM role: $role_name"
            fi
        done
    fi
}

discover_all_resources() {
    log_info "Discovering resources to clean up..."
    
    # Initialize arrays for discovered resources
    SCHEDULE_GROUPS=()
    SNS_TOPICS=()
    IAM_ROLES=()
    
    # Allow user to specify specific resources if desired
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        SNS_TOPICS=("arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${TOPIC_NAME}")
    fi
    
    if [[ -n "${SCHEDULE_GROUP_NAME:-}" ]]; then
        SCHEDULE_GROUPS=("${SCHEDULE_GROUP_NAME}")
    fi
    
    if [[ -n "${ROLE_NAME:-}" ]]; then
        IAM_ROLES=("${ROLE_NAME}")
    fi
    
    # If no specific resources provided, discover automatically
    if [[ ${#SCHEDULE_GROUPS[@]} -eq 0 && ${#SNS_TOPICS[@]} -eq 0 && ${#IAM_ROLES[@]} -eq 0 ]]; then
        discover_schedule_groups
        discover_sns_topics
        discover_iam_roles
    fi
    
    # Count total resources
    RESOURCE_COUNT=$((${#SCHEDULE_GROUPS[@]} + ${#SNS_TOPICS[@]} + ${#IAM_ROLES[@]}))
    
    if [[ $RESOURCE_COUNT -eq 0 ]]; then
        log_warning "No business notification resources found to clean up"
        exit 0
    fi
    
    log_info "Found ${RESOURCE_COUNT} resources to clean up"
}

# -----------------------------------------------------------------------------
# User Confirmation Functions
# -----------------------------------------------------------------------------

display_resources_to_delete() {
    echo
    echo "==============================================================================="
    echo "                          RESOURCES TO BE DELETED"
    echo "==============================================================================="
    
    if [[ ${#SCHEDULE_GROUPS[@]} -gt 0 ]]; then
        echo
        log_warning "EventBridge Scheduler Groups (${#SCHEDULE_GROUPS[@]}):"
        for group in "${SCHEDULE_GROUPS[@]}"; do
            echo "  • $group"
            # Count schedules in each group
            local schedule_count
            schedule_count=$(aws scheduler list-schedules \
                --group-name "$group" \
                --query 'length(Schedules)' \
                --output text 2>/dev/null || echo "0")
            echo "    └── Contains $schedule_count schedules"
        done
    fi
    
    if [[ ${#SNS_TOPICS[@]} -gt 0 ]]; then
        echo
        log_warning "SNS Topics (${#SNS_TOPICS[@]}):"
        for topic in "${SNS_TOPICS[@]}"; do
            echo "  • $topic"
            # Count subscriptions for each topic
            local sub_count
            sub_count=$(aws sns list-subscriptions-by-topic \
                --topic-arn "$topic" \
                --query 'length(Subscriptions)' \
                --output text 2>/dev/null || echo "0")
            echo "    └── Contains $sub_count subscriptions"
        done
    fi
    
    if [[ ${#IAM_ROLES[@]} -gt 0 ]]; then
        echo
        log_warning "IAM Roles (${#IAM_ROLES[@]}):"
        for role in "${IAM_ROLES[@]}"; do
            echo "  • $role"
            # Count attached policies
            local policy_count
            policy_count=$(aws iam list-attached-role-policies \
                --role-name "$role" \
                --query 'length(AttachedPolicies)' \
                --output text 2>/dev/null || echo "0")
            echo "    └── Contains $policy_count attached policies"
        done
    fi
    
    echo
    echo "==============================================================================="
}

confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force delete mode enabled - proceeding without confirmation"
        return 0
    fi
    
    display_resources_to_delete
    
    echo
    log_warning "This action will PERMANENTLY DELETE all listed resources!"
    log_warning "This action cannot be undone."
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    log_info "Proceeding with resource cleanup..."
}

# -----------------------------------------------------------------------------
# Resource Deletion Functions
# -----------------------------------------------------------------------------

delete_eventbridge_schedules() {
    if [[ ${#SCHEDULE_GROUPS[@]} -eq 0 ]]; then
        return 0
    fi
    
    log_info "Deleting EventBridge Scheduler schedules and groups..."
    
    for group_name in "${SCHEDULE_GROUPS[@]}"; do
        log_info "Processing schedule group: $group_name"
        
        # Get all schedules in the group
        local schedules
        schedules=$(aws scheduler list-schedules \
            --group-name "$group_name" \
            --query 'Schedules[].Name' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$schedules" && "$schedules" != "None" ]]; then
            # Delete each schedule
            for schedule_name in $schedules; do
                log_info "  Deleting schedule: $schedule_name"
                if aws scheduler delete-schedule \
                    --name "$schedule_name" \
                    --group-name "$group_name" 2>/dev/null; then
                    log_success "    Schedule $schedule_name deleted"
                    ((DELETED_COUNT++))
                else
                    log_error "    Failed to delete schedule $schedule_name"
                    ((FAILED_COUNT++))
                fi
            done
            
            # Wait a moment for schedule deletions to propagate
            sleep 2
        fi
        
        # Delete the schedule group
        log_info "  Deleting schedule group: $group_name"
        if aws scheduler delete-schedule-group \
            --name "$group_name" 2>/dev/null; then
            log_success "    Schedule group $group_name deleted"
            ((DELETED_COUNT++))
        else
            log_error "    Failed to delete schedule group $group_name"
            ((FAILED_COUNT++))
        fi
    done
}

delete_sns_topics() {
    if [[ ${#SNS_TOPICS[@]} -eq 0 ]]; then
        return 0
    fi
    
    log_info "Deleting SNS topics and subscriptions..."
    
    for topic_arn in "${SNS_TOPICS[@]}"; do
        log_info "Processing SNS topic: $topic_arn"
        
        # Get topic name from ARN for display
        local topic_name
        topic_name=$(echo "$topic_arn" | cut -d':' -f6)
        
        # List subscriptions (for information only - they'll be deleted with the topic)
        local subscriptions
        subscriptions=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$topic_arn" \
            --query 'length(Subscriptions)' \
            --output text 2>/dev/null || echo "0")
        
        if [[ "$subscriptions" -gt 0 ]]; then
            log_info "  Topic has $subscriptions subscription(s) - will be deleted with topic"
        fi
        
        # Delete the SNS topic (automatically deletes subscriptions)
        log_info "  Deleting SNS topic: $topic_name"
        if aws sns delete-topic \
            --topic-arn "$topic_arn" 2>/dev/null; then
            log_success "    SNS topic $topic_name deleted (including subscriptions)"
            ((DELETED_COUNT++))
        else
            log_error "    Failed to delete SNS topic $topic_name"
            ((FAILED_COUNT++))
        fi
    done
}

delete_iam_roles() {
    if [[ ${#IAM_ROLES[@]} -eq 0 ]]; then
        return 0
    fi
    
    log_info "Deleting IAM roles and policies..."
    
    for role_name in "${IAM_ROLES[@]}"; do
        log_info "Processing IAM role: $role_name"
        
        # Get attached policies
        local attached_policies
        attached_policies=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        # Detach and delete custom policies
        if [[ -n "$attached_policies" && "$attached_policies" != "None" ]]; then
            for policy_arn in $attached_policies; do
                log_info "  Detaching policy: $policy_arn"
                
                # Detach policy from role
                if aws iam detach-role-policy \
                    --role-name "$role_name" \
                    --policy-arn "$policy_arn" 2>/dev/null; then
                    log_success "    Policy detached from role"
                    
                    # Delete custom policies (not AWS managed policies)
                    if [[ "$policy_arn" != *":aws:policy/"* ]]; then
                        log_info "  Deleting custom policy: $policy_arn"
                        if aws iam delete-policy \
                            --policy-arn "$policy_arn" 2>/dev/null; then
                            log_success "    Custom policy deleted"
                            ((DELETED_COUNT++))
                        else
                            log_error "    Failed to delete custom policy"
                            ((FAILED_COUNT++))
                        fi
                    fi
                else
                    log_error "    Failed to detach policy from role"
                    ((FAILED_COUNT++))
                fi
            done
        fi
        
        # Delete the IAM role
        log_info "  Deleting IAM role: $role_name"
        if aws iam delete-role \
            --role-name "$role_name" 2>/dev/null; then
            log_success "    IAM role $role_name deleted"
            ((DELETED_COUNT++))
        else
            log_error "    Failed to delete IAM role $role_name"
            ((FAILED_COUNT++))
        fi
    done
}

# -----------------------------------------------------------------------------
# Cleanup Functions
# -----------------------------------------------------------------------------

cleanup_temporary_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove any temporary files that might have been created
    local temp_files=(
        "/tmp/scheduler-trust-policy.json"
        "/tmp/sns-publish-policy.json"
        "./scheduler-trust-policy.json"
        "./sns-publish-policy.json"
    )
    
    for temp_file in "${temp_files[@]}"; do
        if [[ -f "$temp_file" ]]; then
            rm -f "$temp_file"
            log_info "  Removed temporary file: $temp_file"
        fi
    done
    
    log_success "Temporary files cleaned up"
}

# -----------------------------------------------------------------------------
# Verification Functions
# -----------------------------------------------------------------------------

verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local remaining_resources=0
    
    # Check for remaining schedule groups
    for group_name in "${SCHEDULE_GROUPS[@]}"; do
        if aws scheduler get-schedule-group \
            --name "$group_name" &>/dev/null; then
            log_warning "Schedule group still exists: $group_name"
            ((remaining_resources++))
        fi
    done
    
    # Check for remaining SNS topics
    for topic_arn in "${SNS_TOPICS[@]}"; do
        if aws sns get-topic-attributes \
            --topic-arn "$topic_arn" &>/dev/null; then
            log_warning "SNS topic still exists: $topic_arn"
            ((remaining_resources++))
        fi
    done
    
    # Check for remaining IAM roles
    for role_name in "${IAM_ROLES[@]}"; do
        if aws iam get-role \
            --role-name "$role_name" &>/dev/null; then
            log_warning "IAM role still exists: $role_name"
            ((remaining_resources++))
        fi
    done
    
    if [[ $remaining_resources -eq 0 ]]; then
        log_success "All resources have been successfully removed"
    else
        log_warning "$remaining_resources resources may still exist and require manual cleanup"
    fi
}

# -----------------------------------------------------------------------------
# Summary Functions
# -----------------------------------------------------------------------------

display_cleanup_summary() {
    echo
    echo "==============================================================================="
    echo "                              CLEANUP SUMMARY"
    echo "==============================================================================="
    echo
    echo "📊 Resource Cleanup Statistics:"
    echo "   • Total resources found: $RESOURCE_COUNT"
    echo "   • Successfully deleted: $DELETED_COUNT"
    echo "   • Failed to delete: $FAILED_COUNT"
    echo
    
    if [[ $FAILED_COUNT -eq 0 ]]; then
        echo "✅ All resources have been successfully cleaned up!"
        echo
        echo "💰 Cost Impact:"
        echo "   • No more charges will be incurred for these resources"
        echo "   • EventBridge Scheduler charges will stop immediately"
        echo "   • SNS message delivery charges will stop immediately"
        echo
        echo "📝 Next Steps:"
        echo "   • Verify no unexpected charges appear on your AWS bill"
        echo "   • Consider implementing the solution again if needed"
        echo "   • Review CloudTrail logs for audit purposes"
    else
        echo "⚠️  Some resources could not be deleted and may require manual cleanup"
        echo
        echo "🔧 Manual Cleanup Required:"
        echo "   • Check AWS Console for remaining resources"
        echo "   • Verify IAM permissions for resource deletion"
        echo "   • Contact AWS Support if resources cannot be deleted"
        echo
        echo "💡 Common Issues:"
        echo "   • IAM roles may have policies attached by other services"
        echo "   • Resources may be in use by other applications"
        echo "   • Insufficient permissions for deletion"
    fi
    
    echo
    echo "==============================================================================="
}

# -----------------------------------------------------------------------------
# Main Cleanup Function
# -----------------------------------------------------------------------------

main() {
    log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    echo "==============================================================================="
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --topic-name)
                TOPIC_NAME="$2"
                shift 2
                ;;
            --schedule-group)
                SCHEDULE_GROUP_NAME="$2"
                shift 2
                ;;
            --role-name)
                ROLE_NAME="$2"
                shift 2
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --force             Skip confirmation prompts"
                echo "  --topic-name NAME   Specific SNS topic name to delete"
                echo "  --schedule-group    Specific schedule group name to delete"
                echo "  --role-name NAME    Specific IAM role name to delete"
                echo "  --region REGION     AWS region (default: configured region)"
                echo "  --dry-run           Show what would be deleted without removing resources"
                echo "  --help              Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Execute cleanup steps
    check_prerequisites
    discover_all_resources
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        display_resources_to_delete
        exit 0
    fi
    
    confirm_deletion
    
    # Execute deletion in proper order (reverse of creation)
    delete_eventbridge_schedules
    delete_sns_topics
    delete_iam_roles
    cleanup_temporary_files
    verify_cleanup
    
    display_cleanup_summary
    
    if [[ $FAILED_COUNT -eq 0 ]]; then
        log_success "Cleanup completed successfully!"
    else
        log_warning "Cleanup completed with $FAILED_COUNT failures - manual intervention may be required"
        exit 1
    fi
    
    echo "==============================================================================="
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi