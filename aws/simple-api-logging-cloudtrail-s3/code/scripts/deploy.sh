#!/bin/bash

#===============================================================================
# AWS CloudTrail API Logging Deployment Script
#
# This script deploys a complete CloudTrail logging solution with:
# - S3 bucket for log storage with encryption and versioning
# - CloudWatch Logs integration for real-time monitoring
# - CloudWatch alarms for security monitoring
# - Proper IAM roles and policies following least privilege
#
# Usage: ./deploy.sh [--dry-run] [--region REGION]
#
# Requirements:
# - AWS CLI v2.0 or later configured with appropriate permissions
# - jq for JSON processing (optional but recommended)
#===============================================================================

set -euo pipefail

# Colors for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/cloudtrail-deploy-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
VERBOSE=false

# Resource naming configuration
readonly RESOURCE_PREFIX="simple-api-logging"
readonly MIN_AWS_CLI_VERSION="2.0.0"

#===============================================================================
# Utility Functions
#===============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC}  $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC}  $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

check_dependencies() {
    log "INFO" "Checking system dependencies..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install AWS CLI v2.0 or later."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if ! version_greater_equal "$aws_version" "$MIN_AWS_CLI_VERSION"; then
        log "ERROR" "AWS CLI version $aws_version is too old. Minimum required: $MIN_AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured or invalid. Run 'aws configure' first."
        exit 1
    fi
    
    # Check for jq (optional but helpful)
    if ! command -v jq &> /dev/null; then
        log "WARN" "jq is not installed. Some output formatting will be limited."
    fi
    
    log "INFO" "✅ All dependencies satisfied"
}

version_greater_equal() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

generate_random_suffix() {
    # Generate 6-character random suffix for unique resource names
    if command -v aws &> /dev/null; then
        aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c6)"
    else
        echo "$(date +%s | tail -c6)"
    fi
}

wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts="${3:-30}"
    local attempt=1
    
    log "INFO" "Waiting for $resource_type '$resource_name' to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        case "$resource_type" in
            "s3-bucket")
                if aws s3api head-bucket --bucket "$resource_name" &>/dev/null; then
                    log "INFO" "✅ S3 bucket '$resource_name' is ready"
                    return 0
                fi
                ;;
            "iam-role")
                if aws iam get-role --role-name "$resource_name" &>/dev/null; then
                    log "INFO" "✅ IAM role '$resource_name' is ready"
                    return 0
                fi
                ;;
            "cloudtrail")
                if aws cloudtrail describe-trails --trail-name-list "$resource_name" &>/dev/null; then
                    log "INFO" "✅ CloudTrail '$resource_name' is ready"
                    return 0
                fi
                ;;
        esac
        
        log "DEBUG" "Attempt $attempt/$max_attempts: $resource_type not ready yet..."
        sleep 10
        ((attempt++))
    done
    
    log "ERROR" "Timeout waiting for $resource_type '$resource_name'"
    return 1
}

cleanup_on_error() {
    log "ERROR" "Deployment failed. Starting cleanup of partially created resources..."
    
    # Store current error state
    local exit_code=$?
    
    # Try to clean up resources that might have been created
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log "INFO" "Attempting to clean up S3 bucket: $BUCKET_NAME"
        aws s3 rm "s3://$BUCKET_NAME" --recursive &>/dev/null || true
        aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null)" &>/dev/null || true
        aws s3 rb "s3://$BUCKET_NAME" &>/dev/null || true
    fi
    
    if [[ -n "${TRAIL_NAME:-}" ]]; then
        log "INFO" "Attempting to clean up CloudTrail: $TRAIL_NAME"
        aws cloudtrail stop-logging --name "$TRAIL_NAME" &>/dev/null || true
        aws cloudtrail delete-trail --name "$TRAIL_NAME" &>/dev/null || true
    fi
    
    if [[ -n "${LOG_GROUP_NAME:-}" ]]; then
        log "INFO" "Attempting to clean up CloudWatch Log Group: $LOG_GROUP_NAME"
        aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME" &>/dev/null || true
    fi
    
    if [[ -n "${ROLE_NAME:-}" ]]; then
        log "INFO" "Attempting to clean up IAM role: $ROLE_NAME"
        aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name CloudTrailLogsPolicy &>/dev/null || true
        aws iam delete-role --role-name "$ROLE_NAME" &>/dev/null || true
    fi
    
    if [[ -n "${TOPIC_ARN:-}" ]]; then
        log "INFO" "Attempting to clean up SNS topic: $TOPIC_ARN"
        aws sns delete-topic --topic-arn "$TOPIC_ARN" &>/dev/null || true
    fi
    
    # Clean up local files
    rm -f cloudtrail-trust-policy.json cloudtrail-logs-policy.json s3-bucket-policy.json &>/dev/null || true
    
    log "ERROR" "Cleanup completed. Check logs at: $LOG_FILE"
    exit $exit_code
}

#===============================================================================
# Infrastructure Deployment Functions
#===============================================================================

setup_environment() {
    log "INFO" "Setting up deployment environment..."
    
    # Set AWS region
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    if [[ -z "$AWS_REGION" ]]; then
        log "ERROR" "AWS region not set. Use --region flag or configure AWS CLI."
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(generate_random_suffix)
    
    # Set resource names with environment variables for consistency
    export BUCKET_NAME="cloudtrail-logs-${AWS_ACCOUNT_ID}-${random_suffix}"
    export TRAIL_NAME="${RESOURCE_PREFIX}-trail-${random_suffix}"
    export LOG_GROUP_NAME="/aws/cloudtrail/${TRAIL_NAME}"
    export ROLE_NAME="CloudTrailLogsRole-${random_suffix}"
    export ALARM_NAME="CloudTrail-RootAccountUsage-${random_suffix}"
    export TOPIC_NAME="cloudtrail-alerts-${random_suffix}"
    
    log "INFO" "✅ Environment configured:"
    log "INFO" "  Region: $AWS_REGION"
    log "INFO" "  Account: $AWS_ACCOUNT_ID"
    log "INFO" "  S3 Bucket: $BUCKET_NAME"
    log "INFO" "  CloudTrail: $TRAIL_NAME"
    log "INFO" "  Log Group: $LOG_GROUP_NAME"
    
    # Store configuration for cleanup script
    cat > "${SCRIPT_DIR}/.deployment-config" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
BUCKET_NAME=$BUCKET_NAME
TRAIL_NAME=$TRAIL_NAME
LOG_GROUP_NAME=$LOG_GROUP_NAME
ROLE_NAME=$ROLE_NAME
ALARM_NAME=$ALARM_NAME
TOPIC_NAME=$TOPIC_NAME
DEPLOYMENT_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

create_s3_bucket() {
    log "INFO" "Creating S3 bucket for CloudTrail logs..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY RUN] Would create S3 bucket: $BUCKET_NAME"
        return 0
    fi
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
        log "WARN" "S3 bucket '$BUCKET_NAME' already exists"
        return 0
    fi
    
    # Create bucket with location constraint if not in us-east-1
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb "s3://$BUCKET_NAME"
    else
        aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Configure server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    
    wait_for_resource "s3-bucket" "$BUCKET_NAME"
    log "INFO" "✅ S3 bucket created with security features: $BUCKET_NAME"
}

create_cloudwatch_log_group() {
    log "INFO" "Creating CloudWatch Log Group..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY RUN] Would create CloudWatch Log Group: $LOG_GROUP_NAME"
        return 0
    fi
    
    # Check if log group already exists
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[?logGroupName==`'$LOG_GROUP_NAME'`]' --output text | grep -q "$LOG_GROUP_NAME"; then
        log "WARN" "CloudWatch Log Group '$LOG_GROUP_NAME' already exists"
        return 0
    fi
    
    # Create log group
    aws logs create-log-group --log-group-name "$LOG_GROUP_NAME"
    
    # Set retention policy
    aws logs put-retention-policy \
        --log-group-name "$LOG_GROUP_NAME" \
        --retention-in-days 30
    
    log "INFO" "✅ CloudWatch Log Group created: $LOG_GROUP_NAME"
}

create_iam_role() {
    log "INFO" "Creating IAM role for CloudTrail..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY RUN] Would create IAM role: $ROLE_NAME"
        return 0
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log "WARN" "IAM role '$ROLE_NAME' already exists"
        export CLOUDTRAIL_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
        return 0
    fi
    
    # Create trust policy
    cat > cloudtrail-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create logs policy
    cat > cloudtrail-logs-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AWSCloudTrailCreateLogStream",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream"
            ],
            "Resource": [
                "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:${LOG_GROUP_NAME}:log-stream:*"
            ]
        },
        {
            "Sid": "AWSCloudTrailPutLogEvents",
            "Effect": "Allow",
            "Action": [
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:${LOG_GROUP_NAME}:log-stream:*"
            ]
        }
    ]
}
EOF
    
    # Create role
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file://cloudtrail-trust-policy.json
    
    # Attach policy
    aws iam put-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name CloudTrailLogsPolicy \
        --policy-document file://cloudtrail-logs-policy.json
    
    wait_for_resource "iam-role" "$ROLE_NAME"
    
    export CLOUDTRAIL_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
    log "INFO" "✅ IAM role created: $CLOUDTRAIL_ROLE_ARN"
}

configure_s3_bucket_policy() {
    log "INFO" "Configuring S3 bucket policy for CloudTrail..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY RUN] Would configure S3 bucket policy"
        return 0
    fi
    
    # Create bucket policy
    cat > s3-bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AWSCloudTrailAclCheck",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}",
            "Condition": {
                "StringEquals": {
                    "aws:SourceArn": "arn:aws:cloudtrail:${AWS_REGION}:${AWS_ACCOUNT_ID}:trail/${TRAIL_NAME}"
                }
            }
        },
        {
            "Sid": "AWSCloudTrailWrite",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/AWSLogs/${AWS_ACCOUNT_ID}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control",
                    "aws:SourceArn": "arn:aws:cloudtrail:${AWS_REGION}:${AWS_ACCOUNT_ID}:trail/${TRAIL_NAME}"
                }
            }
        }
    ]
}
EOF
    
    # Apply bucket policy
    aws s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --policy file://s3-bucket-policy.json
    
    log "INFO" "✅ S3 bucket policy configured with CloudTrail permissions"
}

create_cloudtrail() {
    log "INFO" "Creating CloudTrail..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY RUN] Would create CloudTrail: $TRAIL_NAME"
        return 0
    fi
    
    # Check if trail already exists
    if aws cloudtrail describe-trails --trail-name-list "$TRAIL_NAME" &>/dev/null; then
        log "WARN" "CloudTrail '$TRAIL_NAME' already exists"
        
        # Start logging if not already started
        aws cloudtrail start-logging --name "$TRAIL_NAME" || true
        return 0
    fi
    
    # Create trail
    aws cloudtrail create-trail \
        --name "$TRAIL_NAME" \
        --s3-bucket-name "$BUCKET_NAME" \
        --include-global-service-events \
        --is-multi-region-trail \
        --enable-log-file-validation \
        --cloud-watch-logs-log-group-arn "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:${LOG_GROUP_NAME}:*" \
        --cloud-watch-logs-role-arn "$CLOUDTRAIL_ROLE_ARN"
    
    # Start logging
    aws cloudtrail start-logging --name "$TRAIL_NAME"
    
    wait_for_resource "cloudtrail" "$TRAIL_NAME"
    
    # Get trail ARN
    local trail_arn
    trail_arn=$(aws cloudtrail describe-trails \
        --trail-name-list "$TRAIL_NAME" \
        --query 'trailList[0].TrailARN' --output text)
    
    log "INFO" "✅ CloudTrail created and logging started"
    log "INFO" "  Trail ARN: $trail_arn"
}

create_monitoring() {
    log "INFO" "Creating CloudWatch monitoring and alerts..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY RUN] Would create CloudWatch monitoring"
        return 0
    fi
    
    # Create metric filter for root account usage
    aws logs put-metric-filter \
        --log-group-name "$LOG_GROUP_NAME" \
        --filter-name RootAccountUsage \
        --filter-pattern '{ $.userIdentity.type = "Root" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != "AwsServiceEvent" }' \
        --metric-transformations \
            metricName=RootAccountUsageCount,metricNamespace=CloudTrailMetrics,metricValue=1
    
    # Create SNS topic
    export TOPIC_ARN
    TOPIC_ARN=$(aws sns create-topic \
        --name "$TOPIC_NAME" \
        --query 'TopicArn' --output text)
    
    # Create CloudWatch alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME" \
        --alarm-description "Alert when root account is used" \
        --metric-name RootAccountUsageCount \
        --namespace CloudTrailMetrics \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$TOPIC_ARN"
    
    log "INFO" "✅ CloudWatch monitoring created"
    log "INFO" "  SNS Topic: $TOPIC_ARN"
    log "INFO" "  Alarm: $ALARM_NAME"
}

validate_deployment() {
    log "INFO" "Validating deployment..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    local validation_errors=0
    
    # Check CloudTrail status
    log "INFO" "Checking CloudTrail status..."
    if ! aws cloudtrail get-trail-status --name "$TRAIL_NAME" --query 'IsLogging' --output text | grep -q "True"; then
        log "ERROR" "CloudTrail is not logging"
        ((validation_errors++))
    else
        log "INFO" "✅ CloudTrail is logging"
    fi
    
    # Check S3 bucket
    log "INFO" "Checking S3 bucket..."
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
        log "ERROR" "S3 bucket is not accessible"
        ((validation_errors++))
    else
        log "INFO" "✅ S3 bucket is accessible"
    fi
    
    # Check CloudWatch Log Group
    log "INFO" "Checking CloudWatch Log Group..."
    if ! aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[?logGroupName==`'$LOG_GROUP_NAME'`]' --output text | grep -q "$LOG_GROUP_NAME"; then
        log "ERROR" "CloudWatch Log Group not found"
        ((validation_errors++))
    else
        log "INFO" "✅ CloudWatch Log Group exists"
    fi
    
    # Check IAM role
    log "INFO" "Checking IAM role..."
    if ! aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log "ERROR" "IAM role not found"
        ((validation_errors++))
    else
        log "INFO" "✅ IAM role exists"
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log "INFO" "✅ All validation checks passed"
        return 0
    else
        log "ERROR" "Validation failed with $validation_errors errors"
        return 1
    fi
}

cleanup_temp_files() {
    log "DEBUG" "Cleaning up temporary files..."
    rm -f cloudtrail-trust-policy.json cloudtrail-logs-policy.json s3-bucket-policy.json
}

#===============================================================================
# Main Deployment Logic
#===============================================================================

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS CloudTrail API logging infrastructure.

OPTIONS:
    --dry-run           Show what would be deployed without making changes
    --region REGION     AWS region to deploy resources (overrides AWS CLI default)
    --verbose           Enable verbose debugging output
    --help              Show this help message

EXAMPLES:
    $0                           # Deploy with default settings
    $0 --region us-west-2        # Deploy to specific region
    $0 --dry-run                 # Preview deployment without changes
    $0 --verbose --dry-run       # Verbose preview

REQUIREMENTS:
    - AWS CLI v2.0+ configured with appropriate permissions
    - Permissions for CloudTrail, S3, CloudWatch, IAM, and SNS services

For more information, see the recipe documentation.
EOF
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --region)
                export AWS_REGION="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set up error handling
    trap cleanup_on_error ERR
    trap cleanup_temp_files EXIT
    
    log "INFO" "Starting CloudTrail API Logging deployment..."
    log "INFO" "Log file: $LOG_FILE"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "🔍 DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    check_dependencies
    setup_environment
    create_s3_bucket
    create_cloudwatch_log_group
    create_iam_role
    configure_s3_bucket_policy
    create_cloudtrail
    create_monitoring
    validate_deployment
    
    # Success message
    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "🔍 DRY RUN COMPLETE - Review the planned changes above"
    else
        log "INFO" "🎉 DEPLOYMENT SUCCESSFUL!"
        log "INFO" ""
        log "INFO" "CloudTrail API logging is now active with the following resources:"
        log "INFO" "  • S3 Bucket: $BUCKET_NAME"
        log "INFO" "  • CloudTrail: $TRAIL_NAME"
        log "INFO" "  • CloudWatch Log Group: $LOG_GROUP_NAME"
        log "INFO" "  • SNS Topic: $TOPIC_ARN"
        log "INFO" "  • Root Account Usage Alarm: $ALARM_NAME"
        log "INFO" ""
        log "INFO" "Next Steps:"
        log "INFO" "  1. Subscribe to SNS topic for alerts: aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
        log "INFO" "  2. Review CloudTrail events in CloudWatch Logs or S3"
        log "INFO" "  3. Customize metric filters for additional monitoring"
        log "INFO" ""
        log "INFO" "To clean up resources, run: ./destroy.sh"
        log "INFO" "Configuration saved to: ${SCRIPT_DIR}/.deployment-config"
    fi
}

# Execute main function with all arguments
main "$@"