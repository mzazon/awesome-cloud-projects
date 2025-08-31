#!/bin/bash

# Distributed Service Tracing with VPC Lattice and X-Ray - Deployment Script
# This script deploys the complete infrastructure for distributed service tracing
# using VPC Lattice service mesh and AWS X-Ray for application observability

set -e

# Color codes for output
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

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_NAME="distributed-tracing"
DEPLOYMENT_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
STATE_FILE="${SCRIPT_DIR}/.deployment-state-${DEPLOYMENT_TIMESTAMP}"

# Cleanup function for error handling
cleanup_on_error() {
    warn "Deployment failed. Cleaning up partial resources..."
    if [ -f "${STATE_FILE}" ]; then
        source "${STATE_FILE}"
        ./destroy.sh --force || true
    fi
    rm -f "${STATE_FILE}" || true
    error "Deployment failed and cleanup completed"
}

trap cleanup_on_error ERR

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ "$(printf '%s\n' "2.0.0" "$aws_version" | sort -V | head -n1)" != "2.0.0" ]]; then
        error "AWS CLI version 2.0.0 or higher is required. Current version: $aws_version"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' or set environment variables."
    fi
    
    # Check Python 3
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed. Please install Python 3.8 or higher."
    fi
    
    # Check pip3
    if ! command -v pip3 &> /dev/null; then
        error "pip3 is not installed. Please install pip3."
    fi
    
    # Check required permissions (basic test)
    log "Validating AWS permissions..."
    aws iam get-user &> /dev/null || aws sts get-caller-identity &> /dev/null || error "Unable to validate AWS permissions"
    
    log "Prerequisites check completed successfully"
}

# Environment setup function
setup_environment() {
    log "Setting up environment variables..."
    
    # Core AWS environment
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No default region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    info "AWS Region: ${AWS_REGION}"
    info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "Resource Suffix: ${RANDOM_SUFFIX}"
    
    # Save state for cleanup
    cat > "${STATE_FILE}" << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export VPC_ID=""
export SUBNET_ID=""
export SERVICE_NETWORK_ID=""
export VPC_ASSOCIATION_ID=""
export ORDER_FUNCTION_ARN=""
export PAYMENT_FUNCTION_ARN=""
export INVENTORY_FUNCTION_ARN=""
export XRAY_LAYER_ARN=""
export ORDER_SERVICE_ID=""
export ORDER_TG_ID=""
export DEPLOYMENT_TIMESTAMP="${DEPLOYMENT_TIMESTAMP}"
EOF
    
    log "Environment setup completed"
}

# VPC infrastructure setup
setup_vpc_infrastructure() {
    log "Creating VPC infrastructure..."
    
    # Create VPC
    export VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications \
        "ResourceType=vpc,Tags=[{Key=Name,Value=lattice-tracing-vpc-${RANDOM_SUFFIX}},{Key=Project,Value=${PROJECT_NAME}},{Key=Timestamp,Value=${DEPLOYMENT_TIMESTAMP}}]" \
        --query 'Vpc.VpcId' --output text)
    
    info "VPC created: ${VPC_ID}"
    
    # Wait for VPC to be available
    aws ec2 wait vpc-available --vpc-ids "${VPC_ID}"
    
    # Create internet gateway for Lambda internet access
    IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications \
        "ResourceType=internet-gateway,Tags=[{Key=Name,Value=lattice-tracing-igw-${RANDOM_SUFFIX}},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    # Attach internet gateway
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "${IGW_ID}" \
        --vpc-id "${VPC_ID}"
    
    # Create subnet
    export SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications \
        "ResourceType=subnet,Tags=[{Key=Name,Value=lattice-tracing-subnet-${RANDOM_SUFFIX}},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'Subnet.SubnetId' --output text)
    
    info "Subnet created: ${SUBNET_ID}"
    
    # Create route table and routes
    ROUTE_TABLE_ID=$(aws ec2 create-route-table \
        --vpc-id "${VPC_ID}" \
        --tag-specifications \
        "ResourceType=route-table,Tags=[{Key=Name,Value=lattice-tracing-rt-${RANDOM_SUFFIX}},{Key=Project,Value=${PROJECT_NAME}}]" \
        --query 'RouteTable.RouteTableId' --output text)
    
    aws ec2 create-route \
        --route-table-id "${ROUTE_TABLE_ID}" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "${IGW_ID}"
    
    aws ec2 associate-route-table \
        --route-table-id "${ROUTE_TABLE_ID}" \
        --subnet-id "${SUBNET_ID}"
    
    # Update state file
    sed -i '' "s/export VPC_ID=\"\"/export VPC_ID=\"${VPC_ID}\"/" "${STATE_FILE}"
    sed -i '' "s/export SUBNET_ID=\"\"/export SUBNET_ID=\"${SUBNET_ID}\"/" "${STATE_FILE}"
    sed -i '' "s/IGW_ID=\"\"/export IGW_ID=\"${IGW_ID}\"/" "${STATE_FILE}"
    sed -i '' "s/ROUTE_TABLE_ID=\"\"/export ROUTE_TABLE_ID=\"${ROUTE_TABLE_ID}\"/" "${STATE_FILE}"
    
    log "VPC infrastructure setup completed"
}

# IAM role creation
create_iam_resources() {
    log "Creating IAM resources..."
    
    # Create IAM role for Lambda functions
    aws iam create-role \
        --role-name "lattice-lambda-xray-role-${RANDOM_SUFFIX}" \
        --assume-role-policy-document '{
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
        }' \
        --tags "Key=Project,Value=${PROJECT_NAME}" "Key=Timestamp,Value=${DEPLOYMENT_TIMESTAMP}" || warn "IAM role may already exist"
    
    # Wait for role to propagate
    sleep 10
    
    # Attach necessary policies
    aws iam attach-role-policy \
        --role-name "lattice-lambda-xray-role-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name "lattice-lambda-xray-role-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess
    
    aws iam attach-role-policy \
        --role-name "lattice-lambda-xray-role-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole
    
    # Wait for policy attachments to propagate
    sleep 15
    
    log "IAM resources created successfully"
}

# Lambda layer creation
create_lambda_layer() {
    log "Creating Lambda layer with X-Ray SDK..."
    
    # Create temporary directory for dependencies
    TEMP_DIR=$(mktemp -d)
    mkdir -p "${TEMP_DIR}/python"
    
    # Install X-Ray SDK
    pip3 install aws-xray-sdk -t "${TEMP_DIR}/python/" --quiet
    
    # Create layer zip
    cd "${TEMP_DIR}"
    zip -r xray-layer.zip python/ > /dev/null
    
    # Publish Lambda layer
    export XRAY_LAYER_ARN=$(aws lambda publish-layer-version \
        --layer-name "xray-sdk-${RANDOM_SUFFIX}" \
        --description "AWS X-Ray SDK for Python - Distributed Tracing" \
        --zip-file "fileb://xray-layer.zip" \
        --compatible-runtimes python3.12 python3.11 python3.10 \
        --query 'LayerVersionArn' --output text)
    
    info "X-Ray layer created: ${XRAY_LAYER_ARN}"
    
    # Cleanup
    cd "${SCRIPT_DIR}"
    rm -rf "${TEMP_DIR}"
    
    # Update state file
    sed -i '' "s|export XRAY_LAYER_ARN=\"\"|export XRAY_LAYER_ARN=\"${XRAY_LAYER_ARN}\"|" "${STATE_FILE}"
    
    log "Lambda layer creation completed"
}

# Lambda functions creation
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Order Service Lambda
    cat > order-service.py << 'EOF'
import json
import boto3
import os
import time
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch all AWS SDK calls for X-Ray tracing
patch_all()

# Initialize Lambda client for downstream service calls
lambda_client = boto3.client('lambda')

@xray_recorder.capture('process_order')
def lambda_handler(event, context):
    # Extract order information
    order_id = event.get('order_id', 'default-order')
    customer_id = event.get('customer_id', 'unknown-customer')
    items = event.get('items', [])
    
    # Add annotations for filtering and searching traces
    xray_recorder.current_segment().put_annotation('order_id', order_id)
    xray_recorder.current_segment().put_annotation('customer_id', customer_id)
    xray_recorder.current_segment().put_annotation('item_count', len(items))
    
    # Create subsegment for payment processing
    with xray_recorder.in_subsegment('call_payment_service'):
        payment_response = call_payment_service(order_id, items)
    
    # Create subsegment for inventory check
    with xray_recorder.in_subsegment('call_inventory_service'):
        inventory_response = call_inventory_service(order_id, items)
    
    # Add metadata for detailed trace context
    xray_recorder.current_segment().put_metadata('order_details', {
        'order_id': order_id,
        'customer_id': customer_id,
        'items': items,
        'payment_status': payment_response,
        'inventory_status': inventory_response
    })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'order_id': order_id,
            'customer_id': customer_id,
            'payment_status': payment_response,
            'inventory_status': inventory_response,
            'message': 'Order processed successfully'
        })
    }

@xray_recorder.capture('payment_call')
def call_payment_service(order_id, items):
    # Calculate total amount
    total_amount = sum(item.get('price', 0) * item.get('quantity', 1) for item in items)
    
    # Add service-specific annotations
    xray_recorder.current_subsegment().put_annotation('service', 'payment')
    xray_recorder.current_subsegment().put_annotation('total_amount', total_amount)
    xray_recorder.current_subsegment().put_metadata('payment_request', {
        'order_id': order_id,
        'amount': total_amount,
        'currency': 'USD'
    })
    
    # Simulate payment service call
    time.sleep(0.1)
    return {'status': 'approved', 'amount': total_amount}

@xray_recorder.capture('inventory_call')  
def call_inventory_service(order_id, items):
    # Add service-specific annotations
    xray_recorder.current_subsegment().put_annotation('service', 'inventory')
    xray_recorder.current_subsegment().put_metadata('inventory_request', {
        'order_id': order_id,
        'items': items
    })
    
    # Simulate inventory service call
    time.sleep(0.05)
    return {'status': 'reserved', 'items_reserved': len(items)}
EOF
    
    zip order-service.zip order-service.py > /dev/null
    
    # Create Order Service Lambda function
    export ORDER_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "order-service-${RANDOM_SUFFIX}" \
        --runtime python3.12 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lattice-lambda-xray-role-${RANDOM_SUFFIX}" \
        --handler order-service.lambda_handler \
        --zip-file fileb://order-service.zip \
        --timeout 30 \
        --memory-size 256 \
        --tracing-config Mode=Active \
        --layers "${XRAY_LAYER_ARN}" \
        --tags "Project=${PROJECT_NAME},Timestamp=${DEPLOYMENT_TIMESTAMP}" \
        --query 'FunctionArn' --output text)
    
    info "Order service created: ${ORDER_FUNCTION_ARN}"
    
    # Payment Service Lambda
    cat > payment-service.py << 'EOF'
import json
import time
import random
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

patch_all()

@xray_recorder.capture('process_payment')
def lambda_handler(event, context):
    order_id = event.get('order_id', 'unknown')
    amount = event.get('amount', 100.00)
    
    # Simulate varying payment processing times
    processing_time = random.uniform(0.1, 0.5)
    time.sleep(processing_time)
    
    # Add annotations and metadata for tracing
    xray_recorder.current_segment().put_annotation('payment_amount', amount)
    xray_recorder.current_segment().put_annotation('processing_time', processing_time)
    xray_recorder.current_segment().put_annotation('payment_gateway', 'stripe')
    xray_recorder.current_segment().put_metadata('payment_details', {
        'order_id': order_id,
        'amount': amount,
        'currency': 'USD',
        'processing_time_ms': processing_time * 1000
    })
    
    # Simulate occasional failures for demonstration
    if random.random() < 0.1:  # 10% failure rate
        xray_recorder.current_segment().add_exception(Exception("Payment gateway timeout"))
        xray_recorder.current_segment().put_annotation('payment_status', 'failed')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Payment processing failed'})
        }
    
    xray_recorder.current_segment().put_annotation('payment_status', 'approved')
    return {
        'statusCode': 200,
        'body': json.dumps({
            'payment_id': f'pay_{order_id}_{int(time.time())}',
            'status': 'approved',
            'amount': amount,
            'processing_time': processing_time
        })
    }
EOF
    
    zip payment-service.zip payment-service.py > /dev/null
    
    export PAYMENT_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "payment-service-${RANDOM_SUFFIX}" \
        --runtime python3.12 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lattice-lambda-xray-role-${RANDOM_SUFFIX}" \
        --handler payment-service.lambda_handler \
        --zip-file fileb://payment-service.zip \
        --timeout 30 \
        --memory-size 256 \
        --tracing-config Mode=Active \
        --layers "${XRAY_LAYER_ARN}" \
        --tags "Project=${PROJECT_NAME},Timestamp=${DEPLOYMENT_TIMESTAMP}" \
        --query 'FunctionArn' --output text)
    
    info "Payment service created: ${PAYMENT_FUNCTION_ARN}"
    
    # Inventory Service Lambda
    cat > inventory-service.py << 'EOF'
import json
import time
import random
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

patch_all()

@xray_recorder.capture('check_inventory')
def lambda_handler(event, context):
    product_id = event.get('product_id', 'default-product')
    quantity = event.get('quantity', 1)
    
    # Simulate database lookup time with variance
    lookup_time = random.uniform(0.05, 0.3)
    time.sleep(lookup_time)
    
    # Add tracing annotations for filtering and analysis
    xray_recorder.current_segment().put_annotation('product_id', product_id)
    xray_recorder.current_segment().put_annotation('quantity_requested', quantity)
    xray_recorder.current_segment().put_annotation('lookup_time', lookup_time)
    xray_recorder.current_segment().put_annotation('database', 'dynamodb')
    
    # Simulate inventory levels
    available_stock = random.randint(0, 100)
    
    xray_recorder.current_segment().put_metadata('inventory_check', {
        'product_id': product_id,
        'available_stock': available_stock,
        'requested_quantity': quantity,
        'lookup_time_ms': lookup_time * 1000
    })
    
    if available_stock >= quantity:
        xray_recorder.current_segment().put_annotation('inventory_status', 'available')
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'available',
                'available_stock': available_stock,
                'reserved_quantity': quantity
            })
        }
    else:
        xray_recorder.current_segment().put_annotation('inventory_status', 'insufficient')
        return {
            'statusCode': 409,
            'body': json.dumps({
                'status': 'insufficient_stock',
                'available_stock': available_stock,
                'requested_quantity': quantity
            })
        }
EOF
    
    zip inventory-service.zip inventory-service.py > /dev/null
    
    export INVENTORY_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "inventory-service-${RANDOM_SUFFIX}" \
        --runtime python3.12 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lattice-lambda-xray-role-${RANDOM_SUFFIX}" \
        --handler inventory-service.lambda_handler \
        --zip-file fileb://inventory-service.zip \
        --timeout 30 \
        --memory-size 256 \
        --tracing-config Mode=Active \
        --layers "${XRAY_LAYER_ARN}" \
        --tags "Project=${PROJECT_NAME},Timestamp=${DEPLOYMENT_TIMESTAMP}" \
        --query 'FunctionArn' --output text)
    
    info "Inventory service created: ${INVENTORY_FUNCTION_ARN}"
    
    # Cleanup
    cd "${SCRIPT_DIR}"
    rm -rf "${TEMP_DIR}"
    
    # Update state file
    sed -i '' "s|export ORDER_FUNCTION_ARN=\"\"|export ORDER_FUNCTION_ARN=\"${ORDER_FUNCTION_ARN}\"|" "${STATE_FILE}"
    sed -i '' "s|export PAYMENT_FUNCTION_ARN=\"\"|export PAYMENT_FUNCTION_ARN=\"${PAYMENT_FUNCTION_ARN}\"|" "${STATE_FILE}"
    sed -i '' "s|export INVENTORY_FUNCTION_ARN=\"\"|export INVENTORY_FUNCTION_ARN=\"${INVENTORY_FUNCTION_ARN}\"|" "${STATE_FILE}"
    
    log "Lambda functions created successfully"
}

# VPC Lattice setup
setup_vpc_lattice() {
    log "Setting up VPC Lattice service network..."
    
    # Create VPC Lattice service network
    export SERVICE_NETWORK_ID=$(aws vpc-lattice create-service-network \
        --name "tracing-network-${RANDOM_SUFFIX}" \
        --auth-type AWS_IAM \
        --tags "Name=tracing-network,Project=${PROJECT_NAME},Timestamp=${DEPLOYMENT_TIMESTAMP}" \
        --query 'id' --output text)
    
    info "Service network created: ${SERVICE_NETWORK_ID}"
    
    # Associate VPC with service network
    export VPC_ASSOCIATION_ID=$(aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --vpc-identifier "${VPC_ID}" \
        --tags "Project=${PROJECT_NAME},Timestamp=${DEPLOYMENT_TIMESTAMP}" \
        --query 'id' --output text)
    
    info "VPC association created: ${VPC_ASSOCIATION_ID}"
    
    # Create target group for order service
    export ORDER_TG_ID=$(aws vpc-lattice create-target-group \
        --name "order-tg-${RANDOM_SUFFIX}" \
        --type LAMBDA \
        --config '{
            "healthCheck": {
                "enabled": true,
                "protocol": "HTTPS",
                "path": "/health",
                "intervalSeconds": 30,
                "timeoutSeconds": 5,
                "healthyThresholdCount": 2,
                "unhealthyThresholdCount": 2
            }
        }' \
        --tags "Name=order-target-group,Project=${PROJECT_NAME},Timestamp=${DEPLOYMENT_TIMESTAMP}" \
        --query 'id' --output text)
    
    info "Target group created: ${ORDER_TG_ID}"
    
    # Register Lambda function with target group
    aws vpc-lattice register-targets \
        --target-group-identifier "${ORDER_TG_ID}" \
        --targets "Id=${ORDER_FUNCTION_ARN}"
    
    # Create VPC Lattice service for order processing
    export ORDER_SERVICE_ID=$(aws vpc-lattice create-service \
        --name "order-service-${RANDOM_SUFFIX}" \
        --auth-type AWS_IAM \
        --tags "Name=order-service,Project=${PROJECT_NAME},Timestamp=${DEPLOYMENT_TIMESTAMP}" \
        --query 'id' --output text)
    
    info "Lattice service created: ${ORDER_SERVICE_ID}"
    
    # Create listener for the service
    aws vpc-lattice create-listener \
        --service-identifier "${ORDER_SERVICE_ID}" \
        --name "order-listener" \
        --protocol HTTPS \
        --port 443 \
        --default-action "{
            \"forward\": {
                \"targetGroups\": [
                    {
                        \"targetGroupIdentifier\": \"${ORDER_TG_ID}\",
                        \"weight\": 100
                    }
                ]
            }
        }" \
        --tags "Name=order-listener,Project=${PROJECT_NAME},Timestamp=${DEPLOYMENT_TIMESTAMP}" > /dev/null
    
    # Associate service with service network
    aws vpc-lattice create-service-network-service-association \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --service-identifier "${ORDER_SERVICE_ID}" \
        --tags "Project=${PROJECT_NAME},Timestamp=${DEPLOYMENT_TIMESTAMP}" > /dev/null
    
    # Update state file
    sed -i '' "s|export SERVICE_NETWORK_ID=\"\"|export SERVICE_NETWORK_ID=\"${SERVICE_NETWORK_ID}\"|" "${STATE_FILE}"
    sed -i '' "s|export VPC_ASSOCIATION_ID=\"\"|export VPC_ASSOCIATION_ID=\"${VPC_ASSOCIATION_ID}\"|" "${STATE_FILE}"
    sed -i '' "s|export ORDER_SERVICE_ID=\"\"|export ORDER_SERVICE_ID=\"${ORDER_SERVICE_ID}\"|" "${STATE_FILE}"
    sed -i '' "s|export ORDER_TG_ID=\"\"|export ORDER_TG_ID=\"${ORDER_TG_ID}\"|" "${STATE_FILE}"
    
    log "VPC Lattice setup completed"
}

# CloudWatch and observability setup
setup_observability() {
    log "Setting up observability and monitoring..."
    
    # Create CloudWatch Log Groups
    aws logs create-log-group \
        --log-group-name "/aws/lambda/order-service-${RANDOM_SUFFIX}" \
        --tags "Project=${PROJECT_NAME},Timestamp=${DEPLOYMENT_TIMESTAMP}" 2>/dev/null || warn "Log group may already exist"
    
    aws logs create-log-group \
        --log-group-name "/aws/lambda/payment-service-${RANDOM_SUFFIX}" \
        --tags "Project=${PROJECT_NAME},Timestamp=${DEPLOYMENT_TIMESTAMP}" 2>/dev/null || warn "Log group may already exist"
    
    aws logs create-log-group \
        --log-group-name "/aws/lambda/inventory-service-${RANDOM_SUFFIX}" \
        --tags "Project=${PROJECT_NAME},Timestamp=${DEPLOYMENT_TIMESTAMP}" 2>/dev/null || warn "Log group may already exist"
    
    # Create log group for VPC Lattice access logs
    aws logs create-log-group \
        --log-group-name "/aws/vpclattice/servicenetwork-${RANDOM_SUFFIX}" \
        --tags "Project=${PROJECT_NAME},Timestamp=${DEPLOYMENT_TIMESTAMP}" 2>/dev/null || warn "Log group may already exist"
    
    # Enable VPC Lattice access logging
    aws vpc-lattice put-access-log-subscription \
        --resource-identifier "${SERVICE_NETWORK_ID}" \
        --destination-arn "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/vpclattice/servicenetwork-${RANDOM_SUFFIX}"
    
    # Create CloudWatch dashboard
    DASHBOARD_BODY='{
        "widgets": [
            {
                "type": "metric",
                "x": 0,
                "y": 0,
                "width": 12,
                "height": 6,
                "properties": {
                    "metrics": [
                        ["AWS/VPC-Lattice", "RequestCount", "ServiceNetwork", "'${SERVICE_NETWORK_ID}'"],
                        [".", "ResponseTime", ".", "."],
                        [".", "ActiveConnectionCount", ".", "."]
                    ],
                    "period": 300,
                    "stat": "Average",
                    "region": "'${AWS_REGION}'",
                    "title": "VPC Lattice Metrics"
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
                        ["AWS/Lambda", "Duration", "FunctionName", "order-service-'${RANDOM_SUFFIX}'"],
                        [".", "Invocations", ".", "."],
                        [".", "Errors", ".", "."]
                    ],
                    "period": 300,
                    "stat": "Average",
                    "region": "'${AWS_REGION}'",
                    "title": "Lambda Performance"
                }
            },
            {
                "type": "metric",
                "x": 0,
                "y": 6,
                "width": 24,
                "height": 6,
                "properties": {
                    "metrics": [
                        ["AWS/X-Ray", "TracesReceived"],
                        [".", "LatencyHigh", "ServiceName", "order-service-'${RANDOM_SUFFIX}'"],
                        [".", "ErrorRate", ".", "."]
                    ],
                    "period": 300,
                    "stat": "Average",
                    "region": "'${AWS_REGION}'",
                    "title": "X-Ray Trace Metrics"
                }
            }
        ]
    }'
    
    aws cloudwatch put-dashboard \
        --dashboard-name "Lattice-XRay-Observability-${RANDOM_SUFFIX}" \
        --dashboard-body "${DASHBOARD_BODY}"
    
    log "Observability setup completed"
}

# Test data generator creation
create_test_generator() {
    log "Creating test data generator..."
    
    cat > "${SCRIPT_DIR}/test-distributed-tracing.py" << EOF
import boto3
import json
import time
import random
from concurrent.futures import ThreadPoolExecutor

lambda_client = boto3.client('lambda')
RANDOM_SUFFIX = "${RANDOM_SUFFIX}"

def invoke_order_service(order_id):
    """Invoke order service with test data"""
    try:
        response = lambda_client.invoke(
            FunctionName=f'order-service-{RANDOM_SUFFIX}',
            InvocationType='RequestResponse',
            Payload=json.dumps({
                'order_id': f'order-{order_id}',
                'customer_id': f'customer-{random.randint(1, 100)}',
                'items': [
                    {
                        'product_id': f'product-{random.randint(1, 50)}',
                        'quantity': random.randint(1, 5),
                        'price': round(random.uniform(10, 200), 2)
                    }
                ]
            })
        )
        return response['StatusCode'] == 200
    except Exception as e:
        print(f"Error invoking order service: {e}")
        return False

def generate_test_traffic(num_requests=50):
    """Generate test traffic for distributed tracing"""
    print(f"Generating {num_requests} test requests...")
    
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = []
        for i in range(num_requests):
            future = executor.submit(invoke_order_service, i)
            futures.append(future)
            # Vary request timing to simulate realistic load
            time.sleep(random.uniform(0.1, 0.5))
        
        # Wait for all requests to complete
        successful_requests = sum(1 for future in futures if future.result())
        print(f"Completed {successful_requests}/{num_requests} requests successfully")

if __name__ == "__main__":
    generate_test_traffic()
EOF
    
    chmod +x "${SCRIPT_DIR}/test-distributed-tracing.py"
    
    log "Test generator created: ${SCRIPT_DIR}/test-distributed-tracing.py"
}

# Validation and testing
run_validation() {
    log "Running deployment validation..."
    
    # Test Lambda function invocation
    info "Testing order service invocation..."
    TEST_RESPONSE=$(aws lambda invoke \
        --function-name "order-service-${RANDOM_SUFFIX}" \
        --payload '{"order_id": "test-order-123", "customer_id": "test-customer", "items": [{"product_id": "test-product", "quantity": 2, "price": 50.00}]}' \
        --output json \
        response.json)
    
    if [ $? -eq 0 ]; then
        info "✅ Order service test successful"
        cat response.json
        rm -f response.json
    else
        error "❌ Order service test failed"
    fi
    
    # Wait for X-Ray traces
    info "Waiting for X-Ray traces to propagate..."
    sleep 30
    
    # Check X-Ray traces
    TRACE_COUNT=$(aws xray get-trace-summaries \
        --time-range-type TimeRangeByStartTime \
        --start-time $(date -d '5 minutes ago' -u +%Y-%m-%dT%H:%M:%SZ) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
        --query 'length(TraceSummaries)' --output text)
    
    if [ "${TRACE_COUNT}" -gt 0 ]; then
        info "✅ X-Ray traces are being collected (${TRACE_COUNT} traces found)"
    else
        warn "⚠️  No X-Ray traces found yet (this is normal for new deployments)"
    fi
    
    log "Validation completed"
}

# Main deployment function
main() {
    log "Starting distributed service tracing deployment..."
    log "Project: ${PROJECT_NAME}"
    log "Timestamp: ${DEPLOYMENT_TIMESTAMP}"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    setup_vpc_infrastructure
    create_iam_resources
    create_lambda_layer
    create_lambda_functions
    setup_vpc_lattice
    setup_observability
    create_test_generator
    run_validation
    
    # Display success information
    log "🎉 Deployment completed successfully!"
    echo ""
    info "📋 Deployment Summary:"
    info "  • VPC Lattice Service Network: ${SERVICE_NETWORK_ID}"
    info "  • Order Service Lambda: ${ORDER_FUNCTION_ARN}"
    info "  • Payment Service Lambda: ${PAYMENT_FUNCTION_ARN}"
    info "  • Inventory Service Lambda: ${INVENTORY_FUNCTION_ARN}"
    info "  • X-Ray Layer: ${XRAY_LAYER_ARN}"
    info "  • CloudWatch Dashboard: Lattice-XRay-Observability-${RANDOM_SUFFIX}"
    echo ""
    info "🧪 Testing:"
    info "  • Run test generator: python3 ${SCRIPT_DIR}/test-distributed-tracing.py"
    info "  • View X-Ray traces: https://${AWS_REGION}.console.aws.amazon.com/xray"
    info "  • View CloudWatch dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch"
    echo ""
    info "🗑️  Cleanup:"
    info "  • Run: ${SCRIPT_DIR}/destroy.sh"
    echo ""
    
    # Save final state
    echo "# Deployment completed successfully at $(date)" >> "${STATE_FILE}"
    log "State file saved: ${STATE_FILE}"
}

# Script execution
if [ "${1}" = "--dry-run" ]; then
    log "Dry run mode - would execute deployment steps"
    exit 0
fi

main "$@"