#!/bin/bash

# IoT Device Provisioning and Certificate Management - Deployment Script
# This script deploys the complete IoT device provisioning solution with security best practices
# Based on the recipe: IoT Device Provisioning and Certificate Management

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_ID="iot-provisioning-$(date +%Y%m%d-%H%M%S)"
RESOURCE_PREFIX="iot-provisioning"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it before running this script."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if required services are available in region
    local region=$(aws configure get region)
    if [ -z "$region" ]; then
        error "AWS region not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "Prerequisites check passed"
    log "AWS Region: $region"
    log "AWS Account: $(aws sts get-caller-identity --query Account --output text)"
    log "Deployment ID: $DEPLOYMENT_ID"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Core AWS environment
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Export resource names
    export TEMPLATE_NAME="device-provisioning-template-${random_suffix}"
    export HOOK_FUNCTION_NAME="device-provisioning-hook-${random_suffix}"
    export DEVICE_REGISTRY_TABLE="device-registry-${random_suffix}"
    export IOT_ROLE_NAME="iot-provisioning-role-${random_suffix}"
    export THING_GROUP_NAME="provisioned-devices-${random_suffix}"
    export SHADOW_INIT_FUNCTION_NAME="device-shadow-initializer-${random_suffix}"
    
    # Create deployment state file
    cat > "/tmp/iot-provisioning-deployment.env" << EOF
# IoT Provisioning Deployment Configuration
# Generated: $(date)
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
TEMPLATE_NAME=${TEMPLATE_NAME}
HOOK_FUNCTION_NAME=${HOOK_FUNCTION_NAME}
DEVICE_REGISTRY_TABLE=${DEVICE_REGISTRY_TABLE}
IOT_ROLE_NAME=${IOT_ROLE_NAME}
THING_GROUP_NAME=${THING_GROUP_NAME}
SHADOW_INIT_FUNCTION_NAME=${SHADOW_INIT_FUNCTION_NAME}
DEPLOYMENT_ID=${DEPLOYMENT_ID}
EOF
    
    log "Environment variables configured"
    log "Configuration saved to: /tmp/iot-provisioning-deployment.env"
}

# Deploy DynamoDB table for device registry
deploy_device_registry() {
    log "Creating DynamoDB table for device registry..."
    
    # Create DynamoDB table
    aws dynamodb create-table \
        --table-name "$DEVICE_REGISTRY_TABLE" \
        --attribute-definitions \
            AttributeName=serialNumber,AttributeType=S \
            AttributeName=deviceType,AttributeType=S \
        --key-schema \
            AttributeName=serialNumber,KeyType=HASH \
        --global-secondary-indexes \
            IndexName=DeviceTypeIndex,KeySchema='[{AttributeName=deviceType,KeyType=HASH}]',Projection='{ProjectionType=ALL}',ProvisionedThroughput='{ReadCapacityUnits=5,WriteCapacityUnits=5}' \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value=IoTProvisioning Key=DeploymentId,Value="$DEPLOYMENT_ID"
    
    # Wait for table to be active
    log "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists --table-name "$DEVICE_REGISTRY_TABLE"
    
    log "DynamoDB table created successfully: $DEVICE_REGISTRY_TABLE"
}

# Create IAM roles and policies
create_iam_resources() {
    log "Creating IAM roles and policies..."
    
    # Create IoT provisioning role trust policy
    cat > "/tmp/iot-provisioning-trust-policy.json" << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "iot.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IoT provisioning role
    aws iam create-role \
        --role-name "$IOT_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/iot-provisioning-trust-policy.json \
        --tags Key=Project,Value=IoTProvisioning Key=DeploymentId,Value="$DEPLOYMENT_ID"
    
    # Create Lambda execution role trust policy
    cat > "/tmp/lambda-trust-policy.json" << 'EOF'
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
    
    # Create Lambda execution role
    aws iam create-role \
        --role-name "${HOOK_FUNCTION_NAME}-execution-role" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --tags Key=Project,Value=IoTProvisioning Key=DeploymentId,Value="$DEPLOYMENT_ID"
    
    # Create Lambda policy
    cat > "/tmp/lambda-policy.json" << EOF
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
            "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DEVICE_REGISTRY_TABLE}*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:DescribeThing",
                "iot:ListThingTypes"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:UpdateThingShadow",
                "iot:GetThingShadow"
            ],
            "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thing/*"
        }
    ]
}
EOF
    
    # Create and attach Lambda policy
    aws iam create-policy \
        --policy-name "${HOOK_FUNCTION_NAME}-policy" \
        --policy-document file:///tmp/lambda-policy.json \
        --tags Key=Project,Value=IoTProvisioning Key=DeploymentId,Value="$DEPLOYMENT_ID"
    
    aws iam attach-role-policy \
        --role-name "${HOOK_FUNCTION_NAME}-execution-role" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${HOOK_FUNCTION_NAME}-policy"
    
    # Create IoT provisioning policy
    cat > "/tmp/iot-provisioning-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:CreateThing",
                "iot:DescribeThing",
                "iot:CreateKeysAndCertificate",
                "iot:AttachThingPrincipal",
                "iot:AttachPolicy",
                "iot:AddThingToThingGroup",
                "iot:UpdateThingShadow"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "lambda:InvokeFunction"
            ],
            "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${HOOK_FUNCTION_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/iot/provisioning:*"
        }
    ]
}
EOF
    
    # Create and attach IoT provisioning policy
    aws iam create-policy \
        --policy-name "${IOT_ROLE_NAME}-policy" \
        --policy-document file:///tmp/iot-provisioning-policy.json \
        --tags Key=Project,Value=IoTProvisioning Key=DeploymentId,Value="$DEPLOYMENT_ID"
    
    aws iam attach-role-policy \
        --role-name "$IOT_ROLE_NAME" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${IOT_ROLE_NAME}-policy"
    
    # Wait for IAM roles to be ready
    log "Waiting for IAM roles to be ready..."
    sleep 10
    
    log "IAM resources created successfully"
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create working directory
    mkdir -p "/tmp/lambda-functions"
    
    # Create pre-provisioning hook function
    cat > "/tmp/lambda-functions/lambda_function.py" << EOF
import json
import boto3
import logging
import os
from datetime import datetime, timezone

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
iot = boto3.client('iot')

def lambda_handler(event, context):
    """
    Pre-provisioning hook to validate and authorize device provisioning
    """
    try:
        # Extract device information from provisioning request
        certificate_pem = event.get('certificatePem', '')
        template_arn = event.get('templateArn', '')
        parameters = event.get('parameters', {})
        
        serial_number = parameters.get('SerialNumber', '')
        device_type = parameters.get('DeviceType', '')
        firmware_version = parameters.get('FirmwareVersion', '')
        manufacturer = parameters.get('Manufacturer', '')
        
        logger.info(f"Processing provisioning request for device: {serial_number}")
        
        # Validate required parameters
        if not all([serial_number, device_type, manufacturer]):
            return create_response(False, "Missing required device parameters")
        
        # Validate device type
        valid_device_types = ['temperature-sensor', 'humidity-sensor', 'pressure-sensor', 'gateway']
        if device_type not in valid_device_types:
            return create_response(False, f"Invalid device type: {device_type}")
        
        # Check if device is already registered
        table_name = os.environ.get('DEVICE_REGISTRY_TABLE', '${DEVICE_REGISTRY_TABLE}')
        table = dynamodb.Table(table_name)
        
        try:
            response = table.get_item(Key={'serialNumber': serial_number})
            if 'Item' in response:
                existing_status = response['Item'].get('status', '')
                if existing_status == 'provisioned':
                    return create_response(False, "Device already provisioned")
                elif existing_status == 'revoked':
                    return create_response(False, "Device has been revoked")
        except Exception as e:
            logger.error(f"Error checking device registry: {str(e)}")
        
        # Validate firmware version (basic check)
        if firmware_version and not firmware_version.startswith('v'):
            return create_response(False, "Invalid firmware version format")
        
        # Store device information in registry
        try:
            device_item = {
                'serialNumber': serial_number,
                'deviceType': device_type,
                'manufacturer': manufacturer,
                'firmwareVersion': firmware_version,
                'status': 'provisioning',
                'provisioningTimestamp': datetime.now(timezone.utc).isoformat(),
                'templateArn': template_arn
            }
            
            table.put_item(Item=device_item)
            logger.info(f"Device {serial_number} registered in device registry")
            
        except Exception as e:
            logger.error(f"Error storing device in registry: {str(e)}")
            return create_response(False, "Failed to register device")
        
        # Determine thing group based on device type
        thing_group = f"{device_type}-devices"
        
        # Create response with device-specific parameters
        response_parameters = {
            'ThingName': f"{device_type}-{serial_number}",
            'ThingGroupName': thing_group,
            'DeviceLocation': parameters.get('Location', 'unknown'),
            'ProvisioningTime': datetime.now(timezone.utc).isoformat()
        }
        
        return create_response(True, "Device validation successful", response_parameters)
        
    except Exception as e:
        logger.error(f"Unexpected error in provisioning hook: {str(e)}")
        return create_response(False, "Internal provisioning error")

def create_response(allow_provisioning, message, parameters=None):
    """Create standardized response for provisioning hook"""
    response = {
        'allowProvisioning': allow_provisioning,
        'message': message
    }
    
    if parameters:
        response['parameters'] = parameters
    
    logger.info(f"Provisioning response: {response}")
    return response
EOF
    
    # Create deployment package
    cd "/tmp/lambda-functions"
    zip -r "provisioning-hook.zip" "lambda_function.py"
    
    # Deploy pre-provisioning hook function
    aws lambda create-function \
        --function-name "$HOOK_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${HOOK_FUNCTION_NAME}-execution-role" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://provisioning-hook.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{DEVICE_REGISTRY_TABLE=${DEVICE_REGISTRY_TABLE}}" \
        --tags Project=IoTProvisioning,DeploymentId="$DEPLOYMENT_ID"
    
    # Create shadow initialization function
    cat > "/tmp/lambda-functions/shadow_init.py" << 'EOF'
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iot_data = boto3.client('iot-data')

def lambda_handler(event, context):
    """Initialize device shadow after successful provisioning"""
    try:
        # Extract thing name from the event
        thing_name = event.get('thingName', '')
        device_type = event.get('deviceType', '')
        
        if not thing_name:
            logger.error("Thing name not provided in event")
            return {'statusCode': 400, 'body': 'Thing name required'}
        
        # Create initial shadow document based on device type
        if device_type == 'temperature-sensor':
            initial_shadow = {
                "state": {
                    "desired": {
                        "samplingRate": 30,
                        "temperatureUnit": "celsius",
                        "alertThreshold": 80,
                        "enabled": True
                    }
                }
            }
        elif device_type == 'gateway':
            initial_shadow = {
                "state": {
                    "desired": {
                        "connectionTimeout": 30,
                        "bufferSize": 100,
                        "compressionEnabled": True,
                        "logLevel": "INFO"
                    }
                }
            }
        else:
            initial_shadow = {
                "state": {
                    "desired": {
                        "enabled": True,
                        "reportingInterval": 60
                    }
                }
            }
        
        # Update device shadow
        iot_data.update_thing_shadow(
            thingName=thing_name,
            payload=json.dumps(initial_shadow)
        )
        
        logger.info(f"Initialized shadow for device: {thing_name}")
        return {
            'statusCode': 200,
            'body': json.dumps(f'Shadow initialized for {thing_name}')
        }
        
    except Exception as e:
        logger.error(f"Error initializing shadow: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF
    
    zip -r "shadow-init.zip" "shadow_init.py"
    
    # Deploy shadow initialization function
    aws lambda create-function \
        --function-name "$SHADOW_INIT_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${HOOK_FUNCTION_NAME}-execution-role" \
        --handler shadow_init.lambda_handler \
        --zip-file fileb://shadow-init.zip \
        --timeout 30 \
        --memory-size 128 \
        --tags Project=IoTProvisioning,DeploymentId="$DEPLOYMENT_ID"
    
    log "Lambda functions created successfully"
}

# Create IoT Thing Groups
create_thing_groups() {
    log "Creating IoT Thing Groups..."
    
    # Create parent thing group
    aws iot create-thing-group \
        --thing-group-name "$THING_GROUP_NAME" \
        --thing-group-properties \
        'thingGroupDescription="Parent group for all provisioned devices"'
    
    # Create device-type specific thing groups
    local device_types=("temperature-sensor" "humidity-sensor" "pressure-sensor" "gateway")
    
    for device_type in "${device_types[@]}"; do
        aws iot create-thing-group \
            --thing-group-name "${device_type}-devices" \
            --thing-group-properties \
            "thingGroupDescription=\"${device_type} devices\",parentGroupName=\"${THING_GROUP_NAME}\""
    done
    
    log "Thing groups created successfully"
}

# Create IoT policies
create_iot_policies() {
    log "Creating IoT policies for device types..."
    
    # Create temperature sensor policy
    cat > "/tmp/temperature-sensor-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:Connect"
            ],
            "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:client/temperature-sensor-*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:Publish"
            ],
            "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/sensors/temperature/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:Subscribe",
                "iot:Receive"
            ],
            "Resource": [
                "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topicfilter/config/temperature-sensor/*",
                "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/config/temperature-sensor/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:GetThingShadow",
                "iot:UpdateThingShadow"
            ],
            "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thing/temperature-sensor-*"
        }
    ]
}
EOF
    
    aws iot create-policy \
        --policy-name "TemperatureSensorPolicy" \
        --policy-document file:///tmp/temperature-sensor-policy.json
    
    # Create gateway policy
    cat > "/tmp/gateway-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:Connect"
            ],
            "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:client/gateway-*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:Publish"
            ],
            "Resource": [
                "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/gateway/*",
                "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/sensors/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:Subscribe",
                "iot:Receive"
            ],
            "Resource": [
                "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topicfilter/config/gateway/*",
                "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/config/gateway/*",
                "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topicfilter/commands/*",
                "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/commands/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:GetThingShadow",
                "iot:UpdateThingShadow"
            ],
            "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thing/gateway-*"
        }
    ]
}
EOF
    
    aws iot create-policy \
        --policy-name "GatewayDevicePolicy" \
        --policy-document file:///tmp/gateway-policy.json
    
    # Create claim certificate policy
    cat > "/tmp/claim-cert-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:Connect"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:Publish"
            ],
            "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/\$aws/provisioning-templates/${TEMPLATE_NAME}/provision/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iot:Subscribe",
                "iot:Receive"
            ],
            "Resource": [
                "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topicfilter/\$aws/provisioning-templates/${TEMPLATE_NAME}/provision/*"
            ]
        }
    ]
}
EOF
    
    aws iot create-policy \
        --policy-name "ClaimCertificatePolicy" \
        --policy-document file:///tmp/claim-cert-policy.json
    
    log "IoT policies created successfully"
}

# Create provisioning template
create_provisioning_template() {
    log "Creating provisioning template..."
    
    # Create provisioning template
    cat > "/tmp/provisioning-template.json" << EOF
{
    "templateName": "${TEMPLATE_NAME}",
    "description": "Template for automated device provisioning with validation",
    "templateBody": "{\"Parameters\":{\"SerialNumber\":{\"Type\":\"String\"},\"DeviceType\":{\"Type\":\"String\"},\"FirmwareVersion\":{\"Type\":\"String\"},\"Manufacturer\":{\"Type\":\"String\"},\"Location\":{\"Type\":\"String\"},\"AWS::IoT::Certificate::Id\":{\"Type\":\"String\"},\"AWS::IoT::Certificate::Arn\":{\"Type\":\"String\"}},\"Resources\":{\"thing\":{\"Type\":\"AWS::IoT::Thing\",\"Properties\":{\"ThingName\":{\"Ref\":\"ThingName\"},\"AttributePayload\":{\"serialNumber\":{\"Ref\":\"SerialNumber\"},\"deviceType\":{\"Ref\":\"DeviceType\"},\"firmwareVersion\":{\"Ref\":\"FirmwareVersion\"},\"manufacturer\":{\"Ref\":\"Manufacturer\"},\"location\":{\"Ref\":\"DeviceLocation\"},\"provisioningTime\":{\"Ref\":\"ProvisioningTime\"}},\"ThingTypeName\":\"IoTDevice\"}},\"certificate\":{\"Type\":\"AWS::IoT::Certificate\",\"Properties\":{\"CertificateId\":{\"Ref\":\"AWS::IoT::Certificate::Id\"},\"Status\":\"Active\"}},\"policy\":{\"Type\":\"AWS::IoT::Policy\",\"Properties\":{\"PolicyName\":{\"Fn::Sub\":\"\${DeviceType}Policy\"}}},\"thingGroup\":{\"Type\":\"AWS::IoT::ThingGroup\",\"Properties\":{\"ThingGroupName\":{\"Ref\":\"ThingGroupName\"}}}}}",
    "enabled": true,
    "provisioningRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IOT_ROLE_NAME}",
    "preProvisioningHook": {
        "targetArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${HOOK_FUNCTION_NAME}",
        "payloadVersion": "2020-04-01"
    },
    "tags": [
        {
            "Key": "Project",
            "Value": "IoTProvisioning"
        },
        {
            "Key": "DeploymentId",
            "Value": "${DEPLOYMENT_ID}"
        }
    ]
}
EOF
    
    aws iot create-provisioning-template \
        --cli-input-json file:///tmp/provisioning-template.json
    
    log "Provisioning template created successfully"
}

# Create claim certificates
create_claim_certificates() {
    log "Creating claim certificates for device manufacturing..."
    
    # Create claim certificate
    aws iot create-keys-and-certificate \
        --set-as-active \
        --certificate-pem-outfile "/tmp/claim-certificate.pem" \
        --public-key-outfile "/tmp/claim-public-key.pem" \
        --private-key-outfile "/tmp/claim-private-key.pem" > "/tmp/claim-cert-output.json"
    
    # Extract certificate ARN and ID
    local claim_cert_arn=$(jq -r '.certificateArn' "/tmp/claim-cert-output.json")
    local claim_cert_id=$(jq -r '.certificateId' "/tmp/claim-cert-output.json")
    
    # Store in environment file
    echo "CLAIM_CERT_ARN=${claim_cert_arn}" >> "/tmp/iot-provisioning-deployment.env"
    echo "CLAIM_CERT_ID=${claim_cert_id}" >> "/tmp/iot-provisioning-deployment.env"
    
    # Attach policy to claim certificate
    aws iot attach-policy \
        --policy-name "ClaimCertificatePolicy" \
        --target "$claim_cert_arn"
    
    log "Claim certificate created successfully"
    log "Certificate ARN: $claim_cert_arn"
    log "Certificate files saved to /tmp/ directory"
}

# Setup monitoring and logging
setup_monitoring() {
    log "Setting up monitoring and alerting..."
    
    # Create CloudWatch log group
    aws logs create-log-group \
        --log-group-name "/aws/iot/provisioning" \
        --tags Project=IoTProvisioning,DeploymentId="$DEPLOYMENT_ID" || true
    
    # Create IoT rule for audit logging
    aws iot create-topic-rule \
        --rule-name "ProvisioningAuditRule-${DEPLOYMENT_ID}" \
        --topic-rule-payload "{
            \"sql\": \"SELECT * FROM '\$aws/events/provisioning/template/+/+'\",
            \"description\": \"Log all provisioning events for audit\",
            \"actions\": [
                {
                    \"cloudwatchLogs\": {
                        \"logGroupName\": \"/aws/iot/provisioning\",
                        \"roleArn\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IOT_ROLE_NAME}\"
                    }
                }
            ]
        }"
    
    log "Monitoring and alerting configured successfully"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check if provisioning template exists
    if aws iot describe-provisioning-template --template-name "$TEMPLATE_NAME" > /dev/null 2>&1; then
        log "✓ Provisioning template validation passed"
    else
        error "✗ Provisioning template validation failed"
        return 1
    fi
    
    # Check if Lambda function exists
    if aws lambda get-function --function-name "$HOOK_FUNCTION_NAME" > /dev/null 2>&1; then
        log "✓ Lambda function validation passed"
    else
        error "✗ Lambda function validation failed"
        return 1
    fi
    
    # Check if DynamoDB table exists
    if aws dynamodb describe-table --table-name "$DEVICE_REGISTRY_TABLE" > /dev/null 2>&1; then
        log "✓ DynamoDB table validation passed"
    else
        error "✗ DynamoDB table validation failed"
        return 1
    fi
    
    log "Deployment validation completed successfully"
}

# Print deployment summary
print_deployment_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Deployment ID: $DEPLOYMENT_ID"
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account: $AWS_ACCOUNT_ID"
    echo ""
    echo "Resources Created:"
    echo "- Provisioning Template: $TEMPLATE_NAME"
    echo "- Pre-provisioning Hook: $HOOK_FUNCTION_NAME"
    echo "- Device Registry Table: $DEVICE_REGISTRY_TABLE"
    echo "- IoT Role: $IOT_ROLE_NAME"
    echo "- Thing Group: $THING_GROUP_NAME"
    echo "- Shadow Initializer: $SHADOW_INIT_FUNCTION_NAME"
    echo ""
    echo "Configuration saved to: /tmp/iot-provisioning-deployment.env"
    echo "Claim certificates saved to: /tmp/claim-*.pem"
    echo ""
    echo "Next Steps:"
    echo "1. Test device provisioning using the claim certificates"
    echo "2. Monitor provisioning logs in CloudWatch"
    echo "3. Configure device manufacturing processes"
    echo "4. Set up certificate lifecycle management"
    echo ""
    echo "For cleanup, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting IoT Device Provisioning and Certificate Management deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    deploy_device_registry
    create_iam_resources
    create_lambda_functions
    create_thing_groups
    create_iot_policies
    create_provisioning_template
    create_claim_certificates
    setup_monitoring
    validate_deployment
    print_deployment_summary
    
    log "Deployment completed successfully!"
    log "Total deployment time: $(date)"
}

# Handle script interruption
cleanup_on_exit() {
    warn "Deployment interrupted. Cleaning up temporary files..."
    rm -f /tmp/iot-provisioning-*.json /tmp/lambda-*.json /tmp/*-policy.json
    exit 1
}

# Set up signal handlers
trap cleanup_on_exit INT TERM

# Run main function
main "$@"