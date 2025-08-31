#!/bin/bash

# Email List Management with SES and DynamoDB - Deployment Script
# This script deploys a serverless email list management system using AWS SES, DynamoDB, and Lambda

set -e  # Exit on any error

# Color codes for output
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
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
    fi
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Installing it is recommended for better JSON processing."
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        error "zip command is not available. Please install it."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    export TABLE_NAME="email-subscribers-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="EmailListLambdaRole-${RANDOM_SUFFIX}"
    export SENDER_EMAIL=${SENDER_EMAIL:-"your-verified-email@example.com"}
    
    # Function names
    export SUBSCRIBE_FUNCTION_NAME="email-subscribe-${RANDOM_SUFFIX}"
    export NEWSLETTER_FUNCTION_NAME="email-newsletter-${RANDOM_SUFFIX}"
    export LIST_FUNCTION_NAME="email-list-${RANDOM_SUFFIX}"
    
    # Create temporary directory for function code
    export TEMP_DIR=$(mktemp -d)
    
    log "Environment variables set:"
    log "  AWS_REGION: ${AWS_REGION}"
    log "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log "  TABLE_NAME: ${TABLE_NAME}"
    log "  LAMBDA_ROLE_NAME: ${LAMBDA_ROLE_NAME}"
    log "  SENDER_EMAIL: ${SENDER_EMAIL}"
    log "  TEMP_DIR: ${TEMP_DIR}"
    
    success "Environment setup completed"
}

# Verify SES availability
verify_ses() {
    log "Verifying SES availability in region ${AWS_REGION}..."
    
    if ! aws ses describe-account-configuration >/dev/null 2>&1; then
        warning "SES may not be available in ${AWS_REGION}. Consider using us-east-1, us-west-2, or eu-west-1"
    else
        success "SES is available in ${AWS_REGION}"
    fi
}

# Create DynamoDB table
create_dynamodb_table() {
    log "Creating DynamoDB table: ${TABLE_NAME}..."
    
    # Check if table already exists
    if aws dynamodb describe-table --table-name "${TABLE_NAME}" >/dev/null 2>&1; then
        warning "DynamoDB table ${TABLE_NAME} already exists, skipping creation"
        return 0
    fi
    
    aws dynamodb create-table \
        --table-name "${TABLE_NAME}" \
        --attribute-definitions \
            AttributeName=email,AttributeType=S \
        --key-schema \
            AttributeName=email,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Purpose,Value=EmailListManagement \
               Key=Environment,Value=Development \
               Key=CreatedBy,Value=email-list-deployment-script
    
    log "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name "${TABLE_NAME}"
    
    success "DynamoDB table ${TABLE_NAME} created successfully"
}

# Verify email address in SES
verify_email_address() {
    log "Verifying email address in SES: ${SENDER_EMAIL}..."
    
    if [ "${SENDER_EMAIL}" = "your-verified-email@example.com" ]; then
        error "Please set SENDER_EMAIL environment variable to your verified email address"
    fi
    
    # Check if email is already verified
    VERIFICATION_STATUS=$(aws ses get-identity-verification-attributes \
        --identities "${SENDER_EMAIL}" \
        --query "VerificationAttributes.\"${SENDER_EMAIL}\".VerificationStatus" \
        --output text 2>/dev/null || echo "NotStarted")
    
    if [ "${VERIFICATION_STATUS}" = "Success" ]; then
        success "Email ${SENDER_EMAIL} is already verified"
    else
        log "Requesting email verification for ${SENDER_EMAIL}..."
        aws ses verify-email-identity --email-address "${SENDER_EMAIL}"
        warning "Email verification request sent to ${SENDER_EMAIL}. Please check your inbox and click the verification link before proceeding."
        warning "Note: New SES accounts start in sandbox mode. You may need to request production access."
    fi
}

# Create IAM role for Lambda functions
create_iam_role() {
    log "Creating IAM role: ${LAMBDA_ROLE_NAME}..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" >/dev/null 2>&1; then
        warning "IAM role ${LAMBDA_ROLE_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create trust policy
    cat > "${TEMP_DIR}/lambda-trust-policy.json" << EOF
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
    
    # Create IAM role
    aws iam create-role \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --assume-role-policy-document "file://${TEMP_DIR}/lambda-trust-policy.json" \
        --tags Key=Purpose,Value=EmailListManagement \
               Key=Environment,Value=Development \
               Key=CreatedBy,Value=email-list-deployment-script
    
    # Create permission policy
    cat > "${TEMP_DIR}/lambda-permissions-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Scan"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${TABLE_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ses:SendEmail",
                "ses:SendRawEmail"
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
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
EOF
    
    # Attach custom policy to role
    aws iam put-role-policy \
        --role-name "${LAMBDA_ROLE_NAME}" \
        --policy-name EmailListManagementPolicy \
        --policy-document "file://${TEMP_DIR}/lambda-permissions-policy.json"
    
    # Wait for role to propagate
    log "Waiting for IAM role to propagate..."
    sleep 10
    
    success "IAM role ${LAMBDA_ROLE_NAME} created with required permissions"
}

# Create Lambda function code files
create_lambda_code() {
    log "Creating Lambda function code files..."
    
    # Subscribe function
    cat > "${TEMP_DIR}/subscribe_function.py" << 'EOF'
import json
import boto3
import datetime
import os
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    try:
        body = json.loads(event['body']) if 'body' in event else event
        email = body.get('email', '').lower().strip()
        name = body.get('name', 'Subscriber')
        
        if not email or '@' not in email:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Valid email required'})
            }
        
        # Add subscriber to DynamoDB
        response = table.put_item(
            Item={
                'email': email,
                'name': name,
                'subscribed_date': datetime.datetime.now().isoformat(),
                'status': 'active'
            },
            ConditionExpression='attribute_not_exists(email)'
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully subscribed {email}',
                'email': email
            })
        }
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            return {
                'statusCode': 409,
                'body': json.dumps({'error': 'Email already subscribed'})
            }
        raise e
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }
EOF
    
    # Newsletter function
    cat > "${TEMP_DIR}/newsletter_function.py" << 'EOF'
import json
import boto3
import os
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
ses = boto3.client('ses')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    try:
        body = json.loads(event['body']) if 'body' in event else event
        subject = body.get('subject', 'Newsletter Update')
        message = body.get('message', 'Thank you for subscribing!')
        sender_email = os.environ['SENDER_EMAIL']
        
        # Get all active subscribers with pagination support
        subscribers = []
        response = table.scan(
            FilterExpression='#status = :status',
            ExpressionAttributeNames={'#status': 'status'},
            ExpressionAttributeValues={':status': 'active'}
        )
        subscribers.extend(response['Items'])
        
        # Handle pagination for large subscriber lists
        while 'LastEvaluatedKey' in response:
            response = table.scan(
                FilterExpression='#status = :status',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={':status': 'active'},
                ExclusiveStartKey=response['LastEvaluatedKey']
            )
            subscribers.extend(response['Items'])
        
        sent_count = 0
        failed_count = 0
        
        for subscriber in subscribers:
            try:
                # Send personalized email
                ses.send_email(
                    Source=sender_email,
                    Destination={'ToAddresses': [subscriber['email']]},
                    Message={
                        'Subject': {'Data': subject},
                        'Body': {
                            'Text': {
                                'Data': f"Hello {subscriber['name']},\n\n{message}\n\nBest regards,\nYour Newsletter Team"
                            },
                            'Html': {
                                'Data': f"""
                                <html>
                                <body>
                                <h2>Hello {subscriber['name']},</h2>
                                <p>{message}</p>
                                <p>Best regards,<br>Your Newsletter Team</p>
                                </body>
                                </html>
                                """
                            }
                        }
                    }
                )
                sent_count += 1
            except ClientError as e:
                print(f"Failed to send to {subscriber['email']}: {e}")
                failed_count += 1
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Newsletter sent to {sent_count} subscribers',
                'sent_count': sent_count,
                'failed_count': failed_count,
                'total_subscribers': len(subscribers)
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Failed to send newsletter'})
        }
EOF
    
    # List subscribers function
    cat > "${TEMP_DIR}/list_function.py" << 'EOF'
import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def lambda_handler(event, context):
    try:
        # Scan table for all subscribers with pagination support
        subscribers = []
        response = table.scan()
        subscribers.extend(response['Items'])
        
        # Handle pagination for large subscriber lists
        while 'LastEvaluatedKey' in response:
            response = table.scan(
                ExclusiveStartKey=response['LastEvaluatedKey']
            )
            subscribers.extend(response['Items'])
        
        # Convert Decimal types for JSON serialization
        for subscriber in subscribers:
            for key, value in subscriber.items():
                if isinstance(value, Decimal):
                    subscriber[key] = float(value)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'subscribers': subscribers,
                'total_count': len(subscribers)
            }, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Failed to retrieve subscribers'})
        }
EOF
    
    success "Lambda function code files created"
}

# Create and deploy Lambda functions
create_lambda_functions() {
    log "Creating and deploying Lambda functions..."
    
    # Get IAM role ARN
    ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
    
    # Create subscribe function
    log "Creating subscribe Lambda function..."
    cd "${TEMP_DIR}"
    zip -q subscribe_function.zip subscribe_function.py
    
    if aws lambda get-function --function-name "${SUBSCRIBE_FUNCTION_NAME}" >/dev/null 2>&1; then
        warning "Subscribe function already exists, updating code..."
        aws lambda update-function-code \
            --function-name "${SUBSCRIBE_FUNCTION_NAME}" \
            --zip-file fileb://subscribe_function.zip
    else
        aws lambda create-function \
            --function-name "${SUBSCRIBE_FUNCTION_NAME}" \
            --runtime python3.12 \
            --role "${ROLE_ARN}" \
            --handler subscribe_function.lambda_handler \
            --zip-file fileb://subscribe_function.zip \
            --timeout 30 \
            --memory-size 256 \
            --environment Variables="{TABLE_NAME=${TABLE_NAME}}" \
            --tags Purpose=EmailListManagement,Environment=Development,CreatedBy=email-list-deployment-script
    fi
    
    success "Subscribe Lambda function created: ${SUBSCRIBE_FUNCTION_NAME}"
    
    # Create newsletter function
    log "Creating newsletter Lambda function..."
    zip -q newsletter_function.zip newsletter_function.py
    
    if aws lambda get-function --function-name "${NEWSLETTER_FUNCTION_NAME}" >/dev/null 2>&1; then
        warning "Newsletter function already exists, updating code..."
        aws lambda update-function-code \
            --function-name "${NEWSLETTER_FUNCTION_NAME}" \
            --zip-file fileb://newsletter_function.zip
    else
        aws lambda create-function \
            --function-name "${NEWSLETTER_FUNCTION_NAME}" \
            --runtime python3.12 \
            --role "${ROLE_ARN}" \
            --handler newsletter_function.lambda_handler \
            --zip-file fileb://newsletter_function.zip \
            --timeout 300 \
            --memory-size 512 \
            --environment Variables="{TABLE_NAME=${TABLE_NAME},SENDER_EMAIL=${SENDER_EMAIL}}" \
            --tags Purpose=EmailListManagement,Environment=Development,CreatedBy=email-list-deployment-script
    fi
    
    success "Newsletter Lambda function created: ${NEWSLETTER_FUNCTION_NAME}"
    
    # Create list subscribers function
    log "Creating list subscribers Lambda function..."
    zip -q list_function.zip list_function.py
    
    if aws lambda get-function --function-name "${LIST_FUNCTION_NAME}" >/dev/null 2>&1; then
        warning "List function already exists, updating code..."
        aws lambda update-function-code \
            --function-name "${LIST_FUNCTION_NAME}" \
            --zip-file fileb://list_function.zip
    else
        aws lambda create-function \
            --function-name "${LIST_FUNCTION_NAME}" \
            --runtime python3.12 \
            --role "${ROLE_ARN}" \
            --handler list_function.lambda_handler \
            --zip-file fileb://list_function.zip \
            --timeout 30 \
            --memory-size 256 \
            --environment Variables="{TABLE_NAME=${TABLE_NAME}}" \
            --tags Purpose=EmailListManagement,Environment=Development,CreatedBy=email-list-deployment-script
    fi
    
    success "List subscribers Lambda function created: ${LIST_FUNCTION_NAME}"
}

# Test deployment
test_deployment() {
    log "Testing deployment with sample data..."
    
    # Test subscribe function
    log "Testing subscribe function..."
    SUBSCRIBE_RESULT=$(aws lambda invoke \
        --function-name "${SUBSCRIBE_FUNCTION_NAME}" \
        --payload '{"email":"test@example.com","name":"Test User"}' \
        "${TEMP_DIR}/subscribe_response.json" \
        --output text --query 'StatusCode')
    
    if [ "${SUBSCRIBE_RESULT}" = "200" ]; then
        success "Subscribe function test passed"
    else
        warning "Subscribe function test returned status: ${SUBSCRIBE_RESULT}"
    fi
    
    # Test list function
    log "Testing list subscribers function..."
    LIST_RESULT=$(aws lambda invoke \
        --function-name "${LIST_FUNCTION_NAME}" \
        --payload '{}' \
        "${TEMP_DIR}/list_response.json" \
        --output text --query 'StatusCode')
    
    if [ "${LIST_RESULT}" = "200" ]; then
        success "List subscribers function test passed"
    else
        warning "List subscribers function test returned status: ${LIST_RESULT}"
    fi
    
    # Display test subscriber
    if command -v jq &> /dev/null && [ -f "${TEMP_DIR}/list_response.json" ]; then
        SUBSCRIBER_COUNT=$(jq -r '.body | fromjson | .total_count' "${TEMP_DIR}/list_response.json" 2>/dev/null || echo "0")
        log "Total subscribers in system: ${SUBSCRIBER_COUNT}"
    fi
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    # Create deployment info file
    cat > "./deployment-info.json" << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "resources": {
        "dynamodb_table": "${TABLE_NAME}",
        "iam_role": "${LAMBDA_ROLE_NAME}",
        "lambda_functions": {
            "subscribe": "${SUBSCRIBE_FUNCTION_NAME}",
            "newsletter": "${NEWSLETTER_FUNCTION_NAME}",
            "list": "${LIST_FUNCTION_NAME}"
        },
        "sender_email": "${SENDER_EMAIL}"
    }
}
EOF
    
    success "Deployment information saved to deployment-info.json"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    if [ -d "${TEMP_DIR}" ]; then
        rm -rf "${TEMP_DIR}"
        success "Temporary files cleaned up"
    fi
}

# Main deployment function
main() {
    log "Starting Email List Management System deployment..."
    log "========================================================="
    
    check_prerequisites
    setup_environment
    verify_ses
    create_dynamodb_table
    verify_email_address
    create_iam_role
    create_lambda_code
    create_lambda_functions
    
    log "========================================================="
    success "Deployment completed successfully!"
    log "========================================================="
    
    # Run tests
    test_deployment
    save_deployment_info
    cleanup_temp_files
    
    log ""
    log "📋 Deployment Summary:"
    log "  • DynamoDB Table: ${TABLE_NAME}"
    log "  • IAM Role: ${LAMBDA_ROLE_NAME}"
    log "  • Subscribe Function: ${SUBSCRIBE_FUNCTION_NAME}"
    log "  • Newsletter Function: ${NEWSLETTER_FUNCTION_NAME}"
    log "  • List Function: ${LIST_FUNCTION_NAME}"
    log "  • Sender Email: ${SENDER_EMAIL}"
    log ""
    log "📧 Next Steps:"
    log "  1. Verify your sender email address in SES if not already done"
    log "  2. Test the functions using the AWS Lambda console or CLI"
    log "  3. Consider adding API Gateway for web-based access"
    log "  4. Review CloudWatch logs for function execution details"
    log ""
    log "🧹 To clean up resources, run: ./destroy.sh"
    log ""
    success "Email List Management System is ready to use!"
}

# Run main function
main "$@"