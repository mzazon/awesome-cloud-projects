#!/bin/bash

# Deploy Cost Allocation and Chargeback Systems
# This script implements the infrastructure for AWS cost allocation and chargeback systems
# following the recipe: Cost Allocation and Chargeback Systems

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
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check account permissions (simplified check)
    log "Checking AWS account access..."
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        error "Unable to retrieve AWS account ID. Check your credentials."
        exit 1
    fi
    
    success "Prerequisites check completed. Account ID: $AWS_ACCOUNT_ID"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifier for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 6))
    
    # Set resource names
    export COST_BUCKET_NAME="cost-allocation-reports-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="cost-allocation-alerts-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="cost-allocation-processor-${RANDOM_SUFFIX}"
    
    log "Region: $AWS_REGION"
    log "Account ID: $AWS_ACCOUNT_ID"
    log "Random suffix: $RANDOM_SUFFIX"
    log "S3 Bucket: $COST_BUCKET_NAME"
    log "SNS Topic: $SNS_TOPIC_NAME"
    log "Lambda Function: $LAMBDA_FUNCTION_NAME"
    
    # Save environment variables to file for cleanup
    cat > .env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
COST_BUCKET_NAME=$COST_BUCKET_NAME
SNS_TOPIC_NAME=$SNS_TOPIC_NAME
LAMBDA_FUNCTION_NAME=$LAMBDA_FUNCTION_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    success "Environment variables configured"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for cost reports..."
    
    if aws s3 ls "s3://${COST_BUCKET_NAME}" 2>/dev/null; then
        warning "S3 bucket ${COST_BUCKET_NAME} already exists"
    else
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb "s3://${COST_BUCKET_NAME}"
        else
            aws s3 mb "s3://${COST_BUCKET_NAME}" --region "$AWS_REGION"
        fi
        success "S3 bucket created: $COST_BUCKET_NAME"
    fi
    
    # Configure bucket policy for CUR
    cat > /tmp/bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "billingreports.amazonaws.com"
            },
            "Action": [
                "s3:GetBucketAcl",
                "s3:GetBucketPolicy"
            ],
            "Resource": "arn:aws:s3:::${COST_BUCKET_NAME}"
        },
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "billingreports.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${COST_BUCKET_NAME}/*"
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket "$COST_BUCKET_NAME" \
        --policy file:///tmp/bucket-policy.json
    
    success "S3 bucket policy configured for Cost and Usage Reports"
}

# Function to create cost categories
create_cost_categories() {
    log "Creating cost allocation categories..."
    
    # Create cost category definition
    cat > /tmp/cost-category.json << EOF
{
    "Name": "CostCenter",
    "Rules": [
        {
            "Value": "Engineering",
            "Rule": {
                "Tags": {
                    "Key": "Department",
                    "Values": ["Engineering", "Development", "DevOps"]
                }
            }
        },
        {
            "Value": "Marketing",
            "Rule": {
                "Tags": {
                    "Key": "Department",
                    "Values": ["Marketing", "Sales", "Customer Success"]
                }
            }
        },
        {
            "Value": "Operations",
            "Rule": {
                "Tags": {
                    "Key": "Department",
                    "Values": ["Operations", "Finance", "HR"]
                }
            }
        }
    ],
    "RuleVersion": "CostCategoryExpression.v1"
}
EOF
    
    if aws ce create-cost-category-definition --cli-input-json file:///tmp/cost-category.json > /dev/null 2>&1; then
        success "Cost category definitions created"
    else
        warning "Cost categories may already exist or insufficient permissions"
    fi
}

# Function to create Cost and Usage Report
create_cur_report() {
    log "Creating Cost and Usage Report..."
    
    cat > /tmp/cur-definition.json << EOF
{
    "ReportName": "cost-allocation-report",
    "TimeUnit": "DAILY",
    "Format": "textORcsv",
    "Compression": "GZIP",
    "AdditionalSchemaElements": [
        "RESOURCES"
    ],
    "S3Bucket": "${COST_BUCKET_NAME}",
    "S3Prefix": "cost-reports/",
    "S3Region": "${AWS_REGION}",
    "AdditionalArtifacts": [
        "REDSHIFT",
        "ATHENA"
    ],
    "RefreshClosedReports": true,
    "ReportVersioning": "OVERWRITE_REPORT"
}
EOF
    
    if aws cur put-report-definition --report-definition file:///tmp/cur-definition.json > /dev/null 2>&1; then
        success "Cost and Usage Report configured"
    else
        warning "CUR report may already exist or insufficient permissions"
    fi
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for cost alerts..."
    
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query TopicArn --output text)
    
    # Create topic policy for budget notifications
    cat > /tmp/sns-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "budgets.amazonaws.com"
            },
            "Action": "SNS:Publish",
            "Resource": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF
    
    aws sns set-topic-attributes \
        --topic-arn "$SNS_TOPIC_ARN" \
        --attribute-name Policy \
        --attribute-value file:///tmp/sns-policy.json
    
    # Store SNS topic ARN in environment file
    echo "SNS_TOPIC_ARN=$SNS_TOPIC_ARN" >> .env
    
    success "SNS topic created: $SNS_TOPIC_ARN"
}

# Function to create department budgets
create_budgets() {
    log "Creating department-specific budgets..."
    
    # Get SNS topic ARN from environment
    source .env
    
    # Create Engineering budget
    cat > /tmp/engineering-budget.json << EOF
{
    "AccountId": "${AWS_ACCOUNT_ID}",
    "Budget": {
        "BudgetName": "Engineering-Monthly-Budget",
        "BudgetLimit": {
            "Amount": "1000",
            "Unit": "USD"
        },
        "TimeUnit": "MONTHLY",
        "BudgetType": "COST",
        "CostFilters": {
            "TagKey": ["Department"],
            "TagValue": ["Engineering"]
        }
    },
    "NotificationsWithSubscribers": [
        {
            "Notification": {
                "NotificationType": "ACTUAL",
                "ComparisonOperator": "GREATER_THAN",
                "Threshold": 80,
                "ThresholdType": "PERCENTAGE"
            },
            "Subscribers": [
                {
                    "SubscriptionType": "SNS",
                    "Address": "${SNS_TOPIC_ARN}"
                }
            ]
        }
    ]
}
EOF
    
    # Create Marketing budget
    cat > /tmp/marketing-budget.json << EOF
{
    "AccountId": "${AWS_ACCOUNT_ID}",
    "Budget": {
        "BudgetName": "Marketing-Monthly-Budget",
        "BudgetLimit": {
            "Amount": "500",
            "Unit": "USD"
        },
        "TimeUnit": "MONTHLY",
        "BudgetType": "COST",
        "CostFilters": {
            "TagKey": ["Department"],
            "TagValue": ["Marketing"]
        }
    },
    "NotificationsWithSubscribers": [
        {
            "Notification": {
                "NotificationType": "ACTUAL",
                "ComparisonOperator": "GREATER_THAN",
                "Threshold": 75,
                "ThresholdType": "PERCENTAGE"
            },
            "Subscribers": [
                {
                    "SubscriptionType": "SNS",
                    "Address": "${SNS_TOPIC_ARN}"
                }
            ]
        }
    ]
}
EOF
    
    # Create budgets
    if aws budgets create-budget --cli-input-json file:///tmp/engineering-budget.json > /dev/null 2>&1; then
        success "Engineering budget created"
    else
        warning "Engineering budget may already exist"
    fi
    
    if aws budgets create-budget --cli-input-json file:///tmp/marketing-budget.json > /dev/null 2>&1; then
        success "Marketing budget created"
    else
        warning "Marketing budget may already exist"
    fi
}

# Function to create Lambda IAM role
create_lambda_role() {
    log "Creating Lambda IAM role..."
    
    # Create trust policy
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
    
    # Create IAM role
    aws iam create-role \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        > /dev/null
    
    # Attach managed policies
    aws iam attach-role-policy \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam attach-role-policy \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --policy-arn arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess
    
    # Create inline policy for S3 and SNS access
    cat > /tmp/lambda-inline-policy.json << EOF
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
                "arn:aws:s3:::${COST_BUCKET_NAME}",
                "arn:aws:s3:::${COST_BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --policy-name CostAllocationPolicy \
        --policy-document file:///tmp/lambda-inline-policy.json
    
    success "Lambda IAM role created"
    
    # Wait for role to propagate
    log "Waiting for IAM role to propagate..."
    sleep 10
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function for cost processing..."
    
    # Create Lambda function code
    cat > /tmp/cost_processor.py << 'EOF'
import json
import boto3
import csv
from datetime import datetime, timedelta
from decimal import Decimal

def lambda_handler(event, context):
    ce_client = boto3.client('ce')
    sns_client = boto3.client('sns')
    
    # Get cost data for the last 30 days
    end_date = datetime.now().strftime('%Y-%m-%d')
    start_date = (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')
    
    try:
        # Query costs by department
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date,
                'End': end_date
            },
            Granularity='MONTHLY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {
                    'Type': 'TAG',
                    'Key': 'Department'
                }
            ]
        )
        
        # Process cost data
        department_costs = {}
        for result in response['ResultsByTime']:
            for group in result['Groups']:
                dept = group['Keys'][0] if group['Keys'][0] != 'No Department' else 'Untagged'
                cost = float(group['Metrics']['BlendedCost']['Amount'])
                department_costs[dept] = department_costs.get(dept, 0) + cost
        
        # Create chargeback report
        report = {
            'report_date': end_date,
            'period': f"{start_date} to {end_date}",
            'department_costs': department_costs,
            'total_cost': sum(department_costs.values())
        }
        
        # Send notification with summary
        message = f"""
Cost Allocation Report - {end_date}

Department Breakdown:
"""
        for dept, cost in department_costs.items():
            message += f"• {dept}: ${cost:.2f}\n"
        
        message += f"\nTotal Cost: ${report['total_cost']:.2f}"
        
        # Get SNS topic ARN from environment variable
        topic_arn = f"arn:aws:sns:{context.invoked_function_arn.split(':')[3]}:{context.invoked_function_arn.split(':')[4]}:cost-allocation-alerts"
        
        sns_client.publish(
            TopicArn=topic_arn,
            Subject='Monthly Cost Allocation Report',
            Message=message
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(report, default=str)
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f"Error processing costs: {str(e)}")
        }
EOF
    
    # Create deployment package
    cd /tmp && zip cost_processor.zip cost_processor.py
    
    # Get Lambda role ARN
    LAMBDA_ROLE_ARN=$(aws iam get-role \
        --role-name "${LAMBDA_FUNCTION_NAME}-role" \
        --query Role.Arn --output text)
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "$LAMBDA_ROLE_ARN" \
        --handler cost_processor.lambda_handler \
        --zip-file fileb://cost_processor.zip \
        --timeout 60 \
        --memory-size 256 \
        > /dev/null
    
    success "Lambda function created: $LAMBDA_FUNCTION_NAME"
}

# Function to create EventBridge schedule
create_eventbridge_schedule() {
    log "Creating EventBridge schedule for monthly cost processing..."
    
    # Create EventBridge rule
    aws events put-rule \
        --name cost-allocation-schedule \
        --schedule-expression "cron(0 9 1 * ? *)" \
        --description "Monthly cost allocation processing" \
        > /dev/null
    
    # Add Lambda permission for EventBridge
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id cost-allocation-schedule \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/cost-allocation-schedule" \
        > /dev/null
    
    # Add Lambda target to EventBridge rule
    aws events put-targets \
        --rule cost-allocation-schedule \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}" \
        > /dev/null
    
    success "EventBridge schedule created"
}

# Function to set up cost anomaly detection
create_anomaly_detection() {
    log "Setting up cost anomaly detection..."
    
    # Create anomaly detector
    cat > /tmp/anomaly-detector.json << EOF
{
    "DetectorName": "DepartmentCostAnomalyDetector",
    "MonitorType": "DIMENSIONAL",
    "DimensionKey": "TAG",
    "MatchOptions": ["EQUALS"],
    "MonitorSpecification": "Department"
}
EOF
    
    if DETECTOR_ARN=$(aws ce create-anomaly-detector \
        --anomaly-detector file:///tmp/anomaly-detector.json \
        --query DetectorArn --output text 2>/dev/null); then
        
        # Create anomaly subscription
        cat > /tmp/anomaly-subscription.json << EOF
{
    "SubscriptionName": "CostAnomalyAlerts",
    "MonitorArnList": ["${DETECTOR_ARN}"],
    "Subscribers": [
        {
            "Address": "${SNS_TOPIC_ARN}",
            "Type": "SNS"
        }
    ],
    "Threshold": 100,
    "Frequency": "DAILY"
}
EOF
        
        aws ce create-anomaly-subscription \
            --anomaly-subscription file:///tmp/anomaly-subscription.json \
            > /dev/null
        
        success "Cost anomaly detection configured"
    else
        warning "Cost anomaly detection setup failed or already exists"
    fi
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check S3 bucket
    if aws s3 ls "s3://${COST_BUCKET_NAME}" > /dev/null 2>&1; then
        success "S3 bucket validation passed"
    else
        error "S3 bucket validation failed"
    fi
    
    # Check SNS topic
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" > /dev/null 2>&1; then
        success "SNS topic validation passed"
    else
        error "SNS topic validation failed"
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" > /dev/null 2>&1; then
        success "Lambda function validation passed"
    else
        error "Lambda function validation failed"
    fi
    
    # Check budgets
    if aws budgets describe-budget \
        --account-id "$AWS_ACCOUNT_ID" \
        --budget-name "Engineering-Monthly-Budget" > /dev/null 2>&1; then
        success "Budget validation passed"
    else
        warning "Budget validation failed (may be expected if quotas exceeded)"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f /tmp/bucket-policy.json
    rm -f /tmp/cost-category.json
    rm -f /tmp/cur-definition.json
    rm -f /tmp/sns-policy.json
    rm -f /tmp/engineering-budget.json
    rm -f /tmp/marketing-budget.json
    rm -f /tmp/lambda-trust-policy.json
    rm -f /tmp/lambda-inline-policy.json
    rm -f /tmp/cost_processor.py
    rm -f /tmp/cost_processor.zip
    rm -f /tmp/anomaly-detector.json
    rm -f /tmp/anomaly-subscription.json
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log "Starting Cost Allocation and Chargeback Systems deployment..."
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_cost_categories
    create_cur_report
    create_sns_topic
    create_budgets
    create_lambda_role
    create_lambda_function
    create_eventbridge_schedule
    create_anomaly_detection
    validate_deployment
    cleanup_temp_files
    
    success "Deployment completed successfully!"
    
    echo ""
    echo "=== Deployment Summary ==="
    echo "S3 Bucket: $COST_BUCKET_NAME"
    echo "SNS Topic: $SNS_TOPIC_NAME"
    echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "Region: $AWS_REGION"
    echo ""
    echo "Next Steps:"
    echo "1. Add email subscribers to SNS topic: $SNS_TOPIC_ARN"
    echo "2. Start tagging resources with 'Department' tag"
    echo "3. Monitor cost reports in S3 bucket (available in 24-48 hours)"
    echo "4. Review budget alerts and adjust thresholds as needed"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"