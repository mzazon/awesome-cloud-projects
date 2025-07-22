#!/bin/bash
set -e

# Real-Time IoT Analytics Deployment Script
# This script deploys the complete IoT analytics pipeline with Kinesis, Flink, Lambda, and S3

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMP_DIR="/tmp/iot-analytics-deployment"

# Default values
DRY_RUN=false
VERBOSE=false
SKIP_CONFIRMATION=false
EMAIL_ADDRESS=""

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Real-Time IoT Analytics Pipeline with Kinesis, Flink, Lambda, and S3

Options:
    -e, --email EMAIL       Email address for SNS alerts (required)
    -d, --dry-run          Show what would be deployed without actually deploying
    -v, --verbose          Enable verbose output
    -y, --yes              Skip confirmation prompts
    -h, --help             Show this help message

Examples:
    $0 --email user@example.com
    $0 --email user@example.com --dry-run
    $0 --email user@example.com --verbose --yes

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--email)
            EMAIL_ADDRESS="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$EMAIL_ADDRESS" ]]; then
    log_error "Email address is required for SNS alerts"
    usage
    exit 1
fi

# Email validation
if ! echo "$EMAIL_ADDRESS" | grep -E "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$" > /dev/null; then
    log_error "Invalid email address format"
    exit 1
fi

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is required but not installed"
        exit 1
    fi
    
    # Check pip
    if ! command -v pip3 &> /dev/null; then
        log_error "pip3 is required but not installed"
        exit 1
    fi
    
    # Check required permissions
    log_info "Checking AWS permissions..."
    local required_permissions=(
        "kinesis:CreateStream"
        "kinesis:DescribeStream"
        "lambda:CreateFunction"
        "lambda:CreateEventSourceMapping"
        "iam:CreateRole"
        "iam:AttachRolePolicy"
        "s3:CreateBucket"
        "s3:PutObject"
        "sns:CreateTopic"
        "sns:Subscribe"
        "kinesisanalyticsv2:CreateApplication"
        "cloudwatch:PutMetricAlarm"
        "cloudwatch:PutDashboard"
    )
    
    # Note: Full permission check would require simulate-principal-policy
    # For now, we'll proceed and catch permission errors during deployment
    
    log_success "Prerequisites check completed"
}

# Function to generate unique identifiers
generate_identifiers() {
    log_info "Generating unique identifiers..."
    
    # Get AWS account details
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not configured"
        exit 1
    fi
    
    # Generate random suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export PROJECT_NAME="iot-analytics-${RANDOM_SUFFIX}"
    export KINESIS_STREAM_NAME="${PROJECT_NAME}-stream"
    export FLINK_APP_NAME="${PROJECT_NAME}-flink-app"
    export LAMBDA_FUNCTION_NAME="${PROJECT_NAME}-processor"
    export S3_BUCKET_NAME="${PROJECT_NAME}-data-${AWS_ACCOUNT_ID}"
    export SNS_TOPIC_NAME="${PROJECT_NAME}-alerts"
    
    log_success "Resource identifiers generated"
    log_info "Project Name: $PROJECT_NAME"
    log_info "Region: $AWS_REGION"
    log_info "Account ID: $AWS_ACCOUNT_ID"
}

# Function to create temporary directory
setup_temp_dir() {
    log_info "Setting up temporary directory..."
    
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    
    mkdir -p "$TEMP_DIR"
    log_success "Temporary directory created: $TEMP_DIR"
}

# Function to create S3 bucket
create_s3_bucket() {
    log_info "Creating S3 bucket for data storage..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create S3 bucket: $S3_BUCKET_NAME"
        return 0
    fi
    
    # Create bucket
    if aws s3 mb "s3://${S3_BUCKET_NAME}" --region "$AWS_REGION"; then
        log_success "S3 bucket created: $S3_BUCKET_NAME"
    else
        log_error "Failed to create S3 bucket"
        return 1
    fi
    
    # Create folder structure
    aws s3api put-object --bucket "$S3_BUCKET_NAME" --key "raw-data/" --content-length 0
    aws s3api put-object --bucket "$S3_BUCKET_NAME" --key "processed-data/" --content-length 0
    aws s3api put-object --bucket "$S3_BUCKET_NAME" --key "analytics-results/" --content-length 0
    
    log_success "S3 folder structure created"
}

# Function to create Kinesis stream
create_kinesis_stream() {
    log_info "Creating Kinesis Data Stream..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Kinesis stream: $KINESIS_STREAM_NAME"
        return 0
    fi
    
    # Create stream
    if aws kinesis create-stream \
        --stream-name "$KINESIS_STREAM_NAME" \
        --shard-count 2 \
        --stream-mode-details StreamMode=PROVISIONED; then
        log_success "Kinesis stream creation initiated"
    else
        log_error "Failed to create Kinesis stream"
        return 1
    fi
    
    # Wait for stream to become active
    log_info "Waiting for Kinesis stream to become active..."
    if aws kinesis wait stream-exists --stream-name "$KINESIS_STREAM_NAME"; then
        log_success "Kinesis stream is active"
    else
        log_error "Kinesis stream failed to become active"
        return 1
    fi
    
    # Get stream ARN
    export STREAM_ARN=$(aws kinesis describe-stream \
        --stream-name "$KINESIS_STREAM_NAME" \
        --query 'StreamDescription.StreamARN' \
        --output text)
    
    log_success "Kinesis stream ARN: $STREAM_ARN"
}

# Function to create SNS topic
create_sns_topic() {
    log_info "Creating SNS topic for alerts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create SNS topic: $SNS_TOPIC_NAME"
        log_info "[DRY RUN] Would subscribe email: $EMAIL_ADDRESS"
        return 0
    fi
    
    # Create topic
    export TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query 'TopicArn' \
        --output text)
    
    if [[ -n "$TOPIC_ARN" ]]; then
        log_success "SNS topic created: $TOPIC_ARN"
    else
        log_error "Failed to create SNS topic"
        return 1
    fi
    
    # Subscribe email
    if aws sns subscribe \
        --topic-arn "$TOPIC_ARN" \
        --protocol email \
        --notification-endpoint "$EMAIL_ADDRESS"; then
        log_success "Email subscription created"
        log_warning "Please check your email and confirm the subscription"
    else
        log_error "Failed to create email subscription"
        return 1
    fi
}

# Function to create IAM roles
create_iam_roles() {
    log_info "Creating IAM roles..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Lambda IAM role: ${PROJECT_NAME}-lambda-role"
        log_info "[DRY RUN] Would create Flink IAM role: ${PROJECT_NAME}-flink-role"
        return 0
    fi
    
    # Create Lambda trust policy
    cat > "$TEMP_DIR/lambda-trust-policy.json" << EOF
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
    
    # Create Lambda role
    if aws iam create-role \
        --role-name "${PROJECT_NAME}-lambda-role" \
        --assume-role-policy-document "file://$TEMP_DIR/lambda-trust-policy.json"; then
        log_success "Lambda IAM role created"
    else
        log_error "Failed to create Lambda IAM role"
        return 1
    fi
    
    # Create Lambda policy
    cat > "$TEMP_DIR/lambda-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:DescribeStream",
                "kinesis:GetRecords",
                "kinesis:GetShardIterator",
                "kinesis:ListStreams"
            ],
            "Resource": "$STREAM_ARN"
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
                "sns:Publish"
            ],
            "Resource": "$TOPIC_ARN"
        }
    ]
}
EOF
    
    # Attach policy to Lambda role
    if aws iam put-role-policy \
        --role-name "${PROJECT_NAME}-lambda-role" \
        --policy-name "${PROJECT_NAME}-lambda-policy" \
        --policy-document "file://$TEMP_DIR/lambda-policy.json"; then
        log_success "Lambda policy attached"
    else
        log_error "Failed to attach Lambda policy"
        return 1
    fi
    
    # Create Flink trust policy
    cat > "$TEMP_DIR/flink-trust-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "kinesisanalytics.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create Flink role
    if aws iam create-role \
        --role-name "${PROJECT_NAME}-flink-role" \
        --assume-role-policy-document "file://$TEMP_DIR/flink-trust-policy.json"; then
        log_success "Flink IAM role created"
    else
        log_error "Failed to create Flink IAM role"
        return 1
    fi
    
    # Create Flink policy
    cat > "$TEMP_DIR/flink-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kinesis:DescribeStream",
                "kinesis:GetRecords",
                "kinesis:GetShardIterator",
                "kinesis:ListStreams"
            ],
            "Resource": "$STREAM_ARN"
        },
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
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
EOF
    
    # Attach policy to Flink role
    if aws iam put-role-policy \
        --role-name "${PROJECT_NAME}-flink-role" \
        --policy-name "${PROJECT_NAME}-flink-policy" \
        --policy-document "file://$TEMP_DIR/flink-policy.json"; then
        log_success "Flink policy attached"
    else
        log_error "Failed to attach Flink policy"
        return 1
    fi
    
    # Set role ARNs
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role"
    export FLINK_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-flink-role"
    
    log_success "IAM roles created and configured"
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Create Lambda function code
    cat > "$TEMP_DIR/iot-processor.py" << 'EOF'
import json
import boto3
import base64
from datetime import datetime
import os

s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    bucket_name = os.environ['S3_BUCKET_NAME']
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    processed_records = []
    
    for record in event['Records']:
        # Decode Kinesis data
        payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
        data = json.loads(payload)
        
        # Process the IoT data
        processed_data = process_iot_data(data)
        processed_records.append(processed_data)
        
        # Store raw data in S3
        timestamp = datetime.now().strftime('%Y/%m/%d/%H')
        key = f"raw-data/{timestamp}/{record['kinesis']['sequenceNumber']}.json"
        
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(data),
            ContentType='application/json'
        )
        
        # Check for anomalies and send alerts
        if is_anomaly(processed_data):
            send_alert(processed_data, topic_arn)
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Processed {len(processed_records)} records')
    }

def process_iot_data(data):
    """Process IoT sensor data"""
    return {
        'device_id': data.get('device_id'),
        'timestamp': data.get('timestamp'),
        'sensor_type': data.get('sensor_type'),
        'value': data.get('value'),
        'unit': data.get('unit'),
        'location': data.get('location'),
        'processed_at': datetime.now().isoformat()
    }

def is_anomaly(data):
    """Simple anomaly detection logic"""
    if data['sensor_type'] == 'temperature' and data['value'] > 80:
        return True
    if data['sensor_type'] == 'pressure' and data['value'] > 100:
        return True
    if data['sensor_type'] == 'vibration' and data['value'] > 50:
        return True
    return False

def send_alert(data, topic_arn):
    """Send alert via SNS"""
    message = f"ALERT: Anomaly detected in {data['sensor_type']} sensor {data['device_id']}. Value: {data['value']} {data['unit']}"
    
    sns.publish(
        TopicArn=topic_arn,
        Message=message,
        Subject="IoT Sensor Anomaly Alert"
    )
EOF
    
    # Create deployment package
    cd "$TEMP_DIR"
    zip iot-processor.zip iot-processor.py
    
    # Wait for IAM role to be ready
    log_info "Waiting for IAM role to be ready..."
    sleep 10
    
    # Create Lambda function
    if aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.11 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler iot-processor.lambda_handler \
        --zip-file "fileb://iot-processor.zip" \
        --timeout 60 \
        --memory-size 256 \
        --environment "Variables={S3_BUCKET_NAME=${S3_BUCKET_NAME},SNS_TOPIC_ARN=${TOPIC_ARN}}"; then
        log_success "Lambda function created"
    else
        log_error "Failed to create Lambda function"
        return 1
    fi
    
    # Create event source mapping
    log_info "Creating event source mapping..."
    if aws lambda create-event-source-mapping \
        --event-source-arn "$STREAM_ARN" \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --starting-position LATEST \
        --batch-size 10 \
        --maximum-batching-window-in-seconds 5; then
        log_success "Event source mapping created"
    else
        log_error "Failed to create event source mapping"
        return 1
    fi
}

# Function to create Flink application
create_flink_application() {
    log_info "Creating Flink application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Flink application: $FLINK_APP_NAME"
        return 0
    fi
    
    # Create Flink application code
    cat > "$TEMP_DIR/flink-app.py" << 'EOF'
from pyflink.table import EnvironmentSettings, TableEnvironment
from pyflink.table.descriptors import Schema, Kafka, Json
import os

def create_iot_analytics_job():
    # Set up the execution environment
    env_settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
    table_env = TableEnvironment.create(env_settings)
    
    # Define source table from Kinesis
    source_ddl = f"""
    CREATE TABLE iot_source (
        device_id STRING,
        timestamp TIMESTAMP(3),
        sensor_type STRING,
        value DOUBLE,
        unit STRING,
        location STRING,
        WATERMARK FOR timestamp AS timestamp - INTERVAL '5' SECOND
    ) WITH (
        'connector' = 'kinesis',
        'stream' = '{os.environ['KINESIS_STREAM_NAME']}',
        'aws.region' = '{os.environ['AWS_REGION']}',
        'format' = 'json'
    )
    """
    
    # Define sink table to S3
    sink_ddl = f"""
    CREATE TABLE iot_analytics_sink (
        device_id STRING,
        sensor_type STRING,
        location STRING,
        avg_value DOUBLE,
        max_value DOUBLE,
        min_value DOUBLE,
        window_start TIMESTAMP(3),
        window_end TIMESTAMP(3)
    ) WITH (
        'connector' = 's3',
        'path' = 's3://{os.environ['S3_BUCKET_NAME']}/analytics-results/',
        'format' = 'json'
    )
    """
    
    # Create tables
    table_env.execute_sql(source_ddl)
    table_env.execute_sql(sink_ddl)
    
    # Define analytics query
    analytics_query = """
    INSERT INTO iot_analytics_sink
    SELECT 
        device_id,
        sensor_type,
        location,
        AVG(value) as avg_value,
        MAX(value) as max_value,
        MIN(value) as min_value,
        TUMBLE_START(timestamp, INTERVAL '5' MINUTE) as window_start,
        TUMBLE_END(timestamp, INTERVAL '5' MINUTE) as window_end
    FROM iot_source
    GROUP BY 
        device_id,
        sensor_type,
        location,
        TUMBLE(timestamp, INTERVAL '5' MINUTE)
    """
    
    # Execute the query
    table_env.execute_sql(analytics_query)

if __name__ == "__main__":
    create_iot_analytics_job()
EOF
    
    # Create Flink application JAR
    cd "$TEMP_DIR"
    zip flink-app.zip flink-app.py
    
    # Upload to S3
    if aws s3 cp flink-app.zip "s3://${S3_BUCKET_NAME}/flink-app.zip"; then
        log_success "Flink application uploaded to S3"
    else
        log_error "Failed to upload Flink application"
        return 1
    fi
    
    # Create Flink application
    if aws kinesisanalyticsv2 create-application \
        --application-name "$FLINK_APP_NAME" \
        --runtime-environment FLINK-1_18 \
        --service-execution-role "$FLINK_ROLE_ARN" \
        --application-configuration '{
            "ApplicationCodeConfiguration": {
                "CodeContent": {
                    "S3ContentLocation": {
                        "BucketARN": "arn:aws:s3:::'${S3_BUCKET_NAME}'",
                        "FileKey": "flink-app.zip"
                    }
                },
                "CodeContentType": "ZIPFILE"
            },
            "EnvironmentProperties": {
                "PropertyGroups": [
                    {
                        "PropertyGroupId": "kinesis.analytics.flink.run.options",
                        "PropertyMap": {
                            "python": "flink-app.py"
                        }
                    }
                ]
            }
        }'; then
        log_success "Flink application created"
    else
        log_error "Failed to create Flink application"
        return 1
    fi
    
    # Start Flink application
    log_info "Starting Flink application..."
    if aws kinesisanalyticsv2 start-application \
        --application-name "$FLINK_APP_NAME" \
        --run-configuration '{
            "ApplicationRestoreConfiguration": {
                "ApplicationRestoreType": "SKIP_RESTORE_FROM_SNAPSHOT"
            }
        }'; then
        log_success "Flink application started"
    else
        log_error "Failed to start Flink application"
        return 1
    fi
}

# Function to create monitoring
create_monitoring() {
    log_info "Creating CloudWatch monitoring..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create CloudWatch alarms and dashboard"
        return 0
    fi
    
    # Create CloudWatch alarm for Kinesis stream
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-kinesis-records" \
        --alarm-description "Monitor Kinesis stream incoming records" \
        --metric-name IncomingRecords \
        --namespace AWS/Kinesis \
        --statistic Sum \
        --period 300 \
        --threshold 100 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=StreamName,Value="$KINESIS_STREAM_NAME" \
        --evaluation-periods 2 \
        --alarm-actions "$TOPIC_ARN"
    
    # Create CloudWatch alarm for Lambda errors
    aws cloudwatch put-metric-alarm \
        --alarm-name "${PROJECT_NAME}-lambda-errors" \
        --alarm-description "Monitor Lambda function errors" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
        --evaluation-periods 1 \
        --alarm-actions "$TOPIC_ARN"
    
    # Create CloudWatch dashboard
    cat > "$TEMP_DIR/dashboard.json" << EOF
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
                    [ "AWS/Kinesis", "IncomingRecords", "StreamName", "$KINESIS_STREAM_NAME" ],
                    [ ".", "OutgoingRecords", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "$AWS_REGION",
                "title": "Kinesis Stream Metrics"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/Lambda", "Invocations", "FunctionName", "$LAMBDA_FUNCTION_NAME" ],
                    [ ".", "Errors", ".", "." ],
                    [ ".", "Duration", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "$AWS_REGION",
                "title": "Lambda Function Metrics"
            }
        }
    ]
}
EOF
    
    if aws cloudwatch put-dashboard \
        --dashboard-name "${PROJECT_NAME}-analytics" \
        --dashboard-body "file://$TEMP_DIR/dashboard.json"; then
        log_success "CloudWatch dashboard created"
    else
        log_error "Failed to create CloudWatch dashboard"
        return 1
    fi
    
    log_success "CloudWatch monitoring configured"
}

# Function to create IoT simulator
create_iot_simulator() {
    log_info "Creating IoT data simulator..."
    
    cat > "$TEMP_DIR/iot-simulator.py" << 'EOF'
import json
import boto3
import random
import time
from datetime import datetime
import sys

kinesis = boto3.client('kinesis')

def generate_sensor_data():
    """Generate realistic IoT sensor data"""
    sensor_types = ['temperature', 'pressure', 'vibration', 'flow']
    locations = ['factory-floor-1', 'factory-floor-2', 'warehouse-a', 'warehouse-b']
    
    return {
        'device_id': f"sensor-{random.randint(1000, 9999)}",
        'timestamp': datetime.now().isoformat(),
        'sensor_type': random.choice(sensor_types),
        'value': round(random.uniform(10, 100), 2),
        'unit': get_unit_for_sensor(random.choice(sensor_types)),
        'location': random.choice(locations)
    }

def get_unit_for_sensor(sensor_type):
    units = {
        'temperature': '°C',
        'pressure': 'PSI',
        'vibration': 'Hz',
        'flow': 'L/min'
    }
    return units.get(sensor_type, 'units')

def send_to_kinesis(data, stream_name):
    """Send data to Kinesis stream"""
    try:
        kinesis.put_record(
            StreamName=stream_name,
            Data=json.dumps(data),
            PartitionKey=data['device_id']
        )
        print(f"Sent: {data}")
    except Exception as e:
        print(f"Error sending data: {e}")

def main():
    stream_name = sys.argv[1] if len(sys.argv) > 1 else 'iot-stream'
    
    print(f"Starting IoT data simulator for stream: {stream_name}")
    print("Press Ctrl+C to stop...")
    
    try:
        while True:
            data = generate_sensor_data()
            send_to_kinesis(data, stream_name)
            time.sleep(2)  # Send data every 2 seconds
    except KeyboardInterrupt:
        print("\nStopping simulator...")

if __name__ == "__main__":
    main()
EOF
    
    log_success "IoT simulator created at: $TEMP_DIR/iot-simulator.py"
    log_info "To run the simulator: python3 $TEMP_DIR/iot-simulator.py $KINESIS_STREAM_NAME"
}

# Function to display deployment summary
show_deployment_summary() {
    log_info "Deployment Summary:"
    echo "===================="
    echo "Project Name: $PROJECT_NAME"
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account: $AWS_ACCOUNT_ID"
    echo ""
    echo "Resources Created:"
    echo "- S3 Bucket: $S3_BUCKET_NAME"
    echo "- Kinesis Stream: $KINESIS_STREAM_NAME"
    echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "- Flink Application: $FLINK_APP_NAME"
    echo "- SNS Topic: $SNS_TOPIC_NAME"
    echo "- CloudWatch Dashboard: ${PROJECT_NAME}-analytics"
    echo ""
    echo "Next Steps:"
    echo "1. Confirm your email subscription in SNS"
    echo "2. Run the IoT simulator to test the pipeline"
    echo "3. Monitor the CloudWatch dashboard for metrics"
    echo "4. Check S3 bucket for processed data"
    echo ""
    echo "To test the pipeline:"
    echo "python3 $TEMP_DIR/iot-simulator.py $KINESIS_STREAM_NAME"
    echo ""
    echo "To cleanup resources:"
    echo "$SCRIPT_DIR/destroy.sh --project-name $PROJECT_NAME"
}

# Function to cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    
    if [[ -n "$PROJECT_NAME" ]]; then
        # This would call the destroy script
        "$SCRIPT_DIR/destroy.sh" --project-name "$PROJECT_NAME" --yes --force || true
    fi
}

# Main deployment function
main() {
    log_info "Starting Real-Time IoT Analytics Pipeline Deployment"
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Show configuration
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        set -x
    fi
    
    # Confirm deployment
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        echo "This will deploy the following resources:"
        echo "- Kinesis Data Stream (2 shards)"
        echo "- Lambda Function for data processing"
        echo "- Managed Service for Apache Flink application"
        echo "- S3 bucket for data storage"
        echo "- SNS topic for alerts"
        echo "- CloudWatch alarms and dashboard"
        echo "- IAM roles and policies"
        echo ""
        echo "Estimated monthly cost: \$50-100 (depends on data volume)"
        echo ""
        read -p "Do you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi
    
    # Run deployment steps
    check_prerequisites
    generate_identifiers
    setup_temp_dir
    create_s3_bucket
    create_kinesis_stream
    create_sns_topic
    create_iam_roles
    create_lambda_function
    create_flink_application
    create_monitoring
    create_iot_simulator
    
    if [[ "$DRY_RUN" != "true" ]]; then
        show_deployment_summary
        log_success "Deployment completed successfully!"
    else
        log_info "Dry run completed - no resources were created"
    fi
}

# Run main function
main "$@"