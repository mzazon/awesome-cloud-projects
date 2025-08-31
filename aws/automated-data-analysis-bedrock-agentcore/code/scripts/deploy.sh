#!/bin/bash

# Automated Data Analysis with Bedrock AgentCore Runtime - Deployment Script
# This script deploys the complete infrastructure for automated data analysis using AWS Bedrock AgentCore

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION 2.0.0" | tr " " "\n" | sort -V | head -n1) != "2.0.0" ]]; then
        error "AWS CLI version 2.0.0 or higher is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        error "zip utility is not installed. Please install zip."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region found, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    export DATA_BUCKET_NAME="data-analysis-input-${RANDOM_SUFFIX}"
    export RESULTS_BUCKET_NAME="data-analysis-results-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION_NAME="data-analysis-orchestrator-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="DataAnalysisOrchestratorRole-${RANDOM_SUFFIX}"
    export POLICY_NAME="DataAnalysisOrchestratorPolicy-${RANDOM_SUFFIX}"
    export DASHBOARD_NAME="DataAnalysisAutomation-${RANDOM_SUFFIX}"
    
    log "Environment configured:"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "  Data Bucket: ${DATA_BUCKET_NAME}"
    log "  Results Bucket: ${RESULTS_BUCKET_NAME}"
    log "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    
    # Save environment variables to file for cleanup script
    cat > .env.deployment << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
DATA_BUCKET_NAME=${DATA_BUCKET_NAME}
RESULTS_BUCKET_NAME=${RESULTS_BUCKET_NAME}
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
POLICY_NAME=${POLICY_NAME}
DASHBOARD_NAME=${DASHBOARD_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables set and saved to .env.deployment"
}

# Function to create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    # Create data bucket
    if aws s3api head-bucket --bucket "$DATA_BUCKET_NAME" 2>/dev/null; then
        warning "Data bucket $DATA_BUCKET_NAME already exists"
    else
        aws s3 mb "s3://${DATA_BUCKET_NAME}" --region "${AWS_REGION}"
        success "Created data bucket: ${DATA_BUCKET_NAME}"
    fi
    
    # Create results bucket
    if aws s3api head-bucket --bucket "$RESULTS_BUCKET_NAME" 2>/dev/null; then
        warning "Results bucket $RESULTS_BUCKET_NAME already exists"
    else
        aws s3 mb "s3://${RESULTS_BUCKET_NAME}" --region "${AWS_REGION}"
        success "Created results bucket: ${RESULTS_BUCKET_NAME}"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${DATA_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    aws s3api put-bucket-versioning \
        --bucket "${RESULTS_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "${DATA_BUCKET_NAME}" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    aws s3api put-bucket-encryption \
        --bucket "${RESULTS_BUCKET_NAME}" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    success "S3 buckets configured with versioning and encryption"
}

# Function to create IAM role and policies
create_iam_resources() {
    log "Creating IAM role and policies..."
    
    # Create trust policy for Lambda
    cat > lambda-trust-policy.json << EOF
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
    
    # Check if role exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        warning "IAM role $IAM_ROLE_NAME already exists"
    else
        # Create IAM role
        aws iam create-role \
            --role-name "${IAM_ROLE_NAME}" \
            --assume-role-policy-document file://lambda-trust-policy.json
        success "Created IAM role: ${IAM_ROLE_NAME}"
    fi
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Create custom policy for AgentCore and S3 access
    cat > custom-permissions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "bedrock-agentcore:CreateCodeInterpreter",
                "bedrock-agentcore:StartCodeInterpreterSession",
                "bedrock-agentcore:InvokeCodeInterpreter",
                "bedrock-agentcore:StopCodeInterpreterSession",
                "bedrock-agentcore:DeleteCodeInterpreter",
                "bedrock-agentcore:ListCodeInterpreters",
                "bedrock-agentcore:GetCodeInterpreter",
                "bedrock-agentcore:GetCodeInterpreterSession"
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
            "Resource": [
                "arn:aws:s3:::${DATA_BUCKET_NAME}/*",
                "arn:aws:s3:::${RESULTS_BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${DATA_BUCKET_NAME}",
                "arn:aws:s3:::${RESULTS_BUCKET_NAME}"
            ]
        }
    ]
}
EOF
    
    # Check if policy exists
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
        warning "IAM policy $POLICY_NAME already exists"
    else
        # Create and attach the custom policy
        aws iam create-policy \
            --policy-name "${POLICY_NAME}" \
            --policy-document file://custom-permissions-policy.json
        success "Created IAM policy: ${POLICY_NAME}"
    fi
    
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "${POLICY_ARN}"
    
    # Wait for IAM role propagation
    log "Waiting for IAM role propagation..."
    sleep 15
    
    success "IAM resources created and configured"
}

# Function to create Lambda function
create_lambda_function() {
    log "Creating Lambda function..."
    
    # Create the Lambda function code
    cat > data_analysis_orchestrator.py << 'EOF'
import json
import boto3
import logging
import os
import time
from urllib.parse import unquote_plus

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
bedrock_agentcore = boto3.client('bedrock-agentcore')

def lambda_handler(event, context):
    """
    Orchestrates automated data analysis using Bedrock AgentCore
    """
    try:
        # Parse S3 event
        for record in event['Records']:
            bucket_name = record['s3']['bucket']['name']
            object_key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing file: {object_key} from bucket: {bucket_name}")
            
            # Generate analysis based on file type
            file_extension = object_key.split('.')[-1].lower()
            analysis_code = generate_analysis_code(file_extension, bucket_name, object_key)
            
            # Create AgentCore session and execute analysis
            session_response = bedrock_agentcore.start_code_interpreter_session(
                codeInterpreterIdentifier='aws.codeinterpreter.v1',
                name=f'DataAnalysis-{int(time.time())}',
                sessionTimeoutSeconds=900
            )
            session_id = session_response['sessionId']
            
            logger.info(f"Started AgentCore session: {session_id}")
            
            # Execute the analysis code
            execution_response = bedrock_agentcore.invoke_code_interpreter(
                codeInterpreterIdentifier='aws.codeinterpreter.v1',
                sessionId=session_id,
                name='executeCode',
                arguments={
                    'language': 'python',
                    'code': analysis_code
                }
            )
            
            logger.info(f"Analysis execution completed for {object_key}")
            
            # Store results metadata
            results_key = f"analysis-results/{object_key.replace('.', '_')}_analysis.json"
            result_metadata = {
                'source_file': object_key,
                'session_id': session_id,
                'analysis_timestamp': context.aws_request_id,
                'execution_status': 'completed',
                'execution_response': execution_response
            }
            
            s3.put_object(
                Bucket=os.environ['RESULTS_BUCKET_NAME'],
                Key=results_key,
                Body=json.dumps(result_metadata, indent=2),
                ContentType='application/json'
            )
            
            # Clean up session
            bedrock_agentcore.stop_code_interpreter_session(
                codeInterpreterIdentifier='aws.codeinterpreter.v1',
                sessionId=session_id
            )
            
        return {
            'statusCode': 200,
            'body': json.dumps('Analysis completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def generate_analysis_code(file_type, bucket_name, object_key):
    """
    Generate appropriate analysis code based on file type
    """
    base_code = f"""
import pandas as pd
import matplotlib.pyplot as plt
import boto3
import io

# Download the file from S3
s3 = boto3.client('s3')
obj = s3.get_object(Bucket='{bucket_name}', Key='{object_key}')
"""
    
    if file_type in ['csv']:
        analysis_code = base_code + """
# Read CSV file
df = pd.read_csv(io.BytesIO(obj['Body'].read()))

# Perform comprehensive analysis
print("Dataset Overview:")
print(f"Shape: {df.shape}")
print(f"Columns: {list(df.columns)}")
print("\\nDataset Info:")
print(df.info())
print("\\nStatistical Summary:")
print(df.describe())
print("\\nMissing Values:")
print(df.isnull().sum())

# Generate basic visualizations if numeric columns exist
numeric_cols = df.select_dtypes(include=['number']).columns
if len(numeric_cols) > 0:
    plt.figure(figsize=(12, 8))
    for i, col in enumerate(numeric_cols[:4], 1):
        plt.subplot(2, 2, i)
        plt.hist(df[col].dropna(), bins=20, alpha=0.7)
        plt.title(f'Distribution of {col}')
        plt.xlabel(col)
        plt.ylabel('Frequency')
    plt.tight_layout()
    plt.savefig('/tmp/data_analysis.png', dpi=150, bbox_inches='tight')
    print("\\nVisualization saved as data_analysis.png")

print("\\nAnalysis completed successfully!")
"""
    elif file_type in ['json']:
        analysis_code = base_code + """
# Read JSON file
import json
data = json.loads(obj['Body'].read().decode('utf-8'))

# Analyze JSON structure
print("JSON Data Analysis:")
print(f"Data type: {type(data)}")
if isinstance(data, dict):
    print(f"Keys: {list(data.keys())}")
elif isinstance(data, list):
    print(f"List length: {len(data)}")
    if len(data) > 0:
        print(f"First item type: {type(data[0])}")
        if isinstance(data[0], dict):
            print(f"Sample keys: {list(data[0].keys())}")

print("\\nJSON analysis completed!")
"""
    else:
        analysis_code = base_code + """
# Generic file analysis
print(f"File size: {obj['ContentLength']} bytes")
print(f"Content type: {obj.get('ContentType', 'Unknown')}")
print("\\nGeneric file analysis completed!")
"""
    
    return analysis_code
EOF
    
    # Package the Lambda function
    if [ -f lambda-function.zip ]; then
        rm lambda-function.zip
    fi
    zip -r lambda-function.zip data_analysis_orchestrator.py
    
    # Get IAM role ARN
    IAM_ROLE_ARN=$(aws iam get-role \
        --role-name "${IAM_ROLE_NAME}" \
        --query 'Role.Arn' --output text)
    
    # Check if Lambda function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        warning "Lambda function $LAMBDA_FUNCTION_NAME already exists, updating..."
        aws lambda update-function-code \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --zip-file fileb://lambda-function.zip
        
        aws lambda update-function-configuration \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --environment Variables="{\"RESULTS_BUCKET_NAME\":\"${RESULTS_BUCKET_NAME}\"}"
    else
        # Create Lambda function
        aws lambda create-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --runtime python3.11 \
            --role "${IAM_ROLE_ARN}" \
            --handler data_analysis_orchestrator.lambda_handler \
            --zip-file fileb://lambda-function.zip \
            --timeout 300 \
            --memory-size 512 \
            --environment Variables="{\"RESULTS_BUCKET_NAME\":\"${RESULTS_BUCKET_NAME}\"}"
    fi
    
    success "Lambda function created/updated successfully"
}

# Function to configure S3 event trigger
configure_s3_trigger() {
    log "Configuring S3 event trigger..."
    
    # Add permission for S3 to invoke Lambda (idempotent)
    aws lambda add-permission \
        --function-name "${LAMBDA_FUNCTION_NAME}" \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id s3-trigger-permission \
        --source-arn "arn:aws:s3:::${DATA_BUCKET_NAME}" 2>/dev/null || true
    
    # Create S3 event notification configuration
    cat > s3-notification-config.json << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "DataAnalysisObjectCreated",
            "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "datasets/"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
    
    # Configure S3 bucket notification
    aws s3api put-bucket-notification-configuration \
        --bucket "${DATA_BUCKET_NAME}" \
        --notification-configuration file://s3-notification-config.json
    
    success "S3 event trigger configured"
}

# Function to create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    # Create CloudWatch dashboard configuration
    cat > dashboard-config.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Invocations", "FunctionName", "${LAMBDA_FUNCTION_NAME}"],
                    [".", "Duration", ".", "."],
                    [".", "Errors", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Data Analysis Lambda Metrics"
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/lambda/${LAMBDA_FUNCTION_NAME}'\\n| fields @timestamp, @message\\n| filter @message like /Processing file/\\n| sort @timestamp desc\\n| limit 20",
                "region": "${AWS_REGION}",
                "title": "Recent Analysis Activities"
            }
        }
    ]
}
EOF
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body file://dashboard-config.json
    
    success "CloudWatch dashboard created: ${DASHBOARD_NAME}"
}

# Function to create and upload sample dataset
create_sample_dataset() {
    log "Creating sample dataset for testing..."
    
    # Create sample CSV dataset
    cat > sample-dataset.csv << EOF
product_id,category,price,quantity_sold,customer_rating,sales_date
1,Electronics,299.99,45,4.5,2024-01-15
2,Books,19.99,123,4.2,2024-01-16
3,Clothing,79.99,67,4.1,2024-01-17
4,Electronics,199.99,89,4.8,2024-01-18
5,Books,24.99,156,4.0,2024-01-19
6,Home,45.99,78,4.3,2024-01-20
7,Electronics,149.99,234,4.6,2024-01-21
8,Clothing,29.99,445,3.9,2024-01-22
9,Books,34.99,67,4.4,2024-01-23
10,Electronics,89.99,123,4.2,2024-01-24
EOF
    
    # Upload dataset to trigger analysis
    aws s3 cp sample-dataset.csv "s3://${DATA_BUCKET_NAME}/datasets/"
    
    success "Sample dataset uploaded and analysis triggered"
    log "Monitor CloudWatch logs to see analysis progress:"
    log "  aws logs tail \"/aws/lambda/${LAMBDA_FUNCTION_NAME}\" --follow"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f lambda-trust-policy.json
    rm -f custom-permissions-policy.json
    rm -f s3-notification-config.json
    rm -f dashboard-config.json
    rm -f data_analysis_orchestrator.py
    rm -f lambda-function.zip
    rm -f sample-dataset.csv
    
    success "Temporary files cleaned up"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo ""
    echo "🚀 Successfully deployed Automated Data Analysis with Bedrock AgentCore!"
    echo ""
    echo "📋 Resources Created:"
    echo "  • S3 Data Bucket: ${DATA_BUCKET_NAME}"
    echo "  • S3 Results Bucket: ${RESULTS_BUCKET_NAME}"
    echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  • IAM Role: ${IAM_ROLE_NAME}"
    echo "  • CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo ""
    echo "🧪 Testing:"
    echo "  Upload files to: s3://${DATA_BUCKET_NAME}/datasets/"
    echo "  View results in: s3://${RESULTS_BUCKET_NAME}/analysis-results/"
    echo ""
    echo "📊 Monitoring:"
    echo "  CloudWatch Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=${DASHBOARD_NAME}"
    echo "  Lambda Logs: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#logsV2:log-groups/log-group/\$252Faws\$252Flambda\$252F${LAMBDA_FUNCTION_NAME}"
    echo ""
    echo "💡 Next Steps:"
    echo "  1. Upload CSV, JSON, or other data files to the datasets/ prefix"
    echo "  2. Monitor the CloudWatch dashboard for processing metrics"
    echo "  3. Check the results bucket for analysis outputs"
    echo ""
    echo "🧹 Cleanup:"
    echo "  Run ./destroy.sh to remove all resources"
    echo ""
    warning "Note: Bedrock AgentCore is in preview and may require account allowlisting"
}

# Main deployment function
main() {
    log "Starting deployment of Automated Data Analysis with Bedrock AgentCore..."
    
    check_prerequisites
    setup_environment
    create_s3_buckets
    create_iam_resources
    create_lambda_function
    configure_s3_trigger
    create_cloudwatch_dashboard
    create_sample_dataset
    cleanup_temp_files
    display_summary
    
    success "Deployment completed successfully!"
}

# Run main function
main "$@"