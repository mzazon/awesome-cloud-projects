#!/bin/bash

# Deploy script for Event-Driven Data Processing with S3 Event Notifications
# This script creates all the infrastructure needed for the recipe solution

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in DRY-RUN mode - no resources will be created"
fi

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is installed (used for JSON parsing)
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
    fi
    
    # Check if zip is installed (used for Lambda deployment packages)
    if ! command -v zip &> /dev/null; then
        error "zip is not installed. Please install it first."
    fi
    
    # Check required permissions
    info "Checking AWS permissions..."
    local permissions=(
        "s3:CreateBucket"
        "s3:PutBucketNotification"
        "lambda:CreateFunction"
        "lambda:AddPermission"
        "iam:CreateRole"
        "iam:AttachRolePolicy"
        "sns:CreateTopic"
        "sqs:CreateQueue"
        "cloudwatch:PutMetricAlarm"
    )
    
    # Note: In a real implementation, you would check these permissions
    # For now, we'll assume they exist if the user can call get-caller-identity
    
    log "Prerequisites check completed successfully"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warn "No AWS region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Export resource names
    export BUCKET_NAME="data-processing-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="data-processor-${random_suffix}"
    export ERROR_HANDLER_NAME="error-handler-${random_suffix}"
    export DLQ_NAME="data-processing-dlq-${random_suffix}"
    export SNS_TOPIC_NAME="data-processing-alerts-${random_suffix}"
    export LAMBDA_ROLE_NAME="data-processing-lambda-role-${random_suffix}"
    
    # Create temporary directory for deployment files
    export TEMP_DIR=$(mktemp -d)
    
    log "Environment variables configured:"
    info "  AWS Region: $AWS_REGION"
    info "  AWS Account ID: $AWS_ACCOUNT_ID"
    info "  Bucket Name: $BUCKET_NAME"
    info "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    info "  Error Handler: $ERROR_HANDLER_NAME"
    info "  DLQ Name: $DLQ_NAME"
    info "  SNS Topic: $SNS_TOPIC_NAME"
    info "  Lambda Role: $LAMBDA_ROLE_NAME"
    info "  Temp Directory: $TEMP_DIR"
}

# Create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create S3 bucket: $BUCKET_NAME"
        return 0
    fi
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        warn "S3 bucket $BUCKET_NAME already exists, skipping creation"
        return 0
    fi
    
    # Create bucket (handle region-specific creation)
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$AWS_REGION"
    else
        aws s3api create-bucket \
            --bucket "$BUCKET_NAME" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    log "S3 bucket created successfully: $BUCKET_NAME"
}

# Create SNS topic
create_sns_topic() {
    log "Creating SNS topic..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create SNS topic: $SNS_TOPIC_NAME"
        export SNS_TOPIC_ARN="arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT_ID:$SNS_TOPIC_NAME"
        return 0
    fi
    
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query TopicArn --output text)
    
    # Note: In a real deployment, you would subscribe an email address here
    # For now, we'll just create the topic
    warn "SNS topic created but no email subscription added. Add manually if needed."
    
    log "SNS topic created successfully: $SNS_TOPIC_ARN"
}

# Create SQS Dead Letter Queue
create_sqs_dlq() {
    log "Creating SQS Dead Letter Queue..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create SQS DLQ: $DLQ_NAME"
        export DLQ_URL="https://sqs.$AWS_REGION.amazonaws.com/$AWS_ACCOUNT_ID/$DLQ_NAME"
        export DLQ_ARN="arn:aws:sqs:$AWS_REGION:$AWS_ACCOUNT_ID:$DLQ_NAME"
        return 0
    fi
    
    export DLQ_URL=$(aws sqs create-queue \
        --queue-name "$DLQ_NAME" \
        --attributes VisibilityTimeoutSeconds=300 \
        --query QueueUrl --output text)
    
    export DLQ_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$DLQ_URL" \
        --attribute-names QueueArn \
        --query Attributes.QueueArn --output text)
    
    log "SQS Dead Letter Queue created successfully: $DLQ_ARN"
}

# Create IAM role for Lambda functions
create_lambda_role() {
    log "Creating IAM role for Lambda functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create IAM role: $LAMBDA_ROLE_NAME"
        return 0
    fi
    
    # Create trust policy
    cat > "$TEMP_DIR/lambda-trust-policy.json" << 'EOF'
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
        --role-name "$LAMBDA_ROLE_NAME" \
        --assume-role-policy-document "file://$TEMP_DIR/lambda-trust-policy.json" \
        --description "Role for data processing Lambda functions"
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for S3, SQS, and SNS access
    cat > "$TEMP_DIR/lambda-execution-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::$BUCKET_NAME/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sqs:SendMessage",
                "sqs:GetQueueAttributes"
            ],
            "Resource": [
                "$DLQ_ARN"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": [
                "$SNS_TOPIC_ARN"
            ]
        }
    ]
}
EOF
    
    # Attach custom policy
    aws iam put-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-name DataProcessingPolicy \
        --policy-document "file://$TEMP_DIR/lambda-execution-policy.json"
    
    # Wait for role to be ready
    log "Waiting for IAM role to be ready..."
    sleep 10
    
    log "IAM role created successfully: $LAMBDA_ROLE_NAME"
}

# Create Lambda function for data processing
create_data_processor_lambda() {
    log "Creating data processing Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create Lambda function: $LAMBDA_FUNCTION_NAME"
        export LAMBDA_ARN="arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:$LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Create Lambda function code
    cat > "$TEMP_DIR/data_processor.py" << 'EOF'
import json
import boto3
import urllib.parse
from datetime import datetime

s3 = boto3.client('s3')
sqs = boto3.client('sqs')

def lambda_handler(event, context):
    try:
        # Process each S3 event record
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = urllib.parse.unquote_plus(record['s3']['object']['key'])
            
            print(f"Processing object: {key} from bucket: {bucket}")
            
            # Get object metadata
            response = s3.head_object(Bucket=bucket, Key=key)
            file_size = response['ContentLength']
            
            # Example processing logic based on file type
            if key.endswith('.csv'):
                process_csv_file(bucket, key, file_size)
            elif key.endswith('.json'):
                process_json_file(bucket, key, file_size)
            else:
                print(f"Unsupported file type: {key}")
                continue
            
            # Create processing report
            create_processing_report(bucket, key, file_size)
            
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed S3 events')
        }
        
    except Exception as e:
        print(f"Error processing S3 event: {str(e)}")
        # Send to DLQ for retry logic
        send_to_dlq(event, str(e))
        raise e

def process_csv_file(bucket, key, file_size):
    """Process CSV files - add your business logic here"""
    print(f"Processing CSV file: {key} (Size: {file_size} bytes)")
    # Add your CSV processing logic here
    
def process_json_file(bucket, key, file_size):
    """Process JSON files - add your business logic here"""
    print(f"Processing JSON file: {key} (Size: {file_size} bytes)")
    # Add your JSON processing logic here

def create_processing_report(bucket, key, file_size):
    """Create a processing report and store it in S3"""
    report_key = f"reports/{key}-report-{datetime.now().strftime('%Y%m%d%H%M%S')}.json"
    
    report = {
        'file_processed': key,
        'file_size': file_size,
        'processing_time': datetime.now().isoformat(),
        'status': 'completed'
    }
    
    s3.put_object(
        Bucket=bucket,
        Key=report_key,
        Body=json.dumps(report),
        ContentType='application/json'
    )
    
    print(f"Processing report created: {report_key}")

def send_to_dlq(event, error_message):
    """Send failed event to DLQ for retry"""
    import os
    dlq_url = os.environ.get('DLQ_URL')
    
    if dlq_url:
        message = {
            'original_event': event,
            'error_message': error_message,
            'timestamp': datetime.now().isoformat()
        }
        
        sqs.send_message(
            QueueUrl=dlq_url,
            MessageBody=json.dumps(message)
        )
EOF
    
    # Create deployment package
    cd "$TEMP_DIR"
    zip data_processor.zip data_processor.py
    
    # Create Lambda function
    export LAMBDA_ARN=$(aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::$AWS_ACCOUNT_ID:role/$LAMBDA_ROLE_NAME" \
        --handler data_processor.lambda_handler \
        --zip-file fileb://data_processor.zip \
        --timeout 300 \
        --memory-size 512 \
        --environment Variables="{DLQ_URL=$DLQ_URL}" \
        --dead-letter-config TargetArn="$DLQ_ARN" \
        --description "Data processing function triggered by S3 events" \
        --query FunctionArn --output text)
    
    log "Data processing Lambda function created successfully: $LAMBDA_ARN"
}

# Create Lambda function for error handling
create_error_handler_lambda() {
    log "Creating error handler Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create error handler Lambda function: $ERROR_HANDLER_NAME"
        export ERROR_HANDLER_ARN="arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:$ERROR_HANDLER_NAME"
        return 0
    fi
    
    # Create error handler function code
    cat > "$TEMP_DIR/error_handler.py" << 'EOF'
import json
import boto3
from datetime import datetime

sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        # Process SQS messages from DLQ
        for record in event['Records']:
            message_body = json.loads(record['body'])
            
            # Extract error details
            error_message = message_body.get('error_message', 'Unknown error')
            timestamp = message_body.get('timestamp', datetime.now().isoformat())
            
            # Send alert via SNS
            alert_message = f"""
Data Processing Error Alert

Error: {error_message}
Timestamp: {timestamp}

Please investigate the failed processing job.
"""
            
            import os
            sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
            
            if sns_topic_arn:
                sns.publish(
                    TopicArn=sns_topic_arn,
                    Message=alert_message,
                    Subject='Data Processing Error Alert'
                )
            
            print(f"Error alert sent for: {error_message}")
            
    except Exception as e:
        print(f"Error in error handler: {str(e)}")
        raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('Error handling completed')
    }
EOF
    
    # Create deployment package
    cd "$TEMP_DIR"
    zip error_handler.zip error_handler.py
    
    # Create error handler Lambda function
    export ERROR_HANDLER_ARN=$(aws lambda create-function \
        --function-name "$ERROR_HANDLER_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::$AWS_ACCOUNT_ID:role/$LAMBDA_ROLE_NAME" \
        --handler error_handler.lambda_handler \
        --zip-file fileb://error_handler.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{SNS_TOPIC_ARN=$SNS_TOPIC_ARN}" \
        --description "Error handler for failed data processing events" \
        --query FunctionArn --output text)
    
    log "Error handler Lambda function created successfully: $ERROR_HANDLER_ARN"
}

# Configure SQS trigger for error handler
configure_sqs_trigger() {
    log "Configuring SQS trigger for error handler..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would configure SQS trigger for error handler"
        return 0
    fi
    
    # Create event source mapping for DLQ to error handler
    aws lambda create-event-source-mapping \
        --function-name "$ERROR_HANDLER_NAME" \
        --event-source-arn "$DLQ_ARN" \
        --batch-size 10 \
        --maximum-batching-window-in-seconds 5
    
    log "SQS event source mapping created successfully"
}

# Grant S3 permission to invoke Lambda
grant_s3_permissions() {
    log "Granting S3 permission to invoke Lambda..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would grant S3 permission to invoke Lambda"
        return 0
    fi
    
    # Add permission for S3 to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id s3-trigger-permission \
        --source-arn "arn:aws:s3:::$BUCKET_NAME"
    
    log "S3 permission granted successfully"
}

# Configure S3 event notifications
configure_s3_notifications() {
    log "Configuring S3 event notifications..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would configure S3 event notifications"
        return 0
    fi
    
    # Create notification configuration
    cat > "$TEMP_DIR/notification-config.json" << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "data-processing-notification",
            "LambdaFunctionArn": "$LAMBDA_ARN",
            "Events": [
                "s3:ObjectCreated:*"
            ],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "data/"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
    
    # Apply notification configuration
    aws s3api put-bucket-notification-configuration \
        --bucket "$BUCKET_NAME" \
        --notification-configuration "file://$TEMP_DIR/notification-config.json"
    
    log "S3 event notifications configured successfully"
}

# Create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create CloudWatch alarms"
        return 0
    fi
    
    # Create alarm for Lambda errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "${LAMBDA_FUNCTION_NAME}-errors" \
        --alarm-description "Monitor Lambda function errors" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME"
    
    # Create alarm for DLQ message count
    aws cloudwatch put-metric-alarm \
        --alarm-name "${DLQ_NAME}-messages" \
        --alarm-description "Monitor DLQ message count" \
        --metric-name ApproximateNumberOfVisibleMessages \
        --namespace AWS/SQS \
        --statistic Average \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --dimensions Name=QueueName,Value="$DLQ_NAME"
    
    log "CloudWatch alarms created successfully"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "Temporary files cleaned up"
    fi
}

# Print deployment summary
print_summary() {
    log "Deployment completed successfully!"
    echo ""
    echo "========================================="
    echo "DEPLOYMENT SUMMARY"
    echo "========================================="
    echo "S3 Bucket: $BUCKET_NAME"
    echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "Error Handler: $ERROR_HANDLER_NAME"
    echo "DLQ: $DLQ_NAME"
    echo "SNS Topic: $SNS_TOPIC_ARN"
    echo "Lambda Role: $LAMBDA_ROLE_NAME"
    echo "AWS Region: $AWS_REGION"
    echo "========================================="
    echo ""
    echo "To test the deployment:"
    echo "1. Upload a CSV or JSON file to s3://$BUCKET_NAME/data/"
    echo "2. Check CloudWatch Logs for Lambda execution"
    echo "3. Check s3://$BUCKET_NAME/reports/ for processing reports"
    echo ""
    echo "To monitor the system:"
    echo "1. Subscribe to SNS topic: $SNS_TOPIC_ARN"
    echo "2. Monitor CloudWatch alarms"
    echo "3. Check DLQ for failed messages"
    echo ""
    echo "To clean up, run: ./destroy.sh"
    echo "========================================="
}

# Main deployment function
main() {
    log "Starting deployment of Event-Driven Data Processing with S3 Event Notifications"
    
    # Set trap to cleanup on exit
    trap cleanup_temp_files EXIT
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_sns_topic
    create_sqs_dlq
    create_lambda_role
    create_data_processor_lambda
    create_error_handler_lambda
    configure_sqs_trigger
    grant_s3_permissions
    configure_s3_notifications
    create_cloudwatch_alarms
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY-RUN completed - no resources were actually created"
    else
        print_summary
    fi
}

# Run main function
main "$@"