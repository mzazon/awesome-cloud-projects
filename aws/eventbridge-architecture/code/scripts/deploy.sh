#!/bin/bash

# Deploy script for Event-Driven Architecture with EventBridge
# This script deploys the complete event-driven architecture infrastructure

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
DEFAULT_REGION="us-east-1"
DEFAULT_STACK_NAME="eventbridge-architecture"

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --region REGION          AWS region (default: $DEFAULT_REGION)"
    echo "  --stack-name NAME        Stack name prefix (default: $DEFAULT_STACK_NAME)"
    echo "  --dry-run               Show what would be created without making changes"
    echo "  --skip-confirmation     Skip confirmation prompts"
    echo "  --help                  Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  AWS_REGION              AWS region"
    echo "  AWS_PROFILE             AWS profile to use"
    echo "  DRY_RUN                 Set to 'true' for dry run mode"
    echo "  SKIP_CONFIRMATION       Set to 'true' to skip confirmations"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            log_error "Unknown parameter: $1"
            usage
            ;;
    esac
done

# Set defaults if not provided
AWS_REGION=${AWS_REGION:-$DEFAULT_REGION}
STACK_NAME=${STACK_NAME:-$DEFAULT_STACK_NAME}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it and try again."
        exit 1
    fi
    
    # Check if Python3 is installed
    if ! command -v python3 &> /dev/null; then
        log_error "Python3 is not installed. Please install it and try again."
        exit 1
    fi
    
    # Check if pip3 is installed
    if ! command -v pip3 &> /dev/null; then
        log_error "pip3 is not installed. Please install it and try again."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' and try again."
        exit 1
    fi
    
    # Check if boto3 is installed
    if ! python3 -c "import boto3" &> /dev/null; then
        log_warning "boto3 is not installed. Installing now..."
        pip3 install boto3
    fi
    
    log_success "Prerequisites check passed"
}

# Display deployment information
display_deployment_info() {
    log_info "=== Deployment Configuration ==="
    log_info "AWS Region: $AWS_REGION"
    log_info "Stack Name: $STACK_NAME"
    log_info "Dry Run: $DRY_RUN"
    log_info "Script Directory: $SCRIPT_DIR"
    log_info "Project Directory: $PROJECT_DIR"
    
    # Get AWS account info
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    log_info "AWS Account ID: $account_id"
    log_info "AWS User/Role: $user_arn"
    log_info "================================="
}

# Generate unique resource names
generate_resource_names() {
    log_info "Generating unique resource names..."
    
    # Generate random suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    # Export resource names
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export EVENT_BUS_NAME="ecommerce-events-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="order-notifications-${RANDOM_SUFFIX}"
    export SQS_QUEUE_NAME="event-processing-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="event-processor-${RANDOM_SUFFIX}"
    
    log_success "Resource names generated"
    log_info "Event Bus: $EVENT_BUS_NAME"
    log_info "SNS Topic: $SNS_TOPIC_NAME"
    log_info "SQS Queue: $SQS_QUEUE_NAME"
    log_info "Lambda Function: $LAMBDA_FUNCTION_NAME"
}

# Create EventBridge custom event bus
create_event_bus() {
    log_info "Creating EventBridge custom event bus..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create event bus: $EVENT_BUS_NAME"
        return 0
    fi
    
    aws events create-event-bus \
        --name "$EVENT_BUS_NAME" \
        --tags Key=Name,Value="$EVENT_BUS_NAME" \
               Key=Purpose,Value=ECommerce-Events \
               Key=DeployedBy,Value=deploy-script
    
    export EVENT_BUS_ARN=$(aws events describe-event-bus \
        --name "$EVENT_BUS_NAME" \
        --query 'Arn' --output text)
    
    log_success "Created EventBridge event bus: $EVENT_BUS_NAME"
}

# Create SNS topic and SQS queue
create_messaging_resources() {
    log_info "Creating SNS topic and SQS queue..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create SNS topic: $SNS_TOPIC_NAME"
        log_info "[DRY RUN] Would create SQS queue: $SQS_QUEUE_NAME"
        return 0
    fi
    
    # Create SNS topic
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query 'TopicArn' --output text)
    
    # Create SQS queue
    export SQS_QUEUE_URL=$(aws sqs create-queue \
        --queue-name "$SQS_QUEUE_NAME" \
        --attributes '{
          "VisibilityTimeoutSeconds": "300",
          "MessageRetentionPeriod": "1209600"
        }' \
        --query 'QueueUrl' --output text)
    
    # Get SQS queue ARN
    export SQS_QUEUE_ARN=$(aws sqs get-queue-attributes \
        --queue-url "$SQS_QUEUE_URL" \
        --attribute-names QueueArn \
        --query 'Attributes.QueueArn' --output text)
    
    log_success "Created SNS topic: $SNS_TOPIC_ARN"
    log_success "Created SQS queue: $SQS_QUEUE_ARN"
}

# Create IAM roles
create_iam_roles() {
    log_info "Creating IAM roles..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create IAM roles for EventBridge and Lambda"
        return 0
    fi
    
    # Create EventBridge trust policy
    cat > "$PROJECT_DIR/eventbridge-trust-policy.json" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create EventBridge IAM role
    aws iam create-role \
        --role-name "EventBridgeExecutionRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document "file://$PROJECT_DIR/eventbridge-trust-policy.json" \
        --tags Key=Name,Value="EventBridgeExecutionRole-${RANDOM_SUFFIX}" \
               Key=DeployedBy,Value=deploy-script
    
    # Create EventBridge targets policy
    cat > "$PROJECT_DIR/eventbridge-targets-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "$SNS_TOPIC_ARN"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage"
      ],
      "Resource": "$SQS_QUEUE_ARN"
    },
    {
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "EventBridgeExecutionRole-${RANDOM_SUFFIX}" \
        --policy-name EventBridgeTargetsPolicy \
        --policy-document "file://$PROJECT_DIR/eventbridge-targets-policy.json"
    
    export EVENTBRIDGE_ROLE_ARN=$(aws iam get-role \
        --role-name "EventBridgeExecutionRole-${RANDOM_SUFFIX}" \
        --query 'Role.Arn' --output text)
    
    # Create Lambda trust policy
    cat > "$PROJECT_DIR/lambda-trust-policy.json" << 'EOF'
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
    
    # Create Lambda IAM role
    aws iam create-role \
        --role-name "EventProcessorLambdaRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document "file://$PROJECT_DIR/lambda-trust-policy.json" \
        --tags Key=Name,Value="EventProcessorLambdaRole-${RANDOM_SUFFIX}" \
               Key=DeployedBy,Value=deploy-script
    
    aws iam attach-role-policy \
        --role-name "EventProcessorLambdaRole-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "EventProcessorLambdaRole-${RANDOM_SUFFIX}" \
        --query 'Role.Arn' --output text)
    
    # Wait for IAM roles to be available
    log_info "Waiting for IAM roles to be available..."
    sleep 10
    
    log_success "Created IAM roles"
}

# Create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    # Create Lambda function code
    cat > "$PROJECT_DIR/event_processor.py" << 'EOF'
import json
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Process EventBridge events"""
    
    try:
        logger.info(f"Received event: {json.dumps(event, indent=2)}")
        
        # Extract event details
        event_source = event.get('source', 'unknown')
        event_type = event.get('detail-type', 'unknown')
        event_detail = event.get('detail', {})
        
        # Process based on event type
        result = process_event(event_source, event_type, event_detail)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'eventSource': event_source,
                'eventType': event_type,
                'result': result,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def process_event(source, event_type, detail):
    """Process different types of events"""
    
    if source == 'ecommerce.orders':
        return process_order_event(event_type, detail)
    elif source == 'ecommerce.users':
        return process_user_event(event_type, detail)
    elif source == 'ecommerce.payments':
        return process_payment_event(event_type, detail)
    else:
        return process_generic_event(event_type, detail)

def process_order_event(event_type, detail):
    """Process order-related events"""
    
    if event_type == 'Order Created':
        order_id = detail.get('orderId')
        customer_id = detail.get('customerId')
        total_amount = detail.get('totalAmount', 0)
        
        logger.info(f"Processing new order: {order_id} for customer {customer_id}")
        
        return {
            'action': 'order_processed',
            'orderId': order_id,
            'customerId': customer_id,
            'totalAmount': total_amount,
            'priority': 'high' if total_amount > 1000 else 'normal'
        }
        
    elif event_type == 'Order Cancelled':
        order_id = detail.get('orderId')
        logger.info(f"Processing order cancellation: {order_id}")
        
        return {
            'action': 'order_cancelled',
            'orderId': order_id
        }
    
    return {'action': 'order_event_processed'}

def process_user_event(event_type, detail):
    """Process user-related events"""
    
    if event_type == 'User Registered':
        user_id = detail.get('userId')
        email = detail.get('email')
        
        logger.info(f"Processing new user registration: {user_id}")
        
        return {
            'action': 'user_registered',
            'userId': user_id,
            'email': email,
            'welcomeEmailSent': True
        }
    
    return {'action': 'user_event_processed'}

def process_payment_event(event_type, detail):
    """Process payment-related events"""
    
    if event_type == 'Payment Processed':
        payment_id = detail.get('paymentId')
        amount = detail.get('amount')
        
        logger.info(f"Processing payment: {payment_id} for amount {amount}")
        
        return {
            'action': 'payment_processed',
            'paymentId': payment_id,
            'amount': amount
        }
    
    return {'action': 'payment_event_processed'}

def process_generic_event(event_type, detail):
    """Process generic events"""
    
    logger.info(f"Processing generic event: {event_type}")
    
    return {
        'action': 'generic_event_processed',
        'eventType': event_type
    }
EOF
    
    # Create deployment package
    cd "$PROJECT_DIR"
    zip event_processor.zip event_processor.py
    
    # Create Lambda function
    export LAMBDA_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler event_processor.lambda_handler \
        --zip-file fileb://event_processor.zip \
        --timeout 30 \
        --memory-size 256 \
        --tags DeployedBy=deploy-script \
        --query 'FunctionArn' --output text)
    
    log_success "Created Lambda function: $LAMBDA_FUNCTION_ARN"
}

# Create EventBridge rules
create_eventbridge_rules() {
    log_info "Creating EventBridge rules..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create EventBridge rules"
        return 0
    fi
    
    # Rule 1: Route all order events to Lambda
    aws events put-rule \
        --name "OrderEventsRule-${RANDOM_SUFFIX}" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --event-pattern '{
          "source": ["ecommerce.orders"],
          "detail-type": ["Order Created", "Order Updated", "Order Cancelled"]
        }' \
        --description "Route order events to Lambda processor"
    
    # Add Lambda target to order events rule
    aws events put-targets \
        --rule "OrderEventsRule-${RANDOM_SUFFIX}" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --targets "Id"="1","Arn"="$LAMBDA_FUNCTION_ARN"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id "allow-eventbridge-order-events-${RANDOM_SUFFIX}" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:$AWS_REGION:$AWS_ACCOUNT_ID:rule/$EVENT_BUS_NAME/OrderEventsRule-${RANDOM_SUFFIX}"
    
    # Rule 2: Route high-value orders to SNS
    aws events put-rule \
        --name "HighValueOrdersRule-${RANDOM_SUFFIX}" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --event-pattern '{
          "source": ["ecommerce.orders"],
          "detail-type": ["Order Created"],
          "detail": {
            "totalAmount": [{"numeric": [">", 1000]}]
          }
        }' \
        --description "Route high-value orders to SNS for notifications"
    
    # Add SNS target to high-value orders rule
    aws events put-targets \
        --rule "HighValueOrdersRule-${RANDOM_SUFFIX}" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --targets "Id"="1","Arn"="$SNS_TOPIC_ARN","RoleArn"="$EVENTBRIDGE_ROLE_ARN"
    
    # Rule 3: Route all events to SQS
    aws events put-rule \
        --name "AllEventsToSQSRule-${RANDOM_SUFFIX}" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --event-pattern '{
          "source": ["ecommerce.orders", "ecommerce.users", "ecommerce.payments"]
        }' \
        --description "Route all events to SQS for batch processing"
    
    # Add SQS target to all events rule
    aws events put-targets \
        --rule "AllEventsToSQSRule-${RANDOM_SUFFIX}" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --targets "Id"="1","Arn"="$SQS_QUEUE_ARN","RoleArn"="$EVENTBRIDGE_ROLE_ARN"
    
    # Rule 4: Route user registration events to Lambda
    aws events put-rule \
        --name "UserRegistrationRule-${RANDOM_SUFFIX}" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --event-pattern '{
          "source": ["ecommerce.users"],
          "detail-type": ["User Registered"]
        }' \
        --description "Route user registration events to Lambda"
    
    # Add Lambda target to user registration rule
    aws events put-targets \
        --rule "UserRegistrationRule-${RANDOM_SUFFIX}" \
        --event-bus-name "$EVENT_BUS_NAME" \
        --targets "Id"="1","Arn"="$LAMBDA_FUNCTION_ARN"
    
    # Grant EventBridge permission to invoke Lambda for user events
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id "allow-eventbridge-user-events-${RANDOM_SUFFIX}" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:$AWS_REGION:$AWS_ACCOUNT_ID:rule/$EVENT_BUS_NAME/UserRegistrationRule-${RANDOM_SUFFIX}"
    
    log_success "Created EventBridge rules"
}

# Create utility scripts
create_utility_scripts() {
    log_info "Creating utility scripts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create utility scripts"
        return 0
    fi
    
    # Create event publisher script
    cat > "$PROJECT_DIR/event_publisher.py" << EOF
#!/usr/bin/env python3
import boto3
import json
import random
import uuid
from datetime import datetime, timezone
import argparse

# Initialize EventBridge client
eventbridge = boto3.client('events')

EVENT_BUS_NAME = '$EVENT_BUS_NAME'

def publish_order_event(event_type='Order Created'):
    """Publish order-related events"""
    
    order_id = str(uuid.uuid4())
    customer_id = f'customer_{random.randint(1000, 9999)}'
    total_amount = round(random.uniform(50.0, 2000.0), 2)
    
    event = {
        'Source': 'ecommerce.orders',
        'DetailType': event_type,
        'Detail': json.dumps({
            'orderId': order_id,
            'customerId': customer_id,
            'totalAmount': total_amount,
            'currency': 'USD',
            'items': [
                {
                    'productId': f'prod_{random.randint(100, 999)}',
                    'quantity': random.randint(1, 5),
                    'price': round(total_amount / random.randint(1, 3), 2)
                }
            ],
            'timestamp': datetime.now(timezone.utc).isoformat()
        }),
        'EventBusName': EVENT_BUS_NAME
    }
    
    response = eventbridge.put_events(Entries=[event])
    
    print(f"📦 Published {event_type} event:")
    print(f"   Order ID: {order_id}")
    print(f"   Customer: {customer_id}")
    print(f"   Amount: \${total_amount}")
    print(f"   Response: {response}")
    
    return response

def publish_user_event(event_type='User Registered'):
    """Publish user-related events"""
    
    user_id = str(uuid.uuid4())
    email = f'user{random.randint(1000, 9999)}@example.com'
    
    event = {
        'Source': 'ecommerce.users',
        'DetailType': event_type,
        'Detail': json.dumps({
            'userId': user_id,
            'email': email,
            'firstName': random.choice(['John', 'Jane', 'Bob', 'Alice']),
            'lastName': random.choice(['Smith', 'Johnson', 'Brown', 'Davis']),
            'registrationMethod': random.choice(['email', 'google', 'facebook']),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }),
        'EventBusName': EVENT_BUS_NAME
    }
    
    response = eventbridge.put_events(Entries=[event])
    
    print(f"👤 Published {event_type} event:")
    print(f"   User ID: {user_id}")
    print(f"   Email: {email}")
    print(f"   Response: {response}")
    
    return response

def publish_payment_event(event_type='Payment Processed'):
    """Publish payment-related events"""
    
    payment_id = str(uuid.uuid4())
    amount = round(random.uniform(10.0, 1500.0), 2)
    
    event = {
        'Source': 'ecommerce.payments',
        'DetailType': event_type,
        'Detail': json.dumps({
            'paymentId': payment_id,
            'orderId': str(uuid.uuid4()),
            'amount': amount,
            'currency': 'USD',
            'paymentMethod': random.choice(['credit_card', 'paypal', 'apple_pay']),
            'status': 'completed',
            'timestamp': datetime.now(timezone.utc).isoformat()
        }),
        'EventBusName': EVENT_BUS_NAME
    }
    
    response = eventbridge.put_events(Entries=[event])
    
    print(f"💳 Published {event_type} event:")
    print(f"   Payment ID: {payment_id}")
    print(f"   Amount: \${amount}")
    print(f"   Response: {response}")
    
    return response

def publish_batch_events(count=10):
    """Publish a batch of mixed events"""
    
    print(f"🚀 Publishing {count} events...")
    
    for i in range(count):
        event_type = random.choice(['order', 'user', 'payment'])
        
        if event_type == 'order':
            order_event_type = random.choice(['Order Created', 'Order Updated', 'Order Cancelled'])
            publish_order_event(order_event_type)
        elif event_type == 'user':
            publish_user_event()
        else:
            publish_payment_event()
        
        print()  # Add spacing between events

def main():
    parser = argparse.ArgumentParser(description='EventBridge Event Publisher')
    parser.add_argument('--type', choices=['order', 'user', 'payment', 'batch'],
                       default='batch', help='Type of event to publish')
    parser.add_argument('--count', type=int, default=5,
                       help='Number of events to publish (for batch mode)')
    
    args = parser.parse_args()
    
    if args.type == 'order':
        publish_order_event()
    elif args.type == 'user':
        publish_user_event()
    elif args.type == 'payment':
        publish_payment_event()
    else:
        publish_batch_events(args.count)

if __name__ == "__main__":
    main()
EOF
    
    chmod +x "$PROJECT_DIR/event_publisher.py"
    
    # Create monitoring script
    cat > "$PROJECT_DIR/monitor_events.py" << EOF
#!/usr/bin/env python3
import boto3
import json
from datetime import datetime, timedelta

# Initialize AWS clients
eventbridge = boto3.client('events')
cloudwatch = boto3.client('cloudwatch')
sqs = boto3.client('sqs')

EVENT_BUS_NAME = '$EVENT_BUS_NAME'
SQS_QUEUE_URL = '$SQS_QUEUE_URL'

def check_event_bus_status():
    """Check EventBridge event bus status"""
    try:
        response = eventbridge.describe_event_bus(Name=EVENT_BUS_NAME)
        
        print(f"📊 Event Bus Status: {EVENT_BUS_NAME}")
        print(f"   ARN: {response['Arn']}")
        print(f"   Name: {response['Name']}")
        
    except Exception as e:
        print(f"❌ Error checking event bus: {e}")

def list_event_rules():
    """List EventBridge rules"""
    try:
        response = eventbridge.list_rules(EventBusName=EVENT_BUS_NAME)
        
        print(f"\\n📋 Event Rules ({len(response['Rules'])} total):")
        
        for rule in response['Rules']:
            print(f"   Rule: {rule['Name']}")
            print(f"   State: {rule['State']}")
            print(f"   Description: {rule.get('Description', 'N/A')}")
            
            # Get targets for each rule
            targets_response = eventbridge.list_targets_by_rule(
                Rule=rule['Name'],
                EventBusName=EVENT_BUS_NAME
            )
            
            print(f"   Targets: {len(targets_response['Targets'])}")
            for target in targets_response['Targets']:
                print(f"     - {target['Arn']}")
            print()
            
    except Exception as e:
        print(f"❌ Error listing rules: {e}")

def get_eventbridge_metrics():
    """Get EventBridge CloudWatch metrics"""
    try:
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        # Get successful invocations
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/Events',
            MetricName='SuccessfulInvocations',
            Dimensions=[
                {'Name': 'EventBusName', 'Value': EVENT_BUS_NAME}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Sum']
        )
        
        total_invocations = sum([point['Sum'] for point in response['Datapoints']])
        print(f"\\n📈 EventBridge Metrics (last hour):")
        print(f"   Successful Invocations: {int(total_invocations)}")
        
        # Get failed invocations
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/Events',
            MetricName='FailedInvocations',
            Dimensions=[
                {'Name': 'EventBusName', 'Value': EVENT_BUS_NAME}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Sum']
        )
        
        total_failures = sum([point['Sum'] for point in response['Datapoints']])
        print(f"   Failed Invocations: {int(total_failures)}")
        
    except Exception as e:
        print(f"❌ Error getting metrics: {e}")

def check_sqs_messages():
    """Check messages in SQS queue"""
    try:
        response = sqs.get_queue_attributes(
            QueueUrl=SQS_QUEUE_URL,
            AttributeNames=['ApproximateNumberOfMessages', 'ApproximateNumberOfMessagesNotVisible']
        )
        
        visible_messages = response['Attributes'].get('ApproximateNumberOfMessages', '0')
        invisible_messages = response['Attributes'].get('ApproximateNumberOfMessagesNotVisible', '0')
        
        print(f"\\n📬 SQS Queue Status:")
        print(f"   Visible Messages: {visible_messages}")
        print(f"   Processing Messages: {invisible_messages}")
        
    except Exception as e:
        print(f"❌ Error checking SQS: {e}")

def main():
    print("EventBridge Architecture Monitor")
    print("=" * 35)
    
    check_event_bus_status()
    list_event_rules()
    get_eventbridge_metrics()
    check_sqs_messages()

if __name__ == "__main__":
    main()
EOF
    
    chmod +x "$PROJECT_DIR/monitor_events.py"
    
    log_success "Created utility scripts"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would save deployment information"
        return 0
    fi
    
    # Create deployment info file
    cat > "$PROJECT_DIR/deployment-info.json" << EOF
{
  "deploymentTimestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "awsRegion": "$AWS_REGION",
  "awsAccountId": "$AWS_ACCOUNT_ID",
  "stackName": "$STACK_NAME",
  "randomSuffix": "$RANDOM_SUFFIX",
  "resources": {
    "eventBusName": "$EVENT_BUS_NAME",
    "eventBusArn": "$EVENT_BUS_ARN",
    "snsTopicName": "$SNS_TOPIC_NAME",
    "snsTopicArn": "$SNS_TOPIC_ARN",
    "sqsQueueName": "$SQS_QUEUE_NAME",
    "sqsQueueUrl": "$SQS_QUEUE_URL",
    "sqsQueueArn": "$SQS_QUEUE_ARN",
    "lambdaFunctionName": "$LAMBDA_FUNCTION_NAME",
    "lambdaFunctionArn": "$LAMBDA_FUNCTION_ARN",
    "eventbridgeRoleArn": "$EVENTBRIDGE_ROLE_ARN",
    "lambdaRoleArn": "$LAMBDA_ROLE_ARN"
  },
  "rules": [
    "OrderEventsRule-${RANDOM_SUFFIX}",
    "HighValueOrdersRule-${RANDOM_SUFFIX}",
    "AllEventsToSQSRule-${RANDOM_SUFFIX}",
    "UserRegistrationRule-${RANDOM_SUFFIX}"
  ],
  "utilityScripts": [
    "event_publisher.py",
    "monitor_events.py"
  ]
}
EOF
    
    log_success "Saved deployment information to deployment-info.json"
}

# Display deployment summary
display_deployment_summary() {
    log_info "=== Deployment Summary ==="
    log_info "Deployment completed successfully!"
    log_info ""
    log_info "Resources created:"
    log_info "  • EventBridge Event Bus: $EVENT_BUS_NAME"
    log_info "  • SNS Topic: $SNS_TOPIC_NAME"
    log_info "  • SQS Queue: $SQS_QUEUE_NAME"
    log_info "  • Lambda Function: $LAMBDA_FUNCTION_NAME"
    log_info "  • EventBridge Rules: 4 rules created"
    log_info "  • IAM Roles: 2 roles created"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Test the architecture: python3 event_publisher.py --type batch --count 5"
    log_info "  2. Monitor events: python3 monitor_events.py"
    log_info "  3. Check Lambda logs in CloudWatch"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
    log_info "=========================="
}

# Confirmation prompt
confirm_deployment() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will create AWS resources that may incur charges."
    log_warning "EventBridge: ~\$1.00/million events"
    log_warning "Lambda: ~\$0.20/million requests"
    log_warning "SNS: ~\$0.50/million notifications"
    log_warning "SQS: ~\$0.40/million requests"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY RUN mode - no resources will be created"
        return 0
    fi
    
    read -p "Do you want to proceed with the deployment? (y/N): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# Main deployment function
main() {
    echo ""
    log_info "EventBridge Event-Driven Architecture Deployment"
    log_info "==============================================="
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Display deployment configuration
    display_deployment_info
    
    # Confirm deployment
    confirm_deployment
    
    # Generate resource names
    generate_resource_names
    
    # Create resources
    create_event_bus
    create_messaging_resources
    create_iam_roles
    create_lambda_function
    create_eventbridge_rules
    create_utility_scripts
    
    # Save deployment info
    save_deployment_info
    
    # Display summary
    if [[ "$DRY_RUN" != "true" ]]; then
        display_deployment_summary
    else
        log_info "DRY RUN completed - no resources were created"
    fi
}

# Handle script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        log_error "Deployment failed. You may need to manually clean up any partially created resources."
        log_error "Check the AWS console for any resources that were created."
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"