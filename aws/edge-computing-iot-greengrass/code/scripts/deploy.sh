#!/bin/bash

# AWS IoT Greengrass Edge Computing Deployment Script
# This script deploys the complete IoT Greengrass infrastructure for edge computing

set -euo pipefail

# Color codes for output
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
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${timestamp} - ${message}"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - ${message}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${timestamp} - ${message}"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - ${message}"
            ;;
    esac
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    cleanup_on_error
    exit 1
}

# Cleanup function for errors
cleanup_on_error() {
    log "WARN" "Deployment failed. Cleaning up partially created resources..."
    
    # Remove temporary files
    rm -f greengrass-policy.json greengrass-trust-policy.json
    rm -f stream-manager-config.json lambda-component-recipe.yaml
    rm -f greengrass-config.yaml edge-processor.zip
    rm -rf lambda-edge-function GreengrassCore
    
    log "INFO" "Temporary files cleaned up"
}

# Trap errors
trap 'error_exit "Script failed at line $LINENO"' ERR

# Prerequisites check
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check required tools
    local required_tools=("curl" "unzip" "zip" "python3")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "$tool is required but not installed."
        fi
    done
    
    # Check Python version
    local python_version=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
    if [[ $(echo "$python_version 3.7" | awk '{print ($1 >= $2)}') != 1 ]]; then
        error_exit "Python 3.7 or higher is required. Current version: $python_version"
    fi
    
    log "INFO" "Prerequisites check passed"
}

# Initialize environment variables
initialize_environment() {
    log "INFO" "Initializing environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        error_exit "AWS region not configured. Please set default region."
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        error_exit "Could not determine AWS account ID."
    fi
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export THING_NAME="greengrass-core-${RANDOM_SUFFIX}"
    export THING_GROUP_NAME="greengrass-things-${RANDOM_SUFFIX}"
    export CORE_DEVICE_NAME="greengrass-core-${RANDOM_SUFFIX}"
    export POLICY_NAME="greengrass-policy-${RANDOM_SUFFIX}"
    export ROLE_NAME="greengrass-core-role-${RANDOM_SUFFIX}"
    export LAMBDA_NAME="edge-processor-${RANDOM_SUFFIX}"
    
    # Store variables for cleanup script
    cat > .env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
THING_NAME=${THING_NAME}
THING_GROUP_NAME=${THING_GROUP_NAME}
CORE_DEVICE_NAME=${CORE_DEVICE_NAME}
POLICY_NAME=${POLICY_NAME}
ROLE_NAME=${ROLE_NAME}
LAMBDA_NAME=${LAMBDA_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log "INFO" "Environment initialized successfully"
    log "INFO" "Core device name: ${CORE_DEVICE_NAME}"
    log "INFO" "AWS Region: ${AWS_REGION}"
    log "INFO" "AWS Account ID: ${AWS_ACCOUNT_ID}"
}

# Create IoT Thing and Certificate
create_iot_thing() {
    log "INFO" "Creating IoT Thing and Certificate..."
    
    # Create IoT Thing
    aws iot create-thing --thing-name "${THING_NAME}" || \
        error_exit "Failed to create IoT Thing: ${THING_NAME}"
    
    # Create certificate and keys
    local cert_response=$(aws iot create-keys-and-certificate \
        --set-as-active \
        --output json) || \
        error_exit "Failed to create certificate"
    
    export CERT_ARN=$(echo "$cert_response" | jq -r '.certificateArn')
    export CERT_ID=$(echo "$cert_response" | jq -r '.certificateId')
    
    # Save certificate details for cleanup
    echo "CERT_ARN=${CERT_ARN}" >> .env
    echo "CERT_ID=${CERT_ID}" >> .env
    
    log "INFO" "IoT Thing created: ${THING_NAME}"
    log "INFO" "Certificate created: ${CERT_ID}"
}

# Create and attach IoT policy
create_iot_policy() {
    log "INFO" "Creating IoT Policy..."
    
    # Create policy document
    cat > greengrass-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:Publish",
                "iot:Subscribe",
                "iot:Receive",
                "iot:Connect"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "greengrass:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create policy
    aws iot create-policy \
        --policy-name "${POLICY_NAME}" \
        --policy-document file://greengrass-policy.json || \
        error_exit "Failed to create IoT policy"
    
    # Attach policy to certificate
    aws iot attach-policy \
        --policy-name "${POLICY_NAME}" \
        --target "${CERT_ARN}" || \
        error_exit "Failed to attach policy to certificate"
    
    log "INFO" "IoT policy created and attached: ${POLICY_NAME}"
}

# Create Thing Group
create_thing_group() {
    log "INFO" "Creating Thing Group..."
    
    # Create Thing Group
    aws iot create-thing-group \
        --thing-group-name "${THING_GROUP_NAME}" \
        --thing-group-properties '{
            "thingGroupDescription": "Greengrass core devices group",
            "attributePayload": {
                "attributes": {
                    "environment": "development",
                    "purpose": "edge-computing"
                }
            }
        }' || error_exit "Failed to create Thing Group"
    
    # Add Thing to group
    aws iot add-thing-to-thing-group \
        --thing-group-name "${THING_GROUP_NAME}" \
        --thing-name "${THING_NAME}" || \
        error_exit "Failed to add Thing to group"
    
    log "INFO" "Thing Group created: ${THING_GROUP_NAME}"
}

# Create IAM role for Greengrass
create_iam_role() {
    log "INFO" "Creating IAM Role for Greengrass..."
    
    # Create trust policy
    cat > greengrass-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "credentials.iot.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file://greengrass-trust-policy.json || \
        error_exit "Failed to create IAM role"
    
    # Attach required policies
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSGreengrassResourceAccessRolePolicy || \
        error_exit "Failed to attach policy to role"
    
    log "INFO" "IAM role created: ${ROLE_NAME}"
}

# Create Lambda function
create_lambda_function() {
    log "INFO" "Creating Lambda function for edge processing..."
    
    # Create Lambda function directory
    mkdir -p lambda-edge-function
    
    # Create Lambda function code
    cat > lambda-edge-function/lambda_function.py << 'EOF'
import json
import logging
import time

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process sensor data at the edge
    """
    logger.info(f"Processing edge data: {event}")
    
    # Simulate sensor data processing
    processed_data = {
        "timestamp": int(time.time()),
        "device_id": event.get("device_id", "unknown"),
        "temperature": event.get("temperature", 0),
        "status": "processed_at_edge",
        "processing_time": 0.1
    }
    
    return {
        "statusCode": 200,
        "body": json.dumps(processed_data)
    }
EOF
    
    # Create deployment package
    cd lambda-edge-function
    zip -r ../edge-processor.zip . || error_exit "Failed to create Lambda deployment package"
    cd ..
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "${LAMBDA_NAME}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://edge-processor.zip \
        --timeout 30 \
        --memory-size 128 || \
        error_exit "Failed to create Lambda function"
    
    log "INFO" "Lambda function created: ${LAMBDA_NAME}"
}

# Download and prepare Greengrass Core
prepare_greengrass_core() {
    log "INFO" "Downloading and preparing Greengrass Core software..."
    
    # Download Greengrass Core V2
    curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip \
        -o greengrass-nucleus-latest.zip || \
        error_exit "Failed to download Greengrass Core"
    
    # Extract Greengrass Core
    unzip -q greengrass-nucleus-latest.zip -d GreengrassCore || \
        error_exit "Failed to extract Greengrass Core"
    
    # Get IoT endpoints
    local iot_data_endpoint=$(aws iot describe-endpoint \
        --endpoint-type iot:Data-ATS \
        --query endpointAddress \
        --output text) || \
        error_exit "Failed to get IoT data endpoint"
    
    local iot_cred_endpoint=$(aws iot describe-endpoint \
        --endpoint-type iot:CredentialProvider \
        --query endpointAddress \
        --output text) || \
        error_exit "Failed to get IoT credential endpoint"
    
    # Create configuration file
    cat > greengrass-config.yaml << EOF
---
system:
  certificateFilePath: "/greengrass/v2/device.pem.crt"
  privateKeyPath: "/greengrass/v2/private.pem.key"
  rootCaPath: "/greengrass/v2/AmazonRootCA1.pem"
  thingName: "${THING_NAME}"
services:
  aws.greengrass.Nucleus:
    componentType: "NUCLEUS"
    version: "2.0.0"
    configuration:
      awsRegion: "${AWS_REGION}"
      iotRoleAlias: "GreengrassV2TokenExchangeRoleAlias"
      iotDataEndpoint: "${iot_data_endpoint}"
      iotCredEndpoint: "${iot_cred_endpoint}"
EOF
    
    log "INFO" "Greengrass Core software prepared"
}

# Create Stream Manager configuration
create_stream_manager() {
    log "INFO" "Creating Stream Manager configuration..."
    
    cat > stream-manager-config.json << 'EOF'
{
    "streams": [
        {
            "name": "sensor-data-stream",
            "maxSize": 1000,
            "streamSegmentSize": 100,
            "timeToLiveMillis": 3600000,
            "strategyOnFull": "OverwriteOldestData",
            "exportDefinition": {
                "kinesis": [
                    {
                        "identifier": "sensor-data-export",
                        "kinesisStreamName": "sensor-data-stream",
                        "batchSize": 10,
                        "batchIntervalMillis": 5000
                    }
                ]
            }
        }
    ]
}
EOF
    
    log "INFO" "Stream Manager configuration created"
}

# Deploy components to Greengrass
deploy_components() {
    log "INFO" "Deploying components to Greengrass..."
    
    # Wait for role to be ready
    log "INFO" "Waiting for IAM role to be ready..."
    sleep 30
    
    # Create initial deployment with Nucleus
    local deployment_id=$(aws greengrassv2 create-deployment \
        --target-arn "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thinggroup/${THING_GROUP_NAME}" \
        --deployment-name "initial-deployment-${RANDOM_SUFFIX}" \
        --components '{
            "aws.greengrass.Nucleus": {
                "componentVersion": "2.0.0"
            }
        }' \
        --query 'deploymentId' \
        --output text) || \
        error_exit "Failed to create initial deployment"
    
    echo "DEPLOYMENT_ID=${deployment_id}" >> .env
    
    log "INFO" "Initial deployment created: ${deployment_id}"
    
    # Wait for deployment to complete
    log "INFO" "Waiting for deployment to complete..."
    local max_wait=300
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        local status=$(aws greengrassv2 get-deployment \
            --deployment-id "${deployment_id}" \
            --query 'deploymentStatus' \
            --output text)
        
        if [[ "$status" == "COMPLETED" ]]; then
            log "INFO" "Deployment completed successfully"
            break
        elif [[ "$status" == "FAILED" ]]; then
            error_exit "Deployment failed"
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    if [[ $wait_time -ge $max_wait ]]; then
        log "WARN" "Deployment status check timed out"
    fi
}

# Validate deployment
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    # Check if Lambda function exists
    if aws lambda get-function --function-name "${LAMBDA_NAME}" &>/dev/null; then
        log "INFO" "Lambda function validation passed"
    else
        log "WARN" "Lambda function validation failed"
    fi
    
    # Check if IoT Thing exists
    if aws iot describe-thing --thing-name "${THING_NAME}" &>/dev/null; then
        log "INFO" "IoT Thing validation passed"
    else
        log "WARN" "IoT Thing validation failed"
    fi
    
    # Check if Thing Group exists
    if aws iot describe-thing-group --thing-group-name "${THING_GROUP_NAME}" &>/dev/null; then
        log "INFO" "Thing Group validation passed"
    else
        log "WARN" "Thing Group validation failed"
    fi
    
    # Check if IAM role exists
    if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
        log "INFO" "IAM role validation passed"
    else
        log "WARN" "IAM role validation failed"
    fi
}

# Main deployment function
main() {
    log "INFO" "Starting AWS IoT Greengrass deployment..."
    
    # Check if already deployed
    if [[ -f .env ]]; then
        log "WARN" "Deployment environment file exists. Run destroy.sh first to clean up."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "Deployment cancelled"
            exit 0
        fi
    fi
    
    check_prerequisites
    initialize_environment
    create_iot_thing
    create_iot_policy
    create_thing_group
    create_iam_role
    create_lambda_function
    prepare_greengrass_core
    create_stream_manager
    deploy_components
    validate_deployment
    
    # Clean up temporary files
    rm -f greengrass-policy.json greengrass-trust-policy.json
    rm -f stream-manager-config.json lambda-component-recipe.yaml
    rm -f greengrass-config.yaml edge-processor.zip
    rm -rf lambda-edge-function
    
    log "INFO" "Deployment completed successfully!"
    log "INFO" "Environment variables saved to .env file"
    log "INFO" "To clean up resources, run: ./destroy.sh"
    
    # Display summary
    echo
    echo "=================================="
    echo "Deployment Summary"
    echo "=================================="
    echo "Thing Name: ${THING_NAME}"
    echo "Thing Group: ${THING_GROUP_NAME}"
    echo "Lambda Function: ${LAMBDA_NAME}"
    echo "IAM Role: ${ROLE_NAME}"
    echo "Policy Name: ${POLICY_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo "=================================="
}

# Run main function
main "$@"