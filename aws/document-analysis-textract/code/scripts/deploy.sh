#!/bin/bash

# Deploy script for Document Analysis with Amazon Textract
# This script deploys the complete infrastructure for intelligent document processing
# Recipe: Implementing Document Analysis with Amazon Textract

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running in AWS CloudShell or with AWS CLI configured
check_aws_config() {
    log "Checking AWS configuration..."
    
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        error "Please run 'aws configure' or ensure you're in AWS CloudShell."
        exit 1
    fi
    
    AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        error "AWS region is not configured."
        error "Please set a default region with 'aws configure set region <region>'"
        exit 1
    fi
    
    success "AWS CLI configured for region: $AWS_REGION"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check permissions for required services
    local services=("textract" "lambda" "stepfunctions" "s3" "dynamodb" "sns" "iam")
    for service in "${services[@]}"; do
        case $service in
            textract)
                if ! aws textract list-adapters --region "$AWS_REGION" &> /dev/null; then
                    warning "Cannot verify Textract permissions. Deployment may fail if insufficient permissions."
                fi
                ;;
            lambda)
                if ! aws lambda list-functions --region "$AWS_REGION" &> /dev/null; then
                    error "Insufficient Lambda permissions. Please ensure Lambda:* permissions."
                    exit 1
                fi
                ;;
            s3)
                if ! aws s3 ls &> /dev/null; then
                    error "Insufficient S3 permissions. Please ensure S3:* permissions."
                    exit 1
                fi
                ;;
            iam)
                if ! aws iam list-roles &> /dev/null; then
                    error "Insufficient IAM permissions. Please ensure IAM:* permissions."
                    exit 1
                fi
                ;;
        esac
    done
    
    success "Prerequisites check completed"
}

# Generate unique resource names
generate_resource_names() {
    log "Generating unique resource names..."
    
    # Generate random suffix for unique naming
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export PROJECT_NAME="textract-analysis-${RANDOM_SUFFIX}"
    export INPUT_BUCKET="${PROJECT_NAME}-input"
    export OUTPUT_BUCKET="${PROJECT_NAME}-output"
    export METADATA_TABLE="${PROJECT_NAME}-metadata"
    export SNS_TOPIC="${PROJECT_NAME}-notifications"
    
    log "Project name: $PROJECT_NAME"
    log "Input bucket: $INPUT_BUCKET"
    log "Output bucket: $OUTPUT_BUCKET"
    log "DynamoDB table: $METADATA_TABLE"
    log "SNS topic: $SNS_TOPIC"
}

# Create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets..."
    
    # Create input bucket
    if aws s3 ls "s3://$INPUT_BUCKET" 2>&1 | grep -q 'NoSuchBucket'; then
        aws s3 mb "s3://$INPUT_BUCKET" --region "$AWS_REGION"
        success "Created input bucket: $INPUT_BUCKET"
    else
        warning "Input bucket $INPUT_BUCKET already exists"
    fi
    
    # Create output bucket
    if aws s3 ls "s3://$OUTPUT_BUCKET" 2>&1 | grep -q 'NoSuchBucket'; then
        aws s3 mb "s3://$OUTPUT_BUCKET" --region "$AWS_REGION"
        success "Created output bucket: $OUTPUT_BUCKET"
    else
        warning "Output bucket $OUTPUT_BUCKET already exists"
    fi
    
    # Enable versioning on buckets
    aws s3api put-bucket-versioning \
        --bucket "$INPUT_BUCKET" \
        --versioning-configuration Status=Enabled
    
    aws s3api put-bucket-versioning \
        --bucket "$OUTPUT_BUCKET" \
        --versioning-configuration Status=Enabled
    
    success "S3 buckets configured with versioning"
}

# Create DynamoDB table
create_dynamodb_table() {
    log "Creating DynamoDB table..."
    
    if aws dynamodb describe-table --table-name "$METADATA_TABLE" --region "$AWS_REGION" &> /dev/null; then
        warning "DynamoDB table $METADATA_TABLE already exists"
        return 0
    fi
    
    aws dynamodb create-table \
        --table-name "$METADATA_TABLE" \
        --attribute-definitions \
            AttributeName=documentId,AttributeType=S \
        --key-schema \
            AttributeName=documentId,KeyType=HASH \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region "$AWS_REGION"
    
    log "Waiting for DynamoDB table to be active..."
    aws dynamodb wait table-exists --table-name "$METADATA_TABLE" --region "$AWS_REGION"
    
    success "DynamoDB table created: $METADATA_TABLE"
}

# Create SNS topic
create_sns_topic() {
    log "Creating SNS topic..."
    
    export SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC" \
        --query TopicArn --output text)
    
    success "SNS topic created: $SNS_TOPIC_ARN"
}

# Create IAM role
create_iam_role() {
    log "Creating IAM role for Lambda and Step Functions..."
    
    # Check if role already exists
    if aws iam get-role --role-name "${PROJECT_NAME}-execution-role" &> /dev/null; then
        warning "IAM role ${PROJECT_NAME}-execution-role already exists"
        export EXECUTION_ROLE_ARN=$(aws iam get-role \
            --role-name "${PROJECT_NAME}-execution-role" \
            --query Role.Arn --output text)
        return 0
    fi
    
    # Create trust policy
    cat > /tmp/textract-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": ["lambda.amazonaws.com", "states.amazonaws.com"]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role
    aws iam create-role \
        --role-name "${PROJECT_NAME}-execution-role" \
        --assume-role-policy-document file:///tmp/textract-trust-policy.json
    
    # Attach necessary policies
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
        "arn:aws:iam::aws:policy/AmazonTextractFullAccess"
        "arn:aws:iam::aws:policy/AmazonS3FullAccess"
        "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
        "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
    )
    
    for policy in "${policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "${PROJECT_NAME}-execution-role" \
            --policy-arn "$policy"
    done
    
    # Wait for role to be available
    log "Waiting for IAM role to be available..."
    sleep 10
    
    export EXECUTION_ROLE_ARN=$(aws iam get-role \
        --role-name "${PROJECT_NAME}-execution-role" \
        --query Role.Arn --output text)
    
    success "IAM role created: $EXECUTION_ROLE_ARN"
}

# Create Lambda functions
create_lambda_functions() {
    log "Creating Lambda functions..."
    
    # Create temporary directory for Lambda code
    mkdir -p /tmp/lambda-packages
    
    # Create document classifier function
    cat > /tmp/lambda-packages/document-classifier.py << 'EOF'
import json
import boto3
import os
from urllib.parse import unquote_plus

s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Parse S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        # Get object metadata
        response = s3.head_object(Bucket=bucket, Key=key)
        file_size = response['ContentLength']
        
        # Determine processing type based on file size
        processing_type = 'sync' if file_size < 5 * 1024 * 1024 else 'async'
        
        # Determine document type based on filename
        doc_type = 'invoice' if 'invoice' in key.lower() else 'form' if 'form' in key.lower() else 'general'
        
        return {
            'statusCode': 200,
            'body': {
                'bucket': bucket,
                'key': key,
                'processingType': processing_type,
                'documentType': doc_type,
                'fileSize': file_size
            }
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Package and deploy classifier function
    cd /tmp/lambda-packages
    zip document-classifier.zip document-classifier.py
    
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-document-classifier" \
        --runtime python3.9 \
        --role "$EXECUTION_ROLE_ARN" \
        --handler document-classifier.lambda_handler \
        --zip-file fileb://document-classifier.zip \
        --timeout 30 \
        --environment Variables="{OUTPUT_BUCKET=${OUTPUT_BUCKET},METADATA_TABLE=${METADATA_TABLE}}" \
        --region "$AWS_REGION"
    
    export CLASSIFIER_FUNCTION_ARN=$(aws lambda get-function \
        --function-name "${PROJECT_NAME}-document-classifier" \
        --query Configuration.FunctionArn --output text)
    
    success "Document classifier Lambda created"
    
    # Create Textract processor function
    cat > /tmp/lambda-packages/textract-processor.py << 'EOF'
import json
import boto3
import uuid
import os
from datetime import datetime

textract = boto3.client('textract')
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        # Get input parameters
        bucket = event['bucket']
        key = event['key']
        processing_type = event['processingType']
        document_type = event['documentType']
        
        document_id = str(uuid.uuid4())
        
        # Process document based on type
        if processing_type == 'sync':
            result = process_sync_document(bucket, key, document_type)
        else:
            result = process_async_document(bucket, key, document_type)
        
        # Store metadata in DynamoDB
        store_metadata(document_id, bucket, key, document_type, result)
        
        # Send notification
        send_notification(document_id, document_type, result.get('status', 'completed'))
        
        return {
            'statusCode': 200,
            'body': {
                'documentId': document_id,
                'processingType': processing_type,
                'result': result
            }
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def process_sync_document(bucket, key, document_type):
    """Process single-page document synchronously"""
    try:
        features = ['TABLES', 'FORMS'] if document_type in ['invoice', 'form'] else ['TABLES']
        
        response = textract.analyze_document(
            Document={'S3Object': {'Bucket': bucket, 'Name': key}},
            FeatureTypes=features
        )
        
        # Extract and structure data
        extracted_data = extract_structured_data(response)
        
        # Save results to S3
        output_key = f"results/{key.split('/')[-1]}-analysis.json"
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=json.dumps(extracted_data, indent=2),
            ContentType='application/json'
        )
        
        return {
            'status': 'completed',
            'outputLocation': f"s3://{os.environ['OUTPUT_BUCKET']}/{output_key}",
            'extractedData': extracted_data
        }
    except Exception as e:
        print(f"Sync processing error: {str(e)}")
        raise

def process_async_document(bucket, key, document_type):
    """Start asynchronous document processing"""
    try:
        features = ['TABLES', 'FORMS'] if document_type in ['invoice', 'form'] else ['TABLES']
        
        response = textract.start_document_analysis(
            DocumentLocation={'S3Object': {'Bucket': bucket, 'Name': key}},
            FeatureTypes=features,
            NotificationChannel={
                'SNSTopicArn': os.environ['SNS_TOPIC_ARN'],
                'RoleArn': os.environ['EXECUTION_ROLE_ARN']
            }
        )
        
        return {
            'status': 'in_progress',
            'jobId': response['JobId']
        }
    except Exception as e:
        print(f"Async processing error: {str(e)}")
        raise

def extract_structured_data(response):
    """Extract structured data from Textract response"""
    blocks = response['Blocks']
    
    # Extract text lines
    lines = []
    tables = []
    forms = []
    
    for block in blocks:
        if block['BlockType'] == 'LINE':
            lines.append({
                'text': block.get('Text', ''),
                'confidence': block.get('Confidence', 0)
            })
        elif block['BlockType'] == 'TABLE':
            tables.append({
                'id': block['Id'],
                'confidence': block.get('Confidence', 0)
            })
        elif block['BlockType'] == 'KEY_VALUE_SET':
            forms.append({
                'id': block['Id'],
                'confidence': block.get('Confidence', 0)
            })
    
    return {
        'text_lines': lines,
        'tables': tables,
        'forms': forms,
        'document_metadata': response.get('DocumentMetadata', {})
    }

def store_metadata(document_id, bucket, key, document_type, result):
    """Store document metadata in DynamoDB"""
    table = dynamodb.Table(os.environ['METADATA_TABLE'])
    
    table.put_item(
        Item={
            'documentId': document_id,
            'bucket': bucket,
            'key': key,
            'documentType': document_type,
            'processingStatus': result.get('status', 'completed'),
            'jobId': result.get('jobId'),
            'outputLocation': result.get('outputLocation'),
            'timestamp': datetime.utcnow().isoformat()
        }
    )

def send_notification(document_id, document_type, status):
    """Send processing notification"""
    message = {
        'documentId': document_id,
        'documentType': document_type,
        'status': status,
        'timestamp': datetime.utcnow().isoformat()
    }
    
    sns.publish(
        TopicArn=os.environ['SNS_TOPIC_ARN'],
        Message=json.dumps(message),
        Subject=f'Document Processing {status.title()}'
    )
EOF
    
    # Package and deploy processor function
    zip textract-processor.zip textract-processor.py
    
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-textract-processor" \
        --runtime python3.9 \
        --role "$EXECUTION_ROLE_ARN" \
        --handler textract-processor.lambda_handler \
        --zip-file fileb://textract-processor.zip \
        --timeout 300 \
        --environment Variables="{OUTPUT_BUCKET=${OUTPUT_BUCKET},METADATA_TABLE=${METADATA_TABLE},SNS_TOPIC_ARN=${SNS_TOPIC_ARN},EXECUTION_ROLE_ARN=${EXECUTION_ROLE_ARN}}" \
        --region "$AWS_REGION"
    
    export PROCESSOR_FUNCTION_ARN=$(aws lambda get-function \
        --function-name "${PROJECT_NAME}-textract-processor" \
        --query Configuration.FunctionArn --output text)
    
    success "Textract processor Lambda created"
    
    # Create async results processor function
    cat > /tmp/lambda-packages/async-results-processor.py << 'EOF'
import json
import boto3
import os
from datetime import datetime

textract = boto3.client('textract')
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse SNS message
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        job_id = sns_message['JobId']
        status = sns_message['Status']
        
        if status == 'SUCCEEDED':
            # Get results from Textract
            response = textract.get_document_analysis(JobId=job_id)
            
            # Process results
            extracted_data = extract_structured_data(response)
            
            # Save to S3
            output_key = f"async-results/{job_id}-analysis.json"
            s3.put_object(
                Bucket=os.environ['OUTPUT_BUCKET'],
                Key=output_key,
                Body=json.dumps(extracted_data, indent=2),
                ContentType='application/json'
            )
            
            # Update DynamoDB
            update_document_metadata(job_id, 'completed', output_key)
            
            print(f"Successfully processed job {job_id}")
        else:
            # Update DynamoDB with failed status
            update_document_metadata(job_id, 'failed', None)
            print(f"Job {job_id} failed")
            
        return {'statusCode': 200}
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500}

def extract_structured_data(response):
    """Extract structured data from Textract response"""
    blocks = response['Blocks']
    
    lines = []
    tables = []
    forms = []
    
    for block in blocks:
        if block['BlockType'] == 'LINE':
            lines.append({
                'text': block.get('Text', ''),
                'confidence': block.get('Confidence', 0)
            })
        elif block['BlockType'] == 'TABLE':
            tables.append({
                'id': block['Id'],
                'confidence': block.get('Confidence', 0)
            })
        elif block['BlockType'] == 'KEY_VALUE_SET':
            forms.append({
                'id': block['Id'],
                'confidence': block.get('Confidence', 0)
            })
    
    return {
        'text_lines': lines,
        'tables': tables,
        'forms': forms,
        'document_metadata': response.get('DocumentMetadata', {})
    }

def update_document_metadata(job_id, status, output_location):
    """Update document metadata in DynamoDB"""
    table = dynamodb.Table(os.environ['METADATA_TABLE'])
    
    # Find document by job ID
    response = table.scan(
        FilterExpression='jobId = :jid',
        ExpressionAttributeValues={':jid': job_id}
    )
    
    if response['Items']:
        document_id = response['Items'][0]['documentId']
        
        table.update_item(
            Key={'documentId': document_id},
            UpdateExpression='SET processingStatus = :status, outputLocation = :location, completedAt = :timestamp',
            ExpressionAttributeValues={
                ':status': status,
                ':location': output_location,
                ':timestamp': datetime.utcnow().isoformat()
            }
        )
EOF
    
    # Package and deploy async results processor
    zip async-results-processor.zip async-results-processor.py
    
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-async-results-processor" \
        --runtime python3.9 \
        --role "$EXECUTION_ROLE_ARN" \
        --handler async-results-processor.lambda_handler \
        --zip-file fileb://async-results-processor.zip \
        --timeout 300 \
        --environment Variables="{OUTPUT_BUCKET=${OUTPUT_BUCKET},METADATA_TABLE=${METADATA_TABLE}}" \
        --region "$AWS_REGION"
    
    success "Async results processor Lambda created"
    
    # Create document query function
    cat > /tmp/lambda-packages/document-query.py << 'EOF'
import json
import boto3
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Get query parameters
        document_id = event.get('documentId')
        document_type = event.get('documentType')
        
        table = dynamodb.Table(os.environ['METADATA_TABLE'])
        
        if document_id:
            # Query specific document
            response = table.get_item(Key={'documentId': document_id})
            if 'Item' in response:
                return {
                    'statusCode': 200,
                    'body': json.dumps(response['Item'], default=str)
                }
            else:
                return {
                    'statusCode': 404,
                    'body': json.dumps({'error': 'Document not found'})
                }
        
        elif document_type:
            # Query by document type
            response = table.scan(
                FilterExpression='documentType = :dt',
                ExpressionAttributeValues={':dt': document_type}
            )
            return {
                'statusCode': 200,
                'body': json.dumps(response['Items'], default=str)
            }
        
        else:
            # Return all documents
            response = table.scan()
            return {
                'statusCode': 200,
                'body': json.dumps(response['Items'], default=str)
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Package and deploy query function
    zip document-query.zip document-query.py
    
    aws lambda create-function \
        --function-name "${PROJECT_NAME}-document-query" \
        --runtime python3.9 \
        --role "$EXECUTION_ROLE_ARN" \
        --handler document-query.lambda_handler \
        --zip-file fileb://document-query.zip \
        --timeout 30 \
        --environment Variables="{METADATA_TABLE=${METADATA_TABLE}}" \
        --region "$AWS_REGION"
    
    success "Document query Lambda created"
}

# Create Step Functions state machine
create_step_functions() {
    log "Creating Step Functions state machine..."
    
    # Create state machine definition
    cat > /tmp/textract-workflow.json << EOF
{
  "Comment": "Document Analysis Workflow with Amazon Textract",
  "StartAt": "ClassifyDocument",
  "States": {
    "ClassifyDocument": {
      "Type": "Task",
      "Resource": "${CLASSIFIER_FUNCTION_ARN}",
      "Next": "ProcessDocument"
    },
    "ProcessDocument": {
      "Type": "Task",
      "Resource": "${PROCESSOR_FUNCTION_ARN}",
      "Next": "CheckProcessingType"
    },
    "CheckProcessingType": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.body.processingType",
          "StringEquals": "async",
          "Next": "WaitForAsyncCompletion"
        }
      ],
      "Default": "ProcessingComplete"
    },
    "WaitForAsyncCompletion": {
      "Type": "Wait",
      "Seconds": 30,
      "Next": "CheckAsyncStatus"
    },
    "CheckAsyncStatus": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:textract:getDocumentAnalysis",
      "Parameters": {
        "JobId.$": "$.body.result.jobId"
      },
      "Next": "IsAsyncComplete"
    },
    "IsAsyncComplete": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.JobStatus",
          "StringEquals": "SUCCEEDED",
          "Next": "ProcessingComplete"
        },
        {
          "Variable": "$.JobStatus",
          "StringEquals": "FAILED",
          "Next": "ProcessingFailed"
        }
      ],
      "Default": "WaitForAsyncCompletion"
    },
    "ProcessingComplete": {
      "Type": "Pass",
      "Result": "Document processing completed successfully",
      "End": true
    },
    "ProcessingFailed": {
      "Type": "Fail",
      "Error": "DocumentProcessingFailed",
      "Cause": "Textract processing failed"
    }
  }
}
EOF
    
    # Create state machine
    aws stepfunctions create-state-machine \
        --name "${PROJECT_NAME}-workflow" \
        --definition file:///tmp/textract-workflow.json \
        --role-arn "$EXECUTION_ROLE_ARN" \
        --region "$AWS_REGION"
    
    export STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?name=='${PROJECT_NAME}-workflow'].stateMachineArn" \
        --output text)
    
    success "Step Functions state machine created: $STATE_MACHINE_ARN"
}

# Configure S3 event triggers
configure_s3_events() {
    log "Configuring S3 event triggers..."
    
    # Add permission for S3 to invoke Lambda
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-document-classifier" \
        --principal s3.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id s3-trigger-permission \
        --source-arn "arn:aws:s3:::${INPUT_BUCKET}" \
        --region "$AWS_REGION"
    
    # Create S3 notification configuration
    cat > /tmp/s3-notification.json << EOF
{
  "LambdaConfigurations": [
    {
      "Id": "DocumentUploadTrigger",
      "LambdaFunctionArn": "${CLASSIFIER_FUNCTION_ARN}",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "prefix",
              "Value": "documents/"
            }
          ]
        }
      }
    }
  ]
}
EOF
    
    # Configure bucket notification
    aws s3api put-bucket-notification-configuration \
        --bucket "$INPUT_BUCKET" \
        --notification-configuration file:///tmp/s3-notification.json
    
    success "S3 event triggers configured"
}

# Configure SNS subscriptions
configure_sns_subscriptions() {
    log "Configuring SNS subscriptions..."
    
    # Subscribe async results processor to SNS topic
    ASYNC_FUNCTION_ARN=$(aws lambda get-function \
        --function-name "${PROJECT_NAME}-async-results-processor" \
        --query Configuration.FunctionArn --output text)
    
    aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol lambda \
        --notification-endpoint "$ASYNC_FUNCTION_ARN"
    
    # Add permission for SNS to invoke Lambda
    aws lambda add-permission \
        --function-name "${PROJECT_NAME}-async-results-processor" \
        --principal sns.amazonaws.com \
        --action lambda:InvokeFunction \
        --statement-id sns-trigger-permission \
        --source-arn "$SNS_TOPIC_ARN" \
        --region "$AWS_REGION"
    
    success "SNS subscriptions configured"
}

# Create sample test document
create_sample_document() {
    log "Creating sample test document..."
    
    mkdir -p /tmp/sample-documents
    
    cat > /tmp/sample-documents/sample-invoice.txt << 'EOF'
INVOICE

Invoice Number: INV-2024-001
Date: January 15, 2024

Bill To:
John Doe
123 Main Street
Anytown, ST 12345

Item                    Quantity    Price    Total
Website Development         1      $5000    $5000
Hosting Services           12       $100    $1200

Subtotal:                                   $6200
Tax (8%):                                    $496
Total:                                      $6696
EOF
    
    # Upload sample document
    aws s3 cp /tmp/sample-documents/sample-invoice.txt \
        "s3://$INPUT_BUCKET/documents/sample-invoice.txt"
    
    success "Sample document uploaded for testing"
}

# Save deployment configuration
save_deployment_config() {
    log "Saving deployment configuration..."
    
    cat > /tmp/textract-deployment-config.json << EOF
{
  "deploymentId": "$PROJECT_NAME",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "$AWS_REGION",
  "accountId": "$AWS_ACCOUNT_ID",
  "resources": {
    "inputBucket": "$INPUT_BUCKET",
    "outputBucket": "$OUTPUT_BUCKET",
    "dynamodbTable": "$METADATA_TABLE",
    "snsTopicArn": "$SNS_TOPIC_ARN",
    "executionRoleArn": "$EXECUTION_ROLE_ARN",
    "classifierFunctionArn": "$CLASSIFIER_FUNCTION_ARN",
    "processorFunctionArn": "$PROCESSOR_FUNCTION_ARN",
    "stateMachineArn": "$STATE_MACHINE_ARN"
  }
}
EOF
    
    # Store config in output bucket
    aws s3 cp /tmp/textract-deployment-config.json \
        "s3://$OUTPUT_BUCKET/deployment-config.json"
    
    success "Deployment configuration saved to S3"
}

# Display deployment summary
display_summary() {
    echo ""
    echo "========================================="
    echo "   DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "========================================="
    echo ""
    echo "Project Name: $PROJECT_NAME"
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account: $AWS_ACCOUNT_ID"
    echo ""
    echo "Resources Created:"
    echo "• Input Bucket: $INPUT_BUCKET"
    echo "• Output Bucket: $OUTPUT_BUCKET"
    echo "• DynamoDB Table: $METADATA_TABLE"
    echo "• SNS Topic: $SNS_TOPIC"
    echo "• IAM Role: ${PROJECT_NAME}-execution-role"
    echo "• Lambda Functions: 4 functions created"
    echo "• Step Functions: ${PROJECT_NAME}-workflow"
    echo ""
    echo "Next Steps:"
    echo "1. Upload documents to: s3://$INPUT_BUCKET/documents/"
    echo "2. Monitor processing in DynamoDB table: $METADATA_TABLE"
    echo "3. View results in: s3://$OUTPUT_BUCKET/"
    echo ""
    echo "Testing:"
    echo "Upload a document: aws s3 cp your-document.pdf s3://$INPUT_BUCKET/documents/"
    echo "Check results: aws dynamodb scan --table-name $METADATA_TABLE"
    echo ""
    echo "Clean up: Run ./destroy.sh when finished"
    echo "========================================="
}

# Cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -rf /tmp/lambda-packages
    rm -f /tmp/textract-*.json
    rm -f /tmp/s3-notification.json
    rm -rf /tmp/sample-documents
}

# Main execution
main() {
    echo "======================================"
    echo "  Document Analysis Textract Deploy"
    echo "======================================"
    echo ""
    
    check_aws_config
    check_prerequisites
    generate_resource_names
    create_s3_buckets
    create_dynamodb_table
    create_sns_topic
    create_iam_role
    create_lambda_functions
    create_step_functions
    configure_s3_events
    configure_sns_subscriptions
    create_sample_document
    save_deployment_config
    cleanup_temp_files
    display_summary
}

# Error handling
trap 'error "Deployment failed. Check the logs above for details."; exit 1' ERR

# Run main function
main "$@"