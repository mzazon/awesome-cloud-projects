#!/bin/bash

# Real-time Clickstream Analytics Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CONFIG_FILE="${SCRIPT_DIR}/deployment-config.env"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "${LOG_FILE}" >&2
    exit 1
}

warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" | tee -a "${LOG_FILE}"
}

# Function to confirm destructive actions
confirm_destruction() {
    local resource_type="$1"
    local resource_name="$2"
    
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   ${resource_type}: ${resource_name}"
    echo ""
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log "Force destroy enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to safely delete AWS resources with retries
safe_delete() {
    local command="$1"
    local description="$2"
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if eval "$command" &>/dev/null; then
            log "✅ Successfully deleted: $description"
            return 0
        else
            if [[ $attempt -eq $max_attempts ]]; then
                warning "Failed to delete after $max_attempts attempts: $description"
                return 1
            fi
            warning "Attempt $attempt failed for: $description. Retrying in 5 seconds..."
            sleep 5
            ((attempt++))
        fi
    done
}

# Banner
echo "=========================================="
echo "Real-time Clickstream Analytics Cleanup"
echo "=========================================="
echo ""

log "Starting cleanup of clickstream analytics pipeline"

# Check if configuration file exists
if [[ ! -f "${CONFIG_FILE}" ]]; then
    error "Configuration file not found: ${CONFIG_FILE}"
    echo "Please ensure you run this script from the same location as the deployment script"
    echo "or manually set the required environment variables:"
    echo "  - STREAM_NAME"
    echo "  - TABLE_PREFIX"
    echo "  - BUCKET_NAME"
    echo "  - PROCESSOR_FUNCTION_NAME"
    echo "  - ANOMALY_FUNCTION_NAME"
    echo "  - ROLE_NAME"
    echo "  - DASHBOARD_NAME"
    exit 1
fi

# Load configuration
log "Loading deployment configuration..."
source "${CONFIG_FILE}"

# Validate required variables are set
required_vars=(
    "AWS_REGION"
    "AWS_ACCOUNT_ID"
    "STREAM_NAME"
    "TABLE_PREFIX"
    "BUCKET_NAME"
    "PROCESSOR_FUNCTION_NAME"
    "ANOMALY_FUNCTION_NAME"
    "ROLE_NAME"
    "DASHBOARD_NAME"
)

for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        error "Required variable $var is not set in configuration file"
    fi
done

log "Configuration loaded successfully"
log "  Stream Name: ${STREAM_NAME}"
log "  Table Prefix: ${TABLE_PREFIX}"
log "  Bucket Name: ${BUCKET_NAME}"
log "  Processor Function: ${PROCESSOR_FUNCTION_NAME}"
log "  Anomaly Function: ${ANOMALY_FUNCTION_NAME}"
log "  IAM Role: ${ROLE_NAME}"
log "  Dashboard: ${DASHBOARD_NAME}"

# Prerequisites check
log "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. Please install and configure AWS CLI v2"
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure'"
fi

log "Prerequisites check completed successfully"

# Confirmation
confirm_destruction "Clickstream Analytics Pipeline" "${STREAM_NAME}"

# Step 1: Delete Lambda event source mappings
log "Deleting Lambda event source mappings..."

# Delete processor function event source mappings
PROCESSOR_MAPPINGS=$(aws lambda list-event-source-mappings \
    --function-name "${PROCESSOR_FUNCTION_NAME}" \
    --query 'EventSourceMappings[].UUID' \
    --output text 2>/dev/null || echo "")

if [[ -n "${PROCESSOR_MAPPINGS}" ]]; then
    for uuid in $PROCESSOR_MAPPINGS; do
        safe_delete "aws lambda delete-event-source-mapping --uuid $uuid" \
                   "Event source mapping $uuid for processor function"
    done
else
    log "No event source mappings found for processor function"
fi

# Delete anomaly function event source mappings
ANOMALY_MAPPINGS=$(aws lambda list-event-source-mappings \
    --function-name "${ANOMALY_FUNCTION_NAME}" \
    --query 'EventSourceMappings[].UUID' \
    --output text 2>/dev/null || echo "")

if [[ -n "${ANOMALY_MAPPINGS}" ]]; then
    for uuid in $ANOMALY_MAPPINGS; do
        safe_delete "aws lambda delete-event-source-mapping --uuid $uuid" \
                   "Event source mapping $uuid for anomaly function"
    done
else
    log "No event source mappings found for anomaly function"
fi

# Wait for event source mappings to be fully deleted
log "Waiting for event source mappings to be fully deleted..."
sleep 15

# Step 2: Delete Lambda functions
log "Deleting Lambda functions..."

# Delete processor function
if aws lambda get-function --function-name "${PROCESSOR_FUNCTION_NAME}" &>/dev/null; then
    safe_delete "aws lambda delete-function --function-name ${PROCESSOR_FUNCTION_NAME}" \
               "Processor Lambda function: ${PROCESSOR_FUNCTION_NAME}"
else
    log "Processor function ${PROCESSOR_FUNCTION_NAME} not found, skipping"
fi

# Delete anomaly function
if aws lambda get-function --function-name "${ANOMALY_FUNCTION_NAME}" &>/dev/null; then
    safe_delete "aws lambda delete-function --function-name ${ANOMALY_FUNCTION_NAME}" \
               "Anomaly Lambda function: ${ANOMALY_FUNCTION_NAME}"
else
    log "Anomaly function ${ANOMALY_FUNCTION_NAME} not found, skipping"
fi

# Step 3: Delete DynamoDB tables
log "Deleting DynamoDB tables..."

TABLES=(
    "${TABLE_PREFIX}-page-metrics"
    "${TABLE_PREFIX}-session-metrics"
    "${TABLE_PREFIX}-counters"
)

for table in "${TABLES[@]}"; do
    if aws dynamodb describe-table --table-name "$table" &>/dev/null; then
        safe_delete "aws dynamodb delete-table --table-name $table" \
                   "DynamoDB table: $table"
    else
        log "Table $table not found, skipping"
    fi
done

# Wait for tables to be fully deleted
log "Waiting for DynamoDB tables to be fully deleted..."
for table in "${TABLES[@]}"; do
    while aws dynamodb describe-table --table-name "$table" &>/dev/null; do
        log "Waiting for table $table to be deleted..."
        sleep 10
    done
done

# Step 4: Delete Kinesis stream
log "Deleting Kinesis Data Stream..."

if aws kinesis describe-stream --stream-name "${STREAM_NAME}" &>/dev/null; then
    safe_delete "aws kinesis delete-stream --stream-name ${STREAM_NAME}" \
               "Kinesis stream: ${STREAM_NAME}"
    
    # Wait for stream to be fully deleted
    log "Waiting for Kinesis stream to be fully deleted..."
    while aws kinesis describe-stream --stream-name "${STREAM_NAME}" &>/dev/null; do
        log "Waiting for stream ${STREAM_NAME} to be deleted..."
        sleep 10
    done
else
    log "Stream ${STREAM_NAME} not found, skipping"
fi

# Step 5: Delete S3 bucket and contents
log "Deleting S3 bucket and contents..."

if aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
    # Delete all objects in the bucket first
    log "Emptying S3 bucket: ${BUCKET_NAME}"
    aws s3 rm "s3://${BUCKET_NAME}" --recursive --quiet || warning "Failed to empty bucket ${BUCKET_NAME}"
    
    # Delete the bucket
    safe_delete "aws s3 rb s3://${BUCKET_NAME}" \
               "S3 bucket: ${BUCKET_NAME}"
else
    log "Bucket ${BUCKET_NAME} not found, skipping"
fi

# Step 6: Delete CloudWatch dashboard
log "Deleting CloudWatch dashboard..."

if aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" &>/dev/null; then
    safe_delete "aws cloudwatch delete-dashboards --dashboard-names ${DASHBOARD_NAME}" \
               "CloudWatch dashboard: ${DASHBOARD_NAME}"
else
    log "Dashboard ${DASHBOARD_NAME} not found, skipping"
fi

# Step 7: Delete IAM role and policy
log "Deleting IAM role and policy..."

if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
    # Delete inline policies first
    POLICIES=$(aws iam list-role-policies --role-name "${ROLE_NAME}" \
               --query 'PolicyNames' --output text 2>/dev/null || echo "")
    
    if [[ -n "${POLICIES}" ]]; then
        for policy in $POLICIES; do
            safe_delete "aws iam delete-role-policy --role-name ${ROLE_NAME} --policy-name $policy" \
                       "IAM policy: $policy"
        done
    fi
    
    # Delete attached managed policies
    MANAGED_POLICIES=$(aws iam list-attached-role-policies --role-name "${ROLE_NAME}" \
                       --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    if [[ -n "${MANAGED_POLICIES}" ]]; then
        for policy_arn in $MANAGED_POLICIES; do
            safe_delete "aws iam detach-role-policy --role-name ${ROLE_NAME} --policy-arn $policy_arn" \
                       "Managed policy: $policy_arn"
        done
    fi
    
    # Delete the role
    safe_delete "aws iam delete-role --role-name ${ROLE_NAME}" \
               "IAM role: ${ROLE_NAME}"
else
    log "Role ${ROLE_NAME} not found, skipping"
fi

# Step 8: Clean up local files
log "Cleaning up local files..."

TEMP_DIR="${SCRIPT_DIR}/../temp"
if [[ -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
    log "✅ Removed temporary directory"
fi

# Step 9: Remove configuration file (optional)
read -p "Remove deployment configuration file? (yes/no): " -r
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    rm -f "${CONFIG_FILE}"
    log "✅ Removed configuration file"
else
    log "Configuration file preserved for future use"
fi

# Cleanup summary
echo ""
echo "=========================================="
echo "Cleanup Summary"
echo "=========================================="
echo "✅ Lambda functions deleted"
echo "✅ Event source mappings deleted"
echo "✅ DynamoDB tables deleted"
echo "✅ Kinesis stream deleted"
echo "✅ S3 bucket deleted"
echo "✅ CloudWatch dashboard deleted"
echo "✅ IAM role and policies deleted"
echo "✅ Local files cleaned up"
echo ""

# Final verification
log "Performing final verification..."

REMAINING_RESOURCES=()

# Check if any resources still exist
if aws kinesis describe-stream --stream-name "${STREAM_NAME}" &>/dev/null; then
    REMAINING_RESOURCES+=("Kinesis stream: ${STREAM_NAME}")
fi

if aws lambda get-function --function-name "${PROCESSOR_FUNCTION_NAME}" &>/dev/null; then
    REMAINING_RESOURCES+=("Lambda function: ${PROCESSOR_FUNCTION_NAME}")
fi

if aws lambda get-function --function-name "${ANOMALY_FUNCTION_NAME}" &>/dev/null; then
    REMAINING_RESOURCES+=("Lambda function: ${ANOMALY_FUNCTION_NAME}")
fi

if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
    REMAINING_RESOURCES+=("IAM role: ${ROLE_NAME}")
fi

if aws s3api head-bucket --bucket "${BUCKET_NAME}" &>/dev/null; then
    REMAINING_RESOURCES+=("S3 bucket: ${BUCKET_NAME}")
fi

for table in "${TABLES[@]}"; do
    if aws dynamodb describe-table --table-name "$table" &>/dev/null; then
        REMAINING_RESOURCES+=("DynamoDB table: $table")
    fi
done

if [[ ${#REMAINING_RESOURCES[@]} -gt 0 ]]; then
    echo ""
    echo "⚠️  WARNING: Some resources may still exist:"
    for resource in "${REMAINING_RESOURCES[@]}"; do
        echo "   - $resource"
    done
    echo ""
    echo "These resources may take additional time to be fully deleted,"
    echo "or there may have been errors during deletion."
    echo "Please check the AWS console and delete manually if needed."
    warning "Cleanup completed with some resources potentially remaining"
else
    echo "🎉 All resources successfully deleted!"
    log "Cleanup completed successfully - no remaining resources detected"
fi

echo ""
echo "📋 Cleanup log saved to: ${LOG_FILE}"
echo ""

log "Cleanup process finished"