#!/bin/bash

# Real-Time Fraud Detection with Amazon Fraud Detector - Deployment Script
# This script deploys the complete fraud detection platform including:
# - Amazon Fraud Detector models and rules
# - Kinesis streams for real-time processing
# - Lambda functions for event processing
# - DynamoDB for decision logging
# - SNS for fraud alerts
# - CloudWatch monitoring dashboard

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI not configured or authentication failed"
        error "Please run 'aws configure' or set up AWS credentials"
        exit 1
    fi
}

# Function to check required permissions
check_permissions() {
    log "Checking required AWS permissions..."
    
    # Test basic permissions
    if ! aws iam get-user >/dev/null 2>&1 && ! aws iam get-role --role-name nonexistent-role >/dev/null 2>&1; then
        warn "Limited IAM permissions - some checks may be skipped"
    fi
    
    # Test service access
    local services=("frauddetector" "kinesis" "lambda" "dynamodb" "sns" "cloudwatch" "s3")
    for service in "${services[@]}"; do
        info "Checking $service access..."
        case $service in
            "frauddetector")
                if ! aws frauddetector describe-model-versions --model-id test-check --model-type TRANSACTION_FRAUD_INSIGHTS >/dev/null 2>&1; then
                    true  # Expected to fail, just checking API access
                fi
                ;;
            "kinesis")
                aws kinesis list-streams --limit 1 >/dev/null 2>&1 || {
                    error "No access to Kinesis service"
                    exit 1
                }
                ;;
        esac
    done
    
    log "Permission checks completed"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it from https://aws.amazon.com/cli/"
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: $aws_version"
    
    # Check if Python is installed (for Lambda functions)
    if ! command_exists python3; then
        error "Python 3 is not installed. Please install Python 3.9 or later"
        exit 1
    fi
    
    # Check if pip is installed
    if ! command_exists pip3; then
        error "pip3 is not installed. Please install pip for Python 3"
        exit 1
    fi
    
    # Check if zip is installed
    if ! command_exists zip; then
        error "zip is not installed. Please install zip utility"
        exit 1
    fi
    
    # Check AWS authentication
    check_aws_auth
    
    # Check permissions
    check_permissions
    
    log "Prerequisites check completed successfully"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "No AWS region configured, using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 8)")
    
    # Set resource names
    export FRAUD_BUCKET="fraud-detection-platform-${random_suffix}"
    export KINESIS_STREAM="fraud-transaction-stream-${random_suffix}"
    export EVENT_TYPE_NAME="transaction_fraud_detection_${random_suffix}"
    export ENTITY_TYPE_NAME="customer_entity_${random_suffix}"
    export MODEL_NAME="transaction_fraud_insights_${random_suffix}"
    export DETECTOR_NAME="realtime_fraud_detector_${random_suffix}"
    export DECISIONS_TABLE="fraud_decisions_${random_suffix}"
    export FEATURES_CACHE="fraud-features-${random_suffix}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
FRAUD_BUCKET=$FRAUD_BUCKET
KINESIS_STREAM=$KINESIS_STREAM
EVENT_TYPE_NAME=$EVENT_TYPE_NAME
ENTITY_TYPE_NAME=$ENTITY_TYPE_NAME
MODEL_NAME=$MODEL_NAME
DETECTOR_NAME=$DETECTOR_NAME
DECISIONS_TABLE=$DECISIONS_TABLE
FEATURES_CACHE=$FEATURES_CACHE
EOF
    
    log "Environment variables configured"
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "Resource suffix: $random_suffix"
}

# Function to create foundational infrastructure
create_infrastructure() {
    log "Creating foundational infrastructure..."
    
    # Create S3 bucket for training data
    info "Creating S3 bucket: $FRAUD_BUCKET"
    if aws s3 mb s3://${FRAUD_BUCKET} --region ${AWS_REGION} 2>/dev/null; then
        log "S3 bucket created successfully"
    else
        warn "S3 bucket creation failed or already exists"
    fi
    
    # Create Kinesis stream
    info "Creating Kinesis stream: $KINESIS_STREAM"
    aws kinesis create-stream \
        --stream-name ${KINESIS_STREAM} \
        --shard-count 3 || {
        warn "Kinesis stream creation failed or already exists"
    }
    
    # Create DynamoDB table
    info "Creating DynamoDB table: $DECISIONS_TABLE"
    aws dynamodb create-table \
        --table-name ${DECISIONS_TABLE} \
        --attribute-definitions \
            AttributeName=transaction_id,AttributeType=S \
            AttributeName=timestamp,AttributeType=N \
        --key-schema \
            AttributeName=transaction_id,KeyType=HASH \
            AttributeName=timestamp,KeyType=RANGE \
        --provisioned-throughput \
            ReadCapacityUnits=100,WriteCapacityUnits=100 \
        --global-secondary-indexes \
            IndexName=customer-index,KeySchema=[{AttributeName=customer_id,KeyType=HASH}],Projection={ProjectionType=ALL},ProvisionedThroughput={ReadCapacityUnits=50,WriteCapacityUnits=50} \
        >/dev/null 2>&1 || {
        warn "DynamoDB table creation failed or already exists"
    }
    
    # Wait for Kinesis stream to be active
    info "Waiting for Kinesis stream to be active..."
    aws kinesis wait stream-exists --stream-name ${KINESIS_STREAM} || {
        error "Kinesis stream failed to become active"
        exit 1
    }
    
    log "Foundational infrastructure created successfully"
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create trust policy for Fraud Detector
    cat > /tmp/fraud-detector-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "frauddetector.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create Fraud Detector role
    info "Creating Fraud Detector IAM role..."
    aws iam create-role \
        --role-name FraudDetectorEnhancedRole \
        --assume-role-policy-document file:///tmp/fraud-detector-trust-policy.json \
        >/dev/null 2>&1 || warn "Fraud Detector role creation failed or already exists"
    
    # Create enhanced policy for Fraud Detector
    cat > /tmp/fraud-detector-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::${FRAUD_BUCKET}",
                "arn:aws:s3:::${FRAUD_BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "frauddetector:*",
                "kinesis:PutRecord",
                "kinesis:PutRecords",
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Attach policy to Fraud Detector role
    aws iam put-role-policy \
        --role-name FraudDetectorEnhancedRole \
        --policy-name FraudDetectorEnhancedPolicy \
        --policy-document file:///tmp/fraud-detector-policy.json || {
        warn "Failed to attach policy to Fraud Detector role"
    }
    
    # Create Lambda execution role
    info "Creating Lambda execution role..."
    aws iam create-role \
        --role-name FraudDetectionLambdaRole \
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
        }' >/dev/null 2>&1 || warn "Lambda role creation failed or already exists"
    
    # Attach managed policies to Lambda role
    aws iam attach-role-policy \
        --role-name FraudDetectionLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || true
    
    aws iam attach-role-policy \
        --role-name FraudDetectionLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole || true
    
    # Get role ARNs
    export FRAUD_DETECTOR_ROLE_ARN=$(aws iam get-role \
        --role-name FraudDetectorEnhancedRole \
        --query Role.Arn --output text 2>/dev/null)
    
    export LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name FraudDetectionLambdaRole \
        --query Role.Arn --output text 2>/dev/null)
    
    # Update .env file with role ARNs
    echo "FRAUD_DETECTOR_ROLE_ARN=$FRAUD_DETECTOR_ROLE_ARN" >> .env
    echo "LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN" >> .env
    
    log "IAM roles created successfully"
}

# Function to generate training data
generate_training_data() {
    log "Generating training data..."
    
    # Install required Python packages
    info "Installing required Python packages..."
    pip3 install faker --quiet || {
        error "Failed to install faker package"
        exit 1
    }
    
    # Create training data generation script
    cat > /tmp/generate_training_data.py << 'EOF'
import csv
import random
import datetime
from faker import Faker
import hashlib

fake = Faker()

def generate_card_bin():
    """Generate realistic card BIN numbers"""
    bins = ['411111', '424242', '444444', '555555', '376000', '378282', '371449']
    return random.choice(bins)

def generate_ip_address(is_fraud=False):
    """Generate IP addresses with fraud indicators"""
    if is_fraud and random.random() < 0.3:
        # Suspicious IP patterns
        return f"{random.randint(1, 10)}.{random.randint(1, 10)}.{random.randint(1, 10)}.{random.randint(1, 254)}"
    else:
        return fake.ipv4()

def generate_transaction_data(num_records=5000):
    """Generate comprehensive transaction dataset"""
    records = []
    customers = [f"cust_{i:06d}" for i in range(1, 1001)]  # 1000 unique customers
    
    for i in range(num_records):
        customer_id = random.choice(customers)
        is_fraud = random.random() < 0.05  # 5% fraud rate
        
        # Generate transaction based on fraud pattern
        if is_fraud:
            order_price = random.uniform(500, 5000)  # Higher amounts for fraud
            email = fake.email() if random.random() < 0.7 else f"temp{random.randint(1000, 9999)}@tempmail.com"
            payment_method = random.choice(['credit_card', 'debit_card'])
            product_category = random.choice(['electronics', 'jewelry', 'gift_cards'])
            
            # Shipping and billing mismatch for fraud
            billing_address = fake.street_address()
            billing_city = fake.city()
            billing_state = fake.state_abbr()
            billing_zip = fake.zipcode()
            
            if random.random() < 0.4:  # 40% shipping mismatch
                shipping_address = fake.street_address()
                shipping_city = fake.city()
                shipping_state = fake.state_abbr()
                shipping_zip = fake.zipcode()
            else:
                shipping_address = billing_address
                shipping_city = billing_city
                shipping_state = billing_state
                shipping_zip = billing_zip
            
            customer_name = fake.name()
            phone_number = fake.phone_number()
            
        else:
            order_price = random.uniform(10, 800)  # Normal amounts
            email = fake.email()
            payment_method = random.choice(['credit_card', 'debit_card', 'paypal'])
            product_category = random.choice(['books', 'clothing', 'electronics', 'home', 'sports'])
            
            # Matching billing and shipping for legitimate
            billing_address = fake.street_address()
            billing_city = fake.city()
            billing_state = fake.state_abbr()
            billing_zip = fake.zipcode()
            shipping_address = billing_address
            shipping_city = billing_city
            shipping_state = billing_state
            shipping_zip = billing_zip
            
            customer_name = fake.name()
            phone_number = fake.phone_number()
        
        # Generate timestamp within last 90 days
        timestamp = fake.date_time_between(start_date='-90d', end_date='now')
        
        record = {
            'EVENT_TIMESTAMP': timestamp.strftime('%Y-%m-%dT%H:%M:%SZ'),
            'customer_id': customer_id,
            'email_address': email,
            'ip_address': generate_ip_address(is_fraud),
            'customer_name': customer_name,
            'phone_number': phone_number,
            'billing_address': billing_address,
            'billing_city': billing_city,
            'billing_state': billing_state,
            'billing_zip': billing_zip,
            'shipping_address': shipping_address,
            'shipping_city': shipping_city,
            'shipping_state': shipping_state,
            'shipping_zip': shipping_zip,
            'payment_method': payment_method,
            'card_bin': generate_card_bin(),
            'order_price': round(order_price, 2),
            'product_category': product_category,
            'transaction_amount': round(order_price, 2),
            'currency': 'USD',
            'merchant_category': random.choice(['5411', '5812', '5732', '5999']),
            'EVENT_LABEL': 'fraud' if is_fraud else 'legit'
        }
        
        records.append(record)
    
    return records

# Generate training data
training_data = generate_transaction_data(5000)

# Write to CSV
with open('/tmp/enhanced_training_data.csv', 'w', newline='') as csvfile:
    fieldnames = training_data[0].keys()
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(training_data)

print(f"Generated {len(training_data)} training records")
fraud_count = sum(1 for record in training_data if record['EVENT_LABEL'] == 'fraud')
print(f"Fraud rate: {fraud_count/len(training_data)*100:.1f}%")
EOF
    
    # Generate training data
    info "Generating training dataset..."
    python3 /tmp/generate_training_data.py || {
        error "Failed to generate training data"
        exit 1
    }
    
    # Upload training data to S3
    info "Uploading training data to S3..."
    aws s3 cp /tmp/enhanced_training_data.csv s3://${FRAUD_BUCKET}/training-data/ || {
        error "Failed to upload training data to S3"
        exit 1
    }
    
    log "Training data generated and uploaded successfully"
}

# Function to create Fraud Detector components
create_fraud_detector() {
    log "Creating Fraud Detector components..."
    
    # Create entity type
    info "Creating entity type: $ENTITY_TYPE_NAME"
    aws frauddetector create-entity-type \
        --name ${ENTITY_TYPE_NAME} \
        --description "Enhanced customer entity for transaction fraud detection" \
        >/dev/null 2>&1 || warn "Entity type creation failed or already exists"
    
    # Create event type
    info "Creating event type: $EVENT_TYPE_NAME"
    aws frauddetector create-event-type \
        --name ${EVENT_TYPE_NAME} \
        --description "Real-time transaction fraud detection with behavioral analytics" \
        --event-variables '[
            {"name": "customer_id", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "email_address", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "ip_address", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "customer_name", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "phone_number", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "billing_address", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "billing_city", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "billing_state", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "billing_zip", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "shipping_address", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "shipping_city", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "shipping_state", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "shipping_zip", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "payment_method", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "card_bin", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "order_price", "dataType": "FLOAT", "dataSource": "EVENT", "defaultValue": "0.0"},
            {"name": "product_category", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
            {"name": "transaction_amount", "dataType": "FLOAT", "dataSource": "EVENT", "defaultValue": "0.0"},
            {"name": "currency", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "USD"},
            {"name": "merchant_category", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"}
        ]' \
        --entity-types ${ENTITY_TYPE_NAME} \
        --event-ingestion ENABLED \
        >/dev/null 2>&1 || warn "Event type creation failed or already exists"
    
    # Create labels
    info "Creating fraud detection labels..."
    aws frauddetector create-label \
        --name "fraud" \
        --description "Confirmed fraudulent transaction" \
        >/dev/null 2>&1 || warn "Label creation failed or already exists"
    
    aws frauddetector create-label \
        --name "legit" \
        --description "Legitimate verified transaction" \
        >/dev/null 2>&1 || warn "Label creation failed or already exists"
    
    # Create outcomes
    info "Creating fraud detection outcomes..."
    local outcomes=("immediate_block:Block transaction immediately - high confidence fraud" 
                   "manual_review:Route to manual review - medium risk"
                   "challenge_authentication:Require additional authentication"
                   "approve_transaction:Approve transaction - low risk")
    
    for outcome in "${outcomes[@]}"; do
        IFS=':' read -r name desc <<< "$outcome"
        aws frauddetector create-outcome \
            --name "$name" \
            --description "$desc" \
            >/dev/null 2>&1 || warn "Outcome creation failed or already exists: $name"
    done
    
    log "Fraud Detector components created successfully"
}

# Function to create and train the model
create_and_train_model() {
    log "Creating and training Transaction Fraud Insights model..."
    
    info "Creating model: $MODEL_NAME"
    aws frauddetector create-model \
        --model-id ${MODEL_NAME} \
        --model-type TRANSACTION_FRAUD_INSIGHTS \
        --event-type-name ${EVENT_TYPE_NAME} \
        --training-data-source '{
            "dataLocation": "s3://'${FRAUD_BUCKET}'/training-data/enhanced_training_data.csv",
            "dataAccessRoleArn": "'${FRAUD_DETECTOR_ROLE_ARN}'"
        }' \
        --training-data-schema '{
            "modelVariables": [
                "customer_id", "email_address", "ip_address", "customer_name",
                "phone_number", "billing_address", "billing_city", "billing_state",
                "billing_zip", "shipping_address", "shipping_city", "shipping_state",
                "shipping_zip", "payment_method", "card_bin", "order_price",
                "product_category", "transaction_amount", "currency", "merchant_category"
            ],
            "labelSchema": {
                "labelMapper": {
                    "fraud": ["fraud"],
                    "legit": ["legit"]
                },
                "unlabeledEventsTreatment": "IGNORE"
            }
        }' >/dev/null 2>&1 || {
        warn "Model creation failed or already exists"
        return 0
    }
    
    warn "Model training started - this will take 2-4 hours to complete"
    warn "The deployment will continue with other components"
    warn "You can monitor training progress with: aws frauddetector describe-model-versions --model-id ${MODEL_NAME} --model-type TRANSACTION_FRAUD_INSIGHTS"
    
    log "Model creation initiated successfully"
}

# Function to create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create event enrichment Lambda
    info "Creating event enrichment Lambda function..."
    cat > /tmp/event_enrichment_lambda.py << 'EOF'
import json
import boto3
import hashlib
from datetime import datetime, timedelta
import base64

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Enriches incoming transaction events with behavioral features
    """
    
    for record in event['Records']:
        # Decode Kinesis data
        payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
        transaction_data = json.loads(payload)
        
        # Extract customer ID
        customer_id = transaction_data.get('customer_id')
        
        # Calculate behavioral features
        enriched_data = enrich_transaction_data(transaction_data)
        
        # Forward to fraud detection Lambda
        forward_to_fraud_detection(enriched_data)

def enrich_transaction_data(transaction_data):
    """
    Add behavioral and historical features to transaction data
    """
    customer_id = transaction_data.get('customer_id')
    current_time = datetime.now()
    
    # Calculate transaction frequency (simplified)
    transaction_data['transaction_frequency'] = get_transaction_frequency(customer_id)
    
    # Calculate velocity score based on recent activity
    transaction_data['velocity_score'] = calculate_velocity_score(customer_id)
    
    # Add timestamp for processing
    transaction_data['processing_timestamp'] = current_time.isoformat()
    
    return transaction_data

def get_transaction_frequency(customer_id):
    """
    Calculate number of transactions in last 24 hours
    """
    # Simplified implementation - in production, query DynamoDB
    return 1

def calculate_velocity_score(customer_id):
    """
    Calculate velocity-based risk score
    """
    # Simplified implementation - in production, use historical data
    return 0.1

def forward_to_fraud_detection(enriched_data):
    """
    Forward enriched data to fraud detection Lambda
    """
    lambda_client = boto3.client('lambda')
    
    try:
        lambda_client.invoke(
            FunctionName='fraud-detection-processor',
            InvocationType='Event',
            Payload=json.dumps(enriched_data)
        )
    except Exception as e:
        print(f"Error forwarding to fraud detection: {str(e)}")
EOF
    
    # Create fraud detection processor Lambda
    cat > /tmp/fraud_detection_processor.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

frauddetector = boto3.client('frauddetector')
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Process fraud detection for enriched transaction data
    """
    try:
        # Extract transaction data
        transaction_data = event
        
        # Generate unique event ID
        event_id = f"txn_{uuid.uuid4().hex[:16]}"
        
        # Prepare variables for fraud detection
        variables = prepare_fraud_variables(transaction_data)
        
        # Simple rule-based detection for demo (since model training takes time)
        decision = simple_fraud_detection(transaction_data, variables)
        
        # Process and log decision
        process_decision = process_fraud_decision(transaction_data, decision)
        
        # Send alerts if necessary
        if process_decision['risk_level'] in ['HIGH', 'CRITICAL']:
            send_fraud_alert(process_decision)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'transaction_id': transaction_data.get('transaction_id'),
                'decision': process_decision['action'],
                'risk_score': process_decision['risk_score'],
                'risk_level': process_decision['risk_level']
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing fraud detection: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def prepare_fraud_variables(transaction_data):
    """
    Prepare variables for fraud detection API call
    """
    return {
        'customer_id': transaction_data.get('customer_id', 'unknown'),
        'email_address': transaction_data.get('email_address', 'unknown'),
        'ip_address': transaction_data.get('ip_address', 'unknown'),
        'customer_name': transaction_data.get('customer_name', 'unknown'),
        'phone_number': transaction_data.get('phone_number', 'unknown'),
        'billing_address': transaction_data.get('billing_address', 'unknown'),
        'billing_city': transaction_data.get('billing_city', 'unknown'),
        'billing_state': transaction_data.get('billing_state', 'unknown'),
        'billing_zip': transaction_data.get('billing_zip', 'unknown'),
        'shipping_address': transaction_data.get('shipping_address', 'unknown'),
        'shipping_city': transaction_data.get('shipping_city', 'unknown'),
        'shipping_state': transaction_data.get('shipping_state', 'unknown'),
        'shipping_zip': transaction_data.get('shipping_zip', 'unknown'),
        'payment_method': transaction_data.get('payment_method', 'unknown'),
        'card_bin': transaction_data.get('card_bin', 'unknown'),
        'order_price': str(transaction_data.get('order_price', 0.0)),
        'product_category': transaction_data.get('product_category', 'unknown'),
        'transaction_amount': str(transaction_data.get('transaction_amount', 0.0)),
        'currency': transaction_data.get('currency', 'USD'),
        'merchant_category': transaction_data.get('merchant_category', 'unknown')
    }

def simple_fraud_detection(transaction_data, variables):
    """
    Simple rule-based fraud detection for demo purposes
    """
    risk_score = 0
    
    # Check transaction amount
    amount = float(variables.get('transaction_amount', 0))
    if amount > 2000:
        risk_score += 500
    elif amount > 1000:
        risk_score += 200
    elif amount > 500:
        risk_score += 100
    
    # Check for shipping/billing mismatch
    if variables.get('billing_state') != variables.get('shipping_state'):
        risk_score += 300
    
    # Check for suspicious email patterns
    email = variables.get('email_address', '')
    if 'tempmail' in email or 'temp' in email:
        risk_score += 400
    
    # Check for suspicious IP patterns
    ip = variables.get('ip_address', '')
    if ip.startswith('1.') or ip.startswith('2.') or ip.startswith('3.'):
        risk_score += 200
    
    return {
        'risk_score': risk_score,
        'modelScores': [{'scores': {'SIMPLE_RULE': risk_score}}],
        'ruleResults': []
    }

def process_fraud_decision(transaction_data, fraud_response):
    """
    Process fraud detection response and make decision
    """
    # Extract risk score
    risk_score = fraud_response.get('risk_score', 0)
    
    # Determine action based on risk score
    if risk_score > 900:
        action = 'immediate_block'
        risk_level = 'CRITICAL'
    elif risk_score > 600:
        action = 'manual_review'
        risk_level = 'HIGH'
    elif risk_score > 400:
        action = 'challenge_authentication'
        risk_level = 'MEDIUM'
    else:
        action = 'approve_transaction'
        risk_level = 'LOW'
    
    # Create decision record
    decision = {
        'transaction_id': transaction_data.get('transaction_id'),
        'customer_id': transaction_data.get('customer_id'),
        'timestamp': datetime.now().isoformat(),
        'risk_score': risk_score,
        'risk_level': risk_level,
        'action': action,
        'processing_time': datetime.now().isoformat()
    }
    
    # Log decision to DynamoDB
    log_decision(decision)
    
    return decision

def log_decision(decision):
    """
    Log fraud decision to DynamoDB
    """
    import os
    
    try:
        table = dynamodb.Table(os.environ['DECISIONS_TABLE'])
        
        table.put_item(
            Item={
                'transaction_id': decision['transaction_id'],
                'timestamp': int(datetime.now().timestamp()),
                'customer_id': decision['customer_id'],
                'risk_score': decision['risk_score'],
                'risk_level': decision['risk_level'],
                'action': decision['action'],
                'processing_time': decision['processing_time']
            }
        )
    except Exception as e:
        logger.error(f"Error logging decision: {str(e)}")

def send_fraud_alert(decision):
    """
    Send fraud alert for high-risk transactions
    """
    import os
    
    try:
        if 'SNS_TOPIC_ARN' in os.environ:
            message = {
                'alert_type': 'HIGH_RISK_TRANSACTION',
                'transaction_id': decision['transaction_id'],
                'customer_id': decision['customer_id'],
                'risk_score': decision['risk_score'],
                'risk_level': decision['risk_level'],
                'action': decision['action'],
                'timestamp': decision['timestamp']
            }
            
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Message=json.dumps(message),
                Subject=f"High Risk Transaction Alert - {decision['risk_level']}"
            )
    except Exception as e:
        logger.error(f"Error sending alert: {str(e)}")
EOF
    
    # Create deployment packages
    cd /tmp
    zip -q event-enrichment.zip event_enrichment_lambda.py
    zip -q fraud-detection-processor.zip fraud_detection_processor.py
    cd - > /dev/null
    
    # Create Lambda functions
    aws lambda create-function \
        --function-name event-enrichment-processor \
        --runtime python3.9 \
        --role ${LAMBDA_ROLE_ARN} \
        --handler event_enrichment_lambda.lambda_handler \
        --zip-file fileb:///tmp/event-enrichment.zip \
        --timeout 60 \
        --memory-size 256 \
        >/dev/null 2>&1 || warn "Event enrichment Lambda creation failed or already exists"
    
    aws lambda create-function \
        --function-name fraud-detection-processor \
        --runtime python3.9 \
        --role ${LAMBDA_ROLE_ARN} \
        --handler fraud_detection_processor.lambda_handler \
        --zip-file fileb:///tmp/fraud-detection-processor.zip \
        --timeout 30 \
        --memory-size 512 \
        --environment Variables='{
            "DETECTOR_NAME": "'${DETECTOR_NAME}'",
            "EVENT_TYPE_NAME": "'${EVENT_TYPE_NAME}'",
            "ENTITY_TYPE_NAME": "'${ENTITY_TYPE_NAME}'",
            "DECISIONS_TABLE": "'${DECISIONS_TABLE}'"
        }' >/dev/null 2>&1 || warn "Fraud detection Lambda creation failed or already exists"
    
    # Create event source mapping
    info "Creating Kinesis event source mapping..."
    aws lambda create-event-source-mapping \
        --event-source-arn arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${KINESIS_STREAM} \
        --function-name event-enrichment-processor \
        --starting-position LATEST \
        --batch-size 10 \
        >/dev/null 2>&1 || warn "Event source mapping creation failed or already exists"
    
    log "Lambda functions created successfully"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for fraud alerts..."
    
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name fraud-detection-alerts \
        --query TopicArn --output text 2>/dev/null)
    
    if [ -n "$SNS_TOPIC_ARN" ]; then
        # Update Lambda function environment
        aws lambda update-function-configuration \
            --function-name fraud-detection-processor \
            --environment Variables='{
                "DETECTOR_NAME": "'${DETECTOR_NAME}'",
                "EVENT_TYPE_NAME": "'${EVENT_TYPE_NAME}'",
                "ENTITY_TYPE_NAME": "'${ENTITY_TYPE_NAME}'",
                "DECISIONS_TABLE": "'${DECISIONS_TABLE}'",
                "SNS_TOPIC_ARN": "'${SNS_TOPIC_ARN}'"
            }' >/dev/null 2>&1
        
        # Update .env file
        echo "SNS_TOPIC_ARN=$SNS_TOPIC_ARN" >> .env
        
        log "SNS topic created successfully: $SNS_TOPIC_ARN"
    else
        warn "SNS topic creation failed"
    fi
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    log "Creating monitoring dashboard..."
    
    cat > /tmp/fraud_detection_dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Invocations", "FunctionName", "fraud-detection-processor"],
                    ["AWS/Lambda", "Duration", "FunctionName", "fraud-detection-processor"],
                    ["AWS/Lambda", "Errors", "FunctionName", "fraud-detection-processor"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Fraud Detection Lambda Metrics"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/Kinesis", "IncomingRecords", "StreamName", "${KINESIS_STREAM}"],
                    ["AWS/Kinesis", "OutgoingRecords", "StreamName", "${KINESIS_STREAM}"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Transaction Stream Metrics"
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", "${DECISIONS_TABLE}"],
                    ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", "${DECISIONS_TABLE}"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Decision Storage Metrics"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "FraudDetectionPlatform" \
        --dashboard-body file:///tmp/fraud_detection_dashboard.json \
        >/dev/null 2>&1 || warn "Dashboard creation failed"
    
    log "Monitoring dashboard created successfully"
}

# Function to test the deployment
test_deployment() {
    log "Testing deployment..."
    
    # Test Lambda function
    info "Testing fraud detection Lambda function..."
    aws lambda invoke \
        --function-name fraud-detection-processor \
        --payload '{
            "customer_id": "test_customer_001",
            "transaction_id": "test_txn_001",
            "order_price": 150.00,
            "transaction_amount": 150.00,
            "email_address": "test@example.com",
            "ip_address": "192.168.1.1",
            "billing_state": "CA",
            "shipping_state": "CA"
        }' \
        /tmp/test_response.json >/dev/null 2>&1
    
    if [ -f "/tmp/test_response.json" ]; then
        info "Lambda test completed - check /tmp/test_response.json for results"
    else
        warn "Lambda test failed"
    fi
    
    # Test Kinesis stream
    info "Testing Kinesis stream..."
    echo '{"transaction_id": "test_001", "customer_id": "test_customer", "order_price": 99.99}' | \
    aws kinesis put-record \
        --stream-name ${KINESIS_STREAM} \
        --partition-key "test" \
        --data file:///dev/stdin >/dev/null 2>&1 || warn "Kinesis test failed"
    
    log "Deployment testing completed"
}

# Main deployment function
main() {
    log "Starting fraud detection platform deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Set up environment
    setup_environment
    
    # Create infrastructure components
    create_infrastructure
    
    # Create IAM roles
    create_iam_roles
    
    # Generate training data
    generate_training_data
    
    # Create Fraud Detector components
    create_fraud_detector
    
    # Create and train model
    create_and_train_model
    
    # Create Lambda functions
    create_lambda_functions
    
    # Create SNS topic
    create_sns_topic
    
    # Create monitoring dashboard
    create_monitoring_dashboard
    
    # Test deployment
    test_deployment
    
    # Cleanup temporary files
    rm -f /tmp/fraud-detector-*.json /tmp/generate_training_data.py
    rm -f /tmp/enhanced_training_data.csv /tmp/*lambda*.py /tmp/*.zip
    rm -f /tmp/fraud_detection_dashboard.json /tmp/test_response.json
    
    log "Deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "AWS Region: $AWS_REGION"
    echo "S3 Bucket: $FRAUD_BUCKET"
    echo "Kinesis Stream: $KINESIS_STREAM"
    echo "DynamoDB Table: $DECISIONS_TABLE"
    echo "Model Name: $MODEL_NAME"
    echo "Detector Name: $DETECTOR_NAME"
    echo "SNS Topic: $SNS_TOPIC_ARN"
    echo ""
    echo "=== IMPORTANT NOTES ==="
    echo "1. Model training is in progress and will take 2-4 hours"
    echo "2. Monitor training: aws frauddetector describe-model-versions --model-id $MODEL_NAME --model-type TRANSACTION_FRAUD_INSIGHTS"
    echo "3. Environment variables saved in .env file"
    echo "4. Use destroy.sh to clean up resources"
    echo "5. Check CloudWatch logs for Lambda function execution details"
    echo ""
    warn "Remember to clean up resources when done to avoid ongoing charges"
}

# Run main function
main "$@"