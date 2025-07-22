#!/bin/bash

# Deploy script for Automated Report Generation with EventBridge Scheduler and S3
# This script deploys a complete serverless reporting solution using AWS services

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2.0 or later."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or not authenticated."
        error "Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    
    # Check if zip is available for Lambda packaging
    if ! command -v zip &> /dev/null; then
        error "zip utility is not installed. Please install zip to create Lambda deployment packages."
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region found. Using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 6))
    
    # Set resource names
    export DATA_BUCKET="report-data-${RANDOM_SUFFIX}"
    export REPORTS_BUCKET="report-output-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION="report-generator-${RANDOM_SUFFIX}"
    export SCHEDULE_NAME="daily-reports-${RANDOM_SUFFIX}"
    
    # Prompt for verified email address
    if [ -z "${VERIFIED_EMAIL:-}" ]; then
        echo -n "Enter your verified SES email address: "
        read VERIFIED_EMAIL
        export VERIFIED_EMAIL
    fi
    
    # Validate email format
    if [[ ! "$VERIFIED_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email format: $VERIFIED_EMAIL"
        exit 1
    fi
    
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "Data Bucket: ${DATA_BUCKET}"
    log "Reports Bucket: ${REPORTS_BUCKET}"
    log "Lambda Function: ${LAMBDA_FUNCTION}"
    log "Schedule Name: ${SCHEDULE_NAME}"
    log "Email Address: ${VERIFIED_EMAIL}"
    
    success "Environment variables configured successfully"
}

# Function to create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    # Create bucket for source data
    if aws s3 mb s3://${DATA_BUCKET} --region ${AWS_REGION}; then
        success "Created data bucket: ${DATA_BUCKET}"
    else
        error "Failed to create data bucket: ${DATA_BUCKET}"
        exit 1
    fi
    
    # Create bucket for generated reports
    if aws s3 mb s3://${REPORTS_BUCKET} --region ${AWS_REGION}; then
        success "Created reports bucket: ${REPORTS_BUCKET}"
    else
        error "Failed to create reports bucket: ${REPORTS_BUCKET}"
        exit 1
    fi
    
    # Enable versioning on both buckets for data protection
    log "Enabling versioning on buckets..."
    aws s3api put-bucket-versioning \
        --bucket ${DATA_BUCKET} \
        --versioning-configuration Status=Enabled
    
    aws s3api put-bucket-versioning \
        --bucket ${REPORTS_BUCKET} \
        --versioning-configuration Status=Enabled
    
    success "S3 buckets created and versioning enabled"
}

# Function to upload sample data
upload_sample_data() {
    log "Creating and uploading sample data..."
    
    # Create sample sales data
    cat > sample_sales.csv << 'EOF'
Date,Product,Sales,Region
2025-01-01,Product A,1000,North
2025-01-01,Product B,1500,South
2025-01-02,Product A,1200,North
2025-01-02,Product B,800,South
2025-01-03,Product A,1100,North
2025-01-03,Product B,1300,South
EOF
    
    # Upload sales data to S3
    if aws s3 cp sample_sales.csv s3://${DATA_BUCKET}/sales/; then
        success "Uploaded sales data to S3"
    else
        error "Failed to upload sales data"
        exit 1
    fi
    
    # Create sample inventory data
    cat > sample_inventory.csv << 'EOF'
Product,Stock,Warehouse,Last_Updated
Product A,250,Warehouse 1,2025-01-03
Product B,180,Warehouse 1,2025-01-03
Product A,300,Warehouse 2,2025-01-03
Product B,220,Warehouse 2,2025-01-03
EOF
    
    # Upload inventory data to S3
    if aws s3 cp sample_inventory.csv s3://${DATA_BUCKET}/inventory/; then
        success "Uploaded inventory data to S3"
    else
        error "Failed to upload inventory data"
        exit 1
    fi
    
    # Clean up local files
    rm -f sample_sales.csv sample_inventory.csv
    
    success "Sample data uploaded successfully"
}

# Function to create IAM roles and policies
create_iam_resources() {
    log "Creating IAM roles and policies..."
    
    # Create trust policy for Lambda service
    cat > lambda-trust-policy.json << 'EOF'
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
    
    # Create IAM role for Lambda
    if aws iam create-role \
        --role-name ReportGeneratorRole \
        --assume-role-policy-document file://lambda-trust-policy.json; then
        success "Created Lambda IAM role"
    else
        warning "Lambda IAM role may already exist"
    fi
    
    # Attach AWS managed policy for basic Lambda execution
    aws iam attach-role-policy \
        --role-name ReportGeneratorRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for S3 and SES access
    cat > lambda-permissions-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${DATA_BUCKET}",
        "arn:aws:s3:::${DATA_BUCKET}/*",
        "arn:aws:s3:::${REPORTS_BUCKET}",
        "arn:aws:s3:::${REPORTS_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail",
        "ses:SendRawEmail"
      ],
      "Resource": "*"
    }
  ]
}
EOF
    
    # Create and attach custom policy
    if aws iam create-policy \
        --policy-name ReportGeneratorPolicy \
        --policy-document file://lambda-permissions-policy.json; then
        success "Created custom IAM policy"
    else
        warning "Custom IAM policy may already exist"
    fi
    
    aws iam attach-role-policy \
        --role-name ReportGeneratorRole \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/ReportGeneratorPolicy
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    success "IAM resources created successfully"
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    # Create Lambda function code
    cat > report_generator.py << 'EOF'
import boto3
import csv
import json
import os
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.base import MIMEBase
from email import encoders
import io

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    ses = boto3.client('ses')
    
    data_bucket = os.environ['DATA_BUCKET']
    reports_bucket = os.environ['REPORTS_BUCKET']
    email_address = os.environ['EMAIL_ADDRESS']
    
    try:
        # Read sales data from S3
        response = s3.get_object(Bucket=data_bucket, Key='sales/sample_sales.csv')
        sales_data = response['Body'].read().decode('utf-8')
        
        # Read inventory data from S3
        response = s3.get_object(Bucket=data_bucket, Key='inventory/sample_inventory.csv')
        inventory_data = response['Body'].read().decode('utf-8')
        
        # Generate comprehensive report
        report_content = generate_report(sales_data, inventory_data)
        
        # Save report to S3 with timestamp
        report_key = f"reports/daily_report_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        s3.put_object(
            Bucket=reports_bucket,
            Key=report_key,
            Body=report_content,
            ContentType='text/csv'
        )
        
        # Send email notification with report attachment
        send_email_report(ses, email_address, report_content, report_key)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Report generated successfully: {report_key}')
        }
        
    except Exception as e:
        print(f"Error generating report: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error generating report: {str(e)}')
        }

def generate_report(sales_data, inventory_data):
    # Process sales data and calculate totals
    sales_reader = csv.DictReader(io.StringIO(sales_data))
    sales_summary = {}
    
    for row in sales_reader:
        product = row['Product']
        sales = int(row['Sales'])
        if product not in sales_summary:
            sales_summary[product] = 0
        sales_summary[product] += sales
    
    # Process inventory data and calculate totals
    inventory_reader = csv.DictReader(io.StringIO(inventory_data))
    inventory_summary = {}
    
    for row in inventory_reader:
        product = row['Product']
        stock = int(row['Stock'])
        if product not in inventory_summary:
            inventory_summary[product] = 0
        inventory_summary[product] += stock
    
    # Generate combined business report
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Product', 'Total Sales', 'Total Inventory', 'Sales Ratio'])
    
    for product in sales_summary:
        total_sales = sales_summary[product]
        total_inventory = inventory_summary.get(product, 0)
        sales_ratio = total_sales / total_inventory if total_inventory > 0 else 0
        writer.writerow([product, total_sales, total_inventory, f"{sales_ratio:.2f}"])
    
    return output.getvalue()

def send_email_report(ses, email_address, report_content, report_key):
    subject = f"Daily Business Report - {datetime.now().strftime('%Y-%m-%d')}"
    
    msg = MIMEMultipart()
    msg['From'] = email_address
    msg['To'] = email_address
    msg['Subject'] = subject
    
    body = f"""
Dear Team,

Please find attached the daily business report generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}.

Report includes:
- Sales summary by product
- Inventory levels by product
- Sales ratio analysis

This report has been automatically generated and stored in S3 at: {report_key}

Best regards,
Automated Reporting System
"""
    
    msg.attach(MIMEText(body, 'plain'))
    
    # Attach CSV report
    attachment = MIMEBase('application', 'octet-stream')
    attachment.set_payload(report_content.encode())
    encoders.encode_base64(attachment)
    attachment.add_header(
        'Content-Disposition',
        f'attachment; filename=daily_report_{datetime.now().strftime("%Y%m%d")}.csv'
    )
    msg.attach(attachment)
    
    # Send email using SES
    ses.send_raw_email(
        Source=email_address,
        Destinations=[email_address],
        RawMessage={'Data': msg.as_string()}
    )
EOF
    
    # Create deployment package
    if zip function.zip report_generator.py; then
        success "Created Lambda deployment package"
    else
        error "Failed to create Lambda deployment package"
        exit 1
    fi
    
    # Create Lambda function
    if aws lambda create-function \
        --function-name ${LAMBDA_FUNCTION} \
        --runtime python3.9 \
        --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/ReportGeneratorRole \
        --handler report_generator.lambda_handler \
        --zip-file fileb://function.zip \
        --timeout 300 \
        --memory-size 512 \
        --environment Variables="{DATA_BUCKET=${DATA_BUCKET},REPORTS_BUCKET=${REPORTS_BUCKET},EMAIL_ADDRESS=${VERIFIED_EMAIL}}"; then
        success "Created Lambda function: ${LAMBDA_FUNCTION}"
    else
        error "Failed to create Lambda function"
        exit 1
    fi
    
    # Clean up temporary files
    rm -f report_generator.py function.zip
    
    success "Lambda function created successfully"
}

# Function to create EventBridge Scheduler
create_eventbridge_scheduler() {
    log "Creating EventBridge Scheduler..."
    
    # Create trust policy for EventBridge Scheduler
    cat > scheduler-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "scheduler.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role for EventBridge Scheduler
    if aws iam create-role \
        --role-name EventBridgeSchedulerRole \
        --assume-role-policy-document file://scheduler-trust-policy.json; then
        success "Created EventBridge Scheduler IAM role"
    else
        warning "EventBridge Scheduler IAM role may already exist"
    fi
    
    # Create policy for Lambda function invocation
    cat > scheduler-permissions-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction"
      ],
      "Resource": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION}"
    }
  ]
}
EOF
    
    # Create and attach policy
    if aws iam create-policy \
        --policy-name EventBridgeSchedulerPolicy \
        --policy-document file://scheduler-permissions-policy.json; then
        success "Created EventBridge Scheduler policy"
    else
        warning "EventBridge Scheduler policy may already exist"
    fi
    
    aws iam attach-role-policy \
        --role-name EventBridgeSchedulerRole \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/EventBridgeSchedulerPolicy
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    # Create EventBridge schedule for daily execution at 9 AM UTC
    if aws scheduler create-schedule \
        --name ${SCHEDULE_NAME} \
        --schedule-expression "cron(0 9 * * ? *)" \
        --target "{\"Arn\":\"arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION}\",\"RoleArn\":\"arn:aws:iam::${AWS_ACCOUNT_ID}:role/EventBridgeSchedulerRole\"}" \
        --flexible-time-window "{\"Mode\":\"OFF\"}" \
        --description "Daily business report generation"; then
        success "Created EventBridge schedule: ${SCHEDULE_NAME}"
    else
        error "Failed to create EventBridge schedule"
        exit 1
    fi
    
    # Clean up temporary files
    rm -f scheduler-trust-policy.json scheduler-permissions-policy.json
    
    success "EventBridge Scheduler created successfully"
}

# Function to configure SES email verification
configure_ses() {
    log "Configuring Amazon SES email verification..."
    
    # Verify email identity in SES
    if aws ses verify-email-identity --email-address ${VERIFIED_EMAIL}; then
        success "Email verification initiated for ${VERIFIED_EMAIL}"
    else
        warning "Email verification may have already been initiated"
    fi
    
    # Check current verification status
    log "Checking email verification status..."
    VERIFICATION_STATUS=$(aws ses get-identity-verification-attributes \
        --identities ${VERIFIED_EMAIL} \
        --query "VerificationAttributes.\"${VERIFIED_EMAIL}\".VerificationStatus" \
        --output text 2>/dev/null || echo "Unknown")
    
    log "Email verification status: ${VERIFICATION_STATUS}"
    
    if [ "$VERIFICATION_STATUS" != "Success" ]; then
        warning "Email verification is not complete."
        warning "Please check your email (${VERIFIED_EMAIL}) and click the verification link."
        warning "Reports will not be sent until email verification is complete."
    else
        success "Email verification is complete"
    fi
    
    success "SES configuration completed"
}

# Function to test the deployment
test_deployment() {
    log "Testing the deployment..."
    
    # Test Lambda function execution
    log "Testing Lambda function..."
    if aws lambda invoke \
        --function-name ${LAMBDA_FUNCTION} \
        --payload '{}' \
        response.json > /dev/null 2>&1; then
        
        # Check the response
        STATUS_CODE=$(cat response.json | grep -o '"statusCode": [0-9]*' | cut -d: -f2 | tr -d ' ')
        if [ "$STATUS_CODE" = "200" ]; then
            success "Lambda function test successful"
        else
            warning "Lambda function test returned status code: $STATUS_CODE"
            cat response.json
        fi
    else
        error "Failed to test Lambda function"
    fi
    
    # Verify EventBridge schedule status
    log "Verifying EventBridge schedule..."
    SCHEDULE_STATE=$(aws scheduler get-schedule --name ${SCHEDULE_NAME} \
        --query 'State' --output text 2>/dev/null || echo "Unknown")
    
    if [ "$SCHEDULE_STATE" = "ENABLED" ]; then
        success "EventBridge schedule is enabled and active"
    else
        warning "EventBridge schedule state: $SCHEDULE_STATE"
    fi
    
    # Check for generated reports
    log "Checking for generated reports..."
    REPORT_COUNT=$(aws s3 ls s3://${REPORTS_BUCKET}/reports/ --recursive | wc -l)
    if [ "$REPORT_COUNT" -gt 0 ]; then
        success "Found $REPORT_COUNT generated report(s) in S3"
    else
        log "No reports found yet (this is normal for a new deployment)"
    fi
    
    # Clean up test files
    rm -f response.json
    
    success "Deployment testing completed"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f lambda-trust-policy.json lambda-permissions-policy.json
    rm -f scheduler-trust-policy.json scheduler-permissions-policy.json
    rm -f sample_sales.csv sample_inventory.csv
    rm -f report_generator.py function.zip response.json
    success "Temporary files cleaned up"
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "======================================"
    success "DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "======================================"
    echo ""
    echo "Resource Summary:"
    echo "  - Data Bucket: ${DATA_BUCKET}"
    echo "  - Reports Bucket: ${REPORTS_BUCKET}"
    echo "  - Lambda Function: ${LAMBDA_FUNCTION}"
    echo "  - EventBridge Schedule: ${SCHEDULE_NAME}"
    echo "  - Email Address: ${VERIFIED_EMAIL}"
    echo ""
    echo "The automated report generation system is now deployed and will:"
    echo "  - Generate daily reports at 9:00 AM UTC"
    echo "  - Process data from S3 and create business insights"
    echo "  - Store reports in S3 with timestamps"
    echo "  - Send email notifications with report attachments"
    echo ""
    echo "Next Steps:"
    echo "  1. Verify your email address if not already done"
    echo "  2. Upload your own data files to s3://${DATA_BUCKET}/"
    echo "  3. Customize the Lambda function for your specific reporting needs"
    echo "  4. Monitor CloudWatch logs for execution details"
    echo ""
    echo "To test the system manually:"
    echo "  aws lambda invoke --function-name ${LAMBDA_FUNCTION} --payload '{}' response.json"
    echo ""
    echo "To clean up resources:"
    echo "  ./destroy.sh"
    echo ""
}

# Main deployment function
main() {
    echo "======================================"
    echo "AWS Automated Report Generation Deployment"
    echo "======================================"
    echo ""
    
    check_prerequisites
    setup_environment
    create_s3_buckets
    upload_sample_data
    create_iam_resources
    create_lambda_function
    create_eventbridge_scheduler
    configure_ses
    test_deployment
    cleanup_temp_files
    display_summary
}

# Run main function
main "$@"