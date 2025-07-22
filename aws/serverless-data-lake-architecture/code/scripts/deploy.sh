#!/bin/bash

# Advanced Serverless Data Lake Architecture Deployment Script
# This script deploys a complete serverless data lake with Lambda layers, Glue, and EventBridge
# Recipe: Implementing Advanced Serverless Data Lake Architecture with Lambda Layers, Glue, and EventBridge

set -e

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    
    # Remove any created local files
    rm -f lambda-trust-policy.json lambda-policy.json glue-trust-policy.json glue-s3-policy.json
    rm -f s3-notification-config.json test-data.json invalid-data.json
    rm -f *.zip *.py
    rm -rf lambda-layer/
    
    log_warning "Partial cleanup completed. You may need to manually remove any AWS resources that were created."
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if required commands are available
    for cmd in zip python3 pip; do
        if ! command -v $cmd &> /dev/null; then
            error_exit "$cmd is not installed. Please install $cmd."
        fi
    done
    
    # Check AWS permissions
    log "Validating AWS permissions..."
    aws iam get-user &> /dev/null || aws sts get-caller-identity &> /dev/null || error_exit "Unable to validate AWS credentials"
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "No default region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export PROJECT_NAME="advanced-serverless-datalake-${RANDOM_SUFFIX}"
    export LAMBDA_LAYER_NAME="${PROJECT_NAME}-shared-layer"
    export CUSTOM_EVENT_BUS="${PROJECT_NAME}-event-bus"
    export S3_BUCKET_RAW="${PROJECT_NAME}-raw-data"
    export S3_BUCKET_PROCESSED="${PROJECT_NAME}-processed-data"
    export S3_BUCKET_QUARANTINE="${PROJECT_NAME}-quarantine-data"
    export DYNAMODB_METADATA_TABLE="${PROJECT_NAME}-metadata"
    export GLUE_DATABASE="${PROJECT_NAME}_catalog"
    
    log_success "Environment variables configured:"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account ID: $AWS_ACCOUNT_ID"
    log "  Project Name: $PROJECT_NAME"
}

# Create S3 buckets and DynamoDB table
create_storage_resources() {
    log "Creating storage resources..."
    
    # Create S3 buckets
    aws s3 mb s3://${S3_BUCKET_RAW} --region ${AWS_REGION} || error_exit "Failed to create raw data bucket"
    aws s3 mb s3://${S3_BUCKET_PROCESSED} --region ${AWS_REGION} || error_exit "Failed to create processed data bucket"
    aws s3 mb s3://${S3_BUCKET_QUARANTINE} --region ${AWS_REGION} || error_exit "Failed to create quarantine bucket"
    
    log_success "Created S3 buckets"
    
    # Create DynamoDB table
    aws dynamodb create-table \
        --table-name ${DYNAMODB_METADATA_TABLE} \
        --attribute-definitions \
            AttributeName=ProcessId,AttributeType=S \
            AttributeName=Timestamp,AttributeType=S \
        --key-schema \
            AttributeName=ProcessId,KeyType=HASH \
            AttributeName=Timestamp,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
        || error_exit "Failed to create DynamoDB table"
    
    log_success "Created DynamoDB metadata table"
    
    # Wait for DynamoDB table to be active
    log "Waiting for DynamoDB table to become active..."
    aws dynamodb wait table-exists --table-name ${DYNAMODB_METADATA_TABLE} || error_exit "DynamoDB table creation timeout"
    log_success "DynamoDB table is active"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles and policies..."
    
    # Create Lambda trust policy
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
    
    # Create IAM role for Lambda functions
    aws iam create-role \
        --role-name ${PROJECT_NAME}-lambda-role \
        --assume-role-policy-document file://lambda-trust-policy.json \
        || error_exit "Failed to create Lambda IAM role"
    
    # Create comprehensive Lambda policy
    cat > lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:*"
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
                "arn:aws:s3:::${S3_BUCKET_RAW}/*",
                "arn:aws:s3:::${S3_BUCKET_PROCESSED}/*",
                "arn:aws:s3:::${S3_BUCKET_QUARANTINE}/*",
                "arn:aws:s3:::${S3_BUCKET_RAW}",
                "arn:aws:s3:::${S3_BUCKET_PROCESSED}",
                "arn:aws:s3:::${S3_BUCKET_QUARANTINE}"
            ]
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
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DYNAMODB_METADATA_TABLE}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "events:PutEvents"
            ],
            "Resource": "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:event-bus/${CUSTOM_EVENT_BUS}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "glue:StartJobRun",
                "glue:GetJobRun",
                "glue:StartWorkflowRun",
                "glue:GetWorkflowRun"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "xray:PutTraceSegments",
                "xray:PutTelemetryRecords",
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name ${PROJECT_NAME}-lambda-role \
        --policy-name ${PROJECT_NAME}-lambda-policy \
        --policy-document file://lambda-policy.json \
        || error_exit "Failed to attach Lambda policy"
    
    log_success "Created Lambda IAM role and policy"
    
    # Create Glue trust policy
    cat > glue-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "glue.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    aws iam create-role \
        --role-name ${PROJECT_NAME}-glue-role \
        --assume-role-policy-document file://glue-trust-policy.json \
        || error_exit "Failed to create Glue IAM role"
    
    # Attach managed policies to Glue role
    aws iam attach-role-policy \
        --role-name ${PROJECT_NAME}-glue-role \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole \
        || error_exit "Failed to attach Glue service role policy"
    
    # Create custom policy for S3 access
    cat > glue-s3-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_PROCESSED}/*",
                "arn:aws:s3:::${S3_BUCKET_PROCESSED}"
            ]
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name ${PROJECT_NAME}-glue-role \
        --policy-name S3AccessPolicy \
        --policy-document file://glue-s3-policy.json \
        || error_exit "Failed to attach Glue S3 policy"
    
    log_success "Created Glue IAM role and policies"
    
    # Wait for IAM roles to propagate
    log "Waiting for IAM roles to propagate..."
    sleep 10
}

# Create Lambda layer
create_lambda_layer() {
    log "Creating Lambda layer with shared libraries..."
    
    # Create directory structure for Lambda layer
    mkdir -p lambda-layer/python/lib/python3.9/site-packages
    
    # Create shared utilities module
    cat > lambda-layer/python/data_utils.py << 'EOF'
import json
import boto3
import uuid
import hashlib
from datetime import datetime
from typing import Dict, Any, List, Optional

class DataProcessor:
    def __init__(self):
        self.s3_client = boto3.client('s3')
        self.dynamodb = boto3.resource('dynamodb')
        self.events_client = boto3.client('events')

    def generate_process_id(self, source: str, timestamp: str) -> str:
        """Generate unique process ID"""
        data = f"{source}-{timestamp}-{uuid.uuid4()}"
        return hashlib.md5(data.encode()).hexdigest()

    def validate_json_structure(self, data: Dict[str, Any], 
                              required_fields: List[str]) -> bool:
        """Validate JSON data structure"""
        return all(field in data for field in required_fields)

    def calculate_data_quality_score(self, data: Dict[str, Any]) -> float:
        """Calculate data quality score based on completeness"""
        total_fields = len(data)
        non_null_fields = sum(1 for v in data.values() if v is not None and v != "")
        return (non_null_fields / total_fields) * 100 if total_fields > 0 else 0

    def publish_custom_event(self, event_bus: str, source: str, 
                            detail_type: str, detail: Dict[str, Any]):
        """Publish custom event to EventBridge"""
        self.events_client.put_events(
            Entries=[
                {
                    'Source': source,
                    'DetailType': detail_type,
                    'Detail': json.dumps(detail),
                    'EventBusName': event_bus
                }
            ]
        )

    def store_metadata(self, table_name: str, process_id: str, metadata: Dict[str, Any]):
        """Store processing metadata in DynamoDB"""
        table = self.dynamodb.Table(table_name)
        item = {
            'ProcessId': process_id,
            'Timestamp': datetime.utcnow().isoformat(),
            **metadata
        }
        table.put_item(Item=item)

class DataValidator:
    @staticmethod
    def is_valid_email(email: str) -> bool:
        import re
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return re.match(pattern, email) is not None

    @staticmethod
    def is_valid_phone(phone: str) -> bool:
        import re
        pattern = r'^\+?1?[2-9]\d{2}[2-9]\d{2}\d{4}$'
        return re.match(pattern, phone.replace('-', '').replace(' ', '')) is not None

    @staticmethod
    def is_valid_date_format(date_str: str, format: str = '%Y-%m-%d') -> bool:
        try:
            datetime.strptime(date_str, format)
            return True
        except ValueError:
            return False
EOF
    
    # Create requirements.txt for layer dependencies
    cat > lambda-layer/python/requirements.txt << 'EOF'
pandas==1.5.3
numpy==1.24.3
boto3==1.26.137
jsonschema==4.17.3
requests==2.31.0
EOF
    
    # Install dependencies in the layer
    log "Installing Python dependencies..."
    cd lambda-layer/python
    pip install -r requirements.txt -t lib/python3.9/site-packages/ --quiet || error_exit "Failed to install Python dependencies"
    cd ../..
    
    # Package the layer
    cd lambda-layer && zip -r ../lambda-layer.zip . > /dev/null && cd ..
    
    # Create the Lambda layer
    aws lambda publish-layer-version \
        --layer-name ${LAMBDA_LAYER_NAME} \
        --description "Shared utilities for data lake processing" \
        --zip-file fileb://lambda-layer.zip \
        --compatible-runtimes python3.9 python3.10 python3.11 \
        --compatible-architectures x86_64 arm64 \
        > /dev/null || error_exit "Failed to create Lambda layer"
    
    export LAYER_ARN=$(aws lambda list-layer-versions \
        --layer-name ${LAMBDA_LAYER_NAME} \
        --query 'LayerVersions[0].LayerVersionArn' --output text)
    
    log_success "Created Lambda layer: ${LAYER_ARN}"
}

# Create EventBridge components
create_eventbridge() {
    log "Creating EventBridge custom bus and rules..."
    
    # Create custom EventBridge bus
    aws events create-event-bus --name ${CUSTOM_EVENT_BUS} || error_exit "Failed to create EventBridge bus"
    
    # Create event rule for data ingestion events
    aws events put-rule \
        --name "${PROJECT_NAME}-data-ingestion-rule" \
        --event-pattern '{"source":["datalake.ingestion"],"detail-type":["Data Received"]}' \
        --state ENABLED \
        --event-bus-name ${CUSTOM_EVENT_BUS} \
        || error_exit "Failed to create data ingestion rule"
    
    # Create event rule for data validation events
    aws events put-rule \
        --name "${PROJECT_NAME}-data-validation-rule" \
        --event-pattern '{"source":["datalake.validation"],"detail-type":["Data Validated"]}' \
        --state ENABLED \
        --event-bus-name ${CUSTOM_EVENT_BUS} \
        || error_exit "Failed to create data validation rule"
    
    # Create event rule for data quality events
    aws events put-rule \
        --name "${PROJECT_NAME}-data-quality-rule" \
        --event-pattern '{"source":["datalake.quality"],"detail-type":["Quality Check Complete"]}' \
        --state ENABLED \
        --event-bus-name ${CUSTOM_EVENT_BUS} \
        || error_exit "Failed to create data quality rule"
    
    log_success "Created EventBridge custom bus and rules"
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create data ingestion function
    cat > data-ingestion-lambda.py << EOF
import json
import boto3
import os
from datetime import datetime
from data_utils import DataProcessor

def lambda_handler(event, context):
    processor = DataProcessor()
    
    # Extract event information
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    
    # Generate process ID
    process_id = processor.generate_process_id(bucket, datetime.utcnow().isoformat())
    
    try:
        # Download and process the file
        s3_response = processor.s3_client.get_object(Bucket=bucket, Key=key)
        file_content = s3_response['Body'].read().decode('utf-8')
        
        # Determine file type and process accordingly
        if key.endswith('.json'):
            data = json.loads(file_content)
            data_type = 'json'
        elif key.endswith('.csv'):
            # For CSV files, we'll pass the raw content
            data = {'raw_content': file_content, 'type': 'csv'}
            data_type = 'csv'
        else:
            data = {'raw_content': file_content, 'type': 'unknown'}
            data_type = 'unknown'
        
        # Store metadata
        metadata = {
            'SourceBucket': bucket,
            'SourceKey': key,
            'FileSize': len(file_content),
            'DataType': data_type,
            'Status': 'ingested',
            'ProcessingStage': 'ingestion'
        }
        
        processor.store_metadata(
            table_name=os.environ['METADATA_TABLE'],
            process_id=process_id,
            metadata=metadata
        )
        
        # Publish ingestion event
        event_detail = {
            'processId': process_id,
            'bucket': bucket,
            'key': key,
            'dataType': data_type,
            'fileSize': len(file_content)
        }
        
        processor.publish_custom_event(
            event_bus=os.environ['CUSTOM_EVENT_BUS'],
            source='datalake.ingestion',
            detail_type='Data Received',
            detail=event_detail
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'processId': process_id,
                'message': 'Data ingested successfully'
            })
        }
        
    except Exception as e:
        print(f"Error processing file: {str(e)}")
        
        # Store error metadata
        error_metadata = {
            'SourceBucket': bucket,
            'SourceKey': key,
            'Status': 'failed',
            'ProcessingStage': 'ingestion',
            'ErrorMessage': str(e)
        }
        
        processor.store_metadata(
            table_name=os.environ['METADATA_TABLE'],
            process_id=process_id,
            metadata=error_metadata
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Package and create the function
    zip data-ingestion-lambda.zip data-ingestion-lambda.py > /dev/null
    
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-data-ingestion" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role" \
        --handler data-ingestion-lambda.lambda_handler \
        --zip-file fileb://data-ingestion-lambda.zip \
        --timeout 300 \
        --memory-size 512 \
        --layers ${LAYER_ARN} \
        --environment Variables="{\
            \"METADATA_TABLE\":\"${DYNAMODB_METADATA_TABLE}\",\
            \"CUSTOM_EVENT_BUS\":\"${CUSTOM_EVENT_BUS}\",\
            \"PROCESSED_BUCKET\":\"${S3_BUCKET_PROCESSED}\"\
        }" \
        --tracing-config Mode=Active \
        > /dev/null || error_exit "Failed to create data ingestion Lambda function"
    
    log_success "Created data ingestion Lambda function"
    
    # Create data validation function
    cat > data-validation-lambda.py << EOF
import json
import boto3
import os
from data_utils import DataProcessor, DataValidator

def lambda_handler(event, context):
    processor = DataProcessor()
    validator = DataValidator()
    
    # Parse EventBridge event
    detail = event['detail']
    process_id = detail['processId']
    bucket = detail['bucket']
    key = detail['key']
    data_type = detail['dataType']
    
    try:
        # Download the file for validation
        s3_response = processor.s3_client.get_object(Bucket=bucket, Key=key)
        file_content = s3_response['Body'].read().decode('utf-8')
        
        validation_results = {
            'processId': process_id,
            'validationPassed': True,
            'validationErrors': [],
            'qualityScore': 0
        }
        
        if data_type == 'json':
            try:
                data = json.loads(file_content)
                
                # Validate required fields (example schema)
                required_fields = ['id', 'timestamp', 'data']
                if not processor.validate_json_structure(data, required_fields):
                    validation_results['validationPassed'] = False
                    validation_results['validationErrors'].append('Missing required fields')
                
                # Calculate quality score
                validation_results['qualityScore'] = processor.calculate_data_quality_score(data)
                
                # Additional field validations
                if 'email' in data and not validator.is_valid_email(data['email']):
                    validation_results['validationErrors'].append('Invalid email format')
                
                if 'phone' in data and not validator.is_valid_phone(data['phone']):
                    validation_results['validationErrors'].append('Invalid phone format')
                
            except json.JSONDecodeError:
                validation_results['validationPassed'] = False
                validation_results['validationErrors'].append('Invalid JSON format')
        
        elif data_type == 'csv':
            # Basic CSV validation
            lines = file_content.strip().split('\\n')
            if len(lines) < 2:  # Header + at least one data row
                validation_results['validationPassed'] = False
                validation_results['validationErrors'].append('CSV file must have header and data rows')
            else:
                validation_results['qualityScore'] = 85.0  # Default score for valid CSV
        
        # Determine destination based on validation
        if validation_results['validationPassed'] and validation_results['qualityScore'] >= 70:
            destination_bucket = os.environ['PROCESSED_BUCKET']
            destination_prefix = 'validated/'
            status = 'validated'
        else:
            destination_bucket = os.environ['QUARANTINE_BUCKET']
            destination_prefix = 'quarantine/'
            status = 'quarantined'
        
        # Copy file to appropriate destination
        destination_key = f"{destination_prefix}{key}"
        processor.s3_client.copy_object(
            CopySource={'Bucket': bucket, 'Key': key},
            Bucket=destination_bucket,
            Key=destination_key
        )
        
        # Update metadata
        metadata = {
            'Status': status,
            'ProcessingStage': 'validation',
            'ValidationPassed': validation_results['validationPassed'],
            'QualityScore': validation_results['qualityScore'],
            'ValidationErrors': validation_results['validationErrors'],
            'DestinationBucket': destination_bucket,
            'DestinationKey': destination_key
        }
        
        processor.store_metadata(
            table_name=os.environ['METADATA_TABLE'],
            process_id=process_id,
            metadata=metadata
        )
        
        # Publish validation event
        processor.publish_custom_event(
            event_bus=os.environ['CUSTOM_EVENT_BUS'],
            source='datalake.validation',
            detail_type='Data Validated',
            detail=validation_results
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(validation_results)
        }
        
    except Exception as e:
        print(f"Error validating data: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Package and create the validation function
    zip data-validation-lambda.zip data-validation-lambda.py > /dev/null
    
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-data-validation" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role" \
        --handler data-validation-lambda.lambda_handler \
        --zip-file fileb://data-validation-lambda.zip \
        --timeout 300 \
        --memory-size 512 \
        --layers ${LAYER_ARN} \
        --environment Variables="{\
            \"METADATA_TABLE\":\"${DYNAMODB_METADATA_TABLE}\",\
            \"CUSTOM_EVENT_BUS\":\"${CUSTOM_EVENT_BUS}\",\
            \"PROCESSED_BUCKET\":\"${S3_BUCKET_PROCESSED}\",\
            \"QUARANTINE_BUCKET\":\"${S3_BUCKET_QUARANTINE}\"\
        }" \
        --tracing-config Mode=Active \
        > /dev/null || error_exit "Failed to create data validation Lambda function"
    
    log_success "Created data validation Lambda function"
    
    # Create quality monitoring function
    cat > quality-monitoring-lambda.py << EOF
import json
import boto3
import os
from data_utils import DataProcessor
from datetime import datetime, timedelta

def lambda_handler(event, context):
    processor = DataProcessor()
    cloudwatch = boto3.client('cloudwatch')
    
    # Parse EventBridge event
    detail = event['detail']
    process_id = detail['processId']
    quality_score = detail.get('qualityScore', 0)
    validation_passed = detail.get('validationPassed', False)
    
    try:
        # Calculate quality metrics over time
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        # Query recent processing metadata
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ['METADATA_TABLE'])
        
        # Scan for recent records (in production, use GSI for better performance)
        response = table.scan(
            FilterExpression='ProcessingStage = :stage',
            ExpressionAttributeValues={':stage': 'validation'}
        )
        
        # Calculate aggregate metrics
        total_records = len(response['Items'])
        passed_records = sum(1 for item in response['Items'] 
                           if item.get('ValidationPassed', False))
        avg_quality_score = sum(float(item.get('QualityScore', 0)) 
                              for item in response['Items']) / max(total_records, 1)
        
        # Publish CloudWatch metrics
        cloudwatch.put_metric_data(
            Namespace='DataLake/Quality',
            MetricData=[
                {
                    'MetricName': 'ValidationSuccessRate',
                    'Value': (passed_records / max(total_records, 1)) * 100,
                    'Unit': 'Percent',
                    'Dimensions': [
                        {
                            'Name': 'Pipeline',
                            'Value': os.environ.get('PROJECT_NAME', 'unknown')
                        }
                    ]
                },
                {
                    'MetricName': 'AverageQualityScore',
                    'Value': avg_quality_score,
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'Pipeline',
                            'Value': os.environ.get('PROJECT_NAME', 'unknown')
                        }
                    ]
                },
                {
                    'MetricName': 'ProcessedRecords',
                    'Value': total_records,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'Pipeline',
                            'Value': os.environ.get('PROJECT_NAME', 'unknown')
                        }
                    ]
                }
            ]
        )
        
        # Store aggregated quality metadata
        quality_metadata = {
            'TotalRecords': total_records,
            'PassedRecords': passed_records,
            'SuccessRate': (passed_records / max(total_records, 1)) * 100,
            'AverageQualityScore': avg_quality_score,
            'ProcessingStage': 'quality_monitoring'
        }
        
        processor.store_metadata(
            table_name=os.environ['METADATA_TABLE'],
            process_id=f"quality-{datetime.utcnow().isoformat()}",
            metadata=quality_metadata
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Quality metrics updated',
                'metrics': quality_metadata
            })
        }
        
    except Exception as e:
        print(f"Error monitoring quality: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Package and create the quality monitoring function
    zip quality-monitoring-lambda.zip quality-monitoring-lambda.py > /dev/null
    
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-quality-monitoring" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-lambda-role" \
        --handler quality-monitoring-lambda.lambda_handler \
        --zip-file fileb://quality-monitoring-lambda.zip \
        --timeout 300 \
        --memory-size 256 \
        --layers ${LAYER_ARN} \
        --environment Variables="{\
            \"METADATA_TABLE\":\"${DYNAMODB_METADATA_TABLE}\",\
            \"PROJECT_NAME\":\"${PROJECT_NAME}\"\
        }" \
        --tracing-config Mode=Active \
        > /dev/null || error_exit "Failed to create quality monitoring Lambda function"
    
    log_success "Created quality monitoring Lambda function"
}

# Create Glue components
create_glue_components() {
    log "Creating Glue components..."
    
    # Create Glue database
    aws glue create-database \
        --database-input Name=${GLUE_DATABASE},Description="Data lake catalog database" \
        || error_exit "Failed to create Glue database"
    
    # Create Glue crawler
    aws glue create-crawler \
        --name "${PROJECT_NAME}-crawler" \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-glue-role" \
        --database-name ${GLUE_DATABASE} \
        --targets S3Targets="[{\"Path\":\"s3://${S3_BUCKET_PROCESSED}/validated/\"}]" \
        --schedule "cron(0 */6 * * ? *)" \
        || error_exit "Failed to create Glue crawler"
    
    log_success "Created Glue database and crawler"
}

# Configure event-driven integration
configure_integration() {
    log "Configuring event-driven integration..."
    
    # Add S3 event notification to trigger ingestion
    cat > s3-notification-config.json << EOF
{
    "LambdaConfigurations": [
        {
            "Id": "DataIngestionTrigger",
            "LambdaFunctionArn": "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-data-ingestion",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "prefix",
                            "Value": "input/"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
    
    # Apply S3 notification configuration
    aws s3api put-bucket-notification-configuration \
        --bucket ${S3_BUCKET_RAW} \
        --notification-configuration file://s3-notification-config.json \
        || error_exit "Failed to configure S3 notifications"
    
    # Add permission for S3 to invoke Lambda
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-data-ingestion" \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --source-arn "arn:aws:s3:::${S3_BUCKET_RAW}" \
        --statement-id s3-trigger-permission \
        || error_exit "Failed to add S3 Lambda permission"
    
    # Add EventBridge targets for validation function
    aws events put-targets \
        --rule "${PROJECT_NAME}-data-ingestion-rule" \
        --event-bus-name ${CUSTOM_EVENT_BUS} \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-data-validation" \
        || error_exit "Failed to add EventBridge target for validation"
    
    # Add permission for EventBridge to invoke validation Lambda
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-data-validation" \
        --principal events.amazonaws.com \
        --action lambda:InvokeFunction \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${CUSTOM_EVENT_BUS}/${PROJECT_NAME}-data-ingestion-rule" \
        --statement-id eventbridge-validation-permission \
        || error_exit "Failed to add EventBridge validation permission"
    
    # Add EventBridge target for quality monitoring
    aws events put-targets \
        --rule "${PROJECT_NAME}-data-validation-rule" \
        --event-bus-name ${CUSTOM_EVENT_BUS} \
        --targets "Id"="1","Arn"="arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${PROJECT_NAME}-quality-monitoring" \
        || error_exit "Failed to add EventBridge target for quality monitoring"
    
    # Add permission for EventBridge to invoke quality monitoring Lambda
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-quality-monitoring" \
        --principal events.amazonaws.com \
        --action lambda:InvokeFunction \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${CUSTOM_EVENT_BUS}/${PROJECT_NAME}-data-validation-rule" \
        --statement-id eventbridge-quality-permission \
        || error_exit "Failed to add EventBridge quality permission"
    
    log_success "Configured event-driven integration"
}

# Create test data and validate deployment
test_deployment() {
    log "Creating test data to validate deployment..."
    
    # Create test JSON data
    cat > test-data.json << 'EOF'
{
    "id": "12345",
    "timestamp": "2024-01-15T10:30:00Z",
    "data": {
        "temperature": 23.5,
        "humidity": 65.2,
        "location": "sensor-01"
    },
    "email": "test@example.com",
    "phone": "+1-555-123-4567",
    "metadata": {
        "source": "iot-device",
        "version": "1.0"
    }
}
EOF
    
    # Upload test file to trigger the pipeline
    aws s3 cp test-data.json s3://${S3_BUCKET_RAW}/input/test-data.json || error_exit "Failed to upload test data"
    
    log_success "Uploaded test data file"
    log "Waiting 30 seconds for pipeline processing..."
    sleep 30
    
    # Check if processed data exists
    if aws s3 ls s3://${S3_BUCKET_PROCESSED}/validated/ --recursive | grep -q test-data.json; then
        log_success "Test data successfully processed and validated"
    else
        log_warning "Test data processing may still be in progress or failed"
    fi
}

# Save deployment configuration
save_configuration() {
    log "Saving deployment configuration..."
    
    cat > deployment-config.json << EOF
{
    "projectName": "${PROJECT_NAME}",
    "awsRegion": "${AWS_REGION}",
    "awsAccountId": "${AWS_ACCOUNT_ID}",
    "resources": {
        "s3Buckets": {
            "raw": "${S3_BUCKET_RAW}",
            "processed": "${S3_BUCKET_PROCESSED}",
            "quarantine": "${S3_BUCKET_QUARANTINE}"
        },
        "dynamoDbTable": "${DYNAMODB_METADATA_TABLE}",
        "lambdaLayer": "${LAMBDA_LAYER_NAME}",
        "eventBus": "${CUSTOM_EVENT_BUS}",
        "glueDatabase": "${GLUE_DATABASE}",
        "iamRoles": {
            "lambda": "${PROJECT_NAME}-lambda-role",
            "glue": "${PROJECT_NAME}-glue-role"
        },
        "lambdaFunctions": {
            "ingestion": "${PROJECT_NAME}-data-ingestion",
            "validation": "${PROJECT_NAME}-data-validation",
            "qualityMonitoring": "${PROJECT_NAME}-quality-monitoring"
        }
    },
    "deploymentTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log_success "Deployment configuration saved to deployment-config.json"
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f lambda-trust-policy.json lambda-policy.json glue-trust-policy.json glue-s3-policy.json
    rm -f s3-notification-config.json test-data.json
    rm -f *.zip *.py
    rm -rf lambda-layer/
    
    log_success "Temporary files cleaned up"
}

# Display deployment summary
display_summary() {
    log_success "🎉 Advanced Serverless Data Lake Architecture deployed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project Name: ${PROJECT_NAME}"
    echo "AWS Region: ${AWS_REGION}"
    echo "AWS Account: ${AWS_ACCOUNT_ID}"
    echo ""
    echo "=== CREATED RESOURCES ==="
    echo "S3 Buckets:"
    echo "  • Raw Data: ${S3_BUCKET_RAW}"
    echo "  • Processed Data: ${S3_BUCKET_PROCESSED}"
    echo "  • Quarantine: ${S3_BUCKET_QUARANTINE}"
    echo ""
    echo "DynamoDB Table: ${DYNAMODB_METADATA_TABLE}"
    echo "Lambda Layer: ${LAMBDA_LAYER_NAME}"
    echo "EventBridge Bus: ${CUSTOM_EVENT_BUS}"
    echo "Glue Database: ${GLUE_DATABASE}"
    echo ""
    echo "Lambda Functions:"
    echo "  • Data Ingestion: ${PROJECT_NAME}-data-ingestion"
    echo "  • Data Validation: ${PROJECT_NAME}-data-validation"
    echo "  • Quality Monitoring: ${PROJECT_NAME}-quality-monitoring"
    echo ""
    echo "=== TESTING THE PIPELINE ==="
    echo "1. Upload a JSON file to: s3://${S3_BUCKET_RAW}/input/"
    echo "2. Check processed data in: s3://${S3_BUCKET_PROCESSED}/validated/"
    echo "3. Monitor pipeline metrics in CloudWatch under 'DataLake/Quality' namespace"
    echo "4. View processing metadata in DynamoDB table: ${DYNAMODB_METADATA_TABLE}"
    echo ""
    echo "=== ESTIMATED COSTS ==="
    echo "• Lambda executions: ~\$0.20 per 1M requests"
    echo "• S3 storage: ~\$0.023 per GB/month"
    echo "• DynamoDB: Pay-per-request pricing"
    echo "• EventBridge: \$1.00 per million events"
    echo "• Glue Crawler: \$0.44 per DPU-hour"
    echo ""
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo ""
    echo "Configuration saved to: deployment-config.json"
}

# Main deployment flow
main() {
    echo "🚀 Starting Advanced Serverless Data Lake Architecture Deployment"
    echo "================================================================="
    
    check_prerequisites
    setup_environment
    create_storage_resources
    create_iam_roles
    create_lambda_layer
    create_eventbridge
    create_lambda_functions
    create_glue_components
    configure_integration
    test_deployment
    save_configuration
    cleanup_temp_files
    display_summary
    
    log_success "Deployment completed successfully! 🎉"
}

# Execute main function
main "$@"