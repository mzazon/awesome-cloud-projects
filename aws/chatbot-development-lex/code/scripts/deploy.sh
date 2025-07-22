#!/bin/bash

#===============================================================================
# AWS Amazon Lex Chatbot Deployment Script
# 
# This script deploys a complete customer service chatbot using Amazon Lex V2,
# Lambda for fulfillment, DynamoDB for order data, and S3 for product catalog.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate AWS permissions for Lex, Lambda, DynamoDB, S3, and IAM
# - Estimated cost: $2-5 per month for testing
#===============================================================================

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$ERROR_LOG"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS Amazon Lex chatbot infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -r, --region REGION     AWS region (default: from AWS CLI config)
    -p, --prefix PREFIX     Resource name prefix (default: chatbot-demo)
    -d, --dry-run           Show what would be deployed without executing
    -v, --verbose           Enable verbose logging

EXAMPLES:
    $0                      # Deploy with default settings
    $0 -r us-east-1         # Deploy to specific region
    $0 -p my-bot            # Deploy with custom prefix
    $0 -d                   # Dry run mode

EOF
}

# Parse command line arguments
parse_args() {
    REGION=""
    PREFIX="chatbot-demo"
    DRY_RUN=false
    VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -p|--prefix)
                PREFIX="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install AWS CLI v2."
        exit 1
    fi

    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $aws_version"

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi

    # Get AWS account ID and region
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$REGION" ]]; then
        REGION=$(aws configure get region)
        if [[ -z "$REGION" ]]; then
            error "AWS region not configured. Use -r option or run 'aws configure'."
            exit 1
        fi
    fi

    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "AWS Region: $REGION"

    # Check required permissions (basic check)
    local services=("lex" "lambda" "dynamodb" "s3" "iam")
    for service in "${services[@]}"; do
        case $service in
            "lex")
                if ! aws lexv2-models list-bots --max-results 1 &> /dev/null; then
                    warn "May not have sufficient Lex permissions"
                fi
                ;;
            "lambda")
                if ! aws lambda list-functions --max-items 1 &> /dev/null; then
                    warn "May not have sufficient Lambda permissions"
                fi
                ;;
            "dynamodb")
                if ! aws dynamodb list-tables &> /dev/null; then
                    warn "May not have sufficient DynamoDB permissions"
                fi
                ;;
            "s3")
                if ! aws s3 ls &> /dev/null; then
                    warn "May not have sufficient S3 permissions"
                fi
                ;;
            "iam")
                if ! aws iam list-roles --max-items 1 &> /dev/null; then
                    warn "May not have sufficient IAM permissions"
                fi
                ;;
        esac
    done

    log "Prerequisites check completed"
}

# Generate unique resource names
generate_resource_names() {
    log "Generating unique resource names..."

    # Generate random suffix
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

    # Export resource names
    export BOT_NAME="${PREFIX}-bot-${random_suffix}"
    export LAMBDA_FUNCTION_NAME="${PREFIX}-fulfillment-${random_suffix}"
    export ORDERS_TABLE_NAME="${PREFIX}-orders-${random_suffix}"
    export PRODUCTS_BUCKET_NAME="${PREFIX}-products-${random_suffix}"
    export LEX_ROLE_NAME="${PREFIX}-lex-role-${random_suffix}"
    export LAMBDA_ROLE_NAME="${PREFIX}-lambda-role-${random_suffix}"

    log "Generated resource names:"
    log "  Bot Name: $BOT_NAME"
    log "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    log "  DynamoDB Table: $ORDERS_TABLE_NAME"
    log "  S3 Bucket: $PRODUCTS_BUCKET_NAME"
    log "  Lex IAM Role: $LEX_ROLE_NAME"
    log "  Lambda IAM Role: $LAMBDA_ROLE_NAME"
}

# Execute command with dry-run support
execute() {
    local cmd="$1"
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        if [[ "$VERBOSE" == "true" ]]; then
            log "Executing: $cmd"
        fi
        eval "$cmd"
    fi
}

# Create IAM role for Lex service
create_lex_iam_role() {
    log "Creating IAM role for Lex service..."

    local assume_role_policy='{
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
    }'

    execute "aws iam create-role \
        --role-name '$LEX_ROLE_NAME' \
        --assume-role-policy-document '$assume_role_policy' \
        --tags Key=Purpose,Value=LexChatbotDemo Key=Project,Value='$PREFIX'"

    execute "aws iam attach-role-policy \
        --role-name '$LEX_ROLE_NAME' \
        --policy-arn arn:aws:iam::aws:policy/AmazonLexFullAccess"

    # Wait for role propagation
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for IAM role propagation..."
        sleep 10
    fi

    log "✅ Lex IAM role created successfully"
}

# Create IAM role for Lambda function
create_lambda_iam_role() {
    log "Creating IAM role for Lambda function..."

    local assume_role_policy='{
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
    }'

    execute "aws iam create-role \
        --role-name '$LAMBDA_ROLE_NAME' \
        --assume-role-policy-document '$assume_role_policy' \
        --tags Key=Purpose,Value=LexChatbotDemo Key=Project,Value='$PREFIX'"

    # Attach necessary policies
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
        "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    )

    for policy in "${policies[@]}"; do
        execute "aws iam attach-role-policy \
            --role-name '$LAMBDA_ROLE_NAME' \
            --policy-arn '$policy'"
    done

    # Wait for role propagation
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for IAM role propagation..."
        sleep 15
    fi

    log "✅ Lambda IAM role created successfully"
}

# Create DynamoDB table
create_dynamodb_table() {
    log "Creating DynamoDB table for order data..."

    execute "aws dynamodb create-table \
        --table-name '$ORDERS_TABLE_NAME' \
        --attribute-definitions AttributeName=OrderId,AttributeType=S \
        --key-schema AttributeName=OrderId,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Purpose,Value=LexChatbotDemo Key=Project,Value='$PREFIX'"

    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for table to become active..."
        aws dynamodb wait table-exists --table-name "$ORDERS_TABLE_NAME"
    fi

    log "✅ DynamoDB table created successfully"
}

# Create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for product catalog..."

    # Create bucket with region-specific configuration
    if [[ "$REGION" == "us-east-1" ]]; then
        execute "aws s3 mb s3://'$PRODUCTS_BUCKET_NAME'"
    else
        execute "aws s3 mb s3://'$PRODUCTS_BUCKET_NAME' --region '$REGION'"
    fi

    # Add bucket tagging
    execute "aws s3api put-bucket-tagging \
        --bucket '$PRODUCTS_BUCKET_NAME' \
        --tagging 'TagSet=[{Key=Purpose,Value=LexChatbotDemo},{Key=Project,Value='$PREFIX'}]'"

    log "✅ S3 bucket created successfully"
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function for bot fulfillment..."

    # Create function code
    local lambda_code_dir="/tmp/lex-lambda-$$"
    mkdir -p "$lambda_code_dir"

    cat > "$lambda_code_dir/lambda_function.py" << 'EOF'
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event)}")
    
    intent_name = event['sessionState']['intent']['name']
    
    if intent_name == 'ProductInformation':
        return handle_product_information(event)
    elif intent_name == 'OrderStatus':
        return handle_order_status(event)
    elif intent_name == 'SupportRequest':
        return handle_support_request(event)
    else:
        return close_intent(event, "I'm sorry, I don't understand that request.")

def handle_product_information(event):
    slots = event['sessionState']['intent']['slots']
    product_type = slots.get('ProductType', {}).get('value', {}).get('interpretedValue')
    
    if not product_type:
        return elicit_slot(event, 'ProductType', 
                          "What type of product are you interested in? We have electronics, clothing, and books.")
    
    # Simulate product information lookup
    product_info = {
        'electronics': "Our electronics include smartphones, laptops, and smart home devices. Prices range from $50 to $2000.",
        'clothing': "Our clothing collection features casual wear, formal attire, and seasonal items. Sizes range from XS to XXL.",
        'books': "Our book selection includes fiction, non-fiction, and educational materials. Most books are priced between $10-30."
    }
    
    response_text = product_info.get(product_type.lower(), 
                                   "I don't have information about that product type. Please try electronics, clothing, or books.")
    
    return close_intent(event, response_text)

def handle_order_status(event):
    slots = event['sessionState']['intent']['slots']
    order_id = slots.get('OrderNumber', {}).get('value', {}).get('interpretedValue')
    
    if not order_id:
        return elicit_slot(event, 'OrderNumber', 
                          "Please provide your order number so I can check the status.")
    
    # Query DynamoDB for order status
    try:
        table_name = os.environ.get('ORDERS_TABLE', 'customer-orders')
        table = dynamodb.Table(table_name)
        response = table.get_item(Key={'OrderId': order_id})
        
        if 'Item' in response:
            order = response['Item']
            status_text = f"Order {order_id} is currently {order.get('Status', 'Unknown')}."
            if 'EstimatedDelivery' in order:
                status_text += f" Estimated delivery: {order['EstimatedDelivery']}"
        else:
            status_text = f"I couldn't find an order with number {order_id}. Please check the number and try again."
            
    except Exception as e:
        logger.error(f"Error querying DynamoDB: {str(e)}")
        status_text = "I'm having trouble accessing order information right now. Please try again later."
    
    return close_intent(event, status_text)

def handle_support_request(event):
    # For complex issues, escalate to human support
    response_text = ("I'll connect you with a human support agent. "
                    "You can also email us at support@company.com or call 1-800-SUPPORT. "
                    "A representative will assist you within 24 hours.")
    
    return close_intent(event, response_text)

def elicit_slot(event, slot_name, message):
    return {
        'sessionState': {
            'dialogAction': {
                'type': 'ElicitSlot',
                'slotToElicit': slot_name
            },
            'intent': event['sessionState']['intent'],
            'originatingRequestId': event['requestAttributes'].get('x-amz-lex:request-id')
        },
        'messages': [
            {
                'contentType': 'PlainText',
                'content': message
            }
        ]
    }

def close_intent(event, message):
    return {
        'sessionState': {
            'dialogAction': {
                'type': 'Close'
            },
            'intent': {
                'name': event['sessionState']['intent']['name'],
                'state': 'Fulfilled'
            },
            'originatingRequestId': event['requestAttributes'].get('x-amz-lex:request-id')
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
    (cd "$lambda_code_dir" && zip lambda_function.zip lambda_function.py)

    # Get Lambda role ARN
    local lambda_role_arn
    if [[ "$DRY_RUN" == "false" ]]; then
        lambda_role_arn=$(aws iam get-role \
            --role-name "$LAMBDA_ROLE_NAME" \
            --query 'Role.Arn' --output text)
    else
        lambda_role_arn="arn:aws:iam::$AWS_ACCOUNT_ID:role/$LAMBDA_ROLE_NAME"
    fi

    # Create Lambda function
    execute "aws lambda create-function \
        --function-name '$LAMBDA_FUNCTION_NAME' \
        --runtime python3.9 \
        --role '$lambda_role_arn' \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://'$lambda_code_dir/lambda_function.zip' \
        --timeout 30 \
        --environment Variables='{ORDERS_TABLE=$ORDERS_TABLE_NAME,PRODUCTS_BUCKET=$PRODUCTS_BUCKET_NAME}' \
        --tags Purpose=LexChatbotDemo,Project='$PREFIX'"

    # Clean up temporary files
    rm -rf "$lambda_code_dir"

    log "✅ Lambda function created successfully"
}

# Create Amazon Lex bot
create_lex_bot() {
    log "Creating Amazon Lex bot..."

    # Get Lex service role ARN
    local lex_role_arn
    if [[ "$DRY_RUN" == "false" ]]; then
        lex_role_arn=$(aws iam get-role \
            --role-name "$LEX_ROLE_NAME" \
            --query 'Role.Arn' --output text)
    else
        lex_role_arn="arn:aws:iam::$AWS_ACCOUNT_ID:role/$LEX_ROLE_NAME"
    fi

    # Create the bot
    execute "aws lexv2-models create-bot \
        --bot-name '$BOT_NAME' \
        --description 'Customer service chatbot for product inquiries and order status' \
        --role-arn '$lex_role_arn' \
        --data-privacy '{\"childDirected\": false}' \
        --idle-session-ttl-in-seconds 300"

    # Get bot ID
    if [[ "$DRY_RUN" == "false" ]]; then
        BOT_ID=$(aws lexv2-models list-bots \
            --query "botSummaries[?botName=='$BOT_NAME'].botId" \
            --output text)
        export BOT_ID
        log "Bot ID: $BOT_ID"
    else
        export BOT_ID="dummy-bot-id"
    fi

    log "✅ Lex bot created successfully"
}

# Configure bot locale and intents
configure_bot_intents() {
    log "Configuring bot locale and intents..."

    # Create bot locale (English US)
    execute "aws lexv2-models create-bot-locale \
        --bot-id '$BOT_ID' \
        --bot-version DRAFT \
        --locale-id en_US \
        --nlu-intent-confidence-threshold 0.7"

    # Create intents
    local intents=("ProductInformation" "OrderStatus" "SupportRequest")
    for intent in "${intents[@]}"; do
        execute "aws lexv2-models create-intent \
            --bot-id '$BOT_ID' \
            --bot-version DRAFT \
            --locale-id en_US \
            --intent-name '$intent' \
            --description 'Intent to handle $intent requests'"
    done

    # Create ProductType slot type
    execute "aws lexv2-models create-slot-type \
        --bot-id '$BOT_ID' \
        --bot-version DRAFT \
        --locale-id en_US \
        --slot-type-name ProductType \
        --description 'Types of products available' \
        --slot-type-values '[
            {\"sampleValue\": {\"value\": \"electronics\"}},
            {\"sampleValue\": {\"value\": \"clothing\"}},
            {\"sampleValue\": {\"value\": \"books\"}}
        ]'"

    log "✅ Bot locale and intents configured successfully"
}

# Build and deploy bot
build_bot() {
    log "Building Lex bot..."

    # Build the bot
    execute "aws lexv2-models build-bot-locale \
        --bot-id '$BOT_ID' \
        --bot-version DRAFT \
        --locale-id en_US"

    # Wait for build to complete
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for bot build to complete..."
        aws lexv2-models wait bot-locale-built \
            --bot-id "$BOT_ID" \
            --bot-version DRAFT \
            --locale-id en_US
    fi

    # Create bot version
    execute "aws lexv2-models create-bot-version \
        --bot-id '$BOT_ID' \
        --description 'Production version of customer service bot'"

    # Create bot alias
    execute "aws lexv2-models create-bot-alias \
        --bot-id '$BOT_ID' \
        --bot-alias-name production \
        --description 'Production alias for customer service bot' \
        --bot-version '1'"

    log "✅ Bot built and deployed successfully"
}

# Grant Lambda permissions
grant_lambda_permissions() {
    log "Granting Lex permission to invoke Lambda function..."

    execute "aws lambda add-permission \
        --function-name '$LAMBDA_FUNCTION_NAME' \
        --statement-id lex-invoke \
        --action lambda:InvokeFunction \
        --principal lexv2.amazonaws.com \
        --source-arn 'arn:aws:lex:$REGION:$AWS_ACCOUNT_ID:bot-alias/$BOT_ID/*'"

    log "✅ Lambda permissions granted successfully"
}

# Populate sample data
populate_sample_data() {
    log "Populating sample data in DynamoDB..."

    local sample_orders=(
        '{"OrderId": {"S": "ORD123456"}, "Status": {"S": "Shipped"}, "EstimatedDelivery": {"S": "2024-01-15"}, "CustomerEmail": {"S": "customer@example.com"}}'
        '{"OrderId": {"S": "ORD789012"}, "Status": {"S": "Processing"}, "EstimatedDelivery": {"S": "2024-01-20"}, "CustomerEmail": {"S": "customer2@example.com"}}'
        '{"OrderId": {"S": "ORD345678"}, "Status": {"S": "Delivered"}, "EstimatedDelivery": {"S": "2024-01-10"}, "CustomerEmail": {"S": "customer3@example.com"}}'
    )

    for order in "${sample_orders[@]}"; do
        execute "aws dynamodb put-item \
            --table-name '$ORDERS_TABLE_NAME' \
            --item '$order'"
    done

    log "✅ Sample data populated successfully"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."

    local deployment_info="${SCRIPT_DIR}/deployment_info.json"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get actual resource ARNs and IDs
        local bot_alias_id
        bot_alias_id=$(aws lexv2-models list-bot-aliases \
            --bot-id "$BOT_ID" \
            --query "botAliasSummaries[0].botAliasId" --output text)

        local lambda_arn
        lambda_arn=$(aws lambda get-function \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --query 'Configuration.FunctionArn' --output text)

        cat > "$deployment_info" << EOF
{
    "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "aws_region": "$REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "resource_prefix": "$PREFIX",
    "bot_name": "$BOT_NAME",
    "bot_id": "$BOT_ID",
    "bot_alias_id": "$bot_alias_id",
    "lambda_function_name": "$LAMBDA_FUNCTION_NAME",
    "lambda_function_arn": "$lambda_arn",
    "orders_table_name": "$ORDERS_TABLE_NAME",
    "products_bucket_name": "$PRODUCTS_BUCKET_NAME",
    "lex_role_name": "$LEX_ROLE_NAME",
    "lambda_role_name": "$LAMBDA_ROLE_NAME"
}
EOF
    else
        cat > "$deployment_info" << EOF
{
    "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "aws_region": "$REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "resource_prefix": "$PREFIX",
    "dry_run": true,
    "bot_name": "$BOT_NAME",
    "lambda_function_name": "$LAMBDA_FUNCTION_NAME",
    "orders_table_name": "$ORDERS_TABLE_NAME",
    "products_bucket_name": "$PRODUCTS_BUCKET_NAME",
    "lex_role_name": "$LEX_ROLE_NAME",
    "lambda_role_name": "$LAMBDA_ROLE_NAME"
}
EOF
    fi

    log "Deployment information saved to: $deployment_info"
}

# Print deployment summary
print_summary() {
    log "Deployment completed successfully!"
    
    echo ""
    echo "==============================================================================="
    echo "                          DEPLOYMENT SUMMARY"
    echo "==============================================================================="
    echo "AWS Region:           $REGION"
    echo "AWS Account:          $AWS_ACCOUNT_ID"
    echo "Resource Prefix:      $PREFIX"
    echo ""
    echo "RESOURCES CREATED:"
    echo "  Lex Bot:            $BOT_NAME"
    echo "  Lambda Function:    $LAMBDA_FUNCTION_NAME"
    echo "  DynamoDB Table:     $ORDERS_TABLE_NAME"
    echo "  S3 Bucket:          $PRODUCTS_BUCKET_NAME"
    echo "  Lex IAM Role:       $LEX_ROLE_NAME"
    echo "  Lambda IAM Role:    $LAMBDA_ROLE_NAME"
    echo ""
    echo "TESTING:"
    echo "You can test the bot using the AWS Console or CLI:"
    if [[ "$DRY_RUN" == "false" ]]; then
        local bot_alias_id
        bot_alias_id=$(aws lexv2-models list-bot-aliases \
            --bot-id "$BOT_ID" \
            --query "botAliasSummaries[0].botAliasId" --output text 2>/dev/null || echo "ALIAS_ID")
        echo "  aws lexv2-runtime recognize-text \\"
        echo "    --bot-id $BOT_ID \\"
        echo "    --bot-alias-id $bot_alias_id \\"
        echo "    --locale-id en_US \\"
        echo "    --session-id test-session \\"
        echo "    --text \"Tell me about your electronics\""
    fi
    echo ""
    echo "CLEANUP:"
    echo "To remove all resources, run: ./destroy.sh -p $PREFIX"
    echo ""
    echo "ESTIMATED MONTHLY COST: \$2-5 for testing workloads"
    echo "==============================================================================="
}

# Main deployment function
main() {
    # Initialize logging
    : > "$LOG_FILE"
    : > "$ERROR_LOG"

    log "Starting AWS Amazon Lex Chatbot deployment..."
    log "Script started at: $(date)"

    # Parse arguments
    parse_args "$@"

    # Check prerequisites
    check_prerequisites

    # Generate resource names
    generate_resource_names

    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No resources will be created"
    fi

    # Deploy infrastructure
    create_lex_iam_role
    create_lambda_iam_role
    create_dynamodb_table
    create_s3_bucket
    create_lambda_function
    create_lex_bot
    configure_bot_intents
    build_bot
    grant_lambda_permissions
    populate_sample_data

    # Save deployment info and print summary
    save_deployment_info
    print_summary

    log "Deployment script completed successfully!"
}

# Error handling
trap 'error "Script failed at line $LINENO. Exit code: $?"; exit 1' ERR

# Run main function
main "$@"