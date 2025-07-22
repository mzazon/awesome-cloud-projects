#!/bin/bash

# AWS DataSync Data Transfer Automation - Deployment Script
# This script deploys the complete DataSync solution for automated data transfer

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN="${DRY_RUN:-false}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
trap 'log "ERROR" "Script failed at line $LINENO"; exit 1' ERR

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS DataSync Data Transfer Automation

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without making changes
    -r, --region        AWS region (default: from AWS CLI config)
    -v, --verbose       Enable verbose logging
    --source-bucket     Source S3 bucket name (optional, will be generated if not provided)
    --dest-bucket       Destination S3 bucket name (optional, will be generated if not provided)

EXAMPLES:
    $0                                  # Deploy with default settings
    $0 --dry-run                        # Show deployment plan
    $0 --region us-west-2               # Deploy to specific region
    $0 --source-bucket my-source        # Use specific bucket names

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --source-bucket)
            SOURCE_BUCKET_NAME="$2"
            shift 2
            ;;
        --dest-bucket)
            DEST_BUCKET_NAME="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Initialize logging
log "INFO" "Starting DataSync deployment script"
log "INFO" "Log file: $LOG_FILE"

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ "${AWS_CLI_VERSION}" < "2.0.0" ]]; then
        log "WARN" "AWS CLI version ${AWS_CLI_VERSION} detected. Version 2.x is recommended"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    # Check required tools
    local required_tools=("jq" "cut" "grep" "sed")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log "ERROR" "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    log "INFO" "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Set AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            log "ERROR" "AWS region not configured. Use --region or configure AWS CLI"
            exit 1
        fi
    fi
    export AWS_REGION
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_ACCOUNT_ID
    
    # Generate unique identifiers
    if [[ -z "${SOURCE_BUCKET_NAME:-}" ]] || [[ -z "${DEST_BUCKET_NAME:-}" ]]; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 8 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo "$(date +%s)$(shuf -i 1000-9999 -n 1)")
    fi
    
    # Set resource names
    export SOURCE_BUCKET_NAME="${SOURCE_BUCKET_NAME:-datasync-source-${RANDOM_SUFFIX}}"
    export DEST_BUCKET_NAME="${DEST_BUCKET_NAME:-datasync-dest-${RANDOM_SUFFIX}}"
    export DATASYNC_ROLE_NAME="DataSyncServiceRole-${RANDOM_SUFFIX}"
    export DATASYNC_TASK_NAME="DataSyncTask-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_ROLE_NAME="DataSyncEventBridgeRole-${RANDOM_SUFFIX}"
    export LOG_GROUP_NAME="/aws/datasync/${DATASYNC_TASK_NAME}"
    
    log "INFO" "Environment configured:"
    log "INFO" "  AWS Region: $AWS_REGION"
    log "INFO" "  AWS Account: $AWS_ACCOUNT_ID"
    log "INFO" "  Source Bucket: $SOURCE_BUCKET_NAME"
    log "INFO" "  Destination Bucket: $DEST_BUCKET_NAME"
    log "INFO" "  DataSync Role: $DATASYNC_ROLE_NAME"
    log "INFO" "  DataSync Task: $DATASYNC_TASK_NAME"
}

# Create S3 buckets
create_s3_buckets() {
    log "INFO" "Creating S3 buckets..."
    
    # Create source bucket
    if ! aws s3api head-bucket --bucket "$SOURCE_BUCKET_NAME" 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would create source bucket: $SOURCE_BUCKET_NAME"
        else
            if [[ "$AWS_REGION" == "us-east-1" ]]; then
                aws s3api create-bucket --bucket "$SOURCE_BUCKET_NAME" --region "$AWS_REGION"
            else
                aws s3api create-bucket \
                    --bucket "$SOURCE_BUCKET_NAME" \
                    --region "$AWS_REGION" \
                    --create-bucket-configuration LocationConstraint="$AWS_REGION"
            fi
            log "INFO" "Created source bucket: $SOURCE_BUCKET_NAME"
        fi
    else
        log "INFO" "Source bucket already exists: $SOURCE_BUCKET_NAME"
    fi
    
    # Create destination bucket
    if ! aws s3api head-bucket --bucket "$DEST_BUCKET_NAME" 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would create destination bucket: $DEST_BUCKET_NAME"
        else
            if [[ "$AWS_REGION" == "us-east-1" ]]; then
                aws s3api create-bucket --bucket "$DEST_BUCKET_NAME" --region "$AWS_REGION"
            else
                aws s3api create-bucket \
                    --bucket "$DEST_BUCKET_NAME" \
                    --region "$AWS_REGION" \
                    --create-bucket-configuration LocationConstraint="$AWS_REGION"
            fi
            log "INFO" "Created destination bucket: $DEST_BUCKET_NAME"
        fi
    else
        log "INFO" "Destination bucket already exists: $DEST_BUCKET_NAME"
    fi
    
    # Upload sample data
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Uploading sample data..."
        echo "Sample data for DataSync transfer - $(date)" > /tmp/sample-file.txt
        aws s3 cp /tmp/sample-file.txt "s3://$SOURCE_BUCKET_NAME/"
        aws s3 cp /tmp/sample-file.txt "s3://$SOURCE_BUCKET_NAME/folder1/"
        aws s3 cp /tmp/sample-file.txt "s3://$SOURCE_BUCKET_NAME/folder2/"
        rm -f /tmp/sample-file.txt
        log "INFO" "Sample data uploaded successfully"
    fi
}

# Create IAM roles and policies
create_iam_resources() {
    log "INFO" "Creating IAM resources..."
    
    # Create trust policy for DataSync service
    local trust_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "datasync.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)
    
    # Create DataSync service role
    if ! aws iam get-role --role-name "$DATASYNC_ROLE_NAME" &>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would create DataSync IAM role: $DATASYNC_ROLE_NAME"
        else
            echo "$trust_policy" > /tmp/datasync-trust-policy.json
            aws iam create-role \
                --role-name "$DATASYNC_ROLE_NAME" \
                --assume-role-policy-document file:///tmp/datasync-trust-policy.json
            rm -f /tmp/datasync-trust-policy.json
            log "INFO" "Created DataSync IAM role: $DATASYNC_ROLE_NAME"
        fi
    else
        log "INFO" "DataSync IAM role already exists: $DATASYNC_ROLE_NAME"
    fi
    
    # Get role ARN
    if [[ "$DRY_RUN" == "false" ]]; then
        DATASYNC_ROLE_ARN=$(aws iam get-role \
            --role-name "$DATASYNC_ROLE_NAME" \
            --query Role.Arn --output text)
        export DATASYNC_ROLE_ARN
    fi
    
    # Create S3 access policy
    local s3_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:ListBucket",
                "s3:ListBucketMultipartUploads"
            ],
            "Resource": [
                "arn:aws:s3:::$SOURCE_BUCKET_NAME",
                "arn:aws:s3:::$DEST_BUCKET_NAME"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:GetObjectTagging",
                "s3:GetObjectVersion",
                "s3:GetObjectVersionTagging",
                "s3:PutObject",
                "s3:PutObjectTagging",
                "s3:DeleteObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "arn:aws:s3:::$SOURCE_BUCKET_NAME/*",
                "arn:aws:s3:::$DEST_BUCKET_NAME/*"
            ]
        }
    ]
}
EOF
)
    
    # Attach S3 policy to DataSync role
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would attach S3 policy to DataSync role"
    else
        echo "$s3_policy" > /tmp/datasync-s3-policy.json
        aws iam put-role-policy \
            --role-name "$DATASYNC_ROLE_NAME" \
            --policy-name DataSyncS3Policy \
            --policy-document file:///tmp/datasync-s3-policy.json
        rm -f /tmp/datasync-s3-policy.json
        log "INFO" "Attached S3 policy to DataSync role"
    fi
    
    # Create EventBridge role
    local eventbridge_trust_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "events.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)
    
    if ! aws iam get-role --role-name "$EVENTBRIDGE_ROLE_NAME" &>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would create EventBridge IAM role: $EVENTBRIDGE_ROLE_NAME"
        else
            echo "$eventbridge_trust_policy" > /tmp/eventbridge-trust-policy.json
            aws iam create-role \
                --role-name "$EVENTBRIDGE_ROLE_NAME" \
                --assume-role-policy-document file:///tmp/eventbridge-trust-policy.json
            rm -f /tmp/eventbridge-trust-policy.json
            log "INFO" "Created EventBridge IAM role: $EVENTBRIDGE_ROLE_NAME"
        fi
    else
        log "INFO" "EventBridge IAM role already exists: $EVENTBRIDGE_ROLE_NAME"
    fi
}

# Create DataSync resources
create_datasync_resources() {
    log "INFO" "Creating DataSync resources..."
    
    # Create source location
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create DataSync source location for bucket: $SOURCE_BUCKET_NAME"
        log "INFO" "[DRY RUN] Would create DataSync destination location for bucket: $DEST_BUCKET_NAME"
        log "INFO" "[DRY RUN] Would create DataSync task: $DATASYNC_TASK_NAME"
    else
        SOURCE_LOCATION_ARN=$(aws datasync create-location-s3 \
            --s3-bucket-arn "arn:aws:s3:::$SOURCE_BUCKET_NAME" \
            --s3-config BucketAccessRoleArn="$DATASYNC_ROLE_ARN" \
            --query LocationArn --output text)
        export SOURCE_LOCATION_ARN
        log "INFO" "Created source location: $SOURCE_LOCATION_ARN"
        
        # Create destination location
        DEST_LOCATION_ARN=$(aws datasync create-location-s3 \
            --s3-bucket-arn "arn:aws:s3:::$DEST_BUCKET_NAME" \
            --s3-config BucketAccessRoleArn="$DATASYNC_ROLE_ARN" \
            --query LocationArn --output text)
        export DEST_LOCATION_ARN
        log "INFO" "Created destination location: $DEST_LOCATION_ARN"
        
        # Create DataSync task
        TASK_ARN=$(aws datasync create-task \
            --source-location-arn "$SOURCE_LOCATION_ARN" \
            --destination-location-arn "$DEST_LOCATION_ARN" \
            --name "$DATASYNC_TASK_NAME" \
            --options '{
                "VerifyMode": "POINT_IN_TIME_CONSISTENT",
                "OverwriteMode": "ALWAYS",
                "PreserveDeletedFiles": "PRESERVE",
                "PreserveDevices": "NONE",
                "PosixPermissions": "NONE",
                "BytesPerSecond": -1,
                "TaskQueueing": "ENABLED",
                "LogLevel": "TRANSFER",
                "TransferMode": "CHANGED"
            }' \
            --query TaskArn --output text)
        export TASK_ARN
        log "INFO" "Created DataSync task: $TASK_ARN"
    fi
}

# Create CloudWatch resources
create_cloudwatch_resources() {
    log "INFO" "Creating CloudWatch resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create CloudWatch log group: $LOG_GROUP_NAME"
        log "INFO" "[DRY RUN] Would create CloudWatch dashboard: DataSyncMonitoring"
    else
        # Create log group
        if ! aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
            aws logs create-log-group --log-group-name "$LOG_GROUP_NAME"
            log "INFO" "Created CloudWatch log group: $LOG_GROUP_NAME"
        else
            log "INFO" "CloudWatch log group already exists: $LOG_GROUP_NAME"
        fi
        
        # Update task with CloudWatch logging
        aws datasync update-task \
            --task-arn "$TASK_ARN" \
            --cloud-watch-log-group-arn \
            "arn:aws:logs:$AWS_REGION:$AWS_ACCOUNT_ID:log-group:$LOG_GROUP_NAME"
        log "INFO" "Configured CloudWatch logging for DataSync task"
        
        # Create dashboard
        local dashboard_body=$(cat << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/DataSync", "BytesTransferred", "TaskArn", "$TASK_ARN"],
                    ["AWS/DataSync", "FilesTransferred", "TaskArn", "$TASK_ARN"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "$AWS_REGION",
                "title": "DataSync Transfer Metrics"
            }
        }
    ]
}
EOF
)
        
        echo "$dashboard_body" > /tmp/datasync-dashboard.json
        aws cloudwatch put-dashboard \
            --dashboard-name DataSyncMonitoring \
            --dashboard-body file:///tmp/datasync-dashboard.json
        rm -f /tmp/datasync-dashboard.json
        log "INFO" "Created CloudWatch dashboard: DataSyncMonitoring"
    fi
}

# Create EventBridge scheduling
create_eventbridge_scheduling() {
    log "INFO" "Creating EventBridge scheduling..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create EventBridge rule for scheduled execution"
    else
        # Create EventBridge rule
        aws events put-rule \
            --name DataSyncScheduledExecution \
            --schedule-expression "rate(1 day)" \
            --description "Daily DataSync task execution"
        log "INFO" "Created EventBridge rule: DataSyncScheduledExecution"
        
        # Get EventBridge role ARN
        EVENTBRIDGE_ROLE_ARN=$(aws iam get-role \
            --role-name "$EVENTBRIDGE_ROLE_NAME" \
            --query Role.Arn --output text)
        
        # Create policy for EventBridge to invoke DataSync
        local eventbridge_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "datasync:StartTaskExecution"
            ],
            "Resource": "$TASK_ARN"
        }
    ]
}
EOF
)
        
        echo "$eventbridge_policy" > /tmp/eventbridge-datasync-policy.json
        aws iam put-role-policy \
            --role-name "$EVENTBRIDGE_ROLE_NAME" \
            --policy-name DataSyncExecutionPolicy \
            --policy-document file:///tmp/eventbridge-datasync-policy.json
        rm -f /tmp/eventbridge-datasync-policy.json
        log "INFO" "Attached DataSync execution policy to EventBridge role"
        
        # Add target to EventBridge rule
        aws events put-targets \
            --rule DataSyncScheduledExecution \
            --targets "Id"="1","Arn"="$TASK_ARN","RoleArn"="$EVENTBRIDGE_ROLE_ARN"
        log "INFO" "Configured EventBridge target for DataSync task"
    fi
}

# Configure task reporting
configure_task_reporting() {
    log "INFO" "Configuring task reporting..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would configure task reporting to S3"
    else
        aws datasync put-task-report \
            --task-arn "$TASK_ARN" \
            --s3-destination '{
                "BucketArn": "arn:aws:s3:::'"$DEST_BUCKET_NAME"'",
                "Subdirectory": "datasync-reports",
                "BucketAccessRoleArn": "'"$DATASYNC_ROLE_ARN"'"
            }' \
            --report-level ERRORS_ONLY
        log "INFO" "Configured task reporting to S3"
    fi
}

# Run initial transfer
run_initial_transfer() {
    log "INFO" "Running initial data transfer..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would execute initial DataSync transfer"
    else
        # Execute task
        TASK_EXECUTION_ARN=$(aws datasync start-task-execution \
            --task-arn "$TASK_ARN" \
            --query TaskExecutionArn --output text)
        log "INFO" "Started task execution: $TASK_EXECUTION_ARN"
        
        # Monitor execution
        log "INFO" "Monitoring task execution status..."
        local max_attempts=60
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            STATUS=$(aws datasync describe-task-execution \
                --task-execution-arn "$TASK_EXECUTION_ARN" \
                --query Status --output text)
            
            log "INFO" "Current status: $STATUS"
            
            if [[ "$STATUS" == "SUCCESS" ]]; then
                log "INFO" "Task execution completed successfully"
                break
            elif [[ "$STATUS" == "ERROR" ]]; then
                log "ERROR" "Task execution failed"
                exit 1
            fi
            
            sleep 10
            ((attempt++))
        done
        
        if [ $attempt -eq $max_attempts ]; then
            log "WARN" "Task execution monitoring timed out after $((max_attempts * 10)) seconds"
        fi
    fi
}

# Save deployment information
save_deployment_info() {
    log "INFO" "Saving deployment information..."
    
    local deployment_file="${SCRIPT_DIR}/deployment-info.json"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > "$deployment_file" << EOF
{
    "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "source_bucket": "$SOURCE_BUCKET_NAME",
    "destination_bucket": "$DEST_BUCKET_NAME",
    "datasync_role_name": "$DATASYNC_ROLE_NAME",
    "datasync_task_name": "$DATASYNC_TASK_NAME",
    "eventbridge_role_name": "$EVENTBRIDGE_ROLE_NAME",
    "log_group_name": "$LOG_GROUP_NAME",
    "datasync_role_arn": "$DATASYNC_ROLE_ARN",
    "source_location_arn": "$SOURCE_LOCATION_ARN",
    "destination_location_arn": "$DEST_LOCATION_ARN",
    "task_arn": "$TASK_ARN"
}
EOF
        log "INFO" "Deployment information saved to: $deployment_file"
    fi
}

# Main deployment function
main() {
    log "INFO" "Starting DataSync deployment..."
    
    check_prerequisites
    setup_environment
    create_s3_buckets
    create_iam_resources
    create_datasync_resources
    create_cloudwatch_resources
    create_eventbridge_scheduling
    configure_task_reporting
    run_initial_transfer
    save_deployment_info
    
    log "INFO" "DataSync deployment completed successfully!"
    log "INFO" "Resources created:"
    log "INFO" "  - Source S3 bucket: $SOURCE_BUCKET_NAME"
    log "INFO" "  - Destination S3 bucket: $DEST_BUCKET_NAME"
    log "INFO" "  - DataSync task: $DATASYNC_TASK_NAME"
    log "INFO" "  - CloudWatch log group: $LOG_GROUP_NAME"
    log "INFO" "  - EventBridge scheduled rule: DataSyncScheduledExecution"
    log "INFO" "  - CloudWatch dashboard: DataSyncMonitoring"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Next steps:"
        log "INFO" "  1. Monitor transfers in CloudWatch dashboard"
        log "INFO" "  2. Check task reports in s3://$DEST_BUCKET_NAME/datasync-reports/"
        log "INFO" "  3. Customize scheduling in EventBridge console"
        log "INFO" "  4. Review costs in AWS Cost Explorer"
    fi
}

# Run main function
main "$@"