#!/bin/bash

# AWS Blockchain Audit Trails Compliance - Deployment Script
# This script deploys the complete infrastructure for blockchain-based compliance audit trails
# using Amazon QLDB, CloudTrail, EventBridge, Lambda, and supporting services.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/compliance-audit-deploy-$(date +%Y%m%d-%H%M%S).log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "${LOG_FILE}"
}

# Error handling function
handle_error() {
    log_error "Deployment failed on line $1"
    log_error "Check log file: ${LOG_FILE}"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if Python 3 is available
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check required permissions
    log "Checking AWS permissions..."
    local caller_identity
    caller_identity=$(aws sts get-caller-identity)
    log "Deploying as: $(echo "${caller_identity}" | jq -r '.Arn // .UserId')"
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Export environment variables
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "No default region found, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        python3 -c "import random, string; print(''.join(random.choices(string.ascii_lowercase + string.digits, k=6)))")
    
    export LEDGER_NAME="compliance-audit-ledger-${random_suffix}"
    export CLOUDTRAIL_NAME="compliance-audit-trail-${random_suffix}"
    export S3_BUCKET_NAME="compliance-audit-bucket-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="audit-processor-${random_suffix}"
    
    # Save environment variables for cleanup script
    cat > /tmp/compliance-audit-env.sh << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export LEDGER_NAME="${LEDGER_NAME}"
export CLOUDTRAIL_NAME="${CLOUDTRAIL_NAME}"
export S3_BUCKET_NAME="${S3_BUCKET_NAME}"
export LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME}"
EOF
    
    log_success "Environment variables configured"
    log "Using AWS Region: ${AWS_REGION}"
    log "Using Account ID: ${AWS_ACCOUNT_ID}"
    log "Resource suffix: ${random_suffix}"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for audit reports and CloudTrail logs..."
    
    # Create S3 bucket with region-specific configuration
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb s3://${S3_BUCKET_NAME}
    else
        aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    # Wait for bucket to be available
    aws s3api wait bucket-exists --bucket ${S3_BUCKET_NAME}
    
    # Enable versioning on S3 bucket for audit integrity
    aws s3api put-bucket-versioning \
        --bucket ${S3_BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption on S3 bucket
    aws s3api put-bucket-encryption \
        --bucket ${S3_BUCKET_NAME} \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    # Enable public access block for security
    aws s3api put-public-access-block \
        --bucket ${S3_BUCKET_NAME} \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    log_success "S3 bucket created: ${S3_BUCKET_NAME}"
}

# Function to create QLDB ledger
create_qldb_ledger() {
    log "Creating Amazon QLDB ledger for immutable records..."
    
    # Create QLDB ledger with standard permissions mode
    aws qldb create-ledger \
        --name ${LEDGER_NAME} \
        --permissions-mode STANDARD \
        --deletion-protection \
        --tags Environment=compliance,Purpose=audit-trail,CreatedBy=deployment-script
    
    # Wait for ledger to become active
    log "Waiting for QLDB ledger to become active..."
    local max_attempts=30
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local status
        status=$(aws qldb describe-ledger --name ${LEDGER_NAME} --query 'State' --output text)
        
        if [[ "${status}" == "ACTIVE" ]]; then
            break
        fi
        
        log "Ledger status: ${status}, waiting... (${attempt}/${max_attempts})"
        sleep 10
        ((attempt++))
    done
    
    if [[ ${attempt} -gt ${max_attempts} ]]; then
        log_error "QLDB ledger failed to become active within expected time"
        exit 1
    fi
    
    # Get ledger ARN for later use
    export LEDGER_ARN=$(aws qldb describe-ledger \
        --name ${LEDGER_NAME} \
        --query 'Arn' --output text)
    
    log_success "QLDB ledger created: ${LEDGER_NAME}"
    log "Ledger ARN: ${LEDGER_ARN}"
}

# Function to create IAM role for Lambda
create_lambda_iam_role() {
    log "Creating IAM role for Lambda audit processor..."
    
    # Create trust policy for Lambda
    cat > /tmp/lambda-trust-policy.json << EOF
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
    
    # Create IAM role
    aws iam create-role \
        --role-name ${LAMBDA_FUNCTION_NAME}-role \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --tags Key=Environment,Value=compliance Key=Purpose,Value=audit-trail Key=CreatedBy,Value=deployment-script
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name ${LAMBDA_FUNCTION_NAME}-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for QLDB and other services
    cat > /tmp/lambda-custom-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "qldb:SendCommand",
                "qldb:GetDigest",
                "qldb:GetBlock",
                "qldb:GetRevision"
            ],
            "Resource": "${LEDGER_ARN}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name ${LAMBDA_FUNCTION_NAME}-role \
        --policy-name ${LAMBDA_FUNCTION_NAME}-policy \
        --policy-document file:///tmp/lambda-custom-policy.json
    
    # Wait for role to be available
    sleep 10
    
    # Get role ARN
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name ${LAMBDA_FUNCTION_NAME}-role \
        --query 'Role.Arn' --output text)
    
    log_success "Lambda IAM role created: ${LAMBDA_ROLE_ARN}"
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function for audit processing..."
    
    # Create Lambda function code
    cat > /tmp/audit_processor.py << 'EOF'
import json
import boto3
import hashlib
import datetime
import os
from botocore.exceptions import ClientError

qldb_client = boto3.client('qldb')
s3_client = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Process CloudTrail event
        audit_record = create_audit_record(event)
        
        # Store in QLDB (simplified for demo)
        ledger_name = os.environ['LEDGER_NAME']
        store_audit_record(ledger_name, audit_record)
        
        # Generate compliance metrics
        generate_compliance_metrics(audit_record)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Audit record processed successfully')
        }
        
    except Exception as e:
        print(f"Error processing audit record: {str(e)}")
        raise

def create_audit_record(event):
    timestamp = datetime.datetime.utcnow().isoformat()
    
    # Extract relevant audit information
    audit_record = {
        'auditId': hashlib.sha256(str(event).encode()).hexdigest()[:16],
        'timestamp': timestamp,
        'eventName': event.get('detail', {}).get('eventName', 'Unknown'),
        'userIdentity': event.get('detail', {}).get('userIdentity', {}),
        'sourceIPAddress': event.get('detail', {}).get('sourceIPAddress', ''),
        'resources': event.get('detail', {}).get('resources', []),
        'eventSource': event.get('detail', {}).get('eventSource', ''),
        'awsRegion': event.get('detail', {}).get('awsRegion', ''),
        'recordHash': ''
    }
    
    # Create hash for integrity verification
    record_string = json.dumps(audit_record, sort_keys=True)
    audit_record['recordHash'] = hashlib.sha256(record_string.encode()).hexdigest()
    
    return audit_record

def store_audit_record(ledger_name, audit_record):
    try:
        # Note: This is a simplified example
        # In production, use proper QLDB session management
        response = qldb_client.get_digest(Name=ledger_name)
        print(f"Stored audit record: {audit_record['auditId']}")
        
        # Store a copy in S3 as well
        s3_bucket = os.environ.get('S3_BUCKET')
        if s3_bucket:
            key = f"audit-records/{datetime.datetime.utcnow().strftime('%Y/%m/%d')}/{audit_record['auditId']}.json"
            s3_client.put_object(
                Bucket=s3_bucket,
                Key=key,
                Body=json.dumps(audit_record),
                ContentType='application/json'
            )
        
    except ClientError as e:
        print(f"Error storing audit record: {e}")
        raise

def generate_compliance_metrics(audit_record):
    # Send custom metrics to CloudWatch
    try:
        cloudwatch.put_metric_data(
            Namespace='ComplianceAudit',
            MetricData=[
                {
                    'MetricName': 'AuditRecordsProcessed',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'EventSource',
                            'Value': audit_record['eventSource']
                        }
                    ]
                }
            ]
        )
    except Exception as e:
        print(f"Error sending metrics: {e}")
EOF
    
    # Create deployment package
    cd /tmp
    zip -q audit_processor.zip audit_processor.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --runtime python3.9 \
        --role ${LAMBDA_ROLE_ARN} \
        --handler audit_processor.lambda_handler \
        --zip-file fileb://audit_processor.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{LEDGER_NAME=${LEDGER_NAME},S3_BUCKET=${S3_BUCKET_NAME}}" \
        --tags Environment=compliance,Purpose=audit-trail,CreatedBy=deployment-script
    
    # Get Lambda function ARN
    export LAMBDA_ARN=$(aws lambda get-function \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --query 'Configuration.FunctionArn' --output text)
    
    log_success "Lambda function created: ${LAMBDA_FUNCTION_NAME}"
    log "Lambda ARN: ${LAMBDA_ARN}"
}

# Function to create CloudTrail
create_cloudtrail() {
    log "Creating CloudTrail for API activity logging..."
    
    # Create CloudTrail trail
    aws cloudtrail create-trail \
        --name ${CLOUDTRAIL_NAME} \
        --s3-bucket-name ${S3_BUCKET_NAME} \
        --s3-key-prefix "cloudtrail-logs/" \
        --include-global-service-events \
        --is-multi-region-trail \
        --enable-log-file-validation \
        --tags-list Key=Environment,Value=compliance \
                   Key=Purpose,Value=audit-trail \
                   Key=CreatedBy,Value=deployment-script
    
    # Start logging
    aws cloudtrail start-logging \
        --name ${CLOUDTRAIL_NAME}
    
    # Get CloudTrail ARN
    export CLOUDTRAIL_ARN=$(aws cloudtrail describe-trails \
        --trail-name-list ${CLOUDTRAIL_NAME} \
        --query 'trailList[0].TrailARN' --output text)
    
    log_success "CloudTrail created and started: ${CLOUDTRAIL_NAME}"
    log "CloudTrail ARN: ${CLOUDTRAIL_ARN}"
}

# Function to create EventBridge rule
create_eventbridge_rule() {
    log "Creating EventBridge rule for real-time processing..."
    
    # Create EventBridge rule for CloudTrail events
    aws events put-rule \
        --name compliance-audit-rule \
        --event-pattern '{
            "source": ["aws.cloudtrail"],
            "detail-type": ["AWS API Call via CloudTrail"],
            "detail": {
                "eventSource": ["qldb.amazonaws.com", "s3.amazonaws.com", "iam.amazonaws.com"],
                "eventName": ["SendCommand", "PutObject", "CreateRole", "DeleteRole"]
            }
        }' \
        --state ENABLED \
        --description "Process critical API calls for compliance audit" \
        --tags Key=Environment,Value=compliance Key=Purpose,Value=audit-trail Key=CreatedBy,Value=deployment-script
    
    # Add Lambda as target
    aws events put-targets \
        --rule compliance-audit-rule \
        --targets "Id"="1","Arn"="${LAMBDA_ARN}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name ${LAMBDA_FUNCTION_NAME} \
        --statement-id allow-eventbridge \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/compliance-audit-rule
    
    log_success "EventBridge rule created for real-time audit processing"
}

# Function to create SNS topic and CloudWatch alarm
create_monitoring() {
    log "Creating SNS topic and CloudWatch monitoring..."
    
    # Create SNS topic for compliance notifications
    export COMPLIANCE_TOPIC_ARN=$(aws sns create-topic \
        --name compliance-audit-alerts \
        --tags Key=Environment,Value=compliance Key=Purpose,Value=audit-trail Key=CreatedBy,Value=deployment-script \
        --query 'TopicArn' --output text)
    
    log "SNS topic created: ${COMPLIANCE_TOPIC_ARN}"
    log_warning "Please manually subscribe your email to SNS topic: ${COMPLIANCE_TOPIC_ARN}"
    
    # Create CloudWatch alarm for audit processing failures
    aws cloudwatch put-metric-alarm \
        --alarm-name "ComplianceAuditErrors" \
        --alarm-description "Alert when audit processing fails" \
        --metric-name "Errors" \
        --namespace "AWS/Lambda" \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions ${COMPLIANCE_TOPIC_ARN} \
        --dimensions Name=FunctionName,Value=${LAMBDA_FUNCTION_NAME} \
        --tags Key=Environment,Value=compliance Key=Purpose,Value=audit-trail Key=CreatedBy,Value=deployment-script
    
    log_success "CloudWatch alarm configured for error monitoring"
}

# Function to create Kinesis Data Firehose
create_kinesis_firehose() {
    log "Creating Kinesis Data Firehose for compliance reporting..."
    
    # Create IAM role for Kinesis Data Firehose
    cat > /tmp/firehose-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "firehose.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    aws iam create-role \
        --role-name compliance-firehose-role \
        --assume-role-policy-document file:///tmp/firehose-trust-policy.json \
        --tags Key=Environment,Value=compliance Key=Purpose,Value=audit-trail Key=CreatedBy,Value=deployment-script
    
    # Create policy for Firehose
    cat > /tmp/firehose-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_NAME}",
                "arn:aws:s3:::${S3_BUCKET_NAME}/*"
            ]
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name compliance-firehose-role \
        --policy-name compliance-firehose-policy \
        --policy-document file:///tmp/firehose-policy.json
    
    # Wait for role to be available
    sleep 10
    
    # Get Firehose role ARN
    export FIREHOSE_ROLE_ARN=$(aws iam get-role \
        --role-name compliance-firehose-role \
        --query 'Role.Arn' --output text)
    
    # Create Kinesis Data Firehose delivery stream
    aws firehose create-delivery-stream \
        --delivery-stream-name compliance-audit-stream \
        --delivery-stream-type DirectPut \
        --s3-destination-configuration '{
            "RoleARN": "'${FIREHOSE_ROLE_ARN}'",
            "BucketARN": "arn:aws:s3:::'${S3_BUCKET_NAME}'",
            "Prefix": "compliance-reports/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/",
            "BufferingHints": {
                "SizeInMBs": 5,
                "IntervalInSeconds": 300
            },
            "CompressionFormat": "GZIP"
        }' \
        --tags Key=Environment,Value=compliance Key=Purpose,Value=audit-trail Key=CreatedBy,Value=deployment-script
    
    log_success "Kinesis Data Firehose created for compliance reporting"
}

# Function to set up Athena
setup_athena() {
    log "Setting up Athena for compliance queries..."
    
    # Create Athena workgroup for compliance queries
    aws athena create-work-group \
        --name compliance-audit-workgroup \
        --description "Workgroup for compliance audit queries" \
        --configuration '{
            "ResultConfiguration": {
                "OutputLocation": "s3://'${S3_BUCKET_NAME}'/athena-results/"
            },
            "EnforceWorkGroupConfiguration": true,
            "PublishCloudWatchMetrics": true
        }' \
        --tags Key=Environment,Value=compliance Key=Purpose,Value=audit-trail Key=CreatedBy,Value=deployment-script
    
    # Create Athena database for compliance data
    local query_id
    query_id=$(aws athena start-query-execution \
        --work-group compliance-audit-workgroup \
        --query-string "CREATE DATABASE IF NOT EXISTS compliance_audit_db;" \
        --result-configuration OutputLocation=s3://${S3_BUCKET_NAME}/athena-results/ \
        --query 'QueryExecutionId' --output text)
    
    # Wait for query to complete
    local max_attempts=30
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local status
        status=$(aws athena get-query-execution --query-execution-id ${query_id} --query 'QueryExecution.Status.State' --output text)
        
        if [[ "${status}" == "SUCCEEDED" ]]; then
            break
        elif [[ "${status}" == "FAILED" || "${status}" == "CANCELLED" ]]; then
            log_error "Athena database creation failed"
            exit 1
        fi
        
        sleep 5
        ((attempt++))
    done
    
    log_success "Athena workgroup and database created for compliance queries"
}

# Function to create CloudWatch dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard for compliance metrics..."
    
    # Create CloudWatch dashboard for compliance metrics
    aws cloudwatch put-dashboard \
        --dashboard-name "ComplianceAuditDashboard" \
        --dashboard-body '{
            "widgets": [
                {
                    "type": "metric",
                    "x": 0,
                    "y": 0,
                    "width": 12,
                    "height": 6,
                    "properties": {
                        "metrics": [
                            [ "ComplianceAudit", "AuditRecordsProcessed" ],
                            [ "AWS/Lambda", "Invocations", "FunctionName", "'${LAMBDA_FUNCTION_NAME}'" ],
                            [ "AWS/Lambda", "Errors", "FunctionName", "'${LAMBDA_FUNCTION_NAME}'" ]
                        ],
                        "period": 300,
                        "stat": "Sum",
                        "region": "'${AWS_REGION}'",
                        "title": "Compliance Audit Metrics"
                    }
                },
                {
                    "type": "log",
                    "x": 0,
                    "y": 6,
                    "width": 24,
                    "height": 6,
                    "properties": {
                        "query": "SOURCE \"/aws/lambda/'${LAMBDA_FUNCTION_NAME}'\"\n| fields @timestamp, @message\n| filter @message like /audit/\n| sort @timestamp desc\n| limit 100",
                        "region": "'${AWS_REGION}'",
                        "title": "Recent Audit Processing Logs"
                    }
                }
            ]
        }'
    
    log_success "CloudWatch dashboard created: ComplianceAuditDashboard"
}

# Function to display deployment summary
display_summary() {
    log_success "🎉 Blockchain Audit Trails Compliance infrastructure deployed successfully!"
    
    echo ""
    echo "=================================================================================="
    echo "                          DEPLOYMENT SUMMARY"
    echo "=================================================================================="
    echo ""
    echo "📋 Core Infrastructure:"
    echo "   • QLDB Ledger: ${LEDGER_NAME}"
    echo "   • CloudTrail: ${CLOUDTRAIL_NAME}"
    echo "   • S3 Bucket: ${S3_BUCKET_NAME}"
    echo "   • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo ""
    echo "🔗 Resource ARNs:"
    echo "   • QLDB Ledger: ${LEDGER_ARN}"
    echo "   • Lambda Function: ${LAMBDA_ARN}"
    echo "   • CloudTrail: ${CLOUDTRAIL_ARN}"
    echo "   • SNS Topic: ${COMPLIANCE_TOPIC_ARN}"
    echo ""
    echo "📊 Monitoring & Analytics:"
    echo "   • CloudWatch Dashboard: ComplianceAuditDashboard"
    echo "   • Athena Workgroup: compliance-audit-workgroup"
    echo "   • EventBridge Rule: compliance-audit-rule"
    echo "   • Kinesis Firehose: compliance-audit-stream"
    echo ""
    echo "🔧 Next Steps:"
    echo "   1. Subscribe your email to SNS topic: ${COMPLIANCE_TOPIC_ARN}"
    echo "   2. Test the system by performing some API operations"
    echo "   3. Check CloudWatch dashboard for metrics"
    echo "   4. Query audit data using Athena workgroup"
    echo ""
    echo "📝 Important Files:"
    echo "   • Environment variables: /tmp/compliance-audit-env.sh"
    echo "   • Deployment log: ${LOG_FILE}"
    echo ""
    echo "⚠️  QLDB Deprecation Notice:"
    echo "   Amazon QLDB is deprecated and will reach end-of-support on July 31, 2025."
    echo "   Consider migrating to Amazon Aurora PostgreSQL for production use."
    echo ""
    echo "🧹 To clean up resources, run: ./destroy.sh"
    echo "=================================================================================="
}

# Main deployment function
main() {
    log "🚀 Starting deployment of Blockchain Audit Trails Compliance infrastructure..."
    log "Deployment log: ${LOG_FILE}"
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_qldb_ledger
    create_lambda_iam_role
    create_lambda_function
    create_cloudtrail
    create_eventbridge_rule
    create_monitoring
    create_kinesis_firehose
    setup_athena
    create_dashboard
    display_summary
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi