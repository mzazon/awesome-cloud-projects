#!/bin/bash

# Infrastructure Monitoring Cleanup Script
# Removes CloudTrail, Config, and Systems Manager monitoring solution
# Recipe: infrastructure-monitoring-cloudtrail-config-systems-manager

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if resource exists
resource_exists() {
    local check_command="$1"
    eval "$check_command" &> /dev/null
    return $?
}

# Banner
echo "============================================================"
echo "  AWS Infrastructure Monitoring Cleanup Script"
echo "  CloudTrail + Config + Systems Manager"
echo "============================================================"
echo

# Check prerequisites
log "Checking prerequisites..."

if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed."
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured."
    exit 1
fi

success "Prerequisites check passed"

# Load configuration from deployment
CONFIG_FILE="/tmp/infrastructure-monitoring-config.env"
if [[ -f "${CONFIG_FILE}" ]]; then
    log "Loading configuration from ${CONFIG_FILE}..."
    source "${CONFIG_FILE}"
    success "Configuration loaded"
else
    warning "Configuration file not found. Please provide resource details manually."
    
    # Prompt for manual input
    echo
    read -p "AWS Region [us-east-1]: " AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}
    
    read -p "S3 Bucket name (monitoring bucket): " MONITORING_BUCKET
    if [[ -z "${MONITORING_BUCKET}" ]]; then
        error "S3 bucket name is required"
        exit 1
    fi
    
    read -p "SNS Topic name: " SNS_TOPIC
    read -p "Config Role name: " CONFIG_ROLE
    read -p "CloudTrail name: " CLOUDTRAIL_NAME
    read -p "Random suffix (for dashboard): " RANDOM_SUFFIX
    
    # Set derived variables
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}"
fi

# Confirmation
echo
warning "This will delete ALL infrastructure monitoring resources:"
log "  • S3 Bucket: ${MONITORING_BUCKET}"
log "  • SNS Topic: ${SNS_TOPIC}"
log "  • Config Role: ${CONFIG_ROLE}"
log "  • CloudTrail: ${CLOUDTRAIL_NAME}"
log "  • Config rules and configuration"
log "  • CloudWatch dashboard"
log "  • Systems Manager resources"
echo
warning "⚠️  This action cannot be undone!"
echo
read -p "Are you sure you want to proceed? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Cleanup cancelled by user"
    exit 0
fi

echo
log "Starting cleanup process..."

# Step 1: Remove CloudWatch dashboard
log "Step 1: Removing CloudWatch dashboard..."
if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
    if resource_exists "aws cloudwatch get-dashboard --dashboard-name InfrastructureMonitoring-${RANDOM_SUFFIX}"; then
        aws cloudwatch delete-dashboard --dashboard-name "InfrastructureMonitoring-${RANDOM_SUFFIX}"
        success "Deleted CloudWatch dashboard"
    else
        warning "CloudWatch dashboard not found"
    fi
else
    warning "Random suffix not available, skipping dashboard cleanup"
fi

# Step 2: Remove Config rules and configuration
log "Step 2: Removing Config rules and configuration..."

# Config rules to delete
declare -a config_rules=(
    "s3-bucket-public-access-prohibited"
    "encrypted-volumes"
    "root-access-key-check"
    "iam-password-policy"
)

for rule_name in "${config_rules[@]}"; do
    if resource_exists "aws configservice describe-config-rules --config-rule-names ${rule_name}"; then
        aws configservice delete-config-rule --config-rule-name ${rule_name}
        log "Deleted Config rule: ${rule_name}"
    else
        warning "Config rule ${rule_name} not found"
    fi
done

# Stop and delete configuration recorder
if resource_exists "aws configservice describe-configuration-recorders"; then
    log "Stopping configuration recorder..."
    aws configservice stop-configuration-recorder --configuration-recorder-name default 2>/dev/null || true
    
    log "Deleting delivery channel..."
    aws configservice delete-delivery-channel --delivery-channel-name default 2>/dev/null || true
    
    log "Deleting configuration recorder..."
    aws configservice delete-configuration-recorder --configuration-recorder-name default 2>/dev/null || true
    
    success "Config configuration removed"
else
    warning "Config not configured"
fi

# Step 3: Remove CloudTrail
log "Step 3: Removing CloudTrail..."
if [[ -n "${CLOUDTRAIL_NAME}" ]]; then
    if resource_exists "aws cloudtrail describe-trails --trail-name-list ${CLOUDTRAIL_NAME}"; then
        log "Stopping CloudTrail logging..."
        aws cloudtrail stop-logging --name ${CLOUDTRAIL_NAME}
        
        log "Deleting CloudTrail..."
        aws cloudtrail delete-trail --name ${CLOUDTRAIL_NAME}
        
        success "CloudTrail deleted: ${CLOUDTRAIL_NAME}"
    else
        warning "CloudTrail ${CLOUDTRAIL_NAME} not found"
    fi
else
    warning "CloudTrail name not provided"
fi

# Step 4: Remove Systems Manager resources
log "Step 4: Removing Systems Manager resources..."

# Delete maintenance windows
if [[ -n "${MAINTENANCE_WINDOW_ID:-}" ]]; then
    if resource_exists "aws ssm describe-maintenance-windows --window-ids ${MAINTENANCE_WINDOW_ID}"; then
        aws ssm delete-maintenance-window --window-id ${MAINTENANCE_WINDOW_ID}
        success "Deleted maintenance window: ${MAINTENANCE_WINDOW_ID}"
    else
        warning "Maintenance window ${MAINTENANCE_WINDOW_ID} not found"
    fi
else
    # Try to find and delete by name pattern
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        WINDOW_ID=$(aws ssm describe-maintenance-windows \
            --filters Key=Name,Values="InfrastructureMonitoring-${RANDOM_SUFFIX}" \
            --query 'WindowIdentities[0].WindowId' --output text 2>/dev/null || echo "")
        
        if [[ -n "${WINDOW_ID}" && "${WINDOW_ID}" != "None" ]]; then
            aws ssm delete-maintenance-window --window-id ${WINDOW_ID}
            success "Deleted maintenance window: ${WINDOW_ID}"
        else
            warning "Maintenance window not found"
        fi
    else
        warning "Cannot identify maintenance window without suffix"
    fi
fi

# Close any open OpsItems related to this deployment
log "Closing related OpsItems..."
if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
    OPS_ITEMS=$(aws ssm describe-ops-items \
        --ops-item-filters Key=Title,Values="Infrastructure Monitoring Setup Complete - ${RANDOM_SUFFIX}" \
        --query 'OpsItemSummaries[].OpsItemId' --output text 2>/dev/null || echo "")
    
    if [[ -n "${OPS_ITEMS}" && "${OPS_ITEMS}" != "None" ]]; then
        for ops_item in ${OPS_ITEMS}; do
            aws ssm update-ops-item \
                --ops-item-id ${ops_item} \
                --status Resolved 2>/dev/null || true
            log "Closed OpsItem: ${ops_item}"
        done
    else
        warning "No matching OpsItems found"
    fi
fi

# Step 5: Remove SNS topic
log "Step 5: Removing SNS topic..."
if [[ -n "${SNS_TOPIC}" ]]; then
    if resource_exists "aws sns get-topic-attributes --topic-arn ${SNS_TOPIC_ARN}"; then
        aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN}
        success "Deleted SNS topic: ${SNS_TOPIC}"
    else
        warning "SNS topic ${SNS_TOPIC} not found"
    fi
else
    warning "SNS topic name not provided"
fi

# Step 6: Remove IAM role
log "Step 6: Removing IAM role..."
if [[ -n "${CONFIG_ROLE}" ]]; then
    if resource_exists "aws iam get-role --role-name ${CONFIG_ROLE}"; then
        log "Detaching policies from IAM role..."
        aws iam detach-role-policy --role-name ${CONFIG_ROLE} \
            --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole 2>/dev/null || true
        
        aws iam delete-role-policy --role-name ${CONFIG_ROLE} --policy-name ConfigS3Policy 2>/dev/null || true
        
        log "Deleting IAM role..."
        aws iam delete-role --role-name ${CONFIG_ROLE}
        
        success "Deleted IAM role: ${CONFIG_ROLE}"
    else
        warning "IAM role ${CONFIG_ROLE} not found"
    fi
else
    warning "Config role name not provided"
fi

# Step 7: Handle S3 bucket cleanup
log "Step 7: Handling S3 bucket cleanup..."
if [[ -n "${MONITORING_BUCKET}" ]]; then
    if resource_exists "aws s3 ls s3://${MONITORING_BUCKET}"; then
        warning "S3 bucket contains monitoring data: ${MONITORING_BUCKET}"
        echo
        log "Options for S3 bucket cleanup:"
        log "  1. Delete all contents and bucket (permanent data loss)"
        log "  2. Keep bucket and contents (you can clean up manually later)"
        echo
        read -p "Choose option [1/2]: " -n 1 -r BUCKET_CHOICE
        echo
        
        case $BUCKET_CHOICE in
            1)
                log "Deleting all bucket contents..."
                aws s3 rm s3://${MONITORING_BUCKET} --recursive
                
                log "Deleting bucket..."
                aws s3 rb s3://${MONITORING_BUCKET}
                
                success "S3 bucket deleted: ${MONITORING_BUCKET}"
                ;;
            2)
                warning "S3 bucket preserved: ${MONITORING_BUCKET}"
                warning "Remember to clean up manually to avoid ongoing charges"
                ;;
            *)
                warning "Invalid choice. S3 bucket preserved: ${MONITORING_BUCKET}"
                ;;
        esac
    else
        warning "S3 bucket ${MONITORING_BUCKET} not found"
    fi
else
    warning "S3 bucket name not provided"
fi

# Step 8: Cleanup temporary files and configuration
log "Step 8: Cleaning up temporary files..."
rm -f /tmp/infrastructure-monitoring-config.env
rm -f /tmp/config-trust-policy.json /tmp/config-s3-policy.json
rm -f /tmp/cloudtrail-bucket-policy.json /tmp/dashboard-body.json
success "Temporary files cleaned up"

# Summary
echo
echo "============================================================"
echo "  🧹 CLEANUP COMPLETED! 🧹"
echo "============================================================"
echo
success "Infrastructure monitoring resources have been removed"
echo
log "Cleanup summary:"
log "  ✅ CloudWatch dashboard removed"
log "  ✅ Config rules and configuration removed"
log "  ✅ CloudTrail removed"
log "  ✅ Systems Manager resources removed"
log "  ✅ SNS topic removed"
log "  ✅ IAM role removed"
if [[ "${BUCKET_CHOICE:-}" == "1" ]]; then
    log "  ✅ S3 bucket and contents deleted"
else
    log "  ⚠️  S3 bucket preserved (manual cleanup needed)"
fi
echo
warning "Note: It may take a few minutes for all resources to be fully removed from the AWS console"
echo
if [[ "${BUCKET_CHOICE:-}" != "1" && -n "${MONITORING_BUCKET}" ]]; then
    warning "Don't forget to manually clean up S3 bucket: ${MONITORING_BUCKET}"
fi
echo
log "Infrastructure monitoring cleanup complete!"