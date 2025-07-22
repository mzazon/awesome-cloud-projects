#!/bin/bash

# AWS Sustainability Dashboards Deployment Script
# Recipe: Carbon Footprint Analytics with QuickSight
# This script deploys the complete sustainability analytics infrastructure

set -e  # Exit on any error

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
    REPO_ROOT="${SCRIPT_DIR}/../../../.."
fi

# Configuration
DEPLOYMENT_LOG="${SCRIPT_DIR}/deployment.log"
RESOURCE_FILE="${SCRIPT_DIR}/deployed_resources.txt"

# Initialize deployment log
echo "=== AWS Sustainability Dashboards Deployment Started at $(date) ===" > "${DEPLOYMENT_LOG}"

log "Starting AWS Sustainability Dashboards deployment..."

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check required AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: ${AWS_CLI_VERSION}"
    
    # Check required permissions
    log "Verifying AWS permissions..."
    
    # Test basic permissions
    local permissions_test=true
    
    # Test S3 permissions
    if ! aws s3 ls &> /dev/null; then
        warning "S3 list permission may be limited"
        permissions_test=false
    fi
    
    # Test IAM permissions
    if ! aws iam get-user &> /dev/null && ! aws iam get-role --role-name NonExistentRole &> /dev/null; then
        warning "IAM permissions may be limited"
        permissions_test=false
    fi
    
    # Test Lambda permissions
    if ! aws lambda list-functions --max-items 1 &> /dev/null; then
        warning "Lambda permissions may be limited"
        permissions_test=false
    fi
    
    # Test Cost Explorer permissions
    if ! aws ce get-cost-categories --max-results 1 &> /dev/null; then
        warning "Cost Explorer permissions may be limited - this is required for sustainability data"
    fi
    
    if [ "$permissions_test" = false ]; then
        warning "Some permissions may be insufficient. Proceeding anyway..."
    fi
    
    success "Prerequisites check completed"
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
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export BUCKET_NAME="sustainability-analytics-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="sustainability-data-processor-${RANDOM_SUFFIX}"
    export ROLE_NAME="SustainabilityAnalyticsRole-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="sustainability-alerts-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_RULE_NAME="sustainability-data-collection-${RANDOM_SUFFIX}"
    
    # Store variables for cleanup
    cat > "${RESOURCE_FILE}" << EOF
# Deployed Resources - Generated on $(date)
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
BUCKET_NAME=${BUCKET_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
ROLE_NAME=${ROLE_NAME}
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
EVENTBRIDGE_RULE_NAME=${EVENTBRIDGE_RULE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log "Environment variables configured"
    log "Region: ${AWS_REGION}"
    log "Account ID: ${AWS_ACCOUNT_ID}"
    log "Resource suffix: ${RANDOM_SUFFIX}"
    
    # Log to deployment log
    echo "Environment setup completed at $(date)" >> "${DEPLOYMENT_LOG}"
    echo "AWS_REGION=${AWS_REGION}" >> "${DEPLOYMENT_LOG}"
    echo "AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}" >> "${DEPLOYMENT_LOG}"
    echo "RANDOM_SUFFIX=${RANDOM_SUFFIX}" >> "${DEPLOYMENT_LOG}"
}

# Create S3 bucket for sustainability data lake
create_s3_bucket() {
    log "Creating S3 bucket for sustainability data lake..."
    
    # Create bucket with appropriate region handling
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb s3://${BUCKET_NAME}
    else
        aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket ${BUCKET_NAME} \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Add bucket policy for enhanced security
    cat > bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyInsecureConnections",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket ${BUCKET_NAME} \
        --policy file://bucket-policy.json
    
    # Create folder structure
    aws s3api put-object --bucket ${BUCKET_NAME} --key sustainability-analytics/ --body /dev/null
    aws s3api put-object --bucket ${BUCKET_NAME} --key manifests/ --body /dev/null
    
    success "S3 bucket created: ${BUCKET_NAME}"
    echo "S3_BUCKET=${BUCKET_NAME}" >> "${DEPLOYMENT_LOG}"
}

# Create IAM role and policies
create_iam_resources() {
    log "Creating IAM role and policies..."
    
    # Create trust policy for Lambda
    cat > trust-policy.json << EOF
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
        --role-name ${ROLE_NAME} \
        --assume-role-policy-document file://trust-policy.json \
        --description "Role for AWS Sustainability Analytics Lambda function"
    
    # Attach managed policy for basic Lambda execution
    aws iam attach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for sustainability analytics
    cat > sustainability-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ce:GetCostAndUsage",
                "ce:GetUsageForecast",
                "ce:GetCostCategories",
                "ce:GetDimensionValues",
                "ce:GetRightsizingRecommendation",
                "cur:DescribeReportDefinitions",
                "cur:GetClassicReport"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "quicksight:CreateDataSet",
                "quicksight:UpdateDataSet",
                "quicksight:CreateDashboard",
                "quicksight:UpdateDashboard",
                "quicksight:DescribeDataSet"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create and attach custom policy
    aws iam create-policy \
        --policy-name SustainabilityAnalyticsPolicy-${RANDOM_SUFFIX} \
        --policy-document file://sustainability-policy.json \
        --description "Policy for accessing AWS sustainability and cost data"
    
    aws iam attach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/SustainabilityAnalyticsPolicy-${RANDOM_SUFFIX}
    
    # Wait for role to be available
    log "Waiting for IAM role propagation..."
    sleep 10
    
    success "IAM resources created: ${ROLE_NAME}"
    echo "IAM_ROLE=${ROLE_NAME}" >> "${DEPLOYMENT_LOG}"
    echo "IAM_POLICY=SustainabilityAnalyticsPolicy-${RANDOM_SUFFIX}" >> "${DEPLOYMENT_LOG}"
}

# Create Lambda function
create_lambda_function() {
    log "Creating Lambda function for data processing..."
    
    # Create Lambda function code
    cat > sustainability_processor.py << 'EOF'
import json
import boto3
import pandas as pd
from datetime import datetime, timedelta
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process sustainability and cost data to create integrated analytics.
    AWS Customer Carbon Footprint Tool data is retrieved monthly with a 3-month delay.
    This function correlates cost data with carbon footprint insights.
    """
    
    try:
        # Initialize AWS clients
        ce_client = boto3.client('ce')
        s3_client = boto3.client('s3')
        cloudwatch = boto3.client('cloudwatch')
        
        # Get environment variables
        bucket_name = event.get('bucket_name', os.environ.get('BUCKET_NAME'))
        
        # Calculate date range (last 6 months for comprehensive analysis)
        end_date = datetime.now()
        start_date = end_date - timedelta(days=180)
        
        logger.info(f"Processing sustainability data from {start_date.date()} to {end_date.date()}")
        
        # Fetch cost data from Cost Explorer
        cost_response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            Metrics=['UnblendedCost'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                {'Type': 'DIMENSION', 'Key': 'REGION'}
            ]
        )
        
        # Get cost optimization recommendations
        try:
            rightsizing_response = ce_client.get_rightsizing_recommendation(
                Service='AmazonEC2',
                Configuration={
                    'BenefitsConsidered': True,
                    'RecommendationTarget': 'CROSS_INSTANCE_FAMILY'
                }
            )
        except Exception as e:
            logger.warning(f"Could not fetch rightsizing recommendations: {e}")
            rightsizing_response = {'RightsizingRecommendations': []}
        
        # Process cost data for sustainability correlation
        processed_data = {
            'timestamp': datetime.now().isoformat(),
            'data_collection_metadata': {
                'aws_region': os.environ.get('AWS_REGION', 'unknown'),
                'processing_date': datetime.now().isoformat(),
                'analysis_period_days': 180,
                'data_source': 'AWS Cost Explorer API'
            },
            'cost_data': cost_response['ResultsByTime'],
            'optimization_recommendations': rightsizing_response,
            'sustainability_metrics': {
                'cost_optimization_opportunities': len(rightsizing_response.get('RightsizingRecommendations', [])),
                'total_services_analyzed': len(set([
                    group['Keys'][0] for result in cost_response['ResultsByTime']
                    for group in result.get('Groups', [])
                ])),
                'carbon_footprint_notes': 'AWS Customer Carbon Footprint Tool data available with 3-month delay via billing console'
            }
        }
        
        # Save processed data to S3 with date partitioning
        s3_key = f"sustainability-analytics/{datetime.now().strftime('%Y/%m/%d')}/processed_data_{datetime.now().strftime('%H%M%S')}.json"
        
        s3_client.put_object(
            Bucket=bucket_name,
            Key=s3_key,
            Body=json.dumps(processed_data, default=str, indent=2),
            ContentType='application/json',
            Metadata={
                'processing-date': datetime.now().isoformat(),
                'data-type': 'sustainability-analytics'
            }
        )
        
        # Send custom metric to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='SustainabilityAnalytics',
            MetricData=[
                {
                    'MetricName': 'DataProcessingSuccess',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'FunctionName',
                            'Value': context.function_name
                        }
                    ]
                }
            ]
        )
        
        logger.info(f"Successfully processed sustainability data and saved to {s3_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Sustainability data processed successfully',
                's3_location': f's3://{bucket_name}/{s3_key}',
                'metrics': processed_data['sustainability_metrics']
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing sustainability data: {str(e)}")
        
        # Send error metric to CloudWatch
        try:
            cloudwatch = boto3.client('cloudwatch')
            cloudwatch.put_metric_data(
                Namespace='SustainabilityAnalytics',
                MetricData=[
                    {
                        'MetricName': 'DataProcessingError',
                        'Value': 1,
                        'Unit': 'Count'
                    }
                ]
            )
        except Exception as cw_error:
            logger.error(f"Error sending CloudWatch metric: {str(cw_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Install pandas if not available (note: this is for local testing)
    if command -v pip &> /dev/null; then
        log "Installing pandas locally for Lambda package..."
        pip install pandas -t . 2>/dev/null || warning "Could not install pandas locally"
    fi
    
    # Package Lambda function
    zip -r function.zip sustainability_processor.py
    
    # Get role ARN
    ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} --query Role.Arn --output text)
    
    # Create Lambda function
    aws lambda create-function \
        --function-name ${FUNCTION_NAME} \
        --runtime python3.9 \
        --role ${ROLE_ARN} \
        --handler sustainability_processor.lambda_handler \
        --zip-file fileb://function.zip \
        --timeout 300 \
        --memory-size 512 \
        --environment Variables="{BUCKET_NAME=${BUCKET_NAME}}" \
        --description "Processes AWS sustainability and cost data for analytics"
    
    success "Lambda function created: ${FUNCTION_NAME}"
    echo "LAMBDA_FUNCTION=${FUNCTION_NAME}" >> "${DEPLOYMENT_LOG}"
}

# Create SNS topic for notifications
create_sns_topic() {
    log "Creating SNS topic for sustainability alerts..."
    
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name ${SNS_TOPIC_NAME} \
        --query TopicArn --output text)
    
    # Set topic attributes for better delivery
    aws sns set-topic-attributes \
        --topic-arn ${SNS_TOPIC_ARN} \
        --attribute-name DisplayName \
        --attribute-value "AWS Sustainability Alerts"
    
    log "SNS Topic created: ${SNS_TOPIC_ARN}"
    log "To receive email notifications, subscribe manually:"
    log "aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint your-email@example.com"
    
    success "SNS topic created: ${SNS_TOPIC_NAME}"
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> "${DEPLOYMENT_LOG}"
    
    # Export for use in other functions
    export SNS_TOPIC_ARN
}

# Configure EventBridge for automation
create_eventbridge_rule() {
    log "Creating EventBridge rule for automated data collection..."
    
    # Create EventBridge rule for monthly execution
    aws events put-rule \
        --name ${EVENTBRIDGE_RULE_NAME} \
        --schedule-expression "rate(30 days)" \
        --description "Monthly sustainability data collection and processing" \
        --state ENABLED
    
    # Add Lambda function as target
    aws events put-targets \
        --rule ${EVENTBRIDGE_RULE_NAME} \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${FUNCTION_NAME}","Input"="{\"bucket_name\":\"${BUCKET_NAME}\",\"trigger_source\":\"eventbridge\"}"
    
    # Grant EventBridge permission to invoke Lambda
    aws lambda add-permission \
        --function-name ${FUNCTION_NAME} \
        --statement-id "allow-eventbridge-${RANDOM_SUFFIX}" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}"
    
    success "EventBridge rule created: ${EVENTBRIDGE_RULE_NAME}"
    echo "EVENTBRIDGE_RULE=${EVENTBRIDGE_RULE_NAME}" >> "${DEPLOYMENT_LOG}"
}

# Create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms for monitoring..."
    
    # Create alarm for Lambda processing failures
    aws cloudwatch put-metric-alarm \
        --alarm-name "SustainabilityDataProcessingFailure-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when sustainability data processing fails" \
        --metric-name "Errors" \
        --namespace "AWS/Lambda" \
        --statistic "Sum" \
        --period 300 \
        --threshold 1 \
        --comparison-operator "GreaterThanOrEqualToThreshold" \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=FunctionName,Value=${FUNCTION_NAME}
    
    # Create custom alarm for sustainability data processing success
    aws cloudwatch put-metric-alarm \
        --alarm-name "SustainabilityDataProcessingSuccess-${RANDOM_SUFFIX}" \
        --alarm-description "Monitor successful sustainability data processing" \
        --metric-name "DataProcessingSuccess" \
        --namespace "SustainabilityAnalytics" \
        --statistic "Sum" \
        --period 86400 \
        --threshold 1 \
        --comparison-operator "LessThanThreshold" \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --treat-missing-data "breaching"
    
    success "CloudWatch alarms configured"
    echo "CLOUDWATCH_ALARMS_CREATED=true" >> "${DEPLOYMENT_LOG}"
}

# Create S3 manifest file for QuickSight
create_quicksight_manifest() {
    log "Creating S3 manifest file for QuickSight integration..."
    
    # Create manifest file for QuickSight data discovery
    cat > sustainability-manifest.json << EOF
{
    "fileLocations": [
        {
            "URIPrefixes": [
                "s3://${BUCKET_NAME}/sustainability-analytics/"
            ]
        }
    ],
    "globalUploadSettings": {
        "format": "JSON",
        "delimiter": ",",
        "textqualifier": "\"",
        "containsHeader": "true"
    }
}
EOF
    
    # Upload manifest to S3
    aws s3 cp sustainability-manifest.json \
        s3://${BUCKET_NAME}/manifests/sustainability-manifest.json \
        --metadata "purpose=quicksight-manifest,data-type=sustainability-analytics"
    
    success "QuickSight manifest file created and uploaded"
    echo "QUICKSIGHT_MANIFEST_CREATED=true" >> "${DEPLOYMENT_LOG}"
}

# Trigger initial data collection
trigger_initial_collection() {
    log "Triggering initial data collection..."
    
    # Trigger Lambda function manually
    aws lambda invoke \
        --function-name ${FUNCTION_NAME} \
        --payload "{\"bucket_name\":\"${BUCKET_NAME}\",\"trigger_source\":\"initial_setup\"}" \
        response.json
    
    # Check response
    if grep -q '"statusCode": 200' response.json; then
        success "Initial data collection completed successfully"
        
        # Show S3 objects
        log "Verifying data in S3..."
        aws s3 ls s3://${BUCKET_NAME}/sustainability-analytics/ --recursive
    else
        warning "Initial data collection may have encountered issues"
        log "Lambda response:"
        cat response.json
    fi
    
    echo "INITIAL_DATA_COLLECTION=completed" >> "${DEPLOYMENT_LOG}"
}

# Display deployment summary
display_summary() {
    log "=== Deployment Summary ==="
    echo
    success "AWS Sustainability Dashboards infrastructure deployed successfully!"
    echo
    echo "Resources created:"
    echo "• S3 Bucket: ${BUCKET_NAME}"
    echo "• Lambda Function: ${FUNCTION_NAME}"
    echo "• IAM Role: ${ROLE_NAME}"
    echo "• SNS Topic: ${SNS_TOPIC_NAME}"
    echo "• EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    echo "• CloudWatch Alarms: 2 alarms for monitoring"
    echo
    echo "Next Steps:"
    echo "1. Set up QuickSight account (if not already done):"
    echo "   https://${AWS_REGION}.quicksight.aws.amazon.com/"
    echo
    echo "2. Create QuickSight data source using:"
    echo "   S3 Manifest: s3://${BUCKET_NAME}/manifests/sustainability-manifest.json"
    echo
    echo "3. Build QuickSight dashboards with:"
    echo "   • Time series charts for cost trends"
    echo "   • Regional cost/carbon intensity comparisons"
    echo "   • Optimization recommendations visualization"
    echo
    echo "4. Subscribe to SNS notifications:"
    echo "   aws sns subscribe --topic-arn \$(aws sns list-topics --query 'Topics[?contains(TopicArn,\`${SNS_TOPIC_NAME}\`)].TopicArn' --output text) --protocol email --notification-endpoint your-email@example.com"
    echo
    echo "Resource details saved to: ${RESOURCE_FILE}"
    echo "Deployment log: ${DEPLOYMENT_LOG}"
    
    # Log final status
    echo "=== Deployment completed successfully at $(date) ===" >> "${DEPLOYMENT_LOG}"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f trust-policy.json sustainability-policy.json bucket-policy.json
    rm -f sustainability_processor.py function.zip
    rm -f sustainability-manifest.json response.json
    
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    echo
    log "=== AWS Sustainability Dashboards Deployment ==="
    echo
    
    # Check if running in dry-run mode
    if [[ "$1" == "--dry-run" ]]; then
        log "DRY RUN MODE - No resources will be created"
        warning "This is a dry run. No actual deployment will occur."
        return 0
    fi
    
    # Confirm deployment
    echo -e "${YELLOW}This will create AWS resources that may incur costs.${NC}"
    echo "Resources to be created:"
    echo "• S3 bucket for data storage"
    echo "• Lambda function for data processing"
    echo "• IAM role and policies"
    echo "• SNS topic for notifications"
    echo "• EventBridge rule for automation"
    echo "• CloudWatch alarms for monitoring"
    echo
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_iam_resources
    create_lambda_function
    create_sns_topic
    create_eventbridge_rule
    create_cloudwatch_alarms
    create_quicksight_manifest
    trigger_initial_collection
    cleanup_temp_files
    display_summary
    
    success "Deployment completed successfully!"
}

# Error handling
trap 'error "Deployment failed at line $LINENO. Check ${DEPLOYMENT_LOG} for details."; cleanup_temp_files; exit 1' ERR

# Run main function
main "$@"