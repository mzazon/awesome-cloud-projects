#!/bin/bash

# Destroy script for AWS Systems Manager State Manager Configuration Management
# This script removes all resources created by the deploy.sh script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_LOG="${SCRIPT_DIR}/cleanup.log"
CONFIG_FILE="${SCRIPT_DIR}/../config/deployment.env"

# Start logging
exec > >(tee -a "${CLEANUP_LOG}") 2>&1

log "Starting AWS Systems Manager State Manager cleanup..."

# Check if config file exists
if [ ! -f "${CONFIG_FILE}" ]; then
    error "Configuration file not found: ${CONFIG_FILE}"
    error "Cannot proceed with cleanup without deployment configuration."
    exit 1
fi

# Load configuration
log "Loading deployment configuration..."
source "${CONFIG_FILE}"

# Verify required variables
REQUIRED_VARS=(
    "AWS_REGION" "AWS_ACCOUNT_ID" "RANDOM_SUFFIX" "ROLE_NAME" "POLICY_NAME" 
    "ASSOCIATION_NAME" "SNS_TOPIC_NAME" "CLOUDWATCH_LOG_GROUP" "SNS_TOPIC_ARN"
    "ROLE_ARN" "POLICY_ARN" "SECURITY_DOC_NAME" "REMEDIATION_DOC_NAME"
    "COMPLIANCE_DOC_NAME" "DASHBOARD_NAME"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        error "Required variable $var is not set in configuration file."
        exit 1
    fi
done

success "Configuration loaded successfully"

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

success "Prerequisites check passed"

# Confirmation prompt
echo ""
echo "=================================================================================="
echo "                           RESOURCE CLEANUP CONFIRMATION"
echo "=================================================================================="
echo ""
echo "⚠️  WARNING: This will permanently delete the following resources:"
echo ""
echo "📋 Resources to be deleted:"
echo "   • IAM Role: ${ROLE_NAME}"
echo "   • IAM Policy: ${POLICY_NAME}"
echo "   • SNS Topic: ${SNS_TOPIC_NAME}"
echo "   • CloudWatch Log Group: ${CLOUDWATCH_LOG_GROUP}"
echo "   • Security Document: ${SECURITY_DOC_NAME}"
echo "   • Remediation Document: ${REMEDIATION_DOC_NAME}"
echo "   • Compliance Document: ${COMPLIANCE_DOC_NAME}"
echo "   • CloudWatch Dashboard: ${DASHBOARD_NAME}"
echo "   • CloudWatch Alarms: 2 monitoring alarms"
if [ -n "${AGENT_ASSOCIATION_ID:-}" ]; then
    echo "   • SSM Agent Association: ${AGENT_ASSOCIATION_ID}"
fi
if [ -n "${SECURITY_ASSOCIATION_ID:-}" ]; then
    echo "   • Security Association: ${SECURITY_ASSOCIATION_ID}"
fi
echo ""
echo "🌍 Region: ${AWS_REGION}"
echo "🏷️  Account: ${AWS_ACCOUNT_ID}"
echo ""
echo "=================================================================================="
echo ""

# Prompt for confirmation
read -p "Are you sure you want to proceed? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log "Cleanup cancelled by user."
    exit 0
fi

echo ""
log "Starting resource cleanup..."

# Function to safely delete resources with error handling
safe_delete() {
    local description="$1"
    local command="$2"
    
    log "Deleting ${description}..."
    
    if eval "$command" 2>/dev/null; then
        success "${description} deleted successfully"
        return 0
    else
        warning "Failed to delete ${description} or it may not exist"
        return 1
    fi
}

# Step 1: Delete State Manager associations
if [ -n "${SECURITY_ASSOCIATION_ID:-}" ]; then
    safe_delete "Security configuration association" \
        "aws ssm delete-association --association-id '${SECURITY_ASSOCIATION_ID}'"
fi

if [ -n "${AGENT_ASSOCIATION_ID:-}" ]; then
    safe_delete "SSM Agent update association" \
        "aws ssm delete-association --association-id '${AGENT_ASSOCIATION_ID}'"
fi

# Step 2: Delete Custom SSM Documents
safe_delete "Security configuration document" \
    "aws ssm delete-document --name '${SECURITY_DOC_NAME}'"

safe_delete "Remediation automation document" \
    "aws ssm delete-document --name '${REMEDIATION_DOC_NAME}'"

safe_delete "Compliance report document" \
    "aws ssm delete-document --name '${COMPLIANCE_DOC_NAME}'"

# Step 3: Delete CloudWatch resources
safe_delete "CloudWatch alarms" \
    "aws cloudwatch delete-alarms --alarm-names '${ALARM_FAILURES:-SSM-Association-Failures-${RANDOM_SUFFIX}}' '${ALARM_VIOLATIONS:-SSM-Compliance-Violations-${RANDOM_SUFFIX}}'"

safe_delete "CloudWatch dashboard" \
    "aws cloudwatch delete-dashboards --dashboard-names '${DASHBOARD_NAME}'"

safe_delete "CloudWatch log group" \
    "aws logs delete-log-group --log-group-name '${CLOUDWATCH_LOG_GROUP}'"

# Step 4: Delete SNS resources
safe_delete "SNS topic" \
    "aws sns delete-topic --topic-arn '${SNS_TOPIC_ARN}'"

# Step 5: Delete IAM resources
log "Deleting IAM resources..."

# Detach policies from role
log "Detaching policies from IAM role..."
aws iam detach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn "${POLICY_ARN}" 2>/dev/null || warning "Failed to detach custom policy"

aws iam detach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || warning "Failed to detach AWS managed policy"

# Delete custom policy
safe_delete "Custom IAM policy" \
    "aws iam delete-policy --policy-arn '${POLICY_ARN}'"

# Delete IAM role
safe_delete "IAM role" \
    "aws iam delete-role --role-name '${ROLE_NAME}'"

# Step 6: Cleanup local files and configuration
log "Cleaning up local files..."

# Remove deployment log files (keep current cleanup log)
find "${SCRIPT_DIR}" -name "deployment.log*" -type f -delete 2>/dev/null || true

# Remove configuration directory
if [ -d "${SCRIPT_DIR}/../config" ]; then
    rm -rf "${SCRIPT_DIR}/../config"
    success "Configuration directory removed"
fi

# Remove any remaining temporary files
rm -f "${SCRIPT_DIR}/state-manager-trust-policy.json"
rm -f "${SCRIPT_DIR}/state-manager-policy.json"
rm -f "${SCRIPT_DIR}/security-config-document.json"
rm -f "${SCRIPT_DIR}/remediation-document.json"
rm -f "${SCRIPT_DIR}/compliance-report.json"
rm -f "${SCRIPT_DIR}/dashboard-config.json"

success "Local files cleaned up"

# Step 7: Verify cleanup
log "Verifying resource cleanup..."

# Check if IAM role still exists
if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
    warning "IAM role ${ROLE_NAME} still exists"
else
    success "IAM role cleanup verified"
fi

# Check if SNS topic still exists
if aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &>/dev/null; then
    warning "SNS topic ${SNS_TOPIC_ARN} still exists"
else
    success "SNS topic cleanup verified"
fi

# Check if CloudWatch log group still exists
if aws logs describe-log-groups --log-group-name-prefix "${CLOUDWATCH_LOG_GROUP}" --query 'logGroups[0].logGroupName' --output text | grep -q "${CLOUDWATCH_LOG_GROUP}"; then
    warning "CloudWatch log group ${CLOUDWATCH_LOG_GROUP} still exists"
else
    success "CloudWatch log group cleanup verified"
fi

# Check if SSM documents still exist
if aws ssm describe-document --name "${SECURITY_DOC_NAME}" &>/dev/null; then
    warning "SSM document ${SECURITY_DOC_NAME} still exists"
else
    success "SSM document cleanup verified"
fi

# Final summary
echo ""
echo "=================================================================================="
echo "                    AWS Systems Manager State Manager Cleanup"
echo "=================================================================================="
echo ""
echo "✅ Cleanup completed successfully!"
echo ""
echo "📋 Resources Removed:"
echo "   • IAM Role: ${ROLE_NAME}"
echo "   • IAM Policy: ${POLICY_NAME}"
echo "   • SNS Topic: ${SNS_TOPIC_NAME}"
echo "   • CloudWatch Log Group: ${CLOUDWATCH_LOG_GROUP}"
echo "   • Security Document: ${SECURITY_DOC_NAME}"
echo "   • Remediation Document: ${REMEDIATION_DOC_NAME}"
echo "   • Compliance Document: ${COMPLIANCE_DOC_NAME}"
echo "   • CloudWatch Dashboard: ${DASHBOARD_NAME}"
echo "   • CloudWatch Alarms: 2 monitoring alarms"
if [ -n "${AGENT_ASSOCIATION_ID:-}" ]; then
    echo "   • SSM Agent Association: ${AGENT_ASSOCIATION_ID}"
fi
if [ -n "${SECURITY_ASSOCIATION_ID:-}" ]; then
    echo "   • Security Association: ${SECURITY_ASSOCIATION_ID}"
fi
echo ""
echo "🧹 Local configuration files removed"
echo "📝 Cleanup log saved to: ${CLEANUP_LOG}"
echo ""
echo "⚠️  Manual Cleanup Required:"
echo "   1. Remove Environment=Demo tags from EC2 instances if no longer needed"
echo "   2. Check for any remaining S3 buckets with association output logs"
echo "   3. Review CloudWatch metrics for any remaining custom metrics"
echo ""
echo "💡 To redeploy, run: ./deploy.sh"
echo ""
echo "=================================================================================="

log "Cleanup completed successfully!"

# Exit with success
exit 0