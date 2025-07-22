#!/bin/bash

# deploy.sh - Deploy Serverless Email Processing System
# This script deploys the complete serverless email processing infrastructure
# using AWS SES, Lambda, S3, and SNS services

set -e  # Exit on any error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS CLI is not configured. Please run 'aws configure'"
        exit 1
    fi
    
    # Check required permissions
    log "INFO" "Verifying AWS permissions..."
    local required_services=("iam" "lambda" "s3" "ses" "sns")
    for service in "${required_services[@]}"; do
        if ! aws ${service} help &> /dev/null; then
            log "ERROR" "Missing permissions for AWS $service service"
            exit 1
        fi
    done
    
    log "SUCCESS" "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log "ERROR" "AWS region not configured. Please set default region"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names (allow override from environment)
    export DOMAIN_NAME="${DOMAIN_NAME:-example.com}"
    export BUCKET_NAME="${BUCKET_NAME:-email-processing-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-email-processor-${RANDOM_SUFFIX}}"
    export SNS_TOPIC_NAME="${SNS_TOPIC_NAME:-email-notifications-${RANDOM_SUFFIX}}"
    export ROLE_NAME="EmailProcessorRole-${RANDOM_SUFFIX}"
    export POLICY_NAME="EmailProcessorPolicy-${RANDOM_SUFFIX}"
    export RULE_SET_NAME="EmailProcessingRuleSet-${RANDOM_SUFFIX}"
    export RULE_NAME="EmailProcessingRule-${RANDOM_SUFFIX}"
    
    # Prompt for domain name if using default
    if [ "$DOMAIN_NAME" = "example.com" ]; then
        log "WARNING" "Using default domain 'example.com'. Please set DOMAIN_NAME environment variable for production use"
        read -p "Enter your verified SES domain (or press Enter to continue with example.com): " user_domain
        if [ -n "$user_domain" ]; then
            export DOMAIN_NAME="$user_domain"
        fi
    fi
    
    log "INFO" "Environment configured:"
    log "INFO" "  AWS Region: $AWS_REGION"
    log "INFO" "  AWS Account: $AWS_ACCOUNT_ID"
    log "INFO" "  Domain: $DOMAIN_NAME"
    log "INFO" "  S3 Bucket: $BUCKET_NAME"
    log "INFO" "  Lambda Function: $FUNCTION_NAME"
    
    # Save state for cleanup
    cat > "$STATE_FILE" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
DOMAIN_NAME=$DOMAIN_NAME
BUCKET_NAME=$BUCKET_NAME
FUNCTION_NAME=$FUNCTION_NAME
SNS_TOPIC_NAME=$SNS_TOPIC_NAME
ROLE_NAME=$ROLE_NAME
POLICY_NAME=$POLICY_NAME
RULE_SET_NAME=$RULE_SET_NAME
RULE_NAME=$RULE_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
}

# Function to create S3 bucket
create_s3_bucket() {
    log "INFO" "Creating S3 bucket for email storage..."
    
    if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        log "WARNING" "S3 bucket $BUCKET_NAME already exists"
        return 0
    fi
    
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://$BUCKET_NAME"
    else
        aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION"
    fi
    
    # Enable versioning for data protection
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Set bucket policy for SES access
    cat > /tmp/bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowSESPuts",
            "Effect": "Allow",
            "Principal": {
                "Service": "ses.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*",
            "Condition": {
                "StringEquals": {
                    "aws:Referer": "$AWS_ACCOUNT_ID"
                }
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket "$BUCKET_NAME" \
        --policy file:///tmp/bucket-policy.json
    
    rm -f /tmp/bucket-policy.json
    
    log "SUCCESS" "S3 bucket created: $BUCKET_NAME"
}

# Function to create SNS topic
create_sns_topic() {
    log "INFO" "Creating SNS topic for notifications..."
    
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query TopicArn --output text)
    
    # Add SNS topic ARN to state file
    echo "SNS_TOPIC_ARN=$SNS_TOPIC_ARN" >> "$STATE_FILE"
    
    log "SUCCESS" "SNS topic created: $SNS_TOPIC_ARN"
}

# Function to create IAM role and policies
create_iam_resources() {
    log "INFO" "Creating IAM role and policies..."
    
    # Create trust policy
    cat > /tmp/lambda-trust-policy.json << 'EOF'
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
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --description "Role for serverless email processing Lambda function"
    
    export LAMBDA_ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/$ROLE_NAME"
    echo "LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN" >> "$STATE_FILE"
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for S3, SES, and SNS access
    cat > /tmp/email-processor-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
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
                "sns:Publish"
            ],
            "Resource": "$SNS_TOPIC_ARN"
        }
    ]
}
EOF
    
    # Create and attach custom policy
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file:///tmp/email-processor-policy.json \
        --description "Policy for serverless email processing"
    
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME"
    
    # Clean up temporary files
    rm -f /tmp/lambda-trust-policy.json /tmp/email-processor-policy.json
    
    log "SUCCESS" "IAM resources created"
    log "INFO" "Waiting for IAM role propagation (10 seconds)..."
    sleep 10
}

# Function to create Lambda function
create_lambda_function() {
    log "INFO" "Creating Lambda function..."
    
    # Create Lambda function code
    cat > /tmp/email-processor.py << 'EOF'
import json
import boto3
import email
import os
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

s3 = boto3.client('s3')
ses = boto3.client('ses')
sns = boto3.client('sns')

def lambda_handler(event, context):
    # Parse SES event
    ses_event = event['Records'][0]['ses']
    message_id = ses_event['mail']['messageId']
    receipt = ses_event['receipt']
    
    # Get email from S3 if stored there
    bucket_name = os.environ.get('BUCKET_NAME')
    
    try:
        # Get email object from S3
        s3_key = f"emails/{message_id}"
        response = s3.get_object(Bucket=bucket_name, Key=s3_key)
        raw_email = response['Body'].read()
        
        # Parse email
        email_message = email.message_from_bytes(raw_email)
        
        # Extract email details
        sender = email_message.get('From', 'Unknown')
        subject = email_message.get('Subject', 'No Subject')
        recipient = receipt['recipients'][0] if receipt['recipients'] else 'Unknown'
        
        # Process email based on subject or content
        if 'support' in subject.lower():
            process_support_email(sender, subject, email_message)
        elif 'invoice' in subject.lower():
            process_invoice_email(sender, subject, email_message)
        else:
            process_general_email(sender, subject, email_message)
        
        # Send notification
        notify_processing_complete(message_id, sender, subject)
        
        return {'statusCode': 200, 'body': 'Email processed successfully'}
        
    except Exception as e:
        print(f"Error processing email: {str(e)}")
        return {'statusCode': 500, 'body': f'Error: {str(e)}'}

def process_support_email(sender, subject, email_message):
    """Process support-related emails"""
    # Send auto-reply
    reply_subject = f"Re: {subject} - Ticket Created"
    reply_body = f"""
Thank you for contacting our support team.

Your ticket has been created and assigned ID: TICKET-{hash(sender) % 10000}

We will respond within 24 hours.

Best regards,
Support Team
"""
    
    send_reply(sender, reply_subject, reply_body)
    
    # Notify support team via SNS
    sns.publish(
        TopicArn=os.environ.get('SNS_TOPIC_ARN'),
        Subject=f"New Support Ticket: {subject}",
        Message=f"From: {sender}\nSubject: {subject}\nPlease check email processing system."
    )

def process_invoice_email(sender, subject, email_message):
    """Process invoice-related emails"""
    # Send confirmation
    reply_subject = f"Invoice Received: {subject}"
    reply_body = f"""
We have received your invoice.

Invoice will be processed within 5 business days.
Reference: INV-{hash(sender) % 10000}

Accounts Payable Team
"""
    
    send_reply(sender, reply_subject, reply_body)

def process_general_email(sender, subject, email_message):
    """Process general emails"""
    # Send general acknowledgment
    reply_subject = f"Re: {subject}"
    reply_body = f"""
Thank you for your email.

We have received your message and will respond appropriately.

Best regards,
Customer Service
"""
    
    send_reply(sender, reply_subject, reply_body)

def send_reply(to_email, subject, body):
    """Send automated reply via SES"""
    try:
        from_email = os.environ.get('FROM_EMAIL', 'noreply@example.com')
        
        ses.send_email(
            Source=from_email,
            Destination={'ToAddresses': [to_email]},
            Message={
                'Subject': {'Data': subject},
                'Body': {'Text': {'Data': body}}
            }
        )
    except Exception as e:
        print(f"Error sending reply: {str(e)}")

def notify_processing_complete(message_id, sender, subject):
    """Send processing notification via SNS"""
    sns.publish(
        TopicArn=os.environ.get('SNS_TOPIC_ARN'),
        Subject="Email Processed",
        Message=f"Message ID: {message_id}\nFrom: {sender}\nSubject: {subject}"
    )
EOF
    
    # Package the function
    cd /tmp
    zip email-processor.zip email-processor.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler email-processor.lambda_handler \
        --zip-file fileb://email-processor.zip \
        --timeout 60 \
        --memory-size 256 \
        --environment Variables="{
            BUCKET_NAME=$BUCKET_NAME,
            SNS_TOPIC_ARN=$SNS_TOPIC_ARN,
            FROM_EMAIL=noreply@$DOMAIN_NAME
        }" \
        --description "Serverless email processing function"
    
    # Get function ARN
    export LAMBDA_ARN=$(aws lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --query Configuration.FunctionArn --output text)
    
    echo "LAMBDA_ARN=$LAMBDA_ARN" >> "$STATE_FILE"
    
    # Clean up temporary files
    rm -f /tmp/email-processor.py /tmp/email-processor.zip
    
    log "SUCCESS" "Lambda function created: $LAMBDA_ARN"
}

# Function to configure SES permissions
configure_ses_permissions() {
    log "INFO" "Configuring SES permissions for Lambda..."
    
    # Add permission for SES to invoke Lambda
    aws lambda add-permission \
        --function-name "$FUNCTION_NAME" \
        --statement-id ses-invoke \
        --action lambda:InvokeFunction \
        --principal ses.amazonaws.com \
        --source-account "$AWS_ACCOUNT_ID"
    
    log "SUCCESS" "SES permissions configured"
}

# Function to configure SES domain and rules
configure_ses_rules() {
    log "INFO" "Configuring SES domain and receipt rules..."
    
    # Verify domain for receiving (if not already done)
    log "INFO" "Verifying domain identity for SES..."
    aws ses verify-domain-identity --domain "$DOMAIN_NAME" || true
    
    # Display MX record information
    log "INFO" "Please add this MX record to your domain DNS:"
    log "INFO" "  Priority: 10"
    log "INFO" "  Value: inbound-smtp.$AWS_REGION.amazonaws.com"
    
    if [ "$DOMAIN_NAME" = "example.com" ]; then
        log "WARNING" "Using example.com domain - SES receipt rules will be created but email receiving will not work"
        log "WARNING" "Please update DOMAIN_NAME environment variable and redeploy for production use"
    else
        read -p "Press Enter after adding the MX record to continue (or Ctrl+C to cancel)..."
    fi
    
    # Create rule set
    aws ses create-receipt-rule-set \
        --rule-set-name "$RULE_SET_NAME" || true
    
    # Set as active rule set
    aws ses set-active-receipt-rule-set \
        --rule-set-name "$RULE_SET_NAME"
    
    # Create receipt rule
    cat > /tmp/receipt-rule.json << EOF
{
    "Name": "$RULE_NAME",
    "Enabled": true,
    "TlsPolicy": "Optional",
    "Recipients": ["support@$DOMAIN_NAME", "invoices@$DOMAIN_NAME"],
    "Actions": [
        {
            "S3Action": {
                "BucketName": "$BUCKET_NAME",
                "ObjectKeyPrefix": "emails/"
            }
        },
        {
            "LambdaAction": {
                "FunctionArn": "$LAMBDA_ARN",
                "InvocationType": "Event"
            }
        }
    ]
}
EOF
    
    # Create the receipt rule
    aws ses create-receipt-rule \
        --rule-set-name "$RULE_SET_NAME" \
        --rule file:///tmp/receipt-rule.json
    
    rm -f /tmp/receipt-rule.json
    
    log "SUCCESS" "SES receipt rules configured"
}

# Function to setup SNS notifications
setup_sns_notifications() {
    log "INFO" "Setting up SNS notifications..."
    
    # Prompt for notification email
    if [ -z "${EMAIL_FOR_NOTIFICATIONS:-}" ]; then
        read -p "Enter email address for notifications (or press Enter to skip): " EMAIL_FOR_NOTIFICATIONS
    fi
    
    if [ -n "$EMAIL_FOR_NOTIFICATIONS" ]; then
        aws sns subscribe \
            --topic-arn "$SNS_TOPIC_ARN" \
            --protocol email \
            --notification-endpoint "$EMAIL_FOR_NOTIFICATIONS"
        
        log "SUCCESS" "SNS subscription created. Please check email and confirm subscription."
        echo "EMAIL_FOR_NOTIFICATIONS=$EMAIL_FOR_NOTIFICATIONS" >> "$STATE_FILE"
    else
        log "INFO" "Skipping SNS email subscription"
    fi
}

# Function to display deployment summary
deployment_summary() {
    log "SUCCESS" "Deployment completed successfully!"
    echo
    log "INFO" "Resource Summary:"
    log "INFO" "  S3 Bucket: $BUCKET_NAME"
    log "INFO" "  Lambda Function: $FUNCTION_NAME"
    log "INFO" "  SNS Topic: $SNS_TOPIC_NAME"
    log "INFO" "  SES Rule Set: $RULE_SET_NAME"
    log "INFO" "  Domain: $DOMAIN_NAME"
    echo
    log "INFO" "Test the system by sending emails to:"
    log "INFO" "  support@$DOMAIN_NAME (for support tickets)"
    log "INFO" "  invoices@$DOMAIN_NAME (for invoice processing)"
    echo
    log "INFO" "To clean up resources, run: ./destroy.sh"
    echo
    log "INFO" "Deployment state saved to: $STATE_FILE"
}

# Main deployment function
main() {
    log "INFO" "Starting serverless email processing system deployment..."
    log "INFO" "Log file: $LOG_FILE"
    
    # Check if already deployed
    if [ -f "$STATE_FILE" ]; then
        log "WARNING" "Deployment state file exists. Resources may already be deployed."
        read -p "Continue anyway? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            log "INFO" "Deployment cancelled"
            exit 0
        fi
    fi
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_sns_topic
    create_iam_resources
    create_lambda_function
    configure_ses_permissions
    configure_ses_rules
    setup_sns_notifications
    deployment_summary
    
    log "SUCCESS" "Deployment completed successfully!"
}

# Error handling
trap 'log "ERROR" "Deployment failed at line $LINENO. Check $LOG_FILE for details."' ERR

# Run main function
main "$@"