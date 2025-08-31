#!/bin/bash

# Interactive Data Analytics with Bedrock AgentCore Code Interpreter - Deployment Script
# This script deploys the complete infrastructure for interactive data analytics using AWS Bedrock
# AgentCore Code Interpreter, S3, Lambda, CloudWatch, and API Gateway.

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false
FORCE_DEPLOY=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" >&2
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        DEBUG)
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
                echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
            fi
            ;;
    esac
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Interactive Data Analytics with Bedrock AgentCore Code Interpreter

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without making changes
    -f, --force         Force deployment even if resources exist
    --region REGION     AWS region (default: from AWS CLI config)
    --suffix SUFFIX     Custom suffix for resource names
    --debug             Enable debug logging

EXAMPLES:
    $0                                  # Deploy with auto-generated suffix
    $0 --dry-run                       # Preview deployment
    $0 --region us-west-2              # Deploy to specific region
    $0 --suffix prod --force           # Force deployment with custom suffix

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_DEPLOY=true
                shift
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            --suffix)
                CUSTOM_SUFFIX="$2"
                shift 2
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            *)
                log ERROR "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log ERROR "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log DEBUG "AWS CLI version: $aws_version"
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log ERROR "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log ERROR "AWS credentials not configured or invalid. Please run 'aws configure'."
        exit 1
    fi
    
    # Check Bedrock service availability
    if ! aws bedrock list-foundation-models &> /dev/null; then
        log WARN "Bedrock service access verification failed. Ensure your account has Bedrock access."
    fi
    
    log INFO "Prerequisites check completed successfully"
}

# Set environment variables
setup_environment() {
    log INFO "Setting up environment variables..."
    
    # Set AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            log WARN "No region configured, defaulting to us-east-1"
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate or use custom suffix
    if [[ -n "${CUSTOM_SUFFIX:-}" ]]; then
        RANDOM_SUFFIX="$CUSTOM_SUFFIX"
    else
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            openssl rand -hex 3)
    fi
    
    # Set resource names
    export BUCKET_RAW_DATA="analytics-raw-data-${RANDOM_SUFFIX}"
    export BUCKET_RESULTS="analytics-results-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="analytics-orchestrator-${RANDOM_SUFFIX}"
    export CODE_INTERPRETER_NAME="analytics-interpreter-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="analytics-execution-role-${RANDOM_SUFFIX}"
    export API_GATEWAY_NAME="analytics-api-${RANDOM_SUFFIX}"
    export DLQ_NAME="analytics-dlq-${RANDOM_SUFFIX}"
    
    log INFO "Environment configured for region: $AWS_REGION"
    log INFO "Using resource suffix: $RANDOM_SUFFIX"
    log DEBUG "Account ID: $AWS_ACCOUNT_ID"
}

# Check if resources already exist
check_existing_resources() {
    log INFO "Checking for existing resources..."
    
    local resources_exist=false
    
    # Check S3 buckets
    if aws s3 ls "s3://$BUCKET_RAW_DATA" &> /dev/null; then
        log WARN "S3 bucket $BUCKET_RAW_DATA already exists"
        resources_exist=true
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        log WARN "Lambda function $LAMBDA_FUNCTION_NAME already exists"
        resources_exist=true
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        log WARN "IAM role $IAM_ROLE_NAME already exists"
        resources_exist=true
    fi
    
    if [[ "$resources_exist" == "true" && "$FORCE_DEPLOY" != "true" ]]; then
        log ERROR "Resources already exist. Use --force to override or choose a different suffix."
        exit 1
    fi
}

# Create IAM role and policies
create_iam_resources() {
    log INFO "Creating IAM role and policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create IAM role: $IAM_ROLE_NAME"
        return 0
    fi
    
    # Create IAM role
    aws iam create-role \
        --role-name "$IAM_ROLE_NAME" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": ["bedrock.amazonaws.com", "lambda.amazonaws.com"]
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }' > /dev/null
    
    # Attach managed policies
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
    
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess
    
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy
    cat > /tmp/analytics_policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream",
                "bedrock-agentcore:*"
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
                "arn:aws:s3:::${BUCKET_RAW_DATA}",
                "arn:aws:s3:::${BUCKET_RAW_DATA}/*",
                "arn:aws:s3:::${BUCKET_RESULTS}",
                "arn:aws:s3:::${BUCKET_RESULTS}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sqs:SendMessage",
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage"
            ],
            "Resource": "arn:aws:sqs:${AWS_REGION}:${AWS_ACCOUNT_ID}:${DLQ_NAME}"
        }
    ]
}
EOF
    
    aws iam create-policy \
        --policy-name "AnalyticsEnhancedPolicy-${RANDOM_SUFFIX}" \
        --policy-document file:///tmp/analytics_policy.json > /dev/null
    
    aws iam attach-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AnalyticsEnhancedPolicy-${RANDOM_SUFFIX}"
    
    # Wait for role propagation
    log INFO "Waiting for IAM role propagation..."
    sleep 10
    
    log INFO "IAM resources created successfully"
}

# Create S3 buckets
create_s3_buckets() {
    log INFO "Creating S3 buckets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create S3 buckets: $BUCKET_RAW_DATA, $BUCKET_RESULTS"
        return 0
    fi
    
    # Create buckets
    aws s3 mb "s3://$BUCKET_RAW_DATA" --region "$AWS_REGION"
    aws s3 mb "s3://$BUCKET_RESULTS" --region "$AWS_REGION"
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_RAW_DATA" \
        --versioning-configuration Status=Enabled
    
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_RESULTS" \
        --versioning-configuration Status=Enabled
    
    # Configure encryption
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_RAW_DATA" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_RESULTS" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Upload sample data
    upload_sample_data
    
    log INFO "S3 buckets created and configured"
}

# Upload sample data
upload_sample_data() {
    log INFO "Uploading sample datasets..."
    
    # Create sample sales data
    cat > /tmp/sample_sales_data.csv << EOF
date,product,region,sales_amount,quantity,customer_segment
2024-01-01,Widget A,North,1250.50,25,Enterprise
2024-01-02,Widget B,South,890.75,18,SMB
2024-01-03,Widget A,East,2150.25,43,Enterprise
2024-01-04,Widget C,West,567.30,12,Startup
2024-01-05,Widget B,North,1875.60,38,Enterprise
2024-01-06,Widget A,South,1320.45,26,SMB
2024-01-07,Widget C,East,745.20,15,Startup
2024-01-08,Widget B,West,2340.80,47,Enterprise
2024-01-09,Widget A,North,998.15,20,SMB
2024-01-10,Widget C,South,1456.70,29,Enterprise
EOF
    
    # Create sample customer data
    cat > /tmp/sample_customer_data.json << EOF
[
  {"customer_id": "C001", "name": "TechCorp", "segment": "Enterprise", "annual_value": 150000},
  {"customer_id": "C002", "name": "StartupXYZ", "segment": "Startup", "annual_value": 25000},
  {"customer_id": "C003", "name": "MidSize Inc", "segment": "SMB", "annual_value": 75000}
]
EOF
    
    # Upload to S3
    aws s3 cp /tmp/sample_sales_data.csv "s3://$BUCKET_RAW_DATA/datasets/"
    aws s3 cp /tmp/sample_customer_data.json "s3://$BUCKET_RAW_DATA/datasets/"
    
    log INFO "Sample datasets uploaded successfully"
}

# Create Bedrock Code Interpreter
create_code_interpreter() {
    log INFO "Creating Bedrock AgentCore Code Interpreter..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create Code Interpreter: $CODE_INTERPRETER_NAME"
        export CODE_INTERPRETER_ID="dry-run-interpreter-id"
        return 0
    fi
    
    local execution_role_arn=$(aws iam get-role \
        --role-name "$IAM_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    local response=$(aws bedrock-agentcore create-code-interpreter \
        --region "$AWS_REGION" \
        --name "$CODE_INTERPRETER_NAME" \
        --description "Interactive data analytics interpreter for processing S3 datasets" \
        --network-configuration '{
            "networkMode": "PUBLIC"
        }' \
        --execution-role-arn "$execution_role_arn")
    
    export CODE_INTERPRETER_ID=$(echo "$response" | jq -r '.codeInterpreterIdentifier')
    
    log INFO "Code Interpreter created: $CODE_INTERPRETER_ID"
}

# Create SQS Dead Letter Queue
create_sqs_dlq() {
    log INFO "Creating SQS Dead Letter Queue..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create SQS DLQ: $DLQ_NAME"
        return 0
    fi
    
    aws sqs create-queue \
        --queue-name "$DLQ_NAME" \
        --attributes VisibilityTimeoutSeconds=300 > /dev/null
    
    log INFO "SQS Dead Letter Queue created: $DLQ_NAME"
}

# Create Lambda function
create_lambda_function() {
    log INFO "Creating Lambda function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi
    
    local execution_role_arn=$(aws iam get-role \
        --role-name "$IAM_ROLE_NAME" \
        --query 'Role.Arn' --output text)
    
    # Create Lambda function code
    cat > /tmp/lambda_function.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    # Initialize AWS clients
    bedrock = boto3.client('bedrock-agentcore')
    s3 = boto3.client('s3')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Extract query from event
        user_query = event.get('query', 'Analyze the sales data and provide insights')
        
        # Start a Code Interpreter session
        session_response = bedrock.start_code_interpreter_session(
            codeInterpreterIdentifier=os.environ['CODE_INTERPRETER_ID'],
            name=f"analytics-session-{int(datetime.now().timestamp())}",
            sessionTimeoutSeconds=3600
        )
        
        session_id = session_response['sessionId']
        
        # Prepare Python code for data analysis
        analysis_code = f"""
import pandas as pd
import boto3
import matplotlib.pyplot as plt
import seaborn as sns

# Initialize S3 client
s3 = boto3.client('s3')

# Download sales data from S3
s3.download_file('{os.environ['BUCKET_RAW_DATA']}', 'datasets/sample_sales_data.csv', 'sales_data.csv')
s3.download_file('{os.environ['BUCKET_RAW_DATA']}', 'datasets/sample_customer_data.json', 'customer_data.json')

# Load and analyze data based on user query: {user_query}
sales_df = pd.read_csv('sales_data.csv')

print("Data Analysis Results:")
print(f"Total sales amount: ${sales_df['sales_amount'].sum():.2f}")
print(f"Average sales per transaction: ${sales_df['sales_amount'].mean():.2f}")
print("\\nSales by region:")
print(sales_df.groupby('region')['sales_amount'].sum().sort_values(ascending=False))
print("\\nTop performing products:")
print(sales_df.groupby('product')['sales_amount'].sum().sort_values(ascending=False))

# Create visualization
plt.figure(figsize=(10, 6))
sales_by_region = sales_df.groupby('region')['sales_amount'].sum()
sales_by_region.plot(kind='bar')
plt.title('Sales Amount by Region')
plt.ylabel('Sales Amount ($)')
plt.xticks(rotation=45)
plt.tight_layout()
plt.savefig('sales_analysis.png')

# Upload results to S3
s3.upload_file('sales_analysis.png', '{os.environ['BUCKET_RESULTS']}', 'analysis_results/sales_analysis.png')

print("Analysis complete. Results saved to S3.")
        """
        
        # Execute code through Bedrock AgentCore
        execution_response = bedrock.invoke_code_interpreter(
            codeInterpreterIdentifier=os.environ['CODE_INTERPRETER_ID'],
            sessionId=session_id,
            name="executeAnalysis",
            arguments={
                "language": "python",
                "code": analysis_code
            }
        )
        
        # Process the response stream
        results = []
        for event in execution_response.get('stream', []):
            if 'result' in event:
                result = event['result']
                if 'content' in result:
                    for content_item in result['content']:
                        if content_item['type'] == 'text':
                            results.append(content_item['text'])
        
        # Log execution metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='Analytics/CodeInterpreter',
            MetricData=[
                {
                    'MetricName': 'ExecutionCount',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Analysis completed successfully',
                'session_id': session_id,
                'results': results,
                'results_bucket': os.environ['BUCKET_RESULTS']
            })
        }
        
    except Exception as e:
        # Log error metrics
        cloudwatch.put_metric_data(
            Namespace='Analytics/CodeInterpreter',
            MetricData=[
                {
                    'MetricName': 'ExecutionErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Analysis failed'
            })
        }
EOF
    
    # Package Lambda function
    cd /tmp && zip lambda_function.zip lambda_function.py
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --runtime python3.11 \
        --role "$execution_role_arn" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://lambda_function.zip \
        --timeout 300 \
        --memory-size 512 \
        --environment Variables="{
            CODE_INTERPRETER_ID=${CODE_INTERPRETER_ID},
            BUCKET_RAW_DATA=${BUCKET_RAW_DATA},
            BUCKET_RESULTS=${BUCKET_RESULTS}
        }" > /dev/null
    
    # Configure error handling
    aws lambda put-function-event-invoke-config \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --maximum-retry-attempts 2 \
        --maximum-event-age-in-seconds 3600 \
        --dead-letter-config TargetArn="arn:aws:sqs:${AWS_REGION}:${AWS_ACCOUNT_ID}:${DLQ_NAME}" > /dev/null
    
    log INFO "Lambda function created: $LAMBDA_FUNCTION_NAME"
}

# Create CloudWatch monitoring
create_cloudwatch_monitoring() {
    log INFO "Creating CloudWatch monitoring..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create CloudWatch monitoring resources"
        return 0
    fi
    
    # Create log groups
    aws logs create-log-group \
        --log-group-name "/aws/bedrock/agentcore/$CODE_INTERPRETER_NAME" || true
    
    aws logs create-log-group \
        --log-group-name "/aws/lambda/$LAMBDA_FUNCTION_NAME" || true
    
    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "Analytics-ExecutionErrors-${RANDOM_SUFFIX}" \
        --alarm-description "Alert on analytics execution errors" \
        --metric-name ExecutionErrors \
        --namespace Analytics/CodeInterpreter \
        --statistic Sum \
        --period 300 \
        --threshold 3 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "Analytics-LambdaDuration-${RANDOM_SUFFIX}" \
        --alarm-description "Alert on high Lambda execution duration" \
        --metric-name Duration \
        --namespace AWS/Lambda \
        --statistic Average \
        --period 300 \
        --threshold 240000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME"
    
    # Create dashboard
    cat > /tmp/dashboard_config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    [ "Analytics/CodeInterpreter", "ExecutionCount" ],
                    [ ".", "ExecutionErrors" ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Analytics Execution Metrics"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "Analytics-Dashboard-${RANDOM_SUFFIX}" \
        --dashboard-body file:///tmp/dashboard_config.json
    
    log INFO "CloudWatch monitoring configured"
}

# Create API Gateway
create_api_gateway() {
    log INFO "Creating API Gateway..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create API Gateway: $API_GATEWAY_NAME"
        return 0
    fi
    
    # Create REST API
    local api_id=$(aws apigateway create-rest-api \
        --name "$API_GATEWAY_NAME" \
        --description "Interactive Data Analytics API" \
        --query 'id' --output text)
    
    # Get root resource ID
    local root_resource_id=$(aws apigateway get-resources \
        --rest-api-id "$api_id" \
        --query 'items[?path==`/`].id' --output text)
    
    # Create analytics resource
    local analytics_resource_id=$(aws apigateway create-resource \
        --rest-api-id "$api_id" \
        --parent-id "$root_resource_id" \
        --path-part analytics \
        --query 'id' --output text)
    
    # Create POST method
    aws apigateway put-method \
        --rest-api-id "$api_id" \
        --resource-id "$analytics_resource_id" \
        --http-method POST \
        --authorization-type NONE > /dev/null
    
    # Configure Lambda integration
    aws apigateway put-integration \
        --rest-api-id "$api_id" \
        --resource-id "$analytics_resource_id" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}/invocations" > /dev/null
    
    # Deploy API
    aws apigateway create-deployment \
        --rest-api-id "$api_id" \
        --stage-name prod > /dev/null
    
    # Grant API Gateway permission to invoke Lambda
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id analytics-api-permission \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${api_id}/*/*" > /dev/null
    
    export API_ENDPOINT="https://${api_id}.execute-api.${AWS_REGION}.amazonaws.com/prod/analytics"
    
    log INFO "API Gateway created: $API_ENDPOINT"
}

# Test deployment
test_deployment() {
    log INFO "Testing deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would test deployment"
        return 0
    fi
    
    # Test Lambda function
    cat > /tmp/test_event.json << EOF
{
    "query": "Calculate the total sales amount by region and identify the top-performing product"
}
EOF
    
    local response=$(aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload file:///tmp/test_event.json \
        --cli-binary-format raw-in-base64-out \
        /tmp/response.json 2>&1)
    
    if [[ $? -eq 0 ]]; then
        log INFO "Lambda function test successful"
    else
        log WARN "Lambda function test failed: $response"
    fi
}

# Save deployment information
save_deployment_info() {
    log INFO "Saving deployment information..."
    
    cat > "${SCRIPT_DIR}/deployment_info_${RANDOM_SUFFIX}.json" << EOF
{
    "deployment_id": "${RANDOM_SUFFIX}",
    "region": "${AWS_REGION}",
    "account_id": "${AWS_ACCOUNT_ID}",
    "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "resources": {
        "iam_role": "${IAM_ROLE_NAME}",
        "s3_buckets": {
            "raw_data": "${BUCKET_RAW_DATA}",
            "results": "${BUCKET_RESULTS}"
        },
        "lambda_function": "${LAMBDA_FUNCTION_NAME}",
        "code_interpreter": "${CODE_INTERPRETER_ID}",
        "sqs_dlq": "${DLQ_NAME}",
        "api_endpoint": "${API_ENDPOINT:-}"
    }
}
EOF
    
    log INFO "Deployment information saved to: deployment_info_${RANDOM_SUFFIX}.json"
}

# Main deployment function
main() {
    echo "🚀 Starting Interactive Data Analytics with Bedrock AgentCore Code Interpreter Deployment"
    echo "📋 Log file: $LOG_FILE"
    echo ""
    
    # Parse arguments
    parse_args "$@"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    
    if [[ "$DRY_RUN" != "true" ]]; then
        check_existing_resources
    fi
    
    create_iam_resources
    create_s3_buckets
    create_sqs_dlq
    create_code_interpreter
    create_lambda_function
    create_cloudwatch_monitoring
    create_api_gateway
    test_deployment
    save_deployment_info
    
    # Cleanup temporary files
    rm -f /tmp/analytics_policy.json /tmp/lambda_function.py /tmp/lambda_function.zip
    rm -f /tmp/sample_*.csv /tmp/sample_*.json /tmp/test_event.json /tmp/response.json
    rm -f /tmp/dashboard_config.json
    
    echo ""
    echo "✅ Deployment completed successfully!"
    echo ""
    echo "📊 Resource Summary:"
    echo "   • Region: $AWS_REGION"
    echo "   • Suffix: $RANDOM_SUFFIX"
    echo "   • S3 Raw Data Bucket: $BUCKET_RAW_DATA"
    echo "   • S3 Results Bucket: $BUCKET_RESULTS"
    echo "   • Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "   • Code Interpreter: $CODE_INTERPRETER_NAME"
    echo "   • API Endpoint: ${API_ENDPOINT:-Not created}"
    echo ""
    echo "🧪 To test the analytics API:"
    if [[ -n "${API_ENDPOINT:-}" ]]; then
        echo "   curl -X POST $API_ENDPOINT \\"
        echo "     -H 'Content-Type: application/json' \\"
        echo "     -d '{\"query\": \"Analyze sales trends and provide insights\"}'"
    else
        echo "   aws lambda invoke --function-name $LAMBDA_FUNCTION_NAME \\"
        echo "     --payload '{\"query\": \"Analyze sales data\"}' response.json"
    fi
    echo ""
    echo "🧹 To clean up resources, run: ./destroy.sh --suffix $RANDOM_SUFFIX"
    echo ""
    
    log INFO "Deployment completed successfully with suffix: $RANDOM_SUFFIX"
}

# Run main function with all arguments
main "$@"