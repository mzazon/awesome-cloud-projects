#!/bin/bash

# Deploy script for S3 Access Logging and Security Monitoring
# This script creates a comprehensive S3 access logging and security monitoring system
# using AWS S3 Server Access Logging combined with CloudTrail API monitoring

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $1"
        return 0
    else
        eval "$1"
    fi
}

log "Starting S3 Access Logging and Security Monitoring deployment..."

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
fi

# Check if AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure' first."
fi

# Check if required permissions are available
log "Validating AWS permissions..."
if ! aws s3 ls &> /dev/null; then
    error "Insufficient S3 permissions. Please ensure your AWS credentials have S3 access."
fi

if ! aws cloudtrail describe-trails &> /dev/null; then
    error "Insufficient CloudTrail permissions. Please ensure your AWS credentials have CloudTrail access."
fi

success "Prerequisites check completed"

# Set environment variables
log "Setting up environment variables..."
export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
if [[ -z "${AWS_REGION}" ]]; then
    export AWS_REGION="us-east-1"
    warning "AWS_REGION not set, defaulting to us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
log "Generating unique resource identifiers..."
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

# Set bucket names
export SOURCE_BUCKET="secure-docs-${RANDOM_SUFFIX}"
export LOGS_BUCKET="s3-access-logs-${RANDOM_SUFFIX}"
export CLOUDTRAIL_BUCKET="cloudtrail-logs-${RANDOM_SUFFIX}"
export TRAIL_NAME="s3-security-monitoring-trail"
export LOG_GROUP_NAME="/aws/cloudtrail/s3-security-monitoring"

log "Resource identifiers generated:"
log "  Source Bucket: ${SOURCE_BUCKET}"
log "  Logs Bucket: ${LOGS_BUCKET}"
log "  CloudTrail Bucket: ${CLOUDTRAIL_BUCKET}"
log "  Trail Name: ${TRAIL_NAME}"

# Create temporary directory for configuration files
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Step 1: Create foundational S3 buckets
log "Creating foundational S3 buckets..."

# Create source bucket
if [[ "$AWS_REGION" == "us-east-1" ]]; then
    execute_command "aws s3api create-bucket --bucket ${SOURCE_BUCKET} --region ${AWS_REGION}"
else
    execute_command "aws s3api create-bucket --bucket ${SOURCE_BUCKET} --region ${AWS_REGION} --create-bucket-configuration LocationConstraint=${AWS_REGION}"
fi

# Create logs bucket
if [[ "$AWS_REGION" == "us-east-1" ]]; then
    execute_command "aws s3api create-bucket --bucket ${LOGS_BUCKET} --region ${AWS_REGION}"
else
    execute_command "aws s3api create-bucket --bucket ${LOGS_BUCKET} --region ${AWS_REGION} --create-bucket-configuration LocationConstraint=${AWS_REGION}"
fi

# Create CloudTrail bucket
if [[ "$AWS_REGION" == "us-east-1" ]]; then
    execute_command "aws s3api create-bucket --bucket ${CLOUDTRAIL_BUCKET} --region ${AWS_REGION}"
else
    execute_command "aws s3api create-bucket --bucket ${CLOUDTRAIL_BUCKET} --region ${AWS_REGION} --create-bucket-configuration LocationConstraint=${AWS_REGION}"
fi

success "Created foundational S3 buckets"

# Step 2: Configure S3 Server Access Logging
log "Configuring S3 Server Access Logging..."

# Create bucket policy for S3 logging service
cat > "${TEMP_DIR}/s3-logging-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "S3ServerAccessLogsPolicy",
            "Effect": "Allow",
            "Principal": {"Service": "logging.s3.amazonaws.com"},
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${LOGS_BUCKET}/access-logs/*",
            "Condition": {
                "ArnLike": {
                    "aws:SourceArn": "arn:aws:s3:::${SOURCE_BUCKET}"
                },
                "StringEquals": {
                    "aws:SourceAccount": "${AWS_ACCOUNT_ID}"
                }
            }
        }
    ]
}
EOF

# Apply logging policy to logs bucket
execute_command "aws s3api put-bucket-policy --bucket ${LOGS_BUCKET} --policy file://${TEMP_DIR}/s3-logging-policy.json"

success "Applied S3 logging policy to logs bucket"

# Step 3: Enable S3 Server Access Logging
log "Enabling S3 Server Access Logging..."

# Create logging configuration with date-based partitioning
cat > "${TEMP_DIR}/logging-config.json" << EOF
{
    "LoggingEnabled": {
        "TargetBucket": "${LOGS_BUCKET}",
        "TargetPrefix": "access-logs/",
        "TargetObjectKeyFormat": {
            "PartitionedPrefix": {
                "PartitionDateSource": "EventTime"
            }
        }
    }
}
EOF

# Enable server access logging
execute_command "aws s3api put-bucket-logging --bucket ${SOURCE_BUCKET} --bucket-logging-status file://${TEMP_DIR}/logging-config.json"

success "Enabled S3 server access logging with date partitioning"

# Step 4: Create CloudTrail bucket policy
log "Creating CloudTrail bucket policy..."

cat > "${TEMP_DIR}/cloudtrail-policy.json" << EOF
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
            "Resource": "arn:aws:s3:::${CLOUDTRAIL_BUCKET}"
        },
        {
            "Sid": "AWSCloudTrailWrite",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${CLOUDTRAIL_BUCKET}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control"
                }
            }
        }
    ]
}
EOF

# Apply CloudTrail policy
execute_command "aws s3api put-bucket-policy --bucket ${CLOUDTRAIL_BUCKET} --policy file://${TEMP_DIR}/cloudtrail-policy.json"

success "Applied CloudTrail bucket policy"

# Step 5: Create CloudTrail with S3 data events
log "Creating CloudTrail with S3 data events..."

execute_command "aws cloudtrail create-trail \
    --name ${TRAIL_NAME} \
    --s3-bucket-name ${CLOUDTRAIL_BUCKET} \
    --s3-key-prefix cloudtrail-logs/ \
    --include-global-service-events \
    --is-multi-region-trail \
    --enable-log-file-validation"

# Configure event selectors for S3 data events
execute_command "aws cloudtrail put-event-selectors \
    --trail-name ${TRAIL_NAME} \
    --event-selectors '[{
        \"ReadWriteType\": \"All\",
        \"IncludeManagementEvents\": true,
        \"DataResources\": [{
            \"Type\": \"AWS::S3::Object\",
            \"Values\": [\"arn:aws:s3:::${SOURCE_BUCKET}/*\"]
        }]
    }]'"

# Start logging
execute_command "aws cloudtrail start-logging --name ${TRAIL_NAME}"

success "Created and started CloudTrail with S3 data events"

# Step 6: Create CloudWatch Log Group and IAM role
log "Creating CloudWatch Log Group and IAM role..."

# Create CloudWatch log group
execute_command "aws logs create-log-group --log-group-name ${LOG_GROUP_NAME} --retention-in-days 30"

# Create IAM role for CloudTrail CloudWatch integration
cat > "${TEMP_DIR}/cloudtrail-logs-role-policy.json" << EOF
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

# Create role
execute_command "aws iam create-role \
    --role-name CloudTrailLogsRole \
    --assume-role-policy-document file://${TEMP_DIR}/cloudtrail-logs-role-policy.json"

# Create policy for CloudWatch Logs
cat > "${TEMP_DIR}/cloudtrail-logs-permissions.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:${LOG_GROUP_NAME}*"
        }
    ]
}
EOF

# Attach policy to role
execute_command "aws iam put-role-policy \
    --role-name CloudTrailLogsRole \
    --policy-name CloudTrailLogsPolicy \
    --policy-document file://${TEMP_DIR}/cloudtrail-logs-permissions.json"

success "Created CloudWatch log group and IAM role"

# Step 7: Configure CloudTrail CloudWatch integration
log "Configuring CloudTrail CloudWatch integration..."

# Wait for IAM role propagation
sleep 10

export ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/CloudTrailLogsRole"

execute_command "aws cloudtrail update-trail \
    --name ${TRAIL_NAME} \
    --cloud-watch-logs-log-group-arn arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:${LOG_GROUP_NAME} \
    --cloud-watch-logs-role-arn ${ROLE_ARN}"

success "Configured CloudTrail to send logs to CloudWatch"

# Step 8: Create EventBridge rules for security monitoring
log "Creating EventBridge rules for security monitoring..."

# Create SNS topic for security alerts
if [[ "$DRY_RUN" == "true" ]]; then
    export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:s3-security-alerts"
    echo "DRY-RUN: aws sns create-topic --name s3-security-alerts --query TopicArn --output text"
else
    export SNS_TOPIC_ARN=$(aws sns create-topic --name s3-security-alerts --query TopicArn --output text)
fi

# Create EventBridge rule for unauthorized access attempts
execute_command "aws events put-rule \
    --name S3UnauthorizedAccess \
    --event-pattern '{
        \"source\": [\"aws.s3\"],
        \"detail-type\": [\"AWS API Call via CloudTrail\"],
        \"detail\": {
            \"eventName\": [\"GetObject\", \"PutObject\", \"DeleteObject\"],
            \"errorCode\": [\"AccessDenied\", \"SignatureDoesNotMatch\"]
        }
    }'"

# Add SNS target to EventBridge rule
execute_command "aws events put-targets \
    --rule S3UnauthorizedAccess \
    --targets Id=1,Arn=${SNS_TOPIC_ARN}"

# Create policy for EventBridge to publish to SNS
cat > "${TEMP_DIR}/eventbridge-sns-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "events.amazonaws.com"
            },
            "Action": "sns:Publish",
            "Resource": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF

execute_command "aws sns set-topic-attributes \
    --topic-arn ${SNS_TOPIC_ARN} \
    --attribute-name Policy \
    --attribute-value file://${TEMP_DIR}/eventbridge-sns-policy.json"

success "Created EventBridge rules and SNS topic for security alerts"

# Step 9: Create CloudWatch Dashboard
log "Creating CloudWatch Dashboard..."

cat > "${TEMP_DIR}/dashboard-config.json" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/S3", "BucketSizeBytes", "BucketName", "${SOURCE_BUCKET}", "StorageType", "StandardStorage"],
                    ["AWS/S3", "NumberOfObjects", "BucketName", "${SOURCE_BUCKET}", "StorageType", "AllStorageTypes"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "S3 Bucket Metrics"
            }
        },
        {
            "type": "log",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "query": "SOURCE '${LOG_GROUP_NAME}' | fields @timestamp, eventName, sourceIPAddress, userIdentity.type\\n| filter eventName like /GetObject|PutObject|DeleteObject/\\n| stats count() by eventName\\n| sort count desc",
                "region": "${AWS_REGION}",
                "title": "Top S3 API Calls",
                "view": "table"
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '${LOG_GROUP_NAME}' | fields @timestamp, eventName, sourceIPAddress, errorCode, errorMessage\\n| filter errorCode = \"AccessDenied\"\\n| stats count() by sourceIPAddress\\n| sort count desc",
                "region": "${AWS_REGION}",
                "title": "Failed Access Attempts by IP",
                "view": "table"
            }
        }
    ]
}
EOF

execute_command "aws cloudwatch put-dashboard \
    --dashboard-name S3SecurityMonitoring \
    --dashboard-body file://${TEMP_DIR}/dashboard-config.json"

success "Created CloudWatch dashboard for S3 security monitoring"

# Step 10: Create sample security queries
log "Creating sample security analysis queries..."

cat > security-queries.txt << 'EOF'
# CloudWatch Insights Security Analysis Queries

# Query 1: Failed access attempts
fields @timestamp, eventName, sourceIPAddress, errorCode, errorMessage
| filter errorCode = "AccessDenied"
| stats count() by sourceIPAddress
| sort count desc

# Query 2: Unusual access patterns
fields @timestamp, eventName, sourceIPAddress, userIdentity.type
| filter eventName like /GetObject|PutObject|DeleteObject/
| stats count() by sourceIPAddress, userIdentity.type
| sort count desc

# Query 3: Administrative actions
fields @timestamp, eventName, sourceIPAddress, userIdentity.arn
| filter eventName like /PutBucket|DeleteBucket|PutBucketPolicy/
| sort @timestamp desc

# Query 4: High-volume access patterns
fields @timestamp, eventName, sourceIPAddress
| filter eventName like /GetObject|PutObject|DeleteObject/
| stats count() by sourceIPAddress
| sort count desc
| limit 20

# Query 5: Error analysis
fields @timestamp, eventName, errorCode, errorMessage
| filter ispresent(errorCode)
| stats count() by errorCode, errorMessage
| sort count desc
EOF

success "Created CloudWatch Insights queries for security analysis"

# Save configuration for cleanup
log "Saving deployment configuration..."
cat > deployment-config.env << EOF
# S3 Access Logging and Security Monitoring Deployment Configuration
export AWS_REGION=${AWS_REGION}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export SOURCE_BUCKET=${SOURCE_BUCKET}
export LOGS_BUCKET=${LOGS_BUCKET}
export CLOUDTRAIL_BUCKET=${CLOUDTRAIL_BUCKET}
export TRAIL_NAME=${TRAIL_NAME}
export LOG_GROUP_NAME=${LOG_GROUP_NAME}
export SNS_TOPIC_ARN=${SNS_TOPIC_ARN}
export ROLE_ARN=${ROLE_ARN}
EOF

success "Deployment configuration saved to deployment-config.env"

# Final validation
log "Performing final validation..."

# Check bucket creation
for bucket in "${SOURCE_BUCKET}" "${LOGS_BUCKET}" "${CLOUDTRAIL_BUCKET}"; do
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Bucket ${bucket} would be created"
    else
        if aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
            success "Bucket ${bucket} is accessible"
        else
            warning "Bucket ${bucket} may not be ready yet"
        fi
    fi
done

# Check CloudTrail status
if [[ "$DRY_RUN" == "true" ]]; then
    success "DRY-RUN: CloudTrail would be logging"
else
    if aws cloudtrail get-trail-status --name "${TRAIL_NAME}" --query IsLogging --output text 2>/dev/null | grep -q "True"; then
        success "CloudTrail is logging"
    else
        warning "CloudTrail logging status could not be verified"
    fi
fi

# Check CloudWatch log group
if [[ "$DRY_RUN" == "true" ]]; then
    success "DRY-RUN: CloudWatch log group would be created"
else
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${LOG_GROUP_NAME}"; then
        success "CloudWatch log group created"
    else
        warning "CloudWatch log group status could not be verified"
    fi
fi

log "Deployment completed successfully!"
log ""
log "📋 Deployment Summary:"
log "  🗂️  Source Bucket: ${SOURCE_BUCKET}"
log "  📝 Logs Bucket: ${LOGS_BUCKET}"
log "  🛤️  CloudTrail Bucket: ${CLOUDTRAIL_BUCKET}"
log "  📊 CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=S3SecurityMonitoring"
log "  🚨 SNS Topic ARN: ${SNS_TOPIC_ARN}"
log ""
log "⚠️  Important Notes:"
log "  1. S3 Server Access Logs may take several hours to appear"
log "  2. CloudTrail events typically appear within 5-15 minutes"
log "  3. Subscribe to the SNS topic to receive security alerts:"
log "     aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint your-email@example.com"
log "  4. Use the CloudWatch Insights queries in security-queries.txt for log analysis"
log ""
log "🧹 To clean up resources, run: ./destroy.sh"

# Create a test file to generate some logging activity
if [[ "$DRY_RUN" == "false" ]]; then
    log "Creating test file to generate logging activity..."
    echo "Test content for S3 access logging validation" > test-file.txt
    execute_command "aws s3 cp test-file.txt s3://${SOURCE_BUCKET}/"
    rm -f test-file.txt
    success "Test file uploaded to generate access logs"
fi

success "S3 Access Logging and Security Monitoring deployment completed successfully!"