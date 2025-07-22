#!/bin/bash

# Deploy script for Customer Service Chatbots with Amazon Lex
# This script deploys the complete customer service chatbot infrastructure
# including Amazon Lex bot, Lambda function, DynamoDB table, and IAM roles

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if AWS CLI is installed and configured
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region set, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export BOT_NAME="CustomerServiceBot-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="lex-fulfillment-${RANDOM_SUFFIX}"
    export DYNAMODB_TABLE_NAME="customer-data-${RANDOM_SUFFIX}"
    export LEX_SERVICE_ROLE_NAME="LexServiceRole-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="LexLambdaRole-${RANDOM_SUFFIX}"
    export LAMBDA_POLICY_NAME="LexDynamoDBPolicy-${RANDOM_SUFFIX}"
    
    # Store variables in a file for cleanup script
    cat > .env_vars << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export BOT_NAME="$BOT_NAME"
export LAMBDA_FUNCTION_NAME="$LAMBDA_FUNCTION_NAME"
export DYNAMODB_TABLE_NAME="$DYNAMODB_TABLE_NAME"
export LEX_SERVICE_ROLE_NAME="$LEX_SERVICE_ROLE_NAME"
export LAMBDA_ROLE_NAME="$LAMBDA_ROLE_NAME"
export LAMBDA_POLICY_NAME="$LAMBDA_POLICY_NAME"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    
    success "Environment variables configured"
    log "Bot name: $BOT_NAME"
    log "Lambda function: $LAMBDA_FUNCTION_NAME"
    log "DynamoDB table: $DYNAMODB_TABLE_NAME"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create IAM service role for Amazon Lex
    aws iam create-role \
        --role-name "$LEX_SERVICE_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "lexv2.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --tags Key=Project,Value=LexCustomerService > /dev/null
    
    # Attach the required policy to the Lex service role
    aws iam attach-role-policy \
        --role-name "$LEX_SERVICE_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AmazonLexV2BotPolicy"
    
    export LEX_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LEX_SERVICE_ROLE_NAME}"
    
    # Create IAM role for Lambda function
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
        --tags Key=Project,Value=LexCustomerService > /dev/null
    
    # Attach basic execution policy
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    # Create policy for DynamoDB access
    aws iam create-policy \
        --policy-name "$LAMBDA_POLICY_NAME" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "dynamodb:GetItem",
                        "dynamodb:PutItem",
                        "dynamodb:UpdateItem",
                        "dynamodb:Query"
                    ],
                    "Resource": "arn:aws:dynamodb:'"$AWS_REGION"':'"$AWS_ACCOUNT_ID"':table/'"$DYNAMODB_TABLE_NAME"'"
                }
            ]
        }' \
        --tags Key=Project,Value=LexCustomerService > /dev/null
    
    # Attach DynamoDB policy to Lambda role
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_POLICY_NAME}"
    
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    # Add role ARNs to environment file
    echo "export LEX_ROLE_ARN=\"$LEX_ROLE_ARN\"" >> .env_vars
    echo "export LAMBDA_ROLE_ARN=\"$LAMBDA_ROLE_ARN\"" >> .env_vars
    
    success "IAM roles created successfully"
}

# Create DynamoDB table
create_dynamodb_table() {
    log "Creating DynamoDB table..."
    
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE_NAME" \
        --attribute-definitions \
            AttributeName=CustomerId,AttributeType=S \
        --key-schema \
            AttributeName=CustomerId,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value=LexCustomerService > /dev/null
    
    # Wait for table to be created
    log "Waiting for DynamoDB table to be created..."
    aws dynamodb wait table-exists --table-name "$DYNAMODB_TABLE_NAME"
    
    success "DynamoDB table created: $DYNAMODB_TABLE_NAME"
}

# Populate sample data
populate_sample_data() {
    log "Populating sample customer data..."
    
    # Insert sample customer data for testing
    aws dynamodb put-item \
        --table-name "$DYNAMODB_TABLE_NAME" \
        --item '{
            "CustomerId": {"S": "12345"},
            "Name": {"S": "John Smith"},
            "Email": {"S": "john.smith@example.com"},
            "LastOrderId": {"S": "ORD-789"},
            "LastOrderStatus": {"S": "Shipped"},
            "AccountBalance": {"N": "156.78"}
        }' > /dev/null
    
    aws dynamodb put-item \
        --table-name "$DYNAMODB_TABLE_NAME" \
        --item '{
            "CustomerId": {"S": "67890"},
            "Name": {"S": "Jane Doe"},
            "Email": {"S": "jane.doe@example.com"},
            "LastOrderId": {"S": "ORD-456"},
            "LastOrderStatus": {"S": "Processing"},
            "AccountBalance": {"N": "89.23"}
        }' > /dev/null
    
    success "Sample customer data populated"
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    # Create Lambda function code
    cat > lambda_function.py << 'EOF'
import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
table_name = os.environ['DYNAMODB_TABLE_NAME']
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")
    
    intent_name = event['sessionState']['intent']['name']
    slots = event['sessionState']['intent']['slots']
    
    if intent_name == 'OrderStatus':
        return handle_order_status(event, slots)
    elif intent_name == 'BillingInquiry':
        return handle_billing_inquiry(event, slots)
    elif intent_name == 'ProductInfo':
        return handle_product_info(event, slots)
    else:
        return close_intent(event, 'Fulfilled', 
                           'I can help you with order status, billing questions, or product information.')

def handle_order_status(event, slots):
    customer_id = slots.get('CustomerId', {}).get('value', {}).get('interpretedValue')
    
    if not customer_id:
        return elicit_slot(event, 'CustomerId', 
                          'Could you please provide your customer ID to check your order status?')
    
    try:
        response = table.get_item(Key={'CustomerId': customer_id})
        if 'Item' in response:
            item = response['Item']
            message = f"Hi {item['Name']}! Your last order {item['LastOrderId']} is currently {item['LastOrderStatus']}."
        else:
            message = f"I couldn't find a customer with ID {customer_id}. Please check your customer ID."
        
        return close_intent(event, 'Fulfilled', message)
    except Exception as e:
        logger.error(f"Error retrieving order status: {str(e)}")
        return close_intent(event, 'Failed', 
                           'Sorry, I encountered an error checking your order status. Please try again later.')

def handle_billing_inquiry(event, slots):
    customer_id = slots.get('CustomerId', {}).get('value', {}).get('interpretedValue')
    
    if not customer_id:
        return elicit_slot(event, 'CustomerId', 
                          'Could you please provide your customer ID to check your account balance?')
    
    try:
        response = table.get_item(Key={'CustomerId': customer_id})
        if 'Item' in response:
            item = response['Item']
            balance = float(item['AccountBalance'])
            message = f"Hi {item['Name']}! Your current account balance is ${balance:.2f}."
        else:
            message = f"I couldn't find a customer with ID {customer_id}. Please check your customer ID."
        
        return close_intent(event, 'Fulfilled', message)
    except Exception as e:
        logger.error(f"Error retrieving billing info: {str(e)}")
        return close_intent(event, 'Failed', 
                           'Sorry, I encountered an error checking your account. Please try again later.')

def handle_product_info(event, slots):
    product_name = slots.get('ProductName', {}).get('value', {}).get('interpretedValue')
    
    if not product_name:
        return elicit_slot(event, 'ProductName', 
                          'What product would you like information about?')
    
    # Simple product info responses (in real implementation, query product database)
    product_info = {
        'laptop': 'Our laptops feature high-performance processors and long battery life, starting at $899.',
        'smartphone': 'Our smartphones offer premium cameras and 5G connectivity, starting at $699.',
        'tablet': 'Our tablets are perfect for productivity and entertainment, starting at $399.'
    }
    
    product_lower = product_name.lower()
    if product_lower in product_info:
        message = product_info[product_lower]
    else:
        message = f"I don't have specific information about {product_name}. Please contact our sales team for detailed product information."
    
    return close_intent(event, 'Fulfilled', message)

def elicit_slot(event, slot_to_elicit, message):
    return {
        'sessionState': {
            'sessionAttributes': event['sessionState'].get('sessionAttributes', {}),
            'dialogAction': {
                'type': 'ElicitSlot',
                'slotToElicit': slot_to_elicit
            },
            'intent': event['sessionState']['intent']
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }

def close_intent(event, fulfillment_state, message):
    return {
        'sessionState': {
            'sessionAttributes': event['sessionState'].get('sessionAttributes', {}),
            'dialogAction': {
                'type': 'Close'
            },
            'intent': {
                'name': event['sessionState']['intent']['name'],
                'state': fulfillment_state
            }
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }
EOF
    
    # Create deployment package
    zip -q lambda_function.zip lambda_function.py
    
    # Wait for IAM role to propagate
    log "Waiting for IAM role propagation..."
    sleep 15
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda_function.zip \
        --environment Variables="{DYNAMODB_TABLE_NAME=$DYNAMODB_TABLE_NAME}" \
        --timeout 30 \
        --tags Project=LexCustomerService > /dev/null
    
    export LAMBDA_FUNCTION_ARN=$(aws lambda get-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'Configuration.FunctionArn' --output text)
    
    # Add Lambda ARN to environment file
    echo "export LAMBDA_FUNCTION_ARN=\"$LAMBDA_FUNCTION_ARN\"" >> .env_vars
    
    success "Lambda function created: $LAMBDA_FUNCTION_NAME"
}

# Create Amazon Lex bot
create_lex_bot() {
    log "Creating Amazon Lex bot..."
    
    # Create the bot
    BOT_RESPONSE=$(aws lexv2-models create-bot \
        --bot-name "$BOT_NAME" \
        --description "Customer service chatbot for handling common inquiries" \
        --role-arn "$LEX_ROLE_ARN" \
        --data-privacy childDirected=false \
        --idle-session-ttl-in-seconds 600 \
        --bot-tags Project=LexCustomerService)
    
    export BOT_ID=$(echo $BOT_RESPONSE | jq -r '.botId')
    
    # Add Bot ID to environment file
    echo "export BOT_ID=\"$BOT_ID\"" >> .env_vars
    
    success "Lex bot created with ID: $BOT_ID"
}

# Configure bot locale
configure_bot_locale() {
    log "Configuring bot locale..."
    
    # Create bot locale for English (US)
    aws lexv2-models create-bot-locale \
        --bot-id "$BOT_ID" \
        --bot-version "DRAFT" \
        --locale-id "en_US" \
        --description "English US locale for customer service bot" \
        --nlu-intent-confidence-threshold 0.40 \
        --voice-settings voiceId=Joanna \
        --region "$AWS_REGION" > /dev/null
    
    # Wait for locale creation
    sleep 10
    
    success "Bot locale configured for en_US"
}

# Create slot types
create_slot_types() {
    log "Creating custom slot types..."
    
    # Create CustomerId slot type
    aws lexv2-models create-slot-type \
        --bot-id "$BOT_ID" \
        --bot-version "DRAFT" \
        --locale-id "en_US" \
        --slot-type-name "CustomerId" \
        --description "Customer identification numbers" \
        --slot-type-values '[
            {
                "sampleValue": {"value": "12345"},
                "synonyms": []
            },
            {
                "sampleValue": {"value": "67890"},
                "synonyms": []
            }
        ]' \
        --value-selection-strategy "ORIGINAL_VALUE" > /dev/null
    
    # Create ProductName slot type  
    aws lexv2-models create-slot-type \
        --bot-id "$BOT_ID" \
        --bot-version "DRAFT" \
        --locale-id "en_US" \
        --slot-type-name "ProductName" \
        --description "Product names for inquiries" \
        --slot-type-values '[
            {
                "sampleValue": {"value": "laptop"},
                "synonyms": [{"value": "computer"}, {"value": "notebook"}]
            },
            {
                "sampleValue": {"value": "smartphone"},
                "synonyms": [{"value": "phone"}, {"value": "mobile"}]
            },
            {
                "sampleValue": {"value": "tablet"},
                "synonyms": [{"value": "ipad"}]
            }
        ]' \
        --value-selection-strategy "TOP_RESOLUTION" > /dev/null
    
    success "Custom slot types created"
}

# Create intents
create_intents() {
    log "Creating bot intents..."
    
    # Create OrderStatus intent
    aws lexv2-models create-intent \
        --bot-id "$BOT_ID" \
        --bot-version "DRAFT" \
        --locale-id "en_US" \
        --intent-name "OrderStatus" \
        --description "Handle order status inquiries" \
        --sample-utterances '[
            {"utterance": "What is my order status"},
            {"utterance": "Check my order"},
            {"utterance": "Where is my order"},
            {"utterance": "Track my order {CustomerId}"},
            {"utterance": "Order status for {CustomerId}"},
            {"utterance": "My customer ID is {CustomerId}"}
        ]' \
        --slot-priorities '[
            {
                "priority": 1,
                "slotId": "CustomerId"
            }
        ]' > /dev/null
    
    sleep 5
    
    # Create BillingInquiry intent
    aws lexv2-models create-intent \
        --bot-id "$BOT_ID" \
        --bot-version "DRAFT" \
        --locale-id "en_US" \
        --intent-name "BillingInquiry" \
        --description "Handle billing and account balance inquiries" \
        --sample-utterances '[
            {"utterance": "What is my account balance"},
            {"utterance": "Check my balance"},
            {"utterance": "How much do I owe"},
            {"utterance": "Billing information for {CustomerId}"},
            {"utterance": "Account balance for customer {CustomerId}"},
            {"utterance": "My balance please"}
        ]' \
        --slot-priorities '[
            {
                "priority": 1,
                "slotId": "CustomerId"
            }
        ]' > /dev/null
    
    sleep 5
    
    # Create ProductInfo intent
    aws lexv2-models create-intent \
        --bot-id "$BOT_ID" \
        --bot-version "DRAFT" \
        --locale-id "en_US" \
        --intent-name "ProductInfo" \
        --description "Handle product information requests" \
        --sample-utterances '[
            {"utterance": "Tell me about {ProductName}"},
            {"utterance": "Product information for {ProductName}"},
            {"utterance": "What can you tell me about {ProductName}"},
            {"utterance": "I want to know about {ProductName}"},
            {"utterance": "Details about your {ProductName}"}
        ]' \
        --slot-priorities '[
            {
                "priority": 1,
                "slotId": "ProductName"
            }
        ]' > /dev/null
    
    success "Bot intents created"
}

# Add slots to intents
add_slots_to_intents() {
    log "Adding slots to intents..."
    
    # Add CustomerId slot to OrderStatus intent
    aws lexv2-models create-slot \
        --bot-id "$BOT_ID" \
        --bot-version "DRAFT" \
        --locale-id "en_US" \
        --intent-id "OrderStatus" \
        --slot-name "CustomerId" \
        --description "Customer identification number" \
        --slot-type-id "CustomerId" \
        --value-elicitation-setting '{
            "slotConstraint": "Required",
            "promptSpecification": {
                "messageGroups": [
                    {
                        "message": {
                            "plainTextMessage": {
                                "value": "Could you please provide your customer ID?"
                            }
                        }
                    }
                ],
                "maxRetries": 2
            }
        }' > /dev/null
    
    sleep 3
    
    # Add CustomerId slot to BillingInquiry intent
    aws lexv2-models create-slot \
        --bot-id "$BOT_ID" \
        --bot-version "DRAFT" \
        --locale-id "en_US" \
        --intent-id "BillingInquiry" \
        --slot-name "CustomerId" \
        --description "Customer identification number for billing" \
        --slot-type-id "CustomerId" \
        --value-elicitation-setting '{
            "slotConstraint": "Required",
            "promptSpecification": {
                "messageGroups": [
                    {
                        "message": {
                            "plainTextMessage": {
                                "value": "Please provide your customer ID to check your account balance."
                            }
                        }
                    }
                ],
                "maxRetries": 2
            }
        }' > /dev/null
    
    sleep 3
    
    # Add ProductName slot to ProductInfo intent
    aws lexv2-models create-slot \
        --bot-id "$BOT_ID" \
        --bot-version "DRAFT" \
        --locale-id "en_US" \
        --intent-id "ProductInfo" \
        --slot-name "ProductName" \
        --description "Product name for information request" \
        --slot-type-id "ProductName" \
        --value-elicitation-setting '{
            "slotConstraint": "Required",
            "promptSpecification": {
                "messageGroups": [
                    {
                        "message": {
                            "plainTextMessage": {
                                "value": "What product would you like information about?"
                            }
                        }
                    }
                ],
                "maxRetries": 2
            }
        }' > /dev/null
    
    success "Slots added to intents"
}

# Configure Lambda integration
configure_lambda_integration() {
    log "Configuring Lambda integration..."
    
    # Grant Lex permission to invoke Lambda function
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id "lex-invoke-permission" \
        --action lambda:InvokeFunction \
        --principal lexv2.amazonaws.com \
        --source-arn "arn:aws:lex:${AWS_REGION}:${AWS_ACCOUNT_ID}:bot/${BOT_ID}" > /dev/null
    
    # Update intents to use Lambda fulfillment
    for INTENT in "OrderStatus" "BillingInquiry" "ProductInfo"; do
        aws lexv2-models update-intent \
            --bot-id "$BOT_ID" \
            --bot-version "DRAFT" \
            --locale-id "en_US" \
            --intent-id "$INTENT" \
            --intent-name "$INTENT" \
            --fulfillment-code-hook '{
                "enabled": true,
                "fulfillmentUpdatesSpecification": {
                    "active": false
                }
            }' > /dev/null
        
        sleep 2
    done
    
    success "Lambda integration configured"
}

# Build and test bot
build_bot() {
    log "Building bot..."
    
    # Build the bot
    aws lexv2-models build-bot-locale \
        --bot-id "$BOT_ID" \
        --bot-version "DRAFT" \
        --locale-id "en_US" > /dev/null
    
    log "Waiting for bot build to complete..."
    
    # Wait for build completion
    while true; do
        BUILD_STATUS=$(aws lexv2-models describe-bot-locale \
            --bot-id "$BOT_ID" \
            --bot-version "DRAFT" \
            --locale-id "en_US" \
            --query 'botLocaleStatus' --output text)
        
        case $BUILD_STATUS in
            "Built")
                success "Bot build completed successfully"
                break
                ;;
            "Failed")
                error "Bot build failed"
                exit 1
                ;;
            "Building")
                log "Build in progress..."
                sleep 30
                ;;
            *)
                log "Build status: $BUILD_STATUS"
                sleep 30
                ;;
        esac
    done
}

# Test bot functionality
test_bot() {
    log "Testing bot functionality..."
    
    # Test order status intent
    log "Testing order status query..."
    ORDER_RESPONSE=$(aws lexv2-runtime recognize-text \
        --bot-id "$BOT_ID" \
        --bot-alias-id "TSTALIASID" \
        --locale-id "en_US" \
        --session-id "test-session-1" \
        --text "What is my order status for customer 12345?" \
        --query 'messages[0].content' --output text 2>/dev/null || echo "Test failed")
    
    if [[ "$ORDER_RESPONSE" == *"John Smith"* ]]; then
        success "Order status test passed: $ORDER_RESPONSE"
    else
        warning "Order status test may have issues: $ORDER_RESPONSE"
    fi
    
    # Test billing inquiry
    log "Testing billing inquiry..."
    BILLING_RESPONSE=$(aws lexv2-runtime recognize-text \
        --bot-id "$BOT_ID" \
        --bot-alias-id "TSTALIASID" \
        --locale-id "en_US" \
        --session-id "test-session-2" \
        --text "Check my account balance for customer 67890" \
        --query 'messages[0].content' --output text 2>/dev/null || echo "Test failed")
    
    if [[ "$BILLING_RESPONSE" == *"Jane Doe"* ]]; then
        success "Billing inquiry test passed: $BILLING_RESPONSE"
    else
        warning "Billing inquiry test may have issues: $BILLING_RESPONSE"
    fi
    
    # Test product information
    log "Testing product information..."
    PRODUCT_RESPONSE=$(aws lexv2-runtime recognize-text \
        --bot-id "$BOT_ID" \
        --bot-alias-id "TSTALIASID" \
        --locale-id "en_US" \
        --session-id "test-session-3" \
        --text "Tell me about your laptops" \
        --query 'messages[0].content' --output text 2>/dev/null || echo "Test failed")
    
    if [[ "$PRODUCT_RESPONSE" == *"laptop"* ]]; then
        success "Product information test passed: $PRODUCT_RESPONSE"
    else
        warning "Product information test may have issues: $PRODUCT_RESPONSE"
    fi
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f lambda_function.py lambda_function.zip
    success "Temporary files cleaned up"
}

# Display deployment summary
display_summary() {
    echo ""
    echo "============================================"
    success "DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "============================================"
    echo ""
    log "Deployment Summary:"
    echo "  - Bot Name: $BOT_NAME"
    echo "  - Bot ID: $BOT_ID"
    echo "  - Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "  - DynamoDB Table: $DYNAMODB_TABLE_NAME"
    echo "  - AWS Region: $AWS_REGION"
    echo ""
    log "Next Steps:"
    echo "  1. Test the bot using the AWS Console at:"
    echo "     https://${AWS_REGION}.console.aws.amazon.com/lexv2/home?region=${AWS_REGION}#bots"
    echo "  2. Integrate with Amazon Connect for voice support"
    echo "  3. Deploy to web chat using AWS SDK for JavaScript"
    echo ""
    warning "Remember to run ./destroy.sh when you're done testing to avoid ongoing charges!"
    echo ""
    log "Environment variables saved to .env_vars for cleanup script"
}

# Main deployment function
main() {
    echo "============================================"
    echo "  Customer Service Chatbot Deployment"
    echo "  Amazon Lex + Lambda + DynamoDB"
    echo "============================================"
    echo ""
    
    check_prerequisites
    setup_environment
    create_iam_roles
    create_dynamodb_table
    populate_sample_data
    create_lambda_function
    create_lex_bot
    configure_bot_locale
    create_slot_types
    create_intents
    add_slots_to_intents
    configure_lambda_integration
    build_bot
    test_bot
    cleanup_temp_files
    display_summary
}

# Run main function
main "$@"