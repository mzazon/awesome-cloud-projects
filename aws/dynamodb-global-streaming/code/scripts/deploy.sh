#!/bin/bash

# Deploy script for Advanced DynamoDB Streaming with Global Tables
# This script deploys a multi-region DynamoDB architecture with streaming capabilities

set -euo pipefail

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Default configuration
PRIMARY_REGION="us-east-1"
SECONDARY_REGION="eu-west-1"
TERTIARY_REGION="ap-southeast-1"
DRY_RUN=false
FORCE=false

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Advanced DynamoDB Streaming with Global Tables infrastructure

OPTIONS:
    -h, --help              Display this help message
    -d, --dry-run          Show what would be deployed without actually deploying
    -f, --force            Force deployment even if resources exist
    --primary-region       Primary AWS region (default: us-east-1)
    --secondary-region     Secondary AWS region (default: eu-west-1)
    --tertiary-region      Tertiary AWS region (default: ap-southeast-1)
    --log-file            Custom log file path (default: ./deploy.log)

EXAMPLES:
    $0                                    # Deploy with defaults
    $0 --dry-run                         # Preview deployment
    $0 --primary-region us-west-2        # Use different primary region
    $0 --force                           # Force deployment

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --primary-region)
            PRIMARY_REGION="$2"
            shift 2
            ;;
        --secondary-region)
            SECONDARY_REGION="$2"
            shift 2
            ;;
        --tertiary-region)
            TERTIARY_REGION="$2"
            shift 2
            ;;
        --log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log_info "Starting DynamoDB Global Streaming deployment at $(date)"
log_info "Primary Region: $PRIMARY_REGION"
log_info "Secondary Region: $SECONDARY_REGION"
log_info "Tertiary Region: $TERTIARY_REGION"
log_info "Dry Run: $DRY_RUN"
log_info "Force: $FORCE"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    # Get account info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "AWS User/Role: $AWS_USER_ARN"
    
    # Check if regions are valid
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        if ! aws ec2 describe-regions --region-names "$region" &> /dev/null; then
            log_error "Invalid region: $region"
            exit 1
        fi
    done
    
    # Check required permissions (basic check)
    log_info "Checking IAM permissions..."
    
    # Test DynamoDB permissions
    if ! aws dynamodb list-tables --region "$PRIMARY_REGION" &> /dev/null; then
        log_error "Missing DynamoDB permissions in primary region"
        exit 1
    fi
    
    # Test Kinesis permissions
    if ! aws kinesis list-streams --region "$PRIMARY_REGION" &> /dev/null; then
        log_error "Missing Kinesis permissions in primary region"
        exit 1
    fi
    
    # Test Lambda permissions
    if ! aws lambda list-functions --region "$PRIMARY_REGION" &> /dev/null; then
        log_error "Missing Lambda permissions in primary region"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Generate unique identifiers
generate_identifiers() {
    log_info "Generating unique resource identifiers..."
    
    # Generate random suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7)")
    
    export TABLE_NAME="ecommerce-global-${RANDOM_SUFFIX}"
    export STREAM_NAME="ecommerce-events-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="ecommerce-lambda-role-${RANDOM_SUFFIX}"
    
    log_info "Table Name: $TABLE_NAME"
    log_info "Stream Name: $STREAM_NAME"
    log_info "Lambda Role Name: $LAMBDA_ROLE_NAME"
    
    # Save identifiers to state file
    cat > "$STATE_FILE" << EOF
TABLE_NAME=$TABLE_NAME
STREAM_NAME=$STREAM_NAME
LAMBDA_ROLE_NAME=$LAMBDA_ROLE_NAME
PRIMARY_REGION=$PRIMARY_REGION
SECONDARY_REGION=$SECONDARY_REGION
TERTIARY_REGION=$TERTIARY_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
DEPLOYMENT_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

# Create IAM role for Lambda
create_iam_role() {
    log_info "Creating IAM role for Lambda functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create IAM role: $LAMBDA_ROLE_NAME"
        return 0
    fi
    
    # Check if role already exists
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &> /dev/null; then
        if [[ "$FORCE" == "true" ]]; then
            log_warning "Role $LAMBDA_ROLE_NAME already exists, but force flag is set"
        else
            log_error "Role $LAMBDA_ROLE_NAME already exists. Use --force to override"
            exit 1
        fi
    fi
    
    # Create trust policy
    cat > /tmp/lambda-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create role
    aws iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --description "Role for DynamoDB Global Streaming Lambda functions" \
        --tags Key=Application,Value=ECommerce Key=Component,Value=Lambda || {
        if [[ "$FORCE" != "true" ]]; then
            log_error "Failed to create IAM role"
            exit 1
        fi
    }
    
    # Attach policies
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
        "arn:aws:iam::aws:policy/AmazonKinesisFullAccess"
        "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
        "arn:aws:iam::aws:policy/CloudWatchFullAccess"
    )
    
    for policy in "${policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn "$policy"
        log_info "Attached policy: $policy"
    done
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 30
    
    rm -f /tmp/lambda-trust-policy.json
    log_success "IAM role created successfully"
}

# Create DynamoDB table in primary region
create_primary_table() {
    log_info "Creating primary DynamoDB table in $PRIMARY_REGION..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create table: $TABLE_NAME in $PRIMARY_REGION"
        return 0
    fi
    
    # Check if table already exists
    if aws dynamodb describe-table --region "$PRIMARY_REGION" --table-name "$TABLE_NAME" &> /dev/null; then
        if [[ "$FORCE" == "true" ]]; then
            log_warning "Table $TABLE_NAME already exists in $PRIMARY_REGION, but force flag is set"
        else
            log_error "Table $TABLE_NAME already exists in $PRIMARY_REGION. Use --force to override"
            exit 1
        fi
    else
        # Create the primary table
        aws dynamodb create-table \
            --region "$PRIMARY_REGION" \
            --table-name "$TABLE_NAME" \
            --attribute-definitions \
                AttributeName=PK,AttributeType=S \
                AttributeName=SK,AttributeType=S \
                AttributeName=GSI1PK,AttributeType=S \
                AttributeName=GSI1SK,AttributeType=S \
            --key-schema \
                AttributeName=PK,KeyType=HASH \
                AttributeName=SK,KeyType=RANGE \
            --global-secondary-indexes \
                IndexName=GSI1,KeySchema=[{AttributeName=GSI1PK,KeyType=HASH},{AttributeName=GSI1SK,KeyType=RANGE}],Projection={ProjectionType=ALL},BillingMode=PAY_PER_REQUEST \
            --billing-mode PAY_PER_REQUEST \
            --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
            --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
            --tags Key=Application,Value=ECommerce Key=Environment,Value=Production Key=Component,Value=Database
        
        # Wait for table to be active
        log_info "Waiting for table to become active..."
        aws dynamodb wait table-exists --region "$PRIMARY_REGION" --table-name "$TABLE_NAME"
        
        log_success "Primary table created successfully"
    fi
}

# Create Kinesis streams in all regions
create_kinesis_streams() {
    log_info "Creating Kinesis Data Streams in all regions..."
    
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        log_info "Creating Kinesis stream in $region..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create stream: $STREAM_NAME in $region"
            continue
        fi
        
        # Check if stream already exists
        if aws kinesis describe-stream --region "$region" --stream-name "$STREAM_NAME" &> /dev/null; then
            if [[ "$FORCE" == "true" ]]; then
                log_warning "Stream $STREAM_NAME already exists in $region, but force flag is set"
                continue
            else
                log_error "Stream $STREAM_NAME already exists in $region. Use --force to override"
                exit 1
            fi
        fi
        
        # Create stream
        aws kinesis create-stream \
            --region "$region" \
            --stream-name "$STREAM_NAME" \
            --shard-count 3
        
        # Wait for stream to be active
        log_info "Waiting for stream to become active in $region..."
        aws kinesis wait stream-exists --region "$region" --stream-name "$STREAM_NAME"
        
        # Enable enhanced monitoring
        aws kinesis enable-enhanced-monitoring \
            --region "$region" \
            --stream-name "$STREAM_NAME" \
            --shard-level-metrics ALL
        
        log_success "Kinesis stream created in $region"
    done
}

# Enable Kinesis integration for DynamoDB
enable_kinesis_integration() {
    log_info "Enabling Kinesis Data Streams integration for DynamoDB..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable Kinesis integration for table: $TABLE_NAME"
        return 0
    fi
    
    # Get Kinesis stream ARN
    local kinesis_arn
    kinesis_arn=$(aws kinesis describe-stream \
        --region "$PRIMARY_REGION" \
        --stream-name "$STREAM_NAME" \
        --query 'StreamDescription.StreamARN' \
        --output text)
    
    # Enable integration
    aws dynamodb enable-kinesis-streaming-destination \
        --region "$PRIMARY_REGION" \
        --table-name "$TABLE_NAME" \
        --stream-arn "$kinesis_arn"
    
    log_success "Kinesis integration enabled"
}

# Create replica tables for Global Tables
create_replica_tables() {
    log_info "Creating replica tables for Global Tables..."
    
    for region in "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        log_info "Creating replica table in $region..."
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create replica table: $TABLE_NAME in $region"
            continue
        fi
        
        # Check if table already exists
        if aws dynamodb describe-table --region "$region" --table-name "$TABLE_NAME" &> /dev/null; then
            if [[ "$FORCE" == "true" ]]; then
                log_warning "Table $TABLE_NAME already exists in $region, but force flag is set"
                continue
            else
                log_error "Table $TABLE_NAME already exists in $region. Use --force to override"
                exit 1
            fi
        fi
        
        # Create replica table
        aws dynamodb create-table \
            --region "$region" \
            --table-name "$TABLE_NAME" \
            --attribute-definitions \
                AttributeName=PK,AttributeType=S \
                AttributeName=SK,AttributeType=S \
                AttributeName=GSI1PK,AttributeType=S \
                AttributeName=GSI1SK,AttributeType=S \
            --key-schema \
                AttributeName=PK,KeyType=HASH \
                AttributeName=SK,KeyType=RANGE \
            --global-secondary-indexes \
                IndexName=GSI1,KeySchema=[{AttributeName=GSI1PK,KeyType=HASH},{AttributeName=GSI1SK,KeyType=RANGE}],Projection={ProjectionType=ALL},BillingMode=PAY_PER_REQUEST \
            --billing-mode PAY_PER_REQUEST \
            --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
            --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true \
            --tags Key=Application,Value=ECommerce Key=Environment,Value=Production Key=Component,Value=Database
        
        # Wait for table to be active
        log_info "Waiting for replica table to become active in $region..."
        aws dynamodb wait table-exists --region "$region" --table-name "$TABLE_NAME"
        
        log_success "Replica table created in $region"
    done
    
    # Create global table configuration
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Creating global table configuration..."
        
        aws dynamodb create-global-table \
            --region "$PRIMARY_REGION" \
            --global-table-name "$TABLE_NAME" \
            --replication-group \
                RegionName="$PRIMARY_REGION" \
                RegionName="$SECONDARY_REGION" \
                RegionName="$TERTIARY_REGION" || {
            log_warning "Global table may already be configured"
        }
        
        log_success "Global table configuration completed"
    fi
}

# Create Lambda functions
create_lambda_functions() {
    log_info "Creating Lambda functions for stream processing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Lambda functions in all regions"
        return 0
    fi
    
    # Create stream processor function code
    cat > /tmp/stream-processor.py << 'EOF'
import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def lambda_handler(event, context):
    for record in event['Records']:
        if record['eventName'] in ['INSERT', 'MODIFY', 'REMOVE']:
            process_record(record)
    return {'statusCode': 200}

def process_record(record):
    event_name = record['eventName']
    table_name = record['eventSourceARN'].split('/')[-3]
    
    # Extract item data
    if 'NewImage' in record['dynamodb']:
        new_image = record['dynamodb']['NewImage']
        pk = new_image.get('PK', {}).get('S', '')
        
        # Process different entity types
        if pk.startswith('PRODUCT#'):
            process_product_event(event_name, new_image, record.get('dynamodb', {}).get('OldImage'))
        elif pk.startswith('ORDER#'):
            process_order_event(event_name, new_image, record.get('dynamodb', {}).get('OldImage'))
        elif pk.startswith('USER#'):
            process_user_event(event_name, new_image, record.get('dynamodb', {}).get('OldImage'))

def process_product_event(event_name, new_image, old_image):
    # Inventory management logic
    if event_name == 'MODIFY' and old_image:
        old_stock = int(old_image.get('Stock', {}).get('N', '0'))
        new_stock = int(new_image.get('Stock', {}).get('N', '0'))
        
        if old_stock != new_stock:
            send_inventory_alert(new_image, old_stock, new_stock)

def process_order_event(event_name, new_image, old_image):
    # Order processing logic
    if event_name == 'INSERT':
        send_order_notification(new_image)
    elif event_name == 'MODIFY':
        status_changed = check_order_status_change(new_image, old_image)
        if status_changed:
            send_status_update(new_image)

def process_user_event(event_name, new_image, old_image):
    # User activity tracking
    if event_name == 'MODIFY':
        send_user_activity_event(new_image)

def send_inventory_alert(product, old_stock, new_stock):
    eventbridge.put_events(
        Entries=[{
            'Source': 'ecommerce.inventory',
            'DetailType': 'Inventory Change',
            'Detail': json.dumps({
                'productId': product.get('PK', {}).get('S', ''),
                'oldStock': old_stock,
                'newStock': new_stock,
                'timestamp': product.get('UpdatedAt', {}).get('S', '')
            })
        }]
    )

def send_order_notification(order):
    eventbridge.put_events(
        Entries=[{
            'Source': 'ecommerce.orders',
            'DetailType': 'New Order',
            'Detail': json.dumps({
                'orderId': order.get('PK', {}).get('S', ''),
                'customerId': order.get('CustomerId', {}).get('S', ''),
                'amount': order.get('TotalAmount', {}).get('N', ''),
                'timestamp': order.get('CreatedAt', {}).get('S', '')
            })
        }]
    )

def send_status_update(order):
    eventbridge.put_events(
        Entries=[{
            'Source': 'ecommerce.orders',
            'DetailType': 'Order Status Update',
            'Detail': json.dumps({
                'orderId': order.get('PK', {}).get('S', ''),
                'status': order.get('Status', {}).get('S', ''),
                'timestamp': order.get('UpdatedAt', {}).get('S', '')
            })
        }]
    )

def send_user_activity_event(user):
    eventbridge.put_events(
        Entries=[{
            'Source': 'ecommerce.users',
            'DetailType': 'User Activity',
            'Detail': json.dumps({
                'userId': user.get('PK', {}).get('S', ''),
                'lastActive': user.get('LastActiveAt', {}).get('S', ''),
                'timestamp': user.get('UpdatedAt', {}).get('S', '')
            })
        }]
    )

def check_order_status_change(new_image, old_image):
    if not old_image:
        return False
    old_status = old_image.get('Status', {}).get('S', '')
    new_status = new_image.get('Status', {}).get('S', '')
    return old_status != new_status
EOF
    
    # Create Kinesis processor function code
    cat > /tmp/kinesis-processor.py << 'EOF'
import json
import boto3
import base64
from datetime import datetime

cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    metrics_data = []
    
    for record in event['Records']:
        # Decode Kinesis data
        payload = json.loads(base64.b64decode(record['kinesis']['data']))
        
        # Extract metrics based on event type
        if payload.get('eventName') == 'INSERT':
            process_insert_metrics(payload, metrics_data)
        elif payload.get('eventName') == 'MODIFY':
            process_modify_metrics(payload, metrics_data)
        elif payload.get('eventName') == 'REMOVE':
            process_remove_metrics(payload, metrics_data)
    
    # Send metrics to CloudWatch
    if metrics_data:
        send_metrics(metrics_data)
    
    return {'statusCode': 200, 'body': f'Processed {len(event["Records"])} records'}

def process_insert_metrics(payload, metrics_data):
    dynamodb_data = payload.get('dynamodb', {})
    new_image = dynamodb_data.get('NewImage', {})
    pk = new_image.get('PK', {}).get('S', '')
    
    if pk.startswith('ORDER#'):
        amount = float(new_image.get('TotalAmount', {}).get('N', '0'))
        metrics_data.append({
            'MetricName': 'NewOrders',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [{'Name': 'EntityType', 'Value': 'Order'}]
        })
        metrics_data.append({
            'MetricName': 'OrderValue',
            'Value': amount,
            'Unit': 'None',
            'Dimensions': [{'Name': 'EntityType', 'Value': 'Order'}]
        })
    elif pk.startswith('PRODUCT#'):
        metrics_data.append({
            'MetricName': 'NewProducts',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [{'Name': 'EntityType', 'Value': 'Product'}]
        })

def process_modify_metrics(payload, metrics_data):
    dynamodb_data = payload.get('dynamodb', {})
    new_image = dynamodb_data.get('NewImage', {})
    old_image = dynamodb_data.get('OldImage', {})
    pk = new_image.get('PK', {}).get('S', '')
    
    if pk.startswith('PRODUCT#'):
        old_stock = int(old_image.get('Stock', {}).get('N', '0'))
        new_stock = int(new_image.get('Stock', {}).get('N', '0'))
        stock_change = new_stock - old_stock
        
        if stock_change != 0:
            metrics_data.append({
                'MetricName': 'InventoryChange',
                'Value': abs(stock_change),
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'EntityType', 'Value': 'Product'},
                    {'Name': 'ChangeType', 'Value': 'Increase' if stock_change > 0 else 'Decrease'}
                ]
            })

def process_remove_metrics(payload, metrics_data):
    dynamodb_data = payload.get('dynamodb', {})
    old_image = dynamodb_data.get('OldImage', {})
    pk = old_image.get('PK', {}).get('S', '')
    
    if pk.startswith('ORDER#'):
        metrics_data.append({
            'MetricName': 'CancelledOrders',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [{'Name': 'EntityType', 'Value': 'Order'}]
        })

def send_metrics(metrics_data):
    cloudwatch.put_metric_data(
        Namespace='ECommerce/Global',
        MetricData=[{
            **metric,
            'Timestamp': datetime.utcnow()
        } for metric in metrics_data]
    )
EOF
    
    # Package and deploy Lambda functions
    (cd /tmp && zip stream-processor.zip stream-processor.py)
    (cd /tmp && zip kinesis-processor.zip kinesis-processor.py)
    
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        log_info "Deploying Lambda functions in $region..."
        
        # Deploy stream processor
        aws lambda create-function \
            --region "$region" \
            --function-name "${TABLE_NAME}-stream-processor" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
            --handler stream-processor.lambda_handler \
            --zip-file fileb:///tmp/stream-processor.zip \
            --timeout 300 \
            --memory-size 512 \
            --environment Variables="{TABLE_NAME=${TABLE_NAME},REGION=${region}}" \
            --tags Application=ECommerce,Component=StreamProcessor || {
            log_warning "Stream processor may already exist in $region"
        }
        
        # Deploy Kinesis processor
        aws lambda create-function \
            --region "$region" \
            --function-name "${STREAM_NAME}-kinesis-processor" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}" \
            --handler kinesis-processor.lambda_handler \
            --zip-file fileb:///tmp/kinesis-processor.zip \
            --timeout 300 \
            --memory-size 512 \
            --tags Application=ECommerce,Component=KinesisProcessor || {
            log_warning "Kinesis processor may already exist in $region"
        }
        
        log_success "Lambda functions deployed in $region"
    done
    
    # Cleanup temporary files
    rm -f /tmp/stream-processor.py /tmp/kinesis-processor.py
    rm -f /tmp/stream-processor.zip /tmp/kinesis-processor.zip
}

# Configure event source mappings
configure_event_mappings() {
    log_info "Configuring event source mappings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure event source mappings in all regions"
        return 0
    fi
    
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        log_info "Configuring mappings in $region..."
        
        # Get DynamoDB Stream ARN
        local ddb_stream_arn
        ddb_stream_arn=$(aws dynamodb describe-table \
            --region "$region" \
            --table-name "$TABLE_NAME" \
            --query 'Table.LatestStreamArn' \
            --output text)
        
        # Create DynamoDB Streams mapping
        aws lambda create-event-source-mapping \
            --region "$region" \
            --function-name "${TABLE_NAME}-stream-processor" \
            --event-source-arn "$ddb_stream_arn" \
            --starting-position LATEST \
            --batch-size 10 \
            --maximum-batching-window-in-seconds 5 || {
            log_warning "DynamoDB stream mapping may already exist in $region"
        }
        
        # Get Kinesis Stream ARN
        local kinesis_stream_arn
        kinesis_stream_arn=$(aws kinesis describe-stream \
            --region "$region" \
            --stream-name "$STREAM_NAME" \
            --query 'StreamDescription.StreamARN' \
            --output text)
        
        # Create Kinesis mapping
        aws lambda create-event-source-mapping \
            --region "$region" \
            --function-name "${STREAM_NAME}-kinesis-processor" \
            --event-source-arn "$kinesis_stream_arn" \
            --starting-position LATEST \
            --batch-size 100 \
            --maximum-batching-window-in-seconds 10 \
            --parallelization-factor 2 || {
            log_warning "Kinesis stream mapping may already exist in $region"
        }
        
        log_success "Event source mappings configured in $region"
    done
}

# Create CloudWatch dashboard
create_dashboard() {
    log_info "Creating CloudWatch dashboard..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create CloudWatch dashboard"
        return 0
    fi
    
    # Create dashboard configuration
    cat > /tmp/dashboard-config.json << EOF
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["ECommerce/Global", "NewOrders", "EntityType", "Order"],
          [".", "OrderValue", ".", "."],
          [".", "CancelledOrders", ".", "."]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "$PRIMARY_REGION",
        "title": "Order Metrics - Global"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["ECommerce/Global", "InventoryChange", "EntityType", "Product", "ChangeType", "Increase"],
          ["...", "Decrease"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "$PRIMARY_REGION",
        "title": "Inventory Changes - Global"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "$TABLE_NAME"],
          [".", "ConsumedWriteCapacityUnits", ".", "."]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "$PRIMARY_REGION",
        "title": "DynamoDB Capacity - Primary Region"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Kinesis", "IncomingRecords", "StreamName", "$STREAM_NAME"],
          [".", "OutgoingRecords", ".", "."]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "$PRIMARY_REGION",
        "title": "Kinesis Stream Metrics - Primary Region"
      }
    }
  ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --region "$PRIMARY_REGION" \
        --dashboard-name "ECommerce-Global-Monitoring" \
        --dashboard-body file:///tmp/dashboard-config.json
    
    rm -f /tmp/dashboard-config.json
    log_success "CloudWatch dashboard created"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Deployment validation would be performed"
        return 0
    fi
    
    local validation_failed=false
    
    # Check primary table
    if ! aws dynamodb describe-table --region "$PRIMARY_REGION" --table-name "$TABLE_NAME" &> /dev/null; then
        log_error "Primary table validation failed"
        validation_failed=true
    fi
    
    # Check replica tables
    for region in "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        if ! aws dynamodb describe-table --region "$region" --table-name "$TABLE_NAME" &> /dev/null; then
            log_error "Replica table validation failed in $region"
            validation_failed=true
        fi
    done
    
    # Check Kinesis streams
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        if ! aws kinesis describe-stream --region "$region" --stream-name "$STREAM_NAME" &> /dev/null; then
            log_error "Kinesis stream validation failed in $region"
            validation_failed=true
        fi
    done
    
    # Check Lambda functions
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        if ! aws lambda get-function --region "$region" --function-name "${TABLE_NAME}-stream-processor" &> /dev/null; then
            log_error "Stream processor validation failed in $region"
            validation_failed=true
        fi
        
        if ! aws lambda get-function --region "$region" --function-name "${STREAM_NAME}-kinesis-processor" &> /dev/null; then
            log_error "Kinesis processor validation failed in $region"
            validation_failed=true
        fi
    done
    
    if [[ "$validation_failed" == "true" ]]; then
        log_error "Deployment validation failed"
        exit 1
    fi
    
    log_success "Deployment validation passed"
}

# Print deployment summary
print_summary() {
    log_info "Deployment Summary"
    echo "================================================"
    echo "Table Name: $TABLE_NAME"
    echo "Stream Name: $STREAM_NAME"
    echo "Lambda Role: $LAMBDA_ROLE_NAME"
    echo "Primary Region: $PRIMARY_REGION"
    echo "Secondary Region: $SECONDARY_REGION"
    echo "Tertiary Region: $TERTIARY_REGION"
    echo "CloudWatch Dashboard: ECommerce-Global-Monitoring"
    echo "State File: $STATE_FILE"
    echo "Log File: $LOG_FILE"
    echo "================================================"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "Deployment completed successfully!"
        log_info "To test the deployment, add some sample data to the table"
        log_info "To clean up resources, run: ./destroy.sh"
    else
        log_info "Dry run completed - no resources were created"
    fi
}

# Main deployment function
main() {
    check_prerequisites
    generate_identifiers
    create_iam_role
    create_primary_table
    create_kinesis_streams
    enable_kinesis_integration
    create_replica_tables
    create_lambda_functions
    configure_event_mappings
    create_dashboard
    validate_deployment
    print_summary
}

# Handle script interruption
cleanup_on_error() {
    log_error "Script interrupted or failed"
    log_info "Check the log file for details: $LOG_FILE"
    log_info "To clean up partial deployment, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR INT TERM

# Run main function
main

log_info "Script completed at $(date)"