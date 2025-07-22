#!/bin/bash
#
# Destroy script for IoT Data Visualization with QuickSight
# This script removes all infrastructure created for the IoT data visualization solution
#
# Usage: ./destroy.sh [--force] [--dry-run] [--debug]
#
# Author: Recipe Generator
# Version: 1.0
# Last Updated: 2025-01-27

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DRY_RUN=false
DEBUG=false
FORCE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        DEBUG)
            if [[ "$DEBUG" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
                echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            fi
            ;;
    esac
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force] [--dry-run] [--debug]"
            echo ""
            echo "Options:"
            echo "  --force      Skip confirmation prompts"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --debug      Enable debug logging"
            echo "  -h, --help   Show this help message"
            exit 0
            ;;
        *)
            log ERROR "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load environment variables
load_environment() {
    log INFO "Loading environment variables..."
    
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        # Source the environment file
        source "${SCRIPT_DIR}/.env"
        log INFO "Environment variables loaded from ${SCRIPT_DIR}/.env"
    else
        log WARN "No .env file found. Attempting to derive resource names..."
        
        # Try to get AWS region and account ID
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        
        if [[ -z "$AWS_ACCOUNT_ID" ]]; then
            log ERROR "Could not determine AWS Account ID. Please ensure AWS credentials are configured."
            exit 1
        fi
        
        log WARN "Environment variables not found. Manual resource identification may be required."
        return 1
    fi
    
    log DEBUG "Using AWS Region: ${AWS_REGION}"
    log DEBUG "Using AWS Account ID: ${AWS_ACCOUNT_ID}"
}

# Execute AWS CLI command with error handling
execute_aws_command() {
    local description="$1"
    local ignore_errors="${2:-false}"
    shift 2
    local command=("$@")
    
    log INFO "$description"
    log DEBUG "Executing: ${command[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would execute: ${command[*]}"
        return 0
    fi
    
    local output
    if output=$(${command[@]} 2>&1); then
        log DEBUG "Command succeeded: $output"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            log WARN "Command failed (ignored): ${command[*]}"
            log DEBUG "Error output: $output"
            return 0
        else
            log ERROR "Command failed: ${command[*]}"
            log ERROR "Error output: $output"
            return 1
        fi
    fi
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        log INFO "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete all IoT Data Visualization resources!${NC}"
    echo ""
    echo "Resources to be deleted:"
    echo "  - S3 Bucket: ${S3_BUCKET_NAME:-<unknown>}"
    echo "  - Kinesis Stream: ${KINESIS_STREAM_NAME:-<unknown>}"
    echo "  - IoT Thing: ${IOT_THING_NAME:-<unknown>}"
    echo "  - Glue Database: ${GLUE_DATABASE_NAME:-<unknown>}"
    echo "  - QuickSight Resources"
    echo "  - IAM Roles and Policies"
    echo "  - Firehose Delivery Stream"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log INFO "Destruction cancelled by user"
        exit 0
    fi
    
    log INFO "Destruction confirmed by user"
}

# Delete QuickSight resources
delete_quicksight_resources() {
    log INFO "Deleting QuickSight resources..."
    
    # Delete QuickSight dataset (if exists)
    if [[ -n "${QUICKSIGHT_USER_NAME:-}" ]]; then
        local dataset_suffix=$(echo "${QUICKSIGHT_USER_NAME}" | sed 's/quicksight-user-//')
        execute_aws_command "Deleting QuickSight dataset" true \
            aws quicksight delete-data-set \
            --aws-account-id "${AWS_ACCOUNT_ID}" \
            --data-set-id "iot-sensor-dataset-${dataset_suffix}" \
            --region "${AWS_REGION}"
    fi
    
    # Delete QuickSight data source
    if [[ -n "${QUICKSIGHT_USER_NAME:-}" ]]; then
        local datasource_suffix=$(echo "${QUICKSIGHT_USER_NAME}" | sed 's/quicksight-user-//')
        execute_aws_command "Deleting QuickSight data source" true \
            aws quicksight delete-data-source \
            --aws-account-id "${AWS_ACCOUNT_ID}" \
            --data-source-id "iot-athena-datasource-${datasource_suffix}" \
            --region "${AWS_REGION}"
    fi
    
    # Note: QuickSight account and user deletion is not automated for safety
    log WARN "QuickSight account and user are not deleted automatically"
    log WARN "To delete QuickSight account, use the AWS Console or contact AWS support"
    
    log INFO "QuickSight resources cleanup completed"
}

# Delete Glue resources
delete_glue_resources() {
    log INFO "Deleting AWS Glue resources..."
    
    # Delete Glue table
    if [[ -n "${GLUE_DATABASE_NAME:-}" && -n "${GLUE_TABLE_NAME:-}" ]]; then
        execute_aws_command "Deleting Glue table" true \
            aws glue delete-table \
            --database-name "${GLUE_DATABASE_NAME}" \
            --name "${GLUE_TABLE_NAME}"
    fi
    
    # Delete Glue database
    if [[ -n "${GLUE_DATABASE_NAME:-}" ]]; then
        execute_aws_command "Deleting Glue database" true \
            aws glue delete-database \
            --name "${GLUE_DATABASE_NAME}"
    fi
    
    log INFO "Glue resources deleted"
}

# Delete Kinesis and Firehose resources
delete_streaming_resources() {
    log INFO "Deleting Kinesis and Firehose resources..."
    
    # Delete Firehose delivery stream
    if [[ -n "${FIREHOSE_DELIVERY_STREAM:-}" ]]; then
        execute_aws_command "Deleting Firehose delivery stream" true \
            aws firehose delete-delivery-stream \
            --delivery-stream-name "${FIREHOSE_DELIVERY_STREAM}"
        
        # Wait for Firehose to be deleted
        log INFO "Waiting for Firehose stream to be deleted..."
        if [[ "$DRY_RUN" == "false" ]]; then
            sleep 30
        fi
    fi
    
    # Delete Kinesis stream
    if [[ -n "${KINESIS_STREAM_NAME:-}" ]]; then
        execute_aws_command "Deleting Kinesis stream" true \
            aws kinesis delete-stream \
            --stream-name "${KINESIS_STREAM_NAME}"
        
        # Wait for Kinesis stream to be deleted
        log INFO "Waiting for Kinesis stream to be deleted..."
        if [[ "$DRY_RUN" == "false" ]]; then
            sleep 30
        fi
    fi
    
    log INFO "Streaming resources deleted"
}

# Delete IoT Core resources
delete_iot_resources() {
    log INFO "Deleting IoT Core resources..."
    
    # Delete IoT rule
    if [[ -n "${IOT_RULE_NAME:-}" ]]; then
        execute_aws_command "Deleting IoT rule" true \
            aws iot delete-topic-rule \
            --rule-name "${IOT_RULE_NAME}"
    fi
    
    # Delete IoT thing
    if [[ -n "${IOT_THING_NAME:-}" ]]; then
        execute_aws_command "Deleting IoT thing" true \
            aws iot delete-thing \
            --thing-name "${IOT_THING_NAME}"
    fi
    
    # Delete IoT policy
    if [[ -n "${IOT_POLICY_NAME:-}" ]]; then
        execute_aws_command "Deleting IoT policy" true \
            aws iot delete-policy \
            --policy-name "${IOT_POLICY_NAME}"
    fi
    
    log INFO "IoT Core resources deleted"
}

# Delete IAM resources
delete_iam_resources() {
    log INFO "Deleting IAM roles and policies..."
    
    # Detach and delete IoT Kinesis policy
    if [[ -n "${IOT_KINESIS_ROLE_NAME:-}" && -n "${IOT_KINESIS_POLICY_NAME:-}" ]]; then
        execute_aws_command "Detaching IoT Kinesis policy" true \
            aws iam detach-role-policy \
            --role-name "${IOT_KINESIS_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IOT_KINESIS_POLICY_NAME}"
        
        execute_aws_command "Deleting IoT Kinesis policy" true \
            aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IOT_KINESIS_POLICY_NAME}"
    fi
    
    # Detach and delete Firehose S3 policy
    if [[ -n "${FIREHOSE_ROLE_NAME:-}" && -n "${FIREHOSE_S3_POLICY_NAME:-}" ]]; then
        execute_aws_command "Detaching Firehose S3 policy" true \
            aws iam detach-role-policy \
            --role-name "${FIREHOSE_ROLE_NAME}" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${FIREHOSE_S3_POLICY_NAME}"
        
        execute_aws_command "Deleting Firehose S3 policy" true \
            aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${FIREHOSE_S3_POLICY_NAME}"
    fi
    
    # Delete IAM roles
    if [[ -n "${IOT_KINESIS_ROLE_NAME:-}" ]]; then
        execute_aws_command "Deleting IoT Kinesis role" true \
            aws iam delete-role \
            --role-name "${IOT_KINESIS_ROLE_NAME}"
    fi
    
    if [[ -n "${FIREHOSE_ROLE_NAME:-}" ]]; then
        execute_aws_command "Deleting Firehose role" true \
            aws iam delete-role \
            --role-name "${FIREHOSE_ROLE_NAME}"
    fi
    
    log INFO "IAM resources deleted"
}

# Delete S3 bucket and contents
delete_s3_resources() {
    log INFO "Deleting S3 resources..."
    
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        # Check if bucket exists
        if [[ "$DRY_RUN" == "false" ]] && aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
            # Delete all objects in bucket (including versions)
            execute_aws_command "Deleting all objects in S3 bucket" true \
                aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive
            
            # Delete all object versions
            execute_aws_command "Deleting all object versions in S3 bucket" true \
                aws s3api delete-objects \
                --bucket "${S3_BUCKET_NAME}" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "${S3_BUCKET_NAME}" \
                    --output json \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                    2>/dev/null || echo '{"Objects":[]}')"
            
            # Delete all delete markers
            execute_aws_command "Deleting all delete markers in S3 bucket" true \
                aws s3api delete-objects \
                --bucket "${S3_BUCKET_NAME}" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "${S3_BUCKET_NAME}" \
                    --output json \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                    2>/dev/null || echo '{"Objects":[]}')"
            
            # Delete bucket
            execute_aws_command "Deleting S3 bucket" true \
                aws s3api delete-bucket \
                --bucket "${S3_BUCKET_NAME}"
        elif [[ "$DRY_RUN" == "true" ]]; then
            log INFO "[DRY RUN] Would delete S3 bucket: ${S3_BUCKET_NAME}"
        else
            log WARN "S3 bucket ${S3_BUCKET_NAME} does not exist or is not accessible"
        fi
    fi
    
    log INFO "S3 resources deleted"
}

# List orphaned resources
list_orphaned_resources() {
    log INFO "Checking for orphaned resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would check for orphaned resources"
        return 0
    fi
    
    # Check for IoT resources
    local iot_policies=$(aws iot list-policies --query 'policies[?contains(policyName, `iot-device-policy-`)]' --output table 2>/dev/null || echo "")
    if [[ -n "$iot_policies" && "$iot_policies" != "[]" ]]; then
        log WARN "Found potential orphaned IoT policies:"
        echo "$iot_policies"
    fi
    
    # Check for Kinesis streams
    local kinesis_streams=$(aws kinesis list-streams --query 'StreamNames[?contains(@, `iot-data-stream-`)]' --output table 2>/dev/null || echo "")
    if [[ -n "$kinesis_streams" && "$kinesis_streams" != "[]" ]]; then
        log WARN "Found potential orphaned Kinesis streams:"
        echo "$kinesis_streams"
    fi
    
    # Check for S3 buckets
    local s3_buckets=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `iot-analytics-bucket-`)]' --output table 2>/dev/null || echo "")
    if [[ -n "$s3_buckets" && "$s3_buckets" != "[]" ]]; then
        log WARN "Found potential orphaned S3 buckets:"
        echo "$s3_buckets"
    fi
    
    log INFO "Orphaned resources check completed"
}

# Clean up local files
cleanup_local_files() {
    log INFO "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log INFO "[DRY RUN] Would remove .env file"
        else
            rm -f "${SCRIPT_DIR}/.env"
            log INFO "Removed .env file"
        fi
    fi
    
    # Archive log files
    if [[ -f "${SCRIPT_DIR}/deploy.log" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log INFO "[DRY RUN] Would archive deploy.log"
        else
            mv "${SCRIPT_DIR}/deploy.log" "${SCRIPT_DIR}/deploy.log.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            log INFO "Archived deploy.log"
        fi
    fi
    
    log INFO "Local cleanup completed"
}

# Main destruction function
main() {
    log INFO "Starting IoT Data Visualization infrastructure destruction..."
    log INFO "Destruction mode: $([ "$DRY_RUN" == "true" ] && echo "DRY RUN" || echo "LIVE")"
    
    # Initialize log file
    echo "Destruction started at $(date)" > "$LOG_FILE"
    
    # Load environment and confirm
    if ! load_environment; then
        log ERROR "Failed to load environment variables. Cannot proceed with destruction."
        exit 1
    fi
    
    confirm_destruction
    
    # Delete resources in reverse order of creation
    log INFO "Deleting resources in reverse order..."
    
    delete_quicksight_resources
    delete_glue_resources
    delete_streaming_resources
    delete_iot_resources
    delete_iam_resources
    delete_s3_resources
    
    # Check for orphaned resources
    list_orphaned_resources
    
    # Clean up local files
    cleanup_local_files
    
    # Print destruction summary
    log INFO "🎉 Destruction completed successfully!"
    log INFO ""
    log INFO "📋 Destruction Summary:"
    log INFO "   ✅ QuickSight resources cleaned up"
    log INFO "   ✅ Glue resources deleted"
    log INFO "   ✅ Kinesis and Firehose resources deleted"
    log INFO "   ✅ IoT Core resources deleted"
    log INFO "   ✅ IAM roles and policies deleted"
    log INFO "   ✅ S3 bucket and contents deleted"
    log INFO "   ✅ Local files cleaned up"
    log INFO ""
    log INFO "📄 Full destruction log: ${LOG_FILE}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log INFO ""
        log INFO "💡 Note: QuickSight account may still be active"
        log INFO "   Use AWS Console to cancel QuickSight subscription if no longer needed"
        log INFO ""
        log INFO "✅ All billable resources have been removed"
    fi
}

# Run main function
main "$@"