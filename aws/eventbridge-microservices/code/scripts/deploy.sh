#!/bin/bash

# Event-Driven Architecture with Amazon EventBridge - Deployment Script
# This script deploys a complete event-driven e-commerce architecture using EventBridge

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/tmp/eventbridge-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly REQUIRED_TOOLS=("aws" "jq" "zip")

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check logs at: $LOG_FILE"
    log_info "To clean up partial deployment, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Deploy Event-Driven Architecture with Amazon EventBridge

OPTIONS:
    -h, --help          Show this help message
    -r, --region        AWS region (default: from AWS CLI config)
    --dry-run           Show what would be deployed without making changes
    --skip-validation   Skip prerequisite validation
    --debug             Enable debug logging

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME --region us-west-2
    $SCRIPT_NAME --dry-run

EOF
}

# Default values
DRY_RUN=false
SKIP_VALIDATION=false
DEBUG=false
AWS_REGION=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --debug)
            DEBUG=true
            set -x
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validation functions
check_prerequisites() {
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        log_info "Skipping prerequisite validation"
        return 0
    fi

    log_info "Checking prerequisites..."

    # Check required tools
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed"
            exit 1
        fi
    done

    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI not configured. Run 'aws configure' first"
        exit 1
    fi

    # Check AWS permissions
    local test_actions=(
        "events:CreateEventBus"
        "lambda:CreateFunction"
        "iam:CreateRole"
        "sqs:CreateQueue"
        "logs:CreateLogGroup"
    )

    log_info "Validating AWS permissions..."
    for action in "${test_actions[@]}"; do
        if ! aws iam simulate-principal-policy \
            --policy-source-arn "$(aws sts get-caller-identity --query Arn --output text)" \
            --action-names "$action" \
            --query 'EvaluationResults[0].EvalDecision' \
            --output text 2>/dev/null | grep -q "allowed"; then
            log_warning "Permission check failed for: $action (continuing anyway)"
        fi
    done

    log_success "Prerequisites check completed"
}

# Resource creation functions
setup_environment() {
    log_info "Setting up environment variables..."

    # Set AWS region
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            log_error "AWS region not configured. Use --region option or configure AWS CLI"
            exit 1
        fi
    fi
    export AWS_REGION

    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    # Generate unique identifiers
    local random_string=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

    export CUSTOM_BUS_NAME="ecommerce-events-${random_string}"
    export LAMBDA_FUNCTION_PREFIX="eventbridge-demo-${random_string}"

    # Create deployment state directory
    mkdir -p .deployment-state
    cat > .deployment-state/config.env << EOF
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
AWS_REGION=$AWS_REGION
CUSTOM_BUS_NAME=$CUSTOM_BUS_NAME
LAMBDA_FUNCTION_PREFIX=$LAMBDA_FUNCTION_PREFIX
DEPLOYMENT_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
EOF

    log_success "Environment configured - Bus: $CUSTOM_BUS_NAME, Prefix: $LAMBDA_FUNCTION_PREFIX"
}

create_iam_role() {
    log_info "Creating IAM role for Lambda functions..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create IAM role: EventBridgeDemoLambdaRole"
        export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/EventBridgeDemoLambdaRole"
        return 0
    fi

    # Check if role already exists
    if aws iam get-role --role-name EventBridgeDemoLambdaRole &>/dev/null; then
        log_info "IAM role already exists, using existing role"
        export LAMBDA_ROLE_ARN=$(aws iam get-role --role-name EventBridgeDemoLambdaRole --query 'Role.Arn' --output text)
        echo "LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN" >> .deployment-state/config.env
        return 0
    fi

    # Create trust policy
    cat > .deployment-state/lambda-trust-policy.json << 'EOF'
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
    export LAMBDA_ROLE_ARN=$(aws iam create-role \
        --role-name EventBridgeDemoLambdaRole \
        --assume-role-policy-document file://.deployment-state/lambda-trust-policy.json \
        --tags Key=Purpose,Value=EventBridgeDemo Key=ManagedBy,Value=DeploymentScript \
        --query 'Role.Arn' --output text)

    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name EventBridgeDemoLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

    # Create custom policy for EventBridge interactions
    cat > .deployment-state/lambda-eventbridge-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "events:PutEvents",
                "events:ListRules",
                "events:DescribeRule"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF

    aws iam put-role-policy \
        --role-name EventBridgeDemoLambdaRole \
        --policy-name EventBridgeInteractionPolicy \
        --policy-document file://.deployment-state/lambda-eventbridge-policy.json

    # Save role ARN to state
    echo "LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN" >> .deployment-state/config.env

    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10

    log_success "IAM role created: $LAMBDA_ROLE_ARN"
}

create_event_bus() {
    log_info "Creating custom EventBridge event bus..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create event bus: $CUSTOM_BUS_NAME"
        return 0
    fi

    # Check if event bus already exists
    if aws events describe-event-bus --name "$CUSTOM_BUS_NAME" &>/dev/null; then
        log_info "Event bus already exists: $CUSTOM_BUS_NAME"
        return 0
    fi

    # Create custom event bus
    aws events create-event-bus \
        --name "$CUSTOM_BUS_NAME" \
        --tags Key=Purpose,Value=EcommerceDemoIntegration Key=ManagedBy,Value=DeploymentScript

    # Verify creation
    aws events describe-event-bus --name "$CUSTOM_BUS_NAME" --query 'Name' --output text

    log_success "Event bus created: $CUSTOM_BUS_NAME"
}

create_lambda_functions() {
    log_info "Creating Lambda functions..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Lambda functions with prefix: $LAMBDA_FUNCTION_PREFIX"
        return 0
    fi

    # Create deployment package directory
    mkdir -p .deployment-state/lambda-packages

    # Create order processor Lambda
    cat > .deployment-state/lambda-packages/order_processor.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    print(f"Processing order event: {json.dumps(event, indent=2)}")
    
    # Extract order details from the event
    order_details = event.get('detail', {})
    order_id = order_details.get('orderId', 'unknown')
    customer_id = order_details.get('customerId', 'unknown')
    total_amount = order_details.get('totalAmount', 0)
    
    try:
        # Simulate order processing logic
        print(f"Processing order {order_id} for customer {customer_id}")
        print(f"Order total: ${total_amount}")
        
        # Emit order processed event
        response = eventbridge.put_events(
            Entries=[
                {
                    'Source': 'ecommerce.order',
                    'DetailType': 'Order Processed',
                    'Detail': json.dumps({
                        'orderId': order_id,
                        'customerId': customer_id,
                        'totalAmount': total_amount,
                        'status': 'processed',
                        'timestamp': datetime.utcnow().isoformat()
                    }),
                    'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                }
            ]
        )
        
        print(f"Emitted order processed event: {response}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Order {order_id} processed successfully',
                'eventId': response['Entries'][0]['EventId']
            })
        }
        
    except Exception as e:
        print(f"Error processing order: {str(e)}")
        
        # Emit order failed event
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'ecommerce.order',
                    'DetailType': 'Order Processing Failed',
                    'Detail': json.dumps({
                        'orderId': order_id,
                        'customerId': customer_id,
                        'error': str(e),
                        'timestamp': datetime.utcnow().isoformat()
                    }),
                    'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                }
            ]
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF

    # Package and deploy order processing Lambda
    (cd .deployment-state/lambda-packages && zip -q order-processor.zip order_processor.py)

    if ! aws lambda get-function --function-name "${LAMBDA_FUNCTION_PREFIX}-order-processor" &>/dev/null; then
        export ORDER_LAMBDA_ARN=$(aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_PREFIX}-order-processor" \
            --runtime python3.9 \
            --role "$LAMBDA_ROLE_ARN" \
            --handler order_processor.lambda_handler \
            --zip-file fileb://.deployment-state/lambda-packages/order-processor.zip \
            --timeout 30 \
            --environment Variables="{EVENT_BUS_NAME=$CUSTOM_BUS_NAME}" \
            --tags Purpose=EventBridgeDemo,ManagedBy=DeploymentScript \
            --query 'FunctionArn' --output text)
        
        log_success "Order processing Lambda created: $ORDER_LAMBDA_ARN"
    else
        export ORDER_LAMBDA_ARN=$(aws lambda get-function --function-name "${LAMBDA_FUNCTION_PREFIX}-order-processor" --query 'Configuration.FunctionArn' --output text)
        log_info "Order processing Lambda already exists: $ORDER_LAMBDA_ARN"
    fi

    # Create inventory manager Lambda
    cat > .deployment-state/lambda-packages/inventory_manager.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    print(f"Processing inventory event: {json.dumps(event, indent=2)}")
    
    # Extract order details from the event
    order_details = event.get('detail', {})
    order_id = order_details.get('orderId', 'unknown')
    
    try:
        # Simulate inventory check and reservation
        print(f"Checking inventory for order {order_id}")
        
        # Simulate inventory availability (randomize for demo)
        import random
        inventory_available = random.choice([True, True, True, False])  # 75% success rate
        
        if inventory_available:
            # Emit inventory reserved event
            response = eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'ecommerce.inventory',
                        'DetailType': 'Inventory Reserved',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'status': 'reserved',
                            'reservationId': f"res-{order_id}-{int(datetime.now().timestamp())}",
                            'timestamp': datetime.utcnow().isoformat()
                        }),
                        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Inventory reserved for order {order_id}',
                    'eventId': response['Entries'][0]['EventId']
                })
            }
        else:
            # Emit inventory unavailable event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'ecommerce.inventory',
                        'DetailType': 'Inventory Unavailable',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'status': 'unavailable',
                            'reason': 'Insufficient stock',
                            'timestamp': datetime.utcnow().isoformat()
                        }),
                        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Inventory unavailable for order {order_id}'
                })
            }
        
    except Exception as e:
        print(f"Error managing inventory: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF

    # Package and deploy inventory management Lambda
    (cd .deployment-state/lambda-packages && zip -q inventory-manager.zip inventory_manager.py)

    if ! aws lambda get-function --function-name "${LAMBDA_FUNCTION_PREFIX}-inventory-manager" &>/dev/null; then
        export INVENTORY_LAMBDA_ARN=$(aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_PREFIX}-inventory-manager" \
            --runtime python3.9 \
            --role "$LAMBDA_ROLE_ARN" \
            --handler inventory_manager.lambda_handler \
            --zip-file fileb://.deployment-state/lambda-packages/inventory-manager.zip \
            --timeout 30 \
            --environment Variables="{EVENT_BUS_NAME=$CUSTOM_BUS_NAME}" \
            --tags Purpose=EventBridgeDemo,ManagedBy=DeploymentScript \
            --query 'FunctionArn' --output text)
        
        log_success "Inventory management Lambda created: $INVENTORY_LAMBDA_ARN"
    else
        export INVENTORY_LAMBDA_ARN=$(aws lambda get-function --function-name "${LAMBDA_FUNCTION_PREFIX}-inventory-manager" --query 'Configuration.FunctionArn' --output text)
        log_info "Inventory management Lambda already exists: $INVENTORY_LAMBDA_ARN"
    fi

    # Create event generator Lambda
    cat > .deployment-state/lambda-packages/event_generator.py << 'EOF'
import json
import boto3
import os
from datetime import datetime
import random

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    # Generate sample order data
    order_id = f"ord-{int(datetime.now().timestamp())}-{random.randint(1000, 9999)}"
    customer_id = f"cust-{random.randint(1000, 9999)}"
    total_amount = round(random.uniform(25.99, 299.99), 2)
    
    # Create order event
    order_event = {
        'Source': 'ecommerce.api',
        'DetailType': 'Order Created',
        'Detail': json.dumps({
            'orderId': order_id,
            'customerId': customer_id,
            'totalAmount': total_amount,
            'items': [
                {
                    'productId': f'prod-{random.randint(100, 999)}',
                    'quantity': random.randint(1, 3),
                    'price': round(total_amount / random.randint(1, 3), 2)
                }
            ],
            'timestamp': datetime.utcnow().isoformat()
        }),
        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
    }
    
    try:
        response = eventbridge.put_events(Entries=[order_event])
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Order event generated successfully',
                'orderId': order_id,
                'eventId': response['Entries'][0]['EventId']
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF

    # Package and deploy event generator Lambda
    (cd .deployment-state/lambda-packages && zip -q event-generator.zip event_generator.py)

    if ! aws lambda get-function --function-name "${LAMBDA_FUNCTION_PREFIX}-event-generator" &>/dev/null; then
        export EVENT_GENERATOR_ARN=$(aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_PREFIX}-event-generator" \
            --runtime python3.9 \
            --role "$LAMBDA_ROLE_ARN" \
            --handler event_generator.lambda_handler \
            --zip-file fileb://.deployment-state/lambda-packages/event-generator.zip \
            --timeout 30 \
            --environment Variables="{EVENT_BUS_NAME=$CUSTOM_BUS_NAME}" \
            --tags Purpose=EventBridgeDemo,ManagedBy=DeploymentScript \
            --query 'FunctionArn' --output text)
        
        log_success "Event generator Lambda created: $EVENT_GENERATOR_ARN"
    else
        export EVENT_GENERATOR_ARN=$(aws lambda get-function --function-name "${LAMBDA_FUNCTION_PREFIX}-event-generator" --query 'Configuration.FunctionArn' --output text)
        log_info "Event generator Lambda already exists: $EVENT_GENERATOR_ARN"
    fi

    # Save Lambda ARNs to state
    cat >> .deployment-state/config.env << EOF
ORDER_LAMBDA_ARN=$ORDER_LAMBDA_ARN
INVENTORY_LAMBDA_ARN=$INVENTORY_LAMBDA_ARN
EVENT_GENERATOR_ARN=$EVENT_GENERATOR_ARN
EOF
}

create_sqs_queue() {
    log_info "Creating SQS queue for payment processing..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create SQS queue: ${LAMBDA_FUNCTION_PREFIX}-payment-processing"
        return 0
    fi

    # Check if queue already exists
    if aws sqs get-queue-url --queue-name "${LAMBDA_FUNCTION_PREFIX}-payment-processing" &>/dev/null; then
        export PAYMENT_QUEUE_URL=$(aws sqs get-queue-url --queue-name "${LAMBDA_FUNCTION_PREFIX}-payment-processing" --query 'QueueUrl' --output text)
        log_info "SQS queue already exists: $PAYMENT_QUEUE_URL"
    else
        # Create SQS queue
        export PAYMENT_QUEUE_URL=$(aws sqs create-queue \
            --queue-name "${LAMBDA_FUNCTION_PREFIX}-payment-processing" \
            --attributes DelaySeconds=30,VisibilityTimeoutSeconds=300 \
            --tags Purpose=EventBridgeDemo,ManagedBy=DeploymentScript \
            --query 'QueueUrl' --output text)
        
        log_success "SQS queue created: $PAYMENT_QUEUE_URL"
    fi

    export PAYMENT_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$PAYMENT_QUEUE_URL" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)

    # Save queue details to state
    cat >> .deployment-state/config.env << EOF
PAYMENT_QUEUE_URL=$PAYMENT_QUEUE_URL
PAYMENT_QUEUE_ARN=$PAYMENT_QUEUE_ARN
EOF
}

create_cloudwatch_logs() {
    log_info "Creating CloudWatch log group for monitoring..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create CloudWatch log group: /aws/events/${CUSTOM_BUS_NAME}"
        return 0
    fi

    # Create CloudWatch log group
    if ! aws logs describe-log-groups --log-group-name-prefix "/aws/events/${CUSTOM_BUS_NAME}" --query 'logGroups[0]' --output text | grep -q "/aws/events/${CUSTOM_BUS_NAME}"; then
        aws logs create-log-group \
            --log-group-name "/aws/events/${CUSTOM_BUS_NAME}" \
            --tags Purpose=EventBridgeDemo,ManagedBy=DeploymentScript

        log_success "CloudWatch log group created: /aws/events/${CUSTOM_BUS_NAME}"
    else
        log_info "CloudWatch log group already exists: /aws/events/${CUSTOM_BUS_NAME}"
    fi

    export LOG_GROUP_ARN=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/events/${CUSTOM_BUS_NAME}" \
        --query 'logGroups[0].arn' --output text)

    # Save log group ARN to state
    echo "LOG_GROUP_ARN=$LOG_GROUP_ARN" >> .deployment-state/config.env
}

create_eventbridge_rules() {
    log_info "Creating EventBridge rules for event routing..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create EventBridge rules"
        return 0
    fi

    # Create rule patterns directory
    mkdir -p .deployment-state/rule-patterns

    # Rule 1: Route new orders to order processing Lambda
    cat > .deployment-state/rule-patterns/order-rule-pattern.json << 'EOF'
{
    "source": ["ecommerce.api"],
    "detail-type": ["Order Created"],
    "detail": {
        "totalAmount": [{"numeric": [">", 0]}]
    }
}
EOF

    if ! aws events describe-rule --name "${LAMBDA_FUNCTION_PREFIX}-order-processing-rule" --event-bus-name "$CUSTOM_BUS_NAME" &>/dev/null; then
        aws events put-rule \
            --name "${LAMBDA_FUNCTION_PREFIX}-order-processing-rule" \
            --event-pattern file://.deployment-state/rule-patterns/order-rule-pattern.json \
            --state ENABLED \
            --event-bus-name "$CUSTOM_BUS_NAME" \
            --description "Route new orders to processing Lambda" \
            --tags Purpose=EventBridgeDemo,ManagedBy=DeploymentScript

        # Add Lambda permission
        aws lambda add-permission \
            --function-name "${LAMBDA_FUNCTION_PREFIX}-order-processor" \
            --statement-id allow-eventbridge-order-rule \
            --action lambda:InvokeFunction \
            --principal events.amazonaws.com \
            --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${CUSTOM_BUS_NAME}/${LAMBDA_FUNCTION_PREFIX}-order-processing-rule" \
            --output text 2>/dev/null || log_warning "Lambda permission already exists"

        # Add target
        aws events put-targets \
            --rule "${LAMBDA_FUNCTION_PREFIX}-order-processing-rule" \
            --event-bus-name "$CUSTOM_BUS_NAME" \
            --targets "Id"="1","Arn"="$ORDER_LAMBDA_ARN"

        log_success "Order processing rule created"
    else
        log_info "Order processing rule already exists"
    fi

    # Rule 2: Route processed orders to inventory management
    cat > .deployment-state/rule-patterns/inventory-rule-pattern.json << 'EOF'
{
    "source": ["ecommerce.order"],
    "detail-type": ["Order Processed"],
    "detail": {
        "status": ["processed"]
    }
}
EOF

    if ! aws events describe-rule --name "${LAMBDA_FUNCTION_PREFIX}-inventory-check-rule" --event-bus-name "$CUSTOM_BUS_NAME" &>/dev/null; then
        aws events put-rule \
            --name "${LAMBDA_FUNCTION_PREFIX}-inventory-check-rule" \
            --event-pattern file://.deployment-state/rule-patterns/inventory-rule-pattern.json \
            --state ENABLED \
            --event-bus-name "$CUSTOM_BUS_NAME" \
            --description "Route processed orders to inventory check" \
            --tags Purpose=EventBridgeDemo,ManagedBy=DeploymentScript

        # Add Lambda permission
        aws lambda add-permission \
            --function-name "${LAMBDA_FUNCTION_PREFIX}-inventory-manager" \
            --statement-id allow-eventbridge-inventory-rule \
            --action lambda:InvokeFunction \
            --principal events.amazonaws.com \
            --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${CUSTOM_BUS_NAME}/${LAMBDA_FUNCTION_PREFIX}-inventory-check-rule" \
            --output text 2>/dev/null || log_warning "Lambda permission already exists"

        # Add target
        aws events put-targets \
            --rule "${LAMBDA_FUNCTION_PREFIX}-inventory-check-rule" \
            --event-bus-name "$CUSTOM_BUS_NAME" \
            --targets "Id"="1","Arn"="$INVENTORY_LAMBDA_ARN"

        log_success "Inventory check rule created"
    else
        log_info "Inventory check rule already exists"
    fi

    # Rule 3: Route inventory reserved events to payment processing
    cat > .deployment-state/rule-patterns/payment-rule-pattern.json << 'EOF'
{
    "source": ["ecommerce.inventory"],
    "detail-type": ["Inventory Reserved"],
    "detail": {
        "status": ["reserved"]
    }
}
EOF

    if ! aws events describe-rule --name "${LAMBDA_FUNCTION_PREFIX}-payment-processing-rule" --event-bus-name "$CUSTOM_BUS_NAME" &>/dev/null; then
        aws events put-rule \
            --name "${LAMBDA_FUNCTION_PREFIX}-payment-processing-rule" \
            --event-pattern file://.deployment-state/rule-patterns/payment-rule-pattern.json \
            --state ENABLED \
            --event-bus-name "$CUSTOM_BUS_NAME" \
            --description "Route inventory reserved events to payment" \
            --tags Purpose=EventBridgeDemo,ManagedBy=DeploymentScript

        # Add SQS permission
        aws sqs add-permission \
            --queue-url "$PAYMENT_QUEUE_URL" \
            --label allow-eventbridge-payment-rule \
            --aws-account-ids "$AWS_ACCOUNT_ID" \
            --actions SendMessage 2>/dev/null || log_warning "SQS permission already exists"

        # Add target
        aws events put-targets \
            --rule "${LAMBDA_FUNCTION_PREFIX}-payment-processing-rule" \
            --event-bus-name "$CUSTOM_BUS_NAME" \
            --targets "Id"="1","Arn"="$PAYMENT_QUEUE_ARN"

        log_success "Payment processing rule created"
    else
        log_info "Payment processing rule already exists"
    fi

    # Rule 4: Archive all events to CloudWatch Logs for monitoring
    cat > .deployment-state/rule-patterns/monitoring-rule-pattern.json << 'EOF'
{
    "source": [{"prefix": "ecommerce."}]
}
EOF

    if ! aws events describe-rule --name "${LAMBDA_FUNCTION_PREFIX}-monitoring-rule" --event-bus-name "$CUSTOM_BUS_NAME" &>/dev/null; then
        aws events put-rule \
            --name "${LAMBDA_FUNCTION_PREFIX}-monitoring-rule" \
            --event-pattern file://.deployment-state/rule-patterns/monitoring-rule-pattern.json \
            --state ENABLED \
            --event-bus-name "$CUSTOM_BUS_NAME" \
            --description "Archive all ecommerce events for monitoring" \
            --tags Purpose=EventBridgeDemo,ManagedBy=DeploymentScript

        # Add target
        aws events put-targets \
            --rule "${LAMBDA_FUNCTION_PREFIX}-monitoring-rule" \
            --event-bus-name "$CUSTOM_BUS_NAME" \
            --targets "Id"="1","Arn"="$LOG_GROUP_ARN"

        log_success "Monitoring rule created"
    else
        log_info "Monitoring rule already exists"
    fi
}

test_deployment() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run deployment tests"
        return 0
    fi

    log_info "Testing event-driven architecture deployment..."

    # Wait for eventual consistency
    sleep 5

    # Generate a test event
    log_info "Generating test order event..."
    local result=$(aws lambda invoke \
        --function-name "${LAMBDA_FUNCTION_PREFIX}-event-generator" \
        --payload '{}' \
        --cli-binary-format raw-in-base64-out \
        .deployment-state/test-response.json 2>&1)

    if [[ $? -eq 0 ]]; then
        log_success "Test event generated successfully"
        if [[ -f .deployment-state/test-response.json ]]; then
            local response=$(cat .deployment-state/test-response.json)
            log_info "Test response: $response"
        fi
    else
        log_warning "Test event generation failed: $result"
    fi

    # Verify EventBridge rules
    local rule_count=$(aws events list-rules --event-bus-name "$CUSTOM_BUS_NAME" --query 'length(Rules)' --output text)
    log_info "Created $rule_count EventBridge rules"

    # Verify Lambda functions
    local lambda_count=0
    for func in "${LAMBDA_FUNCTION_PREFIX}-order-processor" "${LAMBDA_FUNCTION_PREFIX}-inventory-manager" "${LAMBDA_FUNCTION_PREFIX}-event-generator"; do
        if aws lambda get-function --function-name "$func" &>/dev/null; then
            ((lambda_count++))
        fi
    done
    log_info "Created $lambda_count Lambda functions"
}

generate_deployment_summary() {
    log_info "Generating deployment summary..."

    cat > .deployment-state/deployment-summary.md << EOF
# EventBridge Event-Driven Architecture Deployment Summary

## Deployment Information
- **Deployment Time**: $(date '+%Y-%m-%d %H:%M:%S')
- **AWS Region**: $AWS_REGION
- **AWS Account**: $AWS_ACCOUNT_ID

## Created Resources

### EventBridge
- **Custom Event Bus**: $CUSTOM_BUS_NAME
- **Rules**: 4 routing rules created

### Lambda Functions
- **Order Processor**: ${LAMBDA_FUNCTION_PREFIX}-order-processor
- **Inventory Manager**: ${LAMBDA_FUNCTION_PREFIX}-inventory-manager
- **Event Generator**: ${LAMBDA_FUNCTION_PREFIX}-event-generator

### Supporting Resources
- **SQS Queue**: ${LAMBDA_FUNCTION_PREFIX}-payment-processing
- **CloudWatch Log Group**: /aws/events/${CUSTOM_BUS_NAME}
- **IAM Role**: EventBridgeDemoLambdaRole

## Testing the Architecture

1. Generate a test event:
   \`\`\`bash
   aws lambda invoke \\
       --function-name ${LAMBDA_FUNCTION_PREFIX}-event-generator \\
       --payload '{}' \\
       --cli-binary-format raw-in-base64-out \\
       response.json
   \`\`\`

2. Check CloudWatch logs for event processing:
   \`\`\`bash
   aws logs describe-log-streams \\
       --log-group-name /aws/lambda/${LAMBDA_FUNCTION_PREFIX}-order-processor \\
       --order-by LastEventTime --descending --max-items 1
   \`\`\`

3. Check SQS queue for payment messages:
   \`\`\`bash
   aws sqs receive-message --queue-url $PAYMENT_QUEUE_URL
   \`\`\`

## Cleanup

To remove all resources, run:
\`\`\`bash
./destroy.sh
\`\`\`

## Estimated Costs

- EventBridge: ~\$1.00/million events
- Lambda: ~\$0.20/million requests + compute time
- SQS: ~\$0.40/million requests
- CloudWatch Logs: ~\$0.50/GB ingested

For detailed pricing, see [AWS Pricing Calculator](https://calculator.aws).
EOF

    log_success "Deployment summary saved to .deployment-state/deployment-summary.md"
}

# Main deployment flow
main() {
    log_info "Starting Event-Driven Architecture deployment..."
    log_info "Log file: $LOG_FILE"

    check_prerequisites
    setup_environment
    create_iam_role
    create_event_bus
    create_lambda_functions
    create_sqs_queue
    create_cloudwatch_logs
    create_eventbridge_rules
    test_deployment
    generate_deployment_summary

    log_success "Event-Driven Architecture deployment completed successfully!"
    log_info "Check .deployment-state/deployment-summary.md for details"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo
        echo "🎉 Your event-driven architecture is ready!"
        echo "📋 Custom Event Bus: $CUSTOM_BUS_NAME"
        echo "🔧 Lambda Function Prefix: $LAMBDA_FUNCTION_PREFIX"
        echo "📊 Test with: aws lambda invoke --function-name ${LAMBDA_FUNCTION_PREFIX}-event-generator --payload '{}' response.json"
        echo "🧹 Cleanup with: ./destroy.sh"
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi