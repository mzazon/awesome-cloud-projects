#!/bin/bash

# AWS IoT Device Defender Security Implementation Cleanup Script
# This script removes all resources created by the IoT Device Defender deployment
# Recipe: IoT Security Monitoring with Device Defender

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to confirm destructive actions
confirm_deletion() {
    local resource_type="$1"
    local confirmation
    
    echo
    log_warning "This will permanently delete all ${resource_type} resources."
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    case "${confirmation}" in
        yes|YES|y|Y)
            log_info "Proceeding with ${resource_type} deletion..."
            return 0
            ;;
        *)
            log_info "Deletion cancelled by user."
            return 1
            ;;
    esac
}

# Function to safely delete resource with error handling
safe_delete() {
    local description="$1"
    shift
    local command=("$@")
    
    log_info "Deleting ${description}..."
    if "${command[@]}" 2>/dev/null; then
        log_success "Deleted ${description}"
    else
        log_warning "Failed to delete ${description} (may not exist or already deleted)"
    fi
}

# Function to safely detach resource with error handling
safe_detach() {
    local description="$1"
    shift
    local command=("$@")
    
    log_info "Detaching ${description}..."
    if "${command[@]}" 2>/dev/null; then
        log_success "Detached ${description}"
    else
        log_warning "Failed to detach ${description} (may not exist or already detached)"
    fi
}

# Function to check if resource exists
resource_exists() {
    local check_command=("$@")
    "${check_command[@]}" &>/dev/null
}

# Banner
echo "=============================================================================="
echo "  AWS IoT Device Defender Security Implementation Cleanup"
echo "  Recipe: IoT Security Monitoring with Device Defender"
echo "=============================================================================="
echo

# Prerequisites check
log_info "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure' or set up your credentials."
    exit 1
fi

log_success "Prerequisites check completed"

# Try to load deployment information
if [[ -f "/tmp/iot-defender-deployment.env" ]]; then
    log_info "Loading deployment information from file..."
    source /tmp/iot-defender-deployment.env
    log_success "Loaded deployment information"
else
    log_warning "Deployment information file not found. Please provide resource names manually."
    
    # Get AWS account information
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Prompt for resource names
    echo
    read -p "Enter the Security Profile Name (or press Enter to skip): " SECURITY_PROFILE_NAME
    read -p "Enter the SNS Topic Name (or press Enter to skip): " SNS_TOPIC_NAME
    read -p "Enter the IAM Role Name (or press Enter to skip): " IAM_ROLE_NAME
    read -p "Enter the Random Suffix used (or press Enter to skip): " RANDOM_SUFFIX
    
    # Set derived variables if we have the suffix
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        SECURITY_PROFILE_NAME="${SECURITY_PROFILE_NAME:-IoTSecurityProfile-${RANDOM_SUFFIX}}"
        SNS_TOPIC_NAME="${SNS_TOPIC_NAME:-iot-security-alerts-${RANDOM_SUFFIX}}"
        IAM_ROLE_NAME="${IAM_ROLE_NAME:-IoTDeviceDefenderRole-${RANDOM_SUFFIX}}"
    fi
fi

# Display what will be deleted
echo
log_info "The following resources will be deleted:"
[[ -n "${SECURITY_PROFILE_NAME:-}" ]] && echo "  - Security Profile: ${SECURITY_PROFILE_NAME}"
[[ -n "${SECURITY_PROFILE_NAME:-}" ]] && echo "  - ML Security Profile: ${SECURITY_PROFILE_NAME}-ML"
[[ -n "${RANDOM_SUFFIX:-}" ]] && echo "  - Scheduled Audit: WeeklySecurityAudit-${RANDOM_SUFFIX}"
[[ -n "${RANDOM_SUFFIX:-}" ]] && echo "  - CloudWatch Alarm: IoT-SecurityViolations-${RANDOM_SUFFIX}"
[[ -n "${SNS_TOPIC_NAME:-}" ]] && echo "  - SNS Topic: ${SNS_TOPIC_NAME}"
[[ -n "${IAM_ROLE_NAME:-}" ]] && echo "  - IAM Role: ${IAM_ROLE_NAME}"

# Confirm deletion
if ! confirm_deletion "AWS IoT Device Defender"; then
    exit 0
fi

# Step 1: Remove Security Profile Attachments
if [[ -n "${SECURITY_PROFILE_NAME:-}" ]]; then
    log_info "Step 1: Removing security profile attachments..."
    
    # Detach primary security profile
    safe_detach "primary security profile from targets" \
        aws iot detach-security-profile \
        --security-profile-name "${SECURITY_PROFILE_NAME}" \
        --security-profile-target-arn \
        "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:all/registered-things"
    
    # Detach ML security profile
    safe_detach "ML security profile from targets" \
        aws iot detach-security-profile \
        --security-profile-name "${SECURITY_PROFILE_NAME}-ML" \
        --security-profile-target-arn \
        "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:all/registered-things"
    
    # Wait for detachment to propagate
    log_info "Waiting for security profile detachment to propagate..."
    sleep 5
else
    log_warning "Step 1: Security profile name not provided, skipping attachment removal"
fi

# Step 2: Delete Security Profiles
if [[ -n "${SECURITY_PROFILE_NAME:-}" ]]; then
    log_info "Step 2: Deleting security profiles..."
    
    # Delete primary security profile
    safe_delete "primary security profile" \
        aws iot delete-security-profile \
        --security-profile-name "${SECURITY_PROFILE_NAME}"
    
    # Delete ML security profile
    safe_delete "ML security profile" \
        aws iot delete-security-profile \
        --security-profile-name "${SECURITY_PROFILE_NAME}-ML"
else
    log_warning "Step 2: Security profile name not provided, skipping profile deletion"
fi

# Step 3: Remove Scheduled Audit
if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
    log_info "Step 3: Removing scheduled audit..."
    
    safe_delete "scheduled audit task" \
        aws iot delete-scheduled-audit \
        --scheduled-audit-name "WeeklySecurityAudit-${RANDOM_SUFFIX}"
else
    log_warning "Step 3: Random suffix not provided, skipping scheduled audit deletion"
fi

# Step 4: Clean Up CloudWatch Alarms
if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
    log_info "Step 4: Cleaning up CloudWatch alarms..."
    
    safe_delete "CloudWatch alarm" \
        aws cloudwatch delete-alarms \
        --alarm-names "IoT-SecurityViolations-${RANDOM_SUFFIX}"
else
    log_warning "Step 4: Random suffix not provided, skipping CloudWatch alarm deletion"
fi

# Step 5: Remove SNS Topic and Subscriptions
if [[ -n "${SNS_TOPIC_NAME:-}" ]]; then
    log_info "Step 5: Removing SNS topic and subscriptions..."
    
    # Get SNS topic ARN
    SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    
    # List and remove all subscriptions first
    if resource_exists aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}"; then
        log_info "Removing SNS subscriptions..."
        SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --query 'Subscriptions[].SubscriptionArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${SUBSCRIPTIONS}" ]]; then
            for subscription_arn in ${SUBSCRIPTIONS}; do
                if [[ "${subscription_arn}" != "PendingConfirmation" ]]; then
                    safe_delete "SNS subscription ${subscription_arn}" \
                        aws sns unsubscribe \
                        --subscription-arn "${subscription_arn}"
                fi
            done
        fi
        
        # Delete SNS topic
        safe_delete "SNS topic" \
            aws sns delete-topic --topic-arn "${SNS_TOPIC_ARN}"
    else
        log_warning "SNS topic ${SNS_TOPIC_NAME} not found"
    fi
else
    log_warning "Step 5: SNS topic name not provided, skipping SNS cleanup"
fi

# Step 6: Remove IAM Role
if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
    log_info "Step 6: Removing IAM role..."
    
    # Check if role exists
    if resource_exists aws iam get-role --role-name "${IAM_ROLE_NAME}"; then
        # Detach all attached policies
        log_info "Detaching policies from IAM role..."
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "${IAM_ROLE_NAME}" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in ${ATTACHED_POLICIES}; do
            safe_detach "policy ${policy_arn} from role" \
                aws iam detach-role-policy \
                --role-name "${IAM_ROLE_NAME}" \
                --policy-arn "${policy_arn}"
        done
        
        # Detach inline policies
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "${IAM_ROLE_NAME}" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        for policy_name in ${INLINE_POLICIES}; do
            safe_delete "inline policy ${policy_name}" \
                aws iam delete-role-policy \
                --role-name "${IAM_ROLE_NAME}" \
                --policy-name "${policy_name}"
        done
        
        # Delete IAM role
        safe_delete "IAM role" \
            aws iam delete-role --role-name "${IAM_ROLE_NAME}"
    else
        log_warning "IAM role ${IAM_ROLE_NAME} not found"
    fi
else
    log_warning "Step 6: IAM role name not provided, skipping IAM role deletion"
fi

# Step 7: Disable Device Defender Audit Configuration
log_info "Step 7: Disabling Device Defender audit configuration..."

# Reset audit configuration to minimal settings
safe_delete "Device Defender audit configuration" \
    aws iot update-account-audit-configuration \
    --audit-check-configurations \
    '{
      "AUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK": {"enabled": false},
      "CA_CERTIFICATE_EXPIRING_CHECK": {"enabled": false},
      "CONFLICTING_CLIENT_IDS_CHECK": {"enabled": false},
      "DEVICE_CERTIFICATE_EXPIRING_CHECK": {"enabled": false},
      "DEVICE_CERTIFICATE_SHARED_CHECK": {"enabled": false},
      "IOT_POLICY_OVERLY_PERMISSIVE_CHECK": {"enabled": false},
      "LOGGING_DISABLED_CHECK": {"enabled": false},
      "REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK": {"enabled": false},
      "REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK": {"enabled": false},
      "UNAUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK": {"enabled": false}
    }'

# Step 8: Clean Up Temporary Files
log_info "Step 8: Cleaning up temporary files..."

# Remove deployment information file
if [[ -f "/tmp/iot-defender-deployment.env" ]]; then
    rm -f /tmp/iot-defender-deployment.env
    log_success "Removed deployment information file"
fi

# Remove any remaining temporary files
rm -f /tmp/device-defender-trust-policy.json 2>/dev/null || true

log_success "Temporary files cleaned up"

# Step 9: Verification
log_info "Step 9: Verifying resource deletion..."

# Verify security profiles are deleted
if [[ -n "${SECURITY_PROFILE_NAME:-}" ]]; then
    if ! resource_exists aws iot describe-security-profile --security-profile-name "${SECURITY_PROFILE_NAME}"; then
        log_success "Verified: Primary security profile deleted"
    else
        log_warning "Primary security profile may still exist"
    fi
    
    if ! resource_exists aws iot describe-security-profile --security-profile-name "${SECURITY_PROFILE_NAME}-ML"; then
        log_success "Verified: ML security profile deleted"
    else
        log_warning "ML security profile may still exist"
    fi
fi

# Verify SNS topic is deleted
if [[ -n "${SNS_TOPIC_NAME:-}" ]]; then
    SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    if ! resource_exists aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}"; then
        log_success "Verified: SNS topic deleted"
    else
        log_warning "SNS topic may still exist"
    fi
fi

# Verify IAM role is deleted
if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
    if ! resource_exists aws iam get-role --role-name "${IAM_ROLE_NAME}"; then
        log_success "Verified: IAM role deleted"
    else
        log_warning "IAM role may still exist"
    fi
fi

echo
log_success "AWS IoT Device Defender cleanup completed!"
echo
echo "=============================================================================="
echo "  CLEANUP SUMMARY"
echo "=============================================================================="
echo "✅ Security profiles detached and deleted"
echo "✅ Scheduled audit tasks removed"
echo "✅ CloudWatch alarms deleted"
echo "✅ SNS topics and subscriptions removed"
echo "✅ IAM roles and policies cleaned up"
echo "✅ Device Defender audit configuration disabled"
echo "✅ Temporary files removed"
echo
echo "IMPORTANT NOTES:"
echo "- Device Defender audit configuration has been disabled"
echo "- Any remaining IoT devices are no longer monitored by Device Defender"
echo "- To re-enable monitoring, run the deployment script again"
echo "- Check AWS Console to verify all resources have been removed"
echo
echo "If you encounter any remaining resources, you can manually delete them"
echo "using the AWS Console or specific AWS CLI commands."
echo "=============================================================================="