#!/bin/bash

# =============================================================================
# AWS Backup Strategies with S3 and Glacier - Deployment Script
# =============================================================================
# This script deploys a comprehensive backup strategy using Amazon S3 with 
# intelligent lifecycle transitions to Glacier storage classes, automated 
# backup scheduling with Lambda functions, and event-driven notifications 
# through EventBridge.
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Validation
# =============================================================================

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="/tmp/backup-strategy-deploy-$(date +%Y%m%d_%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}❌ $*${NC}" | tee -a "$LOG_FILE"
}

# Function to cleanup on script exit
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed with exit code $exit_code"
        log_info "Cleanup may be required. Run destroy.sh to remove created resources."
        log_info "Deployment log saved to: $LOG_FILE"
    else
        log_success "Deployment completed successfully!"
        log_info "Deployment log saved to: $LOG_FILE"
    fi
}

trap cleanup_on_exit EXIT

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is required but not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $aws_version"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure' or set up AWS credentials."
        exit 1
    fi
    
    # Check required tools
    local required_tools=("jq" "zip" "python3")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed."
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# =============================================================================
# Environment Setup
# =============================================================================

setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS_REGION is not set. Please set it or configure default region."
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export BACKUP_BUCKET_NAME="backup-strategy-demo-${random_suffix}"
    export BACKUP_FUNCTION_NAME="backup-orchestrator-${random_suffix}"
    export BACKUP_ROLE_NAME="backup-execution-role-${random_suffix}"
    export BACKUP_TOPIC_NAME="backup-notifications-${random_suffix}"
    export RANDOM_SUFFIX="$random_suffix"
    
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "Resource suffix: $random_suffix"
    log_info "Backup bucket: $BACKUP_BUCKET_NAME"
    
    # Create sample data directory for testing
    mkdir -p ~/backup-demo-data
    echo "Critical business data - $(date)" > ~/backup-demo-data/business-data.txt
    echo "Customer records - $(date)" > ~/backup-demo-data/customer-data.txt
    echo "Financial transactions - $(date)" > ~/backup-demo-data/financial-data.txt
    
    log_success "Environment setup completed"
}

# =============================================================================
# Resource Creation Functions
# =============================================================================

create_s3_bucket() {
    log_info "Creating S3 bucket with security configurations..."
    
    # Create the backup bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BACKUP_BUCKET_NAME" --region "$AWS_REGION"
    else
        aws s3api create-bucket \
            --bucket "$BACKUP_BUCKET_NAME" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning for data protection
    aws s3api put-bucket-versioning \
        --bucket "$BACKUP_BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "$BACKUP_BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    # Block public access for security
    aws s3api put-public-access-block \
        --bucket "$BACKUP_BUCKET_NAME" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    
    log_success "S3 bucket created with security configurations"
}

configure_lifecycle_policies() {
    log_info "Configuring intelligent tiering and lifecycle policies..."
    
    # Create lifecycle policy for automated tiering
    cat > /tmp/lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "backup-lifecycle-rule",
            "Status": "Enabled",
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 365,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ],
            "NoncurrentVersionTransitions": [
                {
                    "NoncurrentDays": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "NoncurrentDays": 90,
                    "StorageClass": "GLACIER"
                }
            ],
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 2555
            }
        }
    ]
}
EOF
    
    # Apply lifecycle policy
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$BACKUP_BUCKET_NAME" \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json
    
    # Enable intelligent tiering for cost optimization
    aws s3api put-bucket-intelligent-tiering-configuration \
        --bucket "$BACKUP_BUCKET_NAME" \
        --id backup-intelligent-tiering \
        --intelligent-tiering-configuration '{
            "Id": "backup-intelligent-tiering",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "intelligent-tier/"
            },
            "Tierings": [
                {
                    "Days": 1,
                    "AccessTier": "ARCHIVE_ACCESS"
                },
                {
                    "Days": 90,
                    "AccessTier": "DEEP_ARCHIVE_ACCESS"
                }
            ]
        }'
    
    log_success "Lifecycle policies and intelligent tiering configured"
}

create_iam_role() {
    log_info "Creating IAM role for backup automation..."
    
    # Create trust policy for Lambda execution
    cat > /tmp/trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create the IAM role
    aws iam create-role \
        --role-name "$BACKUP_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/trust-policy.json
    
    # Create custom policy for backup operations
    cat > /tmp/backup-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:GetBucketVersioning",
                "s3:RestoreObject"
            ],
            "Resource": [
                "arn:aws:s3:::${BACKUP_BUCKET_NAME}",
                "arn:aws:s3:::${BACKUP_BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create and attach the custom policy
    aws iam create-policy \
        --policy-name "BackupExecutionPolicy-${RANDOM_SUFFIX}" \
        --policy-document file:///tmp/backup-policy.json
    
    aws iam attach-role-policy \
        --role-name "$BACKUP_ROLE_NAME" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/BackupExecutionPolicy-${RANDOM_SUFFIX}"
    
    # Attach basic execution role
    aws iam attach-role-policy \
        --role-name "$BACKUP_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Wait for role to be available
    log_info "Waiting for IAM role to be available..."
    sleep 10
    
    log_success "IAM role created with backup permissions"
}

create_sns_topic() {
    log_info "Creating SNS topic for backup notifications..."
    
    # Create SNS topic for notifications
    local topic_arn
    topic_arn=$(aws sns create-topic \
        --name "$BACKUP_TOPIC_NAME" \
        --query TopicArn --output text)
    
    export BACKUP_TOPIC_ARN="$topic_arn"
    
    log_info "SNS Topic ARN: $BACKUP_TOPIC_ARN"
    log_warning "To receive email notifications, manually subscribe your email to the SNS topic:"
    log_warning "aws sns subscribe --topic-arn $BACKUP_TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
    
    log_success "SNS topic created"
}

create_lambda_function() {
    log_info "Creating Lambda function for backup orchestration..."
    
    # Create Lambda function code
    cat > /tmp/backup-function.py << 'EOF'
import json
import boto3
import os
from datetime import datetime
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    bucket_name = os.environ['BACKUP_BUCKET']
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    try:
        # Extract backup parameters from event
        backup_type = event.get('backup_type', 'incremental')
        source_prefix = event.get('source_prefix', 'data/')
        
        # Perform backup operation
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_key = f"backups/{backup_type}/{timestamp}/"
        
        # Simulate backup validation
        validation_result = validate_backup(bucket_name, backup_key)
        
        # Send CloudWatch metrics
        cloudwatch.put_metric_data(
            Namespace='BackupStrategy',
            MetricData=[
                {
                    'MetricName': 'BackupSuccess',
                    'Value': 1 if validation_result else 0,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'BackupDuration',
                    'Value': 120,  # Simulated duration
                    'Unit': 'Seconds'
                }
            ]
        )
        
        # Send notification
        message = {
            'backup_type': backup_type,
            'timestamp': timestamp,
            'status': 'SUCCESS' if validation_result else 'FAILED',
            'bucket': bucket_name,
            'backup_location': backup_key
        }
        
        sns.publish(
            TopicArn=topic_arn,
            Message=json.dumps(message, indent=2),
            Subject=f'Backup {message["status"]}: {backup_type}'
        )
        
        logger.info(f"Backup completed: {message}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(message)
        }
        
    except Exception as e:
        logger.error(f"Backup failed: {str(e)}")
        
        # Send failure notification
        sns.publish(
            TopicArn=topic_arn,
            Message=f'Backup failed: {str(e)}',
            Subject='Backup FAILED'
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def validate_backup(bucket_name, backup_key):
    """Validate backup integrity"""
    try:
        # Check if backup location exists
        response = s3.list_objects_v2(
            Bucket=bucket_name,
            Prefix=backup_key,
            MaxKeys=1
        )
        
        # In a real implementation, you would:
        # 1. Verify file checksums
        # 2. Test restoration of sample files
        # 3. Validate backup completeness
        
        return True  # Simplified validation
        
    except Exception as e:
        logger.error(f"Backup validation failed: {str(e)}")
        return False
EOF
    
    # Create deployment package
    cd /tmp
    zip -r backup-function.zip backup-function.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$BACKUP_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${BACKUP_ROLE_NAME}" \
        --handler backup-function.lambda_handler \
        --zip-file fileb://backup-function.zip \
        --timeout 300 \
        --memory-size 256 \
        --environment "Variables={BACKUP_BUCKET=${BACKUP_BUCKET_NAME},SNS_TOPIC_ARN=${BACKUP_TOPIC_ARN}}"
    
    log_success "Lambda function created for backup orchestration"
}

create_eventbridge_rules() {
    log_info "Creating EventBridge rules for scheduled backups..."
    
    # Create EventBridge rule for daily backups
    aws events put-rule \
        --name "daily-backup-${RANDOM_SUFFIX}" \
        --schedule-expression "cron(0 2 * * ? *)" \
        --description "Daily backup at 2 AM UTC"
    
    # Create EventBridge rule for weekly full backups
    aws events put-rule \
        --name "weekly-backup-${RANDOM_SUFFIX}" \
        --schedule-expression "cron(0 1 ? * SUN *)" \
        --description "Weekly full backup on Sunday at 1 AM UTC"
    
    # Add Lambda permission for EventBridge
    aws lambda add-permission \
        --function-name "$BACKUP_FUNCTION_NAME" \
        --statement-id daily-backup-permission \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/daily-backup-${RANDOM_SUFFIX}"
    
    aws lambda add-permission \
        --function-name "$BACKUP_FUNCTION_NAME" \
        --statement-id weekly-backup-permission \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/weekly-backup-${RANDOM_SUFFIX}"
    
    # Create targets for EventBridge rules
    aws events put-targets \
        --rule "daily-backup-${RANDOM_SUFFIX}" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${BACKUP_FUNCTION_NAME}","Input"='{"backup_type":"incremental","source_prefix":"daily/"}'
    
    aws events put-targets \
        --rule "weekly-backup-${RANDOM_SUFFIX}" \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${BACKUP_FUNCTION_NAME}","Input"='{"backup_type":"full","source_prefix":"weekly/"}'
    
    log_success "EventBridge rules configured for automated backups"
}

upload_sample_data() {
    log_info "Uploading sample data and testing backup process..."
    
    # Upload sample data to S3
    aws s3 cp ~/backup-demo-data/ "s3://$BACKUP_BUCKET_NAME/data/" --recursive
    
    # Upload additional test files with different access patterns
    aws s3 cp ~/backup-demo-data/business-data.txt \
        "s3://$BACKUP_BUCKET_NAME/intelligent-tier/business-data.txt"
    
    # Create different backup scenarios
    echo "Archive data - $(date)" > ~/backup-demo-data/archive-data.txt
    aws s3 cp ~/backup-demo-data/archive-data.txt \
        "s3://$BACKUP_BUCKET_NAME/archive/archive-data.txt"
    
    # Test Lambda function manually
    aws lambda invoke \
        --function-name "$BACKUP_FUNCTION_NAME" \
        --payload '{"backup_type":"test","source_prefix":"data/"}' \
        /tmp/response.json
    
    # Display the response
    log_info "Lambda function test response:"
    cat /tmp/response.json
    
    log_success "Sample data uploaded and backup function tested"
}

configure_monitoring() {
    log_info "Configuring CloudWatch monitoring and alarms..."
    
    # Create CloudWatch alarm for backup failures
    aws cloudwatch put-metric-alarm \
        --alarm-name "backup-failure-alarm-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when backup fails" \
        --metric-name BackupSuccess \
        --namespace BackupStrategy \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$BACKUP_TOPIC_ARN"
    
    # Create CloudWatch alarm for backup duration
    aws cloudwatch put-metric-alarm \
        --alarm-name "backup-duration-alarm-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when backup takes too long" \
        --metric-name BackupDuration \
        --namespace BackupStrategy \
        --statistic Average \
        --period 300 \
        --threshold 600 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$BACKUP_TOPIC_ARN"
    
    # Create dashboard for backup monitoring
    cat > /tmp/dashboard-body.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["BackupStrategy", "BackupSuccess"],
                    [".", "BackupDuration"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Backup Metrics"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "backup-strategy-dashboard-${RANDOM_SUFFIX}" \
        --dashboard-body file:///tmp/dashboard-body.json
    
    log_success "CloudWatch monitoring and alarms configured"
}

save_deployment_info() {
    log_info "Saving deployment information..."
    
    # Create deployment info file
    cat > "${SCRIPT_DIR}/../deployment-info.json" << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "random_suffix": "$RANDOM_SUFFIX",
    "resources": {
        "s3_bucket": "$BACKUP_BUCKET_NAME",
        "lambda_function": "$BACKUP_FUNCTION_NAME",
        "iam_role": "$BACKUP_ROLE_NAME",
        "sns_topic": "$BACKUP_TOPIC_NAME",
        "sns_topic_arn": "$BACKUP_TOPIC_ARN",
        "eventbridge_rules": [
            "daily-backup-${RANDOM_SUFFIX}",
            "weekly-backup-${RANDOM_SUFFIX}"
        ],
        "cloudwatch_alarms": [
            "backup-failure-alarm-${RANDOM_SUFFIX}",
            "backup-duration-alarm-${RANDOM_SUFFIX}"
        ],
        "cloudwatch_dashboard": "backup-strategy-dashboard-${RANDOM_SUFFIX}"
    }
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# =============================================================================
# Main Deployment Flow
# =============================================================================

main() {
    log_info "Starting AWS Backup Strategies deployment..."
    log_info "Log file: $LOG_FILE"
    
    # Check if deployment info already exists
    if [ -f "${SCRIPT_DIR}/../deployment-info.json" ]; then
        log_warning "Deployment info file already exists. This may indicate a previous deployment."
        log_warning "To redeploy, please run destroy.sh first to clean up existing resources."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user."
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    configure_lifecycle_policies
    create_iam_role
    create_sns_topic
    create_lambda_function
    create_eventbridge_rules
    upload_sample_data
    configure_monitoring
    save_deployment_info
    
    # Display final information
    echo
    log_success "=== Deployment Summary ==="
    log_info "S3 Bucket: $BACKUP_BUCKET_NAME"
    log_info "Lambda Function: $BACKUP_FUNCTION_NAME"
    log_info "SNS Topic: $BACKUP_TOPIC_ARN"
    log_info "CloudWatch Dashboard: backup-strategy-dashboard-${RANDOM_SUFFIX}"
    echo
    log_warning "Next Steps:"
    log_warning "1. Subscribe to SNS topic for email notifications:"
    log_warning "   aws sns subscribe --topic-arn $BACKUP_TOPIC_ARN --protocol email --notification-endpoint your-email@example.com"
    log_warning "2. Configure cross-region replication if needed"
    log_warning "3. Customize backup schedules in EventBridge as required"
    log_warning "4. Review and test backup restoration procedures"
    echo
    log_info "To clean up all resources, run: ./destroy.sh"
    log_info "Deployment log saved to: $LOG_FILE"
}

# Check if running in dry-run mode
if [ "${1:-}" = "--dry-run" ]; then
    log_info "Running in dry-run mode - no resources will be created"
    log_info "Would execute the following steps:"
    log_info "1. Check prerequisites"
    log_info "2. Setup environment"
    log_info "3. Create S3 bucket with encryption and versioning"
    log_info "4. Configure lifecycle policies"
    log_info "5. Create IAM role for Lambda"
    log_info "6. Create SNS topic"
    log_info "7. Create Lambda function"
    log_info "8. Create EventBridge rules"
    log_info "9. Upload sample data"
    log_info "10. Configure CloudWatch monitoring"
    exit 0
fi

# Run main deployment
main "$@"