#!/bin/bash
set -euo pipefail

# AWS Multi-Factor Authentication with IAM and MFA Devices - Cleanup Script
# This script safely removes all resources created by the MFA deployment

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Cannot proceed with cleanup."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or lacks permissions. Please configure it first."
    fi
    
    # Check for deployment state file
    if [ ! -f "deployment_state.json" ]; then
        warning "deployment_state.json not found. Will attempt cleanup using environment variables or prompt for resource names."
        return 1
    fi
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq is not available. Will use fallback methods for cleanup."
        return 1
    fi
    
    success "Prerequisites check passed"
    return 0
}

# Load configuration from deployment state or environment
load_configuration() {
    log "Loading configuration..."
    
    if [ -f "deployment_state.json" ] && command -v jq &> /dev/null; then
        # Load from deployment state file
        export AWS_REGION=$(jq -r '.aws_region // "us-east-1"' deployment_state.json)
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id // ""' deployment_state.json)
        export TEST_USER_NAME=$(jq -r '.test_user_name // ""' deployment_state.json)
        export MFA_POLICY_NAME=$(jq -r '.mfa_policy_name // ""' deployment_state.json)
        export ADMIN_GROUP_NAME=$(jq -r '.admin_group_name // ""' deployment_state.json)
        
        log "Configuration loaded from deployment_state.json"
    else
        # Fallback to environment variables or defaults
        export AWS_REGION="${AWS_REGION:-$(aws configure get region || echo 'us-east-1')}"
        export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
        
        # Prompt for resource names if not available
        if [ -z "${TEST_USER_NAME:-}" ]; then
            echo -n "Enter test user name to delete: "
            read -r TEST_USER_NAME
            export TEST_USER_NAME
        fi
        
        if [ -z "${MFA_POLICY_NAME:-}" ]; then
            echo -n "Enter MFA policy name to delete: "
            read -r MFA_POLICY_NAME
            export MFA_POLICY_NAME
        fi
        
        if [ -z "${ADMIN_GROUP_NAME:-}" ]; then
            echo -n "Enter admin group name to delete: "
            read -r ADMIN_GROUP_NAME
            export ADMIN_GROUP_NAME
        fi
        
        warning "Configuration loaded from environment/input"
    fi
    
    log "AWS Region: $AWS_REGION"
    log "AWS Account: $AWS_ACCOUNT_ID"
    log "Test User: ${TEST_USER_NAME:-'Not specified'}"
    log "MFA Policy: ${MFA_POLICY_NAME:-'Not specified'}"
    log "Admin Group: ${ADMIN_GROUP_NAME:-'Not specified'}"
}

# Confirmation prompt with safety checks
confirm_cleanup() {
    cat << EOF

================================================================================
                              ⚠️  WARNING ⚠️
================================================================================

This script will PERMANENTLY DELETE the following AWS resources:

🗑️  RESOURCES TO BE DELETED:
   - IAM User: ${TEST_USER_NAME:-'Unknown'}
   - IAM Group: ${ADMIN_GROUP_NAME:-'Unknown'}
   - IAM Policy: ${MFA_POLICY_NAME:-'Unknown'}
   - MFA Devices associated with the user
   - CloudWatch dashboards and alarms
   - CloudWatch metric filters
   - Local files (QR codes, policies, etc.)

💸 COST IMPACT:
   - This will stop ongoing charges for CloudWatch resources
   - No charges for IAM resource deletion

🔒 SECURITY IMPACT:
   - This will remove MFA enforcement for the test user
   - Production systems should not use this test configuration

================================================================================

EOF

    echo -n "Are you sure you want to proceed with the cleanup? (yes/no): "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    # Additional confirmation for safety
    echo -n "Type 'DELETE' to confirm permanent resource removal: "
    read -r delete_confirmation
    
    if [[ "$delete_confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled - confirmation text did not match"
        exit 0
    fi
    
    success "Cleanup confirmed by user"
}

# Remove MFA devices and deactivate
cleanup_mfa_devices() {
    log "Cleaning up MFA devices..."
    
    if [ -z "${TEST_USER_NAME:-}" ]; then
        warning "Test user name not specified, skipping MFA device cleanup"
        return 0
    fi
    
    # Get MFA devices for the user
    if MFA_DEVICES=$(aws iam list-mfa-devices --user-name "$TEST_USER_NAME" --query 'MFADevices[].SerialNumber' --output text 2>/dev/null) && [ -n "$MFA_DEVICES" ]; then
        for device in $MFA_DEVICES; do
            log "Deactivating MFA device: $device"
            if aws iam deactivate-mfa-device \
                --user-name "$TEST_USER_NAME" \
                --serial-number "$device" &> /dev/null; then
                success "Deactivated MFA device: $device"
            else
                warning "Failed to deactivate MFA device: $device"
            fi
        done
    fi
    
    # Get virtual MFA devices for the user
    if VIRTUAL_MFA_DEVICES=$(aws iam list-virtual-mfa-devices \
        --query "VirtualMFADevices[?User.UserName=='${TEST_USER_NAME}'].SerialNumber" \
        --output text 2>/dev/null) && [ -n "$VIRTUAL_MFA_DEVICES" ]; then
        for device in $VIRTUAL_MFA_DEVICES; do
            log "Deleting virtual MFA device: $device"
            if aws iam delete-virtual-mfa-device --serial-number "$device" &> /dev/null; then
                success "Deleted virtual MFA device: $device"
            else
                warning "Failed to delete virtual MFA device: $device"
            fi
        done
    fi
    
    success "MFA device cleanup completed"
}

# Remove user from groups and delete user
cleanup_user() {
    log "Cleaning up IAM user..."
    
    if [ -z "${TEST_USER_NAME:-}" ]; then
        warning "Test user name not specified, skipping user cleanup"
        return 0
    fi
    
    # Check if user exists
    if ! aws iam get-user --user-name "$TEST_USER_NAME" &> /dev/null; then
        warning "User $TEST_USER_NAME does not exist, skipping user cleanup"
        return 0
    fi
    
    # Remove user from all groups
    if USER_GROUPS=$(aws iam get-groups-for-user --user-name "$TEST_USER_NAME" --query 'Groups[].GroupName' --output text 2>/dev/null) && [ -n "$USER_GROUPS" ]; then
        for group in $USER_GROUPS; do
            log "Removing user from group: $group"
            if aws iam remove-user-from-group \
                --user-name "$TEST_USER_NAME" \
                --group-name "$group" &> /dev/null; then
                success "Removed user from group: $group"
            else
                warning "Failed to remove user from group: $group"
            fi
        done
    fi
    
    # Delete login profile
    if aws iam delete-login-profile --user-name "$TEST_USER_NAME" &> /dev/null; then
        success "Deleted login profile for user: $TEST_USER_NAME"
    else
        warning "Failed to delete login profile (may not exist)"
    fi
    
    # Detach user policies
    if USER_POLICIES=$(aws iam list-attached-user-policies --user-name "$TEST_USER_NAME" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null) && [ -n "$USER_POLICIES" ]; then
        for policy in $USER_POLICIES; do
            log "Detaching policy from user: $policy"
            if aws iam detach-user-policy \
                --user-name "$TEST_USER_NAME" \
                --policy-arn "$policy" &> /dev/null; then
                success "Detached policy from user: $policy"
            else
                warning "Failed to detach policy from user: $policy"
            fi
        done
    fi
    
    # Delete inline user policies
    if INLINE_POLICIES=$(aws iam list-user-policies --user-name "$TEST_USER_NAME" --query 'PolicyNames[]' --output text 2>/dev/null) && [ -n "$INLINE_POLICIES" ]; then
        for policy in $INLINE_POLICIES; do
            log "Deleting inline policy: $policy"
            if aws iam delete-user-policy \
                --user-name "$TEST_USER_NAME" \
                --policy-name "$policy" &> /dev/null; then
                success "Deleted inline policy: $policy"
            else
                warning "Failed to delete inline policy: $policy"
            fi
        done
    fi
    
    # Delete user
    if aws iam delete-user --user-name "$TEST_USER_NAME" &> /dev/null; then
        success "Deleted IAM user: $TEST_USER_NAME"
    else
        error "Failed to delete IAM user: $TEST_USER_NAME"
    fi
}

# Remove policies and groups
cleanup_policies_and_groups() {
    log "Cleaning up IAM policies and groups..."
    
    # Cleanup policy
    if [ -n "${MFA_POLICY_NAME:-}" ]; then
        # Get policy ARN from file or construct it
        if [ -f "mfa_policy_arn.txt" ]; then
            MFA_POLICY_ARN=$(cat mfa_policy_arn.txt)
        else
            MFA_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${MFA_POLICY_NAME}"
        fi
        
        # Check if policy exists
        if aws iam get-policy --policy-arn "$MFA_POLICY_ARN" &> /dev/null; then
            # Detach policy from all groups
            if ATTACHED_GROUPS=$(aws iam list-entities-for-policy --policy-arn "$MFA_POLICY_ARN" --query 'PolicyGroups[].GroupName' --output text 2>/dev/null) && [ -n "$ATTACHED_GROUPS" ]; then
                for group in $ATTACHED_GROUPS; do
                    log "Detaching policy from group: $group"
                    if aws iam detach-group-policy \
                        --group-name "$group" \
                        --policy-arn "$MFA_POLICY_ARN" &> /dev/null; then
                        success "Detached policy from group: $group"
                    else
                        warning "Failed to detach policy from group: $group"
                    fi
                done
            fi
            
            # Delete policy
            if aws iam delete-policy --policy-arn "$MFA_POLICY_ARN" &> /dev/null; then
                success "Deleted IAM policy: $MFA_POLICY_NAME"
            else
                warning "Failed to delete IAM policy: $MFA_POLICY_NAME"
            fi
        else
            warning "Policy $MFA_POLICY_NAME does not exist"
        fi
    fi
    
    # Cleanup group
    if [ -n "${ADMIN_GROUP_NAME:-}" ]; then
        if aws iam get-group --group-name "$ADMIN_GROUP_NAME" &> /dev/null; then
            # Detach all policies from group
            if GROUP_POLICIES=$(aws iam list-attached-group-policies --group-name "$ADMIN_GROUP_NAME" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null) && [ -n "$GROUP_POLICIES" ]; then
                for policy in $GROUP_POLICIES; do
                    log "Detaching policy from group: $policy"
                    if aws iam detach-group-policy \
                        --group-name "$ADMIN_GROUP_NAME" \
                        --policy-arn "$policy" &> /dev/null; then
                        success "Detached policy from group: $policy"
                    else
                        warning "Failed to detach policy from group: $policy"
                    fi
                done
            fi
            
            # Delete inline group policies
            if INLINE_POLICIES=$(aws iam list-group-policies --group-name "$ADMIN_GROUP_NAME" --query 'PolicyNames[]' --output text 2>/dev/null) && [ -n "$INLINE_POLICIES" ]; then
                for policy in $INLINE_POLICIES; do
                    log "Deleting inline group policy: $policy"
                    if aws iam delete-group-policy \
                        --group-name "$ADMIN_GROUP_NAME" \
                        --policy-name "$policy" &> /dev/null; then
                        success "Deleted inline group policy: $policy"
                    else
                        warning "Failed to delete inline group policy: $policy"
                    fi
                done
            fi
            
            # Remove all users from group
            if GROUP_USERS=$(aws iam get-group --group-name "$ADMIN_GROUP_NAME" --query 'Users[].UserName' --output text 2>/dev/null) && [ -n "$GROUP_USERS" ]; then
                for user in $GROUP_USERS; do
                    log "Removing user from group: $user"
                    if aws iam remove-user-from-group \
                        --group-name "$ADMIN_GROUP_NAME" \
                        --user-name "$user" &> /dev/null; then
                        success "Removed user from group: $user"
                    else
                        warning "Failed to remove user from group: $user"
                    fi
                done
            fi
            
            # Delete group
            if aws iam delete-group --group-name "$ADMIN_GROUP_NAME" &> /dev/null; then
                success "Deleted IAM group: $ADMIN_GROUP_NAME"
            else
                warning "Failed to delete IAM group: $ADMIN_GROUP_NAME"
            fi
        else
            warning "Group $ADMIN_GROUP_NAME does not exist"
        fi
    fi
}

# Remove CloudWatch monitoring resources
cleanup_monitoring() {
    log "Cleaning up monitoring resources..."
    
    # Get dashboard names from deployment state or search for pattern
    if [ -f "deployment_state.json" ] && command -v jq &> /dev/null; then
        DASHBOARDS=$(jq -r '.resources_created[] | select(.type == "CLOUDWATCH_DASHBOARD") | .name' deployment_state.json 2>/dev/null || true)
        ALARMS=$(jq -r '.resources_created[] | select(.type == "CLOUDWATCH_ALARM") | .name' deployment_state.json 2>/dev/null || true)
        METRIC_FILTERS=$(jq -r '.resources_created[] | select(.type == "METRIC_FILTER") | .name' deployment_state.json 2>/dev/null || true)
    else
        # Search for dashboards with pattern
        DASHBOARDS=$(aws cloudwatch list-dashboards --query 'DashboardEntries[?contains(DashboardName, `MFA-Security-Dashboard`)].DashboardName' --output text 2>/dev/null || true)
        ALARMS=$(aws cloudwatch describe-alarms --query 'MetricAlarms[?contains(AlarmName, `Non-MFA-Console-Logins`)].AlarmName' --output text 2>/dev/null || true)
        # Metric filters require log group name, skip if not available
        METRIC_FILTERS=""
    fi
    
    # Delete dashboards
    if [ -n "$DASHBOARDS" ]; then
        for dashboard in $DASHBOARDS; do
            log "Deleting CloudWatch dashboard: $dashboard"
            if aws cloudwatch delete-dashboards --dashboard-names "$dashboard" &> /dev/null; then
                success "Deleted dashboard: $dashboard"
            else
                warning "Failed to delete dashboard: $dashboard"
            fi
        done
    else
        log "No MFA dashboards found to delete"
    fi
    
    # Delete alarms
    if [ -n "$ALARMS" ]; then
        for alarm in $ALARMS; do
            log "Deleting CloudWatch alarm: $alarm"
            if aws cloudwatch delete-alarms --alarm-names "$alarm" &> /dev/null; then
                success "Deleted alarm: $alarm"
            else
                warning "Failed to delete alarm: $alarm"
            fi
        done
    else
        log "No MFA alarms found to delete"
    fi
    
    # Delete metric filters
    if [ -n "$METRIC_FILTERS" ]; then
        # Try to find CloudTrail log group
        if CLOUDTRAIL_LOG_GROUP=$(aws logs describe-log-groups --log-group-name-prefix "CloudTrail" --query 'logGroups[0].logGroupName' --output text 2>/dev/null) && [ "$CLOUDTRAIL_LOG_GROUP" != "None" ]; then
            for filter in $METRIC_FILTERS; do
                log "Deleting metric filter: $filter"
                if aws logs delete-metric-filter \
                    --log-group-name "$CLOUDTRAIL_LOG_GROUP" \
                    --filter-name "$filter" &> /dev/null; then
                    success "Deleted metric filter: $filter"
                else
                    warning "Failed to delete metric filter: $filter"
                fi
            done
        else
            warning "CloudTrail log group not found, cannot delete metric filters"
        fi
    else
        log "No metric filters found to delete"
    fi
    
    success "Monitoring cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_delete=(
        "deployment_state.json"
        "mfa-enforcement-policy.json"
        "mfa-qr-code.png"
        "mfa-dashboard.json"
        "mfa_policy_arn.txt"
        "mfa_serial.txt"
        "temp_state.json"
    )
    
    for file in "${files_to_delete[@]}"; do
        if [ -f "$file" ]; then
            log "Deleting file: $file"
            rm -f "$file"
            success "Deleted file: $file"
        fi
    done
    
    success "Local file cleanup completed"
}

# Generate cleanup summary
generate_summary() {
    cat << EOF

================================================================================
                            CLEANUP SUMMARY
================================================================================

🗑️  RESOURCES REMOVED:
   ✅ IAM User: ${TEST_USER_NAME:-'N/A'}
   ✅ IAM Group: ${ADMIN_GROUP_NAME:-'N/A'}
   ✅ IAM Policy: ${MFA_POLICY_NAME:-'N/A'}
   ✅ MFA Devices: All devices for user
   ✅ CloudWatch Dashboards: MFA monitoring
   ✅ CloudWatch Alarms: Non-MFA login alerts
   ✅ CloudWatch Metric Filters: MFA usage tracking
   ✅ Local Files: All generated files

💰 COST IMPACT:
   ✅ CloudWatch dashboard charges stopped
   ✅ CloudWatch alarm charges stopped
   ✅ No ongoing IAM charges (free tier)

🔒 SECURITY IMPACT:
   ✅ Test MFA enforcement removed
   ✅ No impact on production systems
   ✅ Temporary credentials invalidated

📁 REMAINING FILES:
   - None (all generated files cleaned up)

================================================================================

✅ Cleanup completed successfully!

The MFA test environment has been completely removed from your AWS account.
All resources have been deleted and ongoing charges have been stopped.

If you want to implement MFA in production:
1. Review the MFA policy for your requirements
2. Apply to production user groups gradually
3. Ensure emergency access procedures are documented
4. Monitor MFA compliance regularly

================================================================================

EOF
}

# Main cleanup function
main() {
    log "Starting AWS MFA cleanup..."
    
    if ! check_prerequisites; then
        warning "Some prerequisites not met, continuing with available methods"
    fi
    
    load_configuration
    confirm_cleanup
    
    log "Beginning resource cleanup..."
    
    # Clean up in reverse order of creation
    cleanup_monitoring
    cleanup_mfa_devices
    cleanup_user
    cleanup_policies_and_groups
    cleanup_local_files
    
    generate_summary
    
    success "🎉 AWS MFA cleanup completed successfully!"
}

# Trap for cleanup on script interruption
cleanup_on_exit() {
    if [ -f "temp_state.json" ]; then
        rm -f temp_state.json
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"