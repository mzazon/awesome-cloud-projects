#!/bin/bash

# AWS IoT Device Management Deployment Script
# This script deploys the complete IoT device management infrastructure
# based on the recipe "IoT Device Registry with IoT Core"

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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check required permissions
    log "Verifying AWS permissions..."
    aws sts get-caller-identity > /dev/null || error "Cannot access AWS STS"
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region found, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export IOT_THING_NAME="temperature-sensor-${RANDOM_SUFFIX}"
    export IOT_POLICY_NAME="device-policy-${RANDOM_SUFFIX}"
    export IOT_RULE_NAME="sensor_data_rule_${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="iot-lambda-role-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="iot-data-processor-${RANDOM_SUFFIX}"
    
    # Create deployment directory
    DEPLOY_DIR="$(pwd)/iot-deployment-${RANDOM_SUFFIX}"
    mkdir -p "$DEPLOY_DIR"
    cd "$DEPLOY_DIR"
    
    # Save environment variables for cleanup
    cat > deployment-vars.env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
IOT_THING_NAME=${IOT_THING_NAME}
IOT_POLICY_NAME=${IOT_POLICY_NAME}
IOT_RULE_NAME=${IOT_RULE_NAME}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
DEPLOY_DIR=${DEPLOY_DIR}
EOF
    
    log "Environment configured:"
    log "  AWS Region: ${AWS_REGION}"
    log "  Account ID: ${AWS_ACCOUNT_ID}"
    log "  IoT Thing: ${IOT_THING_NAME}"
    log "  Deployment Directory: ${DEPLOY_DIR}"
    
    success "Environment setup completed"
}

# Function to create IoT Thing
create_iot_thing() {
    log "Creating IoT Thing in device registry..."
    
    # Create IoT Thing Type first (optional but recommended)
    aws iot create-thing-type \
        --thing-type-name "TemperatureSensor" \
        --thing-type-description "Temperature sensor device type" \
        --thing-type-properties "description=Temperature monitoring sensor" \
        2>/dev/null || warning "Thing type may already exist"
    
    # Create IoT Thing with device attributes
    aws iot create-thing \
        --thing-name "${IOT_THING_NAME}" \
        --thing-type-name "TemperatureSensor" \
        --attribute-payload attributes='{
            "deviceType":"temperature",
            "manufacturer":"SensorCorp",
            "model":"TC-2000",
            "location":"ProductionFloor-A"
        }' > iot-thing-result.json
    
    success "IoT Thing '${IOT_THING_NAME}' created in device registry"
}

# Function to generate device certificates
create_device_certificates() {
    log "Generating device certificate and keys..."
    
    # Create device certificate and private key
    aws iot create-keys-and-certificate \
        --set-as-active \
        --certificate-pem-outfile device-cert.pem \
        --public-key-outfile device-public-key.pem \
        --private-key-outfile device-private-key.pem \
        --query 'certificateArn' --output text > cert-arn.txt
    
    export CERT_ARN=$(cat cert-arn.txt)
    echo "CERT_ARN=${CERT_ARN}" >> deployment-vars.env
    
    success "Device certificate created: ${CERT_ARN}"
}

# Function to create IoT policy
create_iot_policy() {
    log "Creating IoT policy with least privilege permissions..."
    
    # Create IoT policy with restricted permissions
    cat > device-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:Connect",
                "iot:Publish"
            ],
            "Resource": [
                "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:client/\${iot:Connection.Thing.ThingName}",
                "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/sensor/temperature/\${iot:Connection.Thing.ThingName}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:GetThingShadow",
                "iot:UpdateThingShadow"
            ],
            "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thing/\${iot:Connection.Thing.ThingName}"
        }
    ]
}
EOF
    
    aws iot create-policy \
        --policy-name "${IOT_POLICY_NAME}" \
        --policy-document file://device-policy.json
    
    success "IoT policy '${IOT_POLICY_NAME}' created with restricted permissions"
}

# Function to attach policy to certificate
attach_policy_to_certificate() {
    log "Attaching policy to device certificate..."
    
    # Link policy to device certificate
    aws iot attach-policy \
        --policy-name "${IOT_POLICY_NAME}" \
        --target "${CERT_ARN}"
    
    success "Policy attached to device certificate"
}

# Function to associate certificate with IoT Thing
associate_certificate_with_thing() {
    log "Associating certificate with IoT Thing..."
    
    # Connect certificate to IoT Thing
    aws iot attach-thing-principal \
        --thing-name "${IOT_THING_NAME}" \
        --principal "${CERT_ARN}"
    
    success "Certificate associated with IoT Thing"
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function for data processing..."
    
    # Create Lambda execution role trust policy
    cat > lambda-trust-policy.json << EOF
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
    
    # Create IAM role for Lambda
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --description "Role for IoT data processing Lambda function"
    
    # Wait for role to be created
    sleep 5
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create Lambda function code
    cat > lambda-function.py << EOF
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    logger.info(f"Received IoT data: {json.dumps(event)}")
    
    try:
        # Extract device data
        device_name = event.get('device', 'unknown')
        temperature = event.get('temperature', 0)
        timestamp = event.get('timestamp', datetime.utcnow().isoformat())
        
        # Process temperature data
        if temperature > 80:
            logger.warning(f"High temperature alert: {temperature}°C from {device_name}")
            # In production, you could send to SNS, write to DynamoDB, etc.
        elif temperature < 0:
            logger.warning(f"Low temperature alert: {temperature}°C from {device_name}")
        else:
            logger.info(f"Normal temperature reading: {temperature}°C from {device_name}")
        
        # Return success response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data processed successfully',
                'device': device_name,
                'temperature': temperature,
                'timestamp': timestamp,
                'processed_at': datetime.utcnow().isoformat()
            })
        }
    except Exception as e:
        logger.error(f"Error processing IoT data: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Failed to process IoT data',
                'message': str(e)
            })
        }
EOF
    
    # Package Lambda function
    zip lambda-function.zip lambda-function.py
    
    # Wait for IAM role propagation
    log "Waiting for IAM role propagation..."
    sleep 10
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
        --handler lambda-function.lambda_handler \
        --zip-file fileb://lambda-function.zip \
        --description "Process IoT sensor data from temperature devices" \
        --timeout 30 \
        --memory-size 128
    
    success "Lambda function created for IoT data processing"
}

# Function to create IoT rule
create_iot_rule() {
    log "Creating IoT rule for automatic data routing..."
    
    # Create IoT rule for temperature data processing
    cat > iot-rule.json << EOF
{
    "ruleName": "${IOT_RULE_NAME}",
    "topicRulePayload": {
        "sql": "SELECT *, topic(3) as device FROM 'sensor/temperature/+'",
        "description": "Route temperature sensor data to Lambda for processing",
        "actions": [
            {
                "lambda": {
                    "functionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
                }
            }
        ],
        "ruleDisabled": false
    }
}
EOF
    
    # Create the IoT rule
    aws iot create-topic-rule --cli-input-json file://iot-rule.json
    
    # Grant IoT permission to invoke Lambda function
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --statement-id iot-lambda-permission \
        --action lambda:InvokeFunction \
        --principal iot.amazonaws.com \
        --source-arn "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${IOT_RULE_NAME}"
    
    success "IoT rule created to route sensor data to Lambda"
}

# Function to configure device shadow
configure_device_shadow() {
    log "Configuring device shadow for state management..."
    
    # Initialize device shadow with default state
    cat > device-shadow.json << EOF
{
    "state": {
        "desired": {
            "temperature_threshold": 75,
            "reporting_interval": 60,
            "active": true
        },
        "reported": {
            "temperature": 22.5,
            "battery_level": 95,
            "firmware_version": "1.0.0"
        }
    }
}
EOF
    
    # Update device shadow
    aws iot-data update-thing-shadow \
        --thing-name "${IOT_THING_NAME}" \
        --payload file://device-shadow.json \
        shadow-response.json
    
    success "Device shadow initialized with default configuration"
}

# Function to run validation tests
run_validation_tests() {
    log "Running validation tests..."
    
    # Test 1: Verify IoT Thing registration
    log "Testing IoT Thing registration..."
    aws iot describe-thing --thing-name "${IOT_THING_NAME}" > /dev/null
    success "IoT Thing registration verified"
    
    # Test 2: Verify certificate association
    log "Testing certificate association..."
    aws iot list-thing-principals --thing-name "${IOT_THING_NAME}" | grep -q "${CERT_ARN}"
    success "Certificate association verified"
    
    # Test 3: Verify IoT rule configuration
    log "Testing IoT rule configuration..."
    aws iot get-topic-rule --rule-name "${IOT_RULE_NAME}" > /dev/null
    success "IoT rule configuration verified"
    
    # Test 4: Test Lambda function
    log "Testing Lambda function..."
    aws lambda invoke \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --payload '{"temperature": 25.5, "device": "'${IOT_THING_NAME}'", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'"}' \
        lambda-test-response.json > /dev/null
    success "Lambda function test completed"
    
    # Test 5: Simulate device data publishing
    log "Testing device data publishing..."
    aws iot-data publish \
        --topic "sensor/temperature/${IOT_THING_NAME}" \
        --payload '{"temperature": 85.5, "humidity": 65, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)'", "device": "'${IOT_THING_NAME}'"}'
    success "Test message published to IoT topic"
    
    success "All validation tests passed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo ""
    echo "📊 Resources Created:"
    echo "  • IoT Thing: ${IOT_THING_NAME}"
    echo "  • IoT Policy: ${IOT_POLICY_NAME}"
    echo "  • Device Certificate: ${CERT_ARN}"
    echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  • IoT Rule: ${IOT_RULE_NAME}"
    echo "  • IAM Role: ${LAMBDA_ROLE_NAME}"
    echo ""
    echo "📁 Deployment Files Location: ${DEPLOY_DIR}"
    echo ""
    echo "🔐 Device Connection Details:"
    echo "  • Certificate: device-cert.pem"
    echo "  • Private Key: device-private-key.pem"
    echo "  • IoT Endpoint: $(aws iot describe-endpoint --endpoint-type iot:Data-ATS --query endpointAddress --output text)"
    echo ""
    echo "📡 Test Publishing Command:"
    echo "  aws iot-data publish \\"
    echo "    --topic sensor/temperature/${IOT_THING_NAME} \\"
    echo "    --payload '{\"temperature\": 23.5, \"device\": \"${IOT_THING_NAME}\", \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\"}'"
    echo ""
    echo "🧹 Cleanup Command:"
    echo "  Run the destroy.sh script from: ${DEPLOY_DIR}"
    echo ""
    success "IoT Device Management infrastructure deployed successfully!"
}

# Main deployment function
main() {
    log "Starting AWS IoT Device Management deployment..."
    
    check_prerequisites
    setup_environment
    create_iot_thing
    create_device_certificates
    create_iot_policy
    attach_policy_to_certificate
    associate_certificate_with_thing
    create_lambda_function
    create_iot_rule
    configure_device_shadow
    run_validation_tests
    display_summary
    
    log "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted. You may need to run cleanup manually."' INT TERM

# Run main function
main "$@"