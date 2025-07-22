#!/bin/bash

# Deploy script for Advanced Financial Analytics Dashboard with QuickSight and Cost Explorer
# This script automates the deployment of the complete financial analytics solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
RECIPE_NAME="advanced-financial-analytics-dashboard-quicksight-cost-explorer"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Success logging
log_success() {
    log "${GREEN}SUCCESS${NC}" "$*"
}

# Error logging
log_error() {
    log "${RED}ERROR${NC}" "$*"
}

# Warning logging
log_warning() {
    log "${YELLOW}WARNING${NC}" "$*"
}

# Info logging
log_info() {
    log "${BLUE}INFO${NC}" "$*"
}

# Error handler
error_handler() {
    local line_number=$1
    log_error "An error occurred on line ${line_number}. Exiting..."
    echo -e "\n${RED}Deployment failed! Check ${LOG_FILE} for details.${NC}"
    exit 1
}

trap 'error_handler ${LINENO}' ERR

# Display banner
display_banner() {
    echo -e "${BLUE}"
    echo "================================================================"
    echo "  AWS Financial Analytics Dashboard Deployment Script"
    echo "  Recipe: ${RECIPE_NAME}"
    echo "  Date: $(date)"
    echo "================================================================"
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
    log_info "AWS CLI version: ${aws_version}"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required tools
    local required_tools=("python3" "pip3" "zip" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" &> /dev/null; then
            log_error "Required tool '${tool}' is not installed."
            exit 1
        fi
    done
    
    # Check AWS permissions (basic check)
    log_info "Checking AWS permissions..."
    if ! aws iam get-user &> /dev/null && ! aws sts get-caller-identity &> /dev/null; then
        log_error "Unable to verify AWS identity. Please check your AWS credentials."
        exit 1
    fi
    
    log_success "All prerequisites check passed."
}

# Initialize environment variables
initialize_environment() {
    log_info "Initializing environment variables..."
    
    # Set region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "AWS region not set, defaulting to us-east-1"
    fi
    
    # Get account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 6))
    
    export ANALYTICS_BUCKET="financial-analytics-${random_suffix}"
    export RAW_DATA_BUCKET="cost-raw-data-${random_suffix}"
    export PROCESSED_DATA_BUCKET="cost-processed-data-${random_suffix}"
    export REPORTS_BUCKET="financial-reports-${random_suffix}"
    
    # Save environment variables for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
ANALYTICS_BUCKET=${ANALYTICS_BUCKET}
RAW_DATA_BUCKET=${RAW_DATA_BUCKET}
PROCESSED_DATA_BUCKET=${PROCESSED_DATA_BUCKET}
REPORTS_BUCKET=${REPORTS_BUCKET}
EOF
    
    log_success "Environment variables initialized."
    log_info "Region: ${AWS_REGION}"
    log_info "Account ID: ${AWS_ACCOUNT_ID}"
    log_info "Buckets: ${RAW_DATA_BUCKET}, ${PROCESSED_DATA_BUCKET}, ${REPORTS_BUCKET}, ${ANALYTICS_BUCKET}"
}

# Check Cost Explorer and QuickSight setup
check_services() {
    log_info "Checking Cost Explorer and QuickSight availability..."
    
    # Check Cost Explorer
    if ! aws ce get-cost-and-usage \
        --time-period Start=2025-01-01,End=2025-01-02 \
        --granularity DAILY \
        --metrics BlendedCost \
        --group-by Type=DIMENSION,Key=SERVICE &> /dev/null; then
        log_warning "Cost Explorer may not be enabled. Please enable it in the AWS Console."
        log_warning "Visit: https://console.aws.amazon.com/cost-management/home#/cost-explorer"
        read -p "Press Enter after enabling Cost Explorer to continue..."
    fi
    
    # Check QuickSight
    local qs_user=$(aws quicksight describe-user \
        --aws-account-id "${AWS_ACCOUNT_ID}" \
        --namespace default \
        --user-name "admin/${AWS_ACCOUNT_ID}" \
        --query 'User.UserName' --output text 2>/dev/null || echo "not-found")
    
    if [[ "${qs_user}" == "not-found" ]]; then
        log_warning "QuickSight is not set up. Please set it up manually:"
        log_warning "1. Go to https://quicksight.aws.amazon.com/"
        log_warning "2. Sign up for QuickSight (Enterprise Edition recommended)"
        log_warning "3. Configure permissions for S3, Athena, and Cost Explorer"
        read -p "Press Enter after QuickSight setup is complete..."
    fi
    
    log_success "Service availability checked."
}

# Create S3 buckets
create_s3_buckets() {
    log_info "Creating S3 buckets..."
    
    local buckets=("${RAW_DATA_BUCKET}" "${PROCESSED_DATA_BUCKET}" "${REPORTS_BUCKET}" "${ANALYTICS_BUCKET}")
    
    for bucket in "${buckets[@]}"; do
        # Check if bucket already exists
        if aws s3api head-bucket --bucket "${bucket}" 2>/dev/null; then
            log_warning "Bucket ${bucket} already exists, skipping creation."
            continue
        fi
        
        # Create bucket
        if [[ "${AWS_REGION}" == "us-east-1" ]]; then
            aws s3 mb "s3://${bucket}"
        else
            aws s3 mb "s3://${bucket}" --region "${AWS_REGION}"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "${bucket}" \
            --versioning-configuration Status=Enabled
        
        # Set up lifecycle policies
        aws s3api put-bucket-lifecycle-configuration \
            --bucket "${bucket}" \
            --lifecycle-configuration '{
                "Rules": [
                    {
                        "ID": "TransitionToIA",
                        "Status": "Enabled",
                        "Filter": {"Prefix": ""},
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
            }'
        
        log_success "Created bucket: ${bucket}"
    done
    
    log_success "All S3 buckets created successfully."
}

# Create IAM role and policies
create_iam_resources() {
    log_info "Creating IAM role and policies..."
    
    # Check if role already exists
    if aws iam get-role --role-name FinancialAnalyticsLambdaRole &>/dev/null; then
        log_warning "IAM role FinancialAnalyticsLambdaRole already exists, skipping creation."
        export LAMBDA_ANALYTICS_ROLE_ARN=$(aws iam get-role \
            --role-name FinancialAnalyticsLambdaRole \
            --query Role.Arn --output text)
        return
    fi
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/lambda-analytics-trust-policy.json" << 'EOF'
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
        --role-name FinancialAnalyticsLambdaRole \
        --assume-role-policy-document file://"${SCRIPT_DIR}/lambda-analytics-trust-policy.json"
    
    # Create comprehensive policy
    cat > "${SCRIPT_DIR}/lambda-analytics-policy.json" << EOF
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
                "ce:GetCostAndUsage",
                "ce:GetUsageReport",
                "ce:GetRightsizingRecommendation",
                "ce:GetReservationCoverage",
                "ce:GetReservationPurchaseRecommendation",
                "ce:GetReservationUtilization",
                "ce:GetSavingsPlansUtilization",
                "ce:GetDimensionValues",
                "ce:ListCostCategoryDefinitions"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "organizations:ListAccounts",
                "organizations:DescribeOrganization",
                "organizations:ListOrganizationalUnitsForParent",
                "organizations:ListParents"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${RAW_DATA_BUCKET}",
                "arn:aws:s3:::${RAW_DATA_BUCKET}/*",
                "arn:aws:s3:::${PROCESSED_DATA_BUCKET}",
                "arn:aws:s3:::${PROCESSED_DATA_BUCKET}/*",
                "arn:aws:s3:::${REPORTS_BUCKET}",
                "arn:aws:s3:::${REPORTS_BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "glue:CreateTable",
                "glue:UpdateTable",
                "glue:GetTable",
                "glue:GetDatabase",
                "glue:CreateDatabase",
                "glue:CreatePartition"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "quicksight:CreateDataSet",
                "quicksight:UpdateDataSet",
                "quicksight:DescribeDataSet",
                "quicksight:CreateAnalysis",
                "quicksight:UpdateAnalysis"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create and attach policy
    aws iam create-policy \
        --policy-name FinancialAnalyticsPolicy \
        --policy-document file://"${SCRIPT_DIR}/lambda-analytics-policy.json"
    
    aws iam attach-role-policy \
        --role-name FinancialAnalyticsLambdaRole \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/FinancialAnalyticsPolicy"
    
    # Get role ARN
    export LAMBDA_ANALYTICS_ROLE_ARN=$(aws iam get-role \
        --role-name FinancialAnalyticsLambdaRole \
        --query Role.Arn --output text)
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
    
    log_success "IAM resources created successfully."
}

# Deploy Lambda functions
deploy_lambda_functions() {
    log_info "Deploying Lambda functions..."
    
    # Create temporary directory for Lambda packages
    local temp_dir=$(mktemp -d)
    cd "${temp_dir}"
    
    # Create cost data collector Lambda function
    cat > cost_data_collector.py << 'EOF'
import json
import boto3
import logging
import os
from datetime import datetime, timedelta, date
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    ce = boto3.client('ce')
    s3 = boto3.client('s3')
    
    # Calculate date ranges for data collection
    end_date = date.today()
    start_date = end_date - timedelta(days=90)  # Last 90 days
    
    try:
        # 1. Daily cost by service
        daily_cost_response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UnblendedCost', 'UsageQuantity'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                {'Type': 'DIMENSION', 'Key': 'LINKED_ACCOUNT'}
            ]
        )
        
        # 2. Monthly cost by department (tag-based)
        monthly_dept_response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': (start_date.replace(day=1)).strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {'Type': 'TAG', 'Key': 'Department'},
                {'Type': 'TAG', 'Key': 'Project'},
                {'Type': 'TAG', 'Key': 'Environment'}
            ]
        )
        
        # 3. Reserved Instance utilization
        ri_utilization_response = ce.get_reservation_utilization(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY'
        )
        
        # 4. Savings Plans utilization
        savings_plans_response = ce.get_savings_plans_utilization(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY'
        )
        
        # 5. Rightsizing recommendations
        rightsizing_response = ce.get_rightsizing_recommendation(
            Service='AmazonEC2'
        )
        
        # Store all collected data
        collections = {
            'daily_costs': daily_cost_response,
            'monthly_department_costs': monthly_dept_response,
            'ri_utilization': ri_utilization_response,
            'savings_plans_utilization': savings_plans_response,
            'rightsizing_recommendations': rightsizing_response,
            'collection_timestamp': datetime.utcnow().isoformat(),
            'data_period': {
                'start_date': start_date.strftime('%Y-%m-%d'),
                'end_date': end_date.strftime('%Y-%m-%d')
            }
        }
        
        # Generate unique key for this collection
        collection_id = str(uuid.uuid4())
        s3_key = f"raw-cost-data/{datetime.utcnow().strftime('%Y/%m/%d')}/cost-collection-{collection_id}.json"
        
        # Store in S3
        s3.put_object(
            Bucket=os.environ['RAW_DATA_BUCKET'],
            Key=s3_key,
            Body=json.dumps(collections, default=str, indent=2),
            ContentType='application/json',
            Metadata={
                'collection-date': datetime.utcnow().strftime('%Y-%m-%d'),
                'data-type': 'cost-explorer-raw',
                'collection-id': collection_id
            }
        )
        
        logger.info(f"Cost data collected and stored: s3://{os.environ['RAW_DATA_BUCKET']}/{s3_key}")
        
        # Prepare summary for downstream processing
        summary = {
            'total_daily_records': len(daily_cost_response.get('ResultsByTime', [])),
            'total_monthly_records': len(monthly_dept_response.get('ResultsByTime', [])),
            'ri_utilization_periods': len(ri_utilization_response.get('UtilizationsByTime', [])),
            'rightsizing_recommendations': len(rightsizing_response.get('RightsizingRecommendations', [])),
            's3_location': f"s3://{os.environ['RAW_DATA_BUCKET']}/{s3_key}",
            'collection_id': collection_id
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost data collection completed successfully',
                'summary': summary
            })
        }
        
    except Exception as e:
        logger.error(f"Error collecting cost data: {str(e)}")
        raise
EOF
    
    # Package cost data collector
    zip cost-data-collector.zip cost_data_collector.py
    
    # Deploy cost data collector
    if ! aws lambda get-function --function-name "CostDataCollector" &>/dev/null; then
        export COST_COLLECTOR_ARN=$(aws lambda create-function \
            --function-name "CostDataCollector" \
            --runtime python3.9 \
            --role "${LAMBDA_ANALYTICS_ROLE_ARN}" \
            --handler cost_data_collector.lambda_handler \
            --zip-file fileb://cost-data-collector.zip \
            --environment Variables="{RAW_DATA_BUCKET=${RAW_DATA_BUCKET}}" \
            --timeout 900 \
            --memory-size 1024 \
            --query FunctionArn --output text)
        log_success "Created CostDataCollector Lambda function."
    else
        log_warning "CostDataCollector Lambda function already exists, updating..."
        aws lambda update-function-code \
            --function-name "CostDataCollector" \
            --zip-file fileb://cost-data-collector.zip
        export COST_COLLECTOR_ARN=$(aws lambda get-function \
            --function-name "CostDataCollector" \
            --query Configuration.FunctionArn --output text)
    fi
    
    # Create data transformer Lambda function (simplified version for deployment)
    cat > data_transformer.py << 'EOF'
import json
import boto3
import logging
import os
from datetime import datetime
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    glue = boto3.client('glue')
    
    try:
        # Get the latest raw data file from S3
        raw_bucket = os.environ['RAW_DATA_BUCKET']
        processed_bucket = os.environ['PROCESSED_DATA_BUCKET']
        
        # List objects to find latest collection
        response = s3.list_objects_v2(
            Bucket=raw_bucket,
            Prefix='raw-cost-data/',
            MaxKeys=1000
        )
        
        if 'Contents' not in response:
            logger.info("No raw data files found")
            return {'statusCode': 200, 'body': 'No data to process'}
        
        # Sort by last modified and get the latest
        latest_file = sorted(response['Contents'], key=lambda x: x['LastModified'], reverse=True)[0]
        latest_key = latest_file['Key']
        
        logger.info(f"Processing latest file: {latest_key}")
        
        # Read raw data from S3
        obj = s3.get_object(Bucket=raw_bucket, Key=latest_key)
        raw_data = json.loads(obj['Body'].read())
        
        # Transform data for analytics (simplified)
        transformed_data = transform_cost_data(raw_data)
        
        # Store transformed data
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        
        for data_type, data in transformed_data.items():
            json_key = f"processed-data/{data_type}/{datetime.utcnow().strftime('%Y/%m/%d')}/{data_type}_{timestamp}.json"
            
            s3.put_object(
                Bucket=processed_bucket,
                Key=json_key,
                Body=json.dumps(data, default=str, indent=2),
                ContentType='application/json'
            )
        
        logger.info("Data transformation completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data transformation completed',
                'processed_files': list(transformed_data.keys()),
                'output_bucket': processed_bucket
            })
        }
        
    except Exception as e:
        logger.error(f"Error in data transformation: {str(e)}")
        raise

def transform_cost_data(raw_data):
    """Transform raw cost explorer data into analytics-friendly format"""
    transformed = {}
    
    # Transform daily costs
    if 'daily_costs' in raw_data:
        daily_costs = []
        for time_period in raw_data['daily_costs'].get('ResultsByTime', []):
            date = time_period['TimePeriod']['Start']
            
            for group in time_period.get('Groups', []):
                service = group['Keys'][0] if len(group['Keys']) > 0 else 'Unknown'
                account = group['Keys'][1] if len(group['Keys']) > 1 else 'Unknown'
                
                daily_costs.append({
                    'date': date,
                    'service': service,
                    'account_id': account,
                    'blended_cost': float(group['Metrics']['BlendedCost']['Amount']),
                    'unblended_cost': float(group['Metrics']['UnblendedCost']['Amount']),
                    'usage_quantity': float(group['Metrics']['UsageQuantity']['Amount']),
                    'currency': group['Metrics']['BlendedCost']['Unit']
                })
        
        transformed['daily_costs'] = daily_costs
    
    return transformed
EOF
    
    # Package data transformer
    zip data-transformer.zip data_transformer.py
    
    # Deploy data transformer
    if ! aws lambda get-function --function-name "DataTransformer" &>/dev/null; then
        export DATA_TRANSFORMER_ARN=$(aws lambda create-function \
            --function-name "DataTransformer" \
            --runtime python3.9 \
            --role "${LAMBDA_ANALYTICS_ROLE_ARN}" \
            --handler data_transformer.lambda_handler \
            --zip-file fileb://data-transformer.zip \
            --environment Variables="{RAW_DATA_BUCKET=${RAW_DATA_BUCKET},PROCESSED_DATA_BUCKET=${PROCESSED_DATA_BUCKET}}" \
            --timeout 900 \
            --memory-size 1024 \
            --query FunctionArn --output text)
        log_success "Created DataTransformer Lambda function."
    else
        log_warning "DataTransformer Lambda function already exists, updating..."
        aws lambda update-function-code \
            --function-name "DataTransformer" \
            --zip-file fileb://data-transformer.zip
        export DATA_TRANSFORMER_ARN=$(aws lambda get-function \
            --function-name "DataTransformer" \
            --query Configuration.FunctionArn --output text)
    fi
    
    # Clean up temporary directory
    cd "${SCRIPT_DIR}"
    rm -rf "${temp_dir}"
    
    # Save function ARNs
    echo "COST_COLLECTOR_ARN=${COST_COLLECTOR_ARN}" >> "${SCRIPT_DIR}/.env"
    echo "DATA_TRANSFORMER_ARN=${DATA_TRANSFORMER_ARN}" >> "${SCRIPT_DIR}/.env"
    
    log_success "Lambda functions deployed successfully."
}

# Create EventBridge schedules
create_eventbridge_schedules() {
    log_info "Creating EventBridge schedules..."
    
    # Create daily cost data collection schedule
    if ! aws events describe-rule --name "DailyCostDataCollection" &>/dev/null; then
        aws events put-rule \
            --name "DailyCostDataCollection" \
            --description "Daily collection of cost data for analytics" \
            --schedule-expression "cron(0 6 * * ? *)"
        log_success "Created DailyCostDataCollection rule."
    else
        log_warning "DailyCostDataCollection rule already exists."
    fi
    
    # Create weekly data transformation schedule
    if ! aws events describe-rule --name "WeeklyDataTransformation" &>/dev/null; then
        aws events put-rule \
            --name "WeeklyDataTransformation" \
            --description "Weekly transformation of cost data" \
            --schedule-expression "cron(0 7 ? * SUN *)"
        log_success "Created WeeklyDataTransformation rule."
    else
        log_warning "WeeklyDataTransformation rule already exists."
    fi
    
    # Add Lambda targets
    aws events put-targets \
        --rule "DailyCostDataCollection" \
        --targets "[{\"Id\": \"1\", \"Arn\": \"${COST_COLLECTOR_ARN}\", \"Input\": \"{\\\"source\\\": \\\"scheduled-daily\\\"}\"}]"
    
    aws events put-targets \
        --rule "WeeklyDataTransformation" \
        --targets "[{\"Id\": \"1\", \"Arn\": \"${DATA_TRANSFORMER_ARN}\", \"Input\": \"{\\\"source\\\": \\\"scheduled-weekly\\\"}\"}]"
    
    # Grant EventBridge permissions
    aws lambda add-permission \
        --function-name "CostDataCollector" \
        --statement-id "AllowDailyEventBridge" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/DailyCostDataCollection" \
        2>/dev/null || log_warning "Permission may already exist for CostDataCollector"
    
    aws lambda add-permission \
        --function-name "DataTransformer" \
        --statement-id "AllowWeeklyEventBridge" \
        --action "lambda:InvokeFunction" \
        --principal "events.amazonaws.com" \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/WeeklyDataTransformation" \
        2>/dev/null || log_warning "Permission may already exist for DataTransformer"
    
    log_success "EventBridge schedules configured successfully."
}

# Set up Athena
setup_athena() {
    log_info "Setting up Athena workgroup and database..."
    
    # Create Athena workgroup
    if ! aws athena get-work-group --work-group "FinancialAnalytics" &>/dev/null; then
        aws athena create-work-group \
            --name "FinancialAnalytics" \
            --description "Workgroup for financial analytics queries" \
            --configuration "{
                \"ResultConfiguration\": {
                    \"OutputLocation\": \"s3://${ANALYTICS_BUCKET}/athena-results/\"
                },
                \"EnforceWorkGroupConfiguration\": true,
                \"PublishCloudWatchMetrics\": true
            }"
        log_success "Created Athena workgroup: FinancialAnalytics"
    else
        log_warning "Athena workgroup FinancialAnalytics already exists."
    fi
    
    log_success "Athena setup completed."
}

# Run initial data collection
run_initial_collection() {
    log_info "Running initial data collection..."
    
    # Manually trigger initial data collection
    local response=$(aws lambda invoke \
        --function-name "CostDataCollector" \
        --payload '{"source": "manual-initial"}' \
        --cli-binary-format raw-in-base64-out \
        "${SCRIPT_DIR}/collection-response.json")
    
    if [[ $? -eq 0 ]]; then
        log_success "Initial data collection completed."
        log_info "Collection response: $(cat ${SCRIPT_DIR}/collection-response.json)"
    else
        log_warning "Initial data collection may have failed. Check Lambda logs."
    fi
    
    # Wait and trigger transformation
    log_info "Waiting 30 seconds before data transformation..."
    sleep 30
    
    local transform_response=$(aws lambda invoke \
        --function-name "DataTransformer" \
        --payload '{"source": "manual-initial"}' \
        --cli-binary-format raw-in-base64-out \
        "${SCRIPT_DIR}/transformation-response.json")
    
    if [[ $? -eq 0 ]]; then
        log_success "Initial data transformation completed."
        log_info "Transformation response: $(cat ${SCRIPT_DIR}/transformation-response.json)"
    else
        log_warning "Initial data transformation may have failed. Check Lambda logs."
    fi
}

# Display next steps
display_next_steps() {
    echo -e "\n${GREEN}================================================================"
    echo "  DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "================================================================${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo "1. Set up QuickSight data sources and datasets:"
    echo "   - Go to https://quicksight.aws.amazon.com/"
    echo "   - Create data sources for S3 and Athena"
    echo "   - Build interactive dashboards"
    echo ""
    echo "2. Verify data collection:"
    echo "   - Check S3 buckets for raw and processed data"
    echo "   - Review Lambda function logs in CloudWatch"
    echo ""
    echo "3. Customize and extend:"
    echo "   - Add custom metrics and KPIs"
    echo "   - Set up additional cost allocation tags"
    echo "   - Configure alerting and notifications"
    echo ""
    echo -e "${YELLOW}Important Files:${NC}"
    echo "- Environment file: ${SCRIPT_DIR}/.env"
    echo "- Deployment log: ${LOG_FILE}"
    echo "- Cleanup script: ${SCRIPT_DIR}/destroy.sh"
    echo ""
    echo -e "${YELLOW}Estimated Monthly Cost: $200-400${NC}"
    echo "- QuickSight: $18/user/month (Enterprise)"
    echo "- S3 Storage: $20-50/month"
    echo "- Lambda: $10-30/month"
    echo "- Athena: $5-20/month"
    echo ""
}

# Main deployment function
main() {
    display_banner
    
    # Start timing
    local start_time=$(date +%s)
    
    # Initialize log file
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    
    # Execute deployment steps
    check_prerequisites
    initialize_environment
    check_services
    create_s3_buckets
    create_iam_resources
    deploy_lambda_functions
    create_eventbridge_schedules
    setup_athena
    run_initial_collection
    
    # Calculate deployment time
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success "Deployment completed in ${duration} seconds."
    
    display_next_steps
}

# Cleanup function for interrupted deployment
cleanup_on_interrupt() {
    log_warning "Deployment interrupted. Cleaning up partial resources..."
    echo "Run ./destroy.sh to clean up any created resources."
    exit 1
}

# Set up interrupt handler
trap cleanup_on_interrupt SIGINT SIGTERM

# Run main deployment
main "$@"