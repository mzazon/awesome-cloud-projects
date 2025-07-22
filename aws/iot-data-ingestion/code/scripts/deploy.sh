#!/bin/bash

# AWS IoT Data Ingestion Pipeline Deployment Script
# This script deploys IoT Core, Lambda, DynamoDB, and SNS resources for sensor data processing

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check if AWS CLI is installed and configured
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install and configure it first."
        exit 1
    fi
    
    # Check if AWS is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required commands
    local required_commands=("curl" "jq" "zip")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command '$cmd' is not installed."
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export IOT_THING_NAME="sensor-device-${RANDOM_SUFFIX}"
    export IOT_POLICY_NAME="SensorPolicy-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="iot-processor-${RANDOM_SUFFIX}"
    export DYNAMODB_TABLE_NAME="SensorData-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="IoTProcessorRole-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="IoTAlerts-${RANDOM_SUFFIX}"
    export IOT_RULE_NAME="ProcessSensorData-${RANDOM_SUFFIX}"
    
    # Save variables to file for cleanup script
    cat > deployment_vars.txt << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
IOT_THING_NAME=${IOT_THING_NAME}
IOT_POLICY_NAME=${IOT_POLICY_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
DYNAMODB_TABLE_NAME=${DYNAMODB_TABLE_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
IOT_RULE_NAME=${IOT_RULE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables configured"
    log_info "Using suffix: ${RANDOM_SUFFIX}"
}

# Function to create IoT Thing and security credentials
create_iot_resources() {
    log_info "Creating IoT Thing and security credentials..."
    
    # Create IoT Thing Type (optional but recommended)
    aws iot create-thing-type \
        --thing-type-name "SensorDevice" \
        --thing-type-description "Temperature and humidity sensor device" || true
    
    # Create IoT Thing
    aws iot create-thing \
        --thing-name "$IOT_THING_NAME" \
        --thing-type-name "SensorDevice"
    
    # Create certificate and keys
    local cert_response
    cert_response=$(aws iot create-keys-and-certificate \
        --set-as-active \
        --certificate-pem-outfile device-cert.pem \
        --public-key-outfile device-public.key \
        --private-key-outfile device-private.key)
    
    export CERT_ARN=$(echo "$cert_response" | jq -r '.certificateArn')
    export CERT_ID=$(echo "$cert_response" | jq -r '.certificateId')
    
    # Save certificate info
    echo "CERT_ARN=${CERT_ARN}" >> deployment_vars.txt
    echo "CERT_ID=${CERT_ID}" >> deployment_vars.txt
    
    # Download Amazon Root CA certificate
    curl -s -o amazon-root-ca.pem \
        https://www.amazontrust.com/repository/AmazonRootCA1.pem
    
    # Create IoT policy
    cat > iot-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:Connect"
            ],
            "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:client/${IOT_THING_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:Publish",
                "iot:Subscribe",
                "iot:Receive"
            ],
            "Resource": [
                "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/sensor/*",
                "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topicfilter/sensor/*"
            ]
        }
    ]
}
EOF
    
    aws iot create-policy \
        --policy-name "$IOT_POLICY_NAME" \
        --policy-document file://iot-policy.json
    
    # Attach policy and certificate to thing
    aws iot attach-thing-principal \
        --thing-name "$IOT_THING_NAME" \
        --principal "$CERT_ARN"
    
    aws iot attach-principal-policy \
        --policy-name "$IOT_POLICY_NAME" \
        --principal "$CERT_ARN"
    
    log_success "IoT Thing and credentials created successfully"
}

# Function to create DynamoDB table
create_dynamodb_table() {
    log_info "Creating DynamoDB table for sensor data..."
    
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE_NAME" \
        --attribute-definitions \
            AttributeName=deviceId,AttributeType=S \
            AttributeName=timestamp,AttributeType=N \
        --key-schema \
            AttributeName=deviceId,KeyType=HASH \
            AttributeName=timestamp,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Purpose,Value=IoTDataIngestion Key=CreatedBy,Value=DeploymentScript
    
    # Wait for table to be active
    log_info "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE_NAME"
    
    log_success "DynamoDB table created and active"
}

# Function to create SNS topic
create_sns_topic() {
    log_info "Creating SNS topic for alerts..."
    
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query 'TopicArn' --output text)
    
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> deployment_vars.txt
    
    log_success "SNS topic created: ${SNS_TOPIC_ARN}"
}

# Function to create IAM role for Lambda
create_iam_role() {
    log_info "Creating IAM role for Lambda function..."
    
    # Create trust policy
    cat > lambda-trust-policy.json << 'EOF'
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
    
    export LAMBDA_ROLE_ARN=$(aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --query 'Role.Arn' --output text)
    
    echo "LAMBDA_ROLE_ARN=${LAMBDA_ROLE_ARN}" >> deployment_vars.txt
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for DynamoDB, CloudWatch, and SNS
    cat > lambda-permissions.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DYNAMODB_TABLE_NAME}"
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
            "Resource": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name IoTProcessorPolicy \
        --policy-document file://lambda-permissions.json
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 15
    
    log_success "IAM role created and configured"
}

# Function to create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function for IoT data processing..."
    
    # Create Lambda function directory
    mkdir -p iot-processor
    cd iot-processor
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Parse IoT message
        device_id = event.get('deviceId')
        timestamp = event.get('timestamp', int(datetime.now().timestamp()))
        temperature = event.get('temperature')
        humidity = event.get('humidity')
        
        logger.info(f"Processing data from device: {device_id}")
        
        # Validate required fields
        if not all([device_id, temperature, humidity]):
            logger.error("Missing required fields in IoT message")
            return {
                'statusCode': 400,
                'body': json.dumps('Missing required fields')
            }
        
        # Store data in DynamoDB
        table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
        table.put_item(
            Item={
                'deviceId': device_id,
                'timestamp': timestamp,
                'temperature': float(temperature),
                'humidity': float(humidity),
                'processed_at': int(datetime.now().timestamp())
            }
        )
        
        # Send custom metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='IoT/Sensors',
            MetricData=[
                {
                    'MetricName': 'Temperature',
                    'Dimensions': [
                        {'Name': 'DeviceId', 'Value': device_id}
                    ],
                    'Value': float(temperature),
                    'Unit': 'None'
                },
                {
                    'MetricName': 'Humidity',
                    'Dimensions': [
                        {'Name': 'DeviceId', 'Value': device_id}
                    ],
                    'Value': float(humidity),
                    'Unit': 'Percent'
                }
            ]
        )
        
        # Check for alerts (temperature > 30°C)
        if float(temperature) > 30:
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject=f'High Temperature Alert - Device {device_id}',
                Message=f'Temperature reading of {temperature}°C exceeds threshold of 30°C'
            )
            logger.info(f"High temperature alert sent for device {device_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Data processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing IoT data: {str(e)}")
        raise
EOF
    
    # Package Lambda function
    zip -q -r iot-processor.zip lambda_function.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://iot-processor.zip \
        --environment Variables="{DYNAMODB_TABLE=${DYNAMODB_TABLE_NAME},SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}" \
        --timeout 60 \
        --description "Processes IoT sensor data and stores in DynamoDB"
    
    cd ..
    
    log_success "Lambda function created successfully"
}

# Function to configure IoT Rules Engine
configure_iot_rules() {
    log_info "Configuring IoT Rules Engine..."
    
    # Create IoT rule to route sensor data to Lambda
    cat > iot-rule.json << EOF
{
    "ruleName": "${IOT_RULE_NAME}",
    "sql": "SELECT * FROM 'topic/sensor/data'",
    "description": "Route sensor data to Lambda for processing",
    "ruleDisabled": false,
    "actions": [
        {
            "lambda": {
                "functionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
            }
        }
    ]
}
EOF
    
    aws iot create-topic-rule \
        --rule-name "$IOT_RULE_NAME" \
        --topic-rule-payload file://iot-rule.json
    
    # Grant IoT permission to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --principal iot.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id iot-invoke \
        --source-arn "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${IOT_RULE_NAME}"
    
    log_success "IoT Rules Engine configured successfully"
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Get IoT endpoint
    export IOT_ENDPOINT=$(aws iot describe-endpoint \
        --endpoint-type iot:Data-ATS \
        --query 'endpointAddress' --output text)
    
    echo "IOT_ENDPOINT=${IOT_ENDPOINT}" >> deployment_vars.txt
    
    # Publish test message
    log_info "Publishing test message to verify connectivity..."
    aws iot-data publish \
        --topic "topic/sensor/data" \
        --payload "{
            \"deviceId\": \"${IOT_THING_NAME}\",
            \"timestamp\": $(date +%s),
            \"temperature\": 25.5,
            \"humidity\": 60.2,
            \"location\": \"sensor-room-1\"
        }"
    
    # Wait a moment for processing
    sleep 5
    
    # Check if data was stored in DynamoDB
    local item_count
    item_count=$(aws dynamodb scan \
        --table-name "$DYNAMODB_TABLE_NAME" \
        --query 'Count' --output text)
    
    if [[ "$item_count" -gt 0 ]]; then
        log_success "Test data successfully processed and stored"
    else
        log_warning "Test data not found in DynamoDB - check Lambda logs"
    fi
    
    log_success "Deployment verification completed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "=================="
    echo "IoT Thing Name: ${IOT_THING_NAME}"
    echo "IoT Endpoint: ${IOT_ENDPOINT}"
    echo "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "DynamoDB Table: ${DYNAMODB_TABLE_NAME}"
    echo "SNS Topic: ${SNS_TOPIC_ARN}"
    echo "IoT Rule: ${IOT_RULE_NAME}"
    echo ""
    echo "Certificate files created:"
    echo "- device-cert.pem"
    echo "- device-private.key"
    echo "- device-public.key"
    echo "- amazon-root-ca.pem"
    echo ""
    echo "To test with a real device, use the IoT endpoint and certificate files."
    echo "Deployment variables saved to: deployment_vars.txt"
    echo ""
    log_success "IoT Data Ingestion Pipeline deployed successfully!"
}

# Cleanup function for errors
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partial resources..."
    if [[ -f deployment_vars.txt ]]; then
        source deployment_vars.txt
        ./destroy.sh --force 2>/dev/null || true
    fi
}

# Trap errors and cleanup
trap cleanup_on_error ERR

# Main deployment flow
main() {
    log_info "Starting AWS IoT Data Ingestion Pipeline deployment..."
    
    check_prerequisites
    setup_environment
    create_iot_resources
    create_dynamodb_table
    create_sns_topic
    create_iam_role
    create_lambda_function
    configure_iot_rules
    verify_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
    exit 0
}

# Help function
show_help() {
    echo "AWS IoT Data Ingestion Pipeline Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --dry-run      Show what would be deployed without creating resources"
    echo ""
    echo "This script deploys a complete IoT data ingestion pipeline including:"
    echo "- AWS IoT Core (Thing, Policy, Certificates)"
    echo "- DynamoDB table for sensor data"
    echo "- Lambda function for data processing"
    echo "- SNS topic for alerts"
    echo "- IoT Rules Engine configuration"
    echo ""
    echo "Prerequisites:"
    echo "- AWS CLI installed and configured"
    echo "- jq, curl, and zip commands available"
    echo "- Appropriate AWS permissions"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --dry-run)
            log_info "Dry run mode - would deploy IoT pipeline but not creating resources"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main "$@"