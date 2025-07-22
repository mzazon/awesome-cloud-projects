#!/bin/bash

# deploy.sh - Deployment script for Automated Email Notification Systems
# Recipe: Email Notification Automation with SES
# 
# This script deploys a complete event-driven email automation system using:
# - Amazon SES for email delivery
# - AWS Lambda for email processing
# - Amazon EventBridge for event routing
# - CloudWatch for monitoring

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

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy automated email notification system with SES, Lambda, and EventBridge.

OPTIONS:
    -s, --sender-email EMAIL     Sender email address (required)
    -r, --recipient-email EMAIL  Recipient email address for testing (required)
    -p, --project-name NAME      Project name prefix (optional, auto-generated if not provided)
    -R, --region REGION          AWS region (optional, uses current region)
    --dry-run                    Show what would be deployed without making changes
    -h, --help                   Show this help message

EXAMPLES:
    $0 --sender-email admin@example.com --recipient-email test@example.com
    $0 -s admin@example.com -r test@example.com --project-name my-email-system
    $0 --sender-email admin@example.com --recipient-email test@example.com --dry-run

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Appropriate AWS permissions for SES, Lambda, EventBridge, and IAM
    - Verified email addresses in SES (or SES in sandbox mode)

EOF
}

# Default values
DRY_RUN=false
SENDER_EMAIL=""
RECIPIENT_EMAIL=""
PROJECT_NAME=""
AWS_REGION=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--sender-email)
            SENDER_EMAIL="$2"
            shift 2
            ;;
        -r|--recipient-email)
            RECIPIENT_EMAIL="$2"
            shift 2
            ;;
        -p|--project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -R|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$SENDER_EMAIL" ]]; then
    log_error "Sender email address is required. Use --sender-email option."
    usage
    exit 1
fi

if [[ -z "$RECIPIENT_EMAIL" ]]; then
    log_error "Recipient email address is required. Use --recipient-email option."
    usage
    exit 1
fi

# Validate email format
validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log_error "Invalid email format: $email"
        exit 1
    fi
}

validate_email "$SENDER_EMAIL"
validate_email "$RECIPIENT_EMAIL"

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
    local major_version
    major_version=$(echo "$aws_version" | cut -d. -f1)
    if [[ "$major_version" -lt 2 ]]; then
        log_warning "AWS CLI v2 is recommended. Current version: $aws_version"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local required_services=("ses" "lambda" "events" "iam" "logs" "cloudwatch" "s3")
    for service in "${required_services[@]}"; do
        if ! aws "$service" help &> /dev/null; then
            log_error "AWS CLI does not have access to $service service"
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Setup environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            AWS_REGION="us-east-1"
            log_warning "No region configured, using default: $AWS_REGION"
        fi
    fi
    export AWS_REGION
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique project name if not provided
    if [[ -z "$PROJECT_NAME" ]]; then
        local random_suffix
        random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
        PROJECT_NAME="email-automation-${random_suffix}"
    fi
    export PROJECT_NAME
    
    # Set other environment variables
    export EMAIL_SENDER="$SENDER_EMAIL"
    export EMAIL_RECIPIENT="$RECIPIENT_EMAIL"
    export S3_BUCKET="lambda-deployment-${PROJECT_NAME}"
    
    log_info "Environment configuration:"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "  Project Name: $PROJECT_NAME"
    log_info "  Sender Email: $EMAIL_SENDER"
    log_info "  Recipient Email: $EMAIL_RECIPIENT"
    log_info "  S3 Bucket: $S3_BUCKET"
}

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $description"
        log_info "[DRY-RUN] Command: $cmd"
    else
        log_info "$description"
        eval "$cmd"
    fi
}

# Create S3 bucket for Lambda deployment
create_s3_bucket() {
    log_info "Creating S3 bucket for Lambda deployment packages..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://${S3_BUCKET}" &> /dev/null; then
        log_warning "S3 bucket ${S3_BUCKET} already exists, skipping creation"
        return 0
    fi
    
    local create_cmd="aws s3 mb s3://${S3_BUCKET} --region ${AWS_REGION}"
    execute_command "$create_cmd" "Creating S3 bucket: ${S3_BUCKET}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_success "S3 bucket created successfully"
    fi
}

# Verify SES email addresses
verify_ses_emails() {
    log_info "Verifying SES email addresses..."
    
    local verify_sender_cmd="aws ses verify-email-identity --email-address ${EMAIL_SENDER} --region ${AWS_REGION}"
    execute_command "$verify_sender_cmd" "Verifying sender email: ${EMAIL_SENDER}"
    
    local verify_recipient_cmd="aws ses verify-email-identity --email-address ${EMAIL_RECIPIENT} --region ${AWS_REGION}"
    execute_command "$verify_recipient_cmd" "Verifying recipient email: ${EMAIL_RECIPIENT}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Email verification initiated. Please check your email inboxes and click verification links."
        log_info "Waiting 30 seconds for verification to propagate..."
        sleep 30
        
        # Check verification status
        log_info "Checking verification status..."
        aws ses get-identity-verification-attributes \
            --identities "$EMAIL_SENDER" "$EMAIL_RECIPIENT" \
            --region "$AWS_REGION" || log_warning "Could not check verification status"
        
        log_success "SES email verification process initiated"
    fi
}

# Create IAM role and policies
create_iam_resources() {
    log_info "Creating IAM role and policies..."
    
    # Create trust policy
    local trust_policy=$(cat << 'EOF'
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
)
    
    # Create SES permissions policy
    local ses_policy=$(cat << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail",
        "ses:SendTemplatedEmail"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Write policies to temporary files
        echo "$trust_policy" > "/tmp/lambda-trust-policy-${PROJECT_NAME}.json"
        echo "$ses_policy" > "/tmp/ses-permissions-policy-${PROJECT_NAME}.json"
        
        # Create IAM role
        aws iam create-role \
            --role-name "${PROJECT_NAME}-lambda-role" \
            --assume-role-policy-document "file:///tmp/lambda-trust-policy-${PROJECT_NAME}.json" || {
            log_warning "IAM role may already exist, continuing..."
        }
        
        # Attach basic Lambda execution policy
        aws iam attach-role-policy \
            --role-name "${PROJECT_NAME}-lambda-role" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole || {
            log_warning "Policy may already be attached, continuing..."
        }
        
        # Create and attach SES permissions policy
        aws iam create-policy \
            --policy-name "${PROJECT_NAME}-ses-policy" \
            --policy-document "file:///tmp/ses-permissions-policy-${PROJECT_NAME}.json" || {
            log_warning "Policy may already exist, continuing..."
        }
        
        aws iam attach-role-policy \
            --role-name "${PROJECT_NAME}-lambda-role" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-ses-policy" || {
            log_warning "Policy may already be attached, continuing..."
        }
        
        # Clean up temporary files
        rm -f "/tmp/lambda-trust-policy-${PROJECT_NAME}.json" "/tmp/ses-permissions-policy-${PROJECT_NAME}.json"
        
        log_info "Waiting for IAM role to propagate..."
        sleep 10
        
        log_success "IAM resources created successfully"
    else
        log_info "[DRY-RUN] Would create IAM role: ${PROJECT_NAME}-lambda-role"
        log_info "[DRY-RUN] Would create IAM policy: ${PROJECT_NAME}-ses-policy"
    fi
}

# Create SES email template
create_ses_template() {
    log_info "Creating SES email template..."
    
    local template_json=$(cat << 'EOF'
{
  "TemplateName": "NotificationTemplate",
  "SubjectPart": "{{subject}}",
  "HtmlPart": "<html><body><h2>{{title}}</h2><p>{{message}}</p><p>Timestamp: {{timestamp}}</p><p>Event Source: {{source}}</p></body></html>",
  "TextPart": "{{title}}\n\n{{message}}\n\nTimestamp: {{timestamp}}\nEvent Source: {{source}}"
}
EOF
)
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "$template_json" > "/tmp/email-template-${PROJECT_NAME}.json"
        
        aws ses create-template \
            --template "file:///tmp/email-template-${PROJECT_NAME}.json" \
            --region "$AWS_REGION" || {
            log_warning "Email template may already exist, continuing..."
        }
        
        rm -f "/tmp/email-template-${PROJECT_NAME}.json"
        
        log_info "Waiting for email template to propagate..."
        sleep 10
        
        # Verify template creation
        aws ses get-template \
            --template-name NotificationTemplate \
            --region "$AWS_REGION" > /dev/null || {
            log_warning "Could not verify template creation"
        }
        
        log_success "SES email template created successfully"
    else
        log_info "[DRY-RUN] Would create SES template: NotificationTemplate"
    fi
}

# Create Lambda function
create_lambda_function() {
    log_info "Creating Lambda function for email processing..."
    
    local lambda_code=$(cat << EOF
import json
import boto3
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ses_client = boto3.client('ses')

def lambda_handler(event, context):
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Extract event details
        event_detail = event.get('detail', {})
        event_source = event.get('source', 'unknown')
        event_type = event.get('detail-type', 'Unknown Event')
        
        # Extract email configuration from event
        email_config = event_detail.get('emailConfig', {})
        recipient = email_config.get('recipient', '${EMAIL_RECIPIENT}')
        subject = email_config.get('subject', f'Notification: {event_type}')
        message = event_detail.get('message', 'No message provided')
        title = event_detail.get('title', event_type)
        
        # Prepare template data
        template_data = {
            'subject': subject,
            'title': title,
            'message': message,
            'timestamp': datetime.now().isoformat(),
            'source': event_source
        }
        
        # Send templated email
        response = ses_client.send_templated_email(
            Source='${EMAIL_SENDER}',
            Destination={'ToAddresses': [recipient]},
            Template='NotificationTemplate',
            TemplateData=json.dumps(template_data)
        )
        
        logger.info(f"Email sent successfully: {response['MessageId']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Email sent successfully',
                'messageId': response['MessageId'],
                'recipient': recipient
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing email: {str(e)}")
        # Re-raise to trigger EventBridge retry mechanism
        raise e
EOF
)
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create Lambda function code file
        echo "$lambda_code" > "/tmp/email_processor-${PROJECT_NAME}.py"
        
        # Create deployment package
        cd /tmp
        zip "function-${PROJECT_NAME}.zip" "email_processor-${PROJECT_NAME}.py"
        
        # Upload to S3
        aws s3 cp "function-${PROJECT_NAME}.zip" "s3://${S3_BUCKET}/"
        
        # Create Lambda function
        aws lambda create-function \
            --function-name "${PROJECT_NAME}-email-processor" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role" \
            --handler "email_processor-${PROJECT_NAME}.lambda_handler" \
            --code "S3Bucket=${S3_BUCKET},S3Key=function-${PROJECT_NAME}.zip" \
            --timeout 30 \
            --memory-size 256 \
            --description "Email notification processor for event-driven system" || {
            log_warning "Lambda function may already exist, continuing..."
        }
        
        # Wait for Lambda function to be ready
        log_info "Waiting for Lambda function to be ready..."
        aws lambda wait function-active --function-name "${PROJECT_NAME}-email-processor"
        
        # Clean up temporary files
        rm -f "/tmp/email_processor-${PROJECT_NAME}.py" "/tmp/function-${PROJECT_NAME}.zip"
        
        log_success "Lambda function created successfully"
    else
        log_info "[DRY-RUN] Would create Lambda function: ${PROJECT_NAME}-email-processor"
    fi
}

# Create EventBridge resources
create_eventbridge_resources() {
    log_info "Creating EventBridge custom bus and rules..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create custom event bus
        aws events create-event-bus --name "${PROJECT_NAME}-event-bus" || {
            log_warning "Event bus may already exist, continuing..."
        }
        
        # Create EventBridge rule for email notifications
        aws events put-rule \
            --event-bus-name "${PROJECT_NAME}-event-bus" \
            --name "${PROJECT_NAME}-email-rule" \
            --event-pattern '{
              "source": ["custom.application"],
              "detail-type": ["Email Notification Request"]
            }' \
            --state ENABLED \
            --description "Route email notification requests to Lambda processor"
        
        # Add Lambda function as target
        aws events put-targets \
            --event-bus-name "${PROJECT_NAME}-event-bus" \
            --rule "${PROJECT_NAME}-email-rule" \
            --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-email-processor"
        
        # Grant EventBridge permission to invoke Lambda
        aws lambda add-permission \
            --function-name "${PROJECT_NAME}-email-processor" \
            --statement-id "eventbridge-invoke-${PROJECT_NAME}" \
            --action lambda:InvokeFunction \
            --principal events.amazonaws.com \
            --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${PROJECT_NAME}-event-bus/${PROJECT_NAME}-email-rule" || {
            log_warning "Permission may already exist, continuing..."
        }
        
        # Create priority rule
        aws events put-rule \
            --event-bus-name "${PROJECT_NAME}-event-bus" \
            --name "${PROJECT_NAME}-priority-rule" \
            --event-pattern '{
              "source": ["custom.application"],
              "detail-type": ["Priority Alert"],
              "detail": {
                "priority": ["high", "critical"]
              }
            }' \
            --state ENABLED \
            --description "Handle high priority alerts"
        
        aws events put-targets \
            --event-bus-name "${PROJECT_NAME}-event-bus" \
            --rule "${PROJECT_NAME}-priority-rule" \
            --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-email-processor"
        
        aws lambda add-permission \
            --function-name "${PROJECT_NAME}-email-processor" \
            --statement-id "priority-invoke-${PROJECT_NAME}" \
            --action lambda:InvokeFunction \
            --principal events.amazonaws.com \
            --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${PROJECT_NAME}-event-bus/${PROJECT_NAME}-priority-rule" || {
            log_warning "Permission may already exist, continuing..."
        }
        
        # Create scheduled rule for daily reports
        aws events put-rule \
            --name "${PROJECT_NAME}-daily-report" \
            --schedule-expression "cron(0 9 * * ? *)" \
            --state ENABLED \
            --description "Send daily email reports"
        
        aws events put-targets \
            --rule "${PROJECT_NAME}-daily-report" \
            --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-email-processor"
        
        aws lambda add-permission \
            --function-name "${PROJECT_NAME}-email-processor" \
            --statement-id "scheduled-invoke-${PROJECT_NAME}" \
            --action lambda:InvokeFunction \
            --principal events.amazonaws.com \
            --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${PROJECT_NAME}-daily-report" || {
            log_warning "Permission may already exist, continuing..."
        }
        
        log_success "EventBridge resources created successfully"
    else
        log_info "[DRY-RUN] Would create EventBridge bus: ${PROJECT_NAME}-event-bus"
        log_info "[DRY-RUN] Would create EventBridge rules and targets"
    fi
}

# Create CloudWatch monitoring
create_cloudwatch_monitoring() {
    log_info "Creating CloudWatch monitoring and alarms..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create CloudWatch alarm for Lambda errors
        aws cloudwatch put-metric-alarm \
            --alarm-name "${PROJECT_NAME}-lambda-errors" \
            --alarm-description "Monitor Lambda function errors" \
            --metric-name Errors \
            --namespace AWS/Lambda \
            --statistic Sum \
            --period 300 \
            --threshold 1 \
            --comparison-operator GreaterThanOrEqualToThreshold \
            --evaluation-periods 1 \
            --dimensions Name=FunctionName,Value="${PROJECT_NAME}-email-processor" || {
            log_warning "CloudWatch alarm may already exist, continuing..."
        }
        
        # Create CloudWatch alarm for SES bounces
        aws cloudwatch put-metric-alarm \
            --alarm-name "${PROJECT_NAME}-ses-bounces" \
            --alarm-description "Monitor SES bounce rate" \
            --metric-name Bounce \
            --namespace AWS/SES \
            --statistic Sum \
            --period 300 \
            --threshold 5 \
            --comparison-operator GreaterThanOrEqualToThreshold \
            --evaluation-periods 2 || {
            log_warning "CloudWatch alarm may already exist, continuing..."
        }
        
        # Wait for Lambda log group to be created
        log_info "Waiting for Lambda log group to be created..."
        sleep 30
        
        # Create custom metric filter for Lambda logs
        aws logs put-metric-filter \
            --log-group-name "/aws/lambda/${PROJECT_NAME}-email-processor" \
            --filter-name EmailProcessingErrors \
            --filter-pattern "ERROR" \
            --metric-transformations \
                metricName=EmailProcessingErrors,metricNamespace=CustomMetrics,metricValue=1 || {
            log_warning "Metric filter may already exist, continuing..."
        }
        
        log_success "CloudWatch monitoring and alarms configured"
    else
        log_info "[DRY-RUN] Would create CloudWatch alarms and metric filters"
    fi
}

# Test the deployment
test_deployment() {
    log_info "Testing the email automation system..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Test basic email notification
        aws events put-events \
            --entries '[
              {
                "Source": "custom.application",
                "DetailType": "Email Notification Request",
                "Detail": "{\"emailConfig\":{\"recipient\":\"'${EMAIL_RECIPIENT}'\",\"subject\":\"Test Notification\"},\"title\":\"System Alert\",\"message\":\"This is a test notification from the automated email system.\"}",
                "EventBusName": "'${PROJECT_NAME}'-event-bus"
              }
            ]'
        
        log_info "Test event sent. Waiting for processing..."
        sleep 15
        
        # Check Lambda function logs
        log_info "Checking Lambda function logs..."
        aws logs describe-log-streams \
            --log-group-name "/aws/lambda/${PROJECT_NAME}-email-processor" \
            --order-by LastEventTime \
            --descending \
            --max-items 1 || log_warning "Could not retrieve log streams"
        
        log_success "Test deployment completed. Check your email for the test notification."
    else
        log_info "[DRY-RUN] Would send test events to verify deployment"
    fi
}

# Save deployment information
save_deployment_info() {
    local info_file="deployment-info-${PROJECT_NAME}.txt"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > "$info_file" << EOF
# Deployment Information
# Generated: $(date)

PROJECT_NAME=${PROJECT_NAME}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
EMAIL_SENDER=${EMAIL_SENDER}
EMAIL_RECIPIENT=${EMAIL_RECIPIENT}
S3_BUCKET=${S3_BUCKET}

# Resources Created:
# - IAM Role: ${PROJECT_NAME}-lambda-role
# - IAM Policy: ${PROJECT_NAME}-ses-policy
# - Lambda Function: ${PROJECT_NAME}-email-processor
# - EventBridge Bus: ${PROJECT_NAME}-event-bus
# - EventBridge Rules: ${PROJECT_NAME}-email-rule, ${PROJECT_NAME}-priority-rule, ${PROJECT_NAME}-daily-report
# - SES Template: NotificationTemplate
# - S3 Bucket: ${S3_BUCKET}
# - CloudWatch Alarms: ${PROJECT_NAME}-lambda-errors, ${PROJECT_NAME}-ses-bounces

# To test the system:
# aws events put-events --entries '[{"Source": "custom.application", "DetailType": "Email Notification Request", "Detail": "{\\"emailConfig\\":{\\"recipient\\":\\"${EMAIL_RECIPIENT}\\",\\"subject\\":\\"Test\\"},\\"title\\":\\"Test\\",\\"message\\":\\"Test message\\"}", "EventBusName": "${PROJECT_NAME}-event-bus"}]'

# To clean up:
# ./destroy.sh --project-name ${PROJECT_NAME}
EOF
        
        log_success "Deployment information saved to: $info_file"
    else
        log_info "[DRY-RUN] Would save deployment information to: $info_file"
    fi
}

# Main deployment function
main() {
    log_info "Starting deployment of automated email notification system..."
    log_info "================================================"
    
    check_prerequisites
    setup_environment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY-RUN mode enabled. No resources will be created."
    fi
    
    create_s3_bucket
    verify_ses_emails
    create_iam_resources
    create_ses_template
    create_lambda_function
    create_eventbridge_resources
    create_cloudwatch_monitoring
    test_deployment
    save_deployment_info
    
    log_success "================================================"
    log_success "Deployment completed successfully!"
    log_success "Project Name: $PROJECT_NAME"
    log_success "AWS Region: $AWS_REGION"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info ""
        log_info "Next steps:"
        log_info "1. Check your email (${EMAIL_RECIPIENT}) for the test notification"
        log_info "2. Verify email addresses in SES if not already done"
        log_info "3. Monitor CloudWatch logs and metrics"
        log_info "4. Send test events using the EventBridge console or CLI"
        log_info ""
        log_info "To clean up resources, run:"
        log_info "  ./destroy.sh --project-name ${PROJECT_NAME}"
    fi
}

# Handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code: $exit_code"
        log_info "Check the error messages above for details."
        log_info "You may need to clean up partially created resources."
    fi
    exit $exit_code
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"