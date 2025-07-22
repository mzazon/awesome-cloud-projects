#!/bin/bash

# AWS Reserved Instance Management Automation - Deployment Script
# This script deploys the complete RI management automation solution

set -e
set -o pipefail

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI not authenticated. Please run 'aws configure' or set up your credentials."
        exit 1
    fi
    success "AWS CLI authentication verified"
}

# Function to check Cost Explorer access
check_cost_explorer() {
    log "Checking Cost Explorer API access..."
    if ! aws ce get-cost-and-usage \
        --time-period Start=2024-01-01,End=2024-01-02 \
        --granularity MONTHLY \
        --metrics BlendedCost >/dev/null 2>&1; then
        warning "Cost Explorer API access check failed. Please ensure Cost Explorer is enabled."
        warning "You can enable it in the AWS Console under Billing & Cost Management."
    else
        success "Cost Explorer API access verified"
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    success "AWS CLI found"
    
    # Check required tools
    for tool in jq zip; do
        if ! command_exists "$tool"; then
            error "$tool is not installed. Please install $tool."
            exit 1
        fi
    done
    success "Required tools verified"
    
    # Check AWS authentication
    check_aws_auth
    
    # Check Cost Explorer
    check_cost_explorer
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export PROJECT_NAME="ri-management-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="ri-reports-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="ri-alerts-${RANDOM_SUFFIX}"
    export DYNAMODB_TABLE_NAME="ri-tracking-${RANDOM_SUFFIX}"
    
    # Save environment variables for cleanup script
    cat > .env_vars << EOF
PROJECT_NAME="${PROJECT_NAME}"
S3_BUCKET_NAME="${S3_BUCKET_NAME}"
SNS_TOPIC_NAME="${SNS_TOPIC_NAME}"
DYNAMODB_TABLE_NAME="${DYNAMODB_TABLE_NAME}"
AWS_REGION="${AWS_REGION}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
EOF
    
    success "Environment variables configured"
    log "Project Name: ${PROJECT_NAME}"
    log "S3 Bucket: ${S3_BUCKET_NAME}"
    log "Region: ${AWS_REGION}"
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for RI reports..."
    
    if aws s3 ls "s3://${S3_BUCKET_NAME}" >/dev/null 2>&1; then
        warning "S3 bucket ${S3_BUCKET_NAME} already exists, skipping creation"
    else
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb "s3://${S3_BUCKET_NAME}"
        else
            aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}"
        fi
        success "S3 bucket created: ${S3_BUCKET_NAME}"
    fi
    
    # Add bucket versioning for data protection
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Add lifecycle policy to manage costs
    cat > lifecycle-policy.json << 'EOF'
{
    "Rules": [
        {
            "ID": "RI-Reports-Lifecycle",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "ri-"
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ]
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "${S3_BUCKET_NAME}" \
        --lifecycle-configuration file://lifecycle-policy.json
    
    rm -f lifecycle-policy.json
    success "S3 bucket lifecycle policy configured"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for notifications..."
    
    export SNS_TOPIC_ARN=$(aws sns create-topic --name "${SNS_TOPIC_NAME}" \
        --query TopicArn --output text)
    
    # Add the topic ARN to environment file
    echo "SNS_TOPIC_ARN=\"${SNS_TOPIC_ARN}\"" >> .env_vars
    
    success "SNS topic created: ${SNS_TOPIC_ARN}"
}

# Function to create DynamoDB table
create_dynamodb_table() {
    log "Creating DynamoDB table for RI tracking..."
    
    aws dynamodb create-table \
        --table-name "${DYNAMODB_TABLE_NAME}" \
        --attribute-definitions \
            AttributeName=ReservationId,AttributeType=S \
            AttributeName=Timestamp,AttributeType=N \
        --key-schema \
            AttributeName=ReservationId,KeyType=HASH \
            AttributeName=Timestamp,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value="${PROJECT_NAME}" \
        --region "${AWS_REGION}"
    
    log "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name "${DYNAMODB_TABLE_NAME}" --region "${AWS_REGION}"
    
    success "DynamoDB table created: ${DYNAMODB_TABLE_NAME}"
}

# Function to create IAM role and policies
create_iam_role() {
    log "Creating IAM role for Lambda functions..."
    
    # Create trust policy
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
    
    # Create IAM role
    aws iam create-role \
        --role-name "${PROJECT_NAME}-lambda-role" \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --tags Key=Project,Value="${PROJECT_NAME}"
    
    # Create custom policy
    cat > lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ce:GetDimensionValues",
                "ce:GetUsageAndCosts",
                "ce:GetReservationCoverage",
                "ce:GetReservationPurchaseRecommendation",
                "ce:GetReservationUtilization",
                "ce:GetRightsizingRecommendation"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeReservedInstances"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DYNAMODB_TABLE_NAME}"
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
    
    # Attach policies to role
    aws iam attach-role-policy \
        --role-name "${PROJECT_NAME}-lambda-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    aws iam put-role-policy \
        --role-name "${PROJECT_NAME}-lambda-role" \
        --policy-name "${PROJECT_NAME}-custom-policy" \
        --policy-document file://lambda-policy.json
    
    # Clean up policy files
    rm -f lambda-trust-policy.json lambda-policy.json
    
    success "IAM role created: ${PROJECT_NAME}-lambda-role"
    
    # Wait for role propagation
    log "Waiting for IAM role propagation..."
    sleep 10
}

# Function to create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create RI Utilization Analysis Lambda
    cat > ri_utilization_analysis.py << 'EOF'
import json
import boto3
import datetime
from decimal import Decimal
import os

def lambda_handler(event, context):
    ce = boto3.client('ce')
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    # Get environment variables
    bucket_name = os.environ['S3_BUCKET_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    # Calculate date range (last 30 days)
    end_date = datetime.date.today()
    start_date = end_date - datetime.timedelta(days=30)
    
    try:
        # Get RI utilization data
        response = ce.get_reservation_utilization(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            GroupBy=[
                {
                    'Type': 'DIMENSION',
                    'Key': 'SERVICE'
                }
            ]
        )
        
        # Process utilization data
        utilization_data = []
        alerts = []
        
        for result in response['UtilizationsByTime']:
            for group in result['Groups']:
                service = group['Keys'][0]
                utilization = group['Attributes']['UtilizationPercentage']
                
                utilization_data.append({
                    'service': service,
                    'utilization_percentage': float(utilization),
                    'period': result['TimePeriod']['Start'],
                    'total_actual_hours': group['Attributes']['TotalActualHours'],
                    'unused_hours': group['Attributes']['UnusedHours']
                })
                
                # Check for low utilization (below 80%)
                if float(utilization) < 80:
                    alerts.append({
                        'service': service,
                        'utilization': utilization,
                        'type': 'LOW_UTILIZATION',
                        'message': f'Low RI utilization for {service}: {utilization}%'
                    })
        
        # Save report to S3
        report_key = f"ri-utilization-reports/{start_date.strftime('%Y-%m-%d')}.json"
        s3.put_object(
            Bucket=bucket_name,
            Key=report_key,
            Body=json.dumps({
                'report_date': end_date.strftime('%Y-%m-%d'),
                'period': f"{start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')}",
                'utilization_data': utilization_data,
                'alerts': alerts
            }, indent=2)
        )
        
        # Send alerts if any
        if alerts:
            message = f"RI Utilization Alert Report\n\n"
            for alert in alerts:
                message += f"- {alert['message']}\n"
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject="Reserved Instance Utilization Alert",
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'RI utilization analysis completed',
                'report_location': f"s3://{bucket_name}/{report_key}",
                'alerts_generated': len(alerts)
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create RI Recommendations Lambda
    cat > ri_recommendations.py << 'EOF'
import json
import boto3
import datetime
import os

def lambda_handler(event, context):
    ce = boto3.client('ce')
    s3 = boto3.client('s3')
    sns = boto3.client('sns')
    
    # Get environment variables
    bucket_name = os.environ['S3_BUCKET_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    try:
        # Get RI recommendations for EC2
        ec2_response = ce.get_reservation_purchase_recommendation(
            Service='Amazon Elastic Compute Cloud - Compute',
            LookbackPeriodInDays='SIXTY_DAYS',
            TermInYears='ONE_YEAR',
            PaymentOption='PARTIAL_UPFRONT'
        )
        
        # Get RI recommendations for RDS
        rds_response = ce.get_reservation_purchase_recommendation(
            Service='Amazon Relational Database Service',
            LookbackPeriodInDays='SIXTY_DAYS',
            TermInYears='ONE_YEAR',
            PaymentOption='PARTIAL_UPFRONT'
        )
        
        # Process recommendations
        recommendations = []
        total_estimated_savings = 0
        
        # Process EC2 recommendations
        for recommendation in ec2_response['Recommendations']:
            rec_data = {
                'service': 'EC2',
                'instance_type': recommendation['InstanceDetails']['EC2InstanceDetails']['InstanceType'],
                'region': recommendation['InstanceDetails']['EC2InstanceDetails']['Region'],
                'recommended_instances': recommendation['RecommendationDetails']['RecommendedNumberOfInstancesToPurchase'],
                'estimated_monthly_savings': float(recommendation['RecommendationDetails']['EstimatedMonthlySavingsAmount']),
                'estimated_monthly_on_demand_cost': float(recommendation['RecommendationDetails']['EstimatedMonthlyOnDemandCost']),
                'upfront_cost': float(recommendation['RecommendationDetails']['UpfrontCost']),
                'recurring_cost': float(recommendation['RecommendationDetails']['RecurringStandardMonthlyCost'])
            }
            recommendations.append(rec_data)
            total_estimated_savings += rec_data['estimated_monthly_savings']
        
        # Process RDS recommendations
        for recommendation in rds_response['Recommendations']:
            rec_data = {
                'service': 'RDS',
                'instance_type': recommendation['InstanceDetails']['RDSInstanceDetails']['InstanceType'],
                'database_engine': recommendation['InstanceDetails']['RDSInstanceDetails']['DatabaseEngine'],
                'region': recommendation['InstanceDetails']['RDSInstanceDetails']['Region'],
                'recommended_instances': recommendation['RecommendationDetails']['RecommendedNumberOfInstancesToPurchase'],
                'estimated_monthly_savings': float(recommendation['RecommendationDetails']['EstimatedMonthlySavingsAmount']),
                'estimated_monthly_on_demand_cost': float(recommendation['RecommendationDetails']['EstimatedMonthlyOnDemandCost']),
                'upfront_cost': float(recommendation['RecommendationDetails']['UpfrontCost']),
                'recurring_cost': float(recommendation['RecommendationDetails']['RecurringStandardMonthlyCost'])
            }
            recommendations.append(rec_data)
            total_estimated_savings += rec_data['estimated_monthly_savings']
        
        # Save recommendations to S3
        today = datetime.date.today()
        report_key = f"ri-recommendations/{today.strftime('%Y-%m-%d')}.json"
        
        report_data = {
            'report_date': today.strftime('%Y-%m-%d'),
            'total_recommendations': len(recommendations),
            'total_estimated_monthly_savings': total_estimated_savings,
            'recommendations': recommendations
        }
        
        s3.put_object(
            Bucket=bucket_name,
            Key=report_key,
            Body=json.dumps(report_data, indent=2)
        )
        
        # Send notification if there are recommendations
        if recommendations:
            message = f"RI Purchase Recommendations Report\n\n"
            message += f"Total Recommendations: {len(recommendations)}\n"
            message += f"Estimated Monthly Savings: ${total_estimated_savings:.2f}\n\n"
            
            for rec in recommendations[:5]:  # Show top 5
                message += f"- {rec['service']}: {rec['instance_type']} "
                message += f"(${rec['estimated_monthly_savings']:.2f}/month savings)\n"
            
            if len(recommendations) > 5:
                message += f"... and {len(recommendations) - 5} more recommendations\n"
            
            message += f"\nFull report: s3://{bucket_name}/{report_key}"
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject="Reserved Instance Purchase Recommendations",
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'RI recommendations analysis completed',
                'report_location': f"s3://{bucket_name}/{report_key}",
                'recommendations_count': len(recommendations),
                'estimated_savings': total_estimated_savings
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create RI Monitoring Lambda
    cat > ri_monitoring.py << 'EOF'
import json
import boto3
import datetime
import os

def lambda_handler(event, context):
    ce = boto3.client('ce')
    ec2 = boto3.client('ec2')
    dynamodb = boto3.resource('dynamodb')
    sns = boto3.client('sns')
    
    # Get environment variables
    table_name = os.environ['DYNAMODB_TABLE_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    table = dynamodb.Table(table_name)
    
    try:
        # Get EC2 Reserved Instances
        response = ec2.describe_reserved_instances(
            Filters=[
                {
                    'Name': 'state',
                    'Values': ['active']
                }
            ]
        )
        
        alerts = []
        current_time = datetime.datetime.utcnow()
        
        for ri in response['ReservedInstances']:
            ri_id = ri['ReservedInstancesId']
            end_date = ri['End']
            
            # Calculate days until expiration
            days_until_expiration = (end_date.replace(tzinfo=None) - current_time).days
            
            # Store RI data in DynamoDB
            table.put_item(
                Item={
                    'ReservationId': ri_id,
                    'Timestamp': int(current_time.timestamp()),
                    'InstanceType': ri['InstanceType'],
                    'InstanceCount': ri['InstanceCount'],
                    'State': ri['State'],
                    'Start': ri['Start'].isoformat(),
                    'End': ri['End'].isoformat(),
                    'Duration': ri['Duration'],
                    'OfferingClass': ri['OfferingClass'],
                    'OfferingType': ri['OfferingType'],
                    'DaysUntilExpiration': days_until_expiration,
                    'AvailabilityZone': ri.get('AvailabilityZone', 'N/A'),
                    'Region': ri['AvailabilityZone'][:-1] if ri.get('AvailabilityZone') else 'N/A'
                }
            )
            
            # Check for expiration alerts
            if days_until_expiration <= 90:  # 90 days warning
                alert_type = 'EXPIRING_SOON' if days_until_expiration > 30 else 'EXPIRING_VERY_SOON'
                alerts.append({
                    'reservation_id': ri_id,
                    'instance_type': ri['InstanceType'],
                    'instance_count': ri['InstanceCount'],
                    'days_until_expiration': days_until_expiration,
                    'end_date': ri['End'].strftime('%Y-%m-%d'),
                    'alert_type': alert_type
                })
        
        # Send alerts if any
        if alerts:
            message = f"Reserved Instance Expiration Alert\n\n"
            
            for alert in alerts:
                urgency = "URGENT" if alert['days_until_expiration'] <= 30 else "WARNING"
                message += f"[{urgency}] RI {alert['reservation_id']}\n"
                message += f"  Instance Type: {alert['instance_type']}\n"
                message += f"  Count: {alert['instance_count']}\n"
                message += f"  Expires: {alert['end_date']} ({alert['days_until_expiration']} days)\n\n"
            
            sns.publish(
                TopicArn=sns_topic_arn,
                Subject="Reserved Instance Expiration Alert",
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'RI monitoring completed',
                'total_reservations': len(response['ReservedInstances']),
                'expiration_alerts': len(alerts)
            })
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Create deployment packages and Lambda functions
    for func in "utilization" "recommendations" "monitoring"; do
        log "Creating ${func} Lambda function..."
        
        zip "ri-${func}-function.zip" "ri_${func}*.py"
        
        # Determine the correct environment variables for each function
        if [ "$func" = "monitoring" ]; then
            ENV_VARS="{DYNAMODB_TABLE_NAME=${DYNAMODB_TABLE_NAME},SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}"
        else
            ENV_VARS="{S3_BUCKET_NAME=${S3_BUCKET_NAME},SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}"
        fi
        
        aws lambda create-function \
            --function-name "${PROJECT_NAME}-ri-${func}" \
            --runtime python3.9 \
            --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role" \
            --handler "ri_${func}*.lambda_handler" \
            --zip-file "fileb://ri-${func}-function.zip" \
            --timeout 300 \
            --environment "Variables=${ENV_VARS}" \
            --tags "Project=${PROJECT_NAME}" \
            --region "${AWS_REGION}"
        
        success "${func} Lambda function created"
    done
    
    # Clean up function files
    rm -f ri_*.py *.zip
}

# Function to create EventBridge schedules
create_eventbridge_schedules() {
    log "Creating EventBridge schedules..."
    
    # Create EventBridge rule for daily RI utilization analysis
    aws events put-rule \
        --name "${PROJECT_NAME}-daily-utilization" \
        --schedule-expression "cron(0 8 * * ? *)" \
        --description "Daily RI utilization analysis at 8 AM UTC" \
        --state ENABLED \
        --region "${AWS_REGION}"
    
    # Add Lambda target to utilization rule
    aws events put-targets \
        --rule "${PROJECT_NAME}-daily-utilization" \
        --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-ri-utilization" \
        --region "${AWS_REGION}"
    
    # Create EventBridge rule for weekly RI recommendations
    aws events put-rule \
        --name "${PROJECT_NAME}-weekly-recommendations" \
        --schedule-expression "cron(0 9 ? * MON *)" \
        --description "Weekly RI recommendations on Monday at 9 AM UTC" \
        --state ENABLED \
        --region "${AWS_REGION}"
    
    # Add Lambda target to recommendations rule
    aws events put-targets \
        --rule "${PROJECT_NAME}-weekly-recommendations" \
        --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-ri-recommendations" \
        --region "${AWS_REGION}"
    
    # Create EventBridge rule for weekly RI monitoring
    aws events put-rule \
        --name "${PROJECT_NAME}-weekly-monitoring" \
        --schedule-expression "cron(0 10 ? * MON *)" \
        --description "Weekly RI monitoring on Monday at 10 AM UTC" \
        --state ENABLED \
        --region "${AWS_REGION}"
    
    # Add Lambda target to monitoring rule
    aws events put-targets \
        --rule "${PROJECT_NAME}-weekly-monitoring" \
        --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-ri-monitoring" \
        --region "${AWS_REGION}"
    
    success "EventBridge schedules created"
}

# Function to grant EventBridge permissions to Lambda
grant_eventbridge_permissions() {
    log "Granting EventBridge permissions to Lambda functions..."
    
    # Grant EventBridge permission to invoke utilization Lambda
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-ri-utilization" \
        --statement-id "AllowExecutionFromEventBridge" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${PROJECT_NAME}-daily-utilization" \
        --region "${AWS_REGION}"
    
    # Grant EventBridge permission to invoke recommendations Lambda
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-ri-recommendations" \
        --statement-id "AllowExecutionFromEventBridge" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${PROJECT_NAME}-weekly-recommendations" \
        --region "${AWS_REGION}"
    
    # Grant EventBridge permission to invoke monitoring Lambda
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-ri-monitoring" \
        --statement-id "AllowExecutionFromEventBridge" \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${PROJECT_NAME}-weekly-monitoring" \
        --region "${AWS_REGION}"
    
    success "EventBridge permissions granted"
}

# Function to test Lambda functions
test_lambda_functions() {
    log "Testing Lambda functions..."
    
    for func in "utilization" "recommendations" "monitoring"; do
        log "Testing ${func} function..."
        aws lambda invoke \
            --function-name "${PROJECT_NAME}-ri-${func}" \
            --payload '{}' \
            "${func}-test-response.json" \
            --region "${AWS_REGION}" >/dev/null
        
        if [ $? -eq 0 ]; then
            success "${func} function test completed"
        else
            warning "${func} function test failed - check logs"
        fi
    done
    
    # Clean up test files
    rm -f *-test-response.json
}

# Function to setup email subscription
setup_email_subscription() {
    log "Setting up email notifications..."
    
    read -p "Enter your email address for RI alerts (press Enter to skip): " EMAIL_ADDRESS
    
    if [ -n "$EMAIL_ADDRESS" ]; then
        aws sns subscribe \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --protocol email \
            --notification-endpoint "${EMAIL_ADDRESS}" \
            --region "${AWS_REGION}"
        
        success "Email subscription created. Please check your email and confirm the subscription."
    else
        warning "Email subscription skipped. You can subscribe later using:"
        warning "aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint YOUR_EMAIL"
    fi
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "======================================"
    echo "   DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "======================================"
    echo ""
    echo "Resources Created:"
    echo "  • S3 Bucket: ${S3_BUCKET_NAME}"
    echo "  • SNS Topic: ${SNS_TOPIC_ARN}"
    echo "  • DynamoDB Table: ${DYNAMODB_TABLE_NAME}"
    echo "  • IAM Role: ${PROJECT_NAME}-lambda-role"
    echo "  • Lambda Functions:"
    echo "    - ${PROJECT_NAME}-ri-utilization"
    echo "    - ${PROJECT_NAME}-ri-recommendations"
    echo "    - ${PROJECT_NAME}-ri-monitoring"
    echo "  • EventBridge Rules:"
    echo "    - ${PROJECT_NAME}-daily-utilization (8 AM UTC daily)"
    echo "    - ${PROJECT_NAME}-weekly-recommendations (9 AM UTC Monday)"
    echo "    - ${PROJECT_NAME}-weekly-monitoring (10 AM UTC Monday)"
    echo ""
    echo "Next Steps:"
    echo "  1. Confirm your email subscription for SNS notifications"
    echo "  2. Wait for the scheduled functions to run, or test manually"
    echo "  3. Monitor S3 bucket for generated reports"
    echo "  4. Review DynamoDB table for RI tracking data"
    echo ""
    echo "Estimated Monthly Cost: $15-25"
    echo ""
    echo "To clean up all resources, run: ./destroy.sh"
    echo ""
}

# Main deployment function
main() {
    echo "======================================"
    echo "  AWS RI Management Automation Setup"
    echo "======================================"
    echo ""
    
    validate_prerequisites
    setup_environment
    create_s3_bucket
    create_sns_topic
    create_dynamodb_table
    create_iam_role
    create_lambda_functions
    create_eventbridge_schedules
    grant_eventbridge_permissions
    test_lambda_functions
    setup_email_subscription
    display_summary
}

# Run main function
main "$@"