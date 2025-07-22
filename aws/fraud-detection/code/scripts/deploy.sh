#!/bin/bash

# Amazon Fraud Detector Deployment Script
# This script automates the deployment of a fraud detection system using Amazon Fraud Detector

set -euo pipefail

# Colors for output
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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    log "Checking AWS CLI configuration..."
    
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not configured. Run 'aws configure' to set region."
        exit 1
    fi
    
    success "AWS CLI configured - Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION"
}

# Function to check required permissions
check_permissions() {
    log "Checking required AWS permissions..."
    
    local required_services=("frauddetector" "s3" "iam" "lambda" "sts")
    local permission_errors=0
    
    for service in "${required_services[@]}"; do
        case $service in
            "frauddetector")
                if ! aws frauddetector list-entity-types --max-results 1 >/dev/null 2>&1; then
                    error "Missing Amazon Fraud Detector permissions"
                    ((permission_errors++))
                fi
                ;;
            "s3")
                if ! aws s3 ls >/dev/null 2>&1; then
                    error "Missing S3 permissions"
                    ((permission_errors++))
                fi
                ;;
            "iam")
                if ! aws iam list-roles --max-items 1 >/dev/null 2>&1; then
                    error "Missing IAM permissions"
                    ((permission_errors++))
                fi
                ;;
            "lambda")
                if ! aws lambda list-functions --max-items 1 >/dev/null 2>&1; then
                    error "Missing Lambda permissions"
                    ((permission_errors++))
                fi
                ;;
        esac
    done
    
    if [ $permission_errors -gt 0 ]; then
        error "Missing required permissions. Please ensure your AWS user/role has appropriate policies."
        exit 1
    fi
    
    success "All required permissions verified"
}

# Function to generate unique resource names
generate_resource_names() {
    log "Generating unique resource names..."
    
    # Generate random suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    export FRAUD_BUCKET="fraud-detection-data-${RANDOM_SUFFIX}"
    export EVENT_TYPE_NAME="payment_fraud_${RANDOM_SUFFIX}"
    export ENTITY_TYPE_NAME="customer_${RANDOM_SUFFIX}"
    export MODEL_NAME="fraud_detection_model_${RANDOM_SUFFIX}"
    export DETECTOR_NAME="payment_fraud_detector_${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="fraud-prediction-processor-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="FraudDetectorServiceRole-${RANDOM_SUFFIX}"
    
    success "Resource names generated with suffix: ${RANDOM_SUFFIX}"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for training data..."
    
    if aws s3 ls "s3://${FRAUD_BUCKET}" >/dev/null 2>&1; then
        warning "S3 bucket ${FRAUD_BUCKET} already exists"
        return 0
    fi
    
    # Create bucket with appropriate region settings
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://${FRAUD_BUCKET}"
    else
        aws s3 mb "s3://${FRAUD_BUCKET}" --region "$AWS_REGION"
    fi
    
    # Enable versioning and encryption
    aws s3api put-bucket-versioning \
        --bucket "$FRAUD_BUCKET" \
        --versioning-configuration Status=Enabled
    
    aws s3api put-bucket-encryption \
        --bucket "$FRAUD_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    success "S3 bucket created: ${FRAUD_BUCKET}"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for Fraud Detector..."
    
    # Check if role already exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        warning "IAM role ${IAM_ROLE_NAME} already exists"
        export FRAUD_DETECTOR_ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE_NAME" --query Role.Arn --output text)
        return 0
    fi
    
    # Create trust policy
    cat > /tmp/fraud-detector-trust-policy.json << EOF
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
    
    # Create IAM role
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/fraud-detector-trust-policy.json \
        --description "Service role for Amazon Fraud Detector"
    
    # Attach policy
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonFraudDetectorFullAccessPolicy
    
    # Get role ARN
    export FRAUD_DETECTOR_ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE_NAME" --query Role.Arn --output text)
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    success "IAM role created: ${FRAUD_DETECTOR_ROLE_ARN}"
}

# Function to create training data
create_training_data() {
    log "Creating and uploading training data..."
    
    # Create sample training data
    cat > /tmp/training-data.csv << EOF
event_timestamp,customer_id,email_address,ip_address,customer_name,phone_number,billing_address,billing_city,billing_state,billing_zip,shipping_address,shipping_city,shipping_state,shipping_zip,payment_method,card_bin,order_price,product_category,EVENT_LABEL
2024-01-15T10:30:00Z,cust001,john.doe@email.com,192.168.1.1,John Doe,555-1234,123 Main St,Seattle,WA,98101,123 Main St,Seattle,WA,98101,credit_card,411111,99.99,electronics,legit
2024-01-15T11:45:00Z,cust002,jane.smith@email.com,10.0.0.1,Jane Smith,555-5678,456 Oak Ave,Portland,OR,97201,456 Oak Ave,Portland,OR,97201,credit_card,424242,1299.99,electronics,legit
2024-01-15T12:15:00Z,cust003,fraud@temp.com,1.2.3.4,Test User,555-0000,789 Pine St,New York,NY,10001,999 Different St,Los Angeles,CA,90210,credit_card,444444,2500.00,jewelry,fraud
2024-01-15T13:30:00Z,cust004,alice.johnson@email.com,172.16.0.1,Alice Johnson,555-9876,321 Elm St,Chicago,IL,60601,321 Elm St,Chicago,IL,60601,debit_card,555555,45.99,books,legit
2024-01-15T14:45:00Z,cust005,bob.wilson@email.com,192.168.2.1,Bob Wilson,555-4321,654 Maple Dr,Denver,CO,80201,654 Maple Dr,Denver,CO,80201,credit_card,666666,150.00,clothing,legit
2024-01-15T15:00:00Z,cust006,suspicious@tempmail.com,5.6.7.8,Fake Name,555-1111,123 Fake St,Nowhere,XX,00000,456 Other St,Somewhere,YY,11111,credit_card,777777,5000.00,electronics,fraud
2024-01-16T09:15:00Z,cust007,normal@example.com,192.168.1.50,Normal User,555-2222,789 Real St,Austin,TX,78701,789 Real St,Austin,TX,78701,credit_card,888888,75.50,books,legit
2024-01-16T10:30:00Z,cust008,legit@domain.com,10.0.1.1,Legitimate Customer,555-3333,456 True Ave,Miami,FL,33101,456 True Ave,Miami,FL,33101,debit_card,999999,250.00,clothing,legit
2024-01-16T11:45:00Z,cust009,scammer@fake.net,9.8.7.6,Scam Artist,555-4444,999 Bogus Rd,Fake City,ZZ,99999,111 Wrong St,Bad Town,AA,11111,credit_card,123456,3000.00,jewelry,fraud
2024-01-16T13:00:00Z,cust010,customer@real.com,172.16.1.1,Real Customer,555-5555,123 Honest St,Boston,MA,02101,123 Honest St,Boston,MA,02101,credit_card,654321,120.00,electronics,legit
EOF
    
    # Upload to S3
    aws s3 cp /tmp/training-data.csv "s3://${FRAUD_BUCKET}/training-data.csv"
    
    success "Training data uploaded to S3"
}

# Function to create Fraud Detector components
create_fraud_detector_components() {
    log "Creating Fraud Detector entity and event types..."
    
    # Create entity type
    if ! aws frauddetector describe-entity-type --name "$ENTITY_TYPE_NAME" >/dev/null 2>&1; then
        aws frauddetector create-entity-type \
            --name "$ENTITY_TYPE_NAME" \
            --description "Customer entity for fraud detection"
        success "Entity type created: ${ENTITY_TYPE_NAME}"
    else
        warning "Entity type ${ENTITY_TYPE_NAME} already exists"
    fi
    
    # Create event type
    if ! aws frauddetector describe-event-type --name "$EVENT_TYPE_NAME" >/dev/null 2>&1; then
        aws frauddetector create-event-type \
            --name "$EVENT_TYPE_NAME" \
            --description "Payment fraud detection event" \
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
                {"name": "payment_method", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
                {"name": "card_bin", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"},
                {"name": "order_price", "dataType": "FLOAT", "dataSource": "EVENT", "defaultValue": "0.0"},
                {"name": "product_category", "dataType": "STRING", "dataSource": "EVENT", "defaultValue": "unknown"}
            ]' \
            --entity-types "$ENTITY_TYPE_NAME" \
            --event-ingestion ENABLED
        success "Event type created: ${EVENT_TYPE_NAME}"
    else
        warning "Event type ${EVENT_TYPE_NAME} already exists"
    fi
    
    # Create labels
    for label in fraud legit; do
        if ! aws frauddetector describe-label --name "$label" >/dev/null 2>&1; then
            aws frauddetector create-label \
                --name "$label" \
                --description "$([ "$label" = "fraud" ] && echo "Fraudulent transaction" || echo "Legitimate transaction")"
            success "Label created: ${label}"
        else
            warning "Label ${label} already exists"
        fi
    done
}

# Function to create and train ML model
create_and_train_model() {
    log "Creating and training ML model..."
    
    # Check if model already exists
    if aws frauddetector describe-model-versions --model-id "$MODEL_NAME" --model-type ONLINE_FRAUD_INSIGHTS >/dev/null 2>&1; then
        warning "Model ${MODEL_NAME} already exists"
        return 0
    fi
    
    # Create model
    aws frauddetector create-model \
        --model-id "$MODEL_NAME" \
        --model-type ONLINE_FRAUD_INSIGHTS \
        --event-type-name "$EVENT_TYPE_NAME" \
        --training-data-source "{
            \"dataLocation\": \"s3://${FRAUD_BUCKET}/training-data.csv\",
            \"dataAccessRoleArn\": \"${FRAUD_DETECTOR_ROLE_ARN}\"
        }" \
        --training-data-schema '{
            "modelVariables": [
                "customer_id", "email_address", "ip_address", "customer_name",
                "phone_number", "billing_address", "billing_city", "billing_state",
                "billing_zip", "payment_method", "card_bin", "order_price",
                "product_category"
            ],
            "labelSchema": {
                "labelMapper": {
                    "fraud": ["fraud"],
                    "legit": ["legit"]
                },
                "unlabeledEventsTreatment": "IGNORE"
            }
        }'
    
    success "Model created and training started: ${MODEL_NAME}"
    log "Model training will take approximately 45-60 minutes"
}

# Function to wait for model training completion
wait_for_model_training() {
    log "Waiting for model training to complete..."
    
    local max_attempts=72  # 6 hours max (5 min intervals)
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local status=$(aws frauddetector get-model-version \
            --model-id "$MODEL_NAME" \
            --model-type ONLINE_FRAUD_INSIGHTS \
            --model-version-number 1.0 \
            --query 'status' --output text 2>/dev/null || echo "UNKNOWN")
        
        case $status in
            "TRAINING_COMPLETE")
                success "Model training completed successfully"
                return 0
                ;;
            "TRAINING_FAILED")
                error "Model training failed"
                exit 1
                ;;
            "TRAINING_IN_PROGRESS")
                log "Training in progress... (attempt $((attempt + 1))/${max_attempts})"
                ;;
            *)
                log "Training status: ${status} (attempt $((attempt + 1))/${max_attempts})"
                ;;
        esac
        
        sleep 300  # Wait 5 minutes
        ((attempt++))
    done
    
    error "Model training timed out after 6 hours"
    exit 1
}

# Function to create outcomes and rules
create_outcomes_and_rules() {
    log "Creating outcomes..."
    
    # Create outcomes
    for outcome in review block approve; do
        local description
        case $outcome in
            "review") description="Send transaction for manual review" ;;
            "block") description="Block fraudulent transaction" ;;
            "approve") description="Approve legitimate transaction" ;;
        esac
        
        if ! aws frauddetector describe-outcome --name "$outcome" >/dev/null 2>&1; then
            aws frauddetector create-outcome \
                --name "$outcome" \
                --description "$description"
            success "Outcome created: ${outcome}"
        else
            warning "Outcome ${outcome} already exists"
        fi
    done
    
    log "Creating fraud detection rules..."
    
    # Note: Rules will be created when we create the detector
}

# Function to create and activate detector
create_detector() {
    log "Creating fraud detector..."
    
    # Check if detector already exists
    if aws frauddetector describe-detector --detector-id "$DETECTOR_NAME" >/dev/null 2>&1; then
        warning "Detector ${DETECTOR_NAME} already exists"
        return 0
    fi
    
    # Create detector
    aws frauddetector create-detector \
        --detector-id "$DETECTOR_NAME" \
        --description "Payment fraud detection system" \
        --event-type-name "$EVENT_TYPE_NAME"
    
    # Create rules and detector version
    aws frauddetector create-rule \
        --rule-id "high_risk_rule" \
        --detector-id "$DETECTOR_NAME" \
        --description "Flag high-risk transactions for review" \
        --expression "\$${MODEL_NAME}_insightscore > 700 or \$order_price > 1000" \
        --language DETECTORPL \
        --outcomes '["review"]'
    
    aws frauddetector create-rule \
        --rule-id "obvious_fraud_rule" \
        --detector-id "$DETECTOR_NAME" \
        --description "Block obvious fraudulent transactions" \
        --expression "\$${MODEL_NAME}_insightscore > 900" \
        --language DETECTORPL \
        --outcomes '["block"]'
    
    aws frauddetector create-rule \
        --rule-id "low_risk_rule" \
        --detector-id "$DETECTOR_NAME" \
        --description "Approve low-risk transactions" \
        --expression "\$${MODEL_NAME}_insightscore <= 700" \
        --language DETECTORPL \
        --outcomes '["approve"]'
    
    # Create detector version
    aws frauddetector create-detector-version \
        --detector-id "$DETECTOR_NAME" \
        --description "Initial version with ML model and rules" \
        --rules "[
            {
                \"detectorId\": \"${DETECTOR_NAME}\",
                \"ruleId\": \"high_risk_rule\",
                \"ruleVersion\": \"1\"
            },
            {
                \"detectorId\": \"${DETECTOR_NAME}\",
                \"ruleId\": \"obvious_fraud_rule\",
                \"ruleVersion\": \"1\"
            },
            {
                \"detectorId\": \"${DETECTOR_NAME}\",
                \"ruleId\": \"low_risk_rule\",
                \"ruleVersion\": \"1\"
            }
        ]" \
        --model-versions "[
            {
                \"modelId\": \"${MODEL_NAME}\",
                \"modelType\": \"ONLINE_FRAUD_INSIGHTS\",
                \"modelVersionNumber\": \"1.0\"
            }
        ]" \
        --rule-execution-mode FIRST_MATCHED
    
    # Activate detector version
    aws frauddetector update-detector-version-status \
        --detector-id "$DETECTOR_NAME" \
        --detector-version-id "1" \
        --status ACTIVE
    
    success "Fraud detector created and activated: ${DETECTOR_NAME}"
}

# Function to create Lambda function for processing
create_lambda_function() {
    log "Creating Lambda function for fraud processing..."
    
    # Check if function already exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        warning "Lambda function ${LAMBDA_FUNCTION_NAME} already exists"
        return 0
    fi
    
    # Create Lambda function code
    cat > /tmp/fraud-processor.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

frauddetector = boto3.client('frauddetector')

def lambda_handler(event, context):
    try:
        # Extract transaction data from event
        transaction_data = event.get('transaction', {})
        
        # Prepare variables for fraud detection
        variables = {
            'customer_id': transaction_data.get('customer_id', 'unknown'),
            'email_address': transaction_data.get('email_address', 'unknown'),
            'ip_address': transaction_data.get('ip_address', 'unknown'),
            'customer_name': transaction_data.get('customer_name', 'unknown'),
            'phone_number': transaction_data.get('phone_number', 'unknown'),
            'billing_address': transaction_data.get('billing_address', 'unknown'),
            'billing_city': transaction_data.get('billing_city', 'unknown'),
            'billing_state': transaction_data.get('billing_state', 'unknown'),
            'billing_zip': transaction_data.get('billing_zip', 'unknown'),
            'payment_method': transaction_data.get('payment_method', 'unknown'),
            'card_bin': transaction_data.get('card_bin', 'unknown'),
            'order_price': str(transaction_data.get('order_price', 0.0)),
            'product_category': transaction_data.get('product_category', 'unknown')
        }
        
        # Get fraud prediction
        response = frauddetector.get_event_prediction(
            detectorId=event['detector_id'],
            eventId=f"txn_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
            eventTypeName=event['event_type_name'],
            entities=[{
                'entityType': event['entity_type_name'],
                'entityId': variables['customer_id']
            }],
            eventTimestamp=datetime.now().isoformat(),
            eventVariables=variables
        )
        
        # Process results
        prediction_result = {
            'transaction_id': event.get('transaction_id'),
            'customer_id': variables['customer_id'],
            'timestamp': datetime.now().isoformat(),
            'fraud_prediction': response
        }
        
        # Extract outcomes and scores
        outcomes = response.get('ruleResults', [])
        model_scores = response.get('modelScores', [])
        
        # Log prediction results
        logger.info(f"Fraud prediction completed for transaction: {event.get('transaction_id')}")
        logger.info(f"Outcomes: {outcomes}")
        logger.info(f"Model scores: {model_scores}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(prediction_result)
        }
        
    except Exception as e:
        logger.error(f"Error processing fraud prediction: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'transaction_id': event.get('transaction_id')
            })
        }
EOF
    
    # Create deployment package
    cd /tmp
    zip fraud-processor.zip fraud-processor.py
    
    # Create execution role ARN (assuming standard Lambda execution role exists)
    local lambda_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/lambda-execution-role"
    
    # Check if the standard Lambda execution role exists, if not create it
    if ! aws iam get-role --role-name lambda-execution-role >/dev/null 2>&1; then
        log "Creating Lambda execution role..."
        
        cat > /tmp/lambda-trust-policy.json << EOF
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
        
        aws iam create-role \
            --role-name lambda-execution-role \
            --assume-role-policy-document file:///tmp/lambda-trust-policy.json
        
        aws iam attach-role-policy \
            --role-name lambda-execution-role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
        
        aws iam attach-role-policy \
            --role-name lambda-execution-role \
            --policy-arn arn:aws:iam::aws:policy/AmazonFraudDetectorFullAccessPolicy
        
        # Wait for role to be available
        sleep 10
    fi
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$lambda_role_arn" \
        --handler fraud-processor.lambda_handler \
        --zip-file fileb://fraud-processor.zip \
        --timeout 30 \
        --memory-size 128 \
        --description "Fraud detection processing function"
    
    success "Lambda function created: ${LAMBDA_FUNCTION_NAME}"
}

# Function to test the fraud detection system
test_fraud_detection() {
    log "Testing fraud detection system..."
    
    # Test with legitimate transaction
    log "Testing with legitimate transaction..."
    local legit_result=$(aws frauddetector get-event-prediction \
        --detector-id "$DETECTOR_NAME" \
        --event-id "test_legit_$(date +%s)" \
        --event-type-name "$EVENT_TYPE_NAME" \
        --entities "[{
            \"entityType\": \"${ENTITY_TYPE_NAME}\",
            \"entityId\": \"test_customer_001\"
        }]" \
        --event-timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --event-variables '{
            "customer_id": "test_customer_001",
            "email_address": "legitimate@example.com",
            "ip_address": "192.168.1.100",
            "customer_name": "John Smith",
            "phone_number": "555-1234",
            "billing_address": "123 Main St",
            "billing_city": "Seattle",
            "billing_state": "WA",
            "billing_zip": "98101",
            "payment_method": "credit_card",
            "card_bin": "411111",
            "order_price": "99.99",
            "product_category": "electronics"
        }' \
        --query 'ruleResults[0].outcomes[0]' --output text 2>/dev/null || echo "ERROR")
    
    if [ "$legit_result" != "ERROR" ]; then
        success "Legitimate transaction test: ${legit_result}"
    else
        warning "Legitimate transaction test failed"
    fi
    
    # Test with suspicious transaction
    log "Testing with suspicious transaction..."
    local fraud_result=$(aws frauddetector get-event-prediction \
        --detector-id "$DETECTOR_NAME" \
        --event-id "test_fraud_$(date +%s)" \
        --event-type-name "$EVENT_TYPE_NAME" \
        --entities "[{
            \"entityType\": \"${ENTITY_TYPE_NAME}\",
            \"entityId\": \"test_customer_002\"
        }]" \
        --event-timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --event-variables '{
            "customer_id": "test_customer_002",
            "email_address": "suspicious@tempmail.com",
            "ip_address": "1.2.3.4",
            "customer_name": "Fake Name",
            "phone_number": "555-0000",
            "billing_address": "123 Fake St",
            "billing_city": "Nowhere",
            "billing_state": "XX",
            "billing_zip": "00000",
            "payment_method": "credit_card",
            "card_bin": "444444",
            "order_price": "2999.99",
            "product_category": "electronics"
        }' \
        --query 'ruleResults[0].outcomes[0]' --output text 2>/dev/null || echo "ERROR")
    
    if [ "$fraud_result" != "ERROR" ]; then
        success "Suspicious transaction test: ${fraud_result}"
    else
        warning "Suspicious transaction test failed"
    fi
    
    success "Fraud detection tests completed"
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > /tmp/fraud-detector-deployment.json << EOF
{
    "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "aws_region": "${AWS_REGION}",
    "resources": {
        "s3_bucket": "${FRAUD_BUCKET}",
        "event_type_name": "${EVENT_TYPE_NAME}",
        "entity_type_name": "${ENTITY_TYPE_NAME}",
        "model_name": "${MODEL_NAME}",
        "detector_name": "${DETECTOR_NAME}",
        "lambda_function_name": "${LAMBDA_FUNCTION_NAME}",
        "iam_role_name": "${IAM_ROLE_NAME}",
        "iam_role_arn": "${FRAUD_DETECTOR_ROLE_ARN}"
    },
    "endpoints": {
        "fraud_detection_api": "aws frauddetector get-event-prediction --detector-id ${DETECTOR_NAME}",
        "lambda_function": "aws lambda invoke --function-name ${LAMBDA_FUNCTION_NAME}"
    }
}
EOF
    
    # Save to current directory
    cp /tmp/fraud-detector-deployment.json ./fraud-detector-deployment.json
    
    success "Deployment information saved to fraud-detector-deployment.json"
}

# Function to display deployment summary
display_summary() {
    echo
    echo "================================================"
    echo "🎉 FRAUD DETECTION SYSTEM DEPLOYMENT COMPLETE!"
    echo "================================================"
    echo
    echo "📊 Deployed Resources:"
    echo "  • S3 Bucket: ${FRAUD_BUCKET}"
    echo "  • Event Type: ${EVENT_TYPE_NAME}"
    echo "  • Entity Type: ${ENTITY_TYPE_NAME}"
    echo "  • ML Model: ${MODEL_NAME}"
    echo "  • Detector: ${DETECTOR_NAME}"
    echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  • IAM Role: ${IAM_ROLE_NAME}"
    echo
    echo "🔧 Usage Examples:"
    echo "  • Test fraud detection:"
    echo "    aws frauddetector get-event-prediction --detector-id ${DETECTOR_NAME} [...]"
    echo
    echo "  • Invoke Lambda function:"
    echo "    aws lambda invoke --function-name ${LAMBDA_FUNCTION_NAME} [...]"
    echo
    echo "💰 Estimated Monthly Costs:"
    echo "  • Model hosting: ~\$30-50/month"
    echo "  • Predictions: ~\$7.50 per 1,000 requests"
    echo "  • S3 storage: ~\$1-5/month"
    echo "  • Lambda: Pay per invocation"
    echo
    echo "📚 Next Steps:"
    echo "  1. Integrate fraud detection API into your applications"
    echo "  2. Monitor model performance and retrain as needed"
    echo "  3. Adjust rules based on business requirements"
    echo "  4. Set up monitoring and alerting"
    echo
    echo "🧹 Cleanup:"
    echo "  Run ./destroy.sh to remove all resources"
    echo
    echo "================================================"
}

# Main execution
main() {
    log "Starting Amazon Fraud Detector deployment..."
    
    # Pre-deployment checks
    check_aws_config
    check_permissions
    generate_resource_names
    
    # Core deployment steps
    create_s3_bucket
    create_iam_role
    create_training_data
    create_fraud_detector_components
    create_and_train_model
    
    # Wait for training (can be skipped for faster deployment)
    if [ "${SKIP_TRAINING_WAIT:-false}" != "true" ]; then
        wait_for_model_training
    else
        warning "Skipping training wait. Model may not be ready for use immediately."
    fi
    
    create_outcomes_and_rules
    create_detector
    create_lambda_function
    
    # Testing and finalization
    if [ "${SKIP_TESTING:-false}" != "true" ]; then
        test_fraud_detection
    fi
    
    save_deployment_info
    display_summary
    
    success "Deployment completed successfully!"
}

# Cleanup on exit
cleanup() {
    log "Cleaning up temporary files..."
    rm -f /tmp/fraud-detector-trust-policy.json
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/training-data.csv
    rm -f /tmp/fraud-processor.py
    rm -f /tmp/fraud-processor.zip
    rm -f /tmp/fraud-detector-deployment.json
}

trap cleanup EXIT

# Check for help flag
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Amazon Fraud Detector Deployment Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --help, -h          Show this help message"
    echo "  --skip-training     Skip waiting for model training completion"
    echo "  --skip-testing      Skip fraud detection testing"
    echo
    echo "Environment Variables:"
    echo "  SKIP_TRAINING_WAIT  Set to 'true' to skip training wait"
    echo "  SKIP_TESTING        Set to 'true' to skip testing"
    echo
    echo "Examples:"
    echo "  $0                           # Full deployment with training wait"
    echo "  $0 --skip-training           # Deploy without waiting for training"
    echo "  SKIP_TESTING=true $0         # Deploy without testing"
    exit 0
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-training)
            export SKIP_TRAINING_WAIT=true
            shift
            ;;
        --skip-testing)
            export SKIP_TESTING=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"