#!/bin/bash

# AWS Distributed Tracing with X-Ray - Deployment Script
# This script deploys a complete distributed tracing solution using AWS X-Ray and EventBridge

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

# Error handler
error_handler() {
    local line_number=$1
    log_error "Script failed at line $line_number"
    log_error "Rolling back any created resources..."
    cleanup_on_error
    exit 1
}

trap 'error_handler $LINENO' ERR

# Cleanup function for error scenarios
cleanup_on_error() {
    log_warning "Attempting to clean up resources created during failed deployment..."
    
    # Clean up in reverse order
    if [[ -n "${API_ID:-}" ]]; then
        aws apigateway delete-rest-api --rest-api-id "$API_ID" 2>/dev/null || true
    fi
    
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        # Remove Lambda permissions and functions
        for service in order payment inventory notification; do
            aws lambda remove-permission \
                --function-name "${service}-service-${RANDOM_SUFFIX}" \
                --statement-id "eventbridge-invoke-${service}" 2>/dev/null || true
            aws lambda delete-function \
                --function-name "${service}-service-${RANDOM_SUFFIX}" 2>/dev/null || true
        done
        
        # Remove EventBridge rules and targets
        for rule in payment-processing inventory-update notification; do
            aws events remove-targets \
                --rule "${rule}-rule-${RANDOM_SUFFIX}" \
                --event-bus-name "${EVENT_BUS_NAME}" \
                --ids 1 2>/dev/null || true
            aws events delete-rule \
                --name "${rule}-rule-${RANDOM_SUFFIX}" \
                --event-bus-name "${EVENT_BUS_NAME}" 2>/dev/null || true
        done
        
        # Remove event bus and IAM role
        aws events delete-event-bus --name "${EVENT_BUS_NAME}" 2>/dev/null || true
        
        if [[ -n "${LAMBDA_ROLE_NAME:-}" ]]; then
            for policy in "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
                         "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess" \
                         "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"; do
                aws iam detach-role-policy \
                    --role-name "$LAMBDA_ROLE_NAME" \
                    --policy-arn "$policy" 2>/dev/null || true
            done
            aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" 2>/dev/null || true
        fi
    fi
    
    # Clean up local files
    rm -f ./*.py ./*.zip 2>/dev/null || true
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set up IAM role."
        exit 1
    fi
    
    # Check required utilities
    for cmd in curl zip; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd is not installed. Please install $cmd."
            exit 1
        fi
    done
    
    log_success "All prerequisites met"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export EVENT_BUS_NAME="distributed-tracing-bus-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="distributed-tracing-lambda-role-${RANDOM_SUFFIX}"
    export API_GATEWAY_NAME="distributed-tracing-api-${RANDOM_SUFFIX}"
    
    log_success "Environment configured for region: $AWS_REGION"
    log_info "Account ID: $AWS_ACCOUNT_ID"
    log_info "Resource suffix: $RANDOM_SUFFIX"
}

# Create IAM role for Lambda functions
create_iam_role() {
    log_info "Creating IAM role for Lambda functions..."
    
    # Create IAM role
    aws iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
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
        --tags Key=Project,Value=DistributedTracing \
               Key=Environment,Value=Demo
    
    # Attach required policies
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
        "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
    )
    
    for policy in "${policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn "$policy"
    done
    
    # Wait for role to be available
    log_info "Waiting for IAM role to be available..."
    sleep 10
    
    export LAMBDA_ROLE_ARN
    LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --query Role.Arn --output text)
    
    log_success "Created IAM role: $LAMBDA_ROLE_ARN"
}

# Create EventBridge custom bus
create_event_bus() {
    log_info "Creating EventBridge custom bus..."
    
    aws events create-event-bus \
        --name "$EVENT_BUS_NAME" \
        --event-source-name "distributed-tracing-demo" \
        --tags Key=Project,Value=DistributedTracing
    
    export EVENT_BUS_ARN
    EVENT_BUS_ARN=$(aws events describe-event-bus \
        --name "$EVENT_BUS_NAME" \
        --query EventBus.Arn --output text)
    
    log_success "Created EventBridge custom bus: $EVENT_BUS_NAME"
}

# Create Lambda function code files
create_lambda_code() {
    log_info "Creating Lambda function code..."
    
    # Order service code
    cat > order-service.py << 'EOF'
import json
import boto3
import os
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all
from datetime import datetime

# Patch AWS SDK calls for X-Ray tracing
patch_all()

eventbridge = boto3.client('events')

@xray_recorder.capture('order_service_handler')
def lambda_handler(event, context):
    # Extract trace context from API Gateway
    trace_header = event.get('headers', {}).get('X-Amzn-Trace-Id')
    
    # Create subsegment for order processing
    subsegment = xray_recorder.begin_subsegment('process_order')
    
    try:
        # Simulate order processing
        order_id = f"order-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        customer_id = event.get('pathParameters', {}).get('customerId', 'anonymous')
        
        # Add metadata to trace
        subsegment.put_metadata('order_details', {
            'order_id': order_id,
            'customer_id': customer_id,
            'timestamp': datetime.now().isoformat()
        })
        
        # Publish event to EventBridge with trace context
        event_detail = {
            'orderId': order_id,
            'customerId': customer_id,
            'amount': 99.99,
            'status': 'created'
        }
        
        response = eventbridge.put_events(
            Entries=[
                {
                    'Source': 'order.service',
                    'DetailType': 'Order Created',
                    'Detail': json.dumps(event_detail),
                    'EventBusName': os.environ['EVENT_BUS_NAME']
                }
            ]
        )
        
        # Add annotation for filtering
        xray_recorder.put_annotation('order_id', order_id)
        xray_recorder.put_annotation('service_name', 'order-service')
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'X-Amzn-Trace-Id': trace_header
            },
            'body': json.dumps({
                'orderId': order_id,
                'status': 'created',
                'message': 'Order created successfully'
            })
        }
        
    except Exception as e:
        xray_recorder.put_annotation('error', str(e))
        raise e
    finally:
        xray_recorder.end_subsegment()
EOF
    
    # Payment service code
    cat > payment-service.py << 'EOF'
import json
import boto3
import os
import time
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK calls for X-Ray tracing
patch_all()

eventbridge = boto3.client('events')

@xray_recorder.capture('payment_service_handler')
def lambda_handler(event, context):
    # Process EventBridge event
    for record in event['Records']:
        detail = json.loads(record['body'])
        
        # Create subsegment for payment processing
        subsegment = xray_recorder.begin_subsegment('process_payment')
        
        try:
            order_id = detail['detail']['orderId']
            amount = detail['detail']['amount']
            
            # Add metadata to trace
            subsegment.put_metadata('payment_details', {
                'order_id': order_id,
                'amount': amount,
                'processor': 'stripe'
            })
            
            # Simulate payment processing delay
            time.sleep(0.5)
            
            # Publish payment processed event
            payment_event = {
                'orderId': order_id,
                'amount': amount,
                'paymentId': f"pay-{order_id}",
                'status': 'processed'
            }
            
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'payment.service',
                        'DetailType': 'Payment Processed',
                        'Detail': json.dumps(payment_event),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }
                ]
            )
            
            # Add annotations for filtering
            xray_recorder.put_annotation('order_id', order_id)
            xray_recorder.put_annotation('service_name', 'payment-service')
            xray_recorder.put_annotation('payment_amount', amount)
            
        except Exception as e:
            xray_recorder.put_annotation('error', str(e))
            raise e
        finally:
            xray_recorder.end_subsegment()

    return {'statusCode': 200}
EOF
    
    # Inventory service code
    cat > inventory-service.py << 'EOF'
import json
import boto3
import os
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK calls for X-Ray tracing
patch_all()

eventbridge = boto3.client('events')

@xray_recorder.capture('inventory_service_handler')
def lambda_handler(event, context):
    for record in event['Records']:
        detail = json.loads(record['body'])
        
        subsegment = xray_recorder.begin_subsegment('update_inventory')
        
        try:
            order_id = detail['detail']['orderId']
            
            # Add metadata to trace
            subsegment.put_metadata('inventory_update', {
                'order_id': order_id,
                'items_reserved': 1,
                'warehouse': 'east-coast'
            })
            
            # Publish inventory updated event
            inventory_event = {
                'orderId': order_id,
                'status': 'reserved',
                'warehouse': 'east-coast'
            }
            
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'inventory.service',
                        'DetailType': 'Inventory Updated',
                        'Detail': json.dumps(inventory_event),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }
                ]
            )
            
            xray_recorder.put_annotation('order_id', order_id)
            xray_recorder.put_annotation('service_name', 'inventory-service')
            
        except Exception as e:
            xray_recorder.put_annotation('error', str(e))
            raise e
        finally:
            xray_recorder.end_subsegment()

    return {'statusCode': 200}
EOF
    
    # Notification service code
    cat > notification-service.py << 'EOF'
import json
import boto3
import os
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK calls for X-Ray tracing
patch_all()

@xray_recorder.capture('notification_service_handler')
def lambda_handler(event, context):
    for record in event['Records']:
        detail = json.loads(record['body'])
        
        subsegment = xray_recorder.begin_subsegment('send_notification')
        
        try:
            order_id = detail['detail']['orderId']
            event_type = detail['detail-type']
            
            # Add metadata to trace
            subsegment.put_metadata('notification_sent', {
                'order_id': order_id,
                'event_type': event_type,
                'channel': 'email'
            })
            
            xray_recorder.put_annotation('order_id', order_id)
            xray_recorder.put_annotation('service_name', 'notification-service')
            xray_recorder.put_annotation('notification_type', event_type)
            
        except Exception as e:
            xray_recorder.put_annotation('error', str(e))
            raise e
        finally:
            xray_recorder.end_subsegment()

    return {'statusCode': 200}
EOF
    
    log_success "Created Lambda function code files"
}

# Create and deploy Lambda functions
deploy_lambda_functions() {
    log_info "Creating and deploying Lambda functions..."
    
    local services=("order" "payment" "inventory" "notification")
    
    for service in "${services[@]}"; do
        log_info "Creating ${service} service deployment package..."
        
        # Create deployment package
        zip "${service}-service.zip" "${service}-service.py"
        
        # Create Lambda function with X-Ray tracing enabled
        aws lambda create-function \
            --function-name "${service}-service-${RANDOM_SUFFIX}" \
            --runtime python3.9 \
            --role "$LAMBDA_ROLE_ARN" \
            --handler "${service}-service.lambda_handler" \
            --zip-file "fileb://${service}-service.zip" \
            --environment "Variables={EVENT_BUS_NAME=$EVENT_BUS_NAME}" \
            --tracing-config Mode=Active \
            --timeout 30 \
            --tags Project=DistributedTracing,Environment=Demo
        
        log_success "Created ${service} service Lambda function"
    done
    
    # Store function ARNs
    export ORDER_SERVICE_ARN
    ORDER_SERVICE_ARN=$(aws lambda get-function \
        --function-name "order-service-${RANDOM_SUFFIX}" \
        --query Configuration.FunctionArn --output text)
    
    export PAYMENT_SERVICE_ARN
    PAYMENT_SERVICE_ARN=$(aws lambda get-function \
        --function-name "payment-service-${RANDOM_SUFFIX}" \
        --query Configuration.FunctionArn --output text)
    
    export INVENTORY_SERVICE_ARN
    INVENTORY_SERVICE_ARN=$(aws lambda get-function \
        --function-name "inventory-service-${RANDOM_SUFFIX}" \
        --query Configuration.FunctionArn --output text)
    
    export NOTIFICATION_SERVICE_ARN
    NOTIFICATION_SERVICE_ARN=$(aws lambda get-function \
        --function-name "notification-service-${RANDOM_SUFFIX}" \
        --query Configuration.FunctionArn --output text)
    
    log_success "All Lambda functions deployed successfully"
}

# Create EventBridge rules
create_eventbridge_rules() {
    log_info "Creating EventBridge rules..."
    
    # Create rule for payment processing
    aws events put-rule \
        --name "payment-processing-rule-${RANDOM_SUFFIX}" \
        --event-pattern '{
            "source": ["order.service"],
            "detail-type": ["Order Created"]
        }' \
        --state ENABLED \
        --event-bus-name "$EVENT_BUS_NAME" \
        --description "Routes order created events to payment service"
    
    # Create rule for inventory updates
    aws events put-rule \
        --name "inventory-update-rule-${RANDOM_SUFFIX}" \
        --event-pattern '{
            "source": ["order.service"],
            "detail-type": ["Order Created"]
        }' \
        --state ENABLED \
        --event-bus-name "$EVENT_BUS_NAME" \
        --description "Routes order created events to inventory service"
    
    # Create rule for notifications
    aws events put-rule \
        --name "notification-rule-${RANDOM_SUFFIX}" \
        --event-pattern '{
            "source": ["payment.service", "inventory.service"],
            "detail-type": ["Payment Processed", "Inventory Updated"]
        }' \
        --state ENABLED \
        --event-bus-name "$EVENT_BUS_NAME" \
        --description "Routes payment and inventory events to notification service"
    
    log_success "Created EventBridge rules"
}

# Configure EventBridge targets
configure_eventbridge_targets() {
    log_info "Configuring EventBridge targets..."
    
    # Add payment service as target
    aws events put-targets \
        --rule "payment-processing-rule-${RANDOM_SUFFIX}" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --targets "Id=1,Arn=${PAYMENT_SERVICE_ARN}"
    
    # Add inventory service as target
    aws events put-targets \
        --rule "inventory-update-rule-${RANDOM_SUFFIX}" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --targets "Id=1,Arn=${INVENTORY_SERVICE_ARN}"
    
    # Add notification service as target
    aws events put-targets \
        --rule "notification-rule-${RANDOM_SUFFIX}" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --targets "Id=1,Arn=${NOTIFICATION_SERVICE_ARN}"
    
    log_success "Configured EventBridge targets"
}

# Create API Gateway
create_api_gateway() {
    log_info "Creating API Gateway with X-Ray tracing..."
    
    # Create REST API
    export API_ID
    API_ID=$(aws apigateway create-rest-api \
        --name "$API_GATEWAY_NAME" \
        --description "Distributed tracing demo API" \
        --query id --output text)
    
    # Get root resource ID
    local root_id
    root_id=$(aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        --query 'items[0].id' --output text)
    
    # Create orders resource
    local orders_id
    orders_id=$(aws apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$root_id" \
        --path-part orders \
        --query id --output text)
    
    # Create customer resource
    local customer_id
    customer_id=$(aws apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$orders_id" \
        --path-part '{customerId}' \
        --query id --output text)
    
    # Create POST method
    aws apigateway put-method \
        --rest-api-id "$API_ID" \
        --resource-id "$customer_id" \
        --http-method POST \
        --authorization-type NONE
    
    # Configure Lambda integration
    aws apigateway put-integration \
        --rest-api-id "$API_ID" \
        --resource-id "$customer_id" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${ORDER_SERVICE_ARN}/invocations"
    
    # Create deployment
    local deployment_id
    deployment_id=$(aws apigateway create-deployment \
        --rest-api-id "$API_ID" \
        --stage-name prod \
        --query id --output text)
    
    # Enable X-Ray tracing
    aws apigateway put-stage \
        --rest-api-id "$API_ID" \
        --stage-name prod \
        --patch-ops '[{
            "op": "replace",
            "path": "/tracingEnabled",
            "value": "true"
        }]'
    
    export API_ENDPOINT
    API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/prod"
    
    log_success "Created API Gateway with X-Ray tracing enabled"
    log_info "API Endpoint: $API_ENDPOINT"
}

# Grant permissions
grant_permissions() {
    log_info "Granting EventBridge and API Gateway permissions..."
    
    # Grant API Gateway permission to invoke order service
    aws lambda add-permission \
        --function-name "order-service-${RANDOM_SUFFIX}" \
        --statement-id apigateway-invoke \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*/*"
    
    # Grant EventBridge permissions to invoke Lambda functions
    local services=("payment" "inventory" "notification")
    local rules=("payment-processing" "inventory-update" "notification")
    
    for i in "${!services[@]}"; do
        local service="${services[$i]}"
        local rule="${rules[$i]}"
        
        aws lambda add-permission \
            --function-name "${service}-service-${RANDOM_SUFFIX}" \
            --statement-id "eventbridge-invoke-${service}" \
            --action lambda:InvokeFunction \
            --principal events.amazonaws.com \
            --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENT_BUS_NAME}/${rule}-rule-${RANDOM_SUFFIX}"
    done
    
    log_success "Granted all necessary permissions"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
    "deploymentId": "${RANDOM_SUFFIX}",
    "region": "${AWS_REGION}",
    "accountId": "${AWS_ACCOUNT_ID}",
    "eventBusName": "${EVENT_BUS_NAME}",
    "lambdaRoleName": "${LAMBDA_ROLE_NAME}",
    "apiGatewayName": "${API_GATEWAY_NAME}",
    "apiId": "${API_ID}",
    "apiEndpoint": "${API_ENDPOINT}",
    "functions": {
        "orderService": "order-service-${RANDOM_SUFFIX}",
        "paymentService": "payment-service-${RANDOM_SUFFIX}",
        "inventoryService": "inventory-service-${RANDOM_SUFFIX}",
        "notificationService": "notification-service-${RANDOM_SUFFIX}"
    },
    "deployedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Test the deployment
test_deployment() {
    log_info "Testing the distributed tracing deployment..."
    
    # Wait for services to be ready
    log_info "Waiting 30 seconds for services to be ready..."
    sleep 30
    
    # Send test request
    log_info "Sending test request to API Gateway..."
    local response
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"productId": "12345", "quantity": 1}' \
        "${API_ENDPOINT}/orders/customer123" || echo "ERROR")
    
    if [[ "$response" == "ERROR" ]]; then
        log_warning "Test request failed. The deployment may need more time to be ready."
        log_info "You can test manually with: curl -X POST -H 'Content-Type: application/json' -d '{\"productId\": \"12345\", \"quantity\": 1}' '${API_ENDPOINT}/orders/customer123'"
    else
        log_success "Test request successful!"
        log_info "Response: $response"
    fi
    
    log_info "X-Ray traces will be available in 1-2 minutes at:"
    log_info "https://console.aws.amazon.com/xray/home?region=${AWS_REGION}#/service-map"
}

# Main deployment function
main() {
    log_info "Starting AWS Distributed Tracing with X-Ray deployment..."
    
    check_prerequisites
    setup_environment
    create_iam_role
    create_event_bus
    create_lambda_code
    deploy_lambda_functions
    create_eventbridge_rules
    configure_eventbridge_targets
    create_api_gateway
    grant_permissions
    save_deployment_info
    
    # Clean up temporary files
    rm -f ./*.py ./*.zip
    
    log_success "🎉 Deployment completed successfully!"
    echo
    log_info "📋 Deployment Summary:"
    log_info "   API Endpoint: $API_ENDPOINT"
    log_info "   Event Bus: $EVENT_BUS_NAME"
    log_info "   Resource Suffix: $RANDOM_SUFFIX"
    echo
    log_info "🧪 To test the system:"
    log_info "   curl -X POST -H 'Content-Type: application/json' \\"
    log_info "        -d '{\"productId\": \"12345\", \"quantity\": 1}' \\"
    log_info "        '${API_ENDPOINT}/orders/customer123'"
    echo
    log_info "📊 View X-Ray Service Map:"
    log_info "   https://console.aws.amazon.com/xray/home?region=${AWS_REGION}#/service-map"
    echo
    log_info "🗑️  To clean up resources, run: ./destroy.sh"
    
    test_deployment
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi